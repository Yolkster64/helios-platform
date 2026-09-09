using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using HELIOS.AIHub.Routing;

namespace HELIOS.AIHub.Learning;

public sealed record SuccessInterval(double Lower, double Upper);

public sealed record ComboCandidate(
    string Provider, string Model, string? Pool, int Attempts, int Successes,
    double SuccessRate, SuccessInterval Wilson95,
    int QualitySamples, double? MeanQuality,
    int LatencySamples, double? MeanLatencyMs,
    int PositiveCostSamples, double? MeanPositiveCostUsd,
    bool CompleteTradeoffEvidence, bool? OnObservedParetoFrontier,
    IReadOnlyList<string> OutcomeIds, int MissingOutcomeIds);

/// <summary>A reproducible, advisory snapshot, never a routing instruction or a trained model.</summary>
public sealed record ComboAnalysisReport(
    string SchemaVersion, string Mode, string TaskType, string? Language,
    string SnapshotSha256, int InputRows, int DuplicateRows, int ConflictingRows,
    int ScopedOrganicRows, int WindowLimit, bool WindowTruncated,
    DateTimeOffset? WindowStart, DateTimeOffset? WindowEnd,
    IReadOnlyDictionary<string, int> AdvisorySourceRows,
    IReadOnlyList<ComboCandidate> Candidates, IReadOnlyList<string> EvidenceGaps);

/// <summary>
/// Pure bounded analysis over an exported learning JSONL snapshot. It has no provider,
/// network, learning-store writer or routing dependency. Source-tagged evidence stays
/// visible but never joins organic provider estimates. Legacy zero cost is unknown.
/// </summary>
public static class ComboAnalysisService
{
    public const int MaxSnapshotBytes = 16 * 1024 * 1024;
    public const int MaxRows = 10_000;
    public const int MaxWindow = 2_000;
    private const double Z95 = 1.959963984540054;

