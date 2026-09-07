using System.Text.Json.Serialization;
using HELIOS.AIHub.Learning;
using HELIOS.AIHub.Routing;

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
        // One evidence read per pool task type (the string the topology writes), not
        // per pool × task type: pools may share task types, and the store can be a
        // network hop (Azure Table).
        var organicByTask = new Dictionary<string, IReadOnlyList<RoutingOutcome>>(StringComparer.Ordinal);

        foreach (var pool in topology.Pools)
        {
            foreach (var taskType in pool.TaskTypes)
            {
                if (!organicByTask.TryGetValue(taskType, out var organic))
                {
                    // A pool is scored on the evidence RouteAsync would use for its key.
                    // A bare task type reads the language-less records — its own chain's
                    // outcomes; language-qualified outcomes belong to their own chains.
                    // A qualified key (code_generation:fsharp) IS the (taskType,
                    // language) the hub records under, so it reads that scoped window
                    // first and falls back to the language-less one when the scoped read
                    // holds nothing organic, mirroring AIHubService.ApplyLearningAsync;
                    // read verbatim it would score the orphan ("code_generation:fsharp",
                    // no language) bucket nothing writes to. Every read goes through the
                    // store's organic (taskType, language) key so the window is taken
                    // AFTER both scopings: neither another language's outcomes nor an
                    // advisory ingest — the fleet collector's own lane records land
                    // under the pool's task type — filling the newest historyWindow
                    // records can crowd a pool's organic samples out of the read and
                    // report "no evidence" while evidence exists (the hub's RouteAsync
                    // had the same defect on both axes and takes the same fix).
                    organic = await GetOrganicEvidenceAsync(taskType, cancellationToken).ConfigureAwait(false);
                    organicByTask[taskType] = organic;
                }

                var configured = pool.ProviderChain;
                // The pool's original string is also the hub's learning key for that
                // evidence (ChainReorderEngine.LearningKey joins the split with the same
                // separator), so the neural learner's per-key cache lines up with RouteAsync.
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
    /// The organic evidence for one pool task type: the organic (taskType, language)
    /// window the key names (<see cref="SplitPoolTaskType"/>), then — for a qualified
    /// key whose own window holds nothing organic — the organic language-less window.
    /// This is the two-step read AIHubService.ApplyLearningAsync performs for a
    /// language-qualified route, so the plan predicts the policy the hub would actually
    /// apply. Organic-ness is scoped by the store, before its cap (see
    /// <see cref="ILearningStore.GetRecentOrganicForLanguageAsync"/>); nothing here
    /// filters afterwards.
    /// </summary>
    private async Task<IReadOnlyList<RoutingOutcome>> GetOrganicEvidenceAsync(
        string poolTaskType, CancellationToken cancellationToken)
    {
        var (taskType, language) = SplitPoolTaskType(poolTaskType);
        var organic = await GetRecentOrganicSafeAsync(taskType, language, cancellationToken).ConfigureAwait(false);
        if (organic.Count == 0 && language is not null)
        {
            organic = await GetRecentOrganicSafeAsync(taskType, language: null, cancellationToken)
                .ConfigureAwait(false);
        }
        return organic;
    }

    /// <summary>
    /// The (taskType, language) a pool task type records under. A qualified routing key
    /// whose language part is already canonical (<c>code_generation:fsharp</c>) splits;
    /// a bare task type, or a key the hub itself would treat as a literal task type
    /// (<c>code_generation:F#</c>, whose language part is not canonical), reads verbatim
    /// with no language. The planner has no routing table to consult, so unlike
    /// <see cref="TaskTypeRoutingStrategy.CanonicalizeTaskType"/> it does not require
    /// the key to be configured: a pool may name a chain before the hub has one, and is
    /// then scored on the parent task type's evidence through the fallback.
    /// </summary>
    private static (string TaskType, string? Language) SplitPoolTaskType(string poolTaskType)
    {
        var (taskType, language) = TaskTypeRoutingStrategy.SplitRoutingKey(poolTaskType);
        return taskType.Length > 0
               && language is not null
               && string.Equals(TaskTypeRoutingStrategy.NormalizeLanguage(language), language, StringComparison.Ordinal)
            ? (taskType, language)
            : (poolTaskType, null);
    }

    /// <summary>
    /// The newest <c>historyWindow</c> organic outcomes of one (taskType, language) key
    /// — both scoped at the store so the cap applies after scoping. Same degradation
    /// contract as AIHubService.ApplyLearningAsync: a store failure reads as "no
    /// evidence" (engine none), never a crashed advisory report.
    /// </summary>
    private async Task<IReadOnlyList<RoutingOutcome>> GetRecentOrganicSafeAsync(
        string taskType, string? language, CancellationToken cancellationToken)
    {
        try
        {
            return await _learning.GetRecentOrganicForLanguageAsync(
                    taskType, language, _historyWindow, cancellationToken)
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
