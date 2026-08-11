using System.ComponentModel;
using System.Text.Json;
using System.Text.Json.Serialization;
using HELIOS.AIHub.Configuration;
using ModelContextProtocol;
using ModelContextProtocol.Server;

namespace HELIOS.Mcp;

/// <summary>
/// Read-only repo-state tools: absorption-program status (the curated upstream-PR
/// watchlist merged with local benchmark reports — a superset of `helios-ai
/// absorb-status`, adding per-candidate gatePassed and a warnings array) and fleet run
/// status (run manifests plus advisory open/claimed/done board counts — a summary,
/// not scripts/fleet/fleet-status.ps1's full per-worker view). Nothing here fetches,
/// locks, or mutates anything — these tools only report. Repo root resolution matches
/// the other MCP tools: walk up to config/aihub.json via
/// <see cref="AIHubOptions.FindConfigFile"/>.
/// </summary>
[McpServerToolType]
public static class HeliosStatusTools
{
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

    [McpServerTool(Name = "helios_absorb_status_get", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description("Absorption-program status: the upstream-PR watchlist (config/absorption/pr-watchlist.json) as { upstream, total, by_status, candidates }, each candidate merged with any local benchmark report (.helios/absorption/pr-<n>.json) as verdict/gatePassed/benchmarked. Read-only; a superset of `helios-ai absorb-status` output (adds gatePassed and warnings).")]
    public static string GetAbsorbStatus() => BuildAbsorbStatusJson(startDirectory: null);

    [McpServerTool(Name = "helios_fleet_status_get", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description("Fleet run state from .helios/fleet/<runId>/manifest.json: per run { runId, status, pools: [{ pool, board, workers, workersLive, openTasks, claimedTasks, doneTasks, blockedTasks }] }. workers = manifest-recorded count; workersLive = pid+startTime-verified processes still running (0 with recorded workers means a dead fleet). Task counts read from each pool's board db. Latest run by default; allRuns=true for every recorded run. Read-only and lock-free — never blocks workers. A missing fleet directory returns an empty result with a message, not an error.")]
    public static string GetFleetStatus(
        [Description("Include every recorded run instead of only the latest one.")] bool allRuns = false) =>
        BuildFleetStatusJson(allRuns, startDirectory: null);

    /// <summary>
    /// Core of helios_absorb_status_get, split out so tests can point it at a fabricated
    /// repo root. <paramref name="startDirectory"/> = null means "resolve from the
    /// process's own location", exactly like the other tools.
    /// </summary>
    public static string BuildAbsorbStatusJson(string? startDirectory)
    {
        var repoRoot = ResolveRepoRoot(startDirectory);
        var watchlistPath = Path.Combine(repoRoot, "config", "absorption", "pr-watchlist.json");
        if (!File.Exists(watchlistPath))
        {
            throw new McpException(
                $"'{watchlistPath}' does not exist — the absorption watchlist is not set up in this checkout. " +
                "Create config/absorption/pr-watchlist.json ({ upstream, candidates: [{ pr, title, status, ... }] }) first.");
        }

        Watchlist watchlist;
        try
        {
            using var stream = File.OpenRead(watchlistPath);
            watchlist = JsonSerializer.Deserialize<Watchlist>(stream, ReadOptions)
                        ?? throw new InvalidDataException($"'{watchlistPath}' deserialized to null.");
        }
        catch (Exception ex) when (
            ex is IOException or UnauthorizedAccessException or JsonException or InvalidDataException)
        {
            throw new McpException($"Failed to read '{watchlistPath}': {ex.Message}");
        }

        var warnings = new List<string>();
        var reports = LoadBenchmarkReports(Path.Combine(repoRoot, ".helios", "absorption"), warnings);

        var rows = new List<AbsorbCandidateRow>();
        var byStatus = new SortedDictionary<string, int>(StringComparer.Ordinal);
        foreach (var candidate in watchlist.Candidates)
        {
            var status = string.IsNullOrWhiteSpace(candidate.Status) ? "unknown" : candidate.Status;
            byStatus[status] = byStatus.GetValueOrDefault(status) + 1;
            reports.TryGetValue(candidate.Pr, out var report);
            rows.Add(new AbsorbCandidateRow
            {
                Pr = candidate.Pr,
                Title = candidate.Title,
                Status = status,
                Epic = candidate.Epic,
                Verdict = report?.Verdict,
                GatePassed = report?.GatePassed,
                Benchmarked = report?.Benchmarked,
            });
        }

        return JsonSerializer.Serialize(new AbsorbSummary
        {
            Upstream = watchlist.Upstream,
            Total = rows.Count,
            ByStatus = byStatus,
            Candidates = rows,
            Warnings = warnings.Count == 0 ? null : warnings,
        }, WriteOptions);
    }

    /// <summary>
    /// Core of helios_fleet_status_get, split out so tests can point it at a fabricated
    /// repo root.
    /// </summary>
    public static string BuildFleetStatusJson(bool allRuns, string? startDirectory)
    {
        var repoRoot = ResolveRepoRoot(startDirectory);
        var fleetDir = Path.Combine(repoRoot, ".helios", "fleet");
        var noRunsMessage =
            $"No fleet runs found under '{fleetDir}'. Start one: pwsh scripts/fleet/start-fleet.ps1";
        if (!Directory.Exists(fleetDir))
        {
            return JsonSerializer.Serialize(new FleetReport
            {
                Runs = new List<FleetRunRow>(),
                Message = noRunsMessage,
            }, WriteOptions);
        }

        var warnings = new List<string>();
        var runs = new List<FleetRunRow>();
        // Run ids start with a UTC timestamp (yyyyMMdd-HHmmss-xxxxxx), so ordinal
        // name order is chronological — same ordering fleet-status.ps1 uses.
        var orderedRunDirs = Directory.EnumerateDirectories(fleetDir)
            .OrderBy(Path.GetFileName, StringComparer.Ordinal)
            .ToList();
        if (!allRuns)
        {
            // Latest-only is the common, frequently polled path: walk from the newest
            // end and stop at the first readable manifest instead of parsing every
            // historical run. Unreadable manifests passed on the way still warn.
            orderedRunDirs.Reverse();
        }
        foreach (var runDir in orderedRunDirs)
        {
            var manifestPath = Path.Combine(runDir, "manifest.json");
            if (!File.Exists(manifestPath))
            {
                continue;
            }

            FleetManifest? manifest;
            try
            {
                using var stream = File.OpenRead(manifestPath);
                manifest = JsonSerializer.Deserialize<FleetManifest>(stream, ReadOptions);
            }
            catch (Exception ex) when (
                ex is IOException or UnauthorizedAccessException or JsonException)
            {
                warnings.Add($"Skipping unreadable manifest '{manifestPath}': {ex.Message}");
                continue;
            }
            if (manifest is null)
            {
                warnings.Add($"Skipping empty manifest '{manifestPath}'.");
                continue;
            }

            runs.Add(new FleetRunRow
            {
                RunId = manifest.RunId ?? Path.GetFileName(runDir),
                Status = manifest.Status,
                Pools = manifest.Pools
                    .Select(pool => BuildPoolRow(pool, runDir, warnings))
                    .ToList(),
            });
            if (!allRuns)
            {
                // The reversed walk means the first readable manifest IS the latest.
                break;
            }
        }

        return JsonSerializer.Serialize(new FleetReport
        {
            Runs = runs,
            Message = runs.Count == 0 ? noRunsMessage : null,
            Warnings = warnings.Count == 0 ? null : warnings,
        }, WriteOptions);
    }

    /// <summary>Same repo-root resolution as helios_infra_validate: config/aihub.json's grandparent.</summary>
    private static string ResolveRepoRoot(string? startDirectory)
    {
        var configPath = AIHubOptions.FindConfigFile(startDirectory)
            ?? throw new McpException("Repo root not found (no config/aihub.json in any parent directory).");
        return Directory.GetParent(Path.GetDirectoryName(configPath)!)!.FullName;
    }

    private static Dictionary<int, BenchmarkReport> LoadBenchmarkReports(
        string reportsDirectory, List<string> warnings)
    {
        var reports = new Dictionary<int, BenchmarkReport>();
        if (!Directory.Exists(reportsDirectory))
        {
            return reports;
        }

        foreach (var file in Directory.EnumerateFiles(reportsDirectory, "pr-*.json")
                     .OrderBy(f => f, StringComparer.Ordinal))
        {
            try
            {
                using var stream = File.OpenRead(file);
                var report = JsonSerializer.Deserialize<BenchmarkReport>(stream, ReadOptions);
                if (report is { Pr: > 0 })
                {
                    reports[report.Pr] = report;
                }
            }
            catch (Exception ex) when (
                ex is IOException or UnauthorizedAccessException or JsonException)
            {
                // One broken benchmark report must not hide the rest of the status.
                warnings.Add($"Skipping unreadable report '{file}': {ex.Message}");
            }
        }
        return reports;
    }

    private static FleetPoolRow BuildPoolRow(FleetManifestPool pool, string runDir, List<string> warnings)
    {
        var (open, claimed, done, blocked) = TallyBoard(pool.Db, runDir, warnings);
        return new FleetPoolRow
        {
            Pool = pool.Pool,
            Board = pool.Board,
            Workers = pool.Workers.Count,
            WorkersLive = CountLiveWorkers(pool.Workers),
            OpenTasks = open,
            ClaimedTasks = claimed,
            DoneTasks = done,
            BlockedTasks = blocked,
        };
    }

    /// <summary>
    /// Counts manifest workers whose recorded pid is still a live process — the same
    /// pid + startTime identity check the fleet scripts use before killing (2s clock
    /// tolerance). A stub that idle-exited or a crashed agent leaves the manifest
    /// entry behind, so the recorded count alone cannot detect a dead fleet. A pid
    /// whose start time is unreadable or mismatched counts as NOT live: it is either
    /// gone or an unrelated process that reused the pid.
    /// </summary>
    private static int CountLiveWorkers(IReadOnlyList<JsonElement> workers)
    {
        var live = 0;
        foreach (var worker in workers)
        {
            if (worker.ValueKind != JsonValueKind.Object ||
                !worker.TryGetProperty("pid", out var pidElement) ||
                !pidElement.TryGetInt32(out var pid) || pid <= 0)
            {
                continue;
            }

            // The identity contract needs BOTH halves: start-fleet.ps1 records a null
            // startTime when the process start is unreadable, and a pid alone can be
            // reused by an unrelated process after the worker exits — an entry whose
            // recorded start time is absent or unparseable is unverifiable, not live.
            if (!worker.TryGetProperty("startTime", out var startElement) ||
                startElement.ValueKind != JsonValueKind.String ||
                !DateTimeOffset.TryParse(startElement.GetString(), out var recorded))
            {
                continue;
            }

            try
            {
                using var process = System.Diagnostics.Process.GetProcessById(pid);
                var actual = new DateTimeOffset(process.StartTime.ToUniversalTime());
                if (Math.Abs((actual - recorded.ToUniversalTime()).TotalSeconds) > 2)
                {
                    continue; // pid reused by an unrelated process
                }
                live++;
            }
            catch (Exception ex) when (ex is ArgumentException or InvalidOperationException
                or System.ComponentModel.Win32Exception or NotSupportedException)
            {
                // No such process, it exited mid-probe, or its start time is not
                // readable from this principal — all mean "not verifiably ours".
            }
        }
        return live;
    }

    /// <summary>
    /// Counts a pool's board tasks by status. This is a pure, lock-free read:
    /// it deliberately does NOT take the pool's claim lock (manifest 'claimLock') —
    /// status counts are advisory and must never block or delay workers claiming
    /// tasks. Worst case a concurrent write skews a count until the next call.
    /// </summary>
    private static (int Open, int Claimed, int Done, int Blocked) TallyBoard(
        string? dbPath, string runDir, List<string> warnings)
    {
        if (string.IsNullOrWhiteSpace(dbPath))
        {
            return (0, 0, 0, 0);
        }
        // Manifests written by start-fleet.ps1 carry absolute db paths; tolerate
        // relative ones by resolving against the run directory.
        var resolved = Path.IsPathRooted(dbPath) ? dbPath : Path.Combine(runDir, dbPath);
        if (!File.Exists(resolved))
        {
            return (0, 0, 0, 0);
        }

        BoardFile? board;
        try
        {
            using var stream = File.OpenRead(resolved);
            board = JsonSerializer.Deserialize<BoardFile>(stream, ReadOptions);
        }
        catch (Exception ex) when (
            ex is IOException or UnauthorizedAccessException or JsonException)
        {
            warnings.Add($"Skipping unreadable board '{resolved}': {ex.Message}");
            return (0, 0, 0, 0);
        }
        if (board is null)
        {
            return (0, 0, 0, 0);
        }

        int open = 0, claimed = 0, done = 0, blocked = 0;
        foreach (var task in board.Tasks)
        {
            // Same default as fleet-status.ps1: a task without a status is open.
            var status = string.IsNullOrWhiteSpace(task.Status) ? "open" : task.Status;
            if (string.Equals(status, "open", StringComparison.OrdinalIgnoreCase))
            {
                open++;
            }
            else if (string.Equals(status, "claimed", StringComparison.OrdinalIgnoreCase))
            {
                claimed++;
            }
            else if (string.Equals(status, "done", StringComparison.OrdinalIgnoreCase))
            {
                done++;
            }
            else if (string.Equals(status, "blocked", StringComparison.OrdinalIgnoreCase))
            {
                // A fully blocked backlog is exactly the state an operator must see;
                // dropping these made such a pool look empty (fleet-status.ps1 parity).
                blocked++;
            }
        }
        return (open, claimed, done, blocked);
    }

    // ---- absorption shapes (mirrors HELIOS.AIHub.Cli.AbsorptionStatus) -------------

    internal sealed record Watchlist
    {
        [JsonPropertyName("upstream")]
        public string? Upstream { get; init; }

        [JsonPropertyName("candidates")]
        public List<WatchlistCandidate> Candidates { get; init; } = new();
    }

    internal sealed record WatchlistCandidate
    {
        [JsonPropertyName("pr")]
        public int Pr { get; init; }

        [JsonPropertyName("title")]
        public string? Title { get; init; }

        [JsonPropertyName("status")]
        public string? Status { get; init; }

        [JsonPropertyName("epic")]
        public string? Epic { get; init; }
    }

    /// <summary>One .helios/absorption/pr-N.json report written by the absorption benchmark.</summary>
    internal sealed record BenchmarkReport
    {
        [JsonPropertyName("pr")]
        public int Pr { get; init; }

        [JsonPropertyName("verdict")]
        public string? Verdict { get; init; }

        [JsonPropertyName("gatePassed")]
        public bool? GatePassed { get; init; }

        [JsonPropertyName("benchmarked")]
        public string? Benchmarked { get; init; }
    }

    internal sealed record AbsorbSummary
    {
        [JsonPropertyName("upstream")]
        public string? Upstream { get; init; }

        [JsonPropertyName("total")]
        public int Total { get; init; }

        [JsonPropertyName("by_status")]
        public SortedDictionary<string, int> ByStatus { get; init; } = new(StringComparer.Ordinal);

        [JsonPropertyName("candidates")]
        public List<AbsorbCandidateRow> Candidates { get; init; } = new();

        [JsonPropertyName("warnings")]
        public List<string>? Warnings { get; init; }
    }

    internal sealed record AbsorbCandidateRow
    {
        [JsonPropertyName("pr")]
        public int Pr { get; init; }

        [JsonPropertyName("title")]
        public string? Title { get; init; }

        [JsonPropertyName("status")]
        public string? Status { get; init; }

        [JsonPropertyName("epic")]
        public string? Epic { get; init; }

        [JsonPropertyName("verdict")]
        public string? Verdict { get; init; }

        [JsonPropertyName("gatePassed")]
        public bool? GatePassed { get; init; }

        [JsonPropertyName("benchmarked")]
        public string? Benchmarked { get; init; }
    }

    // ---- fleet shapes (mirrors scripts/fleet/start-fleet.ps1's manifest) -----------

    internal sealed record FleetManifest
    {
        [JsonPropertyName("runId")]
        public string? RunId { get; init; }

        [JsonPropertyName("status")]
        public string? Status { get; init; }

        [JsonPropertyName("pools")]
        public List<FleetManifestPool> Pools { get; init; } = new();
    }

    internal sealed record FleetManifestPool
    {
        [JsonPropertyName("pool")]
        public string? Pool { get; init; }

        [JsonPropertyName("board")]
        public string? Board { get; init; }

        [JsonPropertyName("db")]
        public string? Db { get; init; }

        [JsonPropertyName("workers")]
        public List<JsonElement> Workers { get; init; } = new();
    }

    internal sealed record BoardFile
    {
        [JsonPropertyName("tasks")]
        public List<BoardTask> Tasks { get; init; } = new();
    }

    internal sealed record BoardTask
    {
        [JsonPropertyName("status")]
        public string? Status { get; init; }
    }

    internal sealed record FleetReport
    {
        [JsonPropertyName("runs")]
        public List<FleetRunRow> Runs { get; init; } = new();

        [JsonPropertyName("message")]
        public string? Message { get; init; }

        [JsonPropertyName("warnings")]
        public List<string>? Warnings { get; init; }
    }

    internal sealed record FleetRunRow
    {
        [JsonPropertyName("runId")]
        public string? RunId { get; init; }

        [JsonPropertyName("status")]
        public string? Status { get; init; }

        [JsonPropertyName("pools")]
        public List<FleetPoolRow> Pools { get; init; } = new();
    }

    internal sealed record FleetPoolRow
    {
        [JsonPropertyName("pool")]
        public string? Pool { get; init; }

        [JsonPropertyName("board")]
        public string? Board { get; init; }

        [JsonPropertyName("workers")]
        public int Workers { get; init; }

        [JsonPropertyName("openTasks")]
        public int OpenTasks { get; init; }

        [JsonPropertyName("claimedTasks")]
        public int ClaimedTasks { get; init; }

        [JsonPropertyName("doneTasks")]
        public int DoneTasks { get; init; }

        [JsonPropertyName("blockedTasks")]
        public int BlockedTasks { get; init; }

        [JsonPropertyName("workersLive")]
        public int WorkersLive { get; init; }
    }
}
