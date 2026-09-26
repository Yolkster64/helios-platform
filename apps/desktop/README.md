# HELIOS Workbench

The Electron replacement for the HELIOS desktop UI. This first implementation runs
locally with six profiles, persistent preferences, optional workbench modules,
connection inventory, read-only AIHub diagnostics, and a USB layout planning panel.
The wider migration is tracked in [issue #279](https://github.com/Yolkster64/helios-platform/issues/279)
and the [migration guide](../../docs/migration/electron-overhaul/README.md).

## Run

Install Node.js 22.16+ (Node.js 24 recommended), then:

```sh
cd apps/desktop
npm ci
npm test
npm start
```

`npm run package` creates an application folder. `npm run make` creates an unsigned
Squirrel installer on Windows or a zip on macOS/Linux. Build on the target OS.
Signing, notarization, automatic updates, and release publishing are later gates.
Forge's fuses plugin disables Node CLI escape hatches in packaged applications.

There is no renderer bundler in this baseline: local HTML/CSS/JavaScript keeps the
runtime inspectable and shares concepts directly with the Fiddle experiment. Add a
UI framework/build plugin when feature complexity justifies it.

## Check the local AIHub

The desktop makes no service probe until you press **Check local service** and set
an explicit loopback URL. From the repository root, run the existing service with
the required .NET SDK installed:

```sh
dotnet run --project src/ai/HELIOS.AIHub.Api --no-launch-profile -- --urls http://127.0.0.1:5080
```

In a second terminal:

```sh
cd apps/desktop
HELIOS_AIHUB_URL=http://127.0.0.1:5080 npm start
```

PowerShell uses `$env:HELIOS_AIHUB_URL = 'http://127.0.0.1:5080'; npm start`.
Only `GET /healthz` is called, with a timeout, bounded JSON response, no redirects,
and no credentials. Success means the service responded; it does not prove that
any model, provider, or external connector is ready. Sysadmin disables this probe.

## Boundaries and extensions

- The renderer is sandboxed, with context isolation and no Node.js, arbitrary IPC,
  command execution, webviews, remote content, or credential input.
- Main validates the originating window and frame, and every payload. External
  links resolve from fixed resource IDs in the default browser.
- Built-in module toggles change available UI. They do not install or execute code.
- Local preferences live in Electron's per-user data directory. They contain no
  authentication values.
- Connection cards describe planned adapter capabilities and honestly show
  unavailable state. This ChatGPT session's connectors do not authenticate a
  distributed desktop app.
- Native rendering, audio, drivers, and privileged Windows tasks belong in bounded
  worker/service plugins. The first optional C++ experiment is under
  `native/particle-field`; it is not loaded by the desktop yet.
- This program does not replace Explorer or touch a disk, bootloader, registry,
  driver, credential, cloud resource, or tenant configuration.

The [Fiddle lab](../../experiments/electron-fiddle/profile-lab/README.md) is the
small, isolated playground for profile visuals.
