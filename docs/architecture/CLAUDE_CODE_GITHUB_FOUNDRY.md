# Claude Code + GitHub + Microsoft Foundry

HELIOS runs Claude Code against Microsoft Foundry with GitHub and Azure authority kept
separate. The repository carries Claude project context (`CLAUDE.md`, `.claude/agents/`,
`.claude/skills/`, the HELIOS MCP server) while the GitHub workflow obtains Azure access
through short-lived OIDC tokens only.

## Operator entry point

The WinUI 3 shell now exposes **Fabric Control** beside AI Hub. It shows sanitized
readiness for:

- GitHub control plane;
- Claude Code;
- dedicated Claude Azure OIDC;
- Microsoft Foundry / Claude deployments;
- Key Vault + OpenAI/Codex;
- Hermes / AIHub; and
- Slack / Linear / Teams / SharePoint broker connectivity.

The page never renders credential values or performs Azure writes. It provides the
bootstrap/verify commands and links to the governed GitHub/Azure surfaces.

## Dedicated Claude identity

Claude inference does not share the HELIOS deployment identity by default. Use:

```powershell
pwsh scripts/bootstrap/claude-foundry-oidc-setup.ps1 `
  -Repo Yolkster64/helios-platform
```

The bootstrap is idempotent and:

1. requires an already-authenticated Azure CLI session;
2. derives the current subscription unless `-Subscription` is supplied;
3. resolves the Foundry `AIServices` account (or accepts `-FoundryResource`);
4. creates/reuses the `helios-claude-foundry` Entra app and service principal;
5. creates one GitHub federated credential for
   `repo:Yolkster64/helios-platform:ref:refs/heads/main`;
6. grants **Cognitive Services User** on the Foundry account only;
7. verifies the configured Sonnet/Haiku deployment names and reports Opus as optional;
8. writes the non-secret GitHub repository variables when `gh` is authenticated.

No client secret is created.

`Cognitive Services User` is intentionally used as the minimum direct-model-inference
role for this lane. Microsoft Foundry also supports the Foundry-native **Foundry User**
role, which is the preferred role when the principal needs broader Foundry project
capabilities. The Claude workflow itself only needs model invocation, so it does not
receive Contributor or Key Vault write permissions.

## GitHub variables

Dedicated Claude variables:

- `CLAUDE_AZURE_CLIENT_ID`
- `CLAUDE_AZURE_TENANT_ID`
- `CLAUDE_AZURE_SUBSCRIPTION_ID`
- `ANTHROPIC_FOUNDRY_RESOURCE`

Optional:

- `AZURE_RESOURCE_GROUP` (defaults to `rg-helios-ai`)
- `ANTHROPIC_DEFAULT_SONNET_MODEL` (defaults to `claude-sonnet-4-6`)
- `ANTHROPIC_DEFAULT_HAIKU_MODEL` (defaults to `claude-haiku-4-5`)
- `ANTHROPIC_DEFAULT_OPUS_MODEL` (defaults to `claude-opus-4-6`)

The workflow still accepts the existing `AZURE_*` / `AZURE_OIDC_*` identifier chain as
a compatibility fallback, but the dedicated `CLAUDE_AZURE_*` variables take priority.
No `AZURE_CLIENT_SECRET` is read or required.

## Verify without mutation

After bootstrap, use:

```powershell
pwsh scripts/bootstrap/claude-foundry-oidc-setup.ps1 `
  -Repo Yolkster64/helios-platform `
  -VerifyOnly `
  -SkipGitHubVariables
```

`-VerifyOnly` does not create Entra objects, role assignments, federated credentials, or
GitHub variables. It verifies the existing identity, subject, RBAC assignment, Foundry
resource, and required Claude deployment names.

## GitHub execution paths

`.github/workflows/claude-foundry.yml` is owner-dispatched from `main`.

### Review

The Azure-authenticated review job receives:

- `contents: read`;
- `id-token: write` for Azure OIDC; and
- Claude `dontAsk` mode with an explicit read/build/test allowlist.

It cannot edit repository files or run `az`, `git push`, `gh`, `curl`, or `wget` through
Claude's tool surface.

### Implement

The implementation path deliberately splits authority:

1. an Azure-authenticated job lets Claude edit an ephemeral checkout but has no GitHub
   write token and cannot push;
2. it emits a patch artifact;
3. a separate non-Azure job validates the patch against the immutable base commit; and
4. a GitHub-write job with no Azure OIDC permission can publish the validated patch as a
   dedicated branch/draft PR.

A single job therefore never possesses both Azure model authority and repository write
authority.

## Foundry model prerequisites

Claude Code expects deployment names matching the configured model-role variables:

- primary: `claude-sonnet-4-6`;
- fast: `claude-haiku-4-5`;
- extended-thinking: `claude-opus-4-6` (optional for the bootstrap gate).

The bootstrap does not purchase Marketplace offers or deploy paid models. If Sonnet or
Haiku is missing, identity wiring may be complete but Claude remains blocked until the
Azure owner deploys the required model through the governed Foundry process.

## Local Windows / PowerShell

For a local operator session:

```powershell
az login
pwsh scripts/bootstrap/claude-foundry-oidc-setup.ps1 -VerifyOnly -SkipGitHubVariables
pwsh scripts/ai-integration/Connect-ClaudeFoundry.ps1 -Launch
```

`Connect-ClaudeFoundry.ps1` reads Azure account/resource/deployment metadata and sets
process environment variables. It does not create resources, assign RBAC, or write
secrets.

## Security boundary

This integration does not:

- create an Azure client secret;
- grant Contributor to Claude;
- grant Key Vault Secrets Officer to Claude;
- accept Anthropic Marketplace terms;
- deploy Claude models automatically;
- merge Claude-generated PRs automatically; or
- deploy HELIOS infrastructure as a side effect of Claude execution.

The separate governed infrastructure workflow remains `.github/workflows/helios-deploy.yml`.
