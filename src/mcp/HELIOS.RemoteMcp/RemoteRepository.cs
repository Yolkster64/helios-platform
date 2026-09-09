using System.Text;
using System.Text.Json;
using HELIOS.AIHub.Fabric;
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
        };

    public string Fetch(string id)
    {
        if (string.IsNullOrEmpty(id) || !Documents.TryGetValue(id, out var document))
            throw new McpException("Unknown document ID. Use search to find an allowed HELIOS document.");
        return JsonSerializer.Serialize(new
        {
            id, title = document.Title, text = ReadFixedFile(document.Path),
            url = DocumentUrl(document.Path),
            metadata = new { path = document.Path, source = "trusted checkout", liveServiceReceipt = false },
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
                return pair.Value.Title.Contains(query, StringComparison.OrdinalIgnoreCase) ||
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

    private static string DocumentUrl(string path) => $"https://github.com/Yolkster64/helios-platform/blob/main/{path}";
}
