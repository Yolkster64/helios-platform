# HELIOS plugins: one project, every client

Use the existing HELIOS C# MCP server for project context, AIHub routing, Fabric
plans and handoffs. Each person signs into their own client once. The repository
provides the setup; installing a package does not transfer credentials or enable
another person's account.

For the usual checkout workflow, start with `./connect.sh workspace` or
`./connect.ps1 workspace`. The Codex plugin below is an optional way to package
the same tools for a team's plugin catalog.

| Client | Repository connection | Verify after setup |
| --- | --- | --- |
| Claude Code | Root `.mcp.json`; optional existing `plugins/helios-operator` skill and agent | `/mcp`, then call `helios_fabric_plan_get` |
| Codex | Existing repo MCP configuration, or **HELIOS Connect** below | MCP tools show one HELIOS registration; call `helios_fabric_plan_get` |
| VS Code / Copilot | `.vscode/mcp.json` | Enable HELIOS in the agent tool picker; call a read tool |
| Copilot CLI | Project `.mcp.json` | Trust the project MCP server and inspect its available tools |
| Copilot cloud agent | Repository Settings → Copilot → MCP servers | Configure and test the hosted agent separately |
| ChatGPT | Shared HTTP `/mcp` connection, registered in Plugins | Add it to a new conversation and call `helios_project_get` |

The Claude and IDE steps are in [Client setup](CLIENT_SETUP.md). Copilot CLI
reads project MCP configuration, while the GitHub cloud agent uses repository
settings. For that hosted agent, allow only the required tools and use its
`COPILOT_MCP_` secrets or variables when needed. Local sign-ins do not activate
the hosted agent. See [Copilot CLI MCP](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-mcp-servers)
and [Copilot cloud MCP](https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/configure-mcp-servers).

## Install HELIOS Connect in Codex

Prerequisites: a reviewed HELIOS checkout, .NET 10 SDK, `python3` on PATH, and
a Codex client with plugin support. On Windows, if Python is available only as
`python` or `py`, use `./connect.ps1 codex` with the existing MCP configuration.

1. Make `HELIOS_REPO_ROOT` available to the process launching Codex, using the
   absolute path to your trusted checkout. From that checkout in a terminal:

   ```bash
   export HELIOS_REPO_ROOT="$PWD"
   codex plugin marketplace add .
   codex plugin marketplace list
   ```

   PowerShell equivalent:

   ```powershell
   $env:HELIOS_REPO_ROOT = (Get-Location).Path
   codex plugin marketplace add .
   codex plugin marketplace list
   ```

   Terminal environment settings reach processes launched from that terminal.
   A separately launched desktop app also needs this variable in its launch
   environment; restart it after configuring the variable.

2. In the ChatGPT desktop app's Plugins Directory, choose **HELIOS Workspace**
   and install **HELIOS Connect**. The catalog is in
   `.agents/plugins/marketplace.json`; its internal name is `personal` and its
   source resolves from the repository root to `./plugins/helios-connect`.
   The preceding `marketplace add .` registers this explicit repository catalog;
   committing the file alone does not install it for other teammates.

3. Use **one HELIOS MCP registration per client**. This repository already has
   a direct Codex registration. Either keep that working setup and leave this
   plugin disabled, or disable the direct `mcp_servers.helios` registration in
   your local Codex configuration before enabling the plugin. Do not distribute
   that personal choice as a change to the team's default config.

4. Start a new Codex conversation. Confirm its MCP tool list has one HELIOS
   server, then ask it to call `helios_fabric_plan_get`. Inspect the returned
   readiness report before enabling any provider or deployment action.

Each teammate repeats installation against their own reviewed checkout. After
the catalog is published, `codex plugin marketplace add Yolkster64/helios-platform`
can register the GitHub source instead; `HELIOS_REPO_ROOT` still selects that
person's checkout. Do not register both local and GitHub copies of the catalog.
If `personal` already names another configured marketplace, keep the direct MCP
setup until the catalog-name collision is resolved explicitly.

These steps follow OpenAI's [plugin packaging and marketplace workflow](https://developers.openai.com/plugins/build/plugins).
The package uses the supported `.codex-plugin/plugin.json` compatibility format.
It contains no credentials, hooks, copied server or invented ChatGPT app ID.

## Connect this project to ChatGPT and Claude

Follow [Remote bridge](REMOTE_BRIDGE.md) to start the shared HTTP server and
configure an approved HTTPS endpoint or Secure MCP Tunnel. Local loopback alone
is not reachable by ChatGPT's cloud. Configure the Entra scopes and client
consent described there for an authenticated deployment.

