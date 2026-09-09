# HELIOS — one project, one starting point

[Work in Linear](https://linear.app/641974/project/helios-4f592efea071) ·
[Open Slack](https://helios-xk97943.slack.com/docs/T0B8Z1H0MV1/F0BGVRND8GK) ·
[Code on GitHub](https://github.com/Yolkster64/helios-platform)

Follow **Connect → Unify → Automate → Validate**. All 229 existing HELIOS issues
now belong to the same project. Their lifecycle states and history are preserved.

## Start

```bash
bash connect.sh                    # offline inventory, no credentials needed
bash connect.sh setup --connect    # existing setup and login sequence
bash connect.sh claude             # Claude Code, same project and MCP
```

Windows: replace `bash connect.sh` with `pwsh -NoProfile -File ./connect.ps1`.
Python 3.10+ runs the launcher; PowerShell 7.3+ runs its Windows wrapper.
C#/.NET 10 owns AIHub and MCP. The native WinUI control panel opens on the same
four steps and links to AI Hub and Fabric Control.

Setup uses the existing scripts and their saved state. It can install tools,
start provider login flows and repair configured lanes. Saved CLI sessions are
reused; consent/MFA remains controlled by each service. Use `connect.sh setup`
for verification only. Default `connect.sh` never starts a login, installs tools,
probes a service or reads a credential store.

## Choose a surface

| Command | What it opens or runs |
|---|---|
| `connect.sh claude` | Existing HELIOS Claude plugin and root MCP |
| `connect.sh codex` | Codex with this checkout's absolute C# MCP paths |
| `connect.sh copilot` | Copilot CLI, loading the trusted root MCP config |
| `connect.sh cloud-shell` | Existing Cloud Shell verification |
| `connect.sh cloud-shell --connect` | Cloud Shell setup, persistence and login, without inference smoke calls |
| `connect.sh ai status` | Existing AIHub provider status |
| `connect.sh ai routing` | Task/language/provider routing |
| `connect.sh learning` | Advisory fleet plan from recorded outcomes |
| `connect.sh bridge` | Shared Streamable HTTP API at `http://127.0.0.1:7078/mcp` |
| `connect.sh return` | Offline readiness for the ChatGPT Workspace Agent return path |

Open [Azure Cloud Shell](https://shell.azure.com/) and use the same checkout and
commands there. Cloud Shell still requires your Azure account and selected target.
VS Code/Copilot uses `.vscode/mcp.json`; Claude and current Copilot CLI use root
`.mcp.json`. Codex uses `.codex/config.toml`; the launcher supplies absolute paths
without replacing global user configuration. Each client keeps its own trust and
login decisions. GitHub Copilot cloud agents use the same `AGENTS.md`, issue/PR
receipts and repository contracts; no cloud agent was invoked in this setup.

## Agent workspaces and plugins

Use `connect.sh workspace create claude --agent claude`, then open the returned
worktree path. Repeat for Codex, Copilot or a teammate name. Each working area has
its own branch while sharing the same Git repository and HELIOS project.
`connect.sh workspace list` shows the registered workspaces. See
[agent workspaces](AGENT_WORKSPACES.md) for the exact setup and shared API handoffs.

[Plugin setup](mcp/PLUGIN_SETUP.md) maps the HELIOS plugin and MCP connection to
ChatGPT, Codex, Claude Code and Copilot. Installing a plugin does not transfer
other apps’ login sessions. GitHub remains the durable exchange for branches,
pull requests and code review; the shared MCP carries bounded work handoffs.

## Connect both directions

The shared API has one transport and one project, with bounded tools over the
existing C# implementation. Start it using `connect.sh bridge` on a machine that
has this checkout and .NET 10. Local mode needs no Entra registration.

Claude can connect to that endpoint with:

```bash
bash connect.sh bridge connect http://127.0.0.1:7078/mcp
```

For ChatGPT, register the reachable MCP endpoint or Secure MCP Tunnel in developer
mode, then refresh its tools. Follow [the bridge guide](mcp/REMOTE_BRIDGE.md) for
the exact server modes and OAuth settings. A shared local server is not reachable
from this cloud chat until that connection exists. Remote private access uses
Entra; a tunnel has separate Platform access requirements.

- **ChatGPT → Claude:** optional `helios_claude_ask` sends an explicit text prompt
  to a fresh bounded Claude Code invocation using the host's existing Claude login.
  Enable the documented host option once. It cannot attach a private claude.ai
  web session. Model tools and session persistence are disabled for this lane.
- **Claude → ChatGPT:** shared `helios_handoff_submit/list/fetch` tools preserve
  correlated handoffs for the other client to retrieve. For automatic triggering,
  `connect.sh return send` can deliver stdin to a published HELIOS Workspace Agent
  API channel, keeping a stable return conversation. See
  [Workspace Agent return setup](mcp/WORKSPACE_AGENT_RETURN.md).

The Workspace Agent API creates/continues its designated agent conversation;
it is not an API for appending to this arbitrary existing chat. Its access token
is separate from an OpenAI Platform model key. This setup has not created a
published channel, issued that token or registered a custom ChatGPT connection.

## Multi-model work and learning

All surfaces use `config/aihub.json`; the public project map is
`config/control-project.json`. Specialist C#, F#, C++, Python and PowerShell
modules retain their own jobs within that project.

```bash
bash connect.sh ai ask "Review this design" --provider claude-cli
bash connect.sh combo "Review this design" --providers claude-cli,codex
bash connect.sh ai tandem code_review "Review this design"
bash connect.sh learning
```

These inference commands are explicit requests that can consume the selected
accounts' usage. Inspect `ai providers` and `ai routing` first; the names must
exist in the active profile. `combo` forwards the existing compare command and
requires an explicit provider list. Tandem uses the existing task chain and
learned selection. The launcher adds no fallback or provider-selection policy.
Adaptive routing remains off by default; recorded outcomes can inform advisory
fleet plans. Hermes/XCore worker installations and hybrid capacity still need
runtime verification. Recovered training prototypes are not evidence of a fleet.

## Identity, Key Vault and service automation

Use `connect.sh auth status` for bounded native CLI authentication checks.
`connect.sh login github|azure|claude|codex` opens only the selected normal login.
Copilot prompts for `/login` in its interactive session if needed.

[Owner setup](OWNER_START_HERE.md) covers explicit Azure tenant/subscription/RG/vault
selection, a read-only OIDC plan and the existing Key Vault helpers. Workloads use
OIDC or managed identity; no long-lived Azure client secret is introduced. The
`azure-dev` environment owns deployment, with default what-if and explicit apply.
Existing Key Vault scripts keep values out of command arguments and Git. The
full setup can retrieve configured secrets into child processes; default offline
inventory cannot. Process environment changes do not propagate back to the parent
terminal automatically.

[Connector activation](architecture/CONNECTOR_ACTIVATION.md) owns GitHub → Linear
issue mirroring, loop guards and Slack failure/recovery notices. The Slack
webhook's installation selects its delivery channel. Project/canvas edits do not
prove bot delivery. Current app tools can manage the tracker/canvas, but expose
no Slack installation/webhook administration or Linear integration settings.
The Slack browser needs sign-in; Linear browser inspection was blocked by its
URL policy. Those settings were not altered.

SharePoint remains the evidence surface and Outlook the correspondence surface.
Neither is a second work queue. Their runtime Graph adapters and delegated access
still require activation; the connected ChatGPT apps do not export credentials
into Actions, local CLIs or the bridge. An empty `OPENAI_API_KEY` stays missing
regardless of ChatGPT/Codex login. Provider-key setup can be completed separately.

## Source and handoff

This branch preserves Claude PR #252 through `030e23670c673df81064d9603cd752f9e5d961ae`
and incorporates relevant original changes from #136 (connectors), #148 (Azure
preflight), and #186 (Fabric UI). The historical M0nado #190 gateway informs the
bounded HTTP contract; its older platform is not copied over the current one.
The earlier unpublished local changes were removed by workspace maintenance and
have been rebuilt from the recorded contract and published sources. Test results
in this revision are fresh; earlier counts are not used as proof for rebuilt code.

[ChatGPT context import](imports/chatgpt/README.md) accepts shared links, exports
and instructions/files with a provenance ledger. Private project links alone do
not give API access. Follow [the integration handoff](integration/HELIOS-UNIFIED-2026-09-09.md)
for exact validation and live activation state.

Official references: [OpenAI MCP connection](https://developers.openai.com/plugins/deploy/connect-chatgpt),
[Claude MCP](https://code.claude.com/docs/en/mcp),
[Copilot MCP](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-mcp-servers),
[Azure Cloud Shell](https://learn.microsoft.com/en-us/azure/cloud-shell/overview).
