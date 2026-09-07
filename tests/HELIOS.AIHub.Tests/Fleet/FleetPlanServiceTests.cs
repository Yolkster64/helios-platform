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

    private static FleetTopology Topology(params string[] chain) => Topology(TaskTypeName, chain);

    private static FleetTopology Topology(string taskType, string[] chain) => new()
    {
        Pools = new[]
        {
            new FleetPool
            {
                Name = "xcore-9-test",
                TaskTypes = new[] { taskType },
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
    private static List<RoutingOutcome> ReorderingHistory(string taskType = TaskTypeName)
    {
        var history = new List<RoutingOutcome>();
        for (var i = 0; i < 6; i++)
        {
            history.Add(FakeLearningStore.Outcome(taskType, "flaky", success: false));
        }
        for (var i = 0; i < 5; i++)
        {
            history.Add(FakeLearningStore.Outcome(taskType, "reliable", success: true));
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
    public async Task PlanAsync_LanguageTaggedOutcomesFillingTheWindow_DoNotHideLanguagelessEvidence()
    {
        // The 200 newest outcomes (one whole history window) carry a language and favour
        // flaky; the pool's own language-less evidence (reliable beats flaky) lies
        // entirely behind them. Pools route by bare task type, so the planner must read
        // the language-less key AT the store (window after scoping): a shared task-type
        // window scoped afterwards would see no language-less record at all and report
        // 0 samples / engine none / the configured order although 11 organic samples
        // exist — the defect RouteAsync had in round 2, on the advisory path.
        var history = new List<RoutingOutcome>();
        for (var i = 0; i < 200; i++)
        {
            var flakyWins = i % 2 == 0;
            history.Add(FakeLearningStore.Outcome(TaskTypeName, flakyWins ? "flaky" : "reliable", success: flakyWins)
                with { Language = "python" });
        }
        history.AddRange(ReorderingHistory());
        var service = new FleetPlanService(new FakeLearningStore(history), historyWindow: 200);

        var plan = await service.PlanAsync(Topology("flaky", "reliable"));

        var entry = Assert.Single(plan);
        Assert.Equal(11, entry.SampleCount); // the language-less samples, none of the python ones
        Assert.Equal(new[] { "reliable", "flaky" }, entry.LearnedChain);
        Assert.Equal("linear", entry.Engine);
    }

    [Fact]
    public async Task PlanAsync_FleetLaneRecordsFillingTheWindow_DoNotHideOlderOrganicEvidence()
    {
        // The 200 newest outcomes of the pool's task type (one whole history window)
        // are fleet-lane records — exactly what the collector writes under a task type
        // between two organic routes — and they favour flaky; the organic evidence
        // (reliable beats flaky) lies entirely behind them. The planner reads the
        // organic key AT the store (window after scoping): a plain window scoped
        // afterwards would hold lane records only and report 0 samples / engine none /
        // the configured order although 11 organic samples exist — the advisory-axis
        // twin of the language defect above.
        var history = new List<RoutingOutcome>();
        for (var i = 0; i < 200; i++)
        {
            var flakyWins = i % 2 == 0;
            history.Add(FakeLearningStore.Outcome(
                TaskTypeName, flakyWins ? "flaky" : "reliable", success: flakyWins, source: "fleet-lane"));
        }
        history.AddRange(ReorderingHistory());
        var service = new FleetPlanService(new FakeLearningStore(history), historyWindow: 200);

        var plan = await service.PlanAsync(Topology("flaky", "reliable"));

        var entry = Assert.Single(plan);
        Assert.Equal(11, entry.SampleCount); // the organic samples, none of the lane records
        Assert.Equal(new[] { "reliable", "flaky" }, entry.LearnedChain);
        Assert.Equal("linear", entry.Engine);
    }

    [Fact]
    public async Task PlanAsync_QualifiedPoolTaskType_IsScoredOnItsOwnLanguageBucket()
    {
        // A pool listing "code_generation:fsharp" names the (code_generation, fsharp)
        // key the hub records under. Read verbatim it would score the orphan
        // ("code_generation:fsharp", no language) bucket nothing writes to — 0 samples,
        // engine none. And the 200 newest language-less outcomes (one whole window,
        // favouring flaky) must not stand in for the 11 fsharp samples behind them: the
        // scoped window is read first and it is not empty.
        var history = new List<RoutingOutcome>();
        for (var i = 0; i < 200; i++)
        {
            var flakyWins = i % 2 == 0;
            history.Add(FakeLearningStore.Outcome("code_generation", flakyWins ? "flaky" : "reliable", success: flakyWins));
        }
        history.AddRange(ReorderingHistory("code_generation").Select(o => o with { Language = "fsharp" }));
        var service = new FleetPlanService(new FakeLearningStore(history), historyWindow: 200);

        var plan = await service.PlanAsync(Topology("code_generation:fsharp", new[] { "flaky", "reliable" }));

        var entry = Assert.Single(plan);
        Assert.Equal("code_generation:fsharp", entry.TaskType); // the pool's string, verbatim
        Assert.Equal(11, entry.SampleCount); // the fsharp samples, none of the language-less ones
        Assert.Equal(new[] { "reliable", "flaky" }, entry.LearnedChain);
        Assert.Equal("linear", entry.Engine);
    }

    [Fact]
    public async Task PlanAsync_QualifiedPoolTaskType_WithoutLanguageEvidence_FallsBackToLanguagelessEvidence()
    {
        // No fsharp outcome exists yet, so the pool is scored on the parent task type's
        // language-less evidence — the hub's own fallback for a language-qualified route
        // (AIHubService.ApplyLearningAsync) — rather than reporting "no evidence".
        var service = new FleetPlanService(
            new FakeLearningStore(ReorderingHistory("code_generation")), historyWindow: 200);

        var plan = await service.PlanAsync(Topology("code_generation:fsharp", new[] { "flaky", "reliable" }));

        var entry = Assert.Single(plan);
        Assert.Equal("code_generation:fsharp", entry.TaskType);
        Assert.Equal(11, entry.SampleCount);
        Assert.Equal(new[] { "reliable", "flaky" }, entry.LearnedChain);
        Assert.Equal("linear", entry.Engine);
    }

    [Fact]
    public async Task PlanAsync_QualifiedLookingPoolTaskType_WithANonCanonicalLanguage_IsReadVerbatim()
    {
        // "code_generation:F#" is not a key the hub would ever split (its language part
        // is not canonical), so the hub records such requests verbatim and the planner
        // must read that literal key — splitting it would look for evidence under a
        // language no record carries.
        var service = new FleetPlanService(
            new FakeLearningStore(ReorderingHistory("code_generation:F#")), historyWindow: 200);

        var plan = await service.PlanAsync(Topology("code_generation:F#", new[] { "flaky", "reliable" }));

        var entry = Assert.Single(plan);
        Assert.Equal(11, entry.SampleCount);
        Assert.Equal(new[] { "reliable", "flaky" }, entry.LearnedChain);
    }

    [Fact]
    public async Task PlanAsync_SharedQualifiedTaskTypes_ReadsScopedAndFallbackWindowsOnce()
    {
        // Two pools sharing an empty qualified key cost two reads in total (the scoped
        // window, then the language-less fallback), not two per pool: the cache keys on
        // the pool's string, so the second pool reuses the first's evidence.
        var store = new CountingLearningStore();
        var service = new FleetPlanService(store, historyWindow: 200);
        var topology = new FleetTopology
        {
            Pools = new[]
            {
                new FleetPool { Name = "p1", TaskTypes = new[] { "code_generation:fsharp" }, ProviderChain = new[] { "a", "b" } },
                new FleetPool { Name = "p2", TaskTypes = new[] { "code_generation:fsharp" }, ProviderChain = new[] { "b", "a" } },
            },
        };

        var plan = await service.PlanAsync(topology);

        Assert.Equal(2, plan.Count);
        Assert.Equal(2, store.Reads);
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

        public Task<IReadOnlyList<RoutingOutcome>> GetRecentForLanguageAsync(
            string taskType, string? language, int limit = 200, CancellationToken cancellationToken = default)
        {
            Reads++;
            return Task.FromResult<IReadOnlyList<RoutingOutcome>>(Array.Empty<RoutingOutcome>());
        }

        public Task<IReadOnlyList<RoutingOutcome>> GetRecentOrganicForLanguageAsync(
            string taskType, string? language, int limit = 200, CancellationToken cancellationToken = default)
        {
            Reads++;
            return Task.FromResult<IReadOnlyList<RoutingOutcome>>(Array.Empty<RoutingOutcome>());
        }

        public Task<IReadOnlyList<RoutingOutcome>> GetRecentAllAsync(
            int limit = 200, CancellationToken cancellationToken = default)
        {
            Reads++;
            return Task.FromResult<IReadOnlyList<RoutingOutcome>>(Array.Empty<RoutingOutcome>());
        }
    }
}
