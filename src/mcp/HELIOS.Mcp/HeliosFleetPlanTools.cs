using System.ComponentModel;
using System.Text.Json;
using System.Text.Json.Serialization;
using HELIOS.AIHub;
using HELIOS.AIHub.Fleet;
using ModelContextProtocol.Server;

namespace HELIOS.Mcp;

/// <summary>
/// Advisory fleet-plan tool: the MCP twin of `helios-ai fleet-plan --json`. It reads
/// config/fleet/fleet-topology.json and scores each pool's CONFIGURED provider chain
/// against the chain the hub's learned routing would prefer today, through the exact
/// planner the CLI uses (<see cref="AIHubService.CreateFleetPlanner"/> — same learning
/// store, history window, and reorder engine as RouteAsync). ADVISORY ONLY: chains are
/// config and are never auto-applied; this tool mutates neither topology, aihub.json,
/// nor routing state. A missing/unreadable topology and an absent or empty learning
/// store are expected states — a message or engine "none", never a crash.
/// </summary>
[McpServerToolType]
public static class HeliosFleetPlanTools
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    /// <summary>Same advisory voice as the CLI's fleet-plan trailer, carried in-band as a field.</summary>
    public const string AdvisoryNote =
        "Advisory only — learned chains are a report, never applied: nothing was routed, " +
        "installed, or reconfigured, and pool chains change only by editing " +
        "config/fleet/fleet-topology.json.";

    [McpServerTool(Name = "helios_fleet_plan_get", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description("Advisory fleet routing plan (same rows as `helios-ai fleet-plan --json`): for every pool x task type in config/fleet/fleet-topology.json, { pool, taskType, configuredChain, learnedChain, sampleCount, engine } — configuredChain exactly as the topology orders it, learnedChain the order the hub's learned routing would prefer from organic history, engine none|linear|neural, sampleCount the organic outcomes considered. Read-only and advisory: chains are config and are NEVER auto-applied. An empty learning history reports engine 'none' with the configured order; a missing topology returns a message, not an error.")]
    public static async Task<string> GetFleetPlan(
        AIHubService hub,
        [Description("Path to a fleet-topology JSON file. Omit to resolve config/fleet/fleet-topology.json walking up from the current directory (the repo-root convention).")]
        string? topologyPath = null,
        CancellationToken cancellationToken = default)
    {
        var loaded = FleetTopology.TryLoad(string.IsNullOrWhiteSpace(topologyPath) ? null : topologyPath);
        if (loaded.Topology is null)
        {
            // TryLoad already folds missing and unreadable into a one-line reason; an
            // advisory reader reports it rather than crashing (CLI parity).
            return JsonSerializer.Serialize(new
            {
                topologyPath = loaded.Path,
                plan = Array.Empty<FleetPlanEntry>(),
                message = loaded.Error,
                advisory = AdvisoryNote,
            }, JsonOptions);
        }

        var plan = await hub.CreateFleetPlanner().PlanAsync(loaded.Topology, cancellationToken);
        return JsonSerializer.Serialize(new
        {
            topologyPath = loaded.Path,
            plan,
            message = plan.Count == 0
                ? "The topology defines no pool x task-type rows — nothing to score."
                : null,
            advisory = AdvisoryNote,
        }, JsonOptions);
    }
}
