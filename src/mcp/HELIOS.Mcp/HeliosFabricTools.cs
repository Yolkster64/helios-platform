using System.ComponentModel;
using System.Text.Json;
using System.Text.Json.Serialization;
using ModelContextProtocol.Server;

namespace HELIOS.Mcp;

/// <summary>
/// Read-only visibility into the canonical HELIOS Fabric setup contract. The tool
/// intentionally reports environment-variable names and presence only; it never returns
/// or serializes a credential value, invokes a provider, or mutates an external
/// system.
/// </summary>
[McpServerToolType]
public static class HeliosFabricTools
{
    private const string DefaultRelativePath = "config/fabric/helios-fabric.v1.json";
    private static readonly string[] SecretPrefixes =
    [
        "sk-",
        "sk-proj-",
        "ghp_",
        "github_pat_",
        "xoxb-",
        "xoxp-",
        "lin_api_",
    ];

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    [McpServerTool(Name = "helios_fabric_plan_get", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description(
        "Return the sanitized HELIOS Fabric authority map, integration readiness, and " +
        "gated setup phases from config/fabric/helios-fabric.v1.json. The result reports " +
        "only whether named environment references exist; values are never returned. " +
        "Read-only: no repository, provider, connector, Azure, secret, or workstation " +
        "state is changed.")]
    public static string GetFabricPlan(
        [Description(
            "Optional repository-relative path to an alternate Fabric JSON contract. " +
            "Paths outside HELIOS_REPO_ROOT are rejected.")]
        string? configPath = null) =>
        BuildFabricPlanJson(startDirectory: null, requestedPath: configPath);

    /// <summary>
    /// Core of helios_fabric_plan_get, split out so tests can point it at a fabricated
    /// repo root. <paramref name="startDirectory"/> = null means "resolve from
    /// HELIOS_REPO_ROOT or by walking up from the process's cwd/base directory",
    /// matching the other read-only tools' pattern.
    /// </summary>
    public static string BuildFabricPlanJson(string? startDirectory, string? requestedPath = null)
    {
        var secretValuesRead = false;
        try
        {
            var repoRoot = ResolveRepositoryRoot(startDirectory);
            var path = ResolveConfigPath(repoRoot, requestedPath);
            using var document = JsonDocument.Parse(File.ReadAllText(path));
            var root = document.RootElement;

            var canonical = root.GetProperty("canonical");
            var security = root.GetProperty("security");
            EnsureFailClosed(root, canonical, security);

            var secretValuesRead = false;
            var integrations = new List<object>();
            var integrationStates = new Dictionary<string, string>(StringComparer.Ordinal);
            foreach (var integration in root.GetProperty("integrations").EnumerateArray())
            {
                var id = integration.GetProperty("id").GetString()
                    ?? throw new InvalidDataException("integration id is null");
                var desiredState = integration.GetProperty("desiredState").GetString()
                    ?? "unknown";
                var requiredEnvNames = integration.GetProperty("requiredEnv")
                    .EnumerateArray()
                    .Select(item => item.GetString() ?? string.Empty)
                    .Where(name => name.Length > 0)
                    .ToArray();
                var presentEnvNames = requiredEnvNames
                    .Where(name =>
                    {
                        secretValuesRead = true;
                        return !string.IsNullOrEmpty(Environment.GetEnvironmentVariable(name));
                    })
                    .ToArray();
                var missingEnvNames = requiredEnvNames.Except(presentEnvNames, StringComparer.Ordinal).ToArray();
                var readiness = desiredState switch
                {
                    "disabled" => "disabled",
                    "admin-binding-required" => "admin-binding-required",
                    "connection-required" => "connection-required",
                    _ when missingEnvNames.Length > 0 => "environment-reference-missing",
                    _ => "contract-ready",
                };
                integrationStates[id] = readiness;
                integrations.Add(new
                {
                    id,
                    role = integration.GetProperty("role").GetString(),
                    authority = integration.GetProperty("authority").GetString(),
                    desiredState,
                    readiness,
                    requiredEnvNames,
                    presentEnvNames,
                    missingEnvNames,
                    healthChecks = Strings(integration.GetProperty("healthChecks")),
                    target = integration.TryGetProperty("target", out var target)
                        ? target.Clone()
                        : (JsonElement?)null,
                });
            }

            var phases = new List<object>();
            foreach (var phase in root.GetProperty("phases").EnumerateArray())
            {
                var phaseId = phase.GetProperty("id").GetString() ?? "unknown";
                var requiredIntegrations = Strings(phase.GetProperty("requiredIntegrations"));
                var blockedIntegrations = requiredIntegrations
                    .Where(id => integrationStates.TryGetValue(id, out var state)
                        && state is "disabled" or "admin-binding-required"
                            or "connection-required" or "environment-reference-missing")
                    .ToArray();
                var approval = phase.GetProperty("requiredApproval").GetString() ?? "none";
                var readiness = phaseId == "F16"
                    ? "production-disabled"
                    : blockedIntegrations.Length > 0
                        ? "blocked-by-integration"
                        : approval != "none"
                            ? "approval-required"
                            : "contract-ready";
                phases.Add(new
                {
                    id = phaseId,
                    title = phase.GetProperty("title").GetString(),
                    readiness,
                    dependsOn = Strings(phase.GetProperty("dependsOn")),
                    requiredIntegrations,
                    blockedIntegrations,
                    execution = phase.GetProperty("execution").GetString(),
                    mutatesExternalState = phase.GetProperty("mutatesExternalState").GetBoolean(),
                    requiredApproval = approval,
                    outputs = Strings(phase.GetProperty("outputs")),
                });
            }

            return JsonSerializer.Serialize(new
            {
                schemaVersion = root.GetProperty("schemaVersion").GetString(),
                configPath = Path.GetRelativePath(repoRoot, path).Replace('\\', '/'),
                canonical = canonical.Clone(),
                authorities = root.GetProperty("authorities").Clone(),
                integrations,
                phases,
                evidence = root.GetProperty("evidence").Clone(),
                security = new
                {
                    productionEnabled = false,
                    applyDefault = false,
                    secretValuesRead,
                    externalMutationPerformed = false,
                    activeUiFramework = "WinUI 3",
                },
            }, JsonOptions);
        }
        catch (Exception exception) when (exception is IOException
            or UnauthorizedAccessException
            or JsonException
            or InvalidDataException)
        {
            return JsonSerializer.Serialize(new
            {
                error = "HELIOS Fabric contract could not be read or validated.",
                detail = exception.Message,
                externalMutationPerformed = false,
                secretValuesRead,
            }, JsonOptions);
        }
    }

    private static string[] Strings(JsonElement array) => array
        .EnumerateArray()
        .Select(item => item.GetString() ?? string.Empty)
        .Where(value => value.Length > 0)
        .ToArray();

    private static void EnsureFailClosed(JsonElement root, JsonElement canonical, JsonElement security)
    {
        if (canonical.GetProperty("productionEnabled").GetBoolean()
            || security.GetProperty("productionEnabled").GetBoolean()
            || security.GetProperty("applyDefault").GetBoolean()
            || security.GetProperty("secretValuesInRepository").GetBoolean())
        {
            throw new InvalidDataException(
                "Fabric contract is not fail-closed: production, apply, or repository secret values are enabled.");
        }

        if (!string.Equals(
                security.GetProperty("allowedUiFramework").GetString(),
                "WinUI 3",
                StringComparison.Ordinal))
        {
            throw new InvalidDataException("WinUI 3 must remain the active desktop framework.");
        }

        if (!security.GetProperty("externalWritesRequireApproval").GetBoolean())
        {
            throw new InvalidDataException("externalWritesRequireApproval must remain true.");
        }

        var forbiddenUiFrameworks = new HashSet<string>(
            Strings(security.GetProperty("forbiddenUiFrameworks")),
            StringComparer.Ordinal);
        if (!forbiddenUiFrameworks.Contains("WPF") || !forbiddenUiFrameworks.Contains("UWP"))
        {
            throw new InvalidDataException("forbiddenUiFrameworks must include WPF and UWP.");
        }

        EnsureNoSecretLikeValues(root);
        ValidatePhaseTopology(root.GetProperty("integrations"), root.GetProperty("phases"));
    }

    private static void EnsureNoSecretLikeValues(JsonElement value)
    {
        foreach (var text in EnumerateStrings(value))
        {
            var lowered = text.ToLowerInvariant();
            if (SecretPrefixes.Any(prefix => lowered.StartsWith(prefix, StringComparison.Ordinal))
                || lowered.Contains("-----begin private key-----", StringComparison.Ordinal))
            {
                throw new InvalidDataException("Fabric contract appears to contain a credential value.");
            }
        }
    }

    private static IEnumerable<string> EnumerateStrings(JsonElement value)
    {
        switch (value.ValueKind)
        {
            case JsonValueKind.Object:
                foreach (var property in value.EnumerateObject())
                {
                    foreach (var child in EnumerateStrings(property.Value))
                    {
                        yield return child;
                    }
                }
                break;
            case JsonValueKind.Array:
                foreach (var item in value.EnumerateArray())
                {
                    foreach (var child in EnumerateStrings(item))
                    {
                        yield return child;
                    }
                }
                break;
            case JsonValueKind.String:
                var text = value.GetString();
                if (!string.IsNullOrEmpty(text))
                {
                    yield return text;
                }
                break;
        }
    }

    private static void ValidatePhaseTopology(JsonElement integrations, JsonElement phases)
    {
        var integrationIds = new HashSet<string>(StringComparer.Ordinal);
        foreach (var integration in integrations.EnumerateArray())
        {
            integrationIds.Add(integration.GetProperty("id").GetString()
                ?? throw new InvalidDataException("integration id is null"));
        }

        var phaseDependencies = new Dictionary<string, string[]>(StringComparer.Ordinal);
        foreach (var phase in phases.EnumerateArray())
        {
            var phaseId = phase.GetProperty("id").GetString()
                ?? throw new InvalidDataException("phase id is null");
            if (!phaseDependencies.TryAdd(phaseId, Strings(phase.GetProperty("dependsOn"))))
            {
                throw new InvalidDataException($"duplicate phase id {phaseId}");
            }

            var requiredIntegrations = Strings(phase.GetProperty("requiredIntegrations"));
            var missingIntegrations = requiredIntegrations
                .Where(integrationId => !integrationIds.Contains(integrationId))
                .ToArray();
            if (missingIntegrations.Length > 0)
            {
                throw new InvalidDataException(
                    $"phase {phaseId} references missing integrations [{string.Join(", ", missingIntegrations)}]");
            }

            var mutatesExternalState = phase.GetProperty("mutatesExternalState").GetBoolean();
            var requiredApproval = phase.GetProperty("requiredApproval").GetString() ?? "none";
            if (mutatesExternalState && string.Equals(requiredApproval, "none", StringComparison.Ordinal))
            {
                throw new InvalidDataException($"phase {phaseId} mutates external state but has no approval.");
            }
        }

        var missingDependencies = phaseDependencies
            .SelectMany(pair => pair.Value.Select(dependency => (Phase: pair.Key, Dependency: dependency)))
            .Where(item => !phaseDependencies.ContainsKey(item.Dependency))
            .ToArray();
        if (missingDependencies.Length > 0)
        {
            throw new InvalidDataException(
                $"phase {missingDependencies[0].Phase} references missing phase {missingDependencies[0].Dependency}");
        }

        var incoming = phaseDependencies.ToDictionary(pair => pair.Key, _ => 0, StringComparer.Ordinal);
        var outgoing = phaseDependencies.Keys.ToDictionary(key => key, _ => new List<string>(), StringComparer.Ordinal);
        foreach (var (phaseId, dependencies) in phaseDependencies)
        {
            foreach (var dependency in dependencies)
            {
                incoming[phaseId]++;
                outgoing[dependency].Add(phaseId);
            }
        }

        var ready = new Queue<string>(incoming.Where(pair => pair.Value == 0).Select(pair => pair.Key));
        var visited = 0;
        while (ready.Count > 0)
        {
            var phaseId = ready.Dequeue();
            visited++;
            foreach (var child in outgoing[phaseId])
            {
                incoming[child]--;
                if (incoming[child] == 0)
                {
                    ready.Enqueue(child);
                }
            }
        }

        if (visited != phaseDependencies.Count)
        {
            throw new InvalidDataException("phase dependency graph contains a cycle.");
        }
    }

    private static string ResolveRepositoryRoot(string? startDirectory = null)
    {
        // Explicit startDirectory (tests, or a caller that knows the root) is
        // authoritative: walk up from it looking for the contract, but do NOT
        // fall through to the process-wide fallbacks — that would leak the real
        // checkout into a test fixture and hide the failure the test wants.
        if (!string.IsNullOrWhiteSpace(startDirectory))
        {
            return WalkUpFor(startDirectory)
                ?? throw new InvalidDataException(
                    $"HELIOS Fabric contract not found from '{startDirectory}' or any parent " +
                    $"(looking for {DefaultRelativePath}).");
        }

        var configured = Environment.GetEnvironmentVariable("HELIOS_REPO_ROOT");
        if (!string.IsNullOrWhiteSpace(configured))
        {
            var explicitRoot = Path.GetFullPath(configured);
            if (!Directory.Exists(explicitRoot))
            {
                throw new InvalidDataException("Configured HELIOS_REPO_ROOT does not exist.");
            }
            return explicitRoot;
        }

        foreach (var start in new[] { Directory.GetCurrentDirectory(), AppContext.BaseDirectory })
        {
            if (WalkUpFor(start) is { } found)
            {
                return found;
            }
        }

        throw new InvalidDataException(
            "Repository root was not found. Set HELIOS_REPO_ROOT to the checked-out repository.");
    }

    private static string? WalkUpFor(string start)
    {
        var current = new DirectoryInfo(Path.GetFullPath(start));
        while (current is not null)
        {
            if (File.Exists(Path.Combine(current.FullName, DefaultRelativePath)))
            {
                return current.FullName;
            }
            current = current.Parent;
        }
        return null;
    }

    private static string ResolveConfigPath(string repoRoot, string? requestedPath)
    {
        var relative = string.IsNullOrWhiteSpace(requestedPath)
            ? DefaultRelativePath
            : requestedPath;
        var fullPath = Path.GetFullPath(Path.Combine(repoRoot, relative));
        var relativeToRoot = Path.GetRelativePath(repoRoot, fullPath);
        if (Path.IsPathRooted(relativeToRoot)
            || relativeToRoot.Equals("..", StringComparison.Ordinal)
            || relativeToRoot.StartsWith($"..{Path.DirectorySeparatorChar}", StringComparison.Ordinal))
        {
            throw new InvalidDataException("Fabric config path must remain inside HELIOS_REPO_ROOT.");
        }
        if (!File.Exists(fullPath))
        {
            throw new FileNotFoundException("Fabric contract does not exist.", fullPath);
        }

        var canonicalRoot = CanonicalizePath(repoRoot);
        var canonicalPath = CanonicalizePath(fullPath);
        var canonicalRelative = Path.GetRelativePath(canonicalRoot, canonicalPath);
        if (Path.IsPathRooted(canonicalRelative)
            || canonicalRelative.Equals("..", StringComparison.Ordinal)
            || canonicalRelative.StartsWith($"..{Path.DirectorySeparatorChar}", StringComparison.Ordinal))
        {
            throw new InvalidDataException("Fabric config path must remain inside HELIOS_REPO_ROOT.");
        }

        return canonicalPath;
    }

    private static string CanonicalizePath(string path)
    {
        var normalized = Path.GetFullPath(path);
        var root = Path.GetPathRoot(normalized)
            ?? throw new InvalidDataException("Path root could not be resolved.");
        var segments = normalized[root.Length..]
            .Split(new[] { Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar }, StringSplitOptions.RemoveEmptyEntries);

        var current = root;
        foreach (var segment in segments)
        {
            var next = Path.Combine(current, segment);
            var linkTarget = TryResolveLinkTarget(next);
            current = linkTarget is null
                ? next
                : Path.GetFullPath(linkTarget);
        }

        return Path.GetFullPath(current);
    }

    private static string? TryResolveLinkTarget(string path)
    {
        if (!File.Exists(path) && !Directory.Exists(path))
        {
            return null;
        }

        FileSystemInfo node = Directory.Exists(path)
            ? new DirectoryInfo(path)
            : new FileInfo(path);
        if ((node.Attributes & FileAttributes.ReparsePoint) == 0)
        {
            return null;
        }

        var target = node.ResolveLinkTarget(returnFinalTarget: true)
            ?? throw new InvalidDataException("Failed to resolve symbolic link target.");
        var targetPath = target.FullName;
        if (Path.IsPathRooted(targetPath))
        {
            return targetPath;
        }

        var baseDirectory = Path.GetDirectoryName(node.FullName)
            ?? throw new InvalidDataException("Link base directory could not be resolved.");
        return Path.GetFullPath(Path.Combine(baseDirectory, targetPath));
    }
}
