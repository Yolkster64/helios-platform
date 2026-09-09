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

A GitHub event follow-up is enabled for the merge of #252: verify the event, retarget open draft #253 to main, and inspect its current-head checks. It does not merge or deploy. Seven local starter worktrees were created from the published integration source; these are working directories, not running agents or cloud accounts.
