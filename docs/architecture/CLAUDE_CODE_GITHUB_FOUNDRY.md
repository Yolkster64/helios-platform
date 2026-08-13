# Claude Code + GitHub + Microsoft Foundry

This integration connects HELIOS to Claude Code through Microsoft Foundry while keeping
GitHub and Azure authority separated.

## Architecture

The repository already provides Claude project context through `CLAUDE.md`, dedicated
agents under `.claude/agents/`, skills under `.claude/skills/`, and the HELIOS MCP
server. The integration adds two execution paths:

1. **Review** — an owner-only `@claude` PR comment or a manual review dispatch runs
   Claude Code against Microsoft Foundry. The job has Azure OIDC access but only
   read-oriented repository tooling.
2. **Implement** — a manual owner dispatch lets Claude edit an isolated checkout. That
   Azure-authenticated job has a read-only GitHub token and cannot push. It emits a
   patch artifact. A second job with `contents: read` validates the patch, and a third
   job with GitHub write permission but no Azure OIDC permission publishes a dedicated
   `claude/foundry-<run-id>` branch and opens a draft PR.

This means one job never possesses both Azure cloud authority and GitHub repository
write authority.

## Required Azure and GitHub configuration

The workflow consumes repository **variables**, not a client secret:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_RESOURCE_GROUP` (optional; defaults to `rg-helios-ai`)
- `ANTHROPIC_FOUNDRY_RESOURCE` (recommended when more than one Foundry account exists)

Optional model-deployment variables:

- `ANTHROPIC_DEFAULT_SONNET_MODEL` (defaults to `claude-sonnet-4-6`)
- `ANTHROPIC_DEFAULT_HAIKU_MODEL` (defaults to `claude-haiku-4-5`)
- `ANTHROPIC_DEFAULT_OPUS_MODEL` (defaults to `claude-opus-4-6`)

The existing `scripts/bootstrap/azure-oidc-setup.sh` creates the GitHub-to-Azure
federation used by HELIOS without creating a client secret. For Claude inference only,
a dedicated Entra application with the Foundry-native **Azure AI User** role is the
preferred least-privilege end state. The existing HELIOS deployment identity can be
used for initial validation, but it is intentionally more privileged because it also
supports infrastructure deployment.

Do not add `AZURE_CLIENT_SECRET` for this integration.

## Foundry prerequisites

Claude Code requires Claude model deployments in the selected Microsoft Foundry
resource. The names must match the `ANTHROPIC_DEFAULT_*_MODEL` variables above.

This PR does not deploy paid models or alter the existing Bicep stack automatically.
Model purchase/deployment remains an explicit Azure operator action.

## Local Windows / PowerShell

Authenticate Azure first, then configure the current PowerShell process:

```powershell
az login
az account set --subscription <subscription-id>
./scripts/ai-integration/Connect-ClaudeFoundry.ps1
claude
```

If the resource group contains exactly one `AIServices` Foundry account, the helper
finds it automatically. Otherwise specify it explicitly:

```powershell
./scripts/ai-integration/Connect-ClaudeFoundry.ps1 `
  -ResourceGroup rg-helios-ai `
  -FoundryResource <foundry-resource-name> `
  -Launch
```

The helper is observational/configurational: it reads Azure account/resource/deployment
metadata and sets process environment variables. It does not create resources, deploy
models, write secrets, or assign RBAC.

## GitHub review workflow

After `.github/workflows/claude-foundry-comment-review.yml` is on `main`, the repository
owner can add an `@claude` comment to a pull request. The action runs only when the
actor is the repository owner.

The review lane uses:

- `contents: read`
- `issues: write` and `pull-requests: write` only for the review response
- `id-token: write` for Azure OIDC
- Claude `dontAsk` permission mode with an explicit read/build/test tool allowlist
- explicit denial of file writes, `az`, `git push`, `gh`, `curl`, and `wget`

## Manual implementation workflow

From the Actions UI, run **Claude Code on Microsoft Foundry** from `main`, choose
`implement`, and provide the task.

The first job can edit only its ephemeral checkout. It cannot push. The validation
and publish jobs then:

1. downloads the patch artifact;
2. applies it to the same immutable base commit SHA captured before Claude edited;
3. builds the native spoke;
4. builds/tests .NET;
5. compiles/tests Python;
6. compiles the Bicep entrypoint;
7. publishes to a dedicated Claude branch; and
8. opens a **draft** PR.

No automatic merge or Azure infrastructure deployment occurs in this workflow.

## Existing legacy deployment workflow

`.github/workflows/deploy.yml` is an older placeholder-style workflow and still carries
an `AZURE_CLIENT_SECRET` environment reference. Do not use it for this Claude/Foundry
path. The governed Azure deployment workflow is `.github/workflows/helios-deploy.yml`,
which already uses GitHub OIDC.

A separate cleanup PR should retire or harden the legacy workflow so the repository has
one authoritative Azure deployment path.
