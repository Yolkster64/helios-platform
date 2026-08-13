Versions and API claims mirror the cited repo files; update this file in the same PR that changes them.

# Rendering interop (C# shell ↔ native graphics)

This is the seam between the managed WinUI 3 shell (`src/gui/HELIOS.Shell/`) and native rendering. Repo direction: Win2D first, C++/WinRT + SwapChainPanel only when profiling demands it (`docs/architecture/GUI_THEME_ANALYSIS.md` "Interop boundary", `.claude/skills/cpp-performance/SKILL.md` "GPU and rendering"). Platform behavior below is verified against Microsoft Learn (Win2D for WinUI 3, dxinterop, Composition, DXGI pages).

## Win2D controls: pick by redraw pattern

| Control | Backed by | Use for |
|---|---|---|
| CanvasControl | CanvasImageSource | Mostly static content; `Draw` fires only when redraw is needed (sparklines, charts) |
| CanvasVirtualControl | CanvasVirtualImageSource | Content larger than the screen, inside a ScrollViewer |
| CanvasAnimatedControl | CanvasSwapChainPanel + CanvasSwapChain | Continuously changing content; periodic `Draw`, 60/s by default, on a dedicated game-loop thread |

Create expensive resources in the `CreateResources` event, not per-`Draw` — it fires at load and again on device-lost recovery, so handlers must be re-runnable. Image sources vs swap chains (Learn "Using Win2D without built-in controls"): swap chains redraw with low latency and are not tied to the XAML refresh timer, but cost more — keep at most one or two onscreen; a `CanvasImageSource` can be transformed/faded by XAML while a swap chain cannot. `CanvasSwapChainPanel` is the thin XAML wrapper when you want swap-chain rendering without CanvasAnimatedControl's policies: assign a `CanvasSwapChain`, draw via `CreateDrawingSession(...)` then `Present()`, and call `ResizeBuffers` yourself on `SizeChanged`.

## SwapChainPanel + DirectX (the native seam)

`SwapChainPanel` is a Grid subclass that hosts a DXGI swap chain inside the XAML tree. Wiring is a Win32 interop API, not WinRT: QueryInterface the panel for `ISwapChainPanelNative` (WinUI 3 header `microsoft.ui.xaml.media.dxinterop.h`, Windows App SDK 0.5+) and call `SetSwapChain(IDXGISwapChain*)`.

Rules from the dxinterop / SwapChainPanel docs:

- `SetSwapChain` must run on the panel's UI thread; other threads get `RPC_E_WRONG_THREAD`. Rendering and `Present` can then happen off-thread; `CreateCoreIndependentInputSource` moves input + rendering entirely to background threads.
- `SetSwapChain` addrefs the swap chain (and transitively the D3D device). Pass `null` to release the graph — required for prompt device-lost recovery and teardown.
- Call `SetSwapChain` again on the same swap chain after `IDXGISwapChain::ResizeBuffers` or `SetRotation`.
- Keep the app to ~4 swap chains max; simultaneous updates to many degrade performance.
- Panel resize does not stretch presented content (behaves like `Stretch="None"`); handle `CompositionScaleChanged` and re-render using `CompositionScaleX/Y` or XAML scaling blurs your vectors.
- You cannot set `Background` on a SwapChainPanel, and in WinUI 3 it supports neither transparency nor Acrylic/`CompositionBackdropBrush` effects sampling over it.
- Existing native code that owns an `IDXGISwapChain` can instead be wrapped via Win2D C++ interop into a `CanvasSwapChain` and displayed by `CanvasSwapChainPanel` — useful when the scene mixes native output with Win2D drawing.

## Composition (Microsoft.UI.Composition)

The compositor animates off the UI thread — composition animations run in the compositor, independent of UI-thread jank. WinUI 3 differences from UWP (Learn "XAML and Composition interoperability"):

- `CompositionAnimation` runs directly on elements via `UIElement.StartAnimation`/`StopAnimation`; no `ElementCompositionPreview.GetElementVisual` detour needed for `Scale`/`Translation`-style properties.
- Get the compositor with `CompositionTarget.GetCompositorForCurrentThread()` — call it on the UI thread.
- The new UIElement rendering properties (`Scale`, …) and the old ones (`RenderTransform`, `Projection`, `Transform3D`) are mutually exclusive; mixing them fails the API call. Managing the element's Visual yourself via `ElementCompositionPreview` also opts you out of the new properties.
- "Handout" visuals (`GetElementVisual`) have Offset/Size owned by XAML layout: only animate Offset when the element's top-left matches its parent's, and don't write Size. "Handin" visuals (`SetElementChildVisual`) draw on top of the element — use sparingly; they lack XAML accessibility guarantees.

