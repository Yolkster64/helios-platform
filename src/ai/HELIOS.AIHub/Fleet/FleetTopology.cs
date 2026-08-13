using System.Text.Json;
using System.Text.Json.Serialization;

namespace HELIOS.AIHub.Fleet;

/// <summary>A pool's Hermes kanban lane settings — only what advisory readers need.</summary>
public sealed record HermesFleetOptions
{
    [JsonPropertyName("board")]
    public string Board { get; init; } = "";

    [JsonPropertyName("maxConcurrentLanes")]
    public int MaxConcurrentLanes { get; init; }
}

/// <summary>One specialized agent pool from the fleet topology.</summary>
public sealed record FleetPool
{
    [JsonPropertyName("name")]
    public string Name { get; init; } = "";

    [JsonPropertyName("taskTypes")]
    public IReadOnlyList<string> TaskTypes { get; init; } = Array.Empty<string>();

    /// <summary>Ordered provider chain the pool's lanes route through (first = primary).</summary>
    [JsonPropertyName("providerChain")]
    public IReadOnlyList<string> ProviderChain { get; init; } = Array.Empty<string>();

    [JsonPropertyName("hermesFleet")]
    public HermesFleetOptions? HermesFleet { get; init; }
}

/// <summary>
/// Read-only view of config/fleet/fleet-topology.json — the declarative agent-fleet
/// layout (docs/architecture/HERMES_FLEET_AND_XCORE.md). Only the fields advisory
/// consumers need are bound; everything else in the file (spawn contracts, autoscaling,
/// tools, skills, agents, coordination) is deliberately left unread so topology edits
/// never break readers. Nothing here writes the file: topology changes are config
/// edits, never code.
/// </summary>
public sealed record FleetTopology
{
    [JsonPropertyName("version")]
    public int Version { get; init; }

    [JsonPropertyName("pools")]
    public IReadOnlyList<FleetPool> Pools { get; init; } = Array.Empty<FleetPool>();

    private static readonly JsonSerializerOptions ReadOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true,
    };

    /// <summary>
    /// Finds config/fleet/fleet-topology.json the same way
    /// <see cref="Configuration.AIHubOptions.FindConfigFile"/> finds config/aihub.json:
    /// walking up from <paramref name="startDirectory"/> (or the current directory, then
    /// the app base directory), so callers work from any subdirectory of the repo AND as
    /// a published artifact that ships its own config/ folder.
    /// </summary>
    public static string? FindTopologyFile(string? startDirectory = null)
    {
        var starts = startDirectory is not null
            ? new[] { startDirectory }
            : new[] { Directory.GetCurrentDirectory(), AppContext.BaseDirectory };

        foreach (var start in starts)
        {
            var dir = new DirectoryInfo(start);
            while (dir is not null)
            {
                var candidate = System.IO.Path.Combine(
                    dir.FullName, "config", "fleet", "fleet-topology.json");
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
    /// Loads the topology, reporting failure as a status result rather than an exception
    /// (same convention as <see cref="Configuration.ModelCatalog.TryLoad"/> and
    /// absorb-status): a missing or unreadable topology is an expected state for an
    /// advisory reader, not a crash. Null <paramref name="path"/> resolves via
    /// <see cref="FindTopologyFile"/>.
    /// </summary>
    public static FleetTopologyLoadResult TryLoad(string? path = null)
    {
        var resolved = path ?? FindTopologyFile();
        if (resolved is null)
        {
            return new FleetTopologyLoadResult
            {
                Error = "config/fleet/fleet-topology.json not found in this directory or any parent; "
                        + "run from the repo checkout or pass an explicit path.",
            };
        }
        if (!File.Exists(resolved))
        {
            return new FleetTopologyLoadResult
            {
                Path = resolved,
                Error = $"Fleet topology '{resolved}' does not exist.",
            };
        }

        try
        {
            using var stream = File.OpenRead(resolved);
            var topology = JsonSerializer.Deserialize<FleetTopology>(stream, ReadOptions);
            return topology is null
                ? new FleetTopologyLoadResult
                {
                    Path = resolved,
                    Error = $"'{resolved}' deserialized to null.",
                }
                : new FleetTopologyLoadResult { Path = resolved, Topology = topology };
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException)
        {
            return new FleetTopologyLoadResult
            {
                Path = resolved,
                Error = $"Failed to read '{resolved}': {ex.Message}",
            };
        }
    }
}

/// <summary>
/// Outcome of a topology load: either a topology (with the path it came from) or a
/// one-line reason it could not be produced. Never both.
/// </summary>
public sealed record FleetTopologyLoadResult
{
    public FleetTopology? Topology { get; init; }

    /// <summary>Resolved file path when one was found — set even when reading it failed.</summary>
    public string? Path { get; init; }

    /// <summary>Why <see cref="Topology"/> is null; null on success.</summary>
    public string? Error { get; init; }
}
