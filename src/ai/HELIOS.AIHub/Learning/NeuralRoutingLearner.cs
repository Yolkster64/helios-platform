using HELIOS.AIHub.Domain;
using HELIOS.AIHub.Native;

namespace HELIOS.AIHub.Learning;

/// <summary>
/// Deep-learning chain reordering: trains the native C++ MLP on recorded outcomes and
/// fuses its per-provider predictions with the F# linear routing policy.
///
/// Division of labor, per the hub-and-spoke rule: the F# domain builds feature vectors
/// and fuses scores (pure math), the C++ spoke trains and predicts (tight loops), and
/// this class is the only place the two meet — spokes never call each other.
///
/// Returns null whenever it cannot improve on the linear policy: native library absent,
/// too little history, too few candidates, or any native error. Callers fall back to
/// <see cref="RoutingPolicyInterop.ReorderChain"/>, so learning can refine routing but
/// never break it.
/// </summary>
internal sealed class NeuralRoutingLearner
{
    private const int HiddenUnits = 16;
    private const int Epochs = 300;
    private const float LearningRate = 0.05f;
    private const float L2Regularization = 1e-4f;

    /// <summary>Fixed seed: identical history must yield identical routing.</summary>
    private const ulong Seed = 42;

    /// <summary>Below this many prequential samples the MLP just memorizes noise.</summary>
    private const int MinTrainingSamples = 12;

    private readonly object _gate = new();
    private bool _nativeUnavailable;
    private string? _cachedTaskType;
    private int _cachedHistoryCount;
    private DateTimeOffset _cachedNewest;
    private float[]? _cachedWeights;

    /// <summary>
    /// Reorder <paramref name="configuredChain"/> from <paramref name="history"/>
    /// (newest first, as the learning store returns it), or null when the neural path
    /// has nothing trustworthy to add.
    /// </summary>
    public string[]? Reorder(
        string taskType, IReadOnlyList<string> configuredChain, IReadOnlyList<RoutingOutcome> history)
    {
        if (_nativeUnavailable || !NativeGate.Available
            || history.Count < MinTrainingSamples || configuredChain.Count < 2)
        {
            return null;
        }

        // The store returns newest first; prequential training replays history forward,
        // so flip to chronological order.
        var n = history.Count;
        var providers = new string[n];
        var successes = new bool[n];
        var latencies = new double[n];
        var costs = new double[n];
        var qualities = new double[n];
        for (var i = 0; i < n; i++)
        {
            var h = history[n - 1 - i];
            providers[i] = h.Provider;
            successes[i] = h.Success;
            latencies[i] = h.LatencyMs;
            costs[i] = h.CostUsd;
            qualities[i] = h.Quality ?? double.NaN;
        }

        try
        {
            lock (_gate)
            {
                var chain = configuredChain.ToArray();
                var candidates = LearnerFusionInterop.BuildCandidates(
                    taskType, chain, providers, successes, latencies, costs, qualities);
                if (candidates.Providers.Length < 2)
                {
                    return null;
                }

                var weights = TrainOrGetCached(
                    taskType, n, history[0].Timestamp, providers, successes, latencies, costs, qualities);
                if (weights is null)
                {
                    return null;
                }

                var scores = new float[candidates.Providers.Length];
                var status = NativeMethods.MlpPredict(
                    weights, (nuint)weights.Length,
                    (nuint)LearnerFusionInterop.FeatureDim, (nuint)HiddenUnits,
                    candidates.Features, (nuint)candidates.Providers.Length, scores);
                if (status != 0)
                {
                    return null;
                }

                return LearnerFusionInterop.FuseChain(
                    taskType, chain, providers, successes, latencies, costs, qualities,
                    candidates.Providers, Array.ConvertAll(scores, s => (double)s));
            }
        }
        catch (DllNotFoundException)
        {
            _nativeUnavailable = true;
            return null;
        }
        catch (EntryPointNotFoundException)
        {
            _nativeUnavailable = true;
            return null;
        }
    }

    /// <summary>
    /// Train, or reuse the last weights when history is unchanged. The key includes the
    /// newest timestamp because once the store's window saturates, the count stops
    /// moving while the content keeps sliding.
    /// </summary>
    private float[]? TrainOrGetCached(
        string taskType, int historyCount, DateTimeOffset newest,
        string[] providers, bool[] successes, double[] latencies, double[] costs, double[] qualities)
    {
        if (_cachedWeights is not null
            && _cachedTaskType == taskType
            && _cachedHistoryCount == historyCount
            && _cachedNewest == newest)
        {
            return _cachedWeights;
        }

        var training = LearnerFusionInterop.BuildTrainingSet(
            taskType, providers, successes, latencies, costs, qualities);
        if (training.SampleCount < MinTrainingSamples)
        {
            return null;
        }

        var dim = (nuint)LearnerFusionInterop.FeatureDim;
        if (NativeMethods.MlpWeightCount(dim, (nuint)HiddenUnits, out var weightCount) != 0)
        {
            return null;
        }

        var weights = new float[(int)weightCount];
        if (NativeMethods.MlpInit(weights, weightCount, dim, (nuint)HiddenUnits, Seed) != 0)
        {
            return null;
        }

        var status = NativeMethods.MlpTrain(
            weights, weightCount, dim, (nuint)HiddenUnits,
            training.Features, training.Targets, (nuint)training.SampleCount,
            Epochs, LearningRate, L2Regularization, out _);
        if (status != 0)
        {
            return null;
        }

        _cachedTaskType = taskType;
        _cachedHistoryCount = historyCount;
        _cachedNewest = newest;
        _cachedWeights = weights;
        return weights;
    }
}
