# HELIOS unified integration — 9 September 2026

Start at [CONNECT](../CONNECT.md). This is one canonical project and shared C# implementation with multiple clients. The current repository is `Yolkster64/helios-platform`; the proposed in-place name remains `helios-control`.

## Delivered state

| Surface | Implemented or verified | Activation still needed |
|---|---|---|
| Linear | Canonical HELIOS project: 229 existing issues, seven preserved milestones; 155 moved without changing lifecycle/content; three empty prior projects retained as completed history | Native GitHub integration settings require authenticated admin access |
| Slack | Existing control canvas updated with the four-step path and verified control/CI/deploy/fleet destinations | Bot/webhook installation and delivery receipt; no message sent |
| GitHub | Task branch preserves Claude #252; shared entry point, isolated workspaces, connector workflows and scoped validation | PR checks and review before landing |
| Claude / Codex / Copilot | Same repository instructions, AIHub routing and MCP; native login reuse; plugin/client configuration | Installed clients, their own login and repository trust |
| ChatGPT | Tool-only HTTP MCP bridge; shared durable handoffs; Workspace Agent trigger helper | Reachable registered MCP endpoint and published Workspace Agent API channel/token |
| Azure | Cloud Shell entry point; explicit target OIDC planning; Key Vault references; protected azure-dev workflow | Tenant/subscription/target identity setup and live what-if; no cloud mutation performed |
| AIHub / Hermes / XCore | Existing provider routing, comparisons, recorded-outcome learning and advisory fleet plans are exposed through the shared entry point | Runtime credentials/capacity and worker installation; prototypes do not establish live fleets |
| SharePoint / Outlook | Roles and environment references retained in the project map | Runtime Graph adapters and delegated access remain pending |

Linear: <https://linear.app/641974/project/helios-4f592efea071>
Slack: <https://helios-xk97943.slack.com/docs/T0B8Z1H0MV1/F0BGVRND8GK>

## Both directions and every workspace

Use [agent workspaces](../AGENT_WORKSPACES.md) for an independent Git branch and checkout per coding agent or teammate. This does not create user accounts, paid seats, cloud IDEs or ChatGPT Workspace Agents. No teammate identities are invented. Everyone uses the same repository and Linear project.

The [shared MCP bridge](../mcp/REMOTE_BRIDGE.md) exposes bounded project reads, immutable handoffs and an optional text-only Claude invocation. Local mode needs no Entra application. Cross-machine access uses a registered endpoint; clients do not inherit other apps' credentials.

[The return helper](../mcp/WORKSPACE_AGENT_RETURN.md) can trigger a published ChatGPT Workspace Agent and reuse a stable conversation key. Its conversation is separate from this arbitrary existing chat. A ChatGPT sign-in, a Codex login, an OpenAI model API key and a Workspace Agent token are distinct credentials.

[Plugin setup](../mcp/PLUGIN_SETUP.md) describes packaging and supported installation separately. No custom plugin or Workspace Agent is claimed installed in this chat.

## Provenance

Earlier unpublished local changes were pruned during workspace maintenance. This revision rebuilds those contracts from the published repository and recorded work, rather than claiming the lost files were recovered.

- Claude #252: includes source commit `030e23670c673df81064d9603cd752f9e5d961ae` with exact JSON-number validation and schema work budgets.
- Connector source #136: `6723fb559e929fe3fe99051ff1baf918c43d31b3`.
- Azure source #148: `5a8379174073071d87cdad46754f023e9d8565f3`.
- GUI source #186: `673e3d1680aff026250e12bc428dcd55fb2dfc98`.
- Historical M0nado #190 informs the bounded HTTP contract; its old API implementation is not copied over current C#/.NET 10.
- [Uploaded source audit](../imports/recovery/SOURCE-AUDIT-2026-09-09.md): static provenance and safe recovery mapping; recovered scripts are never executed.

## Validation and limitations

The final PR records the exact head and check results. Fresh local checks cover the entry point (25), Workspace Agent helper (17), worktree isolation, connector behavior (31), shared project plus merged upstream schemas (90), Fabric (12) and Azure deployment custody (29). The Codex plugin has six portable launch tests; Azure target tests cover 17 scenarios in each shell. Native PowerShell authentication/device suites completed 430 cases; the unchanged Python spoke completed 101 tests. These are offline/inert checks, not service-login or delivery receipts.

The .NET solution restore and Bicep command completion encountered an automatic network approval cancellation. The blocked route was not retried. Package-free C# checks exercise core bridge/process/storage behavior but do not prove SDK transport or JWT integration. The all-base PR workflow subsequently built the full solution with zero warnings/errors and passed 671 AIHub tests at `b710e92`, including actual HTTP/JWT integration. The Windows launcher tests passed at that head; Windows plugin argument handling and native GUI packaging-tool selection required follow-up fixes. Current-head checks on [PR #253](https://github.com/Yolkster64/helios-platform/pull/253) remain authoritative. Local Windows execution is unavailable.

