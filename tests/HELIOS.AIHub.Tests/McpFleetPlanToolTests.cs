using System.Reflection;
using System.Text.Json;
using HELIOS.AIHub.Configuration;
using HELIOS.AIHub.Learning;
using HELIOS.Mcp;
using Xunit;

namespace HELIOS.AIHub.Tests;

/// <summary>
/// The advisory fleet-plan MCP tool (helios_fleet_plan_get): discoverability, the
/// CLI-parity row shape ({pool, taskType, configuredChain, learnedChain, sampleCount,
/// engine}), the always-present advisory field, and the degradation paths (missing
/// topology, empty learning history, empty topology). Keyless and deterministic:
/// the hub is built over a <see cref="FakeLearningStore"/> and a fabricated topology
/// file; histories reuse the FleetPlanServiceTests sample counts that pin the linear
/// engine (under the neural learner's 12-sample minimum).
/// </summary>
public sealed class McpFleetPlanToolTests : IDisposable
{
    private const string TaskTypeName = "code_review";

    private readonly List<string> _roots = new();

    public void Dispose()
    {
        foreach (var root in _roots)
        {
            try
            {
                Directory.Delete(root, recursive: true);
            }
            catch (IOException)
            {
            }
            catch (UnauthorizedAccessException)
            {
            }
        }
    }

    // ---- discoverability -----------------------------------------------------------

    [Fact]
    public void FleetPlanTool_IsDiscoverable_ReadOnlyIdempotentClosedWorld()
    {
        var method = typeof(HeliosFleetPlanTools).GetMethod(
            nameof(HeliosFleetPlanTools.GetFleetPlan), BindingFlags.Public | BindingFlags.Static);

        Assert.NotNull(method);
        var toolAttribute = Assert.Single(
            method.GetCustomAttributes(),
            attribute => attribute.GetType().Name == "McpServerToolAttribute");
        var attributeType = toolAttribute.GetType();
        Assert.Equal("helios_fleet_plan_get", attributeType.GetProperty("Name")?.GetValue(toolAttribute)?.ToString());
        Assert.Equal(true, attributeType.GetProperty("ReadOnly")?.GetValue(toolAttribute));
        Assert.Equal(true, attributeType.GetProperty("Idempotent")?.GetValue(toolAttribute));
        Assert.Equal(false, attributeType.GetProperty("OpenWorld")?.GetValue(toolAttribute));
    }

    // ---- happy path against a fabricated topology + scripted store --------------------

    [Fact]
    public async Task FleetPlan_OrganicHistory_EmitsCliShapedRows_WithLearnedReorder()
    {
        // 6 flaky failures + 5 reliable successes: both providers clear the linear
        // policy's confidence threshold while the 11-record total stays under the
        // neural learner's 12-sample minimum — deterministic "linear" either way
        // (same fixture reasoning as FleetPlanServiceTests).
        var history = new List<RoutingOutcome>();
        for (var i = 0; i < 6; i++)
        {
            history.Add(FakeLearningStore.Outcome(TaskTypeName, "flaky", success: false));
        }
        for (var i = 0; i < 5; i++)
        {
            history.Add(FakeLearningStore.Outcome(TaskTypeName, "reliable", success: true));
        }
        var topologyPath = WriteTopology("""
            {
              "version": 2,
              "pools": [
                {
                  "name": "xcore-9-test",
                  "taskTypes": ["code_review"],
                  "providerChain": ["flaky", "reliable"],
                  "hermesFleet": { "board": "xcore-test", "maxConcurrentLanes": 2 }
                }
              ]
            }
            """);

        var json = await HeliosFleetPlanTools.GetFleetPlan(Hub(history), topologyPath);
        using var doc = JsonDocument.Parse(json);

        Assert.Equal(topologyPath, doc.RootElement.GetProperty("topologyPath").GetString());
        var row = Assert.Single(doc.RootElement.GetProperty("plan").EnumerateArray());
        Assert.Equal("xcore-9-test", row.GetProperty("pool").GetString());
        Assert.Equal(TaskTypeName, row.GetProperty("taskType").GetString());
        Assert.Equal(
            new[] { "flaky", "reliable" },
            row.GetProperty("configuredChain").EnumerateArray().Select(e => e.GetString()).ToArray());
        Assert.Equal(
            new[] { "reliable", "flaky" },
            row.GetProperty("learnedChain").EnumerateArray().Select(e => e.GetString()).ToArray());
        Assert.Equal(11, row.GetProperty("sampleCount").GetInt32());
        Assert.Equal("linear", row.GetProperty("engine").GetString());

        // The advisory contract rides in-band on every response.
        var advisory = doc.RootElement.GetProperty("advisory").GetString();
        Assert.Contains("never applied", advisory);
        Assert.Contains("config/fleet/fleet-topology.json", advisory);
        Assert.False(doc.RootElement.TryGetProperty("message", out _));
    }

