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

    /// <summary>
    /// Absolute cap on the entities one scoped read examines, matches or not. The
    /// language-less and the organic reads filter client-side (an absent column cannot
    /// be filtered server-side), so without a cap a partition whose newest rows are all
    /// advisory or all another language's would be walked to its end on every route —
    /// a cheap, persistent write path (<c>POST /v1/learning</c> with the API key) turned
    /// into Azure transaction load and route latency. Two service pages at most.
    /// </summary>
    internal const int DefaultScanBudget = 2_000;

    private readonly TableClient _table;
    private readonly int _scanBudget;
    private readonly SemaphoreSlim _initGate = new(1, 1);
    private bool _initialized;

    /// <param name="endpoint">Table service endpoint, e.g. https://acct.table.core.windows.net.</param>
    public AzureTableLearningStore(Uri endpoint)
        : this(new TableClient(endpoint, TableName, new DefaultAzureCredential()))
    {
    }

    /// <summary>
    /// Test seam. The public constructor binds a DefaultAzureCredential client that no
    /// offline test can exercise, so the shape of every read — the OData filter that
    /// reaches the service, the client-side scoping, the cap ending the stream — is
    /// pinned through a TableClient double (its members are virtual for exactly this).
    /// </summary>
    internal AzureTableLearningStore(TableClient table, int scanBudget = DefaultScanBudget)
    {
        _table = table;
        _scanBudget = scanBudget > 0 ? scanBudget : DefaultScanBudget;
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
            ["OutcomeId"] = outcome.OutcomeId,
            ["TaskType"] = outcome.TaskType,
            ["Language"] = outcome.Language,
            ["Provider"] = outcome.Provider,
            ["Model"] = outcome.Model,
            ["Success"] = outcome.Success,
            ["LatencyMs"] = outcome.LatencyMs,
            ["CostUsd"] = outcome.CostUsd,
            ["Quality"] = outcome.Quality,
            ["Pool"] = outcome.Pool,
            ["Source"] = outcome.Source,
            // Indexed discriminator for the organic read: a null Source is an ABSENT
            // column, which no OData comparison can select, so the organic read filters
            // client-side today. Rows written from here on carry the flag; once every
            // row a deployment cares about has it (backfill, or the pre-flag rows aged
            // out of the window), the read can push "Organic eq true" server-side.
            ["Organic"] = outcome.Source is null,
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
        // Sanitize passes apostrophes through, so the partition key needs OData
        // escaping too or a task type like "customer's-review" breaks the filter.
        var escapedPartition = partition.Replace("'", "''");
        var escapedTaskType = taskType.Replace("'", "''");
        var query = _table.QueryAsync<TableEntity>(
            filter: $"PartitionKey eq '{escapedPartition}' and TaskType eq '{escapedTaskType}'",
            maxPerPage: Math.Min(limit, 1000),
            cancellationToken: cancellationToken);

        await foreach (var entity in query.ConfigureAwait(false))
        {
            results.Add(ToOutcome(entity, fallbackTaskType: taskType));
            if (results.Count >= limit)
            {
                break;
            }
        }

        return results;
    }

    public Task<IReadOnlyList<RoutingOutcome>> GetRecentForLanguageAsync(
        string taskType, string? language, int limit = 200, CancellationToken cancellationToken = default) =>
        ReadScopedAsync(taskType, language, limit, organicOnly: false, cancellationToken);

    public Task<IReadOnlyList<RoutingOutcome>> GetRecentOrganicForLanguageAsync(
        string taskType, string? language, int limit = 200, CancellationToken cancellationToken = default) =>
        ReadScopedAsync(taskType, language, limit, organicOnly: true, cancellationToken);

    /// <summary>
    /// The (taskType, language) window, optionally organic only, capped at
    /// <paramref name="limit"/> after scoping. What is pushed server-side and what is
    /// not follows one Table Storage rule: a null property is simply absent from the
    /// entity, and a comparison against an absent property evaluates to false.
    /// </summary>
    private async Task<IReadOnlyList<RoutingOutcome>> ReadScopedAsync(
        string taskType, string? language, int limit, bool organicOnly, CancellationToken cancellationToken)
    {
        await EnsureTableAsync(cancellationToken).ConfigureAwait(false);

        var escapedPartition = Sanitize(taskType).Replace("'", "''");
        var escapedTaskType = taskType.Replace("'", "''");
        // A qualified language is pushed into the OData filter. The language-less key
        // cannot be (an absent Language column is not "eq" anything), and neither can
        // organic-ness: an organic row has no Source column at all, so there is no
        // server-side "Source is absent" — an "eq" or "ne" on Source would drop the very
        // rows this read wants. Those cases stream the (server-filtered) partition
        // newest-first and keep the first <limit> rows that pass the client-side check
        // — either way the cap applies after scoping, never before. The walk itself is
        // bounded by the scan budget: after that many entities the read returns what it
        // found, so a partition flooded with rows the client-side check rejects costs a
        // fixed number of pages and reads as thin or no evidence (routing then keeps
        // its configured order) instead of a partition-length scan per route.
        var filter = $"PartitionKey eq '{escapedPartition}' and TaskType eq '{escapedTaskType}'";
        if (language is not null)
        {
            filter += $" and Language eq '{language.Replace("'", "''")}'";
        }

        var results = new List<RoutingOutcome>(limit);
        var query = _table.QueryAsync<TableEntity>(
            filter: filter,
            maxPerPage: Math.Min(limit, 1000),
            cancellationToken: cancellationToken);

        var examined = 0;
        await foreach (var entity in query.ConfigureAwait(false))
        {
            examined++;
            var outcome = ToOutcome(entity, fallbackTaskType: taskType);
            if (string.Equals(outcome.Language, language, StringComparison.Ordinal)
                && !(organicOnly && outcome.Source is not null))
            {
                results.Add(outcome);
                if (results.Count >= limit)
                {
                    break;
                }
            }
            if (examined >= _scanBudget)
            {
                break;
            }
        }

        return results;
    }

    public async Task<IReadOnlyList<RoutingOutcome>> GetRecentAllAsync(
        int limit = 200, CancellationToken cancellationToken = default)
    {
        await EnsureTableAsync(cancellationToken).ConfigureAwait(false);

        // Cross-partition telemetry read. A filterless scan comes back ordered by
        // (PartitionKey, RowKey) — newest-first only WITHIN each task-type partition —
        // so "newest overall" has to see the whole table. That is acceptable for the
        // same reason Table Storage was chosen at all (outcomes cost pennies at this
        // volume, and the local JSONL twin reads its whole file too), and this path
        // serves /v1/metrics display only, never a routing decision. Memory stays
        // bounded: a min-heap keyed on timestamp keeps just the newest <c>limit</c>.
        var newest = new PriorityQueue<RoutingOutcome, long>(limit + 1);
        var query = _table.QueryAsync<TableEntity>(
            maxPerPage: 1000, cancellationToken: cancellationToken);
        await foreach (var entity in query.ConfigureAwait(false))
        {
            var outcome = ToOutcome(entity);
            newest.Enqueue(outcome, outcome.Timestamp.UtcTicks);
            if (newest.Count > limit)
            {
                newest.Dequeue(); // the oldest retained outcome falls out
            }
        }

        var results = new List<RoutingOutcome>(newest.Count);
        while (newest.TryDequeue(out var outcome, out _))
        {
            results.Add(outcome);
        }
        results.Reverse(); // the heap drains oldest first → newest first
        return results;
    }

    private static RoutingOutcome ToOutcome(TableEntity entity, string fallbackTaskType = "") => new()
    {
        OutcomeId = entity.GetString("OutcomeId"),
        Timestamp = entity.GetDateTimeOffset("OccurredAt") ?? entity.Timestamp ?? DateTimeOffset.MinValue,
        TaskType = entity.GetString("TaskType") ?? fallbackTaskType,
        // Absent on rows written before the language dimension existed: null, the
        // same "no language" value a language-less route records today.
        Language = entity.GetString("Language"),
        Provider = entity.GetString("Provider") ?? "",
        Model = entity.GetString("Model") ?? "",
        Success = entity.GetBoolean("Success") ?? false,
        LatencyMs = entity.GetDouble("LatencyMs") ?? 0,
        CostUsd = entity.GetDouble("CostUsd") ?? 0,
        Quality = entity.GetDouble("Quality"),
        Pool = entity.GetString("Pool"),
        // Provenance must round-trip: an advisory record that comes back with
        // Source == null would be indistinguishable from a live provider
        // outcome and leak into adaptive routing.
        Source = entity.GetString("Source"),
    };

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
        // Stamp a stable identity ONCE, before the fan-out, so the local and remote
        // copies of this outcome share it and the read-side merge can dedup on it
        // instead of on lossy telemetry fields.
        if (outcome.OutcomeId is null or "")
        {
            outcome = outcome with { OutcomeId = Guid.NewGuid().ToString("N") };
        }

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

    public Task<IReadOnlyList<RoutingOutcome>> GetRecentAsync(
        string taskType, int limit = 200, CancellationToken cancellationToken = default) =>
        MergeAsync(store => store.GetRecentAsync(taskType, limit, cancellationToken), limit);

    public Task<IReadOnlyList<RoutingOutcome>> GetRecentForLanguageAsync(
        string taskType, string? language, int limit = 200, CancellationToken cancellationToken = default) =>
        MergeAsync(
            store => store.GetRecentForLanguageAsync(taskType, language, limit, cancellationToken), limit);

    public Task<IReadOnlyList<RoutingOutcome>> GetRecentOrganicForLanguageAsync(
        string taskType, string? language, int limit = 200, CancellationToken cancellationToken = default) =>
        // Each side scopes organic-ness before its own cap, so the merged window is
        // organic evidence only — never a window an advisory ingest on either side has
        // already consumed.
        MergeAsync(
            store => store.GetRecentOrganicForLanguageAsync(taskType, language, limit, cancellationToken), limit);

    public Task<IReadOnlyList<RoutingOutcome>> GetRecentAllAsync(
        int limit = 200, CancellationToken cancellationToken = default) =>
        MergeAsync(store => store.GetRecentAllAsync(limit, cancellationToken), limit);

    /// <summary>
    /// Merge, never prefer: local writes always land first and remote writes are
    /// best-effort, so after an Azure outage the local store holds outcomes the table
    /// never saw — returning a non-empty remote result alone would serve stale history
    /// until some external reconciliation ran. Every read goes through here so the rule
    /// (and the outage degradation: a failed remote read is an empty remote side, never
    /// a failed call) cannot drift between the reads.
    /// </summary>
    private async Task<IReadOnlyList<RoutingOutcome>> MergeAsync(
        Func<ILearningStore, Task<IReadOnlyList<RoutingOutcome>>> read, int limit)
    {
        IReadOnlyList<RoutingOutcome> remote = Array.Empty<RoutingOutcome>();
        try
        {
            remote = await read(_remote).ConfigureAwait(false);
        }
        catch (RequestFailedException)
        {
        }
        catch (AuthenticationFailedException)
        {
        }

        var local = await read(_local).ConfigureAwait(false);

        return remote.Concat(local)
            .DistinctBy(MergeDedupKey)
            .OrderByDescending(o => o.Timestamp)
            .Take(limit)
            .ToList();
    }

    // Dedup key for the local+remote merge. The stamped OutcomeId is the real
    // identity — telemetry fields make a lossy key (two concurrent outcomes can
    // legitimately share timestamp/provider/model/success/latency — review finding).
    // Rows recorded before the id existed fall back to the telemetry tuple; a string
    // key can never equal a boxed tuple key, so the two populations never collide.
    // TaskType is in the fallback tuple because GetRecentAllAsync spans task types.
    private static object MergeDedupKey(RoutingOutcome o) =>
        o.OutcomeId is { Length: > 0 } id
            ? id
            : (o.Timestamp, o.TaskType, o.Language, o.Provider, o.Model, o.Success, o.LatencyMs, o.Source);
}
