using System.Text;
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

    /// <summary>
    /// Provenance for ADVISORY outcomes ingested from outside the hub — e.g.
    /// "absorption-benchmark", "fork-observation", or "fleet-lane" (lane outcomes from
    /// the fleet collector, whose provider values are lane names like
    /// "pool:xcore-9-code", not providers). Null means a live provider outcome recorded
    /// by the hub itself. Advisory records inform /v1/insights narratives and the
    /// /v1/metrics telemetry aggregates; adaptive routing and fleet-plan exclude every
    /// source-tagged record so external signals can never steer the provider chains
    /// directly.
    /// </summary>
    [JsonPropertyName("source")]
    public string? Source { get; init; }
}

/// <summary>
/// Where routing outcomes are recorded and read back.
///
/// Deliberately narrow: append one outcome, read recent ones for a task type (what
/// routing needs), or read recent ones across every task type (what /v1/metrics
/// telemetry needs). Anything richer belongs in a real analytics store, and keeping
/// this small is what lets the local and Azure backends stay interchangeable.
/// </summary>
public interface ILearningStore
{
    Task RecordAsync(RoutingOutcome outcome, CancellationToken cancellationToken = default);

    /// <summary>Recent outcomes for a task type, newest first, capped by <paramref name="limit"/>.</summary>
    Task<IReadOnlyList<RoutingOutcome>> GetRecentAsync(
        string taskType, int limit = 200, CancellationToken cancellationToken = default);

    /// <summary>
    /// Recent outcomes across ALL task types, newest first, capped by
    /// <paramref name="limit"/>. A display/telemetry read (per-provider aggregates for
    /// /v1/metrics); routing decisions always read one task type via
    /// <see cref="GetRecentAsync"/> so cross-task history can never steer a chain.
    /// </summary>
    Task<IReadOnlyList<RoutingOutcome>> GetRecentAllAsync(
        int limit = 200, CancellationToken cancellationToken = default);
}

/// <summary>Discards everything. The default, so learning is opt-in rather than surprising.</summary>
public sealed class NullLearningStore : ILearningStore
{
    public Task RecordAsync(RoutingOutcome outcome, CancellationToken cancellationToken = default) =>
        Task.CompletedTask;

    public Task<IReadOnlyList<RoutingOutcome>> GetRecentAsync(
        string taskType, int limit = 200, CancellationToken cancellationToken = default) =>
        Task.FromResult<IReadOnlyList<RoutingOutcome>>(Array.Empty<RoutingOutcome>());

    public Task<IReadOnlyList<RoutingOutcome>> GetRecentAllAsync(
        int limit = 200, CancellationToken cancellationToken = default) =>
        Task.FromResult<IReadOnlyList<RoutingOutcome>>(Array.Empty<RoutingOutcome>());
}

/// <summary>
/// Append-only JSONL on local disk — the default when learning is enabled.
///
/// JSONL rather than a database because the file is greppable, diffable, trivially
/// shipped to Azure later, and survives a crash mid-write with at most one bad line.
/// Appends are serialized through a semaphore within the process, and through an
/// adjacent .lock file across processes: with learning on in the shipped config, the
/// API host, the MCP server, and ad-hoc CLI invocations all append to the SAME file,
/// so a process-local gate alone would let appends collide (sharing IOExceptions the
/// callers swallow best-effort, or interleaved partial lines readers must skip —
/// either way, silently lost outcomes).
/// </summary>
public sealed class LocalJsonlLearningStore : ILearningStore, IDisposable
{
    // ~10 bounded attempts with short jittered backoff: enough to ride out another
    // process's append (microseconds long), small enough that a wedged lock file
    // degrades to the usual best-effort IOException in well under two seconds.
    private const int MaxAppendAttempts = 10;

    private readonly string _path;
    private readonly string _lockPath;
    private readonly SemaphoreSlim _writeGate = new(1, 1);

