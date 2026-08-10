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

    /// <summary>Loads the hub config and builds the hub. Resolution order: explicit path,
    /// then the AIHUB_CONFIG environment variable (how .helios/azure.env selects the
    /// cloud-only profile), then config/aihub.json walking up from the current directory.</summary>
    public static AIHubService CreateFromConfig(string? configPath = null)
    {
        var resolved = ResolveConfigPath(configPath);
        // The catalog belongs to whichever config was selected: a --config/AIHUB_CONFIG
        // profile outside the repo must not silently pick up an unrelated tree's
        // model-catalog.json via the default directory walk. Missing-beside-config
        // falls back to the walk inside the constructor.
        var catalogPath = Path.Combine(
            Path.GetDirectoryName(Path.GetFullPath(resolved))!, "model-catalog.json");
        return new(AIHubOptions.Load(resolved), catalog: ModelCatalog.TryLoad(catalogPath));
    }

    /// <summary>Explicit --config beats AIHUB_CONFIG beats walking up the directory tree.</summary>
    public static string ResolveConfigPath(string? configPath = null)
    {
        var fromEnv = Environment.GetEnvironmentVariable("AIHUB_CONFIG");
        return configPath
               ?? (string.IsNullOrWhiteSpace(fromEnv) ? null : fromEnv)
               ?? AIHubOptions.FindConfigFile()
               ?? throw new FileNotFoundException(
                   "config/aihub.json not found in this directory or any parent. Run from the repo, set AIHUB_CONFIG, or pass --config.");
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

        try
        {
            // Construct the local backend only for modes that use it: azure-only mode
            // must not touch the filesystem (a read-only container would fail hub
            // construction over a store it never reads).
            return options.Mode.ToLowerInvariant() switch
            {
                "azure" when !string.IsNullOrWhiteSpace(endpoint) =>
                    new AzureTableLearningStore(new Uri(endpoint)),
                "hybrid" when !string.IsNullOrWhiteSpace(endpoint) =>
                    new HybridLearningStore(
                        new LocalJsonlLearningStore(options.LocalPath),
                        new AzureTableLearningStore(new Uri(endpoint))),
                // Azure requested but unconfigured degrades to local rather than failing —
                // the same "unconfigured is a state" rule the providers follow.
                _ => new LocalJsonlLearningStore(options.LocalPath),
            };
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or UriFormatException)
        {
            // Learning is advisory: a read-only working directory or malformed endpoint
            // must never stop the hub from starting.
            return new NullLearningStore();
        }
    }

    /// <summary>
    /// Best provider for a task under a cost/latency/quality/balanced preference, using
    /// the static model catalog (config/model-catalog.json). Null when the catalog has no
    /// opinion for this task type, or wasn't found — callers should fall back to
    /// <see cref="RouteAsync"/>'s configured chain.
    /// </summary>
    public string? SelectOptimalProvider(string taskType, string preference = "balanced") =>
        SelectOptimalProfile(taskType, preference)?.Provider;

    /// <summary>
    /// Best provider AND the model whose catalog profile won the ranking. Callers should
    /// pass both to <see cref="AskAsync"/>: the ranking scored a specific provider/model
    /// pair, and invoking the provider's configured default instead would silently answer
    /// a different question than the one optimized.
    /// </summary>
    public (string Provider, string Model)? SelectOptimalProfile(string taskType, string preference = "balanced")
    {
        // Rank only profiles a request could actually reach: an unregistered or
        // unconfigured provider winning the ranking would either return null despite
        // a usable runner-up, or select a provider whose ask is guaranteed to fail.
        var ready = _byProvider.Values
            .Where(agent => agent.Readiness == ProviderReadiness.Ready)
            .Select(agent => agent.Provider)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        return ready.Count == 0 ? null : _catalog?.SelectProfile(taskType, preference, ready);
    }

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

        chain = FilterChainByContext(chain, prompt, system);
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
            // Advisory records (Source != null: absorption benchmarks, fork digests)
            // inform insights only — routing must learn exclusively from the hub's own
            // provider outcomes.
            history = history.Where(h => h.Source is null).ToList();
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
        catch (Azure.RequestFailedException)
        {
            // Azure Table learning store outage — same rule as filesystem failures.
            return configuredChain;
        }
        catch (Azure.Identity.AuthenticationFailedException)
        {
            return configuredChain;
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            // A store-internal timeout, not the caller cancelling: learning failures
            // must preserve the configured order, never abort the route.
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
    private List<string> FilterChainByContext(List<string> chain, string prompt, string? system = null)
    {
        if (_catalog is null || chain.Count == 0)
        {
            return chain;
        }

        // System instructions ride in the same context window as the prompt; sizing
        // only the prompt can keep a model that the full payload overflows.
        var promptTokens = EstimateTokenCount(system is null ? prompt : $"{system}\n{prompt}");
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
        if (NativeGate.Available)
        {
            if (NativeMethods.EstimateTokens(utf8, (nuint)utf8.Length, out var tokens) == 0)
            {
                return tokens;
            }
        }

        // Managed fallback mirrors the native heuristic: ASCII averages ~3.85
        // characters per token while a multibyte character is roughly one token.
        // Plain bytes/4 undercounted CJK ~25% relative to the native path, so the
        // same prompt could pass or fail context filtering depending on whether
        // the optional library happened to be present.
        var ascii = 0;
        var multibyte = 0;
        foreach (var b in utf8)
        {
            if ((b & 0xC0) == 0x80)
            {
                continue; // UTF-8 continuation byte
            }
            if (b < 0x80)
            {
                ascii++;
            }
            else
            {
                multibyte++;
            }
        }

        var estimate = (ascii / 3.85) + multibyte;
        return estimate < 1.0 ? 1 : (int)estimate;
    }

    /// <summary>Feature-hash vector width for dedup — fixed so every result maps to the same space.</summary>
    private const int DedupVectorDimension = 64;

    /// <summary>Token-set agreement required to CONFIRM a hash-prefiltered duplicate pair.</summary>
    private const double DedupJaccardVerifyThreshold = 0.5;

    /// <summary>Jaccard similarity over the actual token sets — the collision check
    /// behind the hashed prefilter.</summary>
    internal static double TokenJaccard(string a, string b)
    {
        var setA = new HashSet<string>(Tokenize(a));
        var setB = new HashSet<string>(Tokenize(b));
        if (setA.Count == 0 || setB.Count == 0)
        {
            return 0;
        }
        var intersection = setA.Count(setB.Contains);
        return (double)intersection / (setA.Count + setB.Count - intersection);
    }

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

        if (candidates.Count < 2 || !NativeGate.Available)
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
                // The hashed vector is a 64-bucket prefilter: short unrelated replies
                // can collide into identical vectors ("no" and "approved" share a
                // bucket), so a candidate pair must also agree on actual tokens
                // before it counts as a duplicate.
                if (matrix[(i * candidates.Count) + j] >= DedupSimilarityThreshold
                    && TokenJaccard(candidates[i].result.Text!, candidates[j].result.Text!)
                        >= DedupJaccardVerifyThreshold)
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
                    CostUsd = EstimateCostUsd(result),
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
        catch (Azure.RequestFailedException)
        {
            // An Azure learning-store outage must not turn a successful (paid) provider
            // call into a routing failure.
        }
        catch (Azure.Identity.AuthenticationFailedException)
        {
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            // Store-internal timeout — recording is best-effort.
        }
    }

    /// <summary>
    /// Actual cost of a provider call from catalog rates and reported token usage, so the
    /// learning loop's cost weight and /v1/insights reflect real spend instead of a
    /// constant zero. Zero when usage or a confident rate match is unavailable —
    /// a wrong price is worse than an unknown one.
    /// </summary>
    private double EstimateCostUsd(ChatResult result)
    {
        if (_catalog is null || result.InputTokens is not { } input || result.OutputTokens is not { } output)
        {
            return 0;
        }

        var providerModels = _catalog.AllModels
            .Where(m => string.Equals(m.Provider, result.Provider, StringComparison.OrdinalIgnoreCase))
            .ToList();

        // Exact model match first; then prefix (providers append version suffixes like
        // gpt-5-mini-2025-08-07); a lone catalog entry for the provider is unambiguous.
        var profile = providerModels.FirstOrDefault(m => string.Equals(m.Model, result.Model, StringComparison.OrdinalIgnoreCase))
            ?? providerModels.FirstOrDefault(m => result.Model.StartsWith(m.Model, StringComparison.OrdinalIgnoreCase))
            ?? (providerModels.Count == 1 ? providerModels[0] : null);

        return profile is null
            ? 0
            : PricingInterop.EstimateCostUsd(
                profile.InputPerMillionUsd, profile.OutputPerMillionUsd, input, output);
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

        chain = FilterChainByContext(chain, prompt, system);

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
