# HELIOS program

One page for the whole project: what is connected, what is running, what comes next, and the
short list only you can do. Refreshed at every merge.

Connecting for the first time? [CONNECT.md](CONNECT.md) is the one command and the five things
it asks you for. To see where you stand right now, without changing anything:

```bash
bash scripts/bootstrap/connect.sh --status     # or: pwsh scripts/bootstrap/connect.ps1 -Status
```

## What only you can do

1. **Type a GitHub code**, printed by `bash scripts/bootstrap/connect.sh` in Azure Cloud Shell.
2. **Click "Create", then "Install"**, on the GitHub App page it opens. After this the
   workflows mint their own credentials for every run and no code is needed again.
3. **Paste the API keys you want**, at a hidden prompt: OpenAI, Anthropic, GitHub Models.
   Azure OpenAI, Claude on Foundry and Foundry need no key — they use your Azure sign-in.
4. **Type a Codex code**, printed by the same command.
5. **Confirm the repository is connected** at chatgpt.com/codex settings, which is what makes
   Codex review every pull request. It already is; the script only checks.

Optional, and only if you want the lane: the two connector secrets (`LINEAR_API_KEY`,
`SLACK_WEBHOOK_URL`) plus turning Linear's own GitHub issue sync **off** for team JOH;
`copilot login` and `claude setup-token` on a machine with a browser; Microsoft 365 tenant
consent; the burst fleet deployment, which costs money and waits for your word.

## Where every connection stands

Every row is a lane of the one connect command, so the table and the script never drift.

