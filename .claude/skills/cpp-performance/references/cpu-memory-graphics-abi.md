# CPU, memory, graphics seams, and the flat C ABI — as shipped

*Versions and API claims mirror the cited repo files; update this file in the same PR
that changes them.* Companions: `build-and-packaging.md` (CMake, scripts, CI assert),
`rendering-gpu.md` (D3D12 / Win2D device path), `particle-systems.md` (SoA / AVX2 loops
and the recovered shaders). This file covers what those do not: the memory and CPU
discipline of the *shipped* kernels, the ABI contract end to end, the determinism and
numerical rules, and the hot-path exemplars. System view:
`docs/architecture/AIHUB_LANGUAGE_ROLES.md`.

The one native project is `src/ai/HELIOS.AIHub.Native` (one translation unit,
`helios_aihub_native.cpp`; header `helios_aihub_native.h`; managed side
`src/ai/HELIOS.AIHub/Native/NativeMethods.cs`).

## Pattern 1 — caller-owned, contiguous, row-major memory

Every export computes over memory the caller owns; nothing allocates, frees, retains a
pointer past return, or throws (`helios_aihub_native.h:12-14`). Multi-row inputs are
contiguous row-major buffers with explicit `count`/`dim` (`:53-59`, `:115-119`). The
MLP weight buffer is one flat `float[]` laid out `W1[hidden][dim], b1[hidden],
W2[hidden], b2` (`:89-90`), sized by `helios_mlp_weight_count` = `hidden * (dim + 2) + 1`
(`helios_aihub_native.cpp:73-82`). For the shipped shape (`featureDim = 6`,
`HiddenUnits = 16`) that is 129 floats (`LearnerFusion.fs:33`,
`NeuralRoutingLearner.cs:21`).

Scratch stays on the stack: `HELIOS_MLP_MAX_HIDDEN = 256` caps `double hidden_act[]`
so the no-allocation contract holds (`helios_aihub_native.h:98-99`,
`helios_aihub_native.cpp:333,405`). Shape validation rejects zero dims and hidden
units above the cap before any buffer is touched (`helios_aihub_native.cpp:84-89`).

Trap: the managed side must size buffers exactly — `weight_count != layout.count()` is
`HELIOS_ERR_DIMENSION_MISMATCH`, not a silent overrun (`helios_aihub_native.cpp:282-284`).

## Pattern 2 — CPU: auto-vectorizable loops first, intrinsics only on a profile

The style rule at the top of the translation unit: unit-stride loops, no aliasing between
input and output, no early exits, so MSVC, clang-cl, and gcc all vectorize the same
source; reach for intrinsics only when a profile says the loop is the bottleneck
(`helios_aihub_native.cpp:5-8`). Release builds add `/O2 /GL /Qpar /fp:fast` on MSVC and
`-O3 -ffast-math` elsewhere (`CMakeLists.txt:21,29`) — fine for scoring, not for code
that needs strict IEEE semantics (`build-and-packaging.md` "CMakeLists.txt").

Exemplars:

- Cosine similarity accumulates dot and both norms in `double` because float
  accumulation over thousands of dimensions loses precision that drives dedup decisions
  (`helios_aihub_native.cpp:129-140`).
- The similarity matrix computes only the upper triangle and mirrors it — halving an
  `O(count² · dim)` kernel (`helios_aihub_native.cpp:156-169`).
- The token estimator is a single pass over bytes with two regimes: ASCII characters
  average `kBytesPerToken = 3.85` per token, each multi-byte character counts as one
  (`helios_aihub_native.cpp:19-22,187-208`). Dividing a mixed count by 3.85 would
  undercount CJK prompts about 4× and route them into windows they cannot fit.
- `helios_fit_prefix_bytes` walks with the same weights and backs off to a UTF-8
  boundary so a truncation never splits a sequence (`helios_aihub_native.cpp:28-38,235-253`).

Hot-path budget of the learner: `helios_mlp_train` is `O(epochs · samples · hidden ·
dim)`; the hub calls it with 300 epochs, 16 hidden units, 6 features, and at most
`historyWindow` (200) samples per task type (`NeuralRoutingLearner.cs:21-23`,
`config/aihub.json:224`) — and caches weights while history is unchanged
(`NeuralRoutingLearner.cs:117-131`). Wide SIMD lanes for these shapes are a
measurement question, not an assumption; `particle-systems.md` has the AVX2 loop shape
for when a profile justifies it.

## Pattern 3 — numerical hygiene the learner encodes

