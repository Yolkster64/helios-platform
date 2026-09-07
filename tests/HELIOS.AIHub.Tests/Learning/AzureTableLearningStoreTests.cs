using System.Diagnostics.CodeAnalysis;
using Azure;
using Azure.Core;
using Azure.Data.Tables;
using Azure.Data.Tables.Models;
using HELIOS.AIHub.Learning;
using Xunit;

namespace HELIOS.AIHub.Tests.Learning;

/// <summary>
/// The Azure Table backend's scoped reads, through a TableClient double: which OData
/// filter reaches the service (a qualified language is pushed server-side, apostrophes
/// escaped), what the client-side pass keeps (an absent Language or Source column
/// cannot be filtered server-side), and that the cap ends the stream instead of
/// draining the partition. No network: the double serves canned rows.
/// </summary>
public sealed class AzureTableLearningStoreTests
{
    private const string TaskTypeName = "code_generation";

    private static readonly string BaseFilter =
        $"PartitionKey eq '{TaskTypeName}' and TaskType eq '{TaskTypeName}'";

    [Fact]
    public async Task GetRecentForLanguageAsync_QualifiedLanguage_IsPushedIntoTheFilter_WithApostrophesEscaped()
    {
        // The language rides into the filter as an OData string literal, so an
        // apostrophe in the value would end the literal early unless it is doubled.
        var table = new FakeTableClient(Row("p1", language: "f#'s"));
        var store = new AzureTableLearningStore(table);

        var scoped = await store.GetRecentForLanguageAsync(TaskTypeName, "f#'s");

        Assert.Equal(BaseFilter + " and Language eq 'f#''s'", table.LastFilter);
        Assert.Equal("p1", Assert.Single(scoped).Provider);
    }

    [Fact]
    public async Task GetRecentForLanguageAsync_TaskType_IsSanitizedForThePartition_AndEscapedInBothClauses()
    {
        // Table keys forbid / \ # ? (Sanitize maps them to '_'), so the partition clause
        // carries the sanitized key while the TaskType clause carries the stored task
        // type verbatim — both with the apostrophe doubled, or the OData literal ends
        // early on a task type like "customer's-review".
        const string taskType = "review/customer's#1";
        var entity = new TableEntity("review_customer's_1", "0000000000000000000")
        {
            ["TaskType"] = taskType,
            ["Provider"] = "p1",
            ["Model"] = "fake-model",
            ["Success"] = true,
            ["LatencyMs"] = 100d,
            ["CostUsd"] = 0d,
            ["OccurredAt"] = DateTimeOffset.UnixEpoch,
        };
        var table = new FakeTableClient(entity);
        var store = new AzureTableLearningStore(table);

        var read = await store.GetRecentForLanguageAsync(taskType, language: null);

        Assert.Equal("PartitionKey eq 'review_customer''s_1' and TaskType eq 'review/customer''s#1'", table.LastFilter);
        Assert.Equal("p1", Assert.Single(read).Provider);
    }

    [Fact]
    public async Task GetRecentForLanguageAsync_LanguagelessKey_HasNoLanguageClause_AndKeepsOnlyRowsWithoutOne()
    {
        // An absent Language column is not "eq" anything server-side, so the
        // language-less read streams the partition and drops qualified rows itself.
        var table = new FakeTableClient(
            Row("python", language: "python", at: 3),
            Row("legacy", language: null, at: 2),
            Row("fsharp", language: "fsharp", at: 1));
        var store = new AzureTableLearningStore(table);

        var languageless = await store.GetRecentForLanguageAsync(TaskTypeName, language: null);

        Assert.Equal(BaseFilter, table.LastFilter);
        Assert.Equal("legacy", Assert.Single(languageless).Provider);
    }

    [Fact]
    public async Task GetRecentOrganicForLanguageAsync_KeepsOnlyRowsWithoutASource_ClientSide()
    {
        // An organic row has no Source column at all, so organic-ness cannot be pushed
        // into the filter either: same filter as the plain read, advisory rows dropped
        // while streaming — and still only the requested language.
        var table = new FakeTableClient(
            Row("lane", language: null, source: "fleet-lane", at: 4),
            Row("benchmark", language: null, source: "absorption-benchmark", at: 3),
            Row("organic", language: null, at: 2),
            Row("organic-fsharp", language: "fsharp", at: 1));
        var store = new AzureTableLearningStore(table);

        var organic = await store.GetRecentOrganicForLanguageAsync(TaskTypeName, language: null);

        Assert.Equal(BaseFilter, table.LastFilter);
        Assert.Equal("organic", Assert.Single(organic).Provider);
    }

