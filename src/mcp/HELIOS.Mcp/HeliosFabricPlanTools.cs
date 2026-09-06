using System.ComponentModel;
using System.Text.Json;
using System.Text.Json.Serialization;
using HELIOS.AIHub.Fabric;
using ModelContextProtocol.Server;

namespace HELIOS.Mcp;

/// <summary>
/// Advisory HC-029 execution tool: reads config/fabric/helios-fabric.v1.json and
/// projects the effective next steps while respecting rename gates and checklist
/// dependencies. Read-only: no external mutation is performed.
/// </summary>
[McpServerToolType]
public static class HeliosFabricPlanTools
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    [McpServerTool(Name = "helios_fabric_plan_get", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description("Advisory HC-029 Fabric execution plan from config/fabric/helios-fabric.v1.json: summary counts, effective status per checklist item, dependency/rename gates, and next actions. Read-only and local: no Slack/Linear/SharePoint write, no repo rename, no Azure apply.")]
    public static string GetFabricPlan(
        [Description("Path to the Fabric contract JSON. Omit to resolve config/fabric/helios-fabric.v1.json by walking up from the current directory.")]
        string? contractPath = null,
        [Description("Set true only after the repository rename to Yolkster64/helios-control is complete; rename-gated checklist items become actionable.")]
        bool renameCompleted = false)
    {
        var loaded = FabricContract.TryLoad(string.IsNullOrWhiteSpace(contractPath) ? null : contractPath);
        var planner = new FabricPlanService();

        if (loaded.Contract is null)
        {
            var empty = new FabricPlanResult
            {
                Summary = new FabricPlanSummary(),
                Plan = Array.Empty<FabricPlanEntry>(),
                NextActions = new[]
                {
                    "Load config/fabric/helios-fabric.v1.json or pass an explicit contract path.",
                },
                Message = loaded.Error,
            };

            return JsonSerializer.Serialize(new
            {
                contractPath = loaded.Path,
                renameCompleted,
                summary = empty.Summary,
                plan = empty.Plan,
                nextActions = empty.NextActions,
                message = empty.Message,
                advisory = FabricPlanService.AdvisoryNote,
            }, JsonOptions);
        }

        var plan = planner.BuildPlan(loaded.Contract, renameCompleted);
        return JsonSerializer.Serialize(new
        {
            contractPath = loaded.Path,
            migrationIssue = loaded.Contract.MigrationIssue,
            renameCompleted,
            summary = plan.Summary,
            plan = plan.Plan,
            nextActions = plan.NextActions,
            message = plan.Message,
            advisory = FabricPlanService.AdvisoryNote,
        }, JsonOptions);
    }
}
