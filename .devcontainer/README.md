# HELIOS development container

This directory has two deliberately separate entrypoints:

1. `.devcontainer/devcontainer.json` — the supported VS Code / Codespaces devcontainer.
2. `.devcontainer/docker-compose.yml` — an optional local PostgreSQL sidecar, not a second full workspace container.

That split keeps one canonical toolchain while still offering an opt-in local database.

## What the devcontainer includes

- A `.devcontainer/Dockerfile` image that inherits `mcr.microsoft.com/devcontainers/dotnet:8.0` for the portable `HELIOS.sln` build.
- Dev Container features for Azure CLI, GitHub CLI, **Node.js 22** (pinned for current repository tooling), PowerShell 7, Python 3.11, and Terraform.
- A small Dockerfile layer with `cmake`, `postgresql-client`, `shellcheck`, `sqlite3`, and other repo-level utilities.
- Port forwarding for `helios-ai-api` on `5170`.
- Persistent caches for NuGet, pip, and npm under the container user's home directory.

The workspace opens at `/workspaces/<repo-name>`. The post-create step runs `.devcontainer/onCreateCommand.sh`, which:

- resolves the repo root from the script location;
- optionally builds the native C++ spoke when `cmake` is available;
- rebuilds `src/ai/python/.venv` only when that venv is missing or invalid;
- installs the Python spoke in editable mode with its local `dev` extra; and
- runs `dotnet build HELIOS.sln -c Release` plus `pwsh scripts/build/verify-readiness.ps1`.

It does **not** create or overwrite Git hooks, Git identity, `.env`, `.npmrc`, helper scripts, or other tracked workspace files.

This Linux devcontainer is for the portable AIHub/CLI/MCP/test solution. The active WinUI desktop shell stays on its separate .NET 10 + Windows toolchain and is not built by this container.

## Open the supported devcontainer

In VS Code, choose **Reopen in Container** from the repository root.

If you prefer the Dev Container CLI:

```bash
devcontainer up --workspace-folder .
devcontainer exec --workspace-folder . bash
```

## Optional local PostgreSQL sidecar

The compose file is intentionally database-only. It keeps the existing `postgres-data` named volume and binds the database to loopback instead of all host interfaces.

1. Create an untracked env file at `.devcontainer/local.env`:

   ```dotenv
   HELIOS_DEV_POSTGRES_PASSWORD=choose-a-local-dev-password
   # Optional overrides:
   # HELIOS_DEV_POSTGRES_DB=helios_dev
   # HELIOS_DEV_POSTGRES_USER=helios_dev
   # HELIOS_DEV_POSTGRES_PORT=5432
   ```

2. Start the sidecar:

   ```bash
   docker compose \
     --env-file .devcontainer/local.env \
     --profile database \
     -f .devcontainer/docker-compose.yml \
     up -d postgres
   ```

3. Wait for readiness:

   ```bash
   docker compose \
     --env-file .devcontainer/local.env \
     -f .devcontainer/docker-compose.yml \
     ps
   ```

4. Connect from the host:

   ```bash
   PGPASSWORD=choose-a-local-dev-password \
   psql -h 127.0.0.1 -U helios_dev -d helios_dev
   ```

`init-db.sh` only runs when Docker initializes an empty `postgres-data` volume. It creates the current local dev schema; it does **not** migrate an existing volume.

## Validation commands

These are the repository gates the devcontainer is meant to support:

```bash
cd /workspaces/<repo-name>
dotnet build HELIOS.sln -c Release
dotnet test tests/HELIOS.AIHub.Tests -c Release
cd src/ai/python && python3 -m pytest tests
cd /workspaces/<repo-name>
bicep build infra/main.bicep --stdout
cd /workspaces/<repo-name>
python3 scripts/validation/validate_yolkster_cutover.py
python3 -m unittest discover -s .devcontainer/tests
```

## Limitations and safety notes

- The portable solution intentionally excludes the legacy root/core WPF project.
- The optional native C++ spoke build is best-effort only; AIHub still has managed fallbacks.
- Host Docker access is **not** mounted into the devcontainer by default. If you add it locally, treat that as host-level Docker authority.
- `docker compose down` stops the local PostgreSQL sidecar and preserves `postgres-data`.
- `docker compose down -v` deletes the dev database volume. Use it only when you intentionally want to reset local data.