    [Fact]
    public async Task GetRecentOrganicForLanguageAsync_QualifiedLanguage_PushesTheLanguage_AndDropsAdvisoryRows()
    {
        var table = new FakeTableClient(
            Row("lane-fsharp", language: "fsharp", source: "fleet-lane", at: 2),
            Row("organic-fsharp", language: "fsharp", at: 1));
        var store = new AzureTableLearningStore(table);

        var organic = await store.GetRecentOrganicForLanguageAsync(TaskTypeName, "fsharp");

        Assert.Equal(BaseFilter + " and Language eq 'fsharp'", table.LastFilter);
        Assert.Equal("organic-fsharp", Assert.Single(organic).Provider);
    }

    [Fact]
    public async Task GetRecentOrganicForLanguageAsync_Limit_CountsOrganicRowsOnly_AndStopsTheStream()
    {
        // Advisory rows interleaved with organic ones, window of 2: the cap counts the
        // rows kept, not the rows seen, and once it is reached the read stops pulling
        // pages — the double serves one page per row, so pages never requested are
        // rows never served.
        var table = new FakeTableClient(
            Row("lane-1", language: null, source: "fleet-lane", at: 6),
            Row("p1", language: null, at: 5),
            Row("lane-2", language: null, source: "fleet-lane", at: 4),
            Row("p2", language: null, at: 3),
            Row("lane-3", language: null, source: "fleet-lane", at: 2),
            Row("p3", language: null, at: 1));
        var store = new AzureTableLearningStore(table);

        var window = await store.GetRecentOrganicForLanguageAsync(TaskTypeName, language: null, limit: 2);

        Assert.Equal(new[] { "p1", "p2" }, window.Select(o => o.Provider));
        Assert.Equal(2, table.LastMaxPerPage);
        Assert.True(table.RowsServed < 6, $"the stream served {table.RowsServed} of 6 rows after the cap");
    }

    /// <summary>A row as RecordAsync stores it: a null property is simply absent from the entity.</summary>
    private static TableEntity Row(string provider, string? language, string? source = null, int at = 0)
    {
        var entity = new TableEntity(TaskTypeName, $"{at:D19}")
        {
            ["TaskType"] = TaskTypeName,
            ["Provider"] = provider,
            ["Model"] = "fake-model",
            ["Success"] = true,
            ["LatencyMs"] = 100d,
            ["CostUsd"] = 0d,
            ["OccurredAt"] = DateTimeOffset.UnixEpoch.AddSeconds(at),
        };
        if (language is not null)
        {
            entity["Language"] = language;
        }
        if (source is not null)
        {
            entity["Source"] = source;
        }
        return entity;
    }

    /// <summary>
    /// TableClient double (hand-rolled per the repo's no-Moq idiom): records the query
    /// the store issues and serves the canned rows one page per row, so a read that
    /// stops at its cap shows up as pages never pulled. Only the members the store calls
    /// are overridden; anything else would reach the base implementation with no
    /// pipeline behind it.
    /// </summary>
    private sealed class FakeTableClient : TableClient
    {
        private readonly IReadOnlyList<TableEntity> _rows;

        public FakeTableClient(params TableEntity[] rows)
        {
            _rows = rows;
        }

        public string? LastFilter { get; private set; }

        public int? LastMaxPerPage { get; private set; }

        public int RowsServed { get; private set; }

        public override Task<Response<TableItem>> CreateIfNotExistsAsync(CancellationToken cancellationToken = default) =>
            Task.FromResult(Response.FromValue(new TableItem("aihubOutcomes"), new StubResponse()));

        public override AsyncPageable<T> QueryAsync<T>(
            string? filter, int? maxPerPage, IEnumerable<string>? select, CancellationToken cancellationToken)
        {
            LastFilter = filter;
            LastMaxPerPage = maxPerPage;
            return AsyncPageable<T>.FromPages(PagesOf<T>());
        }

        private IEnumerable<Page<T>> PagesOf<T>()
        {
            foreach (var row in _rows)
            {
                RowsServed++;
                yield return Page<T>.FromValues(new[] { (T)(object)row }, continuationToken: null, new StubResponse());
            }
        }
    }

    /// <summary>The raw HTTP response Azure.Core requires a page and a value to carry; nothing here reads it.</summary>
    private sealed class StubResponse : Response
    {
        public override int Status => 200;

        public override string ReasonPhrase => "OK";

        public override Stream? ContentStream { get; set; }

        public override string ClientRequestId { get; set; } = "";

        public override void Dispose()
        {
        }

        protected override bool ContainsHeader(string name) => false;

        protected override IEnumerable<HttpHeader> EnumerateHeaders() => Array.Empty<HttpHeader>();

        protected override bool TryGetHeader(string name, [NotNullWhen(true)] out string? value)
        {
            value = null;
            return false;
        }

        protected override bool TryGetHeaderValues(string name, [NotNullWhen(true)] out IEnumerable<string>? values)
        {
            values = null;
            return false;
        }
    }
}
