using System.Text.Json;
using System.Text.Json.Serialization;

namespace HELIOS.AIHub.Cli;

/// <summary>
/// Read-only engine behind `helios-ai absorb-status`: summarizes the curated upstream-PR
/// watchlist (config/absorption/pr-watchlist.json) and overlays any benchmark reports the
/// absorption pipeline wrote to .helios/absorption/pr-*.json. Nothing here fetches,
/// merges, or mutates anything — it only reports.
/// </summary>
public static class AbsorptionStatus
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

    /// <summary>
    /// Finds config/absorption/pr-watchlist.json the same way
    /// <see cref="Configuration.AIHubOptions.FindConfigFile"/> finds config/aihub.json:
    /// walking up from <paramref name="startDirectory"/> (or the current directory, then
    /// the app base directory), so the command works from any subdirectory of the repo
    /// AND as a published artifact that ships its own config/ folder.
    /// </summary>
    public static string? FindWatchlistFile(string? startDirectory = null)
    {
        var starts = startDirectory is not null
            ? new[] { startDirectory }
            : new[] { Directory.GetCurrentDirectory(), AppContext.BaseDirectory };

        foreach (var start in starts)
        {
            var dir = new DirectoryInfo(start);
            while (dir is not null)
            {
                var candidate = Path.Combine(
                    dir.FullName, "config", "absorption", "pr-watchlist.json");
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
    /// Writes the absorption summary to <paramref name="output"/> as JSON:
    /// { upstream, total, by_status, candidates: [{ pr, title, status, epic?, verdict?,
    /// benchmarked? }] }. Returns 0 on success; 1 (with a one-line message on
    /// <paramref name="error"/>) when the watchlist is missing or unreadable. An
    /// unreadable individual report is skipped with a warning — one broken benchmark
    /// report must not hide the rest of the status.
    /// </summary>
    public static int Execute(string? startDirectory, TextWriter output, TextWriter error)
    {
        var watchlistPath = FindWatchlistFile(startDirectory);
        if (watchlistPath is null)
        {
            error.WriteLine(
                "config/absorption/pr-watchlist.json not found in this directory or any parent; run from the repo checkout.");
            return 1;
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
            error.WriteLine($"Failed to read '{watchlistPath}': {ex.Message}");
            return 1;
        }

        var reports = LoadReports(ReportsDirectoryFor(watchlistPath), error);

        var rows = new List<CandidateRow>();
        var byStatus = new SortedDictionary<string, int>(StringComparer.Ordinal);
        foreach (var candidate in watchlist.Candidates)
        {
            var status = string.IsNullOrWhiteSpace(candidate.Status) ? "unknown" : candidate.Status;
            byStatus[status] = byStatus.GetValueOrDefault(status) + 1;
            reports.TryGetValue(candidate.Pr, out var report);
            rows.Add(new CandidateRow
            {
                Pr = candidate.Pr,
                Title = candidate.Title,
                Status = status,
                Epic = candidate.Epic,
                Verdict = report?.Verdict,
                Benchmarked = report?.Benchmarked,
            });
        }

        var summary = new Summary
        {
            Upstream = watchlist.Upstream,
            Total = rows.Count,
            ByStatus = new Dictionary<string, int>(byStatus),
            Candidates = rows,
        };
        output.WriteLine(JsonSerializer.Serialize(summary, WriteOptions));
        return 0;
    }

    /// <summary>&lt;root&gt;/config/absorption/pr-watchlist.json → &lt;root&gt;/.helios/absorption.</summary>
    private static string? ReportsDirectoryFor(string watchlistPath)
    {
        var absorptionDir = Path.GetDirectoryName(Path.GetFullPath(watchlistPath));
        var configDir = string.IsNullOrEmpty(absorptionDir) ? null : Path.GetDirectoryName(absorptionDir);
        var root = string.IsNullOrEmpty(configDir) ? null : Path.GetDirectoryName(configDir);
        return string.IsNullOrEmpty(root) ? null : Path.Combine(root, ".helios", "absorption");
    }

    private static Dictionary<int, BenchmarkReport> LoadReports(
        string? reportsDirectory, TextWriter error)
    {
        var reports = new Dictionary<int, BenchmarkReport>();
        if (reportsDirectory is null || !Directory.Exists(reportsDirectory))
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
                error.WriteLine($"[absorb-status] skipping unreadable report '{file}': {ex.Message}");
            }
        }
        return reports;
    }

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

        [JsonPropertyName("benchmarked")]
        public string? Benchmarked { get; init; }
    }

    internal sealed record Summary
    {
        [JsonPropertyName("upstream")]
        public string? Upstream { get; init; }

        [JsonPropertyName("total")]
        public int Total { get; init; }

        [JsonPropertyName("by_status")]
        public Dictionary<string, int> ByStatus { get; init; } = new();

        [JsonPropertyName("candidates")]
        public List<CandidateRow> Candidates { get; init; } = new();
    }

    internal sealed record CandidateRow
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

        [JsonPropertyName("benchmarked")]
        public string? Benchmarked { get; init; }
    }
}
