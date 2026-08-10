# HELIOS.AIHub.Native

C++ spoke for the AIHub: cosine similarity (response dedup across a `compare` fan-out),
UTF-8-safe token estimation, and an online MLP routing learner (`helios_mlp_*`: a
deterministic single-hidden-layer network trained sample-by-sample on routing outcomes —
see the header's doc block for the weight layout and determinism contract). All of it is
exposed as a flat C ABI and called from C# via `LibraryImport`
(see `src/ai/HELIOS.AIHub/Native/NativeMethods.cs`). See
`.claude/skills/cpp-performance/SKILL.md` for the interop rules this follows.

## Build

```bash
scripts/build/build-native.sh              # Release build into ./build
scripts/build/build-native.sh --sanitize   # ASan/UBSan build into ./build-san
# Windows: scripts/build/build-native.ps1
```

Or directly:

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
```

`HELIOS.AIHub.csproj` picks up the binary from `build/` automatically when it exists and
copies it to the AIHub, CLI, and test output directories, so `LibraryImport` resolves it
at runtime — build native first, then `dotnet build`. The library is optional at runtime:
when it is absent, token estimation falls back to a managed byte-count heuristic and
`compare` dedup returns results unmarked. CI builds it unconditionally and asserts it
reached the test output, so the native code paths are always exercised there
(`.github/workflows/dotnet-build.yml`).

## ABI contract

- Every function returns a `helios_status`; none throw across the boundary.
- The caller owns all memory; nothing here allocates or retains a pointer past return.
- `helios_abi_version()` lets the managed side detect a stale native binary at startup
  instead of silently misreading its memory layout —
  `NativeMethods.ExpectedAbiVersion` must match, and the test suite checks it.
