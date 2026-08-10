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
    internal const int ExpectedAbiVersion = 1;

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
}
