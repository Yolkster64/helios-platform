# Enterprise AI connections — detailed buildup runbook

One sitting, in order: refresh Azure auth, build up Azure/Entra/Foundry, wire
Microsoft 365 admin + Copilot, connect the ChatGPT instance, and finish the Claude
enterprise + Workbench API lanes. Every step is exact commands; everything here was
probed live on 2026-08-13 from the operations container, so the starting state is
measured, not assumed.

## 0. Measured starting state (2026-08-13)

| Lane | State | Evidence |
|---|---|---|
| Azure ARM plane | **Blocked — MFA expired** | `az group list` → `AADSTS50078` |
| Azure Graph plane (`az ad`) | **Blocked — MFA expired** | `az ad signed-in-user show` → `AADSTS50078` |
| az profile | Signed in (cached): tenant `349e1399-dccf-45b1-af7e-05d7b0676abf`, subscription `main` | `az account show` |
| M365 tenant (read) | **Live** via the authorized claude.ai Microsoft 365 connector | `GET /me` + SharePoint search verified (`integrations/m365/README.md`) |
| Codex cloud (ChatGPT) ↔ GitHub | **Live** — reviews every PR in this repo | Codex review waves on PRs #94–#99; managed at chatgpt.com/codex settings |
| codex CLI | Not logged in | `codex login status` → "Not logged in" |
| `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` / `GITHUB_MODELS_TOKEN` | unset | env probe (names only) |
| GitHub Copilot reviewer + coding agent | **Live** | Copilot reviews on #99/#10; agent PRs #95–#97 merged |
| Claude Code (enterprise remote session) | **Live** — this operations lane | this session |

The pattern: the *cloud-side* integrations (Codex reviewer, Copilot, M365 connector,
Claude Code) are already connected; what needs buildup is the *tenant/credential
side* — Azure resources, Entra apps, M365 admin registration, and local API lanes.

## 1. Azure re-auth (owner, ~2 min — everything below depends on it)

```bash
az logout
az login --tenant "349e1399-dccf-45b1-af7e-05d7b0676abf"
# If Graph calls still 401 later (az ad ...), refresh with the Graph scope explicitly:
az login --tenant "349e1399-dccf-45b1-af7e-05d7b0676abf" --scope "https://graph.microsoft.com//.default"
az account show   # expect subscription "main"
```

## 2. Detailed Azure buildup (ARM plane)

The Foundry stack (`rg-helios-ai`: account `helios-ai`, project `helios-project`,
`gpt-5-mini` + additional deployments, Key Vault) deploys from `infra/main.bicep` —
current state re-verifies idempotently. Full parameter docs: `infra/README.md`.

```bash
# 2.1 Inventory what exists
az resource list -g rg-helios-ai -o table

# 2.2 Re-verify the stack unchanged (safe, read-only plan)
az deployment group what-if -g rg-helios-ai \
  --template-file infra/main.bicep --parameters infra/main.bicepparam

# 2.3 Build up the Agents' AI Search connection (opt-in module; new Search
#     service is Basic tier ≈ $75/mo — deliberate cost)
az deployment group what-if -g rg-helios-ai \
  --template-file infra/main.bicep --parameters infra/main.bicepparam \
  --parameters deployAiSearchConnection=true
az deployment group create -g rg-helios-ai \
  --template-file infra/main.bicep --parameters infra/main.bicepparam \
  --parameters deployAiSearchConnection=true

# 2.4 Export the runtime env contract from outputs (names in .env.template)
az deployment group show -g rg-helios-ai -n main \
  --query "properties.outputs.{foundry:projectEndpoint.value, kv:keyVaultUri.value}"
# -> AZURE_FOUNDRY_PROJECT_ENDPOINT / AZURE_KEY_VAULT_URI
```

Verify: `helios-ai status` flips `azure-foundry` toward ready once
`AZURE_FOUNDRY_PROJECT_ENDPOINT` is exported; `helios_foundry_agent_list` (MCP)
lists agents; `helios_infra_validate` stays green.

## 3. Entra buildup (Graph plane)

