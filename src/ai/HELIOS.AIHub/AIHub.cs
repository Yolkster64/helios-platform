using HELIOS.AIHub.Abstractions;
using HELIOS.AIHub.Configuration;
using HELIOS.AIHub.Learning;
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
    /// Reorder the configured chain from recorded outcomes, via the F# routing policy.
    /// Any failure here falls back to the configured order — learning must never be able
    /// to break routing, only improve it.
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

            var reordered = RoutingPolicyInterop.ReorderChain(
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

        return await Task.WhenAll(tasks).ConfigureAwait(false);
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
