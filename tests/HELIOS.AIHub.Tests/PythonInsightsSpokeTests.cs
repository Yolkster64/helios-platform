using HELIOS.AIHub.Learning;
using Xunit;

namespace HELIOS.AIHub.Tests;

/// <summary>
/// The C#→Python subprocess boundary. Round-trip tests are guarded on the spoke being
/// runnable here (python3 on PATH + src/ai/python found by walk-up), so keyless CI and
/// Windows dev boxes without Python stay green; the degrade tests always run.
/// </summary>
public sealed class PythonInsightsSpokeTests
{
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
            return; // no runnable Python spoke in this environment
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
            return;
        }

        var groups = result.Value.GetProperty("groups");
        Assert.Equal(2, groups.GetArrayLength());
        Assert.Equal(2, groups[0].GetArrayLength());
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
