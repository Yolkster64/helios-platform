using System.ComponentModel;
using System.Text.Json;
using ModelContextProtocol.Server;

namespace HELIOS.RemoteMcp;

[McpServerToolType]
public sealed class RemoteReadTools(RemoteRepository repository, RemoteMcpOptions options)
{
    [McpServerTool(Name = "search", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description("Search the fixed HELIOS project document catalog. Results contain IDs for fetch. Reads the trusted checkout; does not search mail, Slack, private sessions, or arbitrary files.")]
    public string Search([Description("Plain text to find, 1 to 200 characters.")] string query) => repository.Search(query);

    [McpServerTool(Name = "fetch", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description("Fetch a HELIOS project document by the exact ID returned by search. IDs are catalog keys, never URLs or filesystem paths. Checkout content can differ from the linked main branch.")]
    public string Fetch([Description("Catalog ID returned by search.")] string id) => repository.Fetch(id);

    [McpServerTool(Name = "helios_project_get", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description("Read the shared HELIOS project map used by Claude, Codex, the launcher, and the control panel.")]
    public string Project() => repository.Fetch("project");

    [McpServerTool(Name = "helios_task_routing_get", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description("Read the existing task/language routing table. Returns configured chains only, without loading credentials or calling a provider.")]
    public string Routing() => repository.TaskRouting();

    [McpServerTool(Name = "helios_fabric_plan_get", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description("Run the shared C# Fabric planner against the fixed project contract. Advisory only; no rename, cloud changes, or connector writes.")]
    public string FabricPlan() => repository.FabricPlan();

    [McpServerTool(Name = "helios_fleet_topology_get", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description("Read the configured Hermes and XCore fleet topology. Configuration is not evidence of running workers.")]
    public string Fleet() => repository.Fetch("fleet");

    [McpServerTool(Name = "helios_fleet_readiness_get", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description("Read offline Hermes/XCore capacity ceilings and activation dependencies from the fixed fleet topology. Uses the shared C# planner; no worker launch, model calls, credential reads or cloud operations. Configured lanes are not verified workers.")]
    public string FleetReadiness() => repository.FleetReadiness();

    [McpServerTool(Name = "helios_bridge_status_get", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description("Read this bridge's enabled capabilities. Does not probe sign-in, call a model, or claim a web Claude session is attached.")]
    public string Status() => JsonSerializer.Serialize(new
    {
        transport = "streamable-http", project = "helios-control", authentication = options.AuthMode,
        claude = new { enabled = options.ClaudeEnabled, authentication = "unverified", existingWebSessionAttached = false },
        connectorDelivery = "unverified", productionEnabled = false,
    });
}
