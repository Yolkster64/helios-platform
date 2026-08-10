using HELIOS.AIHub.Domain;
using HELIOS.AIHub.Learning;
using HELIOS.AIHub.Native;
using Xunit;

namespace HELIOS.AIHub.Tests;

/// <summary>
/// Tests for the F# learner-fusion domain (pure, always run) and the end-to-end neural
/// reorder path through <see cref="NeuralRoutingLearner"/> (guarded on the native lib,
/// same policy as NativeLearnerTests).
/// </summary>
public class LearnerFusionTests
{
    private const string TaskType = "code_generation";

    private static (string[] Providers, bool[] Successes, double[] Latencies, double[] Costs, double[] Qualities)
        Arrays(params (string Provider, bool Success)[] outcomes)
    {
        var n = outcomes.Length;
        var providers = new string[n];
        var successes = new bool[n];
        var latencies = new double[n];
        var costs = new double[n];
        var qualities = new double[n];
        for (var i = 0; i < n; i++)
        {
            providers[i] = outcomes[i].Provider;
            successes[i] = outcomes[i].Success;
            latencies[i] = 100;
            costs[i] = 0.01;
            qualities[i] = double.NaN;
        }
        return (providers, successes, latencies, costs, qualities);
    }

    [Fact]
    public void BuildTrainingSet_SkipsEachProvidersFirstOutcome()
    {
        var (p, s, l, c, q) = Arrays(
            ("a", true), ("b", false), ("a", true), ("b", true), ("a", false), ("b", true));

        var training = LearnerFusionInterop.BuildTrainingSet(TaskType, p, s, l, c, q);

        // 6 outcomes, 2 providers: each provider's first outcome has no prior state.
        Assert.Equal(4, training.SampleCount);
        Assert.Equal(4 * LearnerFusionInterop.FeatureDim, training.Features.Length);
        Assert.Equal(4, training.Targets.Length);
    }

    [Fact]
    public void BuildTrainingSet_BlendsQualityIntoTargets()
    {
        var providers = new[] { "a", "a", "a" };
        var successes = new[] { true, true, false };
        var latencies = new[] { 100.0, 100.0, 100.0 };
        var costs = new[] { 0.01, 0.01, 0.01 };
        var qualities = new[] { double.NaN, 0.5, double.NaN };

        var training = LearnerFusionInterop.BuildTrainingSet(
            TaskType, providers, successes, latencies, costs, qualities);

        Assert.Equal(2, training.SampleCount);
        // Second outcome: success with quality 0.5 -> 0.5*1 + 0.5*0.5.
        Assert.Equal(0.75f, training.Targets[0], precision: 5);
        // Third outcome: unrated failure stays a hard 0.
        Assert.Equal(0.0f, training.Targets[1], precision: 5);
    }

    [Fact]
    public void BuildTrainingSet_IsDeterministic()
    {
        var (p, s, l, c, q) = Arrays(
            ("a", true), ("b", false), ("a", true), ("b", true), ("a", false), ("b", true));

        var first = LearnerFusionInterop.BuildTrainingSet(TaskType, p, s, l, c, q);
        var second = LearnerFusionInterop.BuildTrainingSet(TaskType, p, s, l, c, q);

        Assert.Equal(first.Features, second.Features);
        Assert.Equal(first.Targets, second.Targets);
    }

    [Fact]
    public void BuildCandidates_KeepsChainOrderAndDropsProvidersWithoutHistory()
    {
        var (p, s, l, c, q) = Arrays(("b", true), ("a", true), ("b", false), ("stranger", true));
        var chain = new[] { "a", "b", "c" };

        var candidates = LearnerFusionInterop.BuildCandidates(TaskType, chain, p, s, l, c, q);

        Assert.Equal(new[] { "a", "b" }, candidates.Providers);
        Assert.Equal(new[] { 1, 2 }, candidates.Attempts);
        Assert.Equal(2 * LearnerFusionInterop.FeatureDim, candidates.Features.Length);
    }

