using System.ComponentModel;
using System.Text.Json;
using System.Text.Json.Serialization;
using HELIOS.AIHub.Configuration;
using ModelContextProtocol;
using ModelContextProtocol.Server;

namespace HELIOS.Mcp;

/// <summary>
/// Read-only config authoring tool: validates one repo-relative manifest against the
/// JSON Schema config/schemas/manifests.json maps it to (the same map
/// scripts/validation/validate_config_schemas.py and .vscode/settings.json use), with
/// the dependency-free <see cref="JsonSchemaLite"/> engine. Nothing here applies,
/// fetches, or rewrites anything — it only reports. Repo root resolution follows the
/// operator tools: HELIOS_REPO_ROOT / CLAUDE_PROJECT_DIR when they point at a
/// checkout, else walk up to config/aihub.json via
/// <see cref="AIHubOptions.FindConfigFile"/>.
/// </summary>
[McpServerToolType]
public static class HeliosConfigTools
{
    private const string MappingRelativePath = "config/schemas/manifests.json";

    private static readonly JsonSerializerOptions WriteOptions = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    [McpServerTool(Name = "helios_config_validate", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description("Validate one repo-relative config manifest (config/github/labels.json, config/github/milestones.json, config/connectors.json, config/fork-watch.json, config/absorption/pr-watchlist.json, config/fleet/fleet-topology.json, config/aihub.json, ...) against the JSON Schema config/schemas/manifests.json maps it to. Returns { path, schema, valid, errors: [{ path, message }] } with every error and its JSON path. Read-only and local: applies nothing, rewrites nothing, no network.")]
    public static string ValidateConfig(
        [Description("Repo-relative manifest path with forward slashes, e.g. config/github/labels.json. Absolute paths and '..' segments are refused.")]
        string path,
        [Description("Optional repo-relative schema to use instead of the mapped one (e.g. config/schemas/github-labels.schema.json for a draft copied from templates/). Same path rules; required for a file that has no mapping.")]
        string? schemaPath = null)
        => BuildValidationJson(path, schemaPath, startDirectory: null);

    /// <summary>
    /// Core of helios_config_validate, split out so tests can point it at a fabricated
    /// repo root. <paramref name="startDirectory"/> = null means "resolve from the
    /// environment / process location", exactly like the other tools.
    /// </summary>
    public static string BuildValidationJson(string path, string? schemaPath, string? startDirectory)
    {
        var repoRoot = ResolveRepoRoot(startDirectory);
        var manifestRelative = NormalizeRepoRelative(path, "path");
        var manifestFull = ResolveInsideRepo(repoRoot, manifestRelative, "path");
        if (!File.Exists(manifestFull))
        {
            throw new McpException(
                $"'{manifestRelative}' does not exist under '{repoRoot}'. Pass a repo-relative manifest path such as " +
                $"config/github/labels.json (the mapped files are listed in {MappingRelativePath}).");
        }

        string schemaRelative;
        if (string.IsNullOrWhiteSpace(schemaPath))
        {
            schemaRelative = LookupMappedSchema(repoRoot, manifestRelative)
                ?? throw new McpException(
                    $"No schema is mapped for '{manifestRelative}' in {MappingRelativePath}. Add a mapping there, or pass " +
                    "schemaPath (e.g. config/schemas/github-labels.schema.json) to validate a draft explicitly.");
        }
        else
        {
            schemaRelative = NormalizeRepoRelative(schemaPath, "schemaPath");
        }
        var schemaFull = ResolveInsideRepo(repoRoot, schemaRelative, "schemaPath");
        if (!File.Exists(schemaFull))
        {
            throw new McpException(
                $"Schema '{schemaRelative}' does not exist under '{repoRoot}'. Schemas live in config/schemas/ and are named " +
                $"in {MappingRelativePath}.");
        }

        using var schemaDocument = ParseSchema(schemaFull, schemaRelative);
        var errors = new List<JsonSchemaLite.Issue>();
        try
        {
            using var stream = File.OpenRead(manifestFull);
            using var manifestDocument = JsonDocument.Parse(stream);
            errors.AddRange(JsonSchemaLite.Validate(schemaDocument.RootElement, manifestDocument.RootElement));
        }
        catch (JsonException ex)
        {
            // A manifest that is not JSON is an invalid manifest, not a broken call.
            errors.Add(new JsonSchemaLite.Issue("$", $"invalid JSON: {ex.Message}"));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            throw new McpException($"Failed to read '{manifestRelative}': {ex.Message}");
        }

        return JsonSerializer.Serialize(new ValidationResult
        {
            Path = manifestRelative,
            Schema = schemaRelative,
            Valid = errors.Count == 0,
            Errors = errors.Select(issue => new ValidationError { Path = issue.Path, Message = issue.Message }).ToList(),
        }, WriteOptions);
    }

    private static JsonDocument ParseSchema(string schemaFull, string schemaRelative)
    {
        JsonDocument document;
        try
        {
            using var stream = File.OpenRead(schemaFull);
            document = JsonDocument.Parse(stream);
        }
        catch (Exception ex) when (ex is JsonException or IOException or UnauthorizedAccessException)
        {
            throw new McpException($"Schema '{schemaRelative}' could not be read as JSON: {ex.Message}");
        }

        try
        {
            JsonSchemaLite.CheckSchema(document.RootElement);
        }
        catch (JsonSchemaLite.SchemaException ex)
        {
            document.Dispose();
            throw new McpException($"Schema '{schemaRelative}' is not usable: {ex.Message}");
        }
        return document;
    }

    private static string? LookupMappedSchema(string repoRoot, string manifestRelative)
    {
        var mappingFull = Path.Combine(repoRoot, "config", "schemas", "manifests.json");
        if (!File.Exists(mappingFull))
        {
            throw new McpException(
                $"'{MappingRelativePath}' is missing under '{repoRoot}' — the manifest-to-schema map is required to resolve a schema. " +
                "Pass schemaPath explicitly or restore the map.");
        }

        try
        {
            using var stream = File.OpenRead(mappingFull);
            using var document = JsonDocument.Parse(stream);
            if (!document.RootElement.TryGetProperty("mappings", out var mappings) || mappings.ValueKind != JsonValueKind.Array)
            {
                throw new McpException($"'{MappingRelativePath}' has no 'mappings' array.");
            }
            foreach (var mapping in mappings.EnumerateArray())
            {
                if (mapping.ValueKind != JsonValueKind.Object
                    || !mapping.TryGetProperty("manifest", out var manifest)
                    || !mapping.TryGetProperty("schema", out var schema)
                    || manifest.ValueKind != JsonValueKind.String
                    || schema.ValueKind != JsonValueKind.String)
                {
                    continue;
                }
                if (string.Equals(manifest.GetString(), manifestRelative, StringComparison.OrdinalIgnoreCase))
                {
                    return schema.GetString();
                }
            }
            return null;
        }
        catch (Exception ex) when (ex is JsonException or IOException or UnauthorizedAccessException)
        {
            throw new McpException($"'{MappingRelativePath}' could not be read: {ex.Message}");
        }
    }

    /// <summary>
    /// Accepts only a relative, forward-slash path that stays inside the checkout: no
    /// drive or root prefix, no '..' segment (even one that would resolve back inside).
    /// </summary>
    private static string NormalizeRepoRelative(string? value, string parameterName)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new McpException($"{parameterName} is required: a repo-relative path such as config/github/labels.json.");
        }
        var normalized = value.Trim().Replace('\\', '/');
        if (normalized.StartsWith("./", StringComparison.Ordinal))
        {
            normalized = normalized[2..];
        }
        if (Path.IsPathRooted(normalized) || normalized.StartsWith('/') || normalized.Contains(':'))
        {
            throw new McpException(
                $"{parameterName} must be repo-relative (got '{value}'); absolute paths are refused so the tool only ever reads inside the checkout.");
        }
        var segments = normalized.Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (segments.Length == 0 || segments.Any(segment => segment == ".." || segment == "."))
        {
            throw new McpException(
                $"{parameterName} must not contain '.' or '..' segments (got '{value}'); use the repo-relative path such as config/github/labels.json.");
        }
        return string.Join('/', segments);
    }

    private static string ResolveInsideRepo(string repoRoot, string relative, string parameterName)
    {
        var rootFull = Path.GetFullPath(repoRoot).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var full = Path.GetFullPath(Path.Combine(rootFull, relative.Replace('/', Path.DirectorySeparatorChar)));
        var prefix = rootFull + Path.DirectorySeparatorChar;
        if (!full.StartsWith(prefix, StringComparison.Ordinal))
        {
            throw new McpException($"{parameterName} '{relative}' resolves outside the checkout '{rootFull}' and was refused.");
        }
        return full;
    }

    private static string ResolveRepoRoot(string? startDirectory)
    {
        if (startDirectory is null)
        {
            foreach (var variable in new[] { "HELIOS_REPO_ROOT", "CLAUDE_PROJECT_DIR" })
            {
                var candidate = Environment.GetEnvironmentVariable(variable);
                if (!string.IsNullOrWhiteSpace(candidate))
                {
                    var fullPath = Path.GetFullPath(candidate);
                    if (File.Exists(Path.Combine(fullPath, "config", "aihub.json")))
                    {
                        return fullPath;
                    }
                }
            }
        }

        var configPath = AIHubOptions.FindConfigFile(startDirectory)
            ?? throw new McpException(
                "Repo root not found (no config/aihub.json in any parent directory). Start the client in the helios-platform checkout or set HELIOS_REPO_ROOT.");
        return Directory.GetParent(Path.GetDirectoryName(configPath)!)!.FullName;
    }

    private sealed class ValidationResult
    {
        [JsonPropertyName("path")]
        public string Path { get; init; } = "";

        [JsonPropertyName("schema")]
        public string Schema { get; init; } = "";

        [JsonPropertyName("valid")]
        public bool Valid { get; init; }

        [JsonPropertyName("errors")]
        public List<ValidationError> Errors { get; init; } = new();
    }

    private sealed class ValidationError
    {
        [JsonPropertyName("path")]
        public string Path { get; init; } = "";

        [JsonPropertyName("message")]
        public string Message { get; init; } = "";
    }
}
