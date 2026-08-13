Versions and API claims mirror the cited repo files; update this file in the same PR that changes them.

# Rendering & GPU (D3D12 / Win2D) for the HELIOS native spoke

Scope: the C++ rendering path behind the WinUI 3 shell. Today `src/ai/HELIOS.AIHub.Native/` is CPU-only
(similarity, token math, MLP — see `helios_aihub_native.h`); the GPU path is design intent from
`docs/architecture/GUI_THEME_ANALYSIS.md` ("Interop boundary") and `SKILL.md` ("GPU and rendering").
Every D3D12/DXGI/PIX/DXC API named here is verified against Microsoft Learn (URLs inline); none of it
exists in the repo yet — see "Not in the repo (candidates)".

## The rule: GPU work stays in the native spoke, orchestration stays in C#

`helios_aihub_native.h` states the contract: the library "exposes a C ABI that only the C# orchestrator
calls (via LibraryImport). It never calls back into managed code, never performs I/O, and never talks to
another spoke." Apply the same split to rendering:

| Stays in C# (hub / shell)                                        | Stays in the native spoke (C++)                          |
|------------------------------------------------------------------|----------------------------------------------------------|
| Decide *when* to redraw; own the `SwapChainPanel` XAML element    | Build/execute command lists; own device, queue, fences    |
| Fetch provider metrics via `HELIOS.AIHub` APIs; shape them into a flat sample buffer | Turn caller-owned sample buffers into vertices/draw calls |
| Read `config/aihub.json`, providers, routing (native never reads it — header rule) | Descriptor heaps, root signatures, barriers, residency    |
| Declare the boundary in `src/ai/HELIOS.AIHub/Native/NativeMethods.cs` (`LibraryImport`, `CallConvCdecl`) | Export `extern "C"` entry points returning `helios_status` |

New rendering exports must follow the existing ABI shape (status codes, caller-owned memory, `noexcept`
boundary, bump `helios_abi_version()` / `NativeMethods.ExpectedAbiVersion` together — header + README):

```cpp
/* Pattern only — not an existing export. Mirrors helios_aihub_native.h. */
HELIOS_API helios_status helios_chart_render(
    const float* samples, size_t count, uint64_t frame_id);  /* C# decides when; C++ decides how */
```

## C++/WinRT vs flat C ABI at the boundary

`SKILL.md` ("Interop boundary (STRICT)"): default is a flat C ABI consumed via `LibraryImport`; the
alternative "for UI-facing components" is a C++/WinRT runtime class referenced as a `.winmd`.
`GUI_THEME_ANALYSIS.md` picks the second for rendering: "a C++/WinRT component renders to a
`SwapChainPanel` — the C++ spoke rule applies (flat ABI, no spoke-to-spoke calls)."

| Choose            | When                                                                | Rules that still apply |
|-------------------|---------------------------------------------------------------------|------------------------|
| Flat C ABI (.dll) | Pure computation over caller-owned buffers (everything shipped today) | No C++ types/exceptions across; status codes; ABI version check |
| C++/WinRT (.winmd)| The component must receive a `SwapChainPanel`/WinRT objects from XAML | Only the C# orchestrator/shell consumes it; no I/O, no spoke-to-spoke, no `config/aihub.json` |

Pitfall: do not let a C++/WinRT rendering class become a second orchestrator — it may hold the D3D device
and swap chain, but provider data still arrives from C# as plain buffers, exactly like the C-ABI path.

## Win2D vs raw D3D12 — decide before writing any device code

| Situation                                                    | Use | Source |
|--------------------------------------------------------------|-----|--------|
| Sparklines, cost charts, 2D dashboards                       | Win2D `CanvasControl` + `Draw` handler, in C# | `.claude/skills/winui3-shell/SKILL.md` |
| Large scrollable surfaces                                     | `CanvasVirtualControl` | same |
| Custom effects Win2D cannot express                          | D3D interop off Win2D's device (`ICanvasDevice`) | `SKILL.md` "GPU and rendering" |
| Profiled CPU-bound scene prep; thousands of animated elements | C++/WinRT spoke rendering to `SwapChainPanel` (raw D3D12) | `GUI_THEME_ANALYSIS.md`; winui3-shell SKILL.md |
| Wide data-parallel math (>~1M elements)                      | Compute shader (HLSL `Dispatch`) in the spoke | `SKILL.md` |
| Data < a few MB, branchy, or sub-ms latency budget           | Stay on CPU; measure the copy both ways | `SKILL.md` |

