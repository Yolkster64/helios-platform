using System.Text;
using HELIOS.AIHub.Abstractions;
using HELIOS.AIHub.Configuration;
using HELIOS.AIHub.Learning;
using HELIOS.AIHub.Native;
using HELIOS.AIHub.Providers;
using HELIOS.AIHub.Resilience;
using HELIOS.AIHub.Routing;
using HELIOS.AIHub.Domain;

namespace HELIOS.AIHub;

/// <summary>
/// Facade over every configured provider: direct ask, strength-based routing with
/// circuit-broken fallback, parallel comparison, and status.
/// </summary>
public sealed class AIHubService
{
    private readonly Dictionary<string, IChatProviderAgent> _byProvider;
    private readonly AgentRouter _router;
    private readonly TaskTypeRoutingStrategy _strategy;
    private readonly FallbackChain _fallback = new();
    private readonly AIHubOptions _options;
    private readonly ILearningStore _learning;
    private readonly NeuralRoutingLearner _neuralLearner = new();
    private readonly ModelCatalog? _catalog;

    public AIHubService(
        AIHubOptions options, ISecretResolver? secrets = null,
        ILearningStore? learning = null, ModelCatalog? catalog = null)
    {
        _options = options;
        _learning = learning ?? CreateLearningStore(options.Learning);
        _catalog = catalog ?? ModelCatalog.TryLoad();
        _strategy = new TaskTypeRoutingStrategy(options.Routing);
        _router = new AgentRouter(_strategy);

        var agents = ProviderFactory.CreateAll(options, secrets ?? new SecretResolver());
        _byProvider = new Dictionary<string, IChatProviderAgent>(StringComparer.OrdinalIgnoreCase);
        foreach (var agent in agents)
        {
            _byProvider[agent.Provider] = agent;
            _router.RegisterAgent(agent, new[] { agent.Provider, "chat" });
        }
    }

    /// <summary>Loads config/aihub.json (walking up from the current directory) and builds the hub.</summary>
    public static AIHubService CreateFromConfig(string? configPath = null)
    {
        var path = configPath
                   ?? AIHubOptions.FindConfigFile()
                   ?? throw new FileNotFoundException(
                       "config/aihub.json not found in this directory or any parent. Run from the repo, or pass --config.");
        return new AIHubService(AIHubOptions.Load(path));
    }

    public IRoutingTableView RoutingTable => new RoutingTableView(_options.Routing);

    /// <summary>Where routing outcomes are recorded; useful for reporting and tests.</summary>
    public ILearningStore Learning => _learning;

    private static ILearningStore CreateLearningStore(LearningOptions options)
    {
        if (!options.Enabled)
        {
            return new NullLearningStore();
        }

        var endpoint = Environment.GetEnvironmentVariable(options.TableEndpointEnv);
        var local = new LocalJsonlLearningStore(options.LocalPath);

        return options.Mode.ToLowerInvariant() switch
        {
            "azure" when !string.IsNullOrWhiteSpace(endpoint) =>
                new AzureTableLearningStore(new Uri(endpoint)),
            "hybrid" when !string.IsNullOrWhiteSpace(endpoint) =>
                new HybridLearningStore(local, new AzureTableLearningStore(new Uri(endpoint))),
            // Azure requested but unconfigured degrades to local rather than failing —
            // the same "unconfigured is a state" rule the providers follow.
            _ => local,
        };
    }

    /// <summary>
    /// Best provider for a task under a cost/latency/quality/balanced preference, using
    /// the static model catalog (config/model-catalog.json). Null when the catalog has no
    /// opinion for this task type, or wasn't found — callers should fall back to
    /// <see cref="RouteAsync"/>'s configured chain.
    /// </summary>
    public string? SelectOptimalProvider(string taskType, string preference = "balanced") =>
        _catalog?.SelectProvider(taskType, preference) is { } provider && _byProvider.ContainsKey(provider)
            ? provider
            : null;

    /// <summary>Ask one provider directly (or the default chain when provider is null).</summary>
    public Task<ChatResult> AskAsync(
        string prompt, string? provider = null, string? model = null, string? system = null,
        CancellationToken cancellationToken = default)
    {
        if (provider is null)
        {
            return RouteAsync(taskType: null, prompt, system, cancellationToken);
        }

        if (!_byProvider.TryGetValue(provider, out var agent))
        {
            return Task.FromResult(new ChatResult(false, null, provider, model ?? "", TimeSpan.Zero,
                Error: $"Unknown provider '{provider}'. Known: {string.Join(", ", _byProvider.Keys.OrderBy(k => k))}."));
        }

        return agent.ChatAsync(new ChatRequest(prompt, System: system, Model: model), cancellationToken);
    }

