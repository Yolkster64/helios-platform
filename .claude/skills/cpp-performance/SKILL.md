---
name: cpp-performance
description: C++ for performance-critical HELIOS components — memory/CPU/GPU optimization, Windows kernel-adjacent tooling (ETW, IOCP), security hardening, and the flat C ABI boundary into the C# orchestrator. Use when writing, reviewing, or tuning native code in the HELIOS platform.
---

Hub-and-spoke rule: C++ is a spoke — it ships as a native DLL behind a flat C ABI (or a C++/WinRT component for WinUI 3) consumed ONLY by the C# orchestrator; it never calls F#, Python, or external services directly.

## Memory optimization

Arena/pool allocation with `std::pmr` — allocate a slab once, sub-allocate cheaply, tear down in O(1):

```cpp
#include <memory_resource>

std::pmr::monotonic_buffer_resource arena{64 * 1024};   // frame/request lifetime
std::pmr::unsynchronized_pool_resource pool{&arena};    // recycles fixed-size blocks
std::pmr::vector<Sample> samples{&pool};                // no per-element heap traffic
// ... use samples ...
// arena destructor releases everything; never free elements individually
```

Cache-line alignment and false-sharing avoidance — per-thread hot state must not share a 64-byte line:

```cpp
struct alignas(std::hardware_destructive_interference_size) PerThreadCounter {
    std::atomic<uint64_t> value{0};
};
static_assert(alignof(PerThreadCounter) >= 64);
PerThreadCounter counters[kMaxThreads];  // one line each; no cross-core ping-pong
```

Prefer SoA over AoS in hot loops (`struct Positions { std::vector<float> x, y, z; }`) so the prefetcher streams only the fields you touch. Reserve vectors up front; measure with VTune/WPA before restructuring.

## CPU optimization

AVX2 intrinsics for the inner kernel; keep a scalar fallback and dispatch at runtime via `__cpuidex`:

```cpp
#include <immintrin.h>
float dot_avx2(const float* a, const float* b, size_t n) {
    __m256 acc = _mm256_setzero_ps();
    size_t i = 0;
    for (; i + 8 <= n; i += 8)
        acc = _mm256_fmadd_ps(_mm256_loadu_ps(a + i), _mm256_loadu_ps(b + i), acc);
    alignas(32) float lanes[8];
    _mm256_store_ps(lanes, acc);
    float sum = lanes[0]+lanes[1]+lanes[2]+lanes[3]+lanes[4]+lanes[5]+lanes[6]+lanes[7];
    for (; i < n; ++i) sum += a[i] * b[i];
    return sum;
}
```

Direction of travel: `std::simd` (standardized for C++26, available today as `std::experimental::simd`) — write new wide code against it where the toolchain allows, keep intrinsics for FMA-critical kernels.

Branch elimination: convert unpredictable branches to arithmetic/masks (`x = cond ? a : b` compiles to `cmov`; `_mm256_blendv_ps` for SIMD lanes). Annotate genuinely skewed branches only:

```cpp
if (buffer_full) [[unlikely]] { flush(); }
```

PGO + LTO beat hand-tuning for layout: train on a representative HELIOS workload, not unit tests. `[[likely]]/[[unlikely]]` lose to real profile data — prefer PGO when you can run the training pass.

## GPU and rendering

- DirectX 12 basics: explicit command lists/allocators, fences for CPU-GPU sync, upload heaps for staging. You own residency and hazards — budget time for it.
- Win2D handles 2D drawing for the WinUI 3 shell; drop to D3D12 interop (`ICanvasDevice` shares the underlying D3D device) only for custom effects Win2D cannot express.
- Compute shaders (HLSL, `Dispatch`) pay off for wide data-parallel work: image transforms, large reductions, embeddings math on >~1M elements.
- Stay on CPU when: data < a few MB (PCIe copy dominates), the workload is branchy/pointer-chasing, or latency budget is sub-millisecond. Measure the copy both ways before porting.

