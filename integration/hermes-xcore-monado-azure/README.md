# HELIOS Azure Integration Slice

This draft joins the Hermes/XCore boundary to a read-only Monado Control Center without copying an upstream Hermes runtime. It is a staging slice, not production authorization.

## Current capability

- `infra/`: Azure Container Apps, ACR, Key Vault, Log Analytics, Application Insights, and a user-assigned managed identity.
- `services/control-api/`: a containerized status API and responsive Monado dashboard.
- `.github/workflows/helios-azure.yml`: Bicep compilation, container smoke tests, Azure what-if, protected OIDC deployment, and digest-pinned release.
- `azure.yaml`: Azure Developer CLI project definition.

The API currently exposes status reads only. Hermes reports `unbound` until a real adapter health check is wired. XCore training is disabled and reports `safe-standby`. There is no training, merge, deletion, RBAC, notification, or USB execution endpoint.

## Trust boundaries

- Pull-request validation has `contents: read` only and cannot request an Azure token.
- Deployment can run only through an explicit `deploy=true` dispatch of the reviewed `main` branch.
- The deploy job uses the protected `azure-dev` environment and an Entra workload-identity federation subject of `repo:Yolkster64/helios-platform:environment:azure-dev`.
- The first deployment creates only the foundation. It does not expose a placeholder container.
- The image is built in ACR and released by immutable digest.
- Container Apps ingress is internal by default. Public access must be added later through the governed Front Door/WAF, APIM, and Entra boundary.
- Key Vault has RBAC, soft delete, purge protection, and public-network access disabled. Runtime secret access is intentionally not granted until private networking and the adapter contract exist.

## Required `azure-dev` variables

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_RESOURCE_GROUP`

The resource group must already exist. Scope the federated deployment identity to that resource group. Infrastructure creation needs Contributor. The ACR pull role assignment should be pre-provisioned by a separately approved identity; otherwise the deployment identity also needs narrowly governed permission to create that role assignment. Do not grant subscription-wide Owner.

## Deployment sequence

1. Keep this pull request in draft until validation is green and the branch is reconciled with the canonical HELIOS repository.
2. Configure the four environment variables, the exact federated subject, approved deployment branches, and required reviewers on `azure-dev`.
3. Merge the reviewed commit to `main`.
4. Dispatch `HELIOS Azure` from `main` with `deploy=true`.
5. Review both what-if results: foundation first, then the digest-pinned internal Container App revision.
6. Verify Azure activity logs, revision health, identity scope, and rollback evidence before any promotion.

Production deployment remains disabled. The canonical network, policy, and runtime contracts in `M0nado/helios-platform` PR #174 take precedence when this slice is promoted.
