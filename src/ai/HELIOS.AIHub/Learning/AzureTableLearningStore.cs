using Azure;
using Azure.Data.Tables;
using Azure.Identity;

namespace HELIOS.AIHub.Learning;

/// <summary>
/// Azure Table Storage backend — the shared-memory option, so every fleet worker and
/// every developer machine learns from the same history instead of each keeping a
/// private local file.
///
/// Table Storage rather than Cosmos: outcomes are append-heavy, queried by exactly one
/// key (task type), and cost pennies at this volume. Partitioning by task type makes the
/// only query we run a single-partition scan.
///
/// Auth is <c>DefaultAzureCredential</c>, so the same code path works with a managed
/// identity in Azure, workload identity in AKS, and `az login` locally.
/// </summary>
public sealed class AzureTableLearningStore : ILearningStore
{
    private const string TableName = "aihubOutcomes";

    private readonly TableClient _table;
    private readonly SemaphoreSlim _initGate = new(1, 1);
    private bool _initialized;

    /// <param name="endpoint">Table service endpoint, e.g. https://acct.table.core.windows.net.</param>
    public AzureTableLearningStore(Uri endpoint)
    {
        _table = new TableClient(endpoint, TableName, new DefaultAzureCredential());
    }

    private async Task EnsureTableAsync(CancellationToken cancellationToken)
    {
        if (_initialized)
        {
            return;
        }
        await _initGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (!_initialized)
            {
                await _table.CreateIfNotExistsAsync(cancellationToken).ConfigureAwait(false);
                _initialized = true;
            }
        }
        finally
        {
            _initGate.Release();
        }
    }

    public async Task RecordAsync(RoutingOutcome outcome, CancellationToken cancellationToken = default)
    {
        await EnsureTableAsync(cancellationToken).ConfigureAwait(false);

        // Descending row key: Table Storage sorts ascending, and we always want newest
        // first, so store the complement of the timestamp and read straight off the top.
        var inverted = DateTimeOffset.MaxValue.Ticks - outcome.Timestamp.Ticks;
        var entity = new TableEntity(Sanitize(outcome.TaskType), $"{inverted:D19}-{Guid.NewGuid():N}")
        {
            ["TaskType"] = outcome.TaskType,
            ["Provider"] = outcome.Provider,
            ["Model"] = outcome.Model,
            ["Success"] = outcome.Success,
            ["LatencyMs"] = outcome.LatencyMs,
            ["CostUsd"] = outcome.CostUsd,
            ["Quality"] = outcome.Quality,
            ["Pool"] = outcome.Pool,
            ["OccurredAt"] = outcome.Timestamp,
        };

        await _table.AddEntityAsync(entity, cancellationToken).ConfigureAwait(false);
    }

    public async Task<IReadOnlyList<RoutingOutcome>> GetRecentAsync(
        string taskType, int limit = 200, CancellationToken cancellationToken = default)
    {
        await EnsureTableAsync(cancellationToken).ConfigureAwait(false);

        var partition = Sanitize(taskType);
        var results = new List<RoutingOutcome>(limit);
        // Also filter the stored TaskType: Sanitize can map distinct task types (e.g.
        // "customer/a" and "customer?a") onto one partition, and cross-task history
        // would train one task's routing on another task's outcomes.
        var escapedTaskType = taskType.Replace("'", "''");
        var query = _table.QueryAsync<TableEntity>(
            filter: $"PartitionKey eq '{partition}' and TaskType eq '{escapedTaskType}'",
            maxPerPage: Math.Min(limit, 1000),
            cancellationToken: cancellationToken);

        await foreach (var entity in query.ConfigureAwait(false))
        {
            results.Add(new RoutingOutcome
            {
                Timestamp = entity.GetDateTimeOffset("OccurredAt") ?? entity.Timestamp ?? DateTimeOffset.MinValue,
                TaskType = entity.GetString("TaskType") ?? taskType,
                Provider = entity.GetString("Provider") ?? "",
                Model = entity.GetString("Model") ?? "",
                Success = entity.GetBoolean("Success") ?? false,
                LatencyMs = entity.GetDouble("LatencyMs") ?? 0,
                CostUsd = entity.GetDouble("CostUsd") ?? 0,
                Quality = entity.GetDouble("Quality"),
                Pool = entity.GetString("Pool"),
            });
            if (results.Count >= limit)
            {
                break;
            }
        }

        return results;
    }

    /// <summary>Table keys forbid / \ # ? and control characters.</summary>
    private static string Sanitize(string key)
    {
        Span<char> buffer = stackalloc char[key.Length];
        for (var i = 0; i < key.Length; i++)
        {
            var c = key[i];
            buffer[i] = c is '/' or '\\' or '#' or '?' || char.IsControl(c) ? '_' : c;
        }
        return buffer.IsEmpty ? "default" : new string(buffer);
    }
}

/// <summary>
/// Writes to a local file and Azure, reading from whichever answers — the hybrid mode the
/// fleet runs in. Azure failures never break a call: learning is an optimization, so a
/// storage outage degrades routing quality rather than taking the hub down with it.
/// </summary>
public sealed class HybridLearningStore : ILearningStore
{
    private readonly ILearningStore _local;
    private readonly ILearningStore _remote;

    public HybridLearningStore(ILearningStore local, ILearningStore remote)
    {
        _local = local;
        _remote = remote;
    }

    public async Task RecordAsync(RoutingOutcome outcome, CancellationToken cancellationToken = default)
    {
        await _local.RecordAsync(outcome, cancellationToken).ConfigureAwait(false);
        try
        {
            await _remote.RecordAsync(outcome, cancellationToken).ConfigureAwait(false);
        }
        catch (RequestFailedException)
        {
            // Local copy is authoritative for this process; a sync job reconciles later.
        }
        catch (AuthenticationFailedException)
        {
        }
    }

    public async Task<IReadOnlyList<RoutingOutcome>> GetRecentAsync(
        string taskType, int limit = 200, CancellationToken cancellationToken = default)
    {
        // Merge, never prefer: local writes always land first and remote writes are
        // best-effort, so after an Azure outage the local store holds outcomes the
        // table never saw — returning a non-empty remote result alone would serve
        // stale history until some external reconciliation ran.
        IReadOnlyList<RoutingOutcome> remote = Array.Empty<RoutingOutcome>();
        try
        {
            remote = await _remote.GetRecentAsync(taskType, limit, cancellationToken).ConfigureAwait(false);
        }
        catch (RequestFailedException)
        {
        }
        catch (AuthenticationFailedException)
        {
        }

        var local = await _local.GetRecentAsync(taskType, limit, cancellationToken).ConfigureAwait(false);

        return remote.Concat(local)
            .DistinctBy(o => (o.Timestamp, o.Provider, o.Model, o.Success, o.LatencyMs))
            .OrderByDescending(o => o.Timestamp)
            .Take(limit)
            .ToList();
    }
}