Use Composition for choreography on XAML content (implicit reposition, shadows, expression-driven parallax); it does not replace a swap chain for immediate-mode scene rendering.

## Threading: DispatcherQueue and render loops

UI objects are single-threaded. Capture `DispatcherQueue.GetForCurrentThread()` on the UI thread at construction — it returns null on worker threads — and marshal every bound-property touch through `TryEnqueue` (`.claude/skills/winui3-shell/SKILL.md`; live example in `src/gui/HELIOS.Shell/ViewModels/AIHubPageViewModel.cs`). For render loops specifically:

- CanvasAnimatedControl's `Update`/`Draw` run on its game-loop thread: never block or `await` inside them, and note that an `await` inside `RunOnGameLoopThreadAsync` work resumes on the thread pool, not the game loop, unless you install a game-loop SynchronizationContext (Learn "Loading resources outside of CreateResources").
- The only UI-thread obligations of a native render loop are the XAML touchpoints: `SetSwapChain`, panel size/scale reads via the queue. Drawing and `Present` stay on the render thread.

## Managed vs native: when to drop to the C++ spoke

Stay managed (Win2D) for 2D drawing — that covers the shell's charts and sparklines (`GUI_THEME_ANALYSIS.md`). Drop to the native spoke only when profiling shows CPU-bound scene prep or the effect exceeds Win2D's expressiveness (`cpp-performance` SKILL.md: D3D12 interop via `ICanvasDevice`, which shares the underlying D3D device, "only for custom effects Win2D cannot express"). The shape of the native path is fixed by the hub-and-spoke rule: a C++/WinRT component renders into a `SwapChainPanel` (or a wrapped `CanvasSwapChain`) and the shell consumes its runtime class — the shell never writes D3D in C#, the spoke exposes a flat ABI, and no spoke calls another spoke (`GUI_THEME_ANALYSIS.md`, `winui3-shell` SKILL.md). Expect to own residency, hazards, and CPU–GPU fencing on the D3D12 side (`cpp-performance` SKILL.md). No web views for core surfaces (`GUI_THEME_ANALYSIS.md`).

## Frame pacing and vsync pitfalls

- **CPU run-ahead is the classic bug**: calling `Present(1, 0)` (vsync on) without fencing CPU frames lets the CPU queue frames ahead of the GPU, inflating input latency. Limit frames in flight with a frame-count fence — typically buffer count minus one (Learn D3D12 "Swap Chains").
- **Waitable swap chains** cut queue latency: create with `DXGI_SWAP_CHAIN_FLAG_FRAME_LATENCY_WAITABLE_OBJECT` (cannot be added or removed later via `ResizeBuffers` — creation-time only), set latency with `IDXGISwapChain2::SetMaximumFrameLatency` (not `IDXGIDevice1`'s), fetch `GetFrameLatencyWaitableObject`, and `WaitForSingleObjectEx` on it before rendering *every* frame, including the first. `CloseHandle` the wait handle when done.
- Waitable-swap-chain latency defaults to 1 (lowest latency, least CPU–GPU parallelism). If CPU and GPU each fit in a refresh budget but their sum does not, set 2.
- Lowest present-to-display latency bypasses vsync entirely: `DXGI_SWAP_CHAIN_FLAG_ALLOW_TEARING` + `Present(0, DXGI_PRESENT_ALLOW_TEARING)`, gated on `IDXGIFactory5::CheckFeatureSupport(DXGI_FEATURE_PRESENT_ALLOW_TEARING)`. A dashboard shell does not want tearing; this exists for latency-critical scenes only.
- Win2D sidesteps most of this: CanvasAnimatedControl owns pacing; CanvasSwapChainPanel leaves redraw frequency to the app. Reach for raw DXGI pacing only inside the C++ spoke.

## Not in the repo (candidates)

- **Microsoft.Graphics.Win2D** (NuGet) — the Win2D package for WinUI 3 (the UWP-era package was `Win2D.uwp`; API surface `Microsoft.Graphics.Canvas.*` is the same). Not yet a `PackageReference` in `src/gui/HELIOS.Shell/HELIOS.Shell.csproj`; add it when the roadmap's sparkline work lands (`src/gui/README.md` roadmap). Win2D is implemented in C++: projects referencing it must target x86/x64/ARM64, never AnyCPU — the csproj's `<Platforms>` already pins this.
- **C++/WinRT authoring tooling** (`Microsoft.Windows.CppWinRT`) for the native spoke component — lives with the spoke when it is created, per `cpp-performance` SKILL.md; nothing under `src/gui/` references it today.
