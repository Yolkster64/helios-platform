using System.Text.Json;
using System.Text.Json.Serialization;

namespace HELIOS.AIHub.Learning;

/// <summary>One recorded routing outcome — the unit the hub learns from.</summary>
public sealed record RoutingOutcome
{
    [JsonPropertyName("timestamp")]
    public DateTimeOffset Timestamp { get; init; }

    [JsonPropertyName("taskType")]
    public string TaskType { get; init; } = "";

    [JsonPropertyName("provider")]
    public string Provider { get; init; } = "";

    [JsonPropertyName("model")]
    public string Model { get; init; } = "";

    [JsonPropertyName("success")]
    public bool Success { get; init; }

    [JsonPropertyName("latencyMs")]
    public double LatencyMs { get; init; }

    [JsonPropertyName("costUsd")]
    public double CostUsd { get; init; }

    /// <summary>Optional judge/human rating in [0,1]; null means unrated.</summary>
    [JsonPropertyName("quality")]
    public double? Quality { get; init; }

    /// <summary>Which fleet pool produced this, when dispatched by the fleet.</summary>
    [JsonPropertyName("pool")]
    public string? Pool { get; init; }
}

/// <summary>
/// Where routing outcomes are recorded and read back.
///
/// Deliberately narrow: append one outcome, read recent ones for a task type. Anything
/// richer belongs in a real analytics store, and keeping this small is what lets the
/// local and Azure backends stay interchangeable.
/// </summary>
public interface ILearningStore
{
    Task RecordAsync(RoutingOutcome outcome, CancellationToken cancellationToken = default);

    /// <summary>Recent outcomes for a task type, newest first, capped by <paramref name="limit"/>.</summary>
    Task<IReadOnlyList<RoutingOutcome>> GetRecentAsync(
        string taskType, int limit = 200, CancellationToken cancellationToken = default);
}

/// <summary>Discards everything. The default, so learning is opt-in rather than surprising.</summary>
public sealed class NullLearningStore : ILearningStore
{
    public Task RecordAsync(RoutingOutcome outcome, CancellationToken cancellationToken = default) =>
        Task.CompletedTask;

    public Task<IReadOnlyList<RoutingOutcome>> GetRecentAsync(
        string taskType, int limit = 200, CancellationToken cancellationToken = default) =>
        Task.FromResult<IReadOnlyList<RoutingOutcome>>(Array.Empty<RoutingOutcome>());
}

/// <summary>
/// Append-only JSONL on local disk — the default when learning is enabled.
///
/// JSONL rather than a database because the file is greppable, diffable, trivially
/// shipped to Azure later, and survives a crash mid-write with at most one bad line.
/// Appends are serialized through a semaphore; concurrent fan-out writes are the norm.
/// </summary>
public sealed class LocalJsonlLearningStore : ILearningStore, IDisposable
{
    private readonly string _path;
    private readonly SemaphoreSlim _writeGate = new(1, 1);

    public LocalJsonlLearningStore(string path)
    {
        _path = path;
        var directory = Path.GetDirectoryName(Path.GetFullPath(path));
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }
    }

    public async Task RecordAsync(RoutingOutcome outcome, CancellationToken cancellationToken = default)
    {
        var line = JsonSerializer.Serialize(outcome);
        await _writeGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            await File.AppendAllTextAsync(_path, line + Environment.NewLine, cancellationToken)
                .ConfigureAwait(false);
        }
        finally
        {
            _writeGate.Release();
        }
    }

    public async Task<IReadOnlyList<RoutingOutcome>> GetRecentAsync(
        string taskType, int limit = 200, CancellationToken cancellationToken = default)
    {
        if (!File.Exists(_path))
        {
            return Array.Empty<RoutingOutcome>();
        }

        // Stream forward keeping a bounded tail window: the log is append-only and
        // grows with every routed attempt, so materializing and deserializing the whole
        // file would make routing latency grow with total history. The substring
        // pre-filter skips deserializing other tasks' lines entirely (the JSON string
        // form of the task type, quotes included, can only appear in matching records
        // or — rarely — inside another string field, which the exact check below drops).
        var window = new Queue<RoutingOutcome>(limit);
        var taskTypeToken = JsonSerializer.Serialize(taskType);
        await Task.Yield();
        foreach (var line in File.ReadLines(_path))
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (string.IsNullOrWhiteSpace(line) || !line.Contains(taskTypeToken, StringComparison.Ordinal))
            {
                continue;
            }
            RoutingOutcome? outcome;
            try
            {
                outcome = JsonSerializer.Deserialize<RoutingOutcome>(line);
            }
            catch (JsonException)
            {
                continue; // A torn line from a crash must not poison the whole history.
            }
            if (outcome is not null && outcome.TaskType == taskType)
            {
                if (window.Count == limit)
                {
                    window.Dequeue();
                }
                window.Enqueue(outcome);
            }
        }

        var results = window.ToList();
        results.Reverse(); // chronological tail → newest first
        return results;
    }

    public void Dispose() => _writeGate.Dispose();
}