    public static ComboAnalysisReport AnalyzeJsonl(
        ReadOnlyMemory<byte> snapshot, string taskType, string? language = null, int limit = 200)
    {
        if (snapshot.Length > MaxSnapshotBytes)
        {
            throw new ArgumentException($"Outcome snapshot exceeds {MaxSnapshotBytes} bytes.");
        }
        if (string.IsNullOrWhiteSpace(taskType) || taskType.Length > 128 || taskType.Contains(':'))
        {
            throw new ArgumentException("Use a nonempty bare task type of at most 128 characters.");
        }
        if (limit is < 1 or > MaxWindow)
        {
            throw new ArgumentException($"Window limit must be between 1 and {MaxWindow}.");
        }
        language = TaskTypeRoutingStrategy.NormalizeLanguage(language);
        if (language?.Length > 128)
        {
            throw new ArgumentException("Language must be at most 128 characters.");
        }

        var rows = ReadRows(snapshot);
        // Stable outcome IDs prevent repeated imports from increasing confidence.
        // Conflicting versions are excluded together, never silently last-write-wins.
        var identified = rows.Where(r => !string.IsNullOrWhiteSpace(r.OutcomeId))
            .GroupBy(r => r.OutcomeId!, StringComparer.Ordinal).ToArray();
        var conflicts = identified.Where(g => g.Distinct().Skip(1).Any()).ToArray();
        var conflictingIds = conflicts.Select(g => g.Key).ToHashSet(StringComparer.Ordinal);
        var duplicateRows = identified.Where(g => !conflictingIds.Contains(g.Key))
            .Sum(g => g.Count() - 1);
        var unique = rows.Where(r => string.IsNullOrWhiteSpace(r.OutcomeId))
            .Concat(identified.Where(g => !conflictingIds.Contains(g.Key)).Select(g => g.First()));
        var scoped = unique.Where(r => r.TaskType == taskType
            && TaskTypeRoutingStrategy.NormalizeLanguage(r.Language) == language).ToArray();
        var sourceCounts = scoped.Where(r => r.Source is not null)
            .GroupBy(r => r.Source!, StringComparer.Ordinal)
            .OrderBy(g => g.Key, StringComparer.Ordinal)
            .ToDictionary(g => g.Key, g => g.Count(), StringComparer.Ordinal);
        // Scope before truncation: imported/fleet sources cannot crowd out organic history.
        var organic = scoped.Where(r => r.Source is null)
            .OrderByDescending(r => r.Timestamp)
            .ThenBy(r => r.Provider, StringComparer.Ordinal)
            .ThenBy(r => r.Model, StringComparer.Ordinal)
            .ThenBy(r => r.Pool, StringComparer.Ordinal)
            .ThenBy(r => r.OutcomeId, StringComparer.Ordinal)
            .ThenBy(r => JsonSerializer.Serialize(r), StringComparer.Ordinal).ToArray();
        var window = organic.Take(limit).ToArray();
        var candidates = window.GroupBy(r => (r.Provider, r.Model, r.Pool))
            .OrderBy(g => g.Key.Provider, StringComparer.Ordinal)
            .ThenBy(g => g.Key.Model, StringComparer.Ordinal)
            .ThenBy(g => g.Key.Pool, StringComparer.Ordinal)
            .Select(g => Aggregate(g.ToArray())).ToArray();
        // Pareto membership is descriptive over complete observed dimensions only.
        // It is deliberately not a weighted routing score or a significance claim.
        var eligible = candidates.Where(c => c.CompleteTradeoffEvidence).ToArray();
        candidates = candidates.Select(c => c with
        {
            OnObservedParetoFrontier = c.CompleteTradeoffEvidence && eligible.Length >= 2
                ? !eligible.Any(other => Dominates(other, c)) : null,
        }).ToArray();

        var gaps = new List<string>
        {
            "Snapshot provenance is caller-supplied; source=null declares organic history but does not authenticate it.",
            "Outcomes lack paired task/request identities; correlation, complementarity and combo success are unknown.",
            "Wilson intervals assume independent comparable Bernoulli trials; routing history may violate this assumption.",
            "Pareto membership describes sample means, not causal superiority, statistical significance or a recommended route.",
            "Positive cost values are reported estimates; zero cannot distinguish missing telemetry from free execution.",
            "This report neither calls models nor trains, changes routes, records outcomes or activates fleets.",
        };
        if (window.Length == 0) gaps.Add("No organic outcomes exist in the requested task/language scope.");
        if (conflicts.Length > 0) gaps.Add("Conflicting outcome IDs were excluded; repair provenance before using these records.");
        if (window.Any(r => string.IsNullOrWhiteSpace(r.OutcomeId))) gaps.Add("Legacy rows without outcome IDs cannot be reliably deduplicated.");
        if (candidates.Any(c => c.Attempts < 5)) gaps.Add("Some provider/model/pool groups have fewer than five attempts; evidence remains sparse.");
        if (candidates.Any(c => !c.CompleteTradeoffEvidence)) gaps.Add("Incomplete quality, positive latency or positive cost coverage prevents full tradeoff comparison for some candidates.");
        if (eligible.Length < 2) gaps.Add("Fewer than two candidates have complete tradeoff evidence; no Pareto comparison was made.");
        if (sourceCounts.Count > 0) gaps.Add("Source-tagged advisory outcomes are retained as source counts and excluded from provider comparisons.");

        return new("1", "offline-advisory", taskType, language,
            Convert.ToHexStringLower(SHA256.HashData(snapshot.Span)), rows.Count, duplicateRows,
            conflicts.Sum(g => g.Count()), organic.Length, limit, organic.Length > limit,
            window.Length == 0 ? null : window.Min(r => r.Timestamp),
            window.Length == 0 ? null : window.Max(r => r.Timestamp), sourceCounts, candidates, gaps);
    }

    /// <summary>Two-sided 95% Wilson score interval; zero samples stays [0,1].</summary>
    public static SuccessInterval Wilson95(int successes, int attempts)
    {
        if (attempts < 0 || successes < 0 || successes > attempts)
            throw new ArgumentOutOfRangeException(nameof(successes));
        if (attempts == 0) return new(0, 1);
        var p = (double)successes / attempts;
        var z2 = Z95 * Z95;
        var denominator = 1 + z2 / attempts;
        var center = (p + z2 / (2 * attempts)) / denominator;
        var half = Z95 * Math.Sqrt(p * (1 - p) / attempts + z2 / (4 * attempts * (double)attempts)) / denominator;
        return new(Math.Clamp(center - half, 0, 1), Math.Clamp(center + half, 0, 1));
    }

