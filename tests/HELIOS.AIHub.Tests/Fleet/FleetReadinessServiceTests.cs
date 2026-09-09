using System.Text.Json;
using System.Text.Json.Serialization;
using HELIOS.AIHub.Fleet;
using Xunit;

namespace HELIOS.AIHub.Tests.Fleet;

public class FleetReadinessServiceTests
{
    private static FleetPool Pool(string name = "test") => new()
    {
        Name = name,
        TaskTypes = new[] { "code_review" },
        ProviderChain = new[] { "claude-cli" },
    };

    private static FleetTopology Topology(params FleetPool[] pools) => new() { Version = 2, Pools = pools };

    [Fact]
    public void ShippedTopology_ReportsDeclaredCeilingsWithoutClaimingWorkersOrCloudTransport()
    {
        var loaded = FleetTopology.TryLoad(FleetTopology.FindTopologyFile(AppContext.BaseDirectory));
        Assert.NotNull(loaded.Topology);

        var report = FleetReadinessService.Plan(loaded.Topology!);

        Assert.True(report.ConfigurationValid);
        Assert.Equal(22, report.ConfiguredConcurrencyCeiling);
        Assert.Equal(new int?[] { 6, 4, 9, 3 }, report.Pools.Select(p => p.ConfiguredConcurrencyCeiling));
        Assert.Equal(new int?[] { 4, 3, 4, 3 }, report.Pools.Select(p => p.Placements[0].ConfiguredCeiling));
        Assert.False(report.RuntimeVerified);
        Assert.Null(report.VerifiedConcurrentWorkers);
        Assert.All(report.Pools.SelectMany(p => p.Placements), placement =>
        {
            Assert.False(placement.RuntimeVerified);
            Assert.Null(placement.VerifiedWorkers);
        });
        Assert.Equal(3, report.Findings.Count(f => f.Code == "burst-target-mismatch"));
        Assert.Equal(3, report.Findings.Count(f => f.Code == "aggregate-capacity"));
        Assert.Equal("not-implemented", report.Pools[0].Placements[1].TransportState);
        Assert.Equal("disabled-by-policy", report.Pools[3].Placements[1].TransportState);
        Assert.Contains(report.Findings, f => f.Code == "native-toolchain" && f.Pool == "xcore-9-native");
    }

    [Fact]
    public void Autoscaling_InheritsDefaultsMemberByMember_WhileHermesLaneSettingsUseObjectFallback()
    {
        var topology = Topology(Pool() with
        {
            Autoscaling = new FleetAutoscalingOptions { MaxLocalLanes = 2 },
        }) with
        {
            Defaults = new FleetDefaults
            {
                PoolSize = 9,
                HermesFleet = new HermesFleetOptions { Board = "default-board", MaxConcurrentLanes = 4 },
                Autoscaling = new FleetAutoscalingOptions
                {
                    Mode = "hybrid", MinLocalLanes = 1, MaxLocalLanes = 3, MaxBurstLanes = 2, BurstTarget = "vmss",
                },
            },
        };
        var report = FleetReadinessService.Plan(topology);
        var pool = Assert.Single(report.Pools);
        Assert.True(report.ConfigurationValid);
        Assert.Equal("hybrid", pool.Mode);
        Assert.Equal("test", pool.Board);
        Assert.Equal(4, pool.ConfiguredConcurrencyCeiling);
        Assert.Equal(new int?[] { 2, 2 }, pool.Placements.Select(p => p.ConfiguredCeiling));
        Assert.DoesNotContain(report.Findings, f => f.Code == "burst-target-mismatch");

        // Existing scripts do not inherit individual Hermes fields from a defaults
        // object once the pool has its own object. The read-only report must agree.
        topology = topology with { Pools = new[] { topology.Pools[0] with { HermesFleet = new HermesFleetOptions { Board = "pool-board" } } } };
        pool = Assert.Single(FleetReadinessService.Plan(topology).Pools);
        Assert.Equal("pool-board", pool.Board);
        Assert.Equal(9, pool.ConfiguredConcurrencyCeiling);
    }

    [Fact]
    public void DefaultHermesBoard_DoesNotAliasPools_WhileDefaultLaneLimitIsInherited()
    {
        var topology = Topology(Pool("alpha"), Pool("beta")) with
        {
            Defaults = new FleetDefaults
            {
                PoolSize = 9,
                HermesFleet = new HermesFleetOptions { Board = "unused-default-board", MaxConcurrentLanes = 4 },
            },
        };

        var report = FleetReadinessService.Plan(topology);

        Assert.True(report.ConfigurationValid);
        Assert.Equal(new[] { "alpha", "beta" }, report.Pools.Select(p => p.Board));
        Assert.Equal(new int?[] { 4, 4 }, report.Pools.Select(p => p.ConfiguredConcurrencyCeiling));
        Assert.Equal(8, report.ConfiguredConcurrencyCeiling);
        Assert.DoesNotContain(report.Findings, f => f.Code == "board-collision");
    }

