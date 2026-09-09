using System.Text.RegularExpressions;
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
            errors.AddRange(ManifestSemantics.Check(schemaDocument.RootElement, manifestDocument.RootElement, schemaRelative));
        }
        catch (JsonException ex)
        {
            // A manifest that is not JSON is an invalid manifest, not a broken call.
            errors.Add(new JsonSchemaLite.Issue("$", $"invalid JSON: {ex.Message}"));
        }
        catch (Exception ex) when (ex is JsonSchemaLite.SchemaException or InvalidOperationException
                                   or FormatException or ArgumentException or RegexMatchTimeoutException)
        {
            // The schema self-check catches unknown keywords; a $ref cycle, a keyword with a value
            // of the wrong shape or a pattern that cannot run surfaces only while validating.
            // Still the schema's fault, still an actionable error rather than a raw exception.
            throw new McpException($"Schema '{schemaRelative}' is not usable: {ex.Message}");
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
            // Every entry is read, not just the first match: a manifest mapped twice would give the
            // sweep (which validates both) and this tool (which would stop at the first) two verdicts
            // for one file, so an ambiguous map is refused here exactly as load_mappings refuses it.
            string? found = null;
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
                if (string.Equals(ManifestSemantics.NormalizeManifestKey(manifest.GetString()!), manifestRelative, StringComparison.OrdinalIgnoreCase))
                {
                    if (found is not null)
                    {
                        throw new McpException(
                            $"'{MappingRelativePath}' maps '{manifestRelative}' twice ('{found}' and '{schema.GetString()}'); a manifest has exactly one schema — fix the map before validating.");
                    }
                    found = schema.GetString();
                }
            }
            return found;
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

        // GetFullPath never follows links, so a symbolic link planted inside the checkout — a
        // directory on the way or the file itself — could hand the tool a file outside it.
        // Every existing component is checked; a link must land inside the checkout too.
        var cursor = rootFull;
        foreach (var segment in relative.Split('/', StringSplitOptions.RemoveEmptyEntries))
        {
            cursor = Path.Combine(cursor, segment);
            FileSystemInfo info = Directory.Exists(cursor) ? new DirectoryInfo(cursor) : new FileInfo(cursor);
            if (!info.Exists)
            {
                break;
            }
            if (info.LinkTarget is not null)
            {
                var target = info.ResolveLinkTarget(returnFinalTarget: true)?.FullName;
                if (target is null || !Path.GetFullPath(target).StartsWith(prefix, StringComparison.Ordinal))
                {
                    throw new McpException($"{parameterName} '{relative}' goes through a symbolic link that leaves the checkout '{rootFull}' and was refused.");
                }
            }
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

/// <summary>
/// Rules a JSON Schema cannot express, keyed by the schema's <c>$id</c>. Mirrors
/// <c>_SEMANTIC_CHECKS</c> in scripts/validation/validate_config_schemas.py so this tool, the CLI
/// and CI give one verdict.
/// </summary>
internal static class ManifestSemantics
{
    /// <summary>
    /// The rules for a schema, chosen by the schema FILE this checkout ships. The $id inside a
    /// schema is editable data: keying on it meant that removing or mistyping one line switched
    /// every semantic rule off while ordinary validation still passed. The file name comes from the
    /// trusted map (or from an explicit schemaPath, which ResolveInsideRepo has already confined);
    /// the $id is a fallback for a schema that carries one but sits elsewhere.
    /// </summary>
    public static IReadOnlyList<JsonSchemaLite.Issue> Check(JsonElement schema, JsonElement instance, string schemaRelativePath = "")
    {
        // A file name alone is not identity — any directory can hold a file called
        // aihub.schema.json — so the name counts only for a schema under this checkout's
        // config/schemas/. Anything else is selected by its HELIOS $id or not at all, which is
        // also what the Python twin's _semantics_for does.
        var path = schemaRelativePath.Replace('\\', '/');
        var name = path.StartsWith("config/schemas/", StringComparison.Ordinal)
                   && path.LastIndexOf('/') == "config/schemas".Length
            ? path[(path.LastIndexOf('/') + 1)..]
            : "";
        if (!SemanticNames.Contains(name)
            && schema.ValueKind == JsonValueKind.Object
            && schema.TryGetProperty("$id", out var id) && id.ValueKind == JsonValueKind.String)
        {
            var identifier = id.GetString() ?? "";
            name = identifier.StartsWith("helios://config/schemas/", StringComparison.Ordinal)
                ? identifier[(identifier.LastIndexOf('/') + 1)..]
                : name;
        }
        // Every manifest, whatever its schema: the Python engine refuses a number outside double
        // range while READING the file, so a value the C# walk never reaches (an unknown property,
        // or a schema that says `true`) must not make one engine call the file valid and the other
        // unreadable.
        var universal = NumbersWithinDoubleRange(instance);
        return name switch
        {
            "aihub.schema.json" => universal.Concat(AihubNames(instance)).Concat(AihubBaseUrls(instance))
                .Concat(AihubChains(instance)).Concat(AihubKeys(instance)).ToList(),

            "github-labels.schema.json" => universal.Concat(LabelNames(instance)).ToList(),
            "manifests.schema.json" => universal.Concat(MappingKeys(instance)).ToList(),
            "github-milestones.schema.json" => universal.Concat(MilestoneTitles(instance)).ToList(),
            "fleet-topology.schema.json" => universal.Concat(FleetPoolNames(instance))
                .Concat(FleetAssigneePrefixes(instance)).Concat(FleetCapacity(instance)).ToList(),
            "fork-watch.schema.json" => universal.Concat(ForkWatchReasons(instance)).ToList(),
            "absorption-pr-watchlist.schema.json" => universal.Concat(WatchlistCandidates(instance)).ToList(),
            "model-catalog.schema.json" => universal.Concat(ModelCatalogPairs(instance)).ToList(),
            "helios-fabric.v1.schema.json" => universal.Concat(FabricSecrets(instance)).ToList(),
            _ => universal,
        };
    }

    /// <summary>
    /// Every number in the document, wherever it sits, must be one a consumer can hold: 1e400
    /// parses as a JsonElement but binds to no double, and the Python engine refuses the token
    /// while reading the file rather than while validating a keyword.
    /// </summary>
    private static List<JsonSchemaLite.Issue> NumbersWithinDoubleRange(JsonElement instance)
    {
        var issues = new List<JsonSchemaLite.Issue>();
        Walk(instance, "$");
        return issues;

        void Walk(JsonElement node, string path)
        {
            switch (node.ValueKind)
            {
                case JsonValueKind.Number when !JsonSchemaLite.IsFiniteNumber(node):
                    issues.Add(new JsonSchemaLite.Issue(path,
                        $"{node.GetRawText()} is out of range for a JSON number: no consumer of this manifest can hold it"));
                    break;
                case JsonValueKind.Object:
                    foreach (var member in node.EnumerateObject())
                    {
                        Walk(member.Value, $"{path}.{member.Name}");
                    }
                    break;
                case JsonValueKind.Array:
                    var index = 0;
                    foreach (var item in node.EnumerateArray())
                    {
                        Walk(item, $"{path}[{index++}]");
                    }
                    break;
            }
        }
    }

    private static readonly HashSet<string> SemanticNames = new(StringComparer.Ordinal)
    {
        "aihub.schema.json", "github-labels.schema.json", "manifests.schema.json",
        "github-milestones.schema.json", "fleet-topology.schema.json", "absorption-pr-watchlist.schema.json",
        "model-catalog.schema.json", "helios-fabric.v1.schema.json", "fork-watch.schema.json",
    };

    /// <summary>
    /// An assignee prefix is an identity: start-fleet.ps1 defaults it to the pool name and names
    /// every worker "&lt;prefix&gt;-&lt;n&gt;", deriving its per-run log path from that name. Two pools
    /// resolving to one prefix — by declaring the same one, or by one declaring another's name —
    /// give distinct workers the same identity and the same files to write.
    /// </summary>
    private static List<JsonSchemaLite.Issue> FleetAssigneePrefixes(JsonElement instance)
    {
        var issues = new List<JsonSchemaLite.Issue>();
        if (instance.ValueKind != JsonValueKind.Object
            || !instance.TryGetProperty("pools", out var pools)
            || pools.ValueKind != JsonValueKind.Array)
        {
            return issues;
        }
        var seen = new Dictionary<string, (int Index, string Name)>(StringComparer.OrdinalIgnoreCase);
        var index = 0;
        foreach (var pool in pools.EnumerateArray())
        {
            var position = index++;
            if (pool.ValueKind != JsonValueKind.Object)
            {
                continue;
            }
            var name = Text(pool, "name") ?? "";
            var prefix = Text(pool, "assigneePrefix") ?? Text(pool, "name");
            if (prefix is null)
            {
                continue;
            }
            // A duplicate NAME already collides by FleetPoolNames and would report the same pair
            // twice; this rule is for the collision a name check cannot see.
            if (seen.TryGetValue(prefix, out var owner)
                && !string.Equals(owner.Name, name, StringComparison.OrdinalIgnoreCase))
            {
                var first = owner.Index;
                issues.Add(new JsonSchemaLite.Issue($"$.pools[{position}].assigneePrefix",
                    $"'{prefix}' is already the effective assignee prefix of pool {first}; start-fleet.ps1 " +
                    "names every worker '<prefix>-<n>' and derives its log path from that"));
            }
            else
            {
                seen.TryAdd(prefix, (position, name));
            }
        }
        return issues;

        static string? Text(JsonElement node, string name) =>
            node.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String
            && value.GetString() is { Length: > 0 } text ? text : null;
    }

    /// <summary>
    /// `because` must be non-blank the way its consumer reads it. fork-observation.yml's preflight
    /// calls Python's Unicode-aware str.strip() and refuses the entry when nothing is left; the
    /// schema's <c>\S</c> is compiled with ASCII semantics — it has to be, so the three engines
    /// share one dialect — and a non-breaking or em space satisfies it, so the required gate
    /// approved a manifest the workflow then rejected.
    /// </summary>
    private static List<JsonSchemaLite.Issue> ForkWatchReasons(JsonElement instance)
    {
        var issues = new List<JsonSchemaLite.Issue>();
        if (instance.ValueKind != JsonValueKind.Object
            || !instance.TryGetProperty("repos", out var repos)
            || repos.ValueKind != JsonValueKind.Array)
        {
            return issues;
        }
        var index = 0;
        foreach (var entry in repos.EnumerateArray())
        {
            var position = index++;
            if (entry.ValueKind != JsonValueKind.Object
                || !entry.TryGetProperty("because", out var because)
                || because.ValueKind != JsonValueKind.String)
            {
                continue;
            }
            var text = because.GetString() ?? "";
            if (text.Length > 0 && string.IsNullOrWhiteSpace(text))
            {
                issues.Add(new JsonSchemaLite.Issue($"$.repos[{position}].because",
                    "is only whitespace once Unicode spaces are counted; fork-observation.yml's preflight " +
                    "reads it with str.strip() and refuses the entry"));
            }
        }
        return issues;
    }

    // What the fleet may attempt across ALL pools, not per pool. Every per-field ceiling in the
    // topology schema is per pool, and `helios-fleet start` selects every pool by default: 100
    // pools of 64 workers passed both validators and asked one host for 6,400 processes.
    // scale-fleet.ps1 likewise sums each pool's burst lanes into ONE absolute
    // `az vmss scale --new-capacity`, so the aggregate is what bills. Four times the 64-process
    // ceiling start-fleet.ps1 enforces on one pool, and twice the 256-lane ceiling one pool may
    // request. The Python twin (_check_fleet_capacity) carries the same two numbers.
    private const long MaxFleetLocalWorkers = 256;
    private const long MaxFleetBurstLanes = 512;

    // The shapes scripts/validation/validate_helios_fabric_contract.py refuses anywhere in the
    // Fabric contract: it records secret NAMES and references, never material, and a token pasted
    // into a free-text field (notes, receiptPath) is the one thing its schema cannot express.
    private static readonly Regex[] SecretShapes =
    {
        new("sk-[A-Za-z0-9]{20,}", RegexOptions.None, TimeSpan.FromSeconds(2)),
        new("gh[pousr]_[A-Za-z0-9]{20,}", RegexOptions.None, TimeSpan.FromSeconds(2)),
        new("xox[baprs]-[A-Za-z0-9-]{20,}", RegexOptions.None, TimeSpan.FromSeconds(2)),
        new("AIza[0-9A-Za-z_-]{35}", RegexOptions.None, TimeSpan.FromSeconds(2)),
        new(@"eyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9._-]{12,}\.[A-Za-z0-9._-]{12,}", RegexOptions.None, TimeSpan.FromSeconds(2)),
        // \x1c-\x1f explicitly: Python's \s covers the file/group/record/unit separators and
        // .NET's does not, and the authoritative Fabric scanner is the Python one — without them a
        // URL carrying U+001C in its userinfo reads as credentials here and as plain text there.
        new(@"https?://[^/\s\x1c-\x1f:@]+:[^/\s\x1c-\x1f@]+@", RegexOptions.None, TimeSpan.FromSeconds(2)),
    };

    /// <summary>
    /// No string in the Fabric contract may look like credential material. The authoritative
    /// validator scans every string; the shared engines are the path this repository advertises for
    /// authoring the contract, and without the rule they answer <c>valid: true</c> for a token
    /// pasted into a note.
    /// </summary>
    private static List<JsonSchemaLite.Issue> FabricSecrets(JsonElement instance)
    {
        var issues = new List<JsonSchemaLite.Issue>();
        Walk(instance, "$");
        return issues;

        void Walk(JsonElement node, string path)
        {
            switch (node.ValueKind)
            {
                case JsonValueKind.String when SecretShapes.Any(shape => shape.IsMatch(node.GetString() ?? "")):
                    issues.Add(new JsonSchemaLite.Issue(path,
                        "contains a secret-like value; the contract stores names and references, never the material itself"));
                    break;
                case JsonValueKind.Object:
                    foreach (var member in node.EnumerateObject())
                    {
                        Walk(member.Value, $"{path}.{member.Name}");
                    }
                    break;
                case JsonValueKind.Array:
                    var index = 0;
                    foreach (var item in node.EnumerateArray())
                    {
                        Walk(item, $"{path}[{index++}]");
                    }
                    break;
            }
        }
    }

    /// <summary>
    /// A model profile's identity is (provider, model), not the whole object. Two profiles
    /// repeating one pair but differing in price or context validate as distinct objects while the
    /// hub reads them as one model twice: ModelCatalog's context filter takes the FIRST match and
    /// preference ranking sees both, so the catalog states two facts for one model.
    /// scripts/build/validate-model-catalog.py already refuses the pair; this is the same rule
    /// where the shared engines can see it.
    /// </summary>
    private static List<JsonSchemaLite.Issue> ModelCatalogPairs(JsonElement instance)
    {
        var issues = new List<JsonSchemaLite.Issue>();
        if (instance.ValueKind != JsonValueKind.Object
            || !instance.TryGetProperty("models", out var models)
            || models.ValueKind != JsonValueKind.Array)
        {
            return issues;
        }
        var seen = new Dictionary<string, int>(StringComparer.Ordinal);
        var index = 0;
        foreach (var entry in models.EnumerateArray())
        {
            var position = index++;
            if (entry.ValueKind != JsonValueKind.Object
                || !entry.TryGetProperty("provider", out var provider) || provider.ValueKind != JsonValueKind.String
                || !entry.TryGetProperty("model", out var model) || model.ValueKind != JsonValueKind.String)
            {
                continue;
            }
            var providerText = provider.GetString()!;
            var modelText = model.GetString()!;
            if (providerText.Length == 0 || modelText.Length == 0)
            {
                continue;
            }
            // '\n' cannot appear in either name unescaped, so it separates the two halves safely.
            var pair = providerText + "\n" + modelText;
            if (seen.TryGetValue(pair, out var first))
            {
                issues.Add(new JsonSchemaLite.Issue($"$.models[{position}]",
                    $"'{providerText}/{modelText}' repeats entry {first}; a provider and model name together identify one profile"));
            }
            else
            {
                seen[pair] = position;
            }
        }
        return issues;
    }

    /// <summary>
    /// The totals the fleet scripts act on: worker processes started on the operator's host, and
    /// burst lanes summed into one VMSS capacity request, resolved the way those scripts resolve
    /// them. What the topology declares is what this bounds — `start-fleet.ps1 -PoolSize N`
    /// overrides every pool's size from the command line and the workspace profile lowers it;
    /// neither is in the file, and an operator typing a flag is making their own decision.
    /// </summary>
    private static List<JsonSchemaLite.Issue> FleetCapacity(JsonElement instance)
    {
        var issues = new List<JsonSchemaLite.Issue>();
        if (instance.ValueKind != JsonValueKind.Object
            || !instance.TryGetProperty("pools", out var pools)
            || pools.ValueKind != JsonValueKind.Array)
        {
            return issues;
        }
        var defaults = Section(instance, "defaults");
        var defaultSize = Capacity(defaults, "poolSize");
        long workers = 0, lanes = 0, burst = 0, count = 0;
        foreach (var pool in pools.EnumerateArray())
        {
            count++;
            if (pool.ValueKind != JsonValueKind.Object)
            {
                continue;
            }
            // start-fleet.ps1's Get-EffectivePoolSize: the pool's poolSize, else the defaults',
            // else 1, then clamped to hermesFleet.maxConcurrentLanes.
            var cap = LaneCap(pool, defaults);
            var size = Capacity(pool, "poolSize") ?? defaultSize ?? 1;
            workers += cap > 0 ? Math.Min(size, cap) : size;

            // scale-fleet.ps1: the merged autoscaling block, where a `cloud` pool holds no local
            // lanes, maxLocalLanes defaults to minLocalLanes (a lone minimum IS the capacity), the
            // lane cap clamps both, and the maximum is raised back to the minimum. No block
            // anywhere means the reconciler skips the pool entirely.
            var own = Section(pool, "autoscaling");
            var inherited = defaults is { } presentDefaults ? Section(presentDefaults, "autoscaling") : null;
            if (own is null && inherited is null)
            {
                continue;
            }
            var mode = Merged(own, inherited, "mode") is { ValueKind: JsonValueKind.String } text
                ? text.GetString()! : "local";
            var minimum = MergedCapacity(own, inherited, "minLocalLanes") ?? 1;
            var maximum = MergedCapacity(own, inherited, "maxLocalLanes") ?? minimum;
            if (mode == "cloud")
            {
                minimum = 0;
                maximum = 0;
            }
            if (cap > 0)
            {
                maximum = Math.Min(maximum, cap);
                minimum = Math.Min(minimum, cap);
            }
            lanes += Math.Max(maximum, minimum);
            if (mode is "hybrid" or "cloud")
            {
                burst += MergedCapacity(own, inherited, "maxBurstLanes") ?? 0;
            }
        }
        if (workers > MaxFleetLocalWorkers)
        {
            issues.Add(new JsonSchemaLite.Issue("$.pools",
                $"{count} pools ask for {workers} worker processes together; start-fleet.ps1 selects every pool " +
                $"by default, and {MaxFleetLocalWorkers} is the ceiling for one host"));
        }
        if (lanes > MaxFleetLocalWorkers)
        {
            issues.Add(new JsonSchemaLite.Issue("$.pools",
                $"maxLocalLanes totals {lanes} across the pools; scale-fleet.ps1 runs a local process per lane, " +
                $"and {MaxFleetLocalWorkers} is the ceiling for one host"));
        }
        if (burst > MaxFleetBurstLanes)
        {
            issues.Add(new JsonSchemaLite.Issue("$.pools",
                $"maxBurstLanes totals {burst} across the pools; scale-fleet.ps1 sums them into one " +
                $"'az vmss scale --new-capacity', and {MaxFleetBurstLanes} is the ceiling for that request"));
        }
        return issues;

        static JsonElement? Section(JsonElement? node, string name) =>
            node is { ValueKind: JsonValueKind.Object } present && present.TryGetProperty(name, out var value)
            && value.ValueKind == JsonValueKind.Object ? value : null;

        // A whole number however it is spelled: 64, 64.0 and 6.4e1 are the 64 PowerShell's [int]
        // cast and the Python engine both read, and TryGetInt64 answers false for the last two.
        static long? Capacity(JsonElement? node, string name) =>
            node is { } present && present.TryGetProperty(name, out var value)
            && JsonSchemaLite.TryGetWholeNumber(value, out var number) ? number : null;

        // Get-PoolAutoscaling merges property by property, the pool's over the defaults'.
        static JsonElement? Merged(JsonElement? own, JsonElement? inherited, string name) =>
            own is { } pool && pool.TryGetProperty(name, out var mine) && mine.ValueKind != JsonValueKind.Null
                ? mine
                : inherited is { } shared && shared.TryGetProperty(name, out var theirs)
                  && theirs.ValueKind != JsonValueKind.Null ? theirs : null;

        static long? MergedCapacity(JsonElement? own, JsonElement? inherited, string name) =>
            Merged(own, inherited, name) is { } value
            && JsonSchemaLite.TryGetWholeNumber(value, out var number) ? number : null;

        // Both scripts read the pool's whole hermesFleet block or the defaults' — never a merge.
        static long LaneCap(JsonElement pool, JsonElement? defaults)
        {
            var hermes = Section(pool, "hermesFleet") ?? Section(defaults, "hermesFleet");
            var cap = Capacity(hermes, "maxConcurrentLanes");
            return cap is > 0 ? cap.Value : 0;
        }
    }

    /// <summary>The properties AIHubOptions and its nested records bind, by canonical spelling.</summary>
    private static readonly Dictionary<string, string[]> AihubSectionKeys = new(StringComparer.Ordinal)
    {
        // $schema and $comment are deliberately absent: nothing binds them, so a differently cased
        // spelling cannot replace a section — it is an unknown key, which this schema tolerates.
        ["$"] = new[] { "providers", "cliAgents", "routing", "learning" },
        ["$.routing"] = new[] { "defaultChain", "taskRouting" },
        ["$.learning"] = new[] { "enabled", "mode", "localPath", "tableEndpointEnv", "adaptiveRouting", "historyWindow" },
    };

    private static readonly string[] AihubProviderKeys =
        { "type", "enabled", "model", "apiKeyEnv", "apiKeySecretName", "endpointEnv", "baseUrl" };

    private static readonly string[] AihubAgentKeys =
        { "name", "enabled", "command", "argsTemplate", "model", "timeoutSeconds" };

    private static List<JsonSchemaLite.Issue> AliasIssues(JsonElement node, string path, string[] canonical)
    {
        var issues = new List<JsonSchemaLite.Issue>();
        if (node.ValueKind != JsonValueKind.Object)
        {
            return issues;
        }
        var known = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var name in canonical)
        {
            known[name] = name;
        }
        foreach (var member in node.EnumerateObject())
        {
            if (known.TryGetValue(member.Name, out var match) && !string.Equals(member.Name, match, StringComparison.Ordinal))
            {
                issues.Add(new JsonSchemaLite.Issue($"{path}.{member.Name}",
                    $"'{member.Name}' differs from '{match}' only by case; the hub's binder folds them together and the later one replaces the earlier"));
            }
        }
        return issues;
    }

    /// <summary>
    /// AIHubOptions.Load binds with PropertyNameCaseInsensitive, so a manifest carrying both
    /// `providers` and `Providers` binds them to one property in source order and the last one
    /// wins - silently replacing a section that validated. The provider map is case-insensitive
    /// for the same reason. Mirrors the Python engine's _check_aihub_keys.
    /// </summary>
    private static List<JsonSchemaLite.Issue> AihubKeys(JsonElement instance)
    {
        var issues = new List<JsonSchemaLite.Issue>();
        if (instance.ValueKind != JsonValueKind.Object)
        {
            return issues;
        }
        foreach (var (path, canonical) in AihubSectionKeys)
        {
            var node = instance;
            if (path != "$" && !instance.TryGetProperty(path[2..], out node))
            {
                continue;
            }
            issues.AddRange(AliasIssues(node, path, canonical));
        }
        if (instance.TryGetProperty("providers", out var providers) && providers.ValueKind == JsonValueKind.Object)
        {
            var seen = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var provider in providers.EnumerateObject())
            {
                if (seen.TryGetValue(provider.Name, out var first))
                {
                    issues.Add(new JsonSchemaLite.Issue($"$.providers.{provider.Name}",
                        $"'{provider.Name}' repeats '{first}'; provider keys are matched case-insensitively"));
                }
                else
                {
                    seen[provider.Name] = provider.Name;
                }
                issues.AddRange(AliasIssues(provider.Value, $"$.providers.{provider.Name}", AihubProviderKeys));
            }
        }
        if (instance.TryGetProperty("cliAgents", out var agents) && agents.ValueKind == JsonValueKind.Array)
        {
            var index = 0;
            foreach (var agent in agents.EnumerateArray())
            {
                issues.AddRange(AliasIssues(agent, $"$.cliAgents[{index++}]", AihubAgentKeys));
            }
        }
        return issues;
    }

    /// <summary>
    /// A candidate's pull-request number is its identity: seed-absorption-tasks.ps1 derives the
    /// task id `absorb-pr-&lt;n&gt;` from it and reads the existing ids once, before the loop, so two
    /// entries with one number are enqueued twice under the same id in a single run.
    /// </summary>
    private static List<JsonSchemaLite.Issue> WatchlistCandidates(JsonElement instance)
    {
        var issues = new List<JsonSchemaLite.Issue>();
        JsonElement candidates;
        if (instance.ValueKind == JsonValueKind.Object && instance.TryGetProperty("candidates", out var listed))
        {
            candidates = listed;
        }
        else
        {
            candidates = instance;
        }
        if (candidates.ValueKind != JsonValueKind.Array)
        {
            return issues;
        }
        var seen = new Dictionary<string, int>(StringComparer.Ordinal);
        var index = 0;
        foreach (var candidate in candidates.EnumerateArray())
        {
            var position = index++;
            // 191 and 191.0 are one pull request: read the number as schema validation reads it,
            // not as one spelling of it.
            if (candidate.ValueKind != JsonValueKind.Object
                || !candidate.TryGetProperty("pr", out var number)
                || number.ValueKind != JsonValueKind.Number
                || !JsonSchemaLite.IsFiniteNumber(number))
            {
                continue;
            }
            var key = JsonSchemaLite.NumberKey(number);
            if (seen.TryGetValue(key, out var first))
            {
                issues.Add(new JsonSchemaLite.Issue($"$.candidates[{position}].pr",
                    $"pull request {number.GetRawText()} repeats entry {first}; both would seed the same absorb-pr task in one run"));
            }
            else
            {
                seen[key] = position;
            }
        }
        return issues;
    }

    /// <summary>Forward slashes, no leading "./" — the same key find_mapping uses.</summary>
    public static string NormalizeManifestKey(string path)
    {
        var key = path.Replace('\\', '/');
        return key.StartsWith("./", StringComparison.Ordinal) ? key[2..] : key;
    }

    /// <summary>
    /// ProviderFactory hands baseUrl to <c>new Uri(...)</c>; the schema pattern excludes credentials
    /// and query data but cannot establish a host or a valid port, so <c>https://:80/x</c> and
    /// <c>https://host:bad/x</c> pass it and fail on the first request. Mirrors the Python engine's
    /// <c>_check_aihub_base_urls</c>.
    /// </summary>
    private static List<JsonSchemaLite.Issue> AihubBaseUrls(JsonElement instance)
    {
        var issues = new List<JsonSchemaLite.Issue>();
        if (instance.ValueKind != JsonValueKind.Object
            || !instance.TryGetProperty("providers", out var providers)
            || providers.ValueKind != JsonValueKind.Object)
        {
            return issues;
        }
        foreach (var provider in providers.EnumerateObject())
        {
            if (provider.Value.ValueKind != JsonValueKind.Object
                || !provider.Value.TryGetProperty("baseUrl", out var baseUrl)
                || baseUrl.ValueKind != JsonValueKind.String)
            {
                continue;
            }
            var text = baseUrl.GetString()!;
            // Uri.TryCreate never throws, so a malformed value - "https://[bad]/" - is this
            // manifest's verdict here, exactly as the Python twin turns urlsplit's ValueError
            // into one instead of letting it escape the sweep.
            var ok = Uri.TryCreate(text, UriKind.Absolute, out var uri)
                     && (uri.Scheme == Uri.UriSchemeHttp || uri.Scheme == Uri.UriSchemeHttps)
                     && !string.IsNullOrEmpty(uri.Host);
            if (!ok)
            {
                issues.Add(new JsonSchemaLite.Issue($"$.providers.{provider.Name}.baseUrl", $"'{text}' is not an absolute http(s) URI with a host and a valid port"));
            }
        }
        return issues;
    }

    /// <summary>
    /// GitHub and apply-labels.ps1 identify labels case-insensitively; two entries whose names
    /// differ only by case would be POSTed twice or patched against each other on every run.
    /// </summary>
    private static List<JsonSchemaLite.Issue> LabelNames(JsonElement instance)
    {
        var issues = new List<JsonSchemaLite.Issue>();
        JsonElement entries;
        string prefix;
        if (instance.ValueKind == JsonValueKind.Object && instance.TryGetProperty("labels", out var labels))
        {
            entries = labels;
            prefix = "$.labels";
        }
        else
        {
            entries = instance;
            prefix = "$";
        }
        if (entries.ValueKind != JsonValueKind.Array)
        {
            return issues;
        }
        var seen = new Dictionary<string, (int Index, string Name)>(StringComparer.OrdinalIgnoreCase);
        var index = 0;
        foreach (var entry in entries.EnumerateArray())
        {
            var position = index++;
            if (entry.ValueKind != JsonValueKind.Object || !entry.TryGetProperty("name", out var name) || name.ValueKind != JsonValueKind.String)
            {
                continue;
            }
            var text = name.GetString()!;
            if (seen.TryGetValue(text, out var first))
            {
                issues.Add(new JsonSchemaLite.Issue($"{prefix}[{position}].name", $"'{text}' repeats entry {first.Index} ('{first.Name}'); GitHub matches label names case-insensitively"));
            }
            else
            {
                seen[text] = (position, text);
            }
        }
        return issues;
    }

    /// <summary>A manifest mapped twice would get two verdicts for one file; see LookupMappedSchema.</summary>
    private static List<JsonSchemaLite.Issue> MappingKeys(JsonElement instance)
    {
        var issues = new List<JsonSchemaLite.Issue>();
        if (instance.ValueKind != JsonValueKind.Object
            || !instance.TryGetProperty("mappings", out var mappings)
            || mappings.ValueKind != JsonValueKind.Array)
        {
            return issues;
        }
        var seen = new Dictionary<string, int>(StringComparer.Ordinal);
        var index = 0;
        foreach (var entry in mappings.EnumerateArray())
        {
            var position = index++;
            if (entry.ValueKind != JsonValueKind.Object || !entry.TryGetProperty("manifest", out var manifest) || manifest.ValueKind != JsonValueKind.String)
            {
                continue;
            }
            var key = NormalizeManifestKey(manifest.GetString()!);
            if (seen.TryGetValue(key, out var first))
            {
                issues.Add(new JsonSchemaLite.Issue($"$.mappings[{position}].manifest", $"'{manifest.GetString()}' is already mapped by entry {first}; a manifest has exactly one schema"));
            }
            else
            {
                seen[key] = position;
            }
        }
        return issues;
    }

    /// <summary>
    /// A chain entry that names nothing, or a chain of nothing but disabled entries, is a dead route
    /// that reads as configured: AIHub resolves each entry against the registry it built from
    /// providers plus enabled CLI agents and skips what is not there, so a typo degrades the chain
    /// silently and an all-disabled chain fails every request routed to it. Mirrors the Python
    /// engine's _check_aihub_chains.
    /// </summary>
    private static List<JsonSchemaLite.Issue> AihubChains(JsonElement instance)
    {
        var issues = new List<JsonSchemaLite.Issue>();
        if (instance.ValueKind != JsonValueKind.Object)
        {
            return issues;
        }
        var known = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var live = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (instance.TryGetProperty("providers", out var providers) && providers.ValueKind == JsonValueKind.Object)
        {
            foreach (var provider in providers.EnumerateObject())
            {
                known.Add(provider.Name);
                var disabled = provider.Value.ValueKind == JsonValueKind.Object
                    && provider.Value.TryGetProperty("enabled", out var providerEnabled)
                    && providerEnabled.ValueKind == JsonValueKind.False;
                if (!disabled)
                {
                    live.Add(provider.Name);
                }
            }
        }
        if (instance.TryGetProperty("cliAgents", out var agents) && agents.ValueKind == JsonValueKind.Array)
        {
            foreach (var agent in agents.EnumerateArray())
            {
                if (agent.ValueKind != JsonValueKind.Object
                    || !agent.TryGetProperty("name", out var name)
                    || name.ValueKind != JsonValueKind.String)
                {
                    continue;
                }
                known.Add(name.GetString()!);
                if (!(agent.TryGetProperty("enabled", out var enabled) && enabled.ValueKind == JsonValueKind.False))
                {
                    live.Add(name.GetString()!);
                }
            }
        }
        if (known.Count == 0)
        {
            return issues; // nothing to resolve against; the schema's required list reports that
        }
        foreach (var (path, chain) in Chains(instance))
        {
            var entries = chain.EnumerateArray().ToList();
            for (var index = 0; index < entries.Count; index++)
            {
                if (entries[index].ValueKind == JsonValueKind.String && !known.Contains(entries[index].GetString()!))
                {
                    issues.Add(new JsonSchemaLite.Issue($"{path}[{index}]",
                        $"'{entries[index].GetString()}' names neither a provider key nor a CLI agent in this file; the hub skips an entry it cannot resolve"));
                }
            }
            if (entries.Count > 0 && !entries.Any(entry => entry.ValueKind == JsonValueKind.String && live.Contains(entry.GetString()!)))
            {
                issues.Add(new JsonSchemaLite.Issue(path,
                    "no entry in this chain is an enabled provider or CLI agent; every request routed here would fail with no backend to try"));
            }
        }
        return issues;
    }

    /// <summary>routing.defaultChain and every routing.taskRouting entry, with its JSON path.</summary>
    private static List<(string Path, JsonElement Chain)> Chains(JsonElement instance)
    {
        var chains = new List<(string, JsonElement)>();
        if (!instance.TryGetProperty("routing", out var routing) || routing.ValueKind != JsonValueKind.Object)
        {
            return chains;
        }
        if (routing.TryGetProperty("defaultChain", out var defaultChain) && defaultChain.ValueKind == JsonValueKind.Array)
        {
            chains.Add(("$.routing.defaultChain", defaultChain));
        }
        if (routing.TryGetProperty("taskRouting", out var taskRouting) && taskRouting.ValueKind == JsonValueKind.Object)
        {
            foreach (var entry in taskRouting.EnumerateObject())
            {
                if (entry.Value.ValueKind == JsonValueKind.Array)
                {
                    chains.Add(($"$.routing.taskRouting.{entry.Name}", entry.Value));
                }
            }
        }
        return chains;
    }

    /// <summary>
    /// apply-milestones.ps1 matches live milestones case-insensitively, so two entries differing
    /// only by case target one milestone and the second PATCH overwrites the first.
    /// </summary>
    private static List<JsonSchemaLite.Issue> MilestoneTitles(JsonElement instance)
    {
        var issues = new List<JsonSchemaLite.Issue>();
        JsonElement entries;
        string prefix;
        if (instance.ValueKind == JsonValueKind.Object && instance.TryGetProperty("milestones", out var milestones))
        {
            entries = milestones;
            prefix = "$.milestones";
        }
        else
        {
            entries = instance;
            prefix = "$";
        }
        if (entries.ValueKind != JsonValueKind.Array)
        {
            return issues;
        }
        var seen = new Dictionary<string, (int Index, string Title)>(StringComparer.OrdinalIgnoreCase);
        var index = 0;
        foreach (var entry in entries.EnumerateArray())
        {
            var position = index++;
            if (entry.ValueKind != JsonValueKind.Object || !entry.TryGetProperty("title", out var title) || title.ValueKind != JsonValueKind.String)
            {
                continue;
            }
            var text = title.GetString()!;
            if (seen.TryGetValue(text, out var first))
            {
                issues.Add(new JsonSchemaLite.Issue($"{prefix}[{position}].title",
                    $"'{text}' repeats entry {first.Index} ('{first.Title}'); milestones are matched case-insensitively"));
            }
            else
            {
                seen[text] = (position, text);
            }
        }
        return issues;
    }

    /// <summary>
    /// A pool name is an identity: start-fleet.ps1 derives the assignee prefix and the Hermes board
    /// from it and scale-fleet.ps1 keys per-pool state by it, so two pools sharing a name share
    /// lanes and one silently absorbs the other's work.
    /// </summary>
    private static List<JsonSchemaLite.Issue> FleetPoolNames(JsonElement instance)
    {
        var issues = new List<JsonSchemaLite.Issue>();
        if (instance.ValueKind != JsonValueKind.Object
            || !instance.TryGetProperty("pools", out var pools)
            || pools.ValueKind != JsonValueKind.Array)
        {
            return issues;
        }
        var seen = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        var index = 0;
        foreach (var pool in pools.EnumerateArray())
        {
            var position = index++;
            if (pool.ValueKind != JsonValueKind.Object || !pool.TryGetProperty("name", out var name) || name.ValueKind != JsonValueKind.String)
            {
                continue;
            }
            var text = name.GetString()!;
            if (seen.TryGetValue(text, out var first))
            {
                issues.Add(new JsonSchemaLite.Issue($"$.pools[{position}].name",
                    $"'{text}' repeats pool {first}; a pool name is its board, its assignee prefix and its scaling key"));
            }
            else
            {
                seen[text] = position;
            }
        }
        return issues;
    }

    /// <summary>
    /// Provider keys and enabled CLI-agent names share ONE registry in the hub (AIHub.cs:
    /// <c>_byProvider[agent.Provider] = agent</c>, providers registered first): a CLI agent named
    /// like a provider, or two enabled agents with one name, silently replaces the earlier entry
    /// and every chain naming it reaches a different backend than configured. Compared
    /// case-insensitively, the way chain entries are looked up.
    /// </summary>
    private static List<JsonSchemaLite.Issue> AihubNames(JsonElement instance)
    {
        var issues = new List<JsonSchemaLite.Issue>();
        if (instance.ValueKind != JsonValueKind.Object)
        {
            return issues;
        }
        var owners = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (instance.TryGetProperty("providers", out var providers) && providers.ValueKind == JsonValueKind.Object)
        {
            foreach (var provider in providers.EnumerateObject())
            {
                if (provider.Value.ValueKind == JsonValueKind.Object
                    && provider.Value.TryGetProperty("enabled", out var providerEnabled)
                    && providerEnabled.ValueKind == JsonValueKind.False)
                {
                    continue; // ProviderFactory.CreateAll skips a disabled provider before registering it
                }
                owners.TryAdd(provider.Name, $"providers.{provider.Name}");
            }
        }
        if (instance.TryGetProperty("cliAgents", out var agents) && agents.ValueKind == JsonValueKind.Array)
        {
            var index = 0;
            foreach (var agent in agents.EnumerateArray())
            {
                var position = index++;
                if (agent.ValueKind != JsonValueKind.Object
                    || (agent.TryGetProperty("enabled", out var enabled) && enabled.ValueKind == JsonValueKind.False))
                {
                    continue; // a disabled entry is skipped by ProviderFactory.CreateAll before its name is read
                }
                if (!agent.TryGetProperty("name", out var name) || name.ValueKind != JsonValueKind.String)
                {
                    continue;
                }
                var text = name.GetString()!;
                if (owners.TryGetValue(text, out var owner))
                {
                    issues.Add(new JsonSchemaLite.Issue(
                        $"$.cliAgents[{position}].name",
                        $"'{text}' is already registered by {owner}; provider keys and CLI-agent names are one registry in the hub"));
                }
                else
                {
                    owners[text] = $"cliAgents[{position}]";
                }
            }
        }
        return issues;
    }
}
