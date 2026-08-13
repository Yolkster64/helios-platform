using HELIOS.AIHub.Domain;

namespace HELIOS.AIHub.Learning;

/// <summary>
/// The hub's single learned-reorder path: the native-MLP neural learner first (it can
/// express signal interactions the linear policy averages away), the F# linear routing
/// policy whenever it abstains. Extracted from <see cref="AIHubService"/> so advisory
/// surfaces (fleet-plan) score chains with EXACTLY the code RouteAsync uses — a second
/// implementation would drift and report plans the hub would never execute.
/// </summary>
internal sealed class ChainReorderEngine
{
    /// <summary>No organic history — nothing was scored, the configured order stands.</summary>
    public const string None = "none";

    /// <summary>The F# linear routing policy scored the chain.</summary>
    public const string Linear = "linear";

    /// <summary>The native MLP scored the chain, fused with the linear policy.</summary>
    public const string Neural = "neural";

    private readonly NeuralRoutingLearner _neuralLearner = new();

    /// <summary>
    /// Drop source-tagged records: a non-null <see cref="RoutingOutcome.Source"/> marks
    /// an ADVISORY ingest (absorption-benchmark, fork-observation, fleet-lane, …) whose
    /// "provider" may not even be a provider — fleet-lane records carry lane names like
    /// "pool:xcore-9-code". Chains learn from organic hub history only, so external
    /// signals can never steer provider order.
    /// </summary>
    public static IReadOnlyList<RoutingOutcome> OrganicOnly(IReadOnlyList<RoutingOutcome> history) =>
        history.Where(h => h.Source is null).ToList();

    /// <summary>
    /// Reorder <paramref name="configuredChain"/> from organic history (newest first, as
    /// the learning store returns it), reporting which engine produced the order: neural
    /// when the native MLP had enough evidence to speak, linear otherwise. Callers pass
    /// pre-filtered organic history (<see cref="OrganicOnly"/>) and handle the empty
    /// case themselves — an empty history is "no evidence" (<see cref="None"/>), not a
    /// reorder.
    /// </summary>
    public (IReadOnlyList<string> Chain, string Engine) Reorder(
        string taskType, IReadOnlyList<string> configuredChain, IReadOnlyList<RoutingOutcome> history)
    {
        var neural = _neuralLearner.Reorder(taskType, configuredChain, history);
        if (neural is not null)
        {
            return (neural, Neural);
        }

        var linear = RoutingPolicyInterop.ReorderChain(
            taskType,
            configuredChain.ToArray(),
            history.Select(h => h.Provider).ToArray(),
            history.Select(h => h.Success).ToArray(),
            history.Select(h => h.LatencyMs).ToArray(),
            history.Select(h => h.CostUsd).ToArray(),
            history.Select(h => h.Quality ?? double.NaN).ToArray());
        return (linear, Linear);
    }
}