    [Fact]
    public void FuseChain_KeepsConfiguredOrderWithThinEvidence()
    {
        // 3 attempts each — below the confidence floor, so even an emphatic network
        // opinion must not move anything.
        var (p, s, l, c, q) = Arrays(
            ("a", false), ("b", true), ("a", false), ("b", true), ("a", false), ("b", true));

        var fused = LearnerFusionInterop.FuseChain(
            TaskType, new[] { "a", "b" }, p, s, l, c, q,
            new[] { "a", "b" }, new[] { 0.0, 1.0 });

        Assert.Equal(new[] { "a", "b" }, fused);
    }

    [Fact]
    public void FuseChain_PromotesProviderTheNetworkFavors()
    {
        // Identical linear evidence (same successes, latencies, costs) so only the MLP
        // prediction differentiates — the fusion term must be what flips the order.
        var (p, s, l, c, q) = Arrays(
            ("a", true), ("b", true), ("a", true), ("b", true), ("a", true), ("b", true),
            ("a", true), ("b", true), ("a", true), ("b", true), ("a", true), ("b", true));

        var fused = LearnerFusionInterop.FuseChain(
            TaskType, new[] { "a", "b" }, p, s, l, c, q,
            new[] { "a", "b" }, new[] { 0.2, 0.9 });

        Assert.Equal(new[] { "b", "a" }, fused);
    }

    // --- End-to-end through the native MLP ------------------------------------------

    private static bool NativeLibraryPresent()
    {
        try
        {
            NativeMethods.AbiVersion();
            return true;
        }
        catch (DllNotFoundException)
        {
            return false;
        }
    }

    private static IReadOnlyList<RoutingOutcome> NewestFirstHistory(
        params (string Provider, bool Success)[] chronological)
    {
        var start = new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero);
        return chronological
            .Select((o, i) => new RoutingOutcome
            {
                Timestamp = start.AddMinutes(i),
                TaskType = TaskType,
                Provider = o.Provider,
                Model = "test-model",
                Success = o.Success,
                LatencyMs = 100,
                CostUsd = 0.01,
            })
            .Reverse()
            .ToList();
    }

    [Fact]
    public void NeuralReorder_ReturnsNullOnThinHistory()
    {
        // Early-out happens before any native call, so this is safe without the lib.
        var learner = new NeuralRoutingLearner();
        var history = NewestFirstHistory(("a", true), ("b", true), ("a", true), ("b", true));

        Assert.Null(learner.Reorder(TaskType, new[] { "a", "b" }, history));
    }

    [Fact]
    public void NeuralReorder_PutsTheSucceedingProviderFirst()
    {
        if (!NativeLibraryPresent())
        {
            return;
        }

        // "flaky" almost always fails, "solid" almost always succeeds; both have plenty
        // of attempts. Linear policy and MLP agree here — the assertion is that the full
        // path (F# features -> native train/predict -> F# fusion) runs and reorders.
        var learner = new NeuralRoutingLearner();
        var history = NewestFirstHistory(
            ("flaky", false), ("solid", true), ("flaky", false), ("solid", true),
            ("flaky", true), ("solid", true), ("flaky", false), ("solid", false),
            ("flaky", false), ("solid", true), ("flaky", false), ("solid", true),
            ("flaky", false), ("solid", true), ("flaky", false), ("solid", true));

        var reordered = learner.Reorder(TaskType, new[] { "flaky", "solid" }, history);

        Assert.NotNull(reordered);
        Assert.Equal(new[] { "solid", "flaky" }, reordered);
    }

    [Fact]
    public void NeuralReorder_IsDeterministicForIdenticalHistory()
    {
        if (!NativeLibraryPresent())
        {
            return;
        }

        var history = NewestFirstHistory(
            ("a", true), ("b", false), ("a", true), ("b", true),
            ("a", false), ("b", true), ("a", true), ("b", false),
            ("a", true), ("b", true), ("a", true), ("b", false),
            ("a", true), ("b", true));
        var chain = new[] { "a", "b" };

        var first = new NeuralRoutingLearner().Reorder(TaskType, chain, history);
        var second = new NeuralRoutingLearner().Reorder(TaskType, chain, history);

        Assert.NotNull(first);
        Assert.Equal(first, second);
    }
}