    [Fact]
    public async Task FleetPlan_EmptyLearningHistory_ReportsEngineNone_AndConfiguredOrder()
    {
        var topologyPath = WriteTopology("""
            {
              "version": 2,
              "pools": [
                {
                  "name": "xcore-9-test",
                  "taskTypes": ["code_review"],
                  "providerChain": ["a", "b", "c"]
                }
              ]
            }
            """);

        var json = await HeliosFleetPlanTools.GetFleetPlan(
            Hub(Array.Empty<RoutingOutcome>()), topologyPath);
        using var doc = JsonDocument.Parse(json);

        var row = Assert.Single(doc.RootElement.GetProperty("plan").EnumerateArray());
        Assert.Equal(
            new[] { "a", "b", "c" },
            row.GetProperty("learnedChain").EnumerateArray().Select(e => e.GetString()).ToArray());
        Assert.Equal(0, row.GetProperty("sampleCount").GetInt32());
        Assert.Equal("none", row.GetProperty("engine").GetString());
    }

    // ---- degradation paths ------------------------------------------------------------

    [Fact]
    public async Task FleetPlan_MissingTopology_ReturnsMessage_NotAnError()
    {
        var missing = Path.Combine(CreateDirectory(), "no-such-topology.json");

        var json = await HeliosFleetPlanTools.GetFleetPlan(
            Hub(Array.Empty<RoutingOutcome>()), missing);
        using var doc = JsonDocument.Parse(json);

        Assert.Equal(0, doc.RootElement.GetProperty("plan").GetArrayLength());
        Assert.Contains(missing, doc.RootElement.GetProperty("message").GetString());
        Assert.Contains("never applied", doc.RootElement.GetProperty("advisory").GetString());
    }

    [Fact]
    public async Task FleetPlan_UnreadableTopology_ReturnsMessage_NotAnError()
    {
        var topologyPath = WriteTopology("{ this is not json");

        var json = await HeliosFleetPlanTools.GetFleetPlan(
            Hub(Array.Empty<RoutingOutcome>()), topologyPath);
        using var doc = JsonDocument.Parse(json);

        Assert.Equal(0, doc.RootElement.GetProperty("plan").GetArrayLength());
        Assert.Contains(topologyPath, doc.RootElement.GetProperty("message").GetString());
    }

    [Fact]
    public async Task FleetPlan_TopologyWithoutPools_ReturnsEmptyPlan_WithMessage()
    {
        var topologyPath = WriteTopology("""{ "version": 2, "pools": [] }""");

        var json = await HeliosFleetPlanTools.GetFleetPlan(
            Hub(Array.Empty<RoutingOutcome>()), topologyPath);
        using var doc = JsonDocument.Parse(json);

        Assert.Equal(0, doc.RootElement.GetProperty("plan").GetArrayLength());
        Assert.Contains("nothing to score", doc.RootElement.GetProperty("message").GetString());
        Assert.Contains("never applied", doc.RootElement.GetProperty("advisory").GetString());
    }

    // ---- helpers ---------------------------------------------------------------------

    /// <summary>
    /// A keyless hub whose planner reads the scripted history — the same construction
    /// seam AIHubService exposes for tests (learning store injected, no providers, no
    /// keys, no network).
    /// </summary>
    private static AIHubService Hub(IReadOnlyList<RoutingOutcome> history) =>
        new(new AIHubOptions(), learning: new FakeLearningStore(history));

    private string WriteTopology(string json)
    {
        var path = Path.Combine(CreateDirectory(), "fleet-topology.json");
        File.WriteAllText(path, json);
        return path;
    }

    private string CreateDirectory()
    {
        var root = Path.Combine(Path.GetTempPath(), $"helios-mcp-fleetplan-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        _roots.Add(root);
        return root;
    }
}
