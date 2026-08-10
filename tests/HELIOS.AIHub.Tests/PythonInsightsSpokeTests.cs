using HELIOS.AIHub.Learning;
using Xunit;

namespace HELIOS.AIHub.Tests;

/// <summary>
/// The C#→Python subprocess boundary. Round-trip tests are guarded on the spoke being
/// runnable here (python3 on PATH + a discovered spoke). CI sets
/// HELIOS_REQUIRE_PYTHON_SPOKE=1 so contract regressions fail; local machines without
/// Python may skip round trips, while the explicit degradation tests always run.
/// </summary>
public sealed class PythonInsightsSpokeTests
{
    private static readonly bool RequirePythonSpoke =
        Environment.GetEnvironmentVariable("HELIOS_REQUIRE_PYTHON_SPOKE") == "1";

    private static RoutingOutcome Outcome(string provider, bool success, double latencyMs = 100) => new()
    {
        Timestamp = DateTimeOffset.UnixEpoch,
        TaskType = "code_generation",
        Provider = provider,
        Model = "m",
        Success = success,
        LatencyMs = latencyMs,
        CostUsd = 0.001,
    };

    [Fact]
    public async Task Summarize_RoundTripsThroughSubprocess()
    {
        var spoke = new PythonInsightsSpoke();
        var outcomes = new[] { Outcome("openai", true, 200), Outcome("openai", false, 100) };

        var summary = await spoke.SummarizeAsync(outcomes);
        if (summary is null)
        {
            Assert.False(RequirePythonSpoke, "The required Python spoke did not round-trip.");
            return;
        }

        var openai = summary.Value.GetProperty("providers").GetProperty("openai");
        Assert.Equal(2, openai.GetProperty("attempts").GetInt32());
        Assert.Equal(0.5, openai.GetProperty("successRate").GetDouble(), precision: 4);
        Assert.Equal(150.0, openai.GetProperty("avgLatencyMs").GetDouble(), precision: 2);
    }

    [Fact]
    public async Task GroupSimilar_FlagsNearDuplicates()
    {
        var spoke = new PythonInsightsSpoke();

        var result = await spoke.GroupSimilarAsync(new[]
        {
            "the circuit breaker opens after five failures",
            "circuit breaker opens after five consecutive failures",
            "bicep parameters configure model capacity",
        }, threshold: 0.5);
        if (result is null)
        {
            Assert.False(RequirePythonSpoke, "The required Python spoke did not round-trip.");
            return;
        }

        var groups = result.Value.GetProperty("groups");
        Assert.Equal(2, groups.GetArrayLength());
        Assert.Equal(2, groups[0].GetArrayLength());
    }

    [Fact]
    public async Task EngineRecommendation_SeparatesAvailableImplementationsAndCandidates()
    {
        var spoke = new PythonInsightsSpoke();

        var result = await spoke.RecommendEnginesAsync(
            cudaEnabled: false,
            securityProfile: "hardened",
            optimizationPressure: 0.8,
            fleetSize: 36,
            includeCandidates: true);
        if (result is null)
        {
            Assert.False(RequirePythonSpoke, "The required Python spoke did not round-trip.");
            return;
        }

        Assert.True(result.Value.GetProperty("selected_count").GetInt32() > 0);
        Assert.True(result.Value.GetProperty("candidate_count").GetInt32() > 0);
        Assert.All(
            result.Value.GetProperty("selected_engines").EnumerateArray(),
            engine =>
            {
                Assert.Equal("implemented", engine.GetProperty("maturity").GetString());
                Assert.True(engine.GetProperty("runtime_available").GetBoolean());
            });
        Assert.All(
            result.Value.GetProperty("candidate_engines").EnumerateArray(),
            engine => Assert.NotEqual("implemented", engine.GetProperty("maturity").GetString()));
        var routingPolicy = Assert.Single(
            result.Value.GetProperty("selected_engines").EnumerateArray(),
            engine => engine.GetProperty("name").GetString() == "routing-policy");
        Assert.True(routingPolicy.GetProperty("runtime_available").GetBoolean());
    }

    [Fact]
    public async Task BogusSpokeDirectory_DegradesToNullNotException()
    {
        var spoke = new PythonInsightsSpoke(Path.GetTempPath());

        Assert.True(spoke.IsAvailable);
        Assert.Null(await spoke.SummarizeAsync(Array.Empty<RoutingOutcome>()));
    }

    [Fact]
    public void FindSpokeDirectory_LocatesTheCheckedInSpoke()
    {
        var directory = PythonInsightsSpoke.FindSpokeDirectory();

        Assert.NotNull(directory);
        Assert.True(File.Exists(Path.Combine(directory, "helios_agents", "__main__.py")));
    }
}