- Stable sigmoid branches on sign so `exp` never overflows (`helios_aihub_native.cpp:62-69`).
- Probabilities are clamped to `[1e-12, 1 - 1e-12]` before `log` (`:345-347`).
- Sigmoid + cross-entropy collapses the output delta to `p - t` (`:351-352`).
- `W2[h]` is read *before* it is updated because the hidden delta must use the value that
  produced the forward pass (`:354-360`).
- No L2 on biases — shrinking them only shifts the decision surface (`:370-372`).
- Targets are clamped to `[0,1]`; soft targets are fine because cross-entropy generalizes
  (`:340-341`; `helios_aihub_native.h:94-95`).
- Xavier-uniform init keeps early activations in tanh's linear region (`:288-292`).

One step of this arithmetic on a two-unit toy network, with the numbers, is worked in
`.claude/skills/aihub-unity/references/combo-calculus.md`.

## Pattern 4 — determinism is part of the ABI

Same binary, same seed, same sample order ⇒ bit-identical weights
(`helios_aihub_native.h:92-95`). The PRNG is xorshift64\* (deliberately not
`std::mt19937`, whose stream is not guaranteed bit-identical across standard-library
implementations); seed 0 is remapped to a non-zero constant so every seed is usable
(`helios_aihub_native.cpp:42-54`). Samples are consumed in caller order with no internal
shuffle, so replaying a learning store reproduces the model. The managed side fixes the
seed at 42 (`NeuralRoutingLearner.cs:26-27`) and the C# tests assert identical history
yields identical routing (`tests/HELIOS.AIHub.Tests/LearnerFusionTests.cs:195-196`) and
that the MLP learns XOR where a linear scorer cannot
(`tests/HELIOS.AIHub.Tests/NativeLearnerTests.cs:66`).

## Pattern 5 — the flat C ABI, end to end

| Layer | Contract | Where |
|---|---|---|
| Exports | `extern "C"`, `HELIOS_API` visibility, every function returns `helios_status` (`HELIOS_OK = 0`, negative errors) | `helios_aihub_native.h:23-43` |
| Version handshake | `helios_abi_version()` returns `kAbiVersion = 2`; the managed side compares against `ExpectedAbiVersion = 2` once per process | `helios_aihub_native.cpp:17,116-118`; `NativeMethods.cs:16-21`; `NativeGate.cs:9-35` |
| Managed declarations | `LibraryImport("helios_aihub_native")`, `UnmanagedCallConv(CallConvCdecl)`, `ReadOnlySpan<float>` in, `Span<float>` out, `nuint` lengths, `out` scalars | `NativeMethods.cs:12-71` |
| Build glue | `AllowUnsafeBlocks` only for the generated stubs; the csproj copies `build/libhelios_aihub_native.so`, the `.dylib`, or `build/Release/helios_aihub_native.dll` beside AIHub, CLI, and test outputs when present | `HELIOS.AIHub.csproj:9-11,31-47` |
| CI | Native library built before `dotnet build`; the test output must contain the `.so` | `.github/workflows/dotnet-build.yml:121,142` |
| Degradation | Absent or stale binary ⇒ managed token heuristic, unmarked compare results, F# linear policy | `AIHub.cs:436-477`; `AIHub.cs:516-518`; `NeuralRoutingLearner.cs:47-51,105-114` |

Adding an export is one change in four places: the header (doc block plus signature),
the `.cpp`, `NativeMethods.cs`, and the ABI bump on both sides — plus a C# test, because
there is no ctest target (`build-and-packaging.md` "No ctest target").

Traps the repo already fixed: `Lazy<bool>` caches a thrown exception forever, so
`BadImageFormatException` (wrong-architecture binary) is caught inside the gate
(`NativeGate.cs:26-31`); `DllNotFoundException` and `EntryPointNotFoundException` mark
the neural path unavailable for the process rather than failing a route
(`NeuralRoutingLearner.cs:105-114`).

## Pattern 6 — security flags are not optional

MSVC: `/W4 /permissive- /GS /guard:cf`, link `/guard:cf /DYNAMICBASE /NXCOMPAT /CETCOMPAT`
(`CMakeLists.txt:19-24`). GCC/Clang: `-fstack-protector-strong -D_FORTIFY_SOURCE=2`,
Release link `-Wl,-z,relro,-z,now` except on Apple (`:26-35`). `-DHELIOS_SANITIZE=ON`
builds ASan+UBSan for the classes of bug the `cpp-perf-reviewer` agent hunts by hand
(`:38-44`). Hidden visibility makes the ABI surface exactly the header (`:8-10`).

