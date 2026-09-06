# HELIOS MCP Server — Client Setup

One tool surface for every agent. The HELIOS MCP server (stdio) exposes the multi-LLM hub
(`helios_ai_ask`, `helios_ai_route`, `helios_ai_tandem`, `helios_ai_compare`,
`helios_ai_status`, `helios_providers_list`, `helios_optimal_provider_get`,
`helios_task_routing_get`, `helios_engine_catalog_get`, `helios_engine_mix_recommend`,
`helios_infra_validate`, `helios_azure_inventory_get`, `helios_auth_status_get`,
`helios_fleet_plan_get`, `helios_fabric_plan_get`, `helios_foundry_agent_list`,
`helios_foundry_agent_create`,
`helios_operator_profile_get`, `helios_operator_profile_save`,
`helios_operator_context_sync`, `helios_operator_next_steps_get`) to any MCP
client, so Claude Code, GitHub Copilot, Codex CLI, and Cursor all drive the same providers
with the same routing table. This is the cross-LLM fabric: each assistant can delegate to
whichever model is best for the task.

Prereqs: .NET 10 SDK; provider keys in the environment (see `.env.template`). Build once
with `dotnet build HELIOS.sln -c Release`.

## Claude Code

Already wired: `.mcp.json` at the repo root is picked up automatically when you open this
repo. Verify with `/mcp`.

For the packaged skill and specialist agent, test the checked-out plugin directly:

```bash
claude --plugin-dir ./plugins/helios-operator
```

Or install it from the repository marketplace after it reaches the default branch:

```text
/plugin marketplace add Yolkster64/helios-platform
/plugin install helios-operator@helios-platform
```

Choose project scope, then invoke `/helios-operator:operate-helios` or mention
`@helios-operator:fabric-operator`. The plugin adds the skill and agent only — the MCP
server itself still comes from the repo-level `.mcp.json`, so enabling the plugin does
not produce duplicate `helios_*` tools or a second server process.

Fewer permission prompts: `.claude/settings.local.json.example` allowlists the read-only
commands a HELIOS session repeats (`az account show`, `az keyvault secret list` (names,
never values), `gh repo view` / `gh pr list` / `gh pr view` / `gh run list` /
`gh ruleset list`, `dotnet build` / `dotnet test`, and the verify scripts plus the auth
doctor, each named by file). Claude Code matches these entries as command prefixes, which
is why the list is shaped the way it is: `gh api` is absent because a `-X POST` or
`-f field=value` after the prefix would ride through unprompted; anything that prints a
credential (`az account get-access-token`, `gh auth status`, `gh auth token`) is absent so
a token never lands in a transcript without a prompt; the verify scripts are listed by
file name rather than `scripts/verify/*` so a `../` path cannot reach a script that
mutates. The one entry that changes local state is the auth doctor, whose `-Apply` only
re-runs non-interactive `az` logins. Copy the example to `.claude/settings.local.json`;
it is personal and must never be committed: `.gitignore` lists that exact file name
(the `.example` stays tracked), so `git check-ignore -q .claude/settings.local.json`
succeeds — if it ever stops doing so, restore the entry before committing. Claude Code
merges it with the project's `.claude/settings.json`, whose deny list still wins.

## VS Code / GitHub Copilot

`.vscode/mcp.json` in this repo registers the server for Copilot agent mode:

```json
{
  "servers": {
    "helios": {
      "type": "stdio",
      "command": "dotnet",
      "args": ["run", "--project", "src/mcp/HELIOS.Mcp", "-c", "Release"],
      "env": {
        "HELIOS_REPO_ROOT": "${workspaceFolder}"
      }
    }
  }
}
```

Open the repo folder (or `workspace.code-workspace`), then enable the tools in Copilot
Chat's agent mode (Tools picker → MCP: helios). The Codespaces devcontainer ships the
same file.

## Codex CLI

Codex starts MCP servers from its own working directory, so its config needs the
absolute project path. Render it instead of hand-editing:

