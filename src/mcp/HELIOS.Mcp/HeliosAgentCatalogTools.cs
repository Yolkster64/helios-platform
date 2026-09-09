using System.ComponentModel;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using HELIOS.AIHub.Configuration;
using HELIOS.AIHub.Routing;
using ModelContextProtocol;
using ModelContextProtocol.Server;

namespace HELIOS.Mcp;

/// <summary>Shared project instructions and deterministic task templates; no dispatcher.</summary>
public sealed class HeliosAgentCatalogStore
{
    public const string CatalogPath = "config/agent-catalog.json";
    public const string SchemaPath = "config/schemas/agent-catalog.schema.json";
    public const string SkillPath = "plugins/helios-connect/skills/helios-work/SKILL.md";
    private readonly string _root;

    public HeliosAgentCatalogStore(string root)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(root) || root.Length > 4096)
                throw new McpException("A trusted HELIOS checkout is required for shared task instructions.");
            _root = Path.GetFullPath(root);
            var depth = 0;
            for (var directory = new DirectoryInfo(_root); directory is not null; directory = directory.Parent)
            {
                if (++depth > 128)
                    throw new McpException("A trusted HELIOS checkout is required for shared task instructions.");
                RejectLinkedPath(directory.FullName);
            }
            var marker = Path.Combine(_root, "AGENTS.md");
            RejectLinkedPath(marker);
            if (!Directory.Exists(_root) || !File.Exists(marker))
                throw new McpException("A trusted HELIOS checkout is required for shared task instructions.");
        }
        catch (Exception ex) when (ex is ArgumentException or IOException or UnauthorizedAccessException or NotSupportedException)
        {
            throw new McpException("A trusted HELIOS checkout is required for shared task instructions.");
        }
    }

    public static HeliosAgentCatalogStore CreateDefault()
    {
        var configured = Environment.GetEnvironmentVariable("HELIOS_REPO_ROOT");
        if (!string.IsNullOrWhiteSpace(configured)) return new(configured);
        for (var directory = new DirectoryInfo(Environment.CurrentDirectory); directory is not null; directory = directory.Parent)
            if (File.Exists(Path.Combine(directory.FullName, "AGENTS.md"))) return new(directory.FullName);
        throw new McpException("Set HELIOS_REPO_ROOT to the trusted HELIOS checkout.");
    }

    public string Catalog()
    {
        using var catalog = ReadCatalog();
        var root = catalog.RootElement;
        var routing = ReadRouting();
        return JsonSerializer.Serialize(new
        {
            projectId = root.GetProperty("projectId"), roles = root.GetProperty("roles"),
            tasks = root.GetProperty("tasks"), sources = root.GetProperty("sources"),
            agentProfiles = ListProfiles(".claude/agents", directorySkills: false),
            skills = ListProfiles(".claude/skills", directorySkills: true),
            routingSource = "config/aihub.json", customProfileApplied = false,
            configuredTaskRouting = new { defaultChain = routing.DefaultChain, taskRouting = routing.TaskRouting },
            runtimeVerified = false, automaticExecution = false,
            note = "Shared definitions and configured routes; native subagent activation and runtime credentials remain client-specific.",
        });
    }

    public string TaskPacket(string taskKind, string? language = null)
    {
        if (taskKind is not ("implement" or "review" or "hybrid-plan" or "fleet-plan"))
            throw new McpException("taskKind must be implement, review, hybrid-plan, or fleet-plan.");
        if (language is not null && language.Length > 32)
            throw new McpException("language must be a short language name.");
        var normalized = TaskTypeRoutingStrategy.NormalizeLanguage(language);
        if (normalized is not null && normalized.Any(c => !char.IsAsciiLetterOrDigit(c) && c is not ('_' or '-')))
            throw new McpException("language must be a language name, not a path or command.");
        using var catalog = ReadCatalog();
        var task = catalog.RootElement.GetProperty("tasks").GetProperty(taskKind);
        var routeTaskType = task.GetProperty("routeTaskType").GetString()!;
        // Use the current core routing algorithm without constructing providers,
        // reading credential stores, invoking models, or recording learning outcomes.
        var route = new TaskTypeRoutingStrategy(ReadRouting()).ResolveChain(routeTaskType, normalized);
        var instructions = ReadFixed(SkillPath, 32 * 1024);
        var sources = catalog.RootElement.GetProperty("sources");
        var references = task.GetProperty("sourceKeys").EnumerateArray().Select(item =>
        {
            var key = item.GetString()!;
            return new { key, path = sources.GetProperty(key).GetString() };
        }).ToArray();
        return JsonSerializer.Serialize(new
        {
            projectId = "helios-control", taskKind, language = normalized,
            routingSource = "config/aihub.json", customProfileApplied = false,
            routeTaskType, configuredChain = route.Chain, resolvedRouteKey = route.ResolvedKey,
            suggestedRole = task.GetProperty("suggestedRole"),
            instructions = new
            {
                path = SkillPath, text = instructions,
                sha256 = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(instructions))).ToLowerInvariant(),
            },
            sourceRefs = references, steps = task.GetProperty("steps"), readinessNotes = task.GetProperty("readinessNotes"),
            handoffContract = new
            {
                submitTool = "helios_handoff_submit", listTool = "helios_handoff_list", fetchTool = "helios_handoff_fetch",
                required = new[] { "handoffId", "correlationId", "recipient", "note" },
                optional = new[] { "sourceSha" }, recipients = catalog.RootElement.GetProperty("roles"),
                idFormat = "new UUIDs for new work; same handoffId for retry", maxNoteBytes = HeliosHandoffStore.MaxNoteBytes,
                sourceClaims = "caller-supplied; not authenticated identity", automaticExecution = false,
            },
            runtimeVerified = false, automaticExecution = false,
            note = "A task template and configured route, not a saved task, running agent, provider call, or cloud deployment.",
        });
    }

    private JsonDocument ReadCatalog()
    {
        JsonDocument? catalog = null;
        try
        {
            catalog = JsonDocument.Parse(ReadFixed(CatalogPath, 32 * 1024));
            using var schema = JsonDocument.Parse(ReadFixed(SchemaPath, 32 * 1024));
            if (JsonSchemaLite.Validate(schema.RootElement, catalog.RootElement).Count > 0)
                throw new McpException("The shared agent catalog does not match its checked-in schema.");
            return catalog;
        }
        catch (Exception ex) when (ex is JsonException or JsonSchemaLite.SchemaException or InvalidOperationException)
        {
            catalog?.Dispose();
            throw new McpException("The shared agent catalog or schema is invalid.");
        }
        catch { catalog?.Dispose(); throw; }
    }

    private RoutingOptions ReadRouting()
    {
        try
        {
            using var document = JsonDocument.Parse(ReadFixed("config/aihub.json", 128 * 1024));
            var routing = document.RootElement.GetProperty("routing").Deserialize<RoutingOptions>() ?? throw new JsonException();
            if (routing.DefaultChain is null || routing.TaskRouting is null ||
                routing.TaskRouting.Any(pair => pair.Value is null) ||
                routing.DefaultChain.Concat(routing.TaskRouting.Values.SelectMany(chain => chain)).Any(name =>
                    string.IsNullOrEmpty(name) || name.Length > 100 || name.Any(c => !char.IsAsciiLetterOrDigit(c) && c is not ('-' or '_'))))
                throw new JsonException();
            return routing;
        }
        catch (Exception ex) when (ex is JsonException or KeyNotFoundException or InvalidOperationException)
        {
            throw new McpException("The configured task routing table is unavailable or malformed.");
        }
    }

    private object[] ListProfiles(string relativeDirectory, bool directorySkills)
    {
        var directory = Resolve(relativeDirectory);
        if (!Directory.Exists(directory)) return [];
        try
        {
            var entries = Directory.EnumerateFileSystemEntries(directory).Take(65).ToArray();
            if (entries.Length > 64) throw new McpException("The shared profile directory exceeds the catalog limit.");
            var paths = new List<object>();
            foreach (var entry in entries.Order(StringComparer.Ordinal))
            {
                var name = Path.GetFileName(entry);
                if (directorySkills ? !Directory.Exists(entry) : !name.EndsWith(".md", StringComparison.Ordinal)) continue;
                var id = directorySkills ? name : Path.GetFileNameWithoutExtension(name);
                if (id.Length is < 1 or > 64 || id.Any(c => !char.IsAsciiLetterOrDigit(c) && c is not ('-' or '_'))) continue;
                var relative = directorySkills ? $"{relativeDirectory}/{name}/SKILL.md" : $"{relativeDirectory}/{name}";
                var path = Resolve(relative);
                if (File.Exists(path)) paths.Add(new { name = id, path = relative, nativeActivation = "client-specific" });
            }
            return paths.ToArray();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            throw new McpException("The shared profile catalog is unavailable.");
        }
    }

    private string ReadFixed(string relative, int limit)
    {
        if (relative is not (CatalogPath or SchemaPath or SkillPath or "config/aihub.json"))
            throw new McpException("This file is outside the shared instruction catalog.");
        try
        {
            using var stream = new FileStream(Resolve(relative), FileMode.Open, FileAccess.Read, FileShare.Read);
            var buffer = new byte[limit + 1];
            var size = stream.ReadAtLeast(buffer, buffer.Length, throwOnEndOfStream: false);
            if (size > limit) throw new McpException("The shared instruction source exceeds its size limit.");
            return new UTF8Encoding(false, true).GetString(buffer, 0, size);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or DecoderFallbackException)
        {
            throw new McpException("A shared instruction source is unavailable.");
        }
    }

    private string Resolve(string relative)
    {
        var path = _root;
        foreach (var component in relative.Split('/'))
        {
            if (component is "" or "." or "..") throw new McpException("Invalid shared source path.");
            path = Path.Combine(path, component);
            RejectLinkedPath(path);
        }
        return path;
    }

    private static void RejectLinkedPath(string path)
    {
        if (new FileInfo(path).LinkTarget is not null || new DirectoryInfo(path).LinkTarget is not null ||
            ((File.Exists(path) || Directory.Exists(path)) && (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0))
            throw new McpException("Linked shared instruction sources are not permitted.");
    }
}

[McpServerToolType]
public static class HeliosAgentCatalogTools
{
    [McpServerTool(Name = "helios_agent_catalog_get", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description("Read the shared HELIOS roles, task templates, skills, agent profiles, source references and configured task routing. Definitions are portable; native subagent activation is client-specific. No model, command, worker, or cloud operation is invoked.")]
    public static string GetCatalog() => HeliosAgentCatalogStore.CreateDefault().Catalog();

    [McpServerTool(Name = "helios_task_packet_get", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description("Read a deterministic task template for implement, review, hybrid-plan, or fleet-plan, including the shared helios-work skill text/hash, existing language-aware routing chain, source references, steps and handoff contract. Creates no task, process, model call, or deployment.")]
    public static string GetTaskPacket(string taskKind, string? language = null) =>
        HeliosAgentCatalogStore.CreateDefault().TaskPacket(taskKind, language);
}
