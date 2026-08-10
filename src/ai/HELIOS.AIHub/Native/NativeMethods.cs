using System.Runtime.InteropServices;

namespace HELIOS.AIHub.Native;

/// <summary>
/// P/Invoke surface for the C++ spoke (src/ai/HELIOS.AIHub.Native).
///
/// Uses <c>LibraryImport</c> — the source-generated marshalling path — rather than
/// <c>DllImport</c>: the generated stubs are AOT-friendly and marshalling mistakes become
/// compile errors instead of runtime heap corruption.
/// </summary>
internal static partial class NativeMethods
{
    internal const string Library = "helios_aihub_native";

    /// <summary>ABI version this managed code was written against.</summary>
    internal const int ExpectedAbiVersion = 2;

    [LibraryImport(Library, EntryPoint = "helios_abi_version")]
    [UnmanagedCallConv(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    internal static partial int AbiVersion();

    [LibraryImport(Library, EntryPoint = "helios_cosine_similarity")]
    [UnmanagedCallConv(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    internal static partial int CosineSimilarity(
        ReadOnlySpan<float> a, ReadOnlySpan<float> b, nuint length, out float similarity);

    [LibraryImport(Library, EntryPoint = "helios_similarity_matrix")]
    [UnmanagedCallConv(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    internal static partial int SimilarityMatrix(
        ReadOnlySpan<float> vectors, nuint count, nuint dim, Span<float> matrix);

    [LibraryImport(Library, EntryPoint = "helios_estimate_tokens")]
    [UnmanagedCallConv(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    internal static partial int EstimateTokens(
        ReadOnlySpan<byte> utf8Text, nuint byteLength, out int tokens);

    [LibraryImport(Library, EntryPoint = "helios_fit_prefix_bytes")]
    [UnmanagedCallConv(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    internal static partial int FitPrefixBytes(
        ReadOnlySpan<byte> utf8Text, nuint byteLength, int maxTokens, out nuint fittedByteLength);

    // MLP routing learner. Weight buffers are caller-owned float[] sized via
    // MlpWeightCount; layout and determinism contract are documented in
    // helios_aihub_native.h.

    [LibraryImport(Library, EntryPoint = "helios_mlp_weight_count")]
    [UnmanagedCallConv(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    internal static partial int MlpWeightCount(
        nuint featureDim, nuint hiddenUnits, out nuint weightCount);

    [LibraryImport(Library, EntryPoint = "helios_mlp_init")]
    [UnmanagedCallConv(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    internal static partial int MlpInit(
        Span<float> weights, nuint weightCount,
        nuint featureDim, nuint hiddenUnits, ulong seed);

    [LibraryImport(Library, EntryPoint = "helios_mlp_train")]
    [UnmanagedCallConv(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    internal static partial int MlpTrain(
        Span<float> weights, nuint weightCount,
        nuint featureDim, nuint hiddenUnits,
        ReadOnlySpan<float> features, ReadOnlySpan<float> targets, nuint sampleCount,
        int epochs, float learningRate, float l2Regularization, out float meanLoss);

    [LibraryImport(Library, EntryPoint = "helios_mlp_predict")]
    [UnmanagedCallConv(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    internal static partial int MlpPredict(
        ReadOnlySpan<float> weights, nuint weightCount,
        nuint featureDim, nuint hiddenUnits,
        ReadOnlySpan<float> features, nuint sampleCount, Span<float> scores);
}
