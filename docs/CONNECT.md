# HELIOS — start once, work together

**One control plane for local and cloud work:** Claude Code, Codex, Copilot and
ChatGPT share AIHub, the same project instructions, tasks and evidence.

[Work in Linear](https://linear.app/641974/project/helios-4f592efea071) ·
[Slack start page](https://helios-xk97943.slack.com/docs/T0B8Z1H0MV1/F0BGVRND8GK) ·
[GitHub](https://github.com/Yolkster64/helios-platform)

## One command

From this checkout, on Linux, Codespaces or Azure Cloud Shell:

```bash
bash connect.sh start --serve
```

Windows uses the same command through PowerShell:

```powershell
pwsh -NoProfile -File ./connect.ps1 start --serve
```

Startup prepares the shared implementation and agent workspaces, installs missing
Claude/Codex/Copilot CLIs with the existing helper when PowerShell and npm are
available, checks saved CLI sessions without prompting, and starts the HTTP MCP bridge in the
foreground using the configured remote options (loopback by default). Keep that
terminal open. Missing optional service access is reported
separately from the local runtime. Python 3.10+, Git and the repository's .NET 10
SDK are prerequisites; startup reports a missing tool or failed build explicitly.

For automation that needs preparation and a finite result, use
`bash connect.sh start --json`. Repeating preparation reuses existing workspaces
and incremental build outputs. `bash connect.sh status` remains an offline inventory.
Neither mode calls a model or deploys infrastructure.

Fresh Cloud Shell checkout while the integration PR is open:

```bash
git clone --single-branch --branch feat/unified-connect-entrypoint https://github.com/Yolkster64/helios-platform.git helios-platform && cd helios-platform && bash connect.sh start --serve
```

The command deliberately selects the published integration branch. After it lands,
clone `main` instead. In an existing checkout, use the start command above; do not
clone over it or discard another contributor's changes.

## Work on one part

Keep **Connect → Unify → Automate → Validate** as the delivery sequence. Choose an
existing issue in one of these areas and return the source commit and checks there.

| Area | Owns | Start here |
|---|---|---|
| Start and connect | Unattended preparation, reusable logins, client setup | [JOH-213](https://linear.app/641974/issue/JOH-213) · [owner setup](OWNER_START_HERE.md) |
| Agents and AIHub | C# core, provider routing, shared skills, MCP and handoffs | [JOH-187](https://linear.app/641974/issue/JOH-187) · [plugins](mcp/PLUGIN_SETUP.md) |
| Cloud and identity | Azure, Cloud Shell, Key Vault, Bicep and Terraform ownership | [JOH-224](https://linear.app/641974/issue/JOH-224) · [hybrid guide](architecture/HYBRID_EXECUTION.md) |
| Delivery and connectors | GitHub CI, Linear, Slack and Microsoft 365 | [JOH-223](https://linear.app/641974/issue/JOH-223) · [activation](architecture/CONNECTOR_ACTIVATION.md) |
| Learning, absorption and fleets | Recorded outcomes, recovered ideas, Hermes and XCore | [JOH-225](https://linear.app/641974/issue/JOH-225) · [absorption](absorption/START_HERE.md) |
| Native experience and setup | WinUI 3, profiles, graphics, USB and system workflows | [JOH-191](https://linear.app/641974/issue/JOH-191) · [native GUI](../src/gui/README.md) |

One outcome gets one active issue and one integration PR. Link source PRs and mark
proven duplicates as duplicates; preserve their descriptions and history. Green
checks and resolved reviews determine readiness. GitHub's purple PR status means
it actually merged. Learning, experiments and absorption remain in their own area
rather than competing with the immediate setup queue.

## Here to there, there to here

The shared MCP and AIHub connect each coding client to GitHub source, Linear
tasks and Slack coordination. Azure supplies the configured runtime; Microsoft
365 holds evidence and correspondence. Each connection reports its own readiness.

Each client reads the same [work skill](../plugins/helios-connect/skills/helios-work/SKILL.md).
The agent catalog and task-packet tools provide shared instructions and routes;
[isolated workspaces](AGENT_WORKSPACES.md) keep concurrent changes separate.
Local linked worktrees share an inbox. Different machines use one authenticated
HTTP endpoint and the same correlation ID, source SHA and handoff receipts.

- **ChatGPT to Claude:** the [bridge](mcp/REMOTE_BRIDGE.md) exposes shared reads and
  handoffs; its optional bounded Claude text tool uses the host's own Claude login.
- **Claude/Codex to ChatGPT:** handoffs are retrievable through the same bridge.
  The [Workspace Agent return helper](mcp/WORKSPACE_AGENT_RETURN.md) can trigger a
  published agent conversation when its channel and access token are configured.
  It does not attach to an arbitrary private chat or claude.ai browser session.
- **GitHub and Linear:** code/review events and the existing issue mirror carry
  durable work references. Keep competing issue-sync directions disabled.
- **Slack and Microsoft 365:** Slack is the coordination front door, SharePoint
  holds evidence, and Outlook holds correspondence. Runtime Graph adapters and
  service permissions still need activation; they are not additional work queues.

A running local bridge is not reachable from this cloud conversation until its
endpoint is registered and authorized. [Plugin setup](mcp/PLUGIN_SETUP.md) covers
that account connection. Routine work can then run unattended with valid access;
startup reports missing consent or credentials rather than waiting on a hidden prompt.

## Optional commands

| Need | Command |
|---|---|
| Open a coding client in this project | `connect.sh claude`, `connect.sh codex`, `connect.sh copilot` |
| Inspect provider routing | `connect.sh ai routing` |
| Review advisory learning | `connect.sh learning` |
| Compare explicitly selected models | `connect.sh combo "task" --providers claude-cli,codex` |
| Check the ChatGPT return channel locally | `connect.sh return status` |
| Complete first-time service sign-ins | `connect.sh setup --connect` |
| Inspect project destinations | `connect.sh project` |

Model commands can consume the selected accounts' usage. Configured providers,
packets and fleet declarations are not proof of running workers or successful
inference. Adaptive routing remains off by default. Bicep and Terraform must not
both own the same Azure target; the hybrid guide records their actual coverage.

The [integration handoff](integration/HELIOS-UNIFIED-2026-09-09.md) holds validation,
provenance and remaining activation work. The [source audit](imports/recovery/SOURCE-AUDIT-2026-09-09.md)
preserves all 16 uploaded inputs, and [ChatGPT imports](imports/chatgpt/README.md)
records shared context. Detailed guides remain available behind this one front door.
