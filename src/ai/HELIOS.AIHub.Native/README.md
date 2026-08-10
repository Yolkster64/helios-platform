# HELIOS.AIHub.Native

C++ spoke for the AIHub: cosine similarity (response dedup across a `compare` fan-out)
and UTF-8-safe token estimation, exposed as a flat C ABI and called from C# via
`LibraryImport` (see `src/ai/HELIOS.AIHub/Native/NativeMethods.cs`). See
`.claude/skills/cpp-performance/SKILL.md` for the interop rules this follows.

## Build

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
# Sanitizer build for local UB/overflow checking (non-MSVC):
cmake -S . -B build-san -DCMAKE_BUILD_TYPE=Debug -DHELIOS_SANITIZE=ON
cmake --build build-san
```

Produces `helios_aihub_native` (`.dll`/`.so`/`.dylib`) — copy or symlink it next to the
AIHub's output directory so `LibraryImport` resolves it at runtime. This library is
optional: nothing in HELIOS.AIHub calls into it yet (PR3 wires the `compare` dedup path),
so its absence does not affect `dotnet build`/`dotnet test`.

## ABI contract

- Every function returns a `helios_status`; none throw across the boundary.
- The caller owns all memory; nothing here allocates or retains a pointer past return.
- `helios_abi_version()` lets the managed side detect a stale native binary at startup
  instead of silently misreading its memory layout.
