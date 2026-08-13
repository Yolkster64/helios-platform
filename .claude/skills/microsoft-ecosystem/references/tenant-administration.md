# Tenant administration — Entra, Conditional Access, M365 admin, Purview

*Versions and API claims mirror the cited repo files; update this file in the same PR
that changes them.* Microsoft claims verified against Microsoft Learn (2026-08); URLs
cited inline — re-verify via the Microsoft Learn MCP tools before relying on anything
this file does not list.

Scope: the tenant-side *administration* knowledge behind this program's runbooks —
`docs/architecture/ENTERPRISE_AI_CONNECTIONS.md` (the measured state and buildup that
`scripts/bootstrap/setup-tenant.ps1` automates) and
`docs/architecture/IDENTITY_ARCHITECTURE.md` (the identity design). Graph/Copilot API
mechanics live in `references/graph-and-copilot.md`, packaging/tooling in
`references/m365-copilot-tools.md`; neither is duplicated here.

## The tenant, as measured

Tenant `349e1399-dccf-45b1-af7e-05d7b0676abf` / `Heli0s.onmicrosoft.com`, subscription
`main`, probed live on 2026-08-13 from the operations container
(`ENTERPRISE_AI_CONNECTIONS.md` §0): the az profile was cached and readable
(`az account show` succeeds offline against the local profile), but **both live
planes — ARM (`az group list`) and Graph (`az ad signed-in-user show`) — were blocked
by `AADSTS50078`**. The M365 read lane (claude.ai Microsoft 365 connector) stayed
live and independently verified the tenant and its SharePoint governance corpus
(`integrations/m365/README.md`, "Live verification"). Everything below is anchored to
that measured tenant, not an idealized one.

## App-registration governance

