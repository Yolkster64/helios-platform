using System.Text.Json.Serialization;
using HELIOS.AIHub.Learning;

namespace HELIOS.AIHub.Fleet;

/// <summary>
/// One advisory pool × task-type comparison: the chain the topology configures next to
/// the chain the hub's learned routing would prefer today, with how much organic
/// evidence backed the comparison and which engine scored it.
/// </summary>
public sealed record FleetPlanEntry
{
    [JsonPropertyName("pool")]
    public string Pool { get; init; } = "";

    [JsonPropertyName("taskType")]
    public string TaskType { get; init; } = "";

    /// <summary>The pool's provider chain exactly as config/fleet/fleet-topology.json orders it.</summary>
    [JsonPropertyName("configuredChain")]
    public IReadOnlyList<string> ConfiguredChain { get; init; } = Array.Empty<string>();

    /// <summary>
    /// The same providers in the order the hub's learned policy would try them — the
    /// configured order whenever evidence is empty or too thin to reorder.
    /// </summary>
    [JsonPropertyName("learnedChain")]
    public IReadOnlyList<string> LearnedChain { get; init; } = Array.Empty<string>();

    /// <summary>Organic (untagged) outcomes that informed the comparison.</summary>
    [JsonPropertyName("sampleCount")]
    public int SampleCount { get; init; }

    /// <summary>none (no organic history) | linear (F# policy) | neural (native MLP fused).</summary>
    [JsonPropertyName("engine")]
    public string Engine { get; init; } = ChainReorderEngine.None;
}

/// <summary>
/// The tandem feedback path between the hub and the agent fleet: scores each fleet
/// pool's CONFIGURED provider chain against what the hub's learned routing — the F#
/// linear policy plus the native neural MLP, via the exact
/// <see cref="ChainReorderEngine"/> RouteAsync uses — would prefer, from organic hub
/// history alone. Records tagged with a <see cref="RoutingOutcome.Source"/> never
/// participate: fleet-lane records in particular are LANE outcomes (provider values
/// like "pool:xcore-9-code"), not provider outcomes.
///
/// ADVISORY ONLY: this reads the learning store and reports. It never mutates topology,
/// aihub.json, or routing state — acting on a divergence is a human editing
/// config/fleet/fleet-topology.json.
/// </summary>
public sealed class FleetPlanService
{
    private readonly ILearningStore _learning;
    private readonly int _historyWindow;
    private readonly ChainReorderEngine _reorderEngine;

    public FleetPlanService(ILearningStore learning, int historyWindow)
        : this(learning, historyWindow, new ChainReorderEngine())
    {
    }

    internal FleetPlanService(ILearningStore learning, int historyWindow, ChainReorderEngine reorderEngine)
    {
        _learning = learning;
        // Same clamp as AIHubService.ApplyLearningAsync: a zero/negative configured
        // window must not reach the store as an invalid capacity.
        _historyWindow = Math.Max(1, historyWindow);
        _reorderEngine = reorderEngine;
    }

    /// <summary>One entry per pool × task type, in topology order.</summary>
    public async Task<IReadOnlyList<FleetPlanEntry>> PlanAsync(
        FleetTopology topology, CancellationToken cancellationToken = default)
    {
        var entries = new List<FleetPlanEntry>();
        // One store read per task type, not per pool × task type: pools may share task
        // types, and the store can be a network hop (Azure Table).
        var organicByTask = new Dictionary<string, IReadOnlyList<RoutingOutcome>>(StringComparer.Ordinal);

        foreach (var pool in topology.Pools)
        {
            foreach (var taskType in pool.TaskTypes)
            {
                if (!organicByTask.TryGetValue(taskType, out var organic))
                {
                    organic = ChainReorderEngine.OrganicOnly(
                        await GetRecentSafeAsync(taskType, cancellationToken).ConfigureAwait(false));
                    organicByTask[taskType] = organic;
                }

                var configured = pool.ProviderChain;
                var (learned, engine) = organic.Count == 0 || configured.Count == 0
                    ? (configured, ChainReorderEngine.None)
                    : _reorderEngine.Reorder(taskType, configured, organic);

                entries.Add(new FleetPlanEntry
                {
                    Pool = pool.Name,
                    TaskType = taskType,
                    ConfiguredChain = configured,
                    LearnedChain = learned,
                    SampleCount = organic.Count,
                    Engine = engine,
                });
            }
        }

        return entries;
    }

    /// <summary>
    /// Same degradation contract as AIHubService.ApplyLearningAsync: a store failure
    /// reads as "no evidence" (engine none), never a crashed advisory report.
    /// </summary>
    private async Task<IReadOnlyList<RoutingOutcome>> GetRecentSafeAsync(
        string taskType, CancellationToken cancellationToken)
    {
        try
        {
            return await _learning.GetRecentAsync(taskType, _historyWindow, cancellationToken)
                .ConfigureAwait(false);
        }
        catch (IOException)
        {
            return Array.Empty<RoutingOutcome>();
        }
        catch (UnauthorizedAccessException)
        {
            return Array.Empty<RoutingOutcome>();
        }
        catch (Azure.RequestFailedException)
        {
            return Array.Empty<RoutingOutcome>();
        }
        catch (Azure.Identity.AuthenticationFailedException)
        {
            return Array.Empty<RoutingOutcome>();
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            // A store-internal timeout, not the caller cancelling.
            return Array.Empty<RoutingOutcome>();
        }
    }
}
