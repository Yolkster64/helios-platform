# SharePoint (pointer) & Azure DevOps (honest status) — reference

*Versions and API claims mirror the cited repo files; update this file in the same PR
that changes them.*

## SharePoint / M365 — what exists, and where the knowledge lives

This skill does not duplicate the Microsoft lane. The owning surfaces:

- **`integrations/m365/README.md`** — the real integration: a Copilot (Graph)
  connector definition (`graph-connector/connection.json` + `schema.json`) that
  indexes repo-side HELIOS docs into M365 search/Copilot grounding, and a
  declarative agent manifest
  (`declarative-agent/declarativeAgent.json`, schema v1.5), plus the owner
  runbooks for both. Everything there is a repo artifact — no tenant mutation
  happens from this repo (README lines 3-9, 71-79). SharePoint/OneDrive content
  is already Copilot-groundable without the connector; the connector adds the
  repo-side corpus that never lands in SharePoint (lines 25-27). Tenant
  reachability and the 49-document HELIOS corpus were live-verified read-only
  on 2026-08-13 (lines 10-24).
- **`.claude/skills/microsoft-ecosystem/`** — the skill that owns Entra, Graph,
  M365 Copilot, Purview, and Fabric; API-level facts (connector endpoints,
  semantic labels, permissions, manifest schema) are in its
  `references/graph-and-copilot.md`. Ground any API claim you cannot cite from
  the repo via the Microsoft Learn MCP tools, never from memory
  (`.claude/skills/microsoft-ecosystem/SKILL.md:9-12`).

### `scripts/microsoft-enterprise/m365/sharepoint-setup.ps1` — read before trusting

Honest characterization (from reading the script): it is a **scaffold, not a
working setup path**. It declares `#Requires -Modules PnP.PowerShell` (line 6)
but no function body ever calls a PnP cmdlet — `New-SharePointSite`,
`New-SharePointList`, and `Set-SharePointSitePermission` log
"created/set successfully" and return `$true` without contacting SharePoint
(lines 22-36, 50-78), and `Get-SharePointSites` returns a hardcoded empty array
(lines 38-48). It also logs to the Windows-only path `C:\Logs\HELIOS\M365`
(lines 10-12) and ends with `Export-ModuleMember` in a plain `.ps1` (line 80),
which fails outside a module. Point setup work at the
`integrations/m365/README.md` runbook instead; never present this script's
"Success" log lines as evidence anything happened.

### What is owner-gated (never delegable)

- **Admin consent** for the connector app's application permissions
  (`ExternalConnection.ReadWrite.OwnedBy` + `ExternalItem.ReadWrite.OwnedBy`) —
  `integrations/m365/README.md:36-41` runbook step 1, and the exact
  `az ad app permission admin-consent` command in
  `docs/architecture/ENTERPRISE_AI_CONNECTIONS.md:77-83`.
- **MFA re-auth**: the measured 2026-08-13 state had both the Azure ARM and
  Graph planes blocked with `AADSTS50078` (MFA expired) —
  `ENTERPRISE_AI_CONNECTIONS.md:9-14`; the fix is the owner-only tenant-scoped
  re-login in its §1 (lines 27-35). Only the owner can satisfy MFA.
- **Every tenant mutation** — connection creation, app upload, consent —
  is an owner action; repo agents may read (as verified) but never write to the
  tenant on their own initiative (`integrations/m365/README.md:71-79`).
- **Verify-only diagnosis**: `scripts/bootstrap/auth-doctor.ps1` has a
  sharepoint connector lane — report-only, env-var names only, values never
  printed; owner fixes are reported as commands, never run.

## Azure DevOps — current state: nothing is configured

No ADO integration exists in this repo. Specifically:

- `config/connectors.json` has only `slack` and `linear` blocks
  (`config/connectors.json:3-36`) — no ADO entry.
- No workflow under `.github/workflows/` calls `dev.azure.com`, and no
  bootstrap script wires an ADO org.
- The mentions that do exist are incidental, not wiring:
  `installer/core-infrastructure/shared-resources/config-templates/azure-config.template.json:33,40-41`
  (an `${AZURE_DEVOPS_PAT}` placeholder and `dev.azure.com/YOUR_ORG/...` sample
  URLs in an installer template),
  `docs/NUGET_PUBLISHING_GUIDE.md:242-258` (ADO Artifacts described as a feed
  option), `microsoft-ecosystem/README.md:141,183` and
  `microsoft-ecosystem/DEPLOYMENT_ARCHITECTURES.md:21` (aspirational
  architecture prose), and `docs/board-setup/BOARD_CUSTOM_FIELDS_COMPLETE.md:1209`
  (an external-link format example). None of these executes anything.

When asked to "sync to ADO" / "post to Azure Boards" / "trigger an ADO
pipeline", the correct answer is: **not configured today** — then, if wanted,
the design-forward sketch below. Never fabricate capability.
`scripts/bootstrap/auth-doctor.ps1`'s azure-devops connector lane reports
exactly this not-configured state (report-only, names only).

### Design-forward: what wiring an ADO org WOULD touch

Marked as design, not current capability. The tool-level facts below are not
citable from this repo — re-verify them via the Microsoft Learn MCP tools
before building (the `microsoft-ecosystem` grounding rule, its
`SKILL.md:9-12`); the repo-pattern claims are cited.

- **CLI surface**: the `az devops` extension
  (`az extension add --name azure-devops`); its documented non-interactive auth
  is the `AZURE_DEVOPS_EXT_PAT` environment variable. Under this repo's rules
  that NAME would join `config/connectors.json` (the env-var-names-only pattern
  of `config/connectors.json:2`) and the value would live in Actions secrets or
  Key Vault, never in the repo (CLAUDE.md "No secrets in the repo" hard rule).
- **Identity**: ADO's classic pattern is stored credentials (PATs, service
  connections). This repo's existing Azure auth pattern is the opposite —
  GitHub→Azure OIDC federation where "no client secret is ever created, so
  there is nothing to leak or rotate", federated credentials for exactly three
  subjects, and least-privilege resource-group scoping
  (`scripts/bootstrap/azure-oidc-setup.sh:2-17`). Any ADO wiring should justify
  why it cannot use federated/workload identity before storing a PAT; if a PAT
  is unavoidable, it follows the same custody chain as `LINEAR_API_KEY`
  (name in config, value in `gh secret set`,
  `docs/architecture/CONNECTIONS_SETUP.md:200-201`).
- **Workflow shape**: an ADO connector would mirror the existing contracts —
  a dedicated workflow reading `config/connectors.json`, a skip-green gate on
  its secret so it can never be the red check (the `linear-sync.yml:50-53` /
  `notify-slack.yml:45-48` pattern), and routing changes as config edits, never
  workflow edits (`CONNECTIONS_SETUP.md:187-189,201`).
- **Server-side home**: if it ever becomes a service instead of a workflow,
  that is the `HELIOS.Connectors` / Hermes-plugin decision deferred to PR4
  (`docs/architecture/ROADMAP_MULTI_LLM.md:31-34`) — a spike decides, and the
  same Key Vault credential flow applies.