    /// <summary>Route by task type through the configured chain with circuit-broken fallback.</summary>
    public async Task<ChatResult> RouteAsync(
        string? taskType, string prompt, string? system = null, CancellationToken cancellationToken = default)
    {
        var chain = _strategy.GetChain(taskType).Where(name => _byProvider.ContainsKey(name)).ToList();
        if (chain.Count == 0)
        {
            return new ChatResult(false, null, "none", "", TimeSpan.Zero,
                Error: taskType is null
                    ? "No providers in routing.defaultChain are registered."
                    : $"No registered providers for task type '{taskType}' (chain empty). Check config/aihub.json.");
        }

        chain = FilterChainByContext(chain, prompt);
        chain = await ApplyLearningAsync(taskType, chain, cancellationToken).ConfigureAwait(false);

        var request = new ChatRequest(prompt, System: system, TaskType: taskType);
        try
        {
            return await _fallback.ExecuteAsync(
                chain,
                async providerName =>
                {
                    var result = await _byProvider[providerName].ChatAsync(request, cancellationToken)
                        .ConfigureAwait(false);
                    await RecordOutcomeAsync(taskType, result, cancellationToken).ConfigureAwait(false);
                    return result;
                },
                isSuccess: static result => result.Success,
                cancellationToken).ConfigureAwait(false);
        }
        catch (FallbackChainExhaustedException ex)
        {
            return new ChatResult(false, null, string.Join("→", chain), "", TimeSpan.Zero, Error: ex.Message);
        }
    }

    /// <summary>
    /// Reorder the configured chain from recorded outcomes. The neural learner (native
    /// MLP + F# fusion) goes first because it can express signal interactions the linear
    /// policy averages away; whenever it abstains — no native library, thin history —
    /// the F# linear policy answers instead. Any failure here falls back to the
    /// configured order — learning must never be able to break routing, only improve it.
    /// </summary>
    private async Task<List<string>> ApplyLearningAsync(
        string? taskType, List<string> configuredChain, CancellationToken cancellationToken)
    {
        if (!_options.Learning.Enabled || !_options.Learning.AdaptiveRouting || taskType is null)
        {
            return configuredChain;
        }

        try
        {
            var history = await _learning
                .GetRecentAsync(taskType, _options.Learning.HistoryWindow, cancellationToken)
                .ConfigureAwait(false);
            if (history.Count == 0)
            {
                return configuredChain;
            }

            var reordered = _neuralLearner.Reorder(taskType, configuredChain, history)
                ?? RoutingPolicyInterop.ReorderChain(
                    taskType,
                    configuredChain.ToArray(),
                    history.Select(h => h.Provider).ToArray(),
                    history.Select(h => h.Success).ToArray(),
                    history.Select(h => h.LatencyMs).ToArray(),
                    history.Select(h => h.CostUsd).ToArray(),
                    history.Select(h => h.Quality ?? double.NaN).ToArray());

            return reordered.Where(_byProvider.ContainsKey).ToList() is { Count: > 0 } valid
                ? valid
                : configuredChain;
        }
        catch (IOException)
        {
            return configuredChain;
        }
        catch (UnauthorizedAccessException)
        {
            return configuredChain;
        }
    }

    /// <summary>Tokens reserved for the completion when checking whether a prompt fits a window.</summary>
    private const int DefaultReservedOutputTokens = 4096;

