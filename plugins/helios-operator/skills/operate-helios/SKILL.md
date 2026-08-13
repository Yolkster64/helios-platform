---
name: operate-helios
description: Operate the HELIOS repository and multi-LLM fabric from Claude Code using one sanitized repo/Azure context. Use for HELIOS planning, implementation, provider routing, Azure inventory or deployment preflight, cross-assistant handoffs, and deciding the safest next action.
---

# Operate HELIOS

Use the HELIOS MCP server as the shared control surface. Its operator files live under the
gitignored `.helios/operator/` directory in the current checkout, so Claude Code, Codex,
Copilot, ChatGPT, Hermes, and XCore can continue from the same inspectable evidence.

## Start every operating task

1. Confirm this is the HELIOS checkout: `AGENTS.md`, `config/aihub.json`, and
   `src/mcp/HELIOS.Mcp` must exist. Read `AGENTS.md` before editing.
2. Call the MCP tool ending in `helios_operator_context_sync` with
   `surface: "claude-code"`. Keep `includeAzure` false unless the task needs current Azure
   state. Set `includeResources` only when resource-level change detection matters.
3. Read `helios_operator_profile_get`, `helios_ai_status`, and
   `helios_task_routing_get` before choosing a provider or proposing infrastructure work.
4. Read `helios_operator_next_steps_get`, compare the suggestions with the user's actual
   request, and take only the steps that are in scope.

When installed as this plugin, MCP tool names are scoped under the plugin and server. When
the repo-level `.mcp.json` is active, the prefix differs. Match the stable tool-name suffix
instead of assuming one client-specific prefix.

## Remember only explicit preferences

Call `helios_operator_profile_save` only for preferences the user states or confirms:
display name, preferred Azure location, naming prefix, non-sensitive default tags, and
assistant surfaces. Never infer account identifiers, identities, resource ownership, or
credentials. The tool rejects credential-looking names and values — including camelCase
tag names such as `clientSecret` — and a save that changes nothing is a no-op.

## Route work deliberately

- Architecture, review, infrastructure reasoning, and long-context analysis: Claude.
- Code generation and test scaffolding: Codex/OpenAI.
- Inline repository completion: Copilot.
- Azure enterprise workloads: the configured Azure provider.
- Fleet experiments and recovered engine concepts: Hermes/XCore only when the engine
  catalog marks them implemented and runtime-available.

Use `helios_ai_route` when another provider materially improves the result. Provider calls
have network and token cost; do not fan out by default. Use `helios_ai_compare` or
`helios_ai_tandem` only when the user asks for comparison or independent review.

## Preserve the control boundary

- Treat GitHub and a fresh Azure inventory as source evidence; cached context is a handoff,
  not proof that external state is unchanged.
- Azure context sync may run `az account show`, `az group list`, and `az resource list`.
  It must never deploy, update, delete, assign roles, create credentials, or change a
  subscription.
- Generate Bicep validation and `what-if` before any deployment. Require explicit user
  approval for `az deployment ... create`, resource changes, PR merge, force push, or
  credential creation.
- Keep secrets in environment variables or Key Vault. Never put values in profile,
  context, journal, config, prompts, commits, or comments.
- Preserve unrelated local changes and work on a task branch. End repository work with a
  reviewable PR unless the user explicitly requests a different handoff.

## Finish with a receipt

Re-run `helios_operator_context_sync` without Azure inventory after repository changes so
the journal records the branch and head. Report: evidence used, files or PR changed,
validation run, external writes performed, approvals still required, and the next
deterministic action.
