---
name: openai-codex
description: Working knowledge of the ChatGPT/OpenAI Codex lane in HELIOS — the Codex cloud PR reviewer, the codex CLI, the openai/openai-codex API providers, and @codex PR commands. Use for ANYTHING involving ChatGPT, OpenAI Codex, the codex CLI, @codex review / @codex address-that-feedback commands, the openai or openai-codex hub providers, routing codegen to the ChatGPT lane, or interpreting a Codex review wave on a PR.
---

# OpenAI Codex / ChatGPT — the HELIOS codegen lane

One vendor, four distinct surfaces with different auth and different contracts.
Confusing them is the #1 failure mode of this lane. Depth and verbatim protocol
strings: `references/codex-surfaces.md`.

## The four surfaces

| # | Surface | What it does | Auth | Ground truth |
|---|---|---|---|---|
| 1 | Codex cloud ↔ GitHub | Auto-reviews every PR; `@codex review` retrigger; `@codex address that feedback` pushes fix commits | Owner connects repo at chatgpt.com/codex settings — zero repo-side config | `docs/architecture/CONNECTIONS_SETUP.md:101-120` |
| 2 | `codex` CLI | Agentic repo-scale edits; the hub's `codex` cliAgent runs `codex exec {prompt}` | `codex login` (ChatGPT-plan device flow) OR `OPENAI_API_KEY` | `config/aihub.json` (cliAgents), `scripts/bootstrap/setup-ai-clis.ps1:114-116` |
| 3 | `openai-codex` API provider | Single completions from `gpt-5.1-codex-max` (codegen specialist; the `openai` provider shares the key) | `OPENAI_API_KEY` env / Key Vault `openai-api-key` ONLY | `config/aihub.json:10-16` |
| 4 | ChatGPT app / workbench | Prompt lab + project key issuance | Project keys from platform.openai.com | `docs/architecture/ENTERPRISE_AI_CONNECTIONS.md:110-126` (§5) |

**The auth trap** (`scripts/bootstrap/connect-all.ps1:314-351`): `OPENAI_API_KEY`
covers surfaces 2 AND 3, but the reverse is NOT true — a `codex login` authenticates
the CLI only; the `openai`/`openai-codex` API providers read only the env var or the
Key Vault secret. A "codex is logged in" state with no key is still a blocked API lane.
Never put the key value in any file; env or Key Vault only (CLAUDE.md hard rule).

## Routing codegen to this lane

Codex leads four task-routing chains in `config/aihub.json:87-130`:
`code_generation`, `code_refactoring`, `test_creation` (all `codex → openai-codex →
…`), and it is second in `debugging` behind `claude-cli`. Commands
(`src/ai/HELIOS.AIHub.Cli/Program.cs:321-324`):

```bash
helios-ai route code_generation "<prompt>" [--system S]   # routed chain, codex leads
helios-ai ask "<prompt>" --provider openai-codex           # pin the API specialist
helios-ai tandem code_generation "<prompt>"                # whole chain concurrently
```

Use the CLI agent (surface 2) for workspaces ("make the tests pass"), the API
provider (surface 3) for payloads you fully control — the split is
`docs/architecture/LLM_STRENGTHS_PLAYBOOK.md:56-68`. Reviews stay Claude-led
(`code_review: anthropic → claude-cli → openai`); don't route diffs to codex.

**Hub output is a DRAFT, never a deliverable** — same discipline as
`.claude/agents/ui-designer.md` Rule 1. Reconcile every draft against the target
stack's skill (`csharp-orchestrator`, `powershell-automation`, …) before writing it
into the repo. The `codex-liaison` agent (`.claude/agents/codex-liaison.md`) owns
this workflow end to end.

## Review wave — quick signal card

Full protocol, timings, and verbatim bot strings: `references/codex-surfaces.md`.
Loop-level choreography: `docs/architecture/REVIEW_LOOP.md`.

| You see | It means |
|---|---|
| Review body "Here are some automated review suggestions…" | Findings exist — read the inline comments |
| 👍 reaction, no review comment | Clean pass |
| "…usage limits for security reviews…" comment | Noise — the *security* add-on quota; the regular review still runs |
| No regular review ~12 min after push | Plan quota likely exhausted — retrigger later with `@codex review` |
| P1 (orange) / P2 (yellow) badge on a finding | Severity ranking; P1s block, P2s are judgment calls |

## Instruction files — keep all three in sync

`AGENTS.md` is Codex's instruction file, `.github/copilot-instructions.md` is
Copilot's, `CLAUDE.md` is Claude's (`docs/architecture/CONNECTIONS_SETUP.md:56-58,116-117`).
Any change to agent-relevant conventions (build commands, hard rules, hub/MCP surface
inventory) must land in ALL THREE in the same commit. Contents contract:
`references/codex-surfaces.md` §"Instruction files".