    /// <summary>
    /// Drop chain entries whose provider/model context window can't fit the prompt, via the
    /// F# ContextBudget module. A 200k-token prompt routed to a 128k-window model wastes a
    /// round-trip that fallback would otherwise have to absorb. Mirrors ApplyLearningAsync's
    /// philosophy: this can only narrow the chain toward providers that fit, never break
    /// routing — providers with no known window are always treated as fitting, and if every
    /// window resolves too small ContextBudget.filterFits hands back the original chain.
    /// </summary>
    private List<string> FilterChainByContext(List<string> chain, string prompt)
    {
        if (_catalog is null || chain.Count == 0)
        {
            return chain;
        }

        var promptTokens = EstimateTokenCount(prompt);
        if (promptTokens <= 0)
        {
            return chain;
        }

        var providerNames = new List<string>();
        var maxContextTokens = new List<int>();
        var reservedOutputTokens = new List<int>();
        foreach (var name in chain)
        {
            var window = ResolveContextWindow(name);
            if (window is not { } w)
            {
                continue;
            }
            providerNames.Add(name);
            maxContextTokens.Add(w.MaxContextTokens);
            reservedOutputTokens.Add(w.ReservedOutputTokens);
        }

        if (providerNames.Count == 0)
        {
            return chain;
        }

        try
        {
            return ContextBudgetInterop.FilterFits(
                promptTokens,
                chain.ToArray(),
                providerNames.ToArray(),
                maxContextTokens.ToArray(),
                reservedOutputTokens.ToArray()).ToList();
        }
        catch (ArithmeticException)
        {
            // Context filtering is an optimization, not a correctness requirement.
            return chain;
        }
    }

    /// <summary>
    /// Resolves a provider's context window from config/model-catalog.json, matched against
    /// its configured/default model. A provider key can carry several catalog entries with
    /// different windows (e.g. anthropic's opus vs. haiku), so an exact model match is tried
    /// first; when the configured model isn't in the catalog, the smallest window among that
    /// provider's entries is used — underestimating capacity is safe, overestimating causes
    /// truncated requests.
    /// </summary>
    private (int MaxContextTokens, int ReservedOutputTokens)? ResolveContextWindow(string providerName)
    {
        if (_catalog is null)
        {
            return null;
        }

        var configuredModel = _options.Providers.TryGetValue(providerName, out var providerOptions)
            ? providerOptions.Model
            : null;
        var defaultModel = configuredModel
            ?? (_byProvider.TryGetValue(providerName, out var agent) ? (agent as ProviderAgentBase)?.DefaultModel : null);

        var candidates = _catalog.AllModels
            .Where(m => string.Equals(m.Provider, providerName, StringComparison.OrdinalIgnoreCase))
            .ToList();
        if (candidates.Count == 0)
        {
            return null;
        }

        var match = defaultModel is not null
            ? candidates.FirstOrDefault(m => string.Equals(m.Model, defaultModel, StringComparison.OrdinalIgnoreCase))
            : null;
        var contextTokens = (match ?? candidates.MinBy(m => m.ContextTokens))!.ContextTokens;

        var reserved = Math.Min(DefaultReservedOutputTokens, contextTokens / 4);
        return (contextTokens, reserved);
    }

    /// <summary>
    /// Estimates a prompt's token count via the C++ native estimator (src/ai/HELIOS.AIHub.Native),
    /// falling back to the same ~4-bytes-per-token heuristic it uses internally when the native
    /// library isn't present at runtime — it's documented as optional, so its absence must degrade
    /// gracefully rather than break routing.
    /// </summary>
    private static int EstimateTokenCount(string text)
    {
        if (string.IsNullOrEmpty(text))
        {
            return 0;
        }

        var utf8 = Encoding.UTF8.GetBytes(text);
        try
        {
            if (NativeMethods.EstimateTokens(utf8, (nuint)utf8.Length, out var tokens) == 0)
            {
                return tokens;
            }
        }
        catch (DllNotFoundException)
        {
        }
        catch (EntryPointNotFoundException)
        {
        }

        return utf8.Length / 4;
    }

    /// <summary>Feature-hash vector width for dedup — fixed so every result maps to the same space.</summary>
    private const int DedupVectorDimension = 64;

    /// <summary>Cosine-similarity threshold above which two responses count as duplicates.</summary>
    private const float DedupSimilarityThreshold = 0.90f;

