using System.ComponentModel;
using HELIOS.Mcp;
using ModelContextProtocol.Server;

namespace HELIOS.RemoteMcp;

[McpServerToolType]
public sealed class RemoteAgentCatalogTools(RemoteMcpOptions options)
{
    [McpServerTool(Name = "helios_agent_catalog_get", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description("Read the shared HELIOS roles, task templates, skills, agent profiles and configured task routes. Native activation remains client-specific; no provider, process or cloud operation runs.")]
    public string Catalog() => new HeliosAgentCatalogStore(options.RepositoryRoot).Catalog();

    [McpServerTool(Name = "helios_task_packet_get", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description("Read the shared helios-work instructions and deterministic plan for implement, review, hybrid-plan or fleet-plan. Optional language selects an existing configured route. Returns a template, not a running task or infrastructure apply.")]
    public string TaskPacket(string taskKind, string? language = null) =>
        new HeliosAgentCatalogStore(options.RepositoryRoot).TaskPacket(taskKind, language);
}