```bash
pwsh scripts/bootstrap/write-codex-config.ps1            # dry run: prints the TOML it would write
pwsh scripts/bootstrap/write-codex-config.ps1 -Apply     # creates ~/.codex/config.toml
pwsh scripts/bootstrap/write-codex-config.ps1 -Apply -Force   # existing file: replaces only the helios table
```

`-Path <file>` renders elsewhere; `-Json` emits one report object. The result is a
`[mcp_servers.helios]` table with `command = "dotnet"`, the `run --project <checkout>/src/mcp/HELIOS.Mcp -c Release`
arguments, and `env = { HELIOS_REPO_ROOT = "<checkout>" }`, followed by the
`[mcp_servers.playwright]` table (see *Playwright MCP* below; `-SkipPlaywright` omits it).
Re-run after moving the checkout. Exit 0 = written or already up to date, 1 = refused (existing file without
`-Force`), 2 = `src/mcp/HELIOS.Mcp` missing. That `-Apply` run is the whole Codex
registration; verify it with `codex mcp list`, which should show `helios`.

## Playwright MCP (browser automation for all three clients)

The same second server is registered everywhere the `helios` server is, so Claude Code,
Copilot and Codex drive one browser tool: `@playwright/mcp` (pinned at `0.0.80`; bump it
in all three places together — `.mcp.json`, `.vscode/mcp.json`, and the table
`scripts/bootstrap/write-codex-config.ps1` renders). It needs Node 18+ (`npx` fetches the
pinned package on first use) and a Chromium it can launch — the devcontainer and the
agent containers already carry one.

| Client | Where | Mode |
|---|---|---|
| Claude Code | `.mcp.json` → `playwright` (`npx -y @playwright/mcp@0.0.80 --headless`) | headless: agent containers and Codespaces have no display |
| VS Code / Copilot | `.vscode/mcp.json` → `playwright` | headed, so you can watch it work |
| Codex CLI | `[mcp_servers.playwright]`, rendered next to the helios table by `write-codex-config.ps1` (`npx.cmd` on Windows); `-SkipPlaywright` leaves it out | headed; add `"--headless"` to `args` on a display-less host |

What to know before letting an agent drive it:

- The browser profile is **persistent** by default: a site you sign into stays signed in
  for the next session. That is what makes the two GitHub App clicks
  (`scripts/bootstrap/connect-github-app.ps1`) scriptable from a logged-in profile, and
  also why the profile directory must never be committed or shared. Pass `--isolated` for
  a throwaway profile.
- Nothing here holds a credential: the config carries the package name and flags only.
  A device code or an MFA prompt still needs you, whatever drives the browser.