In ChatGPT, open **Settings → Security and login → Developer mode**, then
**Plugins → plus**. Enter HELIOS's name and description, choose the reachable
`/mcp` URL or an available tunnel, and complete account linking. Review the tools,
then add the connection to a new conversation. Workspace policy may require an
administrator. See [ChatGPT developer mode](https://developers.openai.com/api/docs/guides/developer-mode)
and [connect and test a plugin](https://developers.openai.com/plugins/deploy/connect-chatgpt).

Connect Claude Code to that same service when it runs on another machine. Linked
worktrees can use the local MCP server and share the primary checkout's handoff
inbox; independent clones need the shared HTTP service. `helios_handoff_submit`
stores a result; the receiving client retrieves it. It does not inject a message
into an already open chat. The optional `helios_claude_ask` lane starts a fresh,
restricted Claude Code invocation using the bridge host's Claude sign-in.

A successful developer-mode registration gives a real `plugin_asdk_app...` ID.
That ID can later back a ChatGPT plugin mapping. This package has no `.app.json`
because no such live registration is claimed here. A ChatGPT sign-in also does
not create an OpenAI Platform API key; local planning and handoffs work without
one, while model providers need their own configured credentials.

## Implementation and verification

### One reusable work skill

`plugins/helios-connect/skills/helios-work/SKILL.md` is the canonical workflow
for implementation, review, hybrid planning and fleet planning. It guides task
ownership, isolated worktrees, provider choices and returned evidence. The
client uses its own native agent facilities; the shared skill does not create
accounts, start fleets or install other clients.

| Client | Shared instructions | Native execution boundary |
| --- | --- | --- |
| Codex | HELIOS Connect exposes `helios-work` through the plugin's `skills` entry | Invoke the installed skill, then use available Codex agents with explicit assignments |
| Claude Code | `/helios-work` loads the repository wrapper, which reads the canonical skill | Claude's available subagent tools run bounded work; existing `aihub-unity` supplies provider guidance |
| Copilot | Include the canonical skill file as repository context, or retrieve the shared task packet through HELIOS MCP | Use the installed editor/CLI/cloud agent's supported facilities; do not assume a Codex plugin installs in Copilot |
| ChatGPT | Connected HELIOS MCP returns the canonical instruction text and hash in a task packet | ChatGPT uses its available tools; a remote packet does not create a native subagent or wake another conversation |
| Hermes / XCore | The same packet and fleet/Fabric configuration define the proposed work | A local role or plan is advisory until the actual executor returns a runtime receipt |

After updating a client connection, inspect its tool list. When advertised,
`helios_agent_catalog_get` reads configured roles and tasks, and
`helios_task_packet_get` accepts `taskKind` (`implement`, `review`, `hybrid-plan`
or `fleet-plan`) plus optional `language`. Both are read-only and perform no
dispatch or inference. The packet carries the canonical instruction path, text
and SHA-256. Use the current schema and report missing tools explicitly; an
older running server does not acquire new tools just because the code changed.

Use `AGENTS.md` for repository authority and [Agent workspaces](../AGENT_WORKSPACES.md)
for the actual workspace helper. Linked worktrees share the local handoff store;
independent machines use the configured HTTP service. Keep provider sign-ins,
application consent and deployment identity local to their approved runtimes.

### Plugin launcher

Codex runs `scripts/mcp_stdio.py` from the installed plugin's directory. The
shim requires an absolute `HELIOS_REPO_ROOT`, validates the checkout layout and
executes its existing `scripts/bootstrap/connect.py mcp` entrypoint. That entrypoint
builds with diagnostics on stderr and starts the existing C# stdio MCP server.
On Windows, the shim uses a native subprocess with inherited stdio and returns
its exit status, preserving checkout paths containing spaces. POSIX uses exec.
The shim does not depend on the current terminal directory or on unsupported
`${CODEX_PLUGIN_ROOT}` / `${CLAUDE_PLUGIN_ROOT}` substitutions. Relative plugin
`cwd` is resolved by Codex's [plugin MCP configuration code](https://github.com/openai/codex/blob/main/codex-rs/codex-mcp/src/plugin_config.rs).

Run the portable package checks from the repository root:

```bash
python3 -m unittest discover -s plugins/helios-connect/tests -v
```

These checks exercise an installed-cache launch with a spaced checkout path,
stdio cleanliness, exit propagation and invalid configuration. They do not
prove native client installation, provider authentication or HTTPS deployment;
the client tool call above verifies the actual runtime connection.
