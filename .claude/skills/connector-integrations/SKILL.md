---
name: connector-integrations
description: Linear and Slack integrations for HELIOS — the config/connectors.json routing table, the linear-sync and notify-slack workflows, their skip-green gates and secrets custody, the team-John sync-loop history, plus the SharePoint pointer into microsoft-ecosystem and the honest Azure DevOps status. Use for ANYTHING involving "linear", "slack", "webhook", "issue sync", "notify", "connector", "connectors.json", "LINEAR_API_KEY", "SLACK_WEBHOOK_URL", "sharepoint sync", "azure devops", or "ado".
---

# Connector integrations (Linear, Slack; SharePoint pointer; ADO status)

Two connectors are live today, and both are GitHub Actions workflows reading one
routing table. There is no connector service in `src/` — the `$comment` in
`config/connectors.json:2` says the file is read by the workflows today and by
`HELIOS.Connectors` only "when it lands"
(`docs/architecture/ROADMAP_MULTI_LLM.md:31-34`, PR4). Do not cite that service
as existing.

## The two live connectors

| Connector | Actions secret | Workflow | Config block |
|---|---|---|---|
| Linear issue sync | `LINEAR_API_KEY` | `.github/workflows/linear-sync.yml` | `linear` (`config/connectors.json:22-36`) |
| Slack notifications | `SLACK_WEBHOOK_URL` | `.github/workflows/notify-slack.yml` | `slack` (`config/connectors.json:3-21`) |

- **Linear** mirrors sync-labeled GitHub issues into team `JOH`, one-directional
  (GitHub is the source of truth): `"[GH-{number}] "` title prefix, label mapping per
  `githubLabelToLinear`, close/reopen moves the Linear workflow state, and a
  comment-back links the mirror (`linear-sync.yml:1-9,156-167`).
- **Slack** posts CI/deploy outcomes on `workflow_run` completion of the six
  workflows it lists, filtered per-workflow by `slack.notifyOn` (`always` vs
  `failures-and-recovery`) — `notify-slack.yml:12-21,50-58`.

## Contracts that hold everywhere

- **Skip-green gates**: without its secret, each workflow prints a pointer to
  `config/connectors.json` and exits 0 — `linear-sync.yml:50-53`,
  `notify-slack.yml:45-48`. Neither can ever be the red check
  (`docs/architecture/CONNECTIONS_SETUP.md:187-189`), so a green run proves
  nothing until you read its log.
- **Secrets custody**: `config/connectors.json` carries env-var NAMES only
  (`config/connectors.json:2`; CLAUDE.md "No secrets in the repo" hard rule).
  Values are Actions secrets, set once by the owner: `gh secret set
  LINEAR_API_KEY` / `gh secret set SLACK_WEBHOOK_URL`
  (`docs/architecture/CONNECTIONS_SETUP.md:200-201`).
- **Routing changes are config edits, never workflow edits**
  (`docs/architecture/CONNECTIONS_SETUP.md:201`): team key, title prefix, sync
  labels, label map, channels, and notify policy all live in
  `config/connectors.json`; both workflows sparse-checkout only `config/`
  (`linear-sync.yml:33-36`, `notify-slack.yml:31-34`).
- **Declared but unconsumed**: `slack.botTokenEnv` names `SLACK_BOT_TOKEN`
  (`config/connectors.json:6`), but nothing in this repo consumes it today — it
  is reserved for the future `HELIOS.Connectors` service
  (`docs/OWNER_START_HERE.md:76`). Never claim bot-token functionality exists.

## Depth

`references/linear-slack.md` — the connectors.json schema walk, both workflows'
full behavior and skip/failure modes, the Linear GraphQL surface actually used,
the team-John sync-loop history (duplicates #54–#93) with the owner click-path,
and the verification recipes from the owner checklist.

`references/sharepoint-devops.md` — what the SharePoint/M365 surface really is
(and which steps are owner-gated), plus the honest Azure DevOps status: nothing
is configured today, and what wiring an ADO org would touch.

## SharePoint — don't duplicate, point

SharePoint/M365 knowledge belongs to `.claude/skills/microsoft-ecosystem`
(API-level facts in its `references/graph-and-copilot.md`) and to
`integrations/m365/README.md` (Graph connector + declarative agent + the
owner-action runbook). This skill only maps where connector-flavored asks land —
see `references/sharepoint-devops.md`, which also gives the honest reading of
`scripts/microsoft-enterprise/m365/sharepoint-setup.ps1`.

## Azure DevOps — honest status

No ADO integration exists in this repo: no workflow calls `dev.azure.com`, no
`config/connectors.json` entry, no wiring script. Existing mentions are
incidental (installer config templates, option lists in docs) — the inventory
and the design-forward notes live in `references/sharepoint-devops.md`. Never
fabricate ADO capability; "nothing is configured" is the correct answer today.

## Diagnose vs set up

- **Verify / diagnose** → `scripts/bootstrap/auth-doctor.ps1`. Its connector
  lanes (linear, slack, sharepoint, azure-devops) are verify-only: env vars are
  checked by NAME only, nothing is mutated, values are never printed, and owner
  fixes are reported as exact commands rather than run. Use these lanes first
  when a connector "doesn't work".
- **Set up / repair** → the owner runbook:
  `docs/architecture/CONNECTIONS_SETUP.md:185-211` (secrets, routing, the
  Linear-side setting) and its checklist verification rows (lines 300-301). Secret
  creation, Linear workspace settings, and tenant consent are owner actions —
  relay them, never attempt them.
- Day-to-day operations (run-log interpretation, routing honesty, the delegable
  runbook steps) belong to the `connector-steward` agent
  (`.claude/agents/connector-steward.md`); credential-lane diagnosis and repair
  belong to `auth-broker` (`.claude/agents/auth-broker.md`).

## MCP reality check

Linear and Slack MCP tools seen in operator sessions are claude.ai session
connectors on the operator side — they are not part of this repo. The repo-side
MCP server is `src/mcp/HELIOS.Mcp` (the only server `.mcp.json:2-8` registers),
and its tools are the ai/status/azure/foundry set — `src/mcp/HELIOS.Mcp/`'s
`HeliosAiTools.cs`, `HeliosStatusTools.cs`, `HeliosAzureTools.cs`, and
`HeliosFoundryTools.cs` define no connector tools. Don't point connector work
at the repo MCP server.
