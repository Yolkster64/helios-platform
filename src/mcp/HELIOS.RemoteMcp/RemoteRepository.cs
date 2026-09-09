using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using HELIOS.AIHub.Fabric;
using HELIOS.AIHub.Fleet;
using ModelContextProtocol;

namespace HELIOS.RemoteMcp;

/// <summary>A finite catalog of reviewed repository documents; never a filesystem browser.</summary>
public sealed class RemoteRepository(RemoteMcpOptions options)
{
    internal const int MaxDocumentBytes = 128 * 1024;
    internal static readonly IReadOnlyDictionary<string, (string Title, string Path)> Documents =
        new Dictionary<string, (string, string)>(StringComparer.Ordinal)
        {
            ["start"] = ("Connect HELIOS", "docs/CONNECT.md"),
            ["agent-contract"] = ("HELIOS agent contract", "AGENTS.md"),
            ["claude"] = ("Claude Code project instructions", "CLAUDE.md"),
            ["clients"] = ("MCP client setup", "docs/mcp/CLIENT_SETUP.md"),
            ["bridge"] = ("ChatGPT and Claude bridge", "docs/mcp/REMOTE_BRIDGE.md"),
            ["workspaces"] = ("Claude and Codex workspaces", "docs/AGENT_WORKSPACES.md"),
            ["project"] = ("Shared HELIOS project map", "config/control-project.json"),
            ["fabric"] = ("HELIOS Fabric contract", "config/fabric/helios-fabric.v1.json"),
            ["fleet"] = ("Hermes and XCore fleet topology", "config/fleet/fleet-topology.json"),
            ["shared-work"] = ("Canonical HELIOS work skill", "plugins/helios-connect/skills/helios-work/SKILL.md"),
            ["agent-catalog"] = ("Shared agent roles and task templates", "config/agent-catalog.json"),
            ["plugins"] = ("ChatGPT, Claude, Codex and Copilot plugin setup", "docs/mcp/PLUGIN_SETUP.md"),
            ["workspace-plugin"] = ("HELIOS workspace plugin", "plugins/helios-connect/README.md"),
            ["operator-plugin"] = ("HELIOS operator plugin", "plugins/helios-operator/README.md"),
            ["chatgpt-return"] = ("Claude to ChatGPT Workspace Agent return path", "docs/mcp/WORKSPACE_AGENT_RETURN.md"),
            ["chatgpt-import"] = ("ChatGPT context import and provenance", "docs/imports/chatgpt/README.md"),
            ["hybrid"] = ("Local and Azure hybrid execution", "docs/architecture/HYBRID_EXECUTION.md"),
            ["fleet-guide"] = ("Hermes, XCore and tandem learning guide", "docs/architecture/HERMES_FLEET_AND_XCORE.md"),
            ["aihub-unity"] = ("AIHub routing, combinations and learning skill", ".claude/skills/aihub-unity/SKILL.md"),
            ["model-pairing"] = ("AIHub model and tool pairing", ".claude/skills/aihub-unity/references/model-and-tool-pairing.md"),
            ["combo-calculus"] = ("AIHub combination scoring and learning", ".claude/skills/aihub-unity/references/combo-calculus.md"),
            ["combo-analysis"] = ("Offline evidence and uncertainty for AIHub combinations", "docs/architecture/COMBO_ANALYSIS.md"),
            ["model-cost"] = ("AIHub model strengths and recorded cost guidance", ".claude/skills/aihub-unity/references/model-strengths-and-cost.md"),
            ["language-roles"] = ("AIHub language responsibilities", "docs/architecture/AIHUB_LANGUAGE_ROLES.md"),
            ["azure-skill"] = ("HELIOS Azure infrastructure skill", ".claude/skills/iac-azure/SKILL.md"),
            ["bicep-tooling"] = ("HELIOS Bicep validation guidance", ".claude/skills/iac-azure/references/bicep-tooling.md"),
            ["terraform-tooling"] = ("HELIOS Terraform validation guidance", ".claude/skills/iac-azure/references/terraform-azurerm.md"),
            ["infra-guide"] = ("HELIOS Bicep infrastructure guide", "infra/README.md"),
            ["terraform-guide"] = ("HELIOS Terraform ownership guide", "infra/terraform/README.md"),
            ["bicep"] = ("HELIOS Bicep resource definitions", "infra/main.bicep"),
            ["terraform"] = ("HELIOS Terraform resource definitions", "infra/terraform/main.tf"),
            ["deployment-workflow"] = ("HELIOS protected deployment workflow", ".github/workflows/helios-deploy.yml"),
            ["owner-setup"] = ("HELIOS identity and owner setup", "docs/OWNER_START_HERE.md"),
            ["project-parts"] = ("Core, Desktop, GUI, USB, Cloud and Fleet component guide", "docs/PROJECT_PARTS.md"),
            ["usb-setup"] = ("HELIOS USB and profile setup wizard", "docs/USB_SETUP.md"),
            ["gui-workbench"] = ("GUI pieces, local previews, editing and Desktop builds", "docs/GUI_WORKBENCH.md"),
            ["connector-activation"] = ("HELIOS connector activation", "docs/architecture/CONNECTOR_ACTIVATION.md"),
            ["absorption"] = ("Absorption and learning starting guide", "docs/absorption/START_HERE.md"),
            ["absorption-pipeline"] = ("Absorption pipeline and learning boundaries", "docs/architecture/ABSORPTION_PIPELINE.md"),
            ["absorption-learnings"] = ("Absorption epics and retained learnings", "docs/absorption/EPICS_AND_LEARNINGS.md"),
        };

