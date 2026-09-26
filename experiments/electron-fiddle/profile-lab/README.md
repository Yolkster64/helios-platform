# HELIOS Profile Lab for Electron Fiddle

A self-contained visual experiment for the Electron overhaul. Choose **Sysadmin**, **Developer**, **Studio**, **Gamer**, **Core**, or **AI/Server** to compare palette, particle speed and the original ether-blade scene. This changes the preview only; it does not activate an OS profile or connect a service.

## Open in Fiddle

1. Open this directory with Electron Fiddle's **Open** action. The main entry is `main.js`; the renderer uses `index.html`, `renderer.js` and `styles.css`.
2. Keep all five source files together, including `preload.js` and `styles.css`. If your Fiddle version only imports its standard editors, add the two additional files to the experiment folder before running it.
3. Select a supported stable Electron version and run the fiddle. No npm packages, external fonts, assets, API keys or network services are needed.

The same five source files can run with a locally installed Electron executable using `electron main.js`. Do not run `node main.js`: the main entry requires Electron.

## What to inspect

- Click or keyboard-activate each profile; the selected button exposes `aria-pressed`, and a live status names the selection.
- Change light intensity from 20% to 100%.
- Pause/resume motion or enable reduced motion. The OS reduced-motion preference is respected on startup and follows later changes until overridden in the experiment.
- Resize the window. Canvas resolution is capped at 2× device pixel ratio; animation suspends while the document is hidden. Reduced motion draws one static frame per control or size change.
- Check keyboard focus, contrast, readable text, and Windows high-contrast behavior. Forced colors hides the decorative canvas and retains the controls.

## Boundaries

The renderer has Node integration disabled, context isolation and sandboxing enabled, and a restrictive CSP. Main denies permission requests, new windows, external navigation, redirects, webviews and all resource requests except this experiment's three local page assets. The empty preload exports no bridge and there are no IPC handlers, network requests, credential reads, shell commands, file writes or native USB operations.

This lab uses Canvas 2D and a bounded 64-particle animation; it is not a native Direct3D renderer or a performance benchmark. Port reviewed visual changes into `apps/desktop` through its renderer and capability contracts. Electron Forge owns product packaging; Fiddle remains a focused experiment.

Validation should distinguish JavaScript syntax and browser interaction checks from a real Electron Fiddle run. A successful syntax check alone does not establish Electron runtime compatibility or measured performance.
