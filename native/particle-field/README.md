# Optional C++ particle field

This is a real, isolated Node-API addon for the Electron migration. It updates a
batch of 3D particles in C++, providing a small example of a native compute
extension. **It is disabled by default and is not imported by the desktop app.**
There are no runtime npm dependencies. Build dependencies and binaries stay in
this directory; the Electron shell can install, build and run without them.

## Build and verify

Use Node 22.22.2+ (22.x), 24.15.0+ (24.x), or 26+ and a C++17 compiler.
These build-tool minimums follow the pinned node-gyp dependency. On Linux/macOS:

```sh
cd native/particle-field
npm ci --ignore-scripts
npm run build
npm test
```

The POSIX build uses the pinned `node-api-headers` package and does not download a
full Node distribution. `NODE_INCLUDE_DIR` can select an existing header
directory, and `CXX` can select a compiler executable. The generated file is
`build/Release/particle_field.node`; generated binaries are not committed.

On Windows, `npm run build` delegates to the pinned `node-gyp`, which requires
Python and Visual Studio C++ build tools. The alternative `npm run build:gyp`
uses `binding.gyp` on every platform. Node-gyp may download matching Node headers
and Windows import libraries. Windows/macOS builds and loading under Electron
must be verified on their actual target platforms before enabling this plugin.

`npm run test:loader` checks the disabled adapter without requiring a binary.
`npm test` also requires a built, loadable native addon and fails when it is
missing; native verification is never silently skipped.

## Contract

```js
const { loadParticleField } = require('./index.cjs');
loadParticleField(); // null; no binary is loaded

// Standalone Node experiment only; not Electron main/preload/renderer code.
const field = loadParticleField({ enabled: true });
const positions = new Float32Array([10, 0, 0, -10, 0, 0]);
const velocities = new Float32Array(6);
field.update(positions, velocities, 1 / 60);
```

`update(positions, velocities, deltaSeconds)` returns `undefined` and mutates both
arrays in place. Arrays contain consecutive xyz triples. For each component:

```text
vNext = (v - 0.35 * p * dt) * exp(-0.8 * dt)
pNext = p + vNext * dt
```

Double precision intermediates are rounded to Float32 when each output is
written. This is a visual simulation, with no real-world physics claim and no
performance claim until measurements compare it with the JavaScript/GPU path.

The native boundary requires:

- Exactly three arguments; ordinary, attached `Float32Array` storage.
- Equal lengths, 1–100,000 particles, and no overlapping memory ranges.
- No `SharedArrayBuffer` storage, so another thread cannot race validation.
- A finite numeric timestep from 0 through 0.05 seconds, without coercion.
- Every input and proposed output component finite and within ±1,000,000.

Every component and proposed result is validated before either array is changed.
Zero time validates inputs and preserves their bits. Failure throws an error and
leaves both arrays unchanged. Disjoint views into one ordinary ArrayBuffer are
allowed. The addon uses Node-API version 8 and does not call V8 APIs.

## Future Electron integration

Keep this plugin disabled until it has an explicit capability declaration,
packaging/rebuild checks, and target-platform tests. Load the reviewed binary in
an Electron **utility process**, outside main/preload/renderer. A worker thread
is not a crash boundary for native code. The app should pass bounded batches
through a typed request/response contract, use a deadline and restart policy,
and mark the extension unavailable if its process fails. Buffer ownership must
be explicit; do not enable shared-memory inputs to bypass copies.

The utility process host, IPC channel, process crash recovery, Electron ABI/load
test, asar unpacking and signed distribution are future integration work, not
features claimed by this initial package. GPU shaders remain a separate option
for visual workloads; benchmark frame latency before selecting a backend.

Reference: [Node-API documentation](https://nodejs.org/api/n-api.html).