    private static ComboCandidate Aggregate(RoutingOutcome[] rows)
    {
        var quality = rows.Where(r => r.Quality.HasValue).Select(r => r.Quality!.Value).ToArray();
        var latency = rows.Where(r => r.LatencyMs > 0).Select(r => r.LatencyMs).ToArray();
        var costs = rows.Where(r => r.CostUsd > 0).Select(r => r.CostUsd).ToArray();
        var successes = rows.Count(r => r.Success);
        return new(rows[0].Provider, rows[0].Model, rows[0].Pool, rows.Length, successes,
            (double)successes / rows.Length, Wilson95(successes, rows.Length),
            quality.Length, Mean(quality), latency.Length, Mean(latency), costs.Length, Mean(costs),
            quality.Length == rows.Length && latency.Length == rows.Length && costs.Length == rows.Length,
            null, rows.Where(r => !string.IsNullOrWhiteSpace(r.OutcomeId)).Select(r => r.OutcomeId!)
                .Order(StringComparer.Ordinal).ToArray(), rows.Count(r => string.IsNullOrWhiteSpace(r.OutcomeId)));
    }

    private static double? Mean(double[] values) => values.Length == 0 ? null : values.Average();

    private static bool Dominates(ComboCandidate a, ComboCandidate b) =>
        a.SuccessRate >= b.SuccessRate && a.MeanQuality >= b.MeanQuality
        && a.MeanLatencyMs <= b.MeanLatencyMs && a.MeanPositiveCostUsd <= b.MeanPositiveCostUsd
        && (a.SuccessRate > b.SuccessRate || a.MeanQuality > b.MeanQuality
            || a.MeanLatencyMs < b.MeanLatencyMs || a.MeanPositiveCostUsd < b.MeanPositiveCostUsd);

    private static List<RoutingOutcome> ReadRows(ReadOnlyMemory<byte> snapshot)
    {
        var result = new List<RoutingOutcome>();
        // Reject malformed UTF-8 instead of hashing one byte stream but silently
        // analyzing replacement characters from a different interpretation.
        string text;
        try
        {
            text = new UTF8Encoding(false, true).GetString(snapshot.Span).TrimStart('\uFEFF');
        }
        catch (DecoderFallbackException)
        {
            throw new ArgumentException("Outcome snapshot is not valid UTF-8; raw bytes omitted.");
        }
        using var reader = new StringReader(text);
        var lineNumber = 0;
        while (reader.ReadLine() is { } line)
        {
            lineNumber++;
            if (string.IsNullOrWhiteSpace(line)) continue;
            if (result.Count >= MaxRows) throw new ArgumentException($"Outcome snapshot exceeds {MaxRows} rows.");
            try
            {
                using var document = JsonDocument.Parse(line);
                var root = document.RootElement;
                if (root.ValueKind != JsonValueKind.Object
                    || !Has(root, "success", JsonValueKind.True, JsonValueKind.False)
                    || !Has(root, "latencyMs", JsonValueKind.Number)
                    || !Has(root, "costUsd", JsonValueKind.Number)
                    || !Has(root, "timestamp", JsonValueKind.String))
                    throw new JsonException();
                // Duplicate keys would let a hidden source or ID be overwritten by
                // deserialization, so ambiguous records are rejected as a whole.
                var keys = root.EnumerateObject().Select(p => p.Name).ToArray();
                if (keys.Distinct(StringComparer.OrdinalIgnoreCase).Count() != keys.Length) throw new JsonException();
                var known = new[] { "outcomeId", "timestamp", "taskType", "language", "provider", "model",
                    "success", "latencyMs", "costUsd", "quality", "pool", "source" };
                if (keys.Any(key => known.Contains(key, StringComparer.OrdinalIgnoreCase)
                    && !known.Contains(key, StringComparer.Ordinal))) throw new JsonException();
                var row = root.Deserialize<RoutingOutcome>() ?? throw new JsonException();
                if (string.IsNullOrWhiteSpace(row.TaskType) || string.IsNullOrWhiteSpace(row.Provider)
                    || row.Model is null || row.Timestamp == default
                    || !double.IsFinite(row.LatencyMs) || row.LatencyMs is < 0 or > 1e12
                    || !double.IsFinite(row.CostUsd) || row.CostUsd is < 0 or > 1e12
                    || row.Quality is { } q && (!double.IsFinite(q) || q is < 0 or > 1)
                    || new[] { row.TaskType, row.Provider, row.Model, row.Language, row.Pool, row.Source, row.OutcomeId }
                        .Any(value => value?.Length > 256)) throw new JsonException();
                result.Add(row);
            }
            catch (JsonException)
            {
                throw new ArgumentException($"Invalid routing outcome at line {lineNumber}; raw record omitted.");
            }
        }
        return result;
    }

    private static bool Has(JsonElement root, string key, params JsonValueKind[] kinds) =>
        root.TryGetProperty(key, out var value) && kinds.Contains(value.ValueKind);
}