## Pattern 7 — graphics seams (design intent, verified elsewhere)

Nothing under `src/ai/HELIOS.AIHub.Native` touches a GPU today; the rendering path is
intent from `docs/architecture/GUI_THEME_ANALYSIS.md` "Interop boundary" and
`DYNAMIC_BACKGROUND_ENGINE.md`. The seams, in order of preference:

1. **`Microsoft.UI.Composition`** for blade, aperture, rings, particles, glow, and
   transitions — the ADR-0010 default; managed, no native code.
2. **Win2D `CanvasControl` / `CanvasAnimatedControl`** for 2D drawing the shell owns
   (`.claude/skills/winui3-shell/references/rendering-interop.md` "Win2D controls").
3. **C++/WinRT component rendering into a `SwapChainPanel`**, or raw D3D12 through
   `ICanvasDevice` interop, only when profiling shows CPU-bound scene prep or an effect
   Win2D cannot express (`rendering-gpu.md` "Win2D vs raw D3D12"). The component holds
   the device, queue, and fences; provider data still arrives from C# as flat buffers;
   the shell consumes the runtime class through the hub's interop layer and never loads
   a spoke DLL itself (`.claude/skills/winui3-shell/SKILL.md:6`).

Rules that carry over unchanged from the CPU kernels: status codes, caller-owned
memory, no exceptions across the boundary, an ABI bump per export, and no reads of
`config/aihub.json` (SKILL.md "Interop boundary (STRICT)").

## When a native path is justified

| Justified | Not justified |
|---|---|
| A profile shows a tight numeric loop over large caller-owned buffers on every request (the header's own criterion, `helios_aihub_native.h:9-11`) | Anything with I/O, JSON, HTTP, or configuration — those belong to C# (`build-and-packaging.md` "Dependencies") |
| The computation is pure and deterministic, so a C# test can pin it | Work that a managed fallback cannot reproduce — the hub must degrade when the binary is absent |
| Data measured in MB and branch-free; sub-millisecond latency budget on CPU (SKILL.md "GPU and rendering") | Pointer-chasing or branchy logic, or data small enough that the P/Invoke transition dominates |

## When to route this work to which model or provider

Hub chains are `config/aihub.json:97-215`; the native fleet pool's chain is `anthropic`,
`openai`, `codex` and it is local-only because burst runners lack the Windows SDK,
MSVC, and a GPU (`config/fleet/fleet-topology.json:84-102`).

| Native work | Task type → chain | Why |
|---|---|---|
| Lifetime, aliasing, UB, and ordering analysis of a kernel | `code_review` or `security_analysis` → `anthropic`, `anthropic-foundry`, … | Deep reasoning over subtle semantics (SKILL.md "Which LLM") |
| Marshalling structs, `LibraryImport` declarations, CMake glue | `code_generation` → `codex`, `openai-codex`, `openai`, `azure-openai`, `anthropic` | Mechanical from the header; reconcile against Pattern 5 |
| A failing native test or an ABI mismatch | `debugging` → `claude-cli`, `codex`, `openai-codex`, `openai` | Agentic CLIs can run the build and read the sanitizer output |
| Deciding managed vs native for a new hot path | `architecture_design` → `anthropic`, `anthropic-foundry`, `openai`; `helios-ai compare` for the second opinion | The decision table above needs a profile and a tradeoff argument |
| Proprietary traces or dumps | `enterprise_data` → `azure-foundry`, `anthropic-foundry`, `azure-openai` | Data stays inside the tenant boundary |

Language-qualified keys landed in PR #248 (`docs/architecture/ROUTING_LANGUAGE_DIMENSION.md`).
The shipped C++ chain is `code_generation:cpp` → `codex`, `openai-codex`, `anthropic`,
`anthropic-foundry`, `openai` (`config/aihub.json:105-111`), selected by
`helios-ai route code_generation "<prompt>" --language cpp` (`c++`, `cxx` and `cc`
normalize to `cpp`: `TaskTypeRoutingStrategy.NormalizeLanguage`,
`src/ai/HELIOS.AIHub/Routing/TaskTypeRoutingStrategy.cs:67-80`). `code_review:cpp` is not
configured, so a review with `--language cpp` runs the bare `code_review` chain above and
records `language: cpp` on the outcome, which scopes adaptive learning to
`(code_review, cpp)` (`ChainReorderEngine.ForLanguage`,
`src/ai/HELIOS.AIHub/Learning/ChainReorderEngine.cs:49-62`). `cpp-perf-reviewer` stays the
review gate for this column.