    public LocalJsonlLearningStore(string path)
    {
        _path = path;
        _lockPath = path + ".lock";
        var directory = Path.GetDirectoryName(Path.GetFullPath(path));
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }
    }

    public async Task RecordAsync(RoutingOutcome outcome, CancellationToken cancellationToken = default)
    {
        // The full line is materialized as one buffer up front so the append below is a
        // single unbuffered write: a completed (or even torn-off) call can never leave a
        // partial line for readers to skip.
        var payload = Encoding.UTF8.GetBytes(JsonSerializer.Serialize(outcome) + Environment.NewLine);
        await _writeGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            for (var attempt = 1; ; attempt++)
            {
                try
                {
                    // FileShare.None on the adjacent .lock file is the cross-process
                    // mutex (advisory flock on Unix, mandatory sharing on Windows); the
                    // loser's open throws IOException immediately and retries below.
                    // The lock file is never deleted: deleting it would race a peer
                    // opening the old inode, and two "exclusive" holders on different
                    // inodes is no lock at all.
                    using var interprocessLock = new FileStream(
                        _lockPath, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
                    // The data file itself stays share-friendly (readers use
                    // FileShare.ReadWrite in GetRecentAsync); bufferSize: 0 disables
                    // FileStream buffering so the single WriteAsync is one OS append.
                    var stream = new FileStream(
                        _path, FileMode.Append, FileAccess.Write, FileShare.ReadWrite,
                        bufferSize: 0, FileOptions.Asynchronous);
                    await using (stream.ConfigureAwait(false))
                    {
                        await stream.WriteAsync(payload, cancellationToken).ConfigureAwait(false);
                    }
                    return;
                }
                catch (IOException) when (attempt < MaxAppendAttempts)
                {
                    // Jittered so N processes contending for the lock spread out
                    // instead of retrying in lockstep.
                    await Task.Delay(Random.Shared.Next(5, 30) * attempt, cancellationToken)
                        .ConfigureAwait(false);
                }
            }
            // Final-attempt IOException propagates: callers already treat recording as
            // best-effort (AIHub.RecordOutcomeAsync swallows IOException), preserving
            // the never-crash-the-hub degradation contract.
        }
        finally
        {
            _writeGate.Release();
        }
    }

    public Task<IReadOnlyList<RoutingOutcome>> GetRecentAsync(
        string taskType, int limit = 200, CancellationToken cancellationToken = default) =>
        ReadTailAsync(taskType, limit, cancellationToken);

    public Task<IReadOnlyList<RoutingOutcome>> GetRecentAllAsync(
        int limit = 200, CancellationToken cancellationToken = default) =>
        ReadTailAsync(taskType: null, limit, cancellationToken);

    /// <summary>Null <paramref name="taskType"/> means every task type (telemetry reads).</summary>
    private async Task<IReadOnlyList<RoutingOutcome>> ReadTailAsync(
        string? taskType, int limit, CancellationToken cancellationToken)
    {
        if (!File.Exists(_path))
        {
            return Array.Empty<RoutingOutcome>();
        }

        // Stream forward keeping a bounded tail window: the log is append-only and
        // grows with every routed attempt, so materializing and deserializing the whole
        // file would make routing latency grow with total history. When a taskType is
        // given, the substring pre-filter skips deserializing other tasks' lines
        // entirely (the JSON string form of the task type, quotes included, can only
        // appear in matching records or — rarely — inside another string field, which
        // the exact check below drops). A null taskType (GetRecentAllAsync, telemetry
        // reads) disables the pre-filter by design: every non-empty line is
        // deserialized, so that path scales with total file size, not the window.
        var window = new Queue<RoutingOutcome>(limit);
        var taskTypeToken = taskType is null ? null : JsonSerializer.Serialize(taskType);
        await Task.Yield();
        // FileShare.ReadWrite: File.ReadLines holds a read-only share for the whole
        // enumeration, which on Windows blocks a concurrent append — and the appender
        // swallows IOException as best-effort, silently losing that outcome.
        using var stream = new FileStream(_path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        using var reader = new StreamReader(stream);
        while (reader.ReadLine() is { } line)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (string.IsNullOrWhiteSpace(line)
                || (taskTypeToken is not null && !line.Contains(taskTypeToken, StringComparison.Ordinal)))
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
            if (outcome is not null && (taskType is null || outcome.TaskType == taskType))
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
