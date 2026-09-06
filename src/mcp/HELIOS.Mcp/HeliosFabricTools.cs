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
            EnsureFailClosed(canonical, security);

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
                        var value = Environment.GetEnvironmentVariable(name);
                        var present = !string.IsNullOrEmpty(value);
                        secretValuesRead |= present;
                        return present;
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

    private static void EnsureFailClosed(JsonElement canonical, JsonElement security)
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
        return fullPath;
    }
}
