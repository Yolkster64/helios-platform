# ChatGPT and Claude Code on one HELIOS project

`HELIOS.RemoteMcp` gives ChatGPT, Claude Code and Codex the same project documents,
Fabric plan and durable handoff inbox through Streamable HTTP at `/mcp`.
The existing local stdio MCP server remains available and shares the same inbox.
An optional `helios_claude_ask` tool sends text to a fresh Claude Code invocation
using the host's existing Claude login. No OpenAI API key is needed for this bridge.

## Start locally

From the trusted checkout, with .NET 10 installed:

```bash
export HELIOS_REPO_ROOT="$PWD"
dotnet run --project src/mcp/HELIOS.RemoteMcp -c Release --no-launch-profile
```

PowerShell:

```powershell
$env:HELIOS_REPO_ROOT = (Get-Location).Path
dotnet run --project src/mcp/HELIOS.RemoteMcp -c Release --no-launch-profile
```

The default address is `http://127.0.0.1:7078/mcp`. `/health` reports that the
server is listening; it does not claim Claude sign-in or connector delivery.
The server accepts only loopback peers and exact Host/Origin values by default.
It does not create a tunnel, publish a service, or deploy resources.

To point Claude Code at this local HTTP server:

```bash
claude mcp add --transport http --scope local helios-shared http://127.0.0.1:7078/mcp
```

Claude Code can also keep using this checkout's `.mcp.json` stdio registration.
Linked Git worktrees automatically share the primary checkout's handoff inbox.
For a nonstandard Git layout, set `HELIOS_HANDOFF_ROOT` to the absolute primary
HELIOS checkout. Two independent clones or machines use the same HTTP service
to share one inbox.

## Ask Claude from another client

Sign into Claude Code on the machine running the bridge once:

```bash
claude auth login
claude auth status
```

Then start the bridge with `HELIOS_REMOTE_CLAUDE_ENABLED=true` and
`HELIOS_REMOTE_CLAUDE_EXECUTABLE` set to the absolute installed native Claude
executable. On Windows it must be an `.exe`, rather than a `.cmd` shim.
Use a Claude Code version that supports `--restricted` and `--safe-mode`
(`--restricted` requires 2.1.248 or later). Unsupported flags cause a failed
request; the bridge never retries with broader permissions.

The `helios_claude_ask` tool takes just `prompt`. Include any code or context
you want reviewed in that text. Its result reports `completed` only after
Claude returns a valid result. `unavailable`, sign-in/version failures, timeouts
and output limits are reported as failures.

This lane uses a new one-turn invocation, with a 16 KiB input limit, 90-second
deadline and bounded output. It disables model tools, MCP connections, browser
integration and session persistence, and runs in a temporary working directory.
Safe mode preserves subscription authentication; bare mode would require API
credentials instead. Managed host policies continue to apply. Requests consume
the signed-in Claude account's usage. Other connector and cloud credentials are
removed from the child environment.

It does not attach to or take over an existing `claude.ai/code` session.
Native Claude session commands are a separate authenticated capability.

## Send a result back to ChatGPT

Claude Code calls `helios_handoff_submit` through its local or HTTP HELIOS MCP
connection with these arguments:

```json
{
  "handoffId": "771d120c-4830-46be-b5c5-6048c1b94771",
  "correlationId": "6ab2c350-b257-4262-8749-4c93061fe209",
  "recipient": "chatgpt",
  "note": "The review is ready. Include findings and evidence links here.",
  "sourceSha": "0123456789abcdef0123456789abcdef01234567"
}
```

Generate fresh UUIDs for new work and use the actual commit SHA, or omit
`sourceSha`. Reuse the original `handoffId` when retrying the same content.
The returned ID and timestamp are the storage receipt.

ChatGPT uses `helios_handoff_list` with `recipient: "chatgpt"`, then
`helios_handoff_fetch` with the returned `handoffId`. Reverse the recipient to
`claude` or `codex` for the other direction. All seven workspace roles are valid
recipients: `chatgpt`, `claude`, `codex`, `copilot`, `hermes`, `xcore`, and `human`.
A recipient name does not start an agent or grant approval authority.
The source SHA and note are caller
claims; they are not authenticated identity, instructions or approval.

Receipts live in the primary checkout's ignored `.helios/bridge` folder, are immutable and survive
client restarts. The inbox holds up to 256 notes of 8 KiB each. Archive old notes
locally when full. Common token formats, Slack webhook URLs and known credential
values are rejected; this check does not replace reviewing a note for sensitive content.
Storage uses restrictive permissions, a cross-process write lock and an atomic
non-overwriting rename. Linked storage paths are refused.

A stored handoff does not push text into an open ChatGPT conversation or cause
either client to execute it. The receiving client must retrieve it, or an
explicitly configured automation can invoke the receiving agent.

## Connect ChatGPT to the same HTTP service

ChatGPT needs a reachable MCP connection. A desktop-only loopback address is not
reachable from ChatGPT's cloud. Use an approved secure MCP tunnel if available in
your environment, or an approved HTTPS host. Register that endpoint in ChatGPT
and finish its account-linking flow once. The server alone cannot create that
client-side connection or reuse browser session cookies.

For an HTTPS deployment, configure the bridge's existing Entra resource-server
mode. These settings contain identity references; no client secret belongs here.

