# .devcontainer

GitHub Codespaces and the VS Code Dev Containers extension read one file here:
`devcontainer.json`. Everything else in this directory is a standalone local-Docker
stack that `devcontainer.json` does not reference (see the last section).

## devcontainer.json (the live configuration)

| Field | Value | Why |
| --- | --- | --- |
| `image` | `mcr.microsoft.com/devcontainers/dotnet:10.0` | The .NET 10 SDK that `global.json` pins |
| `hostRequirements` | 4 CPUs, 8 GB | The default machine size; the Codespaces picker hides smaller types |
| `features` | Azure CLI, GitHub CLI, PowerShell 7, Node LTS, Python 3.11, Terraform | The toolchain `docs/PROJECT_SETUP.md` lists |
| `customizations.vscode.extensions` | Eleven extensions | The same list as `.vscode/extensions.json` and `workspace.code-workspace`; keep the three identical |
| `customizations.vscode.settings` | `dotnet.defaultSolution`, bash terminal, YAML indent, `window.title`, `workbench.colorCustomizations` | The themed chrome, derived from the shell's `Tokens.xaml`; see [`docs/architecture/WORKSPACE_THEME.md`](../docs/architecture/WORKSPACE_THEME.md) |
| `secrets` | Six names, no values | The creation page prompts for them; see [`.github/CODESPACES_GUIDE.md`](../.github/CODESPACES_GUIDE.md) |
| `forwardPorts` / `portsAttributes` | 5170 `helios-ai-api` | The API port, labelled and notified |
| `postCreateCommand` | Optional native spoke, `dotnet restore` + `build HELIOS.sln`, Python spoke, `helios-ai` symlink | Runs once when the codespace is created |
| `postAttachCommand` | `scripts/bootstrap/session-start-check.sh` | The auth self-check line on every attach |

The file is strict JSON (no comments): `quality.yml` runs `python3 -m json.tool` over
every `*.json`, and `validate_all.py` only tolerates JSONC with a warning. Checks that
must stay green after an edit:

```bash
python3 -m json.tool .devcontainer/devcontainer.json > /dev/null
python3 .claude/skills/automation-wiring/scripts/validate_all.py .vscode .devcontainer
python3 scripts/verify/theme-contrast.py   # fails if the colour block drifts from workspace.code-workspace
```

## Prebuilds (owner step; repository settings, not a workflow file)

Codespaces prebuilds are configured in the repository settings. GitHub creates and
runs its own Actions workflow for them; there is no workflow file to add to
`.github/workflows/`, and none should be invented. Prerequisite: GitHub Actions must
be enabled for the repository.

Click path for the owner (`Yolkster64`):

1. <https://github.com/Yolkster64/helios-platform> > **Settings** (under the repository
   name).
2. In the sidebar, under **Code, planning, and automation**, click **Codespaces**.
3. In the **Prebuild configuration** section, click **Set up prebuild**.
4. Branch: `main`. Configuration file: `.devcontainer/devcontainer.json` (the only one).
5. Regions: select **Reduce prebuild available to only specific regions** and tick the
   region shown as your default under Settings > Codespaces > Region. By default a
   prebuild is created in every region, and each region is billed as separate storage.
6. Prebuild triggers: **Every push** (the default). It updates the prebuild on each push
   to `main`, so a codespace never starts from a stale image. **On configuration
   change** (only when `.devcontainer/**` changes) and **Scheduled** use fewer Actions
   minutes but can serve codespaces that miss the latest source.
7. **Template history**: 1 version retained (versions x regions is the stored count).
8. **Show advanced options**: add yourself for failure notifications (they are only
   delivered if failed-Actions-workflow notifications are enabled in personal settings).
9. **Create**. One workflow run per region follows; the machine picker then shows
   **Prebuild ready** on the types that satisfy `hostRequirements`.

What a prebuild honours from `devcontainer.json`: `image`, `features`,
`hostRequirements` (the machine types the prebuild is produced for), and the
`onCreateCommand` and `updateContentCommand` lifecycle hooks. `onCreateCommand` runs
once when the prebuild is created; `updateContentCommand` runs at creation and on
every update. **`postCreateCommand` does not run during a prebuild.** This repository
restores and builds `HELIOS.sln` in `postCreateCommand`, so a prebuild today saves the
image and feature layer only; moving the restore/build into `updateContentCommand`
would add build caching but performs a network restore inside the prebuild, and is a
separate, deliberate change rather than part of the theme work.

## Standalone local Docker stack (legacy; not used by Codespaces)

`Dockerfile` (`mcr.microsoft.com/devcontainers/universal:2-focal`), `docker-compose.yml`
(services `devcontainer` and `postgres`, a `postgres:16-alpine` database; host ports
8080, 5432, 3000, 5173, 3001, 4200, 8000 and 8888), `onCreateCommand.sh` and `init-db.sh`
predate the .NET 10 image. Nothing in `devcontainer.json` points at them, so a
Codespace never builds them. They still run on their own:

```bash
docker compose -f .devcontainer/docker-compose.yml up -d
docker compose -f .devcontainer/docker-compose.yml exec devcontainer bash
docker compose -f .devcontainer/docker-compose.yml down
```
