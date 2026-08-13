using HELIOS.AIHub.Fleet;
using Xunit;

namespace HELIOS.AIHub.Tests.Fleet;

/// <summary>
/// Binds the real shipped config/fleet/fleet-topology.json so topology drift fails CI
/// (same pattern as ConfigBindingTests). Deliberately asserts pool NAMES and BOARDS
/// only — rosters (skills/agents/tools) evolve independently of this reader.
/// </summary>
public class FleetTopologyTests
{
    [Fact]
    public void ShippedTopology_LoadsWithFourPools_AndExpectedNamesAndBoards()
    {
        var path = FleetTopology.FindTopologyFile(AppContext.BaseDirectory);
        Assert.False(
            path is null,
            "config/fleet/fleet-topology.json not found walking up from test output directory");

        var result = FleetTopology.TryLoad(path);

        Assert.Null(result.Error);
        Assert.NotNull(result.Topology);
        var pools = result.Topology!.Pools;
        Assert.Equal(4, pools.Count);
        Assert.Equal(
            new[] { "xcore-9-code", "xcore-9-infra", "xcore-9-review", "xcore-9-native" },
            pools.Select(p => p.Name));
        Assert.Equal(
            new[] { "xcore-code", "xcore-infra", "xcore-review", "xcore-native" },
            pools.Select(p => p.HermesFleet?.Board));
        Assert.All(pools, p => Assert.NotEmpty(p.TaskTypes));
        Assert.All(pools, p => Assert.NotEmpty(p.ProviderChain));
        Assert.All(pools, p => Assert.True(p.HermesFleet!.MaxConcurrentLanes > 0));
    }

    [Fact]
    public void TryLoad_MissingFile_ReturnsStatusResult_NotException()
    {
        var missing = Path.Combine(Path.GetTempPath(), "no-such-fleet-topology.json");

        var result = FleetTopology.TryLoad(missing);

        Assert.Null(result.Topology);
        Assert.NotNull(result.Error);
        Assert.Contains("no-such-fleet-topology.json", result.Error);
    }

    [Fact]
    public void TryLoad_MalformedJson_ReturnsStatusResult_NotException()
    {
        var path = Path.Combine(Path.GetTempPath(), $"fleet-topology-{Guid.NewGuid():N}.json");
        File.WriteAllText(path, "{ not json");
        try
        {
            var result = FleetTopology.TryLoad(path);

            Assert.Null(result.Topology);
            Assert.NotNull(result.Error);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void TryLoad_ToleratesUnknownFieldsAndCommentEntries()
    {
        var path = Path.Combine(Path.GetTempPath(), $"fleet-topology-{Guid.NewGuid():N}.json");
        File.WriteAllText(path, """
            {
              "$comment": "unknown-to-the-reader metadata everywhere",
              "version": 9,
              "defaults": { "poolSize": 3, "spawn": { "command": "x" } },
              "pools": [
                {
                  "name": "pool-a",
                  "specialization": "unbound field",
                  "taskTypes": ["t1", "t2"],
                  "providerChain": ["p1", "p2"],
                  "hermesFleet": { "board": "board-a", "maxConcurrentLanes": 3, "extra": true },
                  "tools": ["Read"],
                  "autoscaling": { "mode": "local" }
                }
              ],
              "coordination": { "handoffs": [] }
            }
            """);
        try
        {
            var result = FleetTopology.TryLoad(path);

            Assert.Null(result.Error);
            var pool = Assert.Single(result.Topology!.Pools);
            Assert.Equal("pool-a", pool.Name);
            Assert.Equal(new[] { "t1", "t2" }, pool.TaskTypes);
            Assert.Equal(new[] { "p1", "p2" }, pool.ProviderChain);
            Assert.Equal("board-a", pool.HermesFleet?.Board);
            Assert.Equal(3, pool.HermesFleet?.MaxConcurrentLanes);
        }
        finally
        {
            File.Delete(path);
        }
    }
}
