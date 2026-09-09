using System.ComponentModel;
using HELIOS.Mcp;
using ModelContextProtocol.Server;

namespace HELIOS.RemoteMcp;

[McpServerToolType]
public sealed class RemoteAgentCatalogTools(RemoteMcpOptions options)
{
    [McpServerTool(Name = "helios_usb_plan_get", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description("Plan USB media with the same portable planner as Desktop, from explicit caller-supplied camelCase JSON inventory (16 KiB maximum). No disk reads or writes; canExecute is always false. Unknown target safety properties block the proposal.")]
    public string UsbPlan(string requestJson) => HeliosUsbSetupTools.GetUsbPlan(requestJson);

    [McpServerTool(Name = "helios_combo_analyze", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description("Analyze supplied AIHub outcome JSONL (up to 32 KiB) with the shared offline uncertainty/tradeoff calculator. Exact task/language scope; 1 to 200 organic outcomes. No files, credentials, model calls, learning writes or route changes.")]
    public string AnalyzeOutcomes(string outcomesJsonl, string taskType, string? language = null, int limit = 200) =>
        HeliosComboAnalysisTools.Analyze(outcomesJsonl, taskType, language, limit);

    [McpServerTool(Name = "helios_agent_catalog_get", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description("Read the shared HELIOS roles, task templates, skills, agent profiles and configured task routes. Native activation remains client-specific; no provider, process or cloud operation runs.")]
    public string Catalog() => new HeliosAgentCatalogStore(options.RepositoryRoot).Catalog();

    [McpServerTool(Name = "helios_task_packet_get", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description("Read the shared helios-work instructions and deterministic plan for implement, review, hybrid-plan or fleet-plan. Optional language selects an existing configured route. Returns a template, not a running task or infrastructure apply.")]
    public string TaskPacket(string taskKind, string? language = null) =>
        new HeliosAgentCatalogStore(options.RepositoryRoot).TaskPacket(taskKind, language);
}
