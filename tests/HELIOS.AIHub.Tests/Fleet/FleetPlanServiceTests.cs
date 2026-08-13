using HELIOS.AIHub.Fleet;
using HELIOS.AIHub.Learning;
using HELIOS.AIHub.Native;
using Xunit;

namespace HELIOS.AIHub.Tests.Fleet;

/// <summary>
/// The fleet-plan advisory path: learned chains computed over each pool's configured
/// providerChain from ORGANIC hub history only. Everything here is keyless and
/// deterministic — histories are hand-rolled, and sample counts are chosen so each test
/// pins one engine ("linear" cases stay under the neural learner's 12-sample minimum;
/// the "neural" case sits at it and asserts per native-library presence).
/// </summary>
public class FleetPlanServiceTests
{
    private const string TaskTypeName = "code_review";

    private static FleetTopology Topology(params string[] chain) => new()
    {
        Pools = new[]
        {
            new FleetPool
            {
                Name = "xcore-9-test",
                TaskTypes = new[] { TaskTypeName },
                ProviderChain = chain,
                HermesFleet = new HermesFleetOptions { Board = "xcore-test", MaxConcurrentLanes = 2 },
            },
        },
    };

    /// <summary>
    /// 6 flaky failures + 5 reliable successes: both providers clear the linear policy's
    /// confidence threshold (5 attempts), but the 11-record total stays under the neural
    /// learner's 12-sample minimum — so the result is the deterministic F# linear
    /// reorder whether or not the native library is present.
    /// </summary>
    private static List<RoutingOutcome> ReorderingHistory()
    {
        var history = new List<RoutingOutcome>();
        for (var i = 0; i < 6; i++)
        {
            history.Add(FakeLearningStore.Outcome(TaskTypeName, "flaky", success: false));
        }
        for (var i = 0; i < 5; i++)
        {
            history.Add(FakeLearningStore.Outcome(TaskTypeName, "reliable", success: true));
        }
        return history;
    }

    [Fact]
    public async Task PlanAsync_OrganicHistory_ReordersConfiguredChain_ViaLinearEngine()
    {
        var service = new FleetPlanService(new FakeLearningStore(ReorderingHistory()), historyWindow: 200);

        var plan = await service.PlanAsync(Topology("flaky", "reliable"));

        var entry = Assert.Single(plan);
        Assert.Equal("xcore-9-test", entry.Pool);
        Assert.Equal(TaskTypeName, entry.TaskType);
        Assert.Equal(new[] { "flaky", "reliable" }, entry.ConfiguredChain);
        Assert.Equal(new[] { "reliable", "flaky" }, entry.LearnedChain);
        Assert.Equal(11, entry.SampleCount);
        Assert.Equal("linear", entry.Engine);
    }

    [Fact]
    public async Task PlanAsync_FleetLaneRecords_NeverInfluenceProviderChains()
    {
        var history = ReorderingHistory(); // organic evidence: reliable beats flaky
        // Poison: lane outcomes tagged source=fleet-lane. Some carry lane names
        // ("pool:xcore-9-code"), some collide with real provider names carrying the
        // OPPOSITE signal — if a regression ever let source-tagged records into the
        // reorder inputs, flaky would jump to (1+20)/26 success vs reliable's 5/25 and
        // the learned order would flip.
        for (var i = 0; i < 20; i++)
        {
            history.Add(FakeLearningStore.Outcome(TaskTypeName, "flaky", success: true, source: "fleet-lane"));
            history.Add(FakeLearningStore.Outcome(TaskTypeName, "reliable", success: false, source: "fleet-lane"));
            history.Add(FakeLearningStore.Outcome(TaskTypeName, "pool:xcore-9-code", success: true, source: "fleet-lane"));
        }
        var service = new FleetPlanService(new FakeLearningStore(history), historyWindow: 200);

        var plan = await service.PlanAsync(Topology("flaky", "reliable"));

        var entry = Assert.Single(plan);
        Assert.Equal(new[] { "reliable", "flaky" }, entry.LearnedChain);
        Assert.Equal(11, entry.SampleCount); // lane records are not samples
        Assert.Equal("linear", entry.Engine);
    }

    [Fact]
    public async Task PlanAsync_OnlySourceTaggedHistory_IsEngineNone_WithConfiguredOrder()
    {
        var history = new List<RoutingOutcome>();
        for (var i = 0; i < 30; i++)
        {
            history.Add(FakeLearningStore.Outcome(TaskTypeName, "b", success: true, source: "fleet-lane"));
            history.Add(FakeLearningStore.Outcome(TaskTypeName, "a", success: false, source: "absorption-benchmark"));
        }
        var service = new FleetPlanService(new FakeLearningStore(history), historyWindow: 200);

        var plan = await service.PlanAsync(Topology("a", "b"));

        var entry = Assert.Single(plan);
        Assert.Equal(new[] { "a", "b" }, entry.LearnedChain);
        Assert.Equal(0, entry.SampleCount);
        Assert.Equal("none", entry.Engine);
    }

