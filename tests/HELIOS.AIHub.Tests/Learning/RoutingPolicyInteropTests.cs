using HELIOS.AIHub.Domain;
using Xunit;

namespace HELIOS.AIHub.Tests.Learning;

/// <summary>Exercises the F# RoutingPolicy through its C# interop surface end to end.</summary>
public class RoutingPolicyInteropTests
{
    [Fact]
    public void ReorderChain_PromotesConsistentlySuccessfulProvider()
    {
        var configured = new[] { "flaky", "reliable" };
        // 6 attempts each — over the confidence threshold (5).
        var providers = new[] { "flaky", "flaky", "flaky", "flaky", "flaky", "flaky",
                                 "reliable", "reliable", "reliable", "reliable", "reliable", "reliable" };
        var successes = new[] { false, false, false, false, true, false,
                                 true, true, true, true, true, true };
        var latencies = new double[12];
        var costs = new double[12];
        var qualities = Enumerable.Repeat(double.NaN, 12).ToArray();

        var result = RoutingPolicyInterop.ReorderChain(
            "code_review", configured, providers, successes, latencies, costs, qualities);

        Assert.Equal(new[] { "reliable", "flaky" }, result);
    }

    [Fact]
    public void ReorderChain_KeepsConfiguredOrder_WhenEvidenceIsThin()
    {
        var configured = new[] { "a", "b" };
        // Only 2 attempts each — below the confidence threshold.
        var providers = new[] { "a", "b" };
        var successes = new[] { false, true };
        var latencies = new double[2];
        var costs = new double[2];
        var qualities = new[] { double.NaN, double.NaN };

        var result = RoutingPolicyInterop.ReorderChain(
            "code_review", configured, providers, successes, latencies, costs, qualities);

        Assert.Equal(configured, result);
    }

    [Fact]
    public void ReorderChain_EmptyHistory_ReturnsConfiguredChain()
    {
        var configured = new[] { "a", "b", "c" };

        var result = RoutingPolicyInterop.ReorderChain(
            "code_review", configured, [], [], [], [], []);

        Assert.Equal(configured, result);
    }

    [Fact]
    public void EstimateCostUsd_ScalesWithTokensAndRate()
    {
        // 1M input tokens at $3/M, 1M output tokens at $15/M => $18.
        var cost = PricingInterop.EstimateCostUsd(3.0, 15.0, 1_000_000, 1_000_000);
        Assert.Equal(18.0, cost, precision: 6);
    }

    [Fact]
    public void FitsBudget_TrueWhenWithinRemaining_FalseWhenOver()
    {
        Assert.True(PricingInterop.FitsBudget(1.0, 3.0, 15.0, 100_000, 0));
        Assert.False(PricingInterop.FitsBudget(0.01, 3.0, 15.0, 1_000_000, 1_000_000));
    }
}
