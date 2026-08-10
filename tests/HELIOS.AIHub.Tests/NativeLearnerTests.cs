using HELIOS.AIHub.Native;
using Xunit;

namespace HELIOS.AIHub.Tests;

/// <summary>
/// Tests for the native MLP routing learner. These run only when the C++ spoke is
/// loadable (built via scripts/build/build-native.sh); CI asserts its presence so the
/// learner is always exercised there, while keyless/toolless dev runs stay green.
/// </summary>
public class NativeLearnerTests
{
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

    private static float[] InitializedWeights(
        nuint dim, nuint hidden, ulong seed, out nuint count)
    {
        Assert.Equal(0, NativeMethods.MlpWeightCount(dim, hidden, out count));
        var weights = new float[(int)count];
        Assert.Equal(0, NativeMethods.MlpInit(weights, count, dim, hidden, seed));
        return weights;
    }

    [Fact]
    public void MlpWeightCount_MatchesLayoutFormula()
    {
        if (!NativeLibraryPresent())
        {
            return;
        }

        Assert.Equal(0, NativeMethods.MlpWeightCount(6, 8, out var count));

        // W1[8][6] + b1[8] + W2[8] + b2 = 48 + 8 + 8 + 1.
        Assert.Equal((nuint)65, count);
    }

    [Fact]
    public void MlpInit_IsDeterministicPerSeed()
    {
        if (!NativeLibraryPresent())
        {
            return;
        }

        var first = InitializedWeights(4, 6, seed: 7, out _);
        var second = InitializedWeights(4, 6, seed: 7, out _);
        var different = InitializedWeights(4, 6, seed: 8, out _);

        Assert.Equal(first, second);
        Assert.NotEqual(first, different);
    }

    [Fact]
    public void MlpTrain_LearnsXor_WhichALinearModelCannot()
    {
        if (!NativeLibraryPresent())
        {
            return;
        }

        // XOR is the canonical function no linear scorer (like the F# routing policy's
        // weighted sum) can represent. Deterministic seed + fixed sample order means
        // this either always passes or always fails — no flakiness.
        var weights = InitializedWeights(2, 8, seed: 42, out var count);
        float[] features = { 0f, 0f, 0f, 1f, 1f, 0f, 1f, 1f };
        float[] targets = { 0f, 1f, 1f, 0f };

        var status = NativeMethods.MlpTrain(
            weights, count, 2, 8, features, targets, 4,
            epochs: 4000, learningRate: 0.5f, l2Regularization: 0f, out var meanLoss);

        Assert.Equal(0, status);
        Assert.True(meanLoss < 0.1f, $"final mean loss {meanLoss} did not converge");

        var scores = new float[4];
        Assert.Equal(0, NativeMethods.MlpPredict(weights, count, 2, 8, features, 4, scores));
        Assert.True(scores[0] < 0.4f, $"f(0,0) = {scores[0]}, expected < 0.4");
        Assert.True(scores[1] > 0.6f, $"f(0,1) = {scores[1]}, expected > 0.6");
        Assert.True(scores[2] > 0.6f, $"f(1,0) = {scores[2]}, expected > 0.6");
        Assert.True(scores[3] < 0.4f, $"f(1,1) = {scores[3]}, expected < 0.4");
    }

    [Fact]
    public void MlpTrain_ReducesLoss()
    {
        if (!NativeLibraryPresent())
        {
            return;
        }

        var weights = InitializedWeights(2, 8, seed: 42, out var count);
        float[] features = { 0f, 0f, 0f, 1f, 1f, 0f, 1f, 1f };
        float[] targets = { 0f, 1f, 1f, 0f };

        Assert.Equal(0, NativeMethods.MlpTrain(
            weights, count, 2, 8, features, targets, 4,
            epochs: 1, learningRate: 0.5f, l2Regularization: 0f, out var earlyLoss));
        Assert.Equal(0, NativeMethods.MlpTrain(
            weights, count, 2, 8, features, targets, 4,
            epochs: 2000, learningRate: 0.5f, l2Regularization: 0f, out var lateLoss));

        Assert.True(lateLoss < earlyLoss,
            $"loss went from {earlyLoss} to {lateLoss}; training should reduce it");
    }

    [Fact]
    public void Mlp_RejectsMismatchedWeightBuffer()
    {
        if (!NativeLibraryPresent())
        {
            return;
        }

        var tooSmall = new float[10];

        // HELIOS_ERR_DIMENSION_MISMATCH = -3.
        Assert.Equal(-3, NativeMethods.MlpInit(tooSmall, 10, 2, 8, seed: 1));
    }
}
