Versions and API claims mirror the cited repo files; update this file in the same PR that changes them.

# Particle systems — optimization pack for the dynamic background engine

Scope: the CPU and GPU particle lanes behind
`docs/architecture/DYNAMIC_BACKGROUND_ENGINE.md` (tiers, budgets, and the ABI shape
live there; this file is the how). The seam rules are NOT restated here — C#/C++
split, device/queue/swap-chain wiring, fences, and DXC build integration are
`references/rendering-gpu.md`; interop strictness is `SKILL.md` ("Interop boundary
(STRICT)"). Nothing in this file exists in the repo yet except the three recovered
shader fragments analyzed below; everything else is labeled in "Not in the repo".

## What the recovered shaders actually are (ground truth)

The design seeds are `docs/ui-xenoblade/Shaders/{GlowShader,ParticleShader,ScanLineShader}.hlsl`
(recovered from the stray bare git store — `docs/architecture/GUI_UPGRADE_PLAN.md` §1).
Read honestly, they are pixel-shader fragments, not a particle system:

- **`ParticleShader.hlsl`** declares a `Particle` struct (position, age, velocity,
  lifetime, color, size) and a cbuffer with `viewProjection`, `timeElapsed`,
  `gravity`, `damping` — and then never uses any of it: the only entry point is a
  pixel shader that samples a texture, fades by an `age` interpolant arriving as
  `TEXCOORD1`, and lerps 60% toward a hardcoded cyan `float3(0.0, 0.83, 1.0)`
  (≈ `#00D4FF`, the WPF-era accent that `GUI_UPGRADE_PLAN.md` §2 retired for
  `#00D9FF`). The simulation and vertex stage were never written; the design implies
  CPU-built billboard quads carrying per-vertex age.
- **`GlowShader.hlsl`** is a single-tap radial-gradient + threshold-bloom composite
  centered at uv (0.5, 0.5). Its cbuffer declares `blurRadius`, but no blur kernel
  exists — one sample, no neighborhood reads. Its "bloom" threshold compares
  `length(baseColor.rgb)` (max ≈ 1.73 for white), not a luma weighting.
- **`ScanLineShader.hlsl`** draws lines via
  `abs(sin(uv.y * lineSpacing + scanSpeed)) < lineHeight`. Despite the comments,
  `lineSpacing`/`lineHeight` operate in normalized-UV/sine-threshold space, not
  pixels, and `scanSpeed` is a static phase offset — there is no time input, so
  animation requires the CPU rewriting the constant every frame. Cyan is hardcoded
  (`#00D4FF` again).

What a D3D12 port changes: the sim moves into a compute shader over GPU-resident
structured buffers (the `Particle` struct finally gets executed); per-vertex age
streams are replaced by the sim buffer + instanced/indirect draw; hardcoded colors
become parameter-block palette entries resolved from `Tokens.xaml`; `GlowShader`'s
blur becomes a real separable two-pass kernel (or the parameter is dropped);
`ScanLineShader` gains a time constant. Ports target SM6 via `dxc.exe` at build time
(`rendering-gpu.md`, "Shader compilation").

## CPU lane (Ambient tier and the Full tier's residual CPU work)

### SoA layout

Per `SKILL.md` ("Memory optimization"): hot fields in separate contiguous arrays so
the prefetcher streams only what the loop touches.

```cpp
struct ParticlePool {                       // capacity fixed at tier init
    alignas(32) float* pos_x;  alignas(32) float* pos_y;
    alignas(32) float* vel_x;  alignas(32) float* vel_y;
    alignas(32) float* age;    alignas(32) float* lifetime;
    // cold data (spawn seed, palette index) in separate arrays — not in the hot loop
    uint32_t alive;                         // dense prefix [0, alive) is live
};
```

32-byte alignment matches AVX2 lane width; allocate the slab once from an arena
(`std::pmr::monotonic_buffer_resource`, `SKILL.md`) sized to the tier cap.

### SIMD update loop (AVX2 baseline, scalar fallback)

Same dispatch discipline as `SKILL.md`'s `dot_avx2`: runtime `__cpuidex` check,
scalar tail, FMA for the integration step.

```cpp
// x' = x + v*dt ; v' = v*damping + wind*dt — 8 particles per iteration
__m256 dt8 = _mm256_set1_ps(dt), damp8 = _mm256_set1_ps(damping),
       windx8 = _mm256_set1_ps(wind_x * dt);
for (size_t i = 0; i + 8 <= alive; i += 8) {
    __m256 vx = _mm256_load_ps(vel_x + i);
    vx = _mm256_fmadd_ps(vx, damp8, windx8);          // damping + wind
    _mm256_store_ps(vel_x + i, vx);
    _mm256_store_ps(pos_x + i,
        _mm256_fmadd_ps(vx, dt8, _mm256_load_ps(pos_x + i)));
}
```

**The gather/scatter trap.** AVX2 has `_mm256_i32gather_ps` but *no scatter*
(scatter is AVX-512); gathers cost multiple cycles per element on most
microarchitectures and forfeit the streaming win. Never drive the hot loop through an
index list (alive-list indirection, sorted-by-depth indices). Keep the arrays
*dense* instead — then every load/store is contiguous. If ordering matters for
blending, sort at render-prep time, not in the sim.

### Death and compaction without branches

Per-particle `if (age > lifetime)` inside the SIMD loop is the classic
mispredict-and-serialize mistake. Two working patterns:

- **Swap-with-last**: after the SIMD pass, one scalar sweep moves dead particles out
  by swapping with index `alive-1` and decrementing `alive`. Order is not preserved —
  fine for additive-blended embers/snow.
- **Mask + compaction pass**: build a per-lane death mask with `_mm256_cmp_ps`,
  then compact in a scalar/BMI2 pass. Only worth it when death rates are high
  (rain hitting a kill plane); measure before choosing it over swap-with-last.

Free-lists (index stack of dead slots) suit stable-order pools; dense-prefix
swap-with-last suits SIMD better. Pick one per system, never both.

### Fixed timestep + interpolation

Sim steps at fixed dt (design pick in `DYNAMIC_BACKGROUND_ENGINE.md`); the render
interpolates `lerp(prev, curr, accumulator/dt)`. Clamp the accumulator (e.g. max 5
steps/frame) so a debugger pause or laptop wake doesn't spiral. Frame rate then only
affects smoothness, never trajectories — and the sim stays deterministic for a given
parameter sequence, which is what makes budget regressions bisectable.

### Cache-line awareness

64-byte lines = two AVX2 lanes per line per array. The SoA arrays already give
sequential access; the remaining traps are (a) interleaving hot and cold fields in
one struct — don't; (b) false sharing if the sim is ever threaded — per
`SKILL.md`, per-thread counters get `alignas(std::hardware_destructive_interference_size)`.
Default position: the Ambient-scale sim (≤ ~512 particles) is single-threaded — a few
hundred particles never justify thread coordination; the Full-tier scale runs on GPU,
so CPU threading of particle updates should not exist in this engine at all.

## Memory

- **Pool budgets per tier** (TARGETS from `DYNAMIC_BACKGROUND_ENGINE.md` §4):
  Ambient ≤ 512 particles — six hot float arrays ≈ 12 KB, noise vs the 32 MB tier
  budget, which is really for Win2D surfaces; Full tier sizes GPU buffers at init
  from the parameter caps (tens of thousands of particles × struct size, plus
  double-buffered sim state) and must fit the 128 MB working-set target.
- **No allocations on the sim path.** All pools/scratch allocated at
  `helios_bg_init`, freed at `helios_bg_teardown`; tick/render allocate nothing
  (same contract as `helios_aihub_native.h`: no function allocates, frees, or
  retains a caller pointer past return). `HELIOS_MLP_MAX_HIDDEN`-style fixed caps —
  a compile-time max particle count per tier — keep scratch bounded and honest.
- **Double-buffered parameter blocks across the ABI.** The spoke copies the
  `helios_bg_params` block *during* `helios_bg_tick` and never keeps the pointer
  (header rule). Torn writes are prevented on the C# side: two pinned blocks, the
  UI/logic thread writes the inactive one and flips an index; the tick call always
  passes a fully written block. No locks on the render thread, no `GCHandle`
  churn per frame (pin once at init).

## GPU lane (Full tier)

Device/queue/swap-chain setup, fencing, and DXC integration: `rendering-gpu.md` —
not repeated here. Particle-specific discipline:

- **GPU-resident state.** Sim state lives in `RWStructuredBuffer<Particle>` (the
  recovered struct, finally real); the CPU uploads only spawn requests and the
  per-frame constant block. The CPU never reads particle state back.
- **Dispatch sizing.** `[numthreads(64,1,1)]` or `[numthreads(128,1,1)]` — multiples
  of both 32 (NVIDIA warp) and 64 (AMD wave); dispatch `ceil(capacity/threads)`
  groups. Avoid many tiny dispatches; one sim pass + one emit pass per frame.
- **Alive/dead management on GPU.** Dead-list as a structured buffer used as an
  index stack via atomics (or append/consume buffers); the emit pass pops dead
  slots, the sim pass pushes expired ones. The alive count feeds rendering
  without CPU involvement via **indirect draw** — the sim writes instance/vertex
  counts into an argument buffer consumed by `ExecuteIndirect` (or
  `DrawInstancedIndirect`-style args). This is what deletes the CPU↔GPU sync point.
- **Upload discipline.** Per-frame constants and spawn requests go through a ring of
  upload-heap allocations, each region fenced to its frame (the "hold every
  per-frame resource until the fence completes" rule in `rendering-gpu.md`).
- **Readback discipline: don't.** A per-frame readback stalls the pipeline. The only
  sanctioned readback is the debug overlay's occasional stats query (alive count,
  once a second at most), fenced and double-buffered so it reads last frame's value
  without waiting.
- **The Win2D-vs-D3D12 decision line**: `rendering-gpu.md`'s table decides. For this
  engine specifically: a few hundred CPU-simulated sprites = Ambient tier, Win2D
  (`CanvasAnimatedControl`, optionally `CanvasSpriteBatch`); tens of thousands with
  GPU-resident state, custom compute, indirect draw = Full tier, the native spoke.
  There is no middle renderer — a scale that outgrows Ambient's budget jumps tiers,
  it does not get a hand-rolled hybrid.

## Network: the weather-poll caching contract

The engine's only network input (Open-Meteo, keyless — §3 of the design doc), and it
is never on the sim or render path:

- One background task polls at most **1 request / 15 minutes** (design-doc budget).
- The last good response is cached with its timestamp; on failure serve stale and
  back off exponentially (15 → 30 → 60 min, cap at 6 h). No retry storms.
- The parsed result is published as an immutable snapshot (atomic pointer swap);
  sim/tick reads the snapshot, never awaits, never observes a partial parse.
- No response ever changes tiers or budgets — weather selects *content*
  (rain/snow/wind parameters), the tier logic is local-only.
- Zero network when the tier is Off, when minimized, or on metered connections.

## Not in the repo (candidates)

| Candidate | What it is | Status |
|---|---|---|
| The background spoke itself (`src/gui/HELIOS.Shell.Native/` candidate path) | The D3D12 particle/scene engine this file optimizes | Design only — `DYNAMIC_BACKGROUND_ENGINE.md` |
| D3D12/DXGI, DXC, WinPixEventRuntime, D3D11On12 | Native graphics stack | See `rendering-gpu.md` "Not in the repo" — unchanged |
| Win2D (`CanvasAnimatedControl`, `CanvasSpriteBatch`) | Managed Ambient-tier renderer | Named in repo skills; no project references the package yet (`rendering-interop.md`) |
| Open-Meteo | Keyless weather API for BG3 | External service; not wired anywhere today |
| AVX-512 scatter, `std::simd` | Wider/portable SIMD options | Direction-of-travel notes only; AVX2 + scalar fallback is the baseline per `SKILL.md` |