    /// <summary>
    /// Marks near-duplicate responses within a CompareAsync fan-out using the native
    /// cosine-similarity kernel (src/ai/HELIOS.AIHub.Native). There's no embedding model wired
    /// into AIHub, so this hashes each response into a fixed-width word-frequency vector — cheap,
    /// deterministic, and enough to catch providers that returned essentially the same text.
    /// Falls back to returning results unmarked when the native library isn't present.
    /// </summary>
    internal static IReadOnlyList<ChatResult> FlagDuplicates(ChatResult[] results)
    {
        var candidates = results
            .Select((result, index) => (result, index))
            .Where(x => x.result.Success && !string.IsNullOrWhiteSpace(x.result.Text))
            .ToList();

        if (candidates.Count < 2)
        {
            return results;
        }

        var vectors = new float[candidates.Count * DedupVectorDimension];
        for (var i = 0; i < candidates.Count; i++)
        {
            HashedFrequencyVector(candidates[i].result.Text!, vectors.AsSpan(i * DedupVectorDimension, DedupVectorDimension));
        }

        var matrix = new float[candidates.Count * candidates.Count];
        try
        {
            if (NativeMethods.SimilarityMatrix(vectors, (nuint)candidates.Count, (nuint)DedupVectorDimension, matrix) != 0)
            {
                return results;
            }
        }
        catch (DllNotFoundException)
        {
            return results;
        }
        catch (EntryPointNotFoundException)
        {
            return results;
        }

        var updated = (ChatResult[])results.Clone();
        for (var i = 0; i < candidates.Count; i++)
        {
            for (var j = 0; j < i; j++)
            {
                if (matrix[(i * candidates.Count) + j] >= DedupSimilarityThreshold)
                {
                    var originalIndex = candidates[i].index;
                    var earlierProvider = candidates[j].result.Provider;
                    updated[originalIndex] = updated[originalIndex] with { DuplicateOfProvider = earlierProvider };
                    break;
                }
            }
        }

        return updated;
    }

    /// <summary>Deterministic hashed word-frequency vector — FNV-1a into buckets, then L2-normalized.</summary>
    internal static void HashedFrequencyVector(string text, Span<float> vector)
    {
        vector.Clear();
        foreach (var word in Tokenize(text))
        {
            var bucket = (int)(Fnv1aHash(word) % (uint)vector.Length);
            vector[bucket] += 1f;
        }

        var normSquared = 0.0;
        foreach (var v in vector)
        {
            normSquared += (double)v * v;
        }

        if (normSquared < 1e-12)
        {
            return;
        }

        var norm = (float)Math.Sqrt(normSquared);
        for (var i = 0; i < vector.Length; i++)
        {
            vector[i] /= norm;
        }
    }

    private static IEnumerable<string> Tokenize(string text)
    {
        var start = -1;
        for (var i = 0; i < text.Length; i++)
        {
            if (char.IsLetterOrDigit(text[i]))
            {
                if (start < 0)
                {
                    start = i;
                }
            }
            else if (start >= 0)
            {
                yield return text[start..i].ToLowerInvariant();
                start = -1;
            }
        }

        if (start >= 0)
        {
            yield return text[start..].ToLowerInvariant();
        }
    }

    private static uint Fnv1aHash(string value)
    {
        const uint offsetBasis = 2166136261;
        const uint prime = 16777619;

        var hash = offsetBasis;
        foreach (var c in value)
        {
            hash ^= c;
            hash *= prime;
        }

        return hash;
    }

    private async Task RecordOutcomeAsync(
        string? taskType, ChatResult result, CancellationToken cancellationToken)
    {
        if (!_options.Learning.Enabled || taskType is null)
        {
            return;
        }

        try
        {
            await _learning.RecordAsync(
                new RoutingOutcome
                {
                    Timestamp = DateTimeOffset.UtcNow,
                    TaskType = taskType,
                    Provider = result.Provider,
                    Model = result.Model,
                    Success = result.Success,
                    LatencyMs = result.Latency.TotalMilliseconds,
                    CostUsd = 0, // Populated by the caller that knows the rate; see Pricing.fs.
                    Pool = Environment.GetEnvironmentVariable("HELIOS_FLEET_POOL"),
                },
                cancellationToken).ConfigureAwait(false);
        }
        catch (IOException)
        {
            // Recording is best-effort; losing a data point must not fail the user's call.
        }
        catch (UnauthorizedAccessException)
        {
        }
    }

