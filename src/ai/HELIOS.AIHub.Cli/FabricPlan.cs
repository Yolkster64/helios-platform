using System.Text.Json;
using System.Text.Json.Serialization;

namespace HELIOS.AIHub.Cli;

/// <summary>
/// Read-only engine behind `helios-ai fabric-plan`: prints the sanitized HELIOS Fabric
/// authority map, integration readiness, and gated setup phases from
/// config/fabric/helios-fabric.v1.json. The command reports env-var NAMES and presence
/// only — it never reads back or prints a credential value, contacts a provider, or
/// mutates any external system. Its behavior mirrors the MCP `helios_fabric_plan_get`
/// tool so the CLI and MCP surfaces agree on what "sanitized" means.
/// </summary>
public static class FabricPlan
{
    private const string DefaultRelativePath = "config/fabric/helios-fabric.v1.json";

    private static readonly JsonSerializerOptions ReadOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true,
    };

    private static readonly JsonSerializerOptions WriteOptions = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    /// <summary>
    /// Finds config/fabric/helios-fabric.v1.json by walking up from
    /// <paramref name="startDirectory"/> (or cwd/AppContext.BaseDirectory when null),
    /// matching the walk-up pattern used by AIHubOptions.FindConfigFile and
    /// AbsorptionStatus.FindWatchlistFile — the command works from any subdirectory
    /// of the repo AND as a published artifact that ships its own config/ folder.
    /// </summary>
    public static string? FindContractFile(string? startDirectory = null)
    {
        var starts = startDirectory is not null
            ? new[] { startDirectory }
            : new[] { Directory.GetCurrentDirectory(), AppContext.BaseDirectory };

        foreach (var start in starts)
        {
            var dir = new DirectoryInfo(start);
            while (dir is not null)
            {
                var candidate = Path.Combine(dir.FullName, DefaultRelativePath);
                if (File.Exists(candidate))
                {
                    return candidate;
                }
                dir = dir.Parent;
            }
        }
        return null;
    }

    /// <summary>
    /// Writes the sanitized fabric plan JSON to <paramref name="output"/>. Returns 0
    /// on success; 1 (with a one-line message on <paramref name="error"/>) when the
    /// contract is missing, unreadable, or violates a fail-closed invariant
    /// (production enabled, apply on by default, repository-stored secret values, or
    /// non-WinUI-3 active desktop framework).
    /// </summary>
    public static int Execute(string? startDirectory, TextWriter output, TextWriter error)
    {
        var contractPath = FindContractFile(startDirectory);
        if (contractPath is null)
        {
            error.WriteLine(
                "config/fabric/helios-fabric.v1.json not found in this directory or any parent; run from the repo checkout.");
            return 1;
        }

        JsonDocument document;
        try
        {
            using var stream = File.OpenRead(contractPath);
            document = JsonDocument.Parse(stream);
        }
        catch (Exception ex) when (
            ex is IOException or UnauthorizedAccessException or JsonException)
        {
            error.WriteLine($"Failed to read '{contractPath}': {ex.Message}");
            return 1;
        }

        try
        {
            var envelope = BuildEnvelope(document.RootElement, contractPath);
            output.WriteLine(JsonSerializer.Serialize(envelope, WriteOptions));
            return 0;
        }
        catch (InvalidDataException ex)
        {
            error.WriteLine($"Fabric contract failed fail-closed check: {ex.Message}");
            return 1;
        }
        catch (JsonException ex)
        {
            error.WriteLine($"Fabric contract JSON was not well-formed: {ex.Message}");
            return 1;
        }
        finally
        {
            document.Dispose();
        }
    }

    private static object BuildEnvelope(JsonElement root, string contractPath)
    {
        var canonical = root.GetProperty("canonical");
        var security = root.GetProperty("security");
        EnsureFailClosed(canonical, security);

        var integrationStates = new Dictionary<string, string>(StringComparer.Ordinal);
        var integrations = new List<IntegrationRow>();
        foreach (var integration in root.GetProperty("integrations").EnumerateArray())
        {
            var id = integration.GetProperty("id").GetString()
                ?? throw new InvalidDataException("integration id is null");
            var desiredState = integration.GetProperty("desiredState").GetString() ?? "unknown";
            var requiredEnvNames = StringArray(integration.GetProperty("requiredEnv"));
            var presentEnvNames = requiredEnvNames
                .Where(name => !string.IsNullOrEmpty(Environment.GetEnvironmentVariable(name)))
                .ToArray();
            var missingEnvNames = requiredEnvNames
                .Except(presentEnvNames, StringComparer.Ordinal).ToArray();
            var readiness = desiredState switch
            {
                "disabled" => "disabled",
                "admin-binding-required" => "admin-binding-required",
                "connection-required" => "connection-required",
                _ when missingEnvNames.Length > 0 => "environment-reference-missing",
                _ => "contract-ready",
            };
            integrationStates[id] = readiness;
            integrations.Add(new IntegrationRow
            {
                Id = id,
                Role = integration.GetProperty("role").GetString(),
                Authority = integration.GetProperty("authority").GetString(),
                DesiredState = desiredState,
                Readiness = readiness,
                RequiredEnvNames = requiredEnvNames,
                PresentEnvNames = presentEnvNames,
                MissingEnvNames = missingEnvNames,
                HealthChecks = StringArray(integration.GetProperty("healthChecks")),
            });
        }

        var phases = new List<PhaseRow>();
        foreach (var phase in root.GetProperty("phases").EnumerateArray())
        {
            var phaseId = phase.GetProperty("id").GetString() ?? "unknown";
            var requiredIntegrations = StringArray(phase.GetProperty("requiredIntegrations"));
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
            phases.Add(new PhaseRow
            {
                Id = phaseId,
                Title = phase.GetProperty("title").GetString(),
                Readiness = readiness,
                DependsOn = StringArray(phase.GetProperty("dependsOn")),
                RequiredIntegrations = requiredIntegrations,
                BlockedIntegrations = blockedIntegrations,
                Execution = phase.GetProperty("execution").GetString(),
                MutatesExternalState = phase.GetProperty("mutatesExternalState").GetBoolean(),
                RequiredApproval = approval,
                Outputs = StringArray(phase.GetProperty("outputs")),
            });
        }

        var readyIntegrations = integrationStates.Count(kv => kv.Value == "contract-ready");
        var readyPhases = phases.Count(p => p.Readiness == "contract-ready");
        var blockedPhases = phases.Count(p => p.Readiness == "blocked-by-integration");

        return new Envelope
        {
            SchemaVersion = root.GetProperty("schemaVersion").GetString(),
            ConfigPath = contractPath,
            Summary = new SummaryRow
            {
                Integrations = integrations.Count,
                ReadyIntegrations = readyIntegrations,
                Phases = phases.Count,
                ReadyPhases = readyPhases,
                BlockedPhases = blockedPhases,
                ProductionEnabled = false,
                ApplyDefault = false,
                ActiveUiFramework = "WinUI 3",
            },
            Canonical = new CanonicalRow
            {
                CurrentRepository = canonical.GetProperty("currentRepository").GetString(),
                TargetRepository = canonical.GetProperty("targetRepository").GetString(),
                GuiRepository = TryGetString(canonical, "guiRepository"),
                RenameMode = TryGetString(canonical, "renameMode"),
            },
            Integrations = integrations,
            Phases = phases,
        };
    }

    private static void EnsureFailClosed(JsonElement canonical, JsonElement security)
    {
        if (canonical.GetProperty("productionEnabled").GetBoolean()
            || security.GetProperty("productionEnabled").GetBoolean()
            || security.GetProperty("applyDefault").GetBoolean()
            || security.GetProperty("secretValuesInRepository").GetBoolean())
        {
            throw new InvalidDataException(
                "production, apply, or repository-stored secret values are enabled.");
        }

        if (!string.Equals(
                security.GetProperty("allowedUiFramework").GetString(),
                "WinUI 3",
                StringComparison.Ordinal))
        {
            throw new InvalidDataException("WinUI 3 must remain the active desktop framework.");
        }
    }

    private static string[] StringArray(JsonElement array) => array
        .EnumerateArray()
        .Select(item => item.GetString() ?? string.Empty)
        .Where(value => value.Length > 0)
        .ToArray();

    private static string? TryGetString(JsonElement obj, string name) =>
        obj.TryGetProperty(name, out var value) ? value.GetString() : null;

    internal sealed record Envelope
    {
        [JsonPropertyName("schemaVersion")]
        public string? SchemaVersion { get; init; }

        [JsonPropertyName("configPath")]
        public string? ConfigPath { get; init; }

        [JsonPropertyName("summary")]
        public SummaryRow Summary { get; init; } = new();

        [JsonPropertyName("canonical")]
        public CanonicalRow Canonical { get; init; } = new();

        [JsonPropertyName("integrations")]
        public List<IntegrationRow> Integrations { get; init; } = new();

        [JsonPropertyName("phases")]
        public List<PhaseRow> Phases { get; init; } = new();
    }

    internal sealed record SummaryRow
    {
        [JsonPropertyName("integrations")]
        public int Integrations { get; init; }

        [JsonPropertyName("readyIntegrations")]
        public int ReadyIntegrations { get; init; }

        [JsonPropertyName("phases")]
        public int Phases { get; init; }

        [JsonPropertyName("readyPhases")]
        public int ReadyPhases { get; init; }

        [JsonPropertyName("blockedPhases")]
        public int BlockedPhases { get; init; }

        [JsonPropertyName("productionEnabled")]
        public bool ProductionEnabled { get; init; }

        [JsonPropertyName("applyDefault")]
        public bool ApplyDefault { get; init; }

        [JsonPropertyName("activeUiFramework")]
        public string? ActiveUiFramework { get; init; }
    }

    internal sealed record CanonicalRow
    {
        [JsonPropertyName("currentRepository")]
        public string? CurrentRepository { get; init; }

        [JsonPropertyName("targetRepository")]
        public string? TargetRepository { get; init; }

        [JsonPropertyName("guiRepository")]
        public string? GuiRepository { get; init; }

        [JsonPropertyName("renameMode")]
        public string? RenameMode { get; init; }
    }

    internal sealed record IntegrationRow
    {
        [JsonPropertyName("id")]
        public string? Id { get; init; }

        [JsonPropertyName("role")]
        public string? Role { get; init; }

        [JsonPropertyName("authority")]
        public string? Authority { get; init; }

        [JsonPropertyName("desiredState")]
        public string? DesiredState { get; init; }

        [JsonPropertyName("readiness")]
        public string? Readiness { get; init; }

        [JsonPropertyName("requiredEnvNames")]
        public string[] RequiredEnvNames { get; init; } = Array.Empty<string>();

        [JsonPropertyName("presentEnvNames")]
        public string[] PresentEnvNames { get; init; } = Array.Empty<string>();

        [JsonPropertyName("missingEnvNames")]
        public string[] MissingEnvNames { get; init; } = Array.Empty<string>();

        [JsonPropertyName("healthChecks")]
        public string[] HealthChecks { get; init; } = Array.Empty<string>();
    }

    internal sealed record PhaseRow
    {
        [JsonPropertyName("id")]
        public string? Id { get; init; }

        [JsonPropertyName("title")]
        public string? Title { get; init; }

        [JsonPropertyName("readiness")]
        public string? Readiness { get; init; }

        [JsonPropertyName("dependsOn")]
        public string[] DependsOn { get; init; } = Array.Empty<string>();

        [JsonPropertyName("requiredIntegrations")]
        public string[] RequiredIntegrations { get; init; } = Array.Empty<string>();

        [JsonPropertyName("blockedIntegrations")]
        public string[] BlockedIntegrations { get; init; } = Array.Empty<string>();

        [JsonPropertyName("execution")]
        public string? Execution { get; init; }

        [JsonPropertyName("mutatesExternalState")]
        public bool MutatesExternalState { get; init; }

        [JsonPropertyName("requiredApproval")]
        public string? RequiredApproval { get; init; }

        [JsonPropertyName("outputs")]
        public string[] Outputs { get; init; } = Array.Empty<string>();
    }
}