## Windows kernel-adjacent concerns

- ETW via TraceLogging — near-zero cost when no session listens; the C# hub correlates with EventSource providers:

```cpp
TRACELOGGING_DEFINE_PROVIDER(g_provider, "Helios.Native",
    (0x6f2ab6b1, 0x1234, 0x4cde, 0x9a, 0xbc, 0xde, 0xf0, 0x12, 0x34, 0x56, 0x78));
TraceLoggingWrite(g_provider, "ScanComplete", TraceLoggingUInt64(files, "FileCount"));
```

- Minifilter drivers: do NOT write one for HELIOS features that ETW, `ReadDirectoryChangesW`, or USN journals can cover. Kernel code means WHQL signing, bluescreen blast radius, and Patch-Tuesday breakage. If truly required, it is a separate signed driver project, not part of this spoke.
- Async I/O at scale: IOCP (`CreateIoCompletionPort` + `GetQueuedCompletionStatusEx`), one completion thread per core. If C# can own the I/O instead, let it — .NET's thread pool is already IOCP-backed.

## Security hardening

Non-negotiable release flags: `/GS` (stack cookies), `/guard:cf` (CFG), `/CETCOMPAT` (CET shadow stacks), `/DYNAMICBASE /HIGHENTROPYVA` (ASLR), `/SDL`. Verify with `dumpbin /headers /loadconfig`.

CI: build a `/fsanitize=address` configuration and run the native test suite under it every PR; ASan on MSVC is supported and catches heap/stack overflows UB reviews miss.

Bounds discipline: pass `std::span<T>` instead of pointer+length internally; define `_MSVC_STL_HARDENING=1` in debug/CI builds so STL indexing faults instead of corrupting.

## Interop boundary (STRICT)

Expose a flat C ABI only — no C++ types, exceptions, or STL across the boundary; return error codes, never throw:

```cpp
extern "C" __declspec(dllexport) int32_t helios_scan(
    const wchar_t* root, ScanResult* out) noexcept;   // 0 = OK, else HeliosError
```

Consumed from C# via source-generated `LibraryImport` — not legacy `DllImport` (repo is net8.0; `LibraryImport` is the standard there and forward through .NET 10 LTS):

```csharp
[LibraryImport("Helios.Native.dll", StringMarshalling = StringMarshalling.Utf16)]
internal static partial int HeliosScan(string root, out ScanResult result);
```

For UI-facing components, ship a C++/WinRT runtime class instead and reference the `.winmd` from the WinUI 3 project. Either way the C# orchestrator is the sole caller: C++ never P/Invokes back into other spokes, never opens sockets to LLM providers, never reads `config/aihub.json`.

## Which LLM to use (via helios-ai / aihub.json)

| Task | Provider | Why |
|---|---|---|
| SIMD/intrinsics, memory layout, lifetime & UB analysis | anthropic (Claude) | Deep reasoning over subtle UB, aliasing, ordering |
| Interop boilerplate: bindings, marshalling structs, CMake glue | openai+codex | High-volume mechanical codegen |
| Inline loop tweaks, small refactors in-editor | copilot | Inline completion |
| Perf analysis of proprietary traces/dumps | azure-foundry | Enterprise data stays in tenant |
| Offline experimentation | ollama | No network |

## Build guidance

MSVC release: `/O2 /GL /Qpar /arch:AVX2 /fp:fast /EHsc /GS /guard:cf /sdl` with link `/LTCG /CETCOMPAT /DYNAMICBASE /HIGHENTROPYVA`. PGO: link `/GENPROFILE`, run the training workload, relink `/USEPROFILE`.

clang-cl alternative (drop-in for MSVC command lines): `clang-cl /O2 -mavx2 -flto=thin /guard:cf`, link with `lld-link`. Use it to cross-check codegen and for better sanitizer diagnostics; keep MSVC as the shipping compiler unless benchmarks say otherwise.