Pitfall: Win2D's engine is Direct2D-family; putting D2D content onto a D3D12 swap chain goes through
D3D11On12 wrapped resources (`D3D11On12CreateDevice`, `CreateWrappedResource`, Acquire/Release around D2D
work, then `Flush`) — not a free "same device" share. Budget for that seam or keep the two paths on
separate panels. (learn.microsoft.com/windows/win32/direct3d12/d2d-using-d3d11on12)

## D3D12 device → queue → swap chain on a SwapChainPanel (minimal path)

1. Debug builds only: `D3D12GetDebugInterface` → `ID3D12Debug::EnableDebugLayer()` — before device
   creation; enabling after creation removes the device (learn.microsoft.com/windows/win32/api/d3d12sdklayers/nf-d3d12sdklayers-id3d12debug-enabledebuglayer).
2. `CreateDXGIFactory1` → `D3D12CreateDevice` (all D3D12 drivers are feature level 11_0+;
   learn.microsoft.com/windows/win32/direct3d12/hardware-feature-levels).
3. `D3D12_COMMAND_QUEUE_DESC{ Type = D3D12_COMMAND_LIST_TYPE_DIRECT }` → `CreateCommandQueue`.
4. `IDXGIFactory2::CreateSwapChainForComposition` — for D3D12 pass the **direct command queue** as
   `pDevice`, not the device. The desc must use `DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL` (flip model only),
   `DXGI_SCALING_STRETCH`, `BufferCount >= 2`, `SampleDesc.Count = 1` — flip model does not do MSAA;
   resolve first (learn.microsoft.com/windows/win32/api/dxgi1_2/nf-dxgi1_2-idxgifactory2-createswapchainforcomposition).
5. Get `ISwapChainPanelNative` from the panel (`panel.as<ISwapChainPanelNative>()` in C++/WinRT) and call
   `SetSwapChain` on the UI thread (learn.microsoft.com/windows/uwp/gaming/directx-and-xaml-interop).
6. Index back buffers with `IDXGISwapChain3::GetCurrentBackBufferIndex`
   (learn.microsoft.com/windows/win32/direct3d12/creating-a-basic-direct3d-12-component).

Pitfalls: after `ResizeBuffers`, call `SetSwapChain` again on the same swap chain; handle
`CompositionScaleChanged` and re-render at the new `CompositionScaleX/Y` or XAML scales your pixels
(SwapChainPanel class remarks, learn.microsoft.com/windows/windows-app-sdk/api/winrt/microsoft.ui.xaml.controls.swapchainpanel).

## Descriptor heaps + root signature (minimal path)

1. `D3D12_DESCRIPTOR_HEAP_DESC` → `ID3D12Device::CreateDescriptorHeap`. RTV heaps are CPU-only;
   CBV/SRV/UAV heaps that shaders read must be shader-visible.
2. Walk heaps with `GetCPUDescriptorHandleForHeapStart` / `GetGPUDescriptorHandleForHeapStart` plus
   `GetDescriptorHandleIncrementSize(type)`. Never hardcode the increment and never dereference a handle —
   both are undefined behavior (learn.microsoft.com/windows/win32/direct3d12/creating-descriptor-heaps).
3. One `CreateRenderTargetView` per swap-chain buffer (`IDXGISwapChain::GetBuffer`).
4. Root signature: fill `D3D12_VERSIONED_ROOT_SIGNATURE_DESC` → `D3D12SerializeVersionedRootSignature` →
   `ID3D12Device::CreateRootSignature`; or author it in HLSL, where the compiled shader already embeds the
   serialized blob (learn.microsoft.com/windows/win32/direct3d12/creating-a-root-signature).
5. Bind at draw time with `SetGraphicsRootDescriptorTable` / `SetComputeRootDescriptorTable`.

## Fence-based frame synchronization

