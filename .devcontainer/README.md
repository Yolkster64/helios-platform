# HELIOS devcontainer

Supported path:

- `.devcontainer/devcontainer.json` uses `mcr.microsoft.com/devcontainers/dotnet:8.0`
  with Azure CLI, GitHub CLI, PowerShell, Node LTS, Python 3.11, and Terraform
  features.
- Post-create bootstrap is `.devcontainer/onCreateCommand.sh` and is intentionally
  idempotent/non-destructive.

Optional local service path (not the default container build):

- `.devcontainer/docker-compose.yml` defines a **profile-gated** local PostgreSQL
  service only (`local-services`) bound to loopback.
- Database credentials are read from environment variables (for example
  `HELIOS_POSTGRES_PASSWORD`) and are not committed.

Examples:

```bash
# Validate devcontainer metadata
jq empty .devcontainer/devcontainer.json
docker compose -f .devcontainer/docker-compose.yml config

# Start optional local postgres sidecar
HELIOS_POSTGRES_PASSWORD=local-dev-password \
docker compose -f .devcontainer/docker-compose.yml --profile local-services up -d
```