    /// <summary>Fan the same prompt out to several providers in parallel.</summary>
    public async Task<IReadOnlyList<ChatResult>> CompareAsync(
        string prompt, IReadOnlyList<string>? providers = null, string? system = null,
        CancellationToken cancellationToken = default)
    {
        var targets = providers is { Count: > 0 }
            ? providers
            : _byProvider.Values.Where(a => a.Readiness == ProviderReadiness.Ready).Select(a => a.Provider).ToList();

        var tasks = targets.Select(name =>
            _byProvider.TryGetValue(name, out var agent)
                ? agent.ChatAsync(new ChatRequest(prompt, System: system), cancellationToken)
                : Task.FromResult(new ChatResult(false, null, name, "", TimeSpan.Zero,
                    Error: $"Unknown provider '{name}'.")));

        var results = await Task.WhenAll(tasks).ConfigureAwait(false);
        return FlagDuplicates(results);
    }

    /// <summary>
    /// Runs a task-type's whole chain concurrently rather than as sequential fallback —
    /// "tandem" mode. The motivating case is code_generation: ChatGPT (API) and Codex
    /// (CLI) genuinely differ in latency and failure modes, so running both at once and
    /// keeping whichever finishes correctly beats waiting out a slow one before trying
    /// the next. Every result is recorded to the learning store (when enabled), so tandem
    /// runs feed the same evidence RouteAsync draws on — usage across the tandem set
    /// compounds into better single-shot routing over time.
    /// </summary>
    public async Task<TandemResult> TandemAsync(
        string taskType, string prompt, string? system = null, CancellationToken cancellationToken = default)
    {
        var chain = _strategy.GetChain(taskType).Where(name => _byProvider.ContainsKey(name)).ToList();
        if (chain.Count == 0)
        {
            return new TandemResult(taskType, Array.Empty<ChatResult>(), null);
        }

        chain = FilterChainByContext(chain, prompt);

        var request = new ChatRequest(prompt, System: system, TaskType: taskType);
        var tasks = chain.Select(async name =>
        {
            var result = await _byProvider[name].ChatAsync(request, cancellationToken).ConfigureAwait(false);
            await RecordOutcomeAsync(taskType, result, cancellationToken).ConfigureAwait(false);
            return result;
        });

        var results = await Task.WhenAll(tasks).ConfigureAwait(false);

        // Prefer the reordered (learned) chain's first successful result; when nothing
        // succeeded there is no winner to report, only the failures to inspect.
        var learnedOrder = await ApplyLearningAsync(taskType, chain, cancellationToken).ConfigureAwait(false);
        var byProviderResult = results.ToDictionary(r => r.Provider, StringComparer.OrdinalIgnoreCase);
        var winner = learnedOrder
            .Select(name => byProviderResult.GetValueOrDefault(name))
            .FirstOrDefault(r => r?.Success == true);

        return new TandemResult(taskType, results, winner);
    }

    /// <summary>Configuration/readiness of every registered provider (no network calls).</summary>
    public IReadOnlyList<ProviderStatusInfo> GetStatus() =>
        _byProvider.Values
            .OrderBy(agent => agent.Provider, StringComparer.OrdinalIgnoreCase)
            .Select(agent =>
            {
                var readiness = agent.Readiness == ProviderReadiness.Ready
                                && _fallback.GetState(agent.Provider) == CircuitState.Open
                    ? ProviderReadiness.Degraded
                    : agent.Readiness;
                var detail = agent is ProviderAgentBase providerAgent ? providerAgent.ConfigurationHint : null;
                return new ProviderStatusInfo(
                    agent.Provider,
                    agent is CliProcessAgent ? "cli" : "api",
                    (agent as ProviderAgentBase)?.DefaultModel,
                    readiness,
                    readiness == ProviderReadiness.Degraded ? "circuit open after repeated failures" : detail);
            })
            .ToList();

    /// <summary>Every provider's tandem result plus which one the learned policy currently favors.</summary>
    public sealed record TandemResult(string TaskType, IReadOnlyList<ChatResult> Results, ChatResult? Winner);

    public interface IRoutingTableView
    {
        IReadOnlyList<string> DefaultChain { get; }
        IReadOnlyDictionary<string, IReadOnlyList<string>> TaskRouting { get; }
    }

    private sealed class RoutingTableView : IRoutingTableView
    {
        public RoutingTableView(RoutingOptions routing)
        {
            DefaultChain = routing.DefaultChain;
            TaskRouting = routing.TaskRouting.ToDictionary(
                kv => kv.Key,
                kv => (IReadOnlyList<string>)kv.Value);
        }

        public IReadOnlyList<string> DefaultChain { get; }
        public IReadOnlyDictionary<string, IReadOnlyList<string>> TaskRouting { get; }
    }
}