    public string Fetch(string id)
    {
        if (string.IsNullOrEmpty(id) || !Documents.TryGetValue(id, out var document))
            throw new McpException("Unknown document ID. Use search to find an allowed HELIOS document.");
        var text = ReadFixedFile(document.Path);
        return JsonSerializer.Serialize(new
        {
            id, title = document.Title, text,
            url = DocumentUrl(document.Path),
            metadata = new
            {
                path = document.Path, source = "trusted checkout", liveServiceReceipt = false,
                sha256 = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text))).ToLowerInvariant(),
            },
        });
    }

    public string Search(string query)
    {
        if (string.IsNullOrWhiteSpace(query) || query.Length > 200)
            throw new McpException("query must contain 1 to 200 characters.");
        var matches = Documents.Where(pair =>
        {
            // Search reads only the same catalog that fetch can return.
            try
            {
                return pair.Key.Contains(query, StringComparison.OrdinalIgnoreCase) ||
                    pair.Value.Path.Contains(query, StringComparison.OrdinalIgnoreCase) ||
                    pair.Value.Title.Contains(query, StringComparison.OrdinalIgnoreCase) ||
                    ReadFixedFile(pair.Value.Path).Contains(query, StringComparison.OrdinalIgnoreCase);
            }
            catch (McpException) { return false; }
        }).Select(pair => new { id = pair.Key, title = pair.Value.Title, url = DocumentUrl(pair.Value.Path) });
        return JsonSerializer.Serialize(new { results = matches.ToArray() });
    }

    public string ReadFixedFile(string relativePath)
    {
        var path = ResolveFixedFile(relativePath);
        try
        {
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
            if (stream.Length > MaxDocumentBytes) throw new McpException("The project document exceeds the remote size limit.");
            // Enforce the limit during read too; a file may grow after its initial length check.
            var bytes = new byte[MaxDocumentBytes + 1];
            var read = 0;
            while (read < bytes.Length)
            {
                var count = stream.Read(bytes, read, bytes.Length - read);
                if (count == 0) break;
                read += count;
            }
            if (read > MaxDocumentBytes) throw new McpException("The project document exceeds the remote size limit.");
            return new UTF8Encoding(false, true).GetString(bytes, 0, read);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or DecoderFallbackException)
        {
            throw new McpException("The allowed project document is unavailable.");
        }
    }

    private string ResolveFixedFile(string relativePath)
    {
        if (!Documents.Values.Any(document => document.Path == relativePath) && relativePath != "config/aihub.json")
            throw new McpException("This file is outside the remote catalog.");
        var current = options.RepositoryRoot;
        // The operator supplies the trusted root; no component beneath it may redirect
        // reads outside it. A concurrently writable checkout is not a supported host.
        try
        {
            foreach (var component in relativePath.Split('/'))
            {
                current = Path.Combine(current, component);
                if ((File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                    throw new McpException("Linked project documents are not served remotely.");
            }
            return current;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            throw new McpException("The allowed project document is unavailable.");
        }
    }

    public string TaskRouting()
    {
        try
        {
            using var doc = JsonDocument.Parse(ReadFixedFile("config/aihub.json"));
            var routing = doc.RootElement.GetProperty("routing");
            return JsonSerializer.Serialize(new
            {
                defaultChain = routing.GetProperty("defaultChain"),
                taskRouting = routing.GetProperty("taskRouting"),
                source = "config/aihub.json", liveInferenceVerified = false,
            });
        }
        catch (Exception ex) when (ex is JsonException or KeyNotFoundException or InvalidOperationException)
        {
            throw new McpException("The routing configuration is unavailable or malformed.");
        }
    }

    public string FabricPlan()
    {
        try
        {
            var contract = JsonSerializer.Deserialize<FabricContract>(ReadFixedFile("config/fabric/helios-fabric.v1.json"))
                ?? throw new JsonException();
            // Reuse the current C# core planner, with no caller-supplied file or rename override.
            var plan = new FabricPlanService().BuildPlan(contract, renameCompleted: false);
            return JsonSerializer.Serialize(new { plan, source = "config/fabric/helios-fabric.v1.json", advisory = true });
        }
        catch (JsonException) { throw new McpException("The Fabric contract is malformed."); }
    }

    public string FleetReadiness()
    {
        try
        {
            var text = ReadFixedFile("config/fleet/fleet-topology.json");
            var topology = JsonSerializer.Deserialize<FleetTopology>(text,
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true }) ?? throw new JsonException();
            return JsonSerializer.Serialize(new
            {
                plan = FleetReadinessService.Plan(topology),
                source = "config/fleet/fleet-topology.json",
                sha256 = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text))).ToLowerInvariant(),
                advisory = true,
            });
        }
        catch (JsonException) { throw new McpException("The fleet topology is malformed."); }
    }

    private static string DocumentUrl(string path) => $"https://github.com/Yolkster64/helios-platform/blob/main/{path}";
}
