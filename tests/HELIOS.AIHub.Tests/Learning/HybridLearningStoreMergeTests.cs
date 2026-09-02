using HELIOS.AIHub.Learning;
using Xunit;

namespace HELIOS.AIHub.Tests.Learning;

/// <summary>
/// The hybrid local+remote merge dedups on the stamped <see cref="RoutingOutcome.OutcomeId"/>,
/// falling back to the telemetry tuple only for legacy rows recorded before the id
/// existed — telemetry fields make a lossy key: two concurrent outcomes can
/// legitimately share timestamp/provider/model/success/latency (review finding).
/// </summary>
public sealed class HybridLearningStoreMergeTests
{
    private static RoutingOutcome Outcome(string? outcomeId, double costUsd = 0) => new()
    {
        OutcomeId = outcomeId,
        Timestamp = DateTimeOffset.UnixEpoch,
        TaskType = "code_generation",
        Provider = "openai",
        Model = "fake-model",
        Success = true,
        LatencyMs = 100,
        CostUsd = costUsd,
        Source = "absorption-benchmark",
    };

    [Fact]
    public async Task GetRecentAllAsync_SameTelemetryTuple_DistinctIds_BothSurvive()
    {
        // Two legitimate concurrent outcomes share every telemetry field but differ
        // in cost — and both copies live in both stores, the hybrid steady state.
        var a = Outcome("id-a", costUsd: 0.001);
        var b = Outcome("id-b", costUsd: 0.002);
        var store = new HybridLearningStore(
            local: new FakeLearningStore(new[] { a, b }),
            remote: new FakeLearningStore(new[] { a, b }));

        var merged = await store.GetRecentAllAsync();

        Assert.Equal(2, merged.Count);
        Assert.Equal(new[] { "id-a", "id-b" }, merged.Select(o => o.OutcomeId).OrderBy(x => x));
    }

    [Fact]
    public async Task GetRecentAllAsync_LegacyNullIds_SameTuple_StillDedupAcrossStores()
    {
        // Pre-id rows keep the old behavior: the same record present in both stores
        // collapses to one via the telemetry tuple.
        var legacy = Outcome(outcomeId: null);
        var store = new HybridLearningStore(
            local: new FakeLearningStore(new[] { legacy }),
            remote: new FakeLearningStore(new[] { legacy }));

        var merged = await store.GetRecentAllAsync();

        Assert.Single(merged);
    }

    [Fact]
    public async Task GetRecentAsync_SameTuple_DistinctIds_BothSurvive()
    {
        var a = Outcome("id-a", costUsd: 0.001);
        var b = Outcome("id-b", costUsd: 0.002);
        var store = new HybridLearningStore(
            local: new FakeLearningStore(new[] { a, b }),
            remote: new FakeLearningStore(new[] { a, b }));

        var merged = await store.GetRecentAsync("code_generation");

        Assert.Equal(2, merged.Count);
    }

    [Fact]
    public async Task RecordAsync_StampsOneSharedOutcomeId_BeforeTheFanOut()
    {
        var local = new FakeLearningStore();
        var remote = new FakeLearningStore();
        var store = new HybridLearningStore(local, remote);

        await store.RecordAsync(Outcome(outcomeId: null));

        var localId = Assert.Single(local.Recorded).OutcomeId;
        var remoteId = Assert.Single(remote.Recorded).OutcomeId;
        Assert.False(string.IsNullOrEmpty(localId));
        Assert.Equal(localId, remoteId); // one identity, both copies
    }
}
