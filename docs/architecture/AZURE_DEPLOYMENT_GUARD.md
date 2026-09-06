# Azure deployment guard: preview first

Status: **draft proposal**. The behavior below takes effect only after this change is
reviewed and merged. Publishing its draft PR does not change the workflow on `main`;
until merge, the existing automatic deployment workflow remains unchanged.

`.github/workflows/helios-deploy.yml` retains its historical display name for existing
Slack/dashboard subscribers, but now performs **manual preview only**. An infrastructure
merge no longer starts Azure apply. `what_if=false` fails explicitly; there is no hidden
apply flag. The workflow never creates a resource group, assigns roles, provisions an
identity, reads secrets, or changes resources. Production remains disabled.

## Before the first preview

Preview is disabled unless the repository variable `HELIOS_AZURE_PREVIEW_ENABLED` is
exactly `true`. Do not set it until the owner has verified all of the following:

1. The existing `azure-dev` GitHub environment has the intended review protection and
   permits only the trusted `main` branch. Naming an environment in YAML does not prove
   those protection rules exist; this change neither creates nor configures them.
2. Its identifier variables bind the intended preview principal and existing target:
   `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, and
   `AZURE_RESOURCE_GROUP`. These are identifiers, not credentials. Use the environment
   scope so its values take precedence over older repository defaults.
3. The Azure workload identity matches the **actual configured OIDC subject** for
   `azure-dev`. The legacy default example is
   `repo:Yolkster64/helios-platform:environment:azure-dev`, not the old main-ref or
   production subject. Verify immutable/custom subject claims and repository/owner IDs
   before configuring trust; repository creation dates, renames, transfers, or custom
   OIDC settings can change the format. Do not log or persist an OIDC token.
4. The principal has only the permissions required to read the intended resources and
   invoke deployment validation/what-if in that scope. No role is assigned here, and a
   generic Reader role is not asserted to include every preview action. A successful
   preview does not establish deployment permission.
5. Azure CLI supports `--validation-level ProviderNoRbac` (2.76 or later), and the
   checked-in `infra/main.bicep` and `infra/main.bicepparam` describe the intended plan.

GitHub documents the environment and immutable/custom subject formats in its
[OIDC reference](https://docs.github.com/en/actions/reference/security/oidc).
Azure documents [preview validation levels](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/deploy-what-if)
and the [validate/what-if commands](https://learn.microsoft.com/en-us/cli/azure/deployment/group).

## One control path

Dispatch **Helios Platform Deploy** from `main`, keep `what_if=true`, and explicitly
enter the tenant ID, subscription ID, and existing resource-group name. No target has a
fallback. This lane deliberately accepts only ASCII resource-group names.

The uncredentialed request job rejects disabled preview, apply requests, wrong source
repositories/refs, missing targets, and malformed identifiers. Only its successful
completion admits the `azure-dev` job. That job checks the requested target against its
configured binding before OIDC login, then verifies the active tenant/subscription and
the exact existing group resource ID. A missing group fails; it is never created.

The shared helper `scripts/validation/azure_deployment_preview.sh` runs ARM validation
followed by resource-ID-only what-if. It uses `ProviderNoRbac` and does not change the
shared CLI account. Request or provider errors fail the run. Resource property payloads
are omitted from the what-if output, though resource identifiers still appear in the
protected run's logs. Do not copy that evidence to public destinations without review.

The workflow-run URL and exact source SHA identify the preview evidence. No deployment
success receipt or integration-event delivery receipt is fabricated. A successful
workflow means **preview succeeded**, never that the platform was deployed. Existing
Slack subscribers still see the historical workflow name; follow the run summary for
the precise result until that connector's status vocabulary is reconciled.

## Activation remains a separate change

This repair does not deploy or enable `HELIOS.RemoteMcp`, Container Apps, or any other
Azure service. It does not configure live GitHub environments, federation, RBAC, secrets,
or connector bindings. PR #148 owns the separate explicit-target OIDC-bootstrap changes;
it does not modify this deployment workflow. Reconcile those scripts' subject settings
before attempting identity setup.

A future reviewed activation lane must bind the exact existing Azure target, source SHA,
template/parameter digest, what-if evidence, protected environment, and specific apply
approval. It must be a new reviewed implementation, not a toggle in this preview helper.
Land this guard before any new `infra/**` lane to remove the historical push-apply path.

## Offline proof

```bash
bash -n scripts/validation/azure_deployment_preview.sh
python3 -m unittest discover -s scripts/validation/tests -p 'test_azure_deployment_guard.py' -v
```

The tests exercise the real helper against an inert Azure CLI and inspect workflow
boundaries. The CI test workflow has read-only GitHub permissions, no environment, and
no OIDC login; pull requests cannot authenticate to Azure through these tests. Offline
tests prove the command/guard contract, not live Azure access or successful what-if.