- Verify: Claude Code `/mcp` lists `playwright`; Copilot's tool picker shows `MCP:
  playwright`; `codex mcp list` shows `helios` and `playwright` after
  `pwsh scripts/bootstrap/write-codex-config.ps1 -Apply` (`-Force` on an existing file
  replaces only the helios+playwright block).

## Cursor

`.cursor/mcp.json` (project) or `~/.cursor/mcp.json` (global):

```json
{
  "mcpServers": {
    "helios": {
      "command": "dotnet",
      "args": ["run", "--project", "src/mcp/HELIOS.Mcp", "-c", "Release"],
      "env": {
        "HELIOS_REPO_ROOT": "."
      }
    }
  }
}
```

`env.HELIOS_REPO_ROOT` is the same key `.mcp.json` (`.`), `.vscode/mcp.json`
(`${workspaceFolder}`) and the Codex table (absolute checkout path) set, so the server
resolves `config/aihub.json` from the project and not from the client's working
directory. `.` is right for the project file; in the global `~/.cursor/mcp.json` use the
absolute checkout path, as the Codex config does.

## Inspector (debugging)

```bash
npx @modelcontextprotocol/inspector -- dotnet run --project src/mcp/HELIOS.Mcp -c Release
```

## Health check

Two levels, both read-only: each launches with `dotnet run ... --no-build`, so neither
restores, compiles, or writes `bin/` / `obj/`. Build first with
`dotnet build HELIOS.sln -c Release`.

- `pwsh scripts/setup/setup-all.ps1` includes an informational `mcp-health` row: it spawns
  the client launch shape with `--no-build` appended
  (`dotnet run --project src/mcp/HELIOS.Mcp -c Release --no-build`), sends one JSON-RPC
  `initialize` over stdio with a 30 s budget, and reports `ready` (the server answered),
  `unhealthy` (it exited, returned an error frame, or stayed silent) or `skipped` (no
  `dotnet`, or no Release build yet; the detail names the build command). The row never
  changes the exit code and carries no `nextCommand`, so the `setup-everything.ps1` /
  `first-run` roll-ups never turn it into an owner action.
- `pwsh scripts/verify/stack-smoke.ps1` is the full handshake (`initialize` →
  `notifications/initialized` → `tools/list` with pagination) and checks the tool names
  against this document name-for-name.

## Tool surface & safety

All tools are non-destructive. `helios_ai_*` call LLM providers (network, token cost);
`helios_ai_status` / `helios_providers_list` / `helios_optimal_provider_get` /
`helios_task_routing_get` are pure reads;
`helios_engine_catalog_get` / `helios_engine_mix_recommend` are deterministic local reads
that separate implemented/runtime-available selections from candidates and never install
or execute candidates;
`helios_infra_validate` compiles `infra/main.bicep` locally with no subscription access;
`helios_absorb_status_get` / `helios_fleet_status_get` are read-only local reads of the
absorption watchlist and fleet run state;
`helios_azure_inventory_get` is a strictly read-only Azure management-plane inventory
(subscription, resource groups, resources via DefaultAzureCredential) — it lists and
never creates, changes, or deletes anything, and without working credentials it returns
`authenticated: false` with a fix hint (run `az login`) instead of failing;
`helios_auth_status_get` is a diagnose-only read of the auth lanes (the
GITHUB_ACTIONS/GH_TOKEN/GITHUB_TOKEN environment, one DefaultAzureCredential
management-plane token probe, and each `config/aihub.json` provider's declared
`apiKeyEnv`) — environment variables are reported by NAME and set/unset state only,
values never enter the output, missing credentials return `authenticated: false` with a
fix hint, and it repairs nothing (repair is `scripts/bootstrap/auth-doctor.ps1`);
`helios_fleet_plan_get` is a purely local advisory read: it scores each fleet pool's
configured provider chain (`config/fleet/fleet-topology.json`) against the hub's learned
routing and only reports — learned chains are NEVER auto-applied, and a missing topology
or empty learning history returns a message / engine `none` instead of failing;
`helios_fabric_plan_get` is a purely local advisory read of
`config/fabric/helios-fabric.v1.json`: it reports HC-029 checklist readiness, dependency
and rename gates, and next actions; it never performs Slack/Linear/SharePoint writes,
repository rename, OIDC/WIF changes, Azure what-if, deployment, or rollback actions;
`helios_foundry_agent_list` is a read against the Azure AI Foundry project
(DefaultAzureCredential) that reports `configured: false` with a fix hint when
`AZURE_FOUNDRY_PROJECT_ENDPOINT` is unset instead of failing.
The one explicit mutation is `helios_foundry_agent_create`: it creates a single
persistent agent on the Foundry project — parameters are validated before any network
call, exactly one create is issued per call (never retried), and nothing is deleted,
overwritten, or executed.
`helios_operator_profile_save` and `helios_operator_context_sync` write only sanitized,
gitignored files under `.helios/operator/`; Azure inventory is opt-in and uses read-only
CLI commands. The other operator tools are local reads. Context is durable per checkout,
not a cross-machine secret store, and should be refreshed before external decisions.
Deployment tools are deliberately absent from v1 — see `docs/architecture/ROADMAP_MULTI_LLM.md`.