    [Theory]
    [InlineData(-1, 1, 1, 0)]
    [InlineData(65, 1, 1, 0)]
    [InlineData(1, -1, 1, 0)]
    [InlineData(1, 1, 65, 0)]
    [InlineData(1, 1, 1, 257)]
    [InlineData(1, 3, 2, 0)]
    public void InvalidCapacity_DoesNotProduceANumericCapacityEstimate(int size, int minLocal, int maxLocal, int burst)
    {
        var report = FleetReadinessService.Plan(Topology(Pool() with
        {
            PoolSize = size,
            Autoscaling = new FleetAutoscalingOptions
            {
                Mode = "hybrid", MinLocalLanes = minLocal, MaxLocalLanes = maxLocal, MaxBurstLanes = burst,
            },
        }));

        Assert.False(report.ConfigurationValid);
        Assert.Null(report.ConfiguredConcurrencyCeiling);
        Assert.Null(Assert.Single(report.Pools).ConfiguredConcurrencyCeiling);
        Assert.Contains(report.Findings, f => f.Severity == "error");
    }

    [Fact]
    public void UnknownModeOrVersion_AndAmbiguousPoolsAreRejected()
    {
        var first = Pool() with
        {
            Autoscaling = new FleetAutoscalingOptions { Mode = "magic" },
            HermesFleet = new HermesFleetOptions { Board = "shared-board" },
        };
        var report = FleetReadinessService.Plan(Topology(first, first) with { Version = 3 });
        Assert.False(report.ConfigurationValid);
        Assert.Null(report.ConfiguredConcurrencyCeiling);
        Assert.Contains(report.Findings, f => f.Code == "topology-version");
        Assert.Contains(report.Findings, f => f.Code == "placement-mode");
        Assert.Contains(report.Findings, f => f.Code == "pool-name");
        Assert.Contains(report.Findings, f => f.Code == "board-collision");
    }

    [Fact]
    public void CasingOnlyPoolAliases_DoNotCountAsIndependentCapacity()
    {
        var first = Pool("alpha") with { HermesFleet = new HermesFleetOptions { Board = "board-one" } };
        var second = Pool("ALPHA") with { HermesFleet = new HermesFleetOptions { Board = "board-two" } };

        var report = FleetReadinessService.Plan(Topology(first, second));

        Assert.False(report.ConfigurationValid);
        Assert.Null(report.ConfiguredConcurrencyCeiling);
        Assert.Contains(report.Findings, f => f.Code == "pool-name" && f.Pool == "ALPHA");
        Assert.DoesNotContain(report.Findings, f => f.Code == "board-collision");
    }

    [Fact]
    public void CasingOnlyBoardAliases_DoNotCountAsIsolatedTaskOwnership()
    {
        var first = Pool("alpha") with { HermesFleet = new HermesFleetOptions { Board = "shared-board" } };
        var second = Pool("beta") with { HermesFleet = new HermesFleetOptions { Board = "SHARED-BOARD" } };

        var report = FleetReadinessService.Plan(Topology(first, second));

        Assert.False(report.ConfigurationValid);
        Assert.Null(report.ConfiguredConcurrencyCeiling);
        Assert.Contains(report.Findings, f => f.Code == "board-collision" && f.Pool == "beta");
        Assert.DoesNotContain(report.Findings, f => f.Code == "pool-name");
    }

    [Fact]
    public void NullCollectionsAndMissingRouting_ReportErrorsInsteadOfReadinessOrExceptions()
    {
        var topology = JsonSerializer.Deserialize<FleetTopology>("""
            {"version":2,"pools":[null,{"name":"broken","taskTypes":null,"providerChain":[],"tools":null}]}
            """)!;
        var report = FleetReadinessService.Plan(topology);
        Assert.False(report.ConfigurationValid);
        Assert.Null(report.ConfiguredConcurrencyCeiling);
        Assert.Contains(report.Findings, f => f.Code == "null-pool");
        Assert.Contains(report.Findings, f => f.Code == "routing-contract");
        Assert.Empty(Assert.Single(report.Pools).DeclaredTools);
        Assert.False(FleetReadinessService.Plan(topology with { Pools = null! }).ConfigurationValid);
    }

    [Theory]
    [InlineData("local", false, true)]
    [InlineData("cloud", true, false)]
    [InlineData("hybrid", true, true)]
    public void ActivationDependencies_AreAcyclicAndOnlyIncludeRequestedPlacements(string mode, bool cloud, bool local)
    {
        var report = FleetReadinessService.Plan(Topology(Pool() with
        {
            PoolSize = 3,
            Autoscaling = new FleetAutoscalingOptions { Mode = mode, MaxBurstLanes = 2 },
        }));
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var stage in report.ActivationStages)
        {
            Assert.All(stage.DependsOn, dependency => Assert.Contains(dependency, seen));
            Assert.True(seen.Add(stage.Id));
            Assert.NotEmpty(stage.RequiredEvidence);
        }
        Assert.Equal(cloud, seen.Contains("cloud-task-receipt"));
        Assert.Equal(local, seen.Contains("local-task-receipt"));
        Assert.Contains("knowledge", seen);
    }

    [Fact]
    public void UnknownWorkerCountsRemainExplicitInJson_EvenWhenCallerIgnoresNulls()
    {
        var report = FleetReadinessService.Plan(Topology(Pool()));
        var json = JsonSerializer.Serialize(report, new JsonSerializerOptions { DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull });
        using var document = JsonDocument.Parse(json);
        Assert.Equal(JsonValueKind.Null, document.RootElement.GetProperty("verifiedConcurrentWorkers").ValueKind);
        var placement = document.RootElement.GetProperty("pools")[0].GetProperty("placements")[0];
        Assert.Equal(JsonValueKind.Null, placement.GetProperty("verifiedWorkers").ValueKind);
        Assert.False(placement.GetProperty("runtimeVerified").GetBoolean());
    }
}