No cloud resources, Entra registrations, RBAC roles, credentials, native app installations, Slack deliveries, model inference calls or PR merges were performed. Slack's browser requires sign-in; Linear browser inspection received an explicit URL-policy rejection. Available connected-app tools do not expose the missing administration operations.

A GitHub event follow-up is enabled: a merge of #252 verifies the event, retargets open draft #253 to main, and inspects its current-head checks. Code updates on #253 trigger a read-only handoff/CI review in ChatGPT. The active implementation agent owns repairs, preventing competing writers. The follow-up does not merge or deploy. Seven local starter worktrees were created from the published integration source; these are working directories, not running agents or cloud accounts.

## Shared agent work

The shared `helios-work` skill is packaged once for Codex, referenced by the
Claude entrypoint and `AGENTS.md`, and returned by the bounded MCP task-packet
API. `helios_agent_catalog_get` indexes existing roles/profiles/skills;
`helios_task_packet_get` prepares implement, review, hybrid-plan and fleet-plan
work with the same skill hash, default-profile routing and handoff contract.
Native execution and subagent activation remain client-specific.

[Hybrid execution](../architecture/HYBRID_EXECUTION.md) records Bicep's current
ownership, Terraform's actual coverage, identity boundaries, fleet stubs and
cross-host transport gaps. The packet carries these gaps instead of claiming
that configured pools are running.

All 15 GitHub workflows passed at `e0d39603b80cdaf2f46050290b5a547a4e774041`,
including 678 AIHub tests, the native Windows shell, Linux/Windows launcher
and plugin tests, and Bicep/Terraform validation. The later shared-catalog
addition requires its own current-head CI result on PR #253.


## Automatic start and project simplification

The existing `connect.sh` / `connect.ps1` now accepts `start --serve`: validate
public manifests, build the shared runtime, install missing coding clients using
the existing installer when PowerShell/npm are present, prepare the seven
workspaces, check existing CLI sessions, then serve the same HTTP MCP bridge.
`start --json` is the finite automation form. Missing optional services stay
visible without preventing the local core from serving. Required SDK/Python/Git
prerequisites are reported; no login or model call is hidden inside startup.

The remote source catalog exposes the maintained shared work skill, plugin and
return setup, hybrid architecture, fleet and absorption guidance through fixed
IDs. Each fetch reports a hash of the returned text, so clients can compare the
same source instead of relying on stale chat summaries. This is shared context
and transport; it does not attach to a private Claude browser session or register
a ChatGPT endpoint without the account connection.

Linear and the existing Slack canvas now lead with six linked work areas and one
next delivery. Their previous content is retained in the existing
[project history](https://linear.app/641974/document/helios-project-history-cd013339de52).
Learning and absorption stay first-class work areas. Explicit Linear Duplicate
states are preserved by the connector before any label or state mutation.
Thirty-eight exact duplicate issue pairs now use Linear's native Duplicate
relationship; their GitHub twins closed through the native integration. The
active queue decreased from 175 to 137 while all 229 records and the original
epic states/descriptions remain. The pair mapping is in the same project history.

PRs [#136](https://github.com/Yolkster64/helios-platform/pull/136) and
[#148](https://github.com/Yolkster64/helios-platform/pull/148) were closed as
superseded by #253 after verifying their implementations were retained. Closing
the standalone proposals does not claim #253 has landed. #186's missing
`nuget.config` Windows workflow trigger is restored here; its broader WinUI
provider-boundary finding remains separate work.

Claude's subsequent fixes through `2e0ab623e5dcacf81e988714f73f389eb005b814`
are incorporated with their history preserved. At inspection, #252 remained open
against main, all 13 workflows passed, and all 55 review threads were resolved.
It had not merged, so #253 stays stacked on that branch and remains a draft.

Local verification of the combined runtime: 734 AIHub tests passed, none skipped;
Release solution build: zero warnings/errors; Python spoke: 101 passed; all 15
manifests and the cutover contract passed. The combined schema suite passed 99
tests; startup, workspaces, connector and return-helper suites passed 114 tests
plus 109 subtests; the plugin suite passed six tests. They exercise inert services,
real temporary Git workspaces and termination of timed-out child processes.
Full current-head CI remains authoritative for Windows and Bicep; the available
local Bicep executable failed bundle loading.

All 16 reattached inputs match the SHA-256 values already recorded in the source
audit. Their recovery and learning intent remains preserved; no recovered script
was executed by this simplification.
