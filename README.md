# HELIOS Platform

HELIOS is an active Windows-platform and multi-LLM integration project owned at
[`Yolkster64/helios-platform`](https://github.com/Yolkster64/helios-platform). The
currently buildable cross-platform slice combines a .NET 8 AI hub, F# policy logic, an
optional C++ native accelerator, a dependency-free Python analytics/advisory spoke, REST,
CLI, MCP, Docker, and review-only Azure infrastructure.

## Current status

This repository is under consolidation; it is not a finished or production-certified
Windows management product.

- `HELIOS.sln` contains the buildable AIHub, CLI, API, MCP, F# domain, and test projects.
- `src/core/HELIOS.Platform` is deliberately excluded because it has hundreds of
  pre-existing compile errors. The legacy root status/phase reports are historical, not
  evidence that those subsystems are deployed.
- The WinUI 3 shell lives in `src/gui/HELIOS.Shell.sln` and requires Windows.
- Azure and Microsoft 365 mutations are never performed by a build or catalog command.
  Validate Bicep and inspect a `what-if` before any separately approved deployment.
- Recovered engine names marked `prototype` or `concept` are proposal vocabulary. Only
  `implemented` entries with `runtime_available=true` enter an advisory plan.

See [AGENTS.md](AGENTS.md) and
[MULTI_LLM_INTEGRATION.md](docs/architecture/MULTI_LLM_INTEGRATION.md) for the current
engineering contract.

## Prerequisites

- .NET SDK 8
- Python 3.10 or newer
- Git
- Optional: CMake plus a C++ compiler for the native spoke
- Optional: Docker with Compose for the local API container
- Optional: Azure CLI/Bicep for infrastructure validation

Provider credentials are optional. Without them, provider status is reported as
`Unconfigured`; keyless tests and local catalog operations still work.

## Build and test

```bash
dotnet restore HELIOS.sln
dotnet build HELIOS.sln -c Release --no-restore
dotnet test tests/HELIOS.AIHub.Tests/HELIOS.AIHub.Tests.csproj -c Release --no-build

cd src/ai/python
python3 -m pip install '.[dev]'
python3 -m pytest tests -q
```

To exercise the optional native code before the .NET build:

```bash
./scripts/build/build-native.sh
```

Infrastructure validation is read-only:

```bash
az bicep build --file infra/main.bicep --stdout >/dev/null
az bicep build-params --file infra/main.bicepparam --stdout >/dev/null
```

## Multi-LLM surfaces

The CLI uses `config/aihub.json` and reads secrets only from environment variables or the
configured Azure Key Vault.

```bash
dotnet run --project src/ai/HELIOS.AIHub.Cli -c Release -- status
dotnet run --project src/ai/HELIOS.AIHub.Cli -c Release -- routing
dotnet run --project src/ai/HELIOS.AIHub.Cli -c Release -- engines
dotnet run --project src/ai/HELIOS.AIHub.Cli -c Release -- \
  engine-plan --security-profile hardened --pressure 0.8 \
  --fleet-size 36 --include-candidates
```

CLI commands: `ask`, `route`, `tandem`, `compare`, `status`, `providers` (`list`),
`routing`, `engines`, and `engine-plan`.

The MCP server is registered in `.mcp.json` and exposes provider calls, status/routing
reads, engine catalog/recommendation reads, and local infrastructure validation. Client
examples are in [docs/mcp/CLIENT_SETUP.md](docs/mcp/CLIENT_SETUP.md).

## REST API

Run locally:

```bash
dotnet run --project src/ai/HELIOS.AIHub.Api -c Release
curl http://localhost:5170/healthz
curl http://localhost:5170/v1/status
```

`/healthz` is public. Direct loopback calls to `/v1/*` need no access key. A Docker-bridge
or remote caller must configure `HELIOS_API_ACCESS_KEY` and send it as
`X-HELIOS-Api-Key`. For hosted use, put the service behind identity-aware, rate-limited
ingress; the local access key is not a replacement for user authorization.

| Endpoint | Verb | Purpose |
|---|---|---|
| `/healthz` | GET | Process liveness |
| `/v1/status` | GET | Provider readiness without provider calls |
| `/v1/routing` | GET | Default and task-specific provider chains |
| `/v1/learning` | GET | Recorded outcomes for one task type |
| `/v1/learning` | POST | Provenance-required advisory outcome ingestion |
| `/v1/insights` | GET | Python summary and drift analysis |
| `/v1/engines` | GET | Implemented capabilities and runtime availability |
| `/v1/engines/recommend` | POST | Deterministic engine advisory plan |
| `/v1/ask` | POST | One provider or the default routed chain |
| `/v1/route` | POST | Task-type routing with fallback |
| `/v1/tandem` | POST | Concurrent provider-chain execution |
| `/v1/compare` | POST | Parallel provider comparison and deduplication |

The Python boundary is capped at four concurrent child processes. Advisory learning
records carry a required `source` and are excluded from adaptive provider routing.

## Local Docker

Compose publishes the API on host loopback only. Set a non-default local key so host
requests crossing Docker's bridge can reach `/v1/*`:

```bash
export HELIOS_API_ACCESS_KEY='replace-with-a-local-secret'
docker compose up --build -d helios-ai-api

curl http://localhost:5170/healthz
curl -H "X-HELIOS-Api-Key: $HELIOS_API_ACCESS_KEY" \
  http://localhost:5170/v1/engines
```

The image runs as a non-root user and includes Python plus the checked-in spoke. Compose
persists `.helios/learning` in a named volume. Provider credentials pass through from the
host; unset providers remain unconfigured. `.env` and `.env.*` are excluded from the
Docker build context so local credentials are not sent to the daemon.

The optional `fleet` profile runs the dependency-free local kanban stub:

```bash
mkdir -p .helios/fleet
export FLEET_UID="$(id -u)" FLEET_GID="$(id -g)"
docker compose --profile fleet up fleet-stub
```

The stub performs no model work and makes no network calls.

## Configuration

Copy `.env.template` to an ignored local file and replace only the variables you use.
Never commit provider keys or API access keys.

Primary provider variables:

- `OPENAI_API_KEY`
- `ANTHROPIC_API_KEY`
- `AZURE_OPENAI_ENDPOINT` and optional `AZURE_OPENAI_API_KEY`
- `AZURE_FOUNDRY_PROJECT_ENDPOINT`
- `AZURE_KEY_VAULT_URI`
- `GITHUB_MODELS_TOKEN`
- `OLLAMA_BASE_URL`

## Architecture and operations

- [Multi-LLM integration](docs/architecture/MULTI_LLM_INTEGRATION.md)
- [Recovered engine integration record](docs/architecture/RECOVERED_AI_ENGINE_FABRIC.md)
- [Consolidation blueprint](docs/CONSOLIDATION_BLUEPRINT.md)
- [Hermes fleet and XCore](docs/architecture/HERMES_FLEET_AND_XCORE.md)
- [Absorption pipeline](docs/architecture/ABSORPTION_PIPELINE.md)
- [Fork observation](docs/architecture/FORK_OBSERVATION.md)
- [Roadmap](docs/architecture/ROADMAP_MULTI_LLM.md)

The absorption pipeline may benchmark prior upstream PRs in disposable worktrees, but
`Yolkster64/helios-platform` remains the write target. Nothing is auto-merged or pushed to
an upstream repository.

## Contributing

Open issues and pull requests against
[`Yolkster64/helios-platform`](https://github.com/Yolkster64/helios-platform). Keep changes
inside the buildable project boundaries described in [AGENTS.md](AGENTS.md), run the
relevant local gates, and do not claim deployment or security properties without
verifiable evidence.

## License

See [LICENSE](LICENSE).