    [Fact]
    public async Task PlanAsync_EmptyHistory_ReportsEngineNone_AndKeepsConfiguredOrder()
    {
        var service = new FleetPlanService(new FakeLearningStore(), historyWindow: 200);

        var plan = await service.PlanAsync(Topology("a", "b", "c"));

        var entry = Assert.Single(plan);
        Assert.Equal(new[] { "a", "b", "c" }, entry.ConfiguredChain);
        Assert.Equal(new[] { "a", "b", "c" }, entry.LearnedChain);
        Assert.Equal(0, entry.SampleCount);
        Assert.Equal("none", entry.Engine);
    }

    [Fact]
    public async Task PlanAsync_ThinEvidence_KeepsConfiguredOrder_ViaLinearEngine()
    {
        // Two records — under the linear confidence threshold. The engine label reports
        // which scorer evaluated the chain, not whether the order moved.
        var history = new List<RoutingOutcome>
        {
            FakeLearningStore.Outcome(TaskTypeName, "a", success: false),
            FakeLearningStore.Outcome(TaskTypeName, "b", success: true),
        };
        var service = new FleetPlanService(new FakeLearningStore(history), historyWindow: 200);

        var plan = await service.PlanAsync(Topology("a", "b"));

        var entry = Assert.Single(plan);
        Assert.Equal(new[] { "a", "b" }, entry.LearnedChain);
        Assert.Equal(2, entry.SampleCount);
        Assert.Equal("linear", entry.Engine);
    }

    [Fact]
    public async Task PlanAsync_RichHistory_UsesNeuralEngine_WhenNativeLibraryPresent()
    {
        // 7 flaky failures + 7 reliable successes = 14 records; prequential training
        // (each provider's first outcome yields no sample) gives exactly the neural
        // learner's 12-sample minimum, so the native MLP trains whenever the library is
        // loadable. Either way the ORDER is pinned: the F# fusion caps the MLP's say at
        // mlpWeight(7) ≈ 0.21, and reliable's linear score (1.0 vs flaky's 0.2) can't be
        // overturned by any prediction in [0,1] — so this asserts both halves of the
        // composition without depending on learned weights.
        var history = new List<RoutingOutcome>();
        for (var i = 0; i < 7; i++)
        {
            history.Add(FakeLearningStore.Outcome(TaskTypeName, "flaky", success: false));
            history.Add(FakeLearningStore.Outcome(TaskTypeName, "reliable", success: true));
        }
        var service = new FleetPlanService(new FakeLearningStore(history), historyWindow: 200);

        var plan = await service.PlanAsync(Topology("flaky", "reliable"));

        var entry = Assert.Single(plan);
        Assert.Equal(new[] { "reliable", "flaky" }, entry.LearnedChain);
        Assert.Equal(14, entry.SampleCount);
        // With the C++ spoke present the neural path speaks; without it the learner
        // abstains and the linear policy answers — degradation, never a failure.
        Assert.Equal(NativeLibraryPresent() ? "neural" : "linear", entry.Engine);
    }

    [Fact]
    public async Task PlanAsync_SharedTaskTypes_ReadsStoreOncePerTaskType()
    {
        var store = new CountingLearningStore();
        var service = new FleetPlanService(store, historyWindow: 200);
        var topology = new FleetTopology
        {
            Pools = new[]
            {
                new FleetPool { Name = "p1", TaskTypes = new[] { TaskTypeName }, ProviderChain = new[] { "a", "b" } },
                new FleetPool { Name = "p2", TaskTypes = new[] { TaskTypeName }, ProviderChain = new[] { "b", "a" } },
            },
        };

        var plan = await service.PlanAsync(topology);

        Assert.Equal(2, plan.Count);
        Assert.Equal(1, store.Reads);
    }

    /// <summary>Same gate the production code uses (NativeGate): ABI handshake succeeds.</summary>
    private static bool NativeLibraryPresent()
    {
        try
        {
            return NativeMethods.AbiVersion() == NativeMethods.ExpectedAbiVersion;
        }
        catch (DllNotFoundException)
        {
            return false;
        }
        catch (EntryPointNotFoundException)
        {
            return false;
        }
    }

    private sealed class CountingLearningStore : ILearningStore
    {
        public int Reads { get; private set; }

        public Task RecordAsync(RoutingOutcome outcome, CancellationToken cancellationToken = default) =>
            Task.CompletedTask;

        public Task<IReadOnlyList<RoutingOutcome>> GetRecentAsync(
            string taskType, int limit = 200, CancellationToken cancellationToken = default)
        {
            Reads++;
            return Task.FromResult<IReadOnlyList<RoutingOutcome>>(Array.Empty<RoutingOutcome>());
        }
    }
}