| Environment variable | Value |
| --- | --- |
| `HELIOS_REPO_ROOT` | Absolute trusted checkout or reviewed deployed snapshot |
| `HELIOS_REMOTE_AUTH_MODE` | `entra` |
| `HELIOS_REMOTE_URL` | Explicit backend IP listener, such as `http://127.0.0.1:7078` |
| `HELIOS_REMOTE_PUBLIC_ORIGIN` | Exact public HTTPS origin, without a path |
| `AZURE_TENANT_ID` | Exact Entra tenant GUID; `common` is rejected |
| `HELIOS_REMOTE_AUDIENCE` | Registered API's access-token audience |
| `HELIOS_REMOTE_SCOPE_RESOURCE` | Registered Application ID URI; defaults to `api://<audience GUID>` or the audience URI |
| `HELIOS_REMOTE_SCOPE` | Read scope name; default `access_as_user` |
| `HELIOS_REMOTE_ALLOWED_ORIGINS` | Optional comma-separated exact HTTPS browser origins |

The server validates JWT signatures, tenant issuer, audience, expiry and the
delegated read scope. Discovery and OAuth challenges advertise full scope URIs,
such as `api://<application GUID>/access_as_user`; JWT `scp` claims are checked
against their bare scope names. Set the scope resource explicitly if your
registered Application ID URI differs from the default. Handoff submissions additionally require `handoff.write`;
Claude requests additionally require `claude.invoke`. Expose and grant only the
needed delegated scopes in the Entra app. Register each client's approved OAuth
redirect URI and use its authorization-code flow with PKCE. Entra registration,
client consent and HTTPS hosting are deployment prerequisites, not completed by
starting this process. There is no dynamic client-registration endpoint.

Discovery is available at `/.well-known/oauth-protected-resource` and
`/.well-known/oauth-protected-resource/mcp`. Challenges use the configured
public origin, never the caller's Host or forwarded headers. Forwarded headers
are not trusted. Keep the backend private behind the approved TLS terminator.
Production deployment remains disabled by repository policy.

## Tools and validation

`helios_agent_catalog_get` returns the seven shared roles, actual checked-in
agent/skill references, task templates and existing configured routes.
`helios_task_packet_get` accepts `taskKind` (`implement`, `review`, `hybrid-plan`,
or `fleet-plan`) and an optional `language`. Each packet includes the same
canonical `helios-work` skill text and SHA-256, current language-aware route,
source references, steps, readiness gaps and the shared handoff contract.
Both tools report `routingSource: "config/aihub.json"` and
`customProfileApplied: false`: they read the checked-in default routing profile;
an `AIHUB_CONFIG` override is not applied to these shared templates.
The packet is a deterministic template. It creates no task, subagent, model
request or cloud deployment. Native client plugins and subagents remain
client-specific; the project instructions and handoff format are shared.

The default HTTP catalog contains `search`, `fetch`, `helios_project_get`,
`helios_task_routing_get`, `helios_fabric_plan_get`, `helios_fleet_topology_get`,
`helios_fleet_readiness_get`, `helios_combo_analyze`, `helios_usb_plan_get`,
`helios_bridge_status_get`, the three `helios_handoff_*` tools,
`helios_agent_catalog_get` and `helios_task_packet_get`. Only the
explicit Claude opt-in adds `helios_claude_ask`. Remote requests cannot provide
filesystem paths, executable names, CLI flags, resume IDs or arbitrary URLs.
Search/fetch serve a fixed allowlist of repository sources, each limited to
128 KiB, including the canonical work skill, hybrid and fleet guides, plugin
setup, Workspace Agent return setup, and absorption/learning guides. A remote
client can search the exact source path from its task packet and fetch the
returned catalog ID without a local checkout. Source paths are searchable;
they are never accepted as fetch IDs or opened outside the allowlist.

Each fetch returns a SHA-256 of its UTF-8 text in `metadata.sha256`, so both
clients can compare the context they actually received. GitHub links still
point to main; that link alone does not identify the host checkout's revision.
Raw `config/aihub.json` is not fetchable: the routing tool returns only the
existing selected routing fields. Missing sources and linked files are refused;
the host must still use a trusted, reviewed checkout. Serving a source or storing
a handoff does not dispatch an agent or prove that a fleet worker is running.

Run the real SDK/JWT/HTTP and inert-process tests with:

```bash
dotnet test tests/HELIOS.AIHub.Tests -c Release --filter 'FullyQualifiedName~RemoteMcp|FullyQualifiedName~Handoff'
```

The separate `HELIOS shared MCP bridge` CI lane builds the whole portable solution.
No live model or tenant is needed for these tests. On this implementation pass,
24 checks against the actual transport-independent C# process/options/handoff
code passed in a package-free harness. That harness used MCP attribute/exception
shims and does not prove SDK transport or JWT integration. Local package restore was blocked. GitHub CI subsequently built the full solution
and passed all 671 AIHub tests, including actual SDK HTTP/JWT tests, at
`b710e92ef066e7eb7e06f8b1a1032f8bc0a63ad6`. Later changes require their own current-head CI result.

## Source continuity

This gateway retains the bounded search/fetch, origin checks and OAuth discovery
ideas from [original HELIOS PR #190](https://github.com/M0nado/helios-platform/pull/190)
at `8c854fca791bbf8e3028b49e7d707bf1d9d5e49f`. Its old standalone .NET 8 API and
hand-written protocol dispatcher were not copied over the newer Yolkster core.
The new .NET 10 host uses the repository's pinned MCP 2.1 SDK and existing C#
Fabric planner. See the official [MCP C# transport documentation](https://csharp.sdk.modelcontextprotocol.io/v2/concepts/transports/transports.html),
[Claude CLI reference](https://code.claude.com/docs/en/cli-reference), and
[Claude programmatic-use guide](https://code.claude.com/docs/en/headless).