**Who can register an app**: by default every user can (the tenant setting "Users can
register applications"); the least-privileged role when that default is locked down
is **Application Developer**
(<https://learn.microsoft.com/entra/identity/role-based-access-control/permissions-reference>;
task mapping: <https://learn.microsoft.com/entra/identity/role-based-access-control/delegate-by-task>).
Registration alone grants nothing tenant-wide — the power moments are *consent* and
*assignment*, which is why `IDENTITY_ARCHITECTURE.md` §1 marks them **[owner]** and
why `register-entra-app.ps1` prints those commands instead of running them.

**Consent is tiered, and the tier matters for this program's two apps**
(<https://learn.microsoft.com/entra/identity/enterprise-apps/grant-admin-consent>):

| What is being consented | Least role that can grant it |
|---|---|
| Delegated scopes / app roles for any API **except Microsoft Graph application permissions** | **Cloud Application Administrator** (or Application Administrator / AI Administrator) |
| **Microsoft Graph app roles (application permissions)** | **Privileged Role Administrator** (or Global Administrator) |

- `helios-ai-api`'s delegated `AIHub.Access` scope (admin-consent-only) → a Cloud
  Application Administrator click (`IDENTITY_ARCHITECTURE.md` §1, owner steps).
- `helios-m365-connector` needs Graph **application** permissions
  `ExternalConnection.ReadWrite.OwnedBy` (`f431331c-49a6-499f-be1c-62af19c34a9d`) +
  `ExternalItem.ReadWrite.OwnedBy` (`8116ae0f-55c2-452d-9944-d18420f5b2c8`)
  (<https://learn.microsoft.com/graph/permissions-reference>), so its
  `az ad app permission admin-consent` (`ENTERPRISE_AI_CONNECTIONS.md` §3.2) is a
  **Privileged Role Administrator / Global Administrator** action — Cloud Application
  Administrator is *not* enough for that one.

**Admin-consent workflow**: rather than handing users standing consent rights, the
tenant can enable the request workflow — users hit "Approval required" and a named
reviewer set gets the queue
(<https://learn.microsoft.com/entra/identity/enterprise-apps/configure-admin-consent-workflow>).
At this tenant's size the owner *is* the reviewer; the workflow is still worth
enabling so requests are recorded instead of arriving as screenshots.

**The duplicate-display-name trap**: Entra display names are **not unique keys** —
`az ad app create --display-name X` happily mints a second registration named `X`,
and every later `az ad app list --display-name X --query "[0]"` becomes a coin flip
between the twins (wrong appId, orphaned role assignments, consent on the wrong
object). `scripts/bootstrap/register-entra-app.ps1:263-274` guards this by listing
first and skipping create when the name resolves; `ENTERPRISE_AI_CONNECTIONS.md` §3.2
resolves the connector appId the same way, and `setup-tenant.ps1` carries the guard
for every app it touches. Rule: **list before create, always; treat appId (never
display name) as the identity.**

## Conditional Access — how it bit this program

On 2026-08-13 the operations container's cached Azure CLI session hit
**`AADSTS50078`** on both ARM and Graph (`ENTERPRISE_AI_CONNECTIONS.md` §0).
`AADSTS50078` is `UserStrongAuthExpired` — "Presented multifactor authentication has
expired due to policies configured by your administrator"
(<https://learn.microsoft.com/entra/identity-platform/reference-error-codes>): a
Conditional Access **sign-in frequency** control (or per-user MFA re-registration)
expired the MFA claim behind an otherwise-valid refresh token
(<https://learn.microsoft.com/entra/identity/conditional-access/concept-session-lifetime>).

What that means for a **long-lived ops container** riding a human's `az login`:

- Sign-in frequency binds to the *user* identity, wherever its tokens are used. A
  container that outlives the frequency window **will** freeze mid-task, exactly as
  measured — this is the policy working, not breaking.
- The remediation is interactive by design and cannot be scripted away:
  `az logout` then `az login --tenant "349e1399-dccf-45b1-af7e-05d7b0676abf"` (add
  `--scope "https://graph.microsoft.com//.default"` if `az ad` calls still 401 —
  `ENTERPRISE_AI_CONNECTIONS.md` §1). `setup-tenant.ps1` step 1 detects the state and
  prints exactly this; it never runs `az login` itself.
- The honest options, in preference order:
  1. **Workload identity for the automation** — GitHub OIDC federation for CI
     (`IDENTITY_ARCHITECTURE.md` §3, deployed) and a dedicated ops identity for the
     container (next section). User-targeting CA policies like sign-in frequency do
     not apply to service principals; Conditional Access *for* workload identities is
     a separate, opt-in feature (risk/location conditions, Workload Identities
     Premium licensing —
     <https://learn.microsoft.com/entra/identity/conditional-access/workload-identity>).
  2. **Accept the freeze** and re-login on the printed command — correct for
     occasional owner-driven sessions.
  3. **Never**: excluding the ops account from CA or relaxing sign-in frequency
     tenant-wide to comfort one container — that trades a policy doing its job for a
     standing hole.

## Security defaults vs Conditional Access

Security defaults are the free baseline (MFA registration for all users, blocking
legacy auth, MFA for privileged actions); Microsoft auto-enables them for eligible
tenants that have **no Conditional Access policies**
(<https://learn.microsoft.com/entra/fundamentals/security-defaults>). They are a
package deal — no per-app, per-user, or session-lifetime tuning. A tenant that needs
granular control (this one demonstrably runs CA with sign-in frequency — the
`AADSTS50078` event) graduates to Conditional Access and disables security defaults;
the discipline when doing so is to **recreate the baseline deliberately** (MFA for
all, block legacy auth) before adding the granular policies, because disabling
defaults removes those protections in the same click. Managing either requires at
least **Conditional Access Administrator** (same page).

## Break-glass hygiene

CA plus MFA means lockout is a real failure mode — the same account that hit
`AADSTS50078` in the container is the account that would have to fix a bad CA policy.
Microsoft's guidance
(<https://learn.microsoft.com/entra/identity/role-based-access-control/security-emergency-access>):
maintain **emergency-access (break-glass) accounts** that are cloud-only
(`*.onmicrosoft.com`, not federated), excluded from Conditional Access policies,
using phishing-resistant credentials (FIDO2/passkey rather than a shared password in
a drawer), with sign-ins **alerted on** — any use of a break-glass account is an
incident by definition. Verify them on a schedule; an untested break-glass account is
a hope, not a control. Tenant-custody rule applies: creating them is an owner action;
nothing in this repo stores or references their credentials.

## Access tiers for the ops automation (the upgrade path)

The honest current model: the operations container rides the **owner's own user
session** — full owner permissions when fresh, `AADSTS50078` freezes when stale, and
every action audits as the human. The upgrade that removes both the fragility and the
over-grant is a **dedicated workload identity** (`helios-ops-automation` — created by
`setup-tenant.ps1 -OpsIdentity`, dry-run by default like everything else). Three
tiers, each an explicit owner grant (role IDs verified against
<https://learn.microsoft.com/azure/role-based-access-control/built-in-roles>):

| Tier | Grants (role @ scope) | What it enables / what breaks if narrower |
|---|---|---|
| **READ** | `Reader` (`acdd72a7-3385-48ef-bd42-f606fba81ae7`) @ `rg-helios-ai` | Inventory and drift checks (`az resource list`, `what-if` needs more — see WRITE). Narrower (single-resource Reader) breaks RG-wide inventory. |
| **WRITE** (default) | `Contributor` (`b24988ac-6180-42a0-ab88-20f7382dd24c`) @ `rg-helios-ai` + `Key Vault Secrets Officer` (`b86a8fe4-44ce-4948-aee5-eccb2c155cd7`) @ `kv-helios-jcut` | Deploy `infra/main.bicep` and write provider secrets — the same two grants as the deployed `helios-github-deploy` identity, for the same reasons (`IDENTITY_ARCHITECTURE.md` §3: Contributor cannot assign roles; the vault is RBAC-mode so secret writes need the data-plane role). |
| **ADMIN** | WRITE + `User Access Administrator` (`18d7d88d-d35e-4fb5-a5c3-7773c20a72d9`) @ `rg-helios-ai` | Lets automation grant/revoke roles inside the RG (e.g. wiring a new MI to Key Vault without an owner click). **Risk stated plainly: UAA means the identity can re-grant itself or others access — a compromised ADMIN-tier credential can escalate within the RG.** Default to WRITE; take ADMIN only when the owner accepts that, which is why `-Apply -Tier admin` additionally requires `-AcceptAdminRisk`. |

All tiers also get **`Azure AI User`** (`53ca6127-db72-4b80-b1b0-d745d6d5456d`) on the
Foundry account — the data-plane role the templates already use for the operator
(`infra/modules/ai-foundry-account.bicep:29-30`), so Foundry calls ride the same Entra
identity instead of a key.

**Credential for a non-OIDC container** (no GitHub OIDC token to exchange):

- **Preferred: certificate credential, generated into Key Vault** — the private key
  never exists as an env var or repo file. Shapes verified against
  <https://learn.microsoft.com/cli/azure/keyvault/certificate>,
  <https://learn.microsoft.com/cli/azure/ad/app/credential>, and
  <https://learn.microsoft.com/cli/azure/azure-cli-sp-tutorial-3>:
  `az keyvault certificate create --vault-name kv-helios-jcut --name helios-ops-automation --policy @<self-signed policy>`
  (default policy from `az keyvault certificate get-default-policy` is self-signed),
  then attach with
  `az ad app credential reset --id <appId> --cert helios-ops-automation --keyvault kv-helios-jcut --append`.
  The container then retrieves and logs in
  (<https://learn.microsoft.com/cli/azure/authenticate-azure-cli-service-principal>):
  `az keyvault secret download --file ops-cert.pfx --vault-name kv-helios-jcut --name helios-ops-automation --encoding base64`,
  `openssl pkcs12 -in ops-cert.pfx -passin pass: -passout pass: -out ops-cert.pem -nodes`,
  `az login --service-principal --username <appId> --certificate ops-cert.pem --tenant 349e1399-dccf-45b1-af7e-05d7b0676abf`
  — then delete both files; they are a materialized credential while they exist.
- **Acceptable: client secret held only in Key Vault**, expiry set, rotation owner
  named (`IDENTITY_ARCHITECTURE.md`'s "last resort" row). Never in files, `.env`s, or
  CI variables.

Every grant above is an **owner action** — `setup-tenant.ps1 -OpsIdentity` *is* the
grant script (dry-run prints each `az role assignment create`; `-Apply` executes with
the bounded PrincipalNotFound retry, because RBAC is eventually consistent).

### Non-Azure surfaces — grant table (clicks and key issuance, not az)

| Surface | Write today | Admin upgrade (owner clicks) |
|---|---|---|
| **GitHub** | The session's existing token already holds repo write | Rulesets/administration: a **fine-grained PAT with repository "Administration" read/write** (or a GitHub App with the Administration permission) for `scripts/github/apply-rulesets.ps1`; Projects v2 remains **classic PAT `project` scope**, passed at run time and never stored (`.claude/skills/github-control/references/auth-topology.md`) |
| **Codex / OpenAI** | Codex cloud already holds repo write through its GitHub connection — evidence: commit `118aaea` landed on PR #10 via `@codex` (`.claude/skills/openai-codex/references/codex-surfaces.md:20-23`) | API write access *is* the key: issue `OPENAI_API_KEY` at platform.openai.com → custody as Key Vault secret `openai-api-key` (`ENTERPRISE_AI_CONNECTIONS.md` §5); no separate admin tier exists to grant |
| **M365 Copilot** | claude.ai M365 connector = read-only lane (`references/m365-copilot-tools.md`, "M365 MCP read lane") — review its scopes in the claude.ai connector settings as the session-side write surface before widening anything | The Graph application permissions + admin consent + upload steps already in `integrations/m365/README.md` (cross-ref — not duplicated here); consent tier per the table above (Privileged Role Administrator for the Graph app roles) |

## M365 admin center surfaces (names only — every one is an owner click)

- **Integrated apps → Upload custom app** — the declarative-agent package upload
  (<https://learn.microsoft.com/microsoft-365/admin/manage/test-and-deploy-microsoft-365-apps>).
- **Settings → Search & intelligence → Data sources** — enabling the
  `heliosplatform` connection for Copilot after Graph-side registration
  (<https://learn.microsoft.com/microsoft-365/copilot/connectors/overview>).
- **SharePoint admin center** — site/sharing governance over the verified
  `…/HELIOS/Governance/` corpus
  (<https://learn.microsoft.com/sharepoint/get-started-new-admin-center>).
- **Billing → Licenses** — Microsoft 365 Copilot is a per-user add-on seat; the
  declarative agent's non-`WebSearch` capabilities require it on the *user's* side
  (<https://learn.microsoft.com/copilot/microsoft-365/microsoft-365-copilot-licensing>;
  capability rule in `references/graph-and-copilot.md`).

## Purview (portal side)

The **Microsoft Purview portal** (purview.microsoft.com) is the unified home of the
M365-licensed governance solutions
(<https://learn.microsoft.com/purview/purview-portal>). Distinct from it: an **Azure
`Microsoft.Purview/accounts` resource** (Data Map, scheduled scans of Azure sources)
is an ARM deployment — that is the opt-in `deployPurview` lane designed in
`docs/architecture/GOVERNANCE_PURVIEW_FABRIC.md`, which already judges M365 Purview
"likely sufficient at current scale". Same brand, two planes; don't provision the
Azure account to do what the portal already does
(<https://learn.microsoft.com/purview/data-governance-overview>).

- **Sensitivity labels** flow: create the label, **publish it via a label policy** to
  users/groups, then it becomes applicable — manually by users, or automatically
  (<https://learn.microsoft.com/purview/sensitivity-labels>).
- **Auto vs manual labeling**: auto-labeling policies label at rest service-side
  (SharePoint/OneDrive/Exchange) and run in **simulation mode first** — review
  matches before turning enforcement on; client-side auto-labeling recommends/applies
  in Office apps as users work
  (<https://learn.microsoft.com/purview/apply-sensitivity-label-automatically>).
  The SharePoint governance tree labeling in `GOVERNANCE_PURVIEW_FABRIC.md` ("M365
  side") is exactly this lane, and matters because that tree is Copilot grounding
  material — labels flow into what Copilot will surface.
- **DLP for Copilot**: a DLP policy scoped to the *Microsoft 365 Copilot* location
  can exclude items carrying chosen sensitivity labels from Copilot/Copilot Chat
  processing when generating responses
  (<https://learn.microsoft.com/purview/dlp-microsoft365-copilot-location-learn-about>;
  DLP fundamentals: <https://learn.microsoft.com/purview/dlp-learn-about-dlp>) — the
  enforcement backstop for "label it internal and Copilot respects it".

## Tenant custody recap

Unchanged and non-negotiable (`SKILL.md`, hard rules): **tenant mutations are owner
actions** — consent grants, app registrations, connection creation, app uploads, role
assignments, label policies. Automation and agents may read when authorized (the M365
MCP lane; `az` probes); `setup-tenant.ps1` encodes the boundary as dry-run-by-default
with `-Apply` reserved for the owner's own session, and the `m365-admin` agent
(`.claude/agents/m365-admin.md`) is forbidden from ever passing `-Apply`.