| Surface | State | In place | Left |
| --- | --- | --- | --- |
| GitHub + `gh` CLI | done | App manifest flow, per-run App token in the governance workflows, personal-token fallback, OIDC to Azure, labels and milestones reconciled from manifests, the review-loop stopping rule, Codex cloud reviews on every pull request | Your App approval — until it exists nothing that needs repository administration applies itself, and the deploy workflow refuses rather than deploying through an unprotected environment. Custom rulesets, Projects manifests and fork sync return with the rest of the control lane. |
| Azure + Key Vault | needs you | Foundry stack in Bicep with ARM and Terraform mirrors, Key Vault under role-based access, an OIDC identity for the workflows, `azure-up` writing `.helios/azure.env`, vault-backed provider secrets by name, the operations identity script | One Cloud Shell run stores the keys and mints the operations identity. The burst pool stays a printed preview until you say deploy. |
| Foundry (Claude and OpenAI models) | done | The `anthropic-foundry` and `azure-openai` providers over Entra with no key, Claude deployments declared as data, `Connect-ClaudeFoundry.ps1`, the owner-dispatched Foundry review workflow | The `CLAUDE_AZURE_*` variables are set by the connect run. |
| ChatGPT / Codex | done | Cloud reviews (code and security) on every pull request, the `codex` command line as a hub lane, the `openai` and `openai-codex` API providers, Codex's configuration written by script, HELIOS's own 24 tools registered *into* Codex | An OpenAI key lights the API lane; the command-line sign-in is one code in the connect run. |
| Claude | done | API provider, Foundry provider, the Claude Code plugin and its 24 governed tools, an instruction file kept in step with Copilot's and Codex's | `claude setup-token` on a machine you use, only if you want that lane there. |
| GitHub Copilot | needs you | Coding-agent dispatch by label, custom instructions, review requests wired | The monthly review quota is spent until it resets. Raise the budget or wait. |
| Workspaces (editor + assistants) | done | The `helios` tool server and the Playwright browser server registered three ways — `.mcp.json` for Claude Code, `.vscode/mcp.json` for VS Code and Copilot, Codex's own config — plus the themed workspace file and the Codespaces devcontainer | Build once (`dotnet build HELIOS.sln -c Release`) so an assistant starts the tools instantly. |
| Microsoft 365 | needs you | Graph connector schema, declarative agent manifest, tenant setup script with a clean preview, Purview and Fabric design records | Administrator consent and the connector enable are tenant writes only you can make. |
| Linear + Slack | needs you | Both workflows read one routing table, honour an `enabled: false` switch, and skip green without their secret; the Linear project and milestones are mirrored; the Slack channels exist with a status post | Two repository secrets by name, and the Linear sync switch. |
| The hub (C#, F#, C++, Python, PowerShell) | done | Routing with the language dimension, tandem and compare, a learning store both local and in Azure with bounded reads, the F# score, the C++ online learner, the Python spoke, PowerShell wrappers, per-language reviewer agents and knowledge packs | Fleet learning v2 is queued. |
| Fleets (Xcore-9 and Hermes) | done | Topology, local fleet up / seed / learn / down, the burst module with a clean preview, Hermes installers, fleet status through the tool set | Burst deployment on your word. Hermes lanes are stubs until its command line is installed on a host. |
| Config authoring | done | JSON Schemas for every manifest, one map, editor bindings, templates, the `helios_config_validate` tool, a required CI job | Merged in #252, after fourteen review rounds. |
| Desktop shell (WinUI 3) | rebuild | The theme tokens and the metrics seam are merged | Phases three to six lived only in a session container and were lost when it restarted. They are rebuilt from the design documents; the Windows build stays your step. |

## Done and merged

Each one gated the same way: build, the full test suite, the Python spoke, a stack smoke test,
an instruction-drift check, a parser sweep, and a secret scanner.

| Pull request | What it delivered |
| --- | --- |
| #208 | Control fabric: governance applied from manifests, branch pruning, one-command bring-up, workstation surfaces, instruction files |
| #215 | Claude on Microsoft Foundry: the provider, Claude deployments as data, the PowerShell mirror, command-line and fallback-chain fixes |
| #236, #241 | Access control: the GitHub App manifest flow, per-run App tokens, one-sitting device logins, Hermes installers |
| #244, #246 | Getting started and organization: the beginner's guide, wiki publishing with link rewriting, browser automation, label and milestone manifests |
| #248 | Coverage: the language dimension in routing and learning, the validation sweep as a required job, an analyzer gate, reviewer agents |
| #250 | Knowledge v2 and the absorption front door: deep per-language references, the unity skill with cost and combination reasoning |
| #252 | Configuration schemas validated by three engines that must agree, the `helios_config_validate` tool, authoring templates, the themed workspace, and one command that connects everything |
| #255 | The offline contract suite for both connect twins, the verdict table that renders a review when no reviewer is available, and a real fix for the red code-quality check |
| #257 | Protected environments as the deployment authority: the manifest, the apply script and its 67-case suite, the governance item that reconciles it from `main`, and the main-only pin that naming an environment had quietly spent |

## Up next, in order

1. **Your one GitHub step** — `pwsh scripts/bootstrap/connect-github-app.ps1 -Repository
   Yolkster64/helios-platform -DispatchGovernance`, from your own machine. Nothing that needs
   repository administration can apply itself until this exists: the `production` environment
   is absent, the `main` ruleset is uncreated, and Governance Apply correctly withholds
   `-Apply` from all three admin items. Until you run it, `helios-deploy.yml` **refuses to
   deploy** rather than running through an environment that gates nothing.
2. **GitHub control and identity, the rest** — custom rulesets, fork sync, Projects and wiki
   manifests, Cloud Shell persistence, fleet host identity. Deployment environments landed in
   #257; the remainder is rebuilt from the recorded design.
3. **Desktop shell phases three to six, rebuilt** — the routing and fleet pages, effects, and
   the settings page. The Windows build is your step.
4. **Fleet learning v2** — a vector learning store (decision record first), a code-survey
   ranking task, sandboxes, and a command-line upgrade pass.
5. **Absorption cadence** — scheduled benchmarks with verdicts on the epics, and dashboard
   sections.

## The whole scope

| Epic | What it covers |
| --- | --- |
| [#223](https://github.com/Yolkster64/helios-platform/issues/223) | Onboarding foundation: guide, lanes, board, pull-request backlog |
| [#234](https://github.com/Yolkster64/helios-platform/issues/234) | GitHub and Azure full access: admin authority, OIDC, vault, operations identity |
| [#242](https://github.com/Yolkster64/helios-platform/issues/242) | Coverage matrix: five languages, infrastructure formats, Microsoft 365, fleets, connectors, learning, Foundry |
| [#235](https://github.com/Yolkster64/helios-platform/issues/235) | Cross-model combination learning, live, with the fleets |
| [#109](https://github.com/Yolkster64/helios-platform/issues/109) | The governed review and merge pipeline |
| [#112](https://github.com/Yolkster64/helios-platform/issues/112) | Per-provider metrics and the themed desktop shell |
| [#115](https://github.com/Yolkster64/helios-platform/issues/115) | Absorption and learning cadence |
| [#137](https://github.com/Yolkster64/helios-platform/issues/137) | PowerShell hygiene, in seven batches |
| [#156](https://github.com/Yolkster64/helios-platform/issues/156) | Canonical cutover to helios-control; the rename is yours |
| [#247](https://github.com/Yolkster64/helios-platform/issues/247) | Label and milestone manifests for organization governance |

## Known gaps, said plainly

- **The ChatGPT project cannot be read from a hosted session.** `chatgpt.com` answers 403 to
  anything but your own browser, and the Codex sign-in does not carry that access. Export it
  once, or paste the parts that matter into `docs/imports/chatgpt/raw/`; every piece is then
  recorded in `docs/imports/chatgpt/README.md` with where it landed.
- **Two prepared changes were lost with a session container** — the GitHub control and identity
  lane, and desktop-shell phases three to six. Nothing pushed was lost; both are rebuilt from
  the design documents rather than pretended away.
- **Azure DevOps is not configured** and nothing in this repository consumes it. That is the
  honest status, not an omission.
- **Hermes lanes are stubs** until its command line is installed on a host; the fleet runs
  XCore pools locally today.

## The rules this project works under

No secrets in the repository: configuration carries the *name* of an environment variable or a
Key Vault secret, never a value. No assistant, connector or bot can approve a production
deployment; GitHub's protected environments remain the deployment authority, and the deploy
workflow now *checks* that rather than asserting it — a job in front of the deployment reads
the live environment and refuses unless a reviewer is required, failing closed on every way of
not being able to tell. Nothing is
renamed, deployed, or granted permission without your word. Every change is reviewed before it
merges, and a change that cannot pass its gate does not merge.
