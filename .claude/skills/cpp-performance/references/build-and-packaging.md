# Native spoke — build and packaging

*Versions and API claims mirror the cited repo files; update this file in the same PR
that changes them.*

The one native project is `src/ai/HELIOS.AIHub.Native` (cosine similarity, token
estimation, MLP routing learner behind a flat C ABI — see its `README.md`; the managed
consumer is `src/ai/HELIOS.AIHub/Native/NativeMethods.cs` via `LibraryImport`).

## CMakeLists.txt — the parts that carry decisions

`src/ai/HELIOS.AIHub.Native/CMakeLists.txt`:

- `cmake_minimum_required(VERSION 3.20)` — the floor every tooling suggestion must
  respect (see the presets note below).
- C++20, `CMAKE_CXX_EXTENSIONS OFF`, `CMAKE_POSITION_INDEPENDENT_CODE ON`.
- `CMAKE_CXX_VISIBILITY_PRESET hidden` + `CMAKE_VISIBILITY_INLINES_HIDDEN ON`:
  everything not explicitly exported is hidden, "so the ABI surface is exactly the
  header" (the file's own comment). New exports are deliberate acts, not accidents.
- One SHARED library, one TU (`helios_aihub_native.cpp`).
- MSVC: `/W4 /permissive- /GS /guard:cf`; Release adds `/O2 /GL /Qpar /fp:fast`;
  link `/guard:cf /DYNAMICBASE /NXCOMPAT /CETCOMPAT`, Release `/LTCG`. The security
  flags are annotated non-negotiable in-file.
- GCC/Clang: `-Wall -Wextra -Wpedantic -fstack-protector-strong -D_FORTIFY_SOURCE=2`;
  Release `-O3 -ffast-math`; Release link `-Wl,-z,relro,-z,now` — except on Apple,
  whose linker rejects `-z relro/now` (guarded by `if(NOT APPLE)`).
- `option(HELIOS_SANITIZE ...)` — ASan+UBSan build, applied only when not MSVC.
- Note `/fp:fast` / `-ffast-math` on Release: fine for similarity scoring, but it
  abandons strict IEEE semantics — code needing exact FP means revisiting these flags.

## The build entry points

`scripts/build/build-native.sh` (what CI runs) and `scripts/build/build-native.ps1`
(Windows twin):

- Release: configures `-DCMAKE_BUILD_TYPE=Release` into `<src>/build`, passes
  `-DCMAKE_CXX_FLAGS_RELEASE="-O3 -DNDEBUG"` explicitly ("so the intent survives
  toolchain-default changes"), and probes an `-O3 -flto` compile+link before setting
  `-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON` — an unsupported toolchain silently keeps
  LTO off instead of breaking the build.
- `--sanitize`: Debug + `-DHELIOS_SANITIZE=ON` into `<src>/build-san`.
- The output paths are load-bearing: `HELIOS.AIHub.csproj` conditionally picks up
  `build/libhelios_aihub_native.so`, `build/libhelios_aihub_native.dylib`, and
  `build/Release/helios_aihub_native.dll` and copies them beside the AIHub/CLI/test
  outputs. Rename `build/` and the managed side silently falls back to managed paths.
- CI (`.github/workflows/dotnet-build.yml`) builds the native library unconditionally
  BEFORE `dotnet build`, then asserts
  `tests/HELIOS.AIHub.Tests/bin/Release/net8.0/libhelios_aihub_native.so` exists —
  graceful runtime degradation is for dev machines, not for CI silently skipping the
  native code paths.

## CMakePresets.json — canonical shape (none exists yet)

Honest gap: there is no `CMakePresets.json` today; the two scripts are the only
blessed entry points. If one is added it must MIRROR the scripts, not replace them
(CI calls `build-native.sh`). The canonical shape:

```json
{
  "version": 2,
  "cmakeMinimumRequired": { "major": 3, "minor": 20, "patch": 0 },
  "configurePresets": [
    { "name": "release", "binaryDir": "${sourceDir}/build",
      "cacheVariables": { "CMAKE_BUILD_TYPE": "Release" } },
    { "name": "sanitize", "binaryDir": "${sourceDir}/build-san",
      "cacheVariables": { "CMAKE_BUILD_TYPE": "Debug", "HELIOS_SANITIZE": "ON" } }
  ],
  "buildPresets": [
    { "name": "release", "configurePreset": "release" },
    { "name": "sanitize", "configurePreset": "sanitize" }
  ]
}
```

Why `"version": 2`: preset schema v1 = CMake 3.19 (configure presets only), v2 = 3.20
(adds build/test presets), v3 = 3.21 (`condition`, `toolchainFile`, ...) — per the
cmake-presets(7) manual. v2 is the newest schema the project's own
`cmake_minimum_required(3.20)` can parse; using v3+ features means raising the
minimum in the same change. `binaryDir` must stay `build` / `build-san` — the csproj
pickup and the CI assert above hardcode those paths.

## No ctest target — the other honest gap

`CMakeLists.txt` has no `enable_testing()` and no `add_test()`. The native code is
tested exclusively through the C# suite: CI builds the library, asserts it reached the
test output, and `dotnet test` exercises the `LibraryImport` paths (including the
`helios_abi_version` startup check against `NativeMethods.ExpectedAbiVersion` — see
the native `README.md`). Consequences:

- a `testPresets` block would have nothing to run; do not add one before a ctest
  target exists;
- pure-native regressions (e.g. numeric drift under `-ffast-math`) surface only
  through managed assertions. If native-only tests become worth having, that is
  `enable_testing()` + a test executable + a ctest step in `dotnet-build.yml` —
  one PR, all three together.

## Dependencies: vcpkg manifest mode, and why the count is zero

There is no `vcpkg.json` anywhere in the repo and the native project has ZERO external
dependencies — by design, not neglect. The spoke rule (SKILL.md: the C++ spoke never
opens sockets to LLM providers, never reads `config/aihub.json`, and is called only by
the C# orchestrator) gates out the usual dependency magnets — HTTP clients, JSON
parsers, logging frameworks all belong to C#. The standard library covers the actual
workload (`<memory_resource>`, `<immintrin.h>`, plain math).

If a real need ever passes that filter (say, a SIMD/linear-algebra library), use vcpkg
**manifest mode** — declarative, per-project, no global state (vcpkg docs;
`scripts/buildsystems/vcpkg.cmake`):

- a `vcpkg.json` next to `CMakeLists.txt` listing `"dependencies"`, pinned via a
  `"builtin-baseline"` commit;
- integration by configuring with
  `-DCMAKE_TOOLCHAIN_FILE=<vcpkg-root>/scripts/buildsystems/vcpkg.cmake`, which runs
  `vcpkg install` against the manifest at configure time;
- with preset schema v2 the toolchain is set in `cacheVariables`
  (`"CMAKE_TOOLCHAIN_FILE": "..."`); the dedicated `toolchainFile` preset field is a
  v3 (CMake 3.21) feature.

Cost to weigh before the FIRST dependency: both build scripts need the toolchain flag
and `dotnet-build.yml` needs vcpkg bootstrapped on the runner. That CI cost is part of
the decision, not a follow-up.
