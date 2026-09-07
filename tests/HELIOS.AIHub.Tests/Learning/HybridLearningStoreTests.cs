using Azure;
using HELIOS.AIHub.Learning;
using Xunit;

namespace HELIOS.AIHub.Tests.Learning;

/// <summary>
/// The language dimension across the hybrid local+remote merge: two records that differ
/// only by language are two outcomes (the fallback dedup tuple carries Language), and
/// the (taskType, language) read scopes BOTH sides before the window, on the same
/// merge-never-prefer rule as the task-type read.
/// </summary>
public sealed class HybridLearningStoreTests
{
    private const string TaskTypeName = "code_generation";

    private static RoutingOutcome Outcome(string provider, string? language, string? outcomeId = null, int at = 0) =>
        new()
        {
            OutcomeId = outcomeId,
            Timestamp = DateTimeOffset.UnixEpoch.AddSeconds(at),
            TaskType = TaskTypeName,
            Language = language,
            Provider = provider,
            Model = "fake-model",
            Success = true,
            LatencyMs = 100,
            CostUsd = 0,
        };

    [Fact]
    public async Task GetRecentAsync_RecordsDifferingOnlyByLanguage_AcrossStores_BothSurvive()
    {
        // Legacy rows (no OutcomeId) dedup on the telemetry tuple. A language-less
        // record on one side and its fsharp twin on the other share every other field;
        // the tuple must tell them apart or the merge silently drops one language's
        // evidence.
        var store = new HybridLearningStore(
            local: new FakeLearningStore(new[] { Outcome("openai", language: "fsharp") }),
            remote: new FakeLearningStore(new[] { Outcome("openai", language: null) }));

        var merged = await store.GetRecentAsync(TaskTypeName);

        Assert.Equal(2, merged.Count);
        Assert.Equal(new string?[] { null, "fsharp" }, merged.Select(o => o.Language).OrderBy(l => l));
    }

    [Fact]
    public async Task GetRecentAsync_SameLanguageAndTuple_OnBothSides_StillDedups()
    {
        // Control for the test above: identical language on both sides is the same
        // legacy record replicated, and collapses to one.
        var twin = Outcome("openai", language: "fsharp");
        var store = new HybridLearningStore(
            local: new FakeLearningStore(new[] { twin }),
            remote: new FakeLearningStore(new[] { twin }));

        Assert.Single(await store.GetRecentAsync(TaskTypeName));
    }

    [Fact]
    public async Task GetRecentForLanguageAsync_ScopesBothSides_ToTheRequestedKey()
    {
        var local = new FakeLearningStore(new[]
        {
            Outcome("local-fsharp", "fsharp", outcomeId: "l1", at: 4),
            Outcome("local-python", "python", outcomeId: "l2", at: 3),
        });
        var remote = new FakeLearningStore(new[]
        {
            Outcome("remote-fsharp", "fsharp", outcomeId: "r1", at: 2),
            Outcome("remote-legacy", language: null, outcomeId: "r2", at: 1),
        });
        var store = new HybridLearningStore(local, remote);

        // The fsharp key: one record from each side, newest first, nothing from python
        // or the language-less rows.
        var fsharp = await store.GetRecentForLanguageAsync(TaskTypeName, "fsharp");
        Assert.Equal(new[] { "local-fsharp", "remote-fsharp" }, fsharp.Select(o => o.Provider));

        // The language-less key: only the legacy row, wherever it lives.
        var languageless = await store.GetRecentForLanguageAsync(TaskTypeName, language: null);
        Assert.Equal("remote-legacy", Assert.Single(languageless).Provider);

        // A language neither side holds is no evidence — never another language's.
        Assert.Empty(await store.GetRecentForLanguageAsync(TaskTypeName, "cpp"));
    }

    [Fact]
    public async Task GetRecentForLanguageAsync_WindowsAfterTheMerge()
    {
        // Three fsharp records across the two sides, window of 2: the two newest win
        // regardless of which store holds them.
        var local = new FakeLearningStore(new[] { Outcome("l-newest", "fsharp", outcomeId: "l1", at: 3) });
        var remote = new FakeLearningStore(new[]
        {
            Outcome("r-middle", "fsharp", outcomeId: "r1", at: 2),
            Outcome("r-oldest", "fsharp", outcomeId: "r2", at: 1),
        });
        var store = new HybridLearningStore(local, remote);

        var window = await store.GetRecentForLanguageAsync(TaskTypeName, "fsharp", limit: 2);

        Assert.Equal(new[] { "l-newest", "r-middle" }, window.Select(o => o.Provider));
    }

    [Fact]
    public async Task GetRecentForLanguageAsync_RemoteOutage_ServesTheLocalScopedRead()
    {
        // Same degradation as the task-type read: an Azure failure on the remote side
        // never hides the local evidence and never surfaces as a routing failure.
        var local = new FakeLearningStore(new[] { Outcome("local-fsharp", "fsharp", outcomeId: "l1") });
        var store = new HybridLearningStore(local, new OutageLearningStore());

        var scoped = await store.GetRecentForLanguageAsync(TaskTypeName, "fsharp");

        Assert.Equal("local-fsharp", Assert.Single(scoped).Provider);
    }

    /// <summary>A remote store whose every read fails the way Azure Table does during an outage.</summary>
    private sealed class OutageLearningStore : ILearningStore
    {
        public Task RecordAsync(RoutingOutcome outcome, CancellationToken cancellationToken = default) =>
            throw new RequestFailedException("simulated table outage");

        public Task<IReadOnlyList<RoutingOutcome>> GetRecentAsync(
            string taskType, int limit = 200, CancellationToken cancellationToken = default) =>
            throw new RequestFailedException("simulated table outage");

        public Task<IReadOnlyList<RoutingOutcome>> GetRecentForLanguageAsync(
            string taskType, string? language, int limit = 200, CancellationToken cancellationToken = default) =>
            throw new RequestFailedException("simulated table outage");

        public Task<IReadOnlyList<RoutingOutcome>> GetRecentAllAsync(
            int limit = 200, CancellationToken cancellationToken = default) =>
            throw new RequestFailedException("simulated table outage");
    }
}