```bash
# 3.1 Ingress app for helios-ai-api (design: IDENTITY_ARCHITECTURE.md §1)
pwsh scripts/bootstrap/register-entra-app.ps1              # dry-run: prints every command
pwsh scripts/bootstrap/register-entra-app.ps1 -Apply       # executes (validates OIDC subjects strictly)

# 3.2 M365 Copilot connector app (used in §4; application permissions)
az ad app create --display-name "helios-m365-connector" --sign-in-audience AzureADMyOrg
APP_ID=$(az ad app list --display-name "helios-m365-connector" --query "[0].appId" -o tsv)
az ad sp create --id "$APP_ID"
# Grant application permissions: ExternalConnection.ReadWrite.OwnedBy + ExternalItem.ReadWrite.OwnedBy
# (Graph resource appId 00000003-0000-0000-c000-000000000000), then admin consent:
az ad app permission admin-consent --id "$APP_ID"

# 3.3 Credential custody: client secret goes to Key Vault ONLY (never a file/repo)
SECRET=$(az ad app credential reset --id "$APP_ID" --display-name kv-custody --query password -o tsv)
az keyvault secret set --vault-name kv-helios-jcut --name m365-connector-client-secret --value "$SECRET"
unset SECRET
```

## 4. Microsoft 365 admin + Copilot buildup

Artifacts are already authored in `integrations/m365/` (connection, schema,
declarative agent manifest); its README carries the full runbook. Condensed order:

1. Client-credentials token for Graph as `helios-m365-connector` (secret from Key
   Vault, never echoed).
2. `POST /external/connections` with `graph-connector/connection.json` →
   `PATCH .../heliosplatform/schema` with `schema.json` → poll the operation to
   `completed` (minutes).
3. M365 admin center → Search & intelligence → Data sources → enable the
   `heliosplatform` connection for Copilot.
4. Package `declarative-agent/declarativeAgent.json` with the M365 Agents Toolkit;
   upload via Integrated apps; assign to the operators group. SharePoint grounding
   works immediately (the governance tree is live-verified); connector grounding
   activates when step 2's items are ingested.
5. Ingestion automation (repo → connector items) rides the GitHub OIDC → Entra
   federation pattern (`IDENTITY_ARCHITECTURE.md` §3) — no stored client secret in CI.

## 5. ChatGPT instance (Codex) — cloud is live, add the local/API lane

Already connected: the Codex cloud reviewer on this repo (triggers on
ready-for-review; `@codex review` / `@codex address that feedback` work in PR
comments; managed at chatgpt.com/codex settings). To light up the local lanes:

```bash
codex login            # ChatGPT-plan device flow (browserless: codex login --device-auth)
# OR platform billing:
export OPENAI_API_KEY=<from platform.openai.com project keys>   # value never in files
```

Both the `codex` CLI lane and the hub's `openai-codex` API provider
(`config/aihub.json`, model `gpt-5.1-codex-max`) key off `OPENAI_API_KEY`; the
`openai` provider shares it. Prefer Key Vault custody: store as `openai-api-key`
secret (the name `config/aihub.json` already references) and let `SecretResolver`
pull it via `AZURE_KEY_VAULT_URI`.

## 6. Claude enterprise + Workbench APIs

- **Claude Code (enterprise ops lane)** — already live: this remote session, plus
  `claude` CLI locally. Nothing to build.
- **`ant` CLI** (platform automation): `ant auth login` (device flow; `--no-browser`
  for Cloud Shell), verify with `ant auth status` (grep stdout, never the exit
  code); `ANTHROPIC_API_KEY` in the environment overrides profiles. CI uses the
  WIF/OIDC federation pattern, not stored keys.
- **Workbench / Console APIs** (platform.claude.com): create (or use) the org's
  workspace for HELIOS, issue a workspace-scoped API key, and custody it as the
  `anthropic-api-key` Key Vault secret (again, the name `config/aihub.json` already
  references) or `ANTHROPIC_API_KEY` env for local work. Workspace scoping keeps
  HELIOS usage/limits separate from other org spend and lets the key be rotated
  without touching other projects. The Workbench itself then serves as the prompt
  lab against the same key the hub uses.
- **Enterprise governance note**: seat/SSO administration happens in the org's
  claude.ai admin console (owner); nothing in this repo stores or requires it.

## 7. One-command verification (after any subset above)

```bash
pwsh scripts/bootstrap/connect-all.ps1          # verify-first; exit 0 = all lanes ready, 2 = attention list
pwsh scripts/setup/setup-all.ps1 -Json          # machine-readable readiness
helios-ai status                                # provider-by-provider readiness with hints
```

`connect-all` is honest about lane semantics (a logged-in `gh` alone does not make
GitHub Models ready; the export remediation is printed). Expected end state: azure,
github, anthropic, openai lanes ready; `helios-ai status` shows `azure-foundry`,
`openai-codex`, `anthropic` configured; M365 Copilot answers HELIOS questions
grounded in the governance tree and, post-ingestion, repo knowledge.
