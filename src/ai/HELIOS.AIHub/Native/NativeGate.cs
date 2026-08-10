namespace HELIOS.AIHub.Native;

/// <summary>
/// One-time ABI handshake with the native library. Callers consult
/// <see cref="Available"/> before any other native call: a stale .so/.dll left
/// behind by a partial deployment must degrade to the managed fallbacks, not
/// call into exports whose signatures or buffer contracts may have changed.
/// </summary>
internal static class NativeGate
{
    private static readonly Lazy<bool> _available = new(() =>
    {
        try
        {
            return NativeMethods.AbiVersion() == NativeMethods.ExpectedAbiVersion;
        }
        catch (DllNotFoundException)
        {
            return false;
        }
        catch (EntryPointNotFoundException)
        {
            return false;
        }
        catch (BadImageFormatException)
        {
            // Wrong-architecture or corrupt binary. Lazy<bool> caches a thrown
            // exception forever, so letting this escape would poison every later
            // Available check instead of degrading to the managed fallbacks.
            return false;
        }
    });

    internal static bool Available => _available.Value;
}