One fence per queue, one monotonically increasing value per frame. GPU side:
`ID3D12CommandQueue::Signal(fence, value)` completes after all prior queue work; CPU side:
`ID3D12Fence::Signal` is immediate. Wait with `GetCompletedValue()` (poll) or
`SetEventOnCompletion(value, event)` + `WaitForSingleObject` (block); a queue can also
`ID3D12CommandQueue::Wait` on another queue's fence
(learn.microsoft.com/windows/win32/direct3d12/user-mode-heap-synchronization).

Pitfalls (all from the same Learn page): keep each fence on a single timeline — two signalers racing one
fence produces waits that may never satisfy; never rewind a fence value. Hold every per-frame resource
the GPU may still read (command allocators, upload buffers, GPU descriptor handles in flight) until the
frame's fence value has completed — GPU handles must outlive the command lists that reference them.

## Debug layers, DRED, PIX markers

- Debug layer: step 1 above; debug/CI builds only, never shipped.
- DRED (after-the-fact GPU fault triage): before device creation, `D3D12GetDebugInterface` →
  `ID3D12DeviceRemovedExtendedDataSettings::SetAutoBreadcrumbsEnablement/SetPageFaultEnablement`
  (`D3D12_DRED_ENABLEMENT_FORCED_ON`); after `DXGI_ERROR_DEVICE_REMOVED`, QueryInterface the device for
  `ID3D12DeviceRemovedExtendedData` (learn.microsoft.com/windows/win32/direct3d12/use-dred).
- PIX: reference the WinPixEventRuntime NuGet package, include `pix3.h`, wrap regions with
  `PIXBeginEvent`/`PIXEndEvent` (or `PIXScopedEvent`) on command lists and queues. Do not call
  `ID3D12GraphicsCommandList::BeginEvent`/`EndEvent` directly — they are internal to the PIX runtime.
  Begin/End must pair on the same thread
  (learn.microsoft.com/windows/win32/api/d3d12/nf-d3d12-id3d12graphicscommandlist-beginevent).

## Shader compilation (DXC) in the build

Shader Model 6 requires `dxc.exe`; `fxc.exe` stops at SM 5.1. Visual Studio invokes DXC automatically when
SM6 is selected in the HLSL property page (learn.microsoft.com/windows/win32/direct3dhlsl/dx-graphics-hlsl-part1).
Target profiles: `vs_6_0`/`ps_6_0`/`cs_6_0`/`lib_6_0` (learn.microsoft.com/windows/win32/direct3dhlsl/dx-graphics-hlsl-models).
For this repo's CMake build (`src/ai/HELIOS.AIHub.Native/CMakeLists.txt` pattern), add a per-`.hlsl`
`add_custom_command` that runs `dxc.exe` to a `.cso` the C++ embeds or loads; keep flag strings against the
"Using dxc.exe and dxcompiler.dll" wiki that the Learn page links — its exact flag syntax is not mirrored
on Learn, so do not trust memory for it. For in-process compilation use `IDxcCompiler3::Compile`
(`IDxcCompiler`/`IDxcCompiler2` are deprecated; learn.microsoft.com/windows/win32/api/dxcapi/nf-dxcapi-idxccompiler3-compile).
Prefer build-time compilation: it keeps the spoke's "no I/O at runtime" contract intact.

## Not in the repo (candidates)

| Candidate | What it is | Verified via |
|-----------|-----------|--------------|
| D3D12 / DXGI (`d3d12.h`, `dxgi1_2.h`+, `d3d12.lib`/`dxgi.lib`) | OS graphics API; nothing links it today (`CMakeLists.txt` links no libraries) | Microsoft Learn pages cited above |
| WinPixEventRuntime (NuGet) | PIX marker runtime (`pix3.h`) | Learn BeginEvent/EndEvent remarks |
| DirectX Shader Compiler (`dxc.exe`, `dxcompiler.dll`, `dxcapi.h`) | SM6 HLSL compiler | Learn compiling-shaders + dxcapi pages |
| D3D11On12 (`d3d11on12.h`) | Bridge for D2D/Win2D-family content onto a D3D12 queue | learn.microsoft.com/windows/win32/direct3d12/direct3d-11-on-12 |
| Win2D (`CanvasControl`, `ICanvasDevice`) | C# 2D layer; named in repo skills but not a package any project references yet | `SKILL.md`, `winui3-shell/SKILL.md`, `GUI_THEME_ANALYSIS.md` |
