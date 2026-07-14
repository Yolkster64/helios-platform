# HELIOS Azure Integration Slice

This slice joins Hermes/XCore execution with the Monado Control Center without copying upstream Hermes.

## Components

- `infra/`: Azure Container Apps, ACR, Key Vault, Log Analytics, Application Insights, and managed identity.
- `services/control-api/`: small control-plane API and static Monado dashboard.
- `.github/workflows/helios-azure.yml`: validation, container publish, and OIDC deployment.
- `azure.yaml`: Azure Developer CLI entry point.

## Trust boundaries

The browser talks only to the control API. The API dispatches to the Hermes adapter using managed configuration. XCore training is disabled by default and reports telemetry through the same API contract. Secrets belong in Key Vault; GitHub uses Azure workload identity federation.

## First deployment

1. Create an Azure federated credential for this repository/environment.
2. Add GitHub environment variables `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID`.
3. Run the `HELIOS Azure` workflow with `deploy=true`.

The workflow first deploys infrastructure, builds the container, pushes it to ACR, and updates the Container App. No long-lived Azure secret is required.

