# Codex surfaces — live usage in this repo

*Versions and API claims mirror the cited repo files; update this file in the same PR
that changes them.* PR-protocol strings were verified verbatim against PR #10
(`Yolkster64/helios-platform`) via the GitHub API at authoring time (2026-08-13);
re-verify against a recent PR if the connector's output format looks different.

## Surface 1 — Codex cloud ↔ GitHub (the PR reviewer)

The connection lives on OpenAI's side, not in this repo: the owner connects the
repo in the Codex settings at chatgpt.com — there is nothing repo-side to
configure or keep in sync (`docs/architecture/CONNECTIONS_SETUP.md:101-120`).
Once connected:

- **Triggers**: opening a PR for review, marking a draft ready, or commenting
  `@codex review` (the connector's own wrapper text lists exactly these three).
  Every push to a PR under review gets a fresh wave.
- **Fix commits**: `@codex address that feedback` (or any `@codex <task>`
  follow-up) has Codex push commits to the PR branch. Real event: commit
  `118aaea` ("Fix acronym credential tag redaction") landed on PR #10 through
  the address-feedback flow — it appears under the repo owner's identity, which
  is how Codex cloud pushes surface, and the follow-up commit on that PR
  (`7ab8219`, "Address Codex wave-5/6 findings") names `118aaea` as the fix it
  builds on. Treat such commits like any hub draft: review before relying on them.
- **Instruction file**: Codex reads `AGENTS.md` (mirroring `CLAUDE.md`) —
  `docs/architecture/CONNECTIONS_SETUP.md:116-117`. It genuinely uses it:
  PR #10 findings carry links like "AGENTS.md reference: AGENTS.md:L57-L60".
- **Quota**: work counts against the ChatGPT plan's Codex limits; when
  exhausted, reviews and commands quietly stop until the window resets
  (`docs/architecture/CONNECTIONS_SETUP.md:112-114`).

## Review-wave protocol (what the connector actually posts)

Measured across PR #10's six waves: the review lands **~7–12 minutes after the
push** (typically ~10). Signals, verbatim:

| Signal | Text / form | Meaning |
|---|---|---|
| Findings exist | Review body: "### 💡 Codex Review / Here are some automated review suggestions for this pull request. / **Reviewed commit:** `<sha>`" | Read the inline comments — the wrapper itself never carries findings |
| Clean pass | "If Codex has suggestions, it will comment; otherwise it will react with 👍." (wrapper's own contract) — a 👍 reaction and no review | Nothing to fix |
| Security-quota noise | Issue comment from `chatgpt-codex-connector[bot]`: "You have reached your Codex usage limits for security reviews. Please try again later." | Ignore. This is the *security-review* add-on's quota; on PR #10 it fired ~1–3 min after every push while the regular review still arrived on schedule |
| Plan quota | No regular review at all by ~12 min post-push, no wrapper | ChatGPT-plan Codex quota exhausted — retrigger later with `@codex review` |

**Findings format**: inline PR review comments (not issue comments). Each opens
with a severity badge — `![P1 Badge](https://img.shields.io/badge/P1-orange?style=flat)`
or `![P2 Badge](…/P2-yellow…)` — then a bold one-line title, a body arguing the
defect, an optional `AGENTS.md reference:` link, and the footer "Useful? React
with 👍 / 👎." P1 = fix before merge; P2 = judgment call, but on PR #10 every P2
was actioned. React 👎 on false positives — it feeds the reviewer.

**Reviewed commit matters**: the wrapper names the head SHA it reviewed. A wave
that reviewed a stale head (you pushed again meanwhile) is answered by the next
wave, not by re-arguing the old one.

Loop-level choreography (who pushes when, how Codex waves interleave with
Copilot and Claude reviews): `docs/architecture/REVIEW_LOOP.md`.

## Surface 2 — `codex` CLI (the hub's agentic lane)

- Install: npm `@openai/codex` via `scripts/bootstrap/setup-ai-clis.ps1:114-116`.
- Auth: `codex login` — ChatGPT-plan browser/device flow
  (`docs/architecture/ENTERPRISE_AI_CONNECTIONS.md:117`, browserless:
  `codex login --device`) — or `OPENAI_API_KEY` in the environment, which is
  what CI/fleet lanes use (`docs/architecture/LLM_STRENGTHS_PLAYBOOK.md:61-62`).
- Hub entry: the `codex` cliAgent in `config/aihub.json:53-58` —
  `command: "codex"`, `argsTemplate: "exec {prompt}"`, 600 s timeout. CLI agents
  are agentic: they read files, run commands, iterate
  (`docs/architecture/LLM_STRENGTHS_PLAYBOOK.md:38-42`).
- MCP: the codex CLI can drive the HELIOS MCP server via
  `~/.codex/config.toml` (`docs/mcp/CLIENT_SETUP.md:38-46`).

## Surface 3 — `openai-codex` API provider

`config/aihub.json:10-16`: type `openai`, model `gpt-5.1-codex-max` (the
catalog's codegen specialist), `apiKeyEnv: OPENAI_API_KEY`,
`apiKeySecretName: openai-api-key`. It is an alias onto the same platform/key
as the `openai` provider — the codegen lane for CI/containers where the codex
CLI is absent (the provider's own `$comment`).

**The CLI-login-does-NOT-cover-API rule** (`scripts/bootstrap/connect-all.ps1:314-351`):
the bootstrap's `openai-codex` lane reports *blocked* when codex is logged in
but `OPENAI_API_KEY` is unset, because the API providers read only that env var
(or the Key Vault `openai-api-key` secret via `AZURE_KEY_VAULT_URI`). The key
short-circuits the whole lane; the login covers the CLI only. Key custody:
Key Vault preferred (`docs/architecture/ENTERPRISE_AI_CONNECTIONS.md:122-126`);
the value never enters a file or this repo.

## Surface 4 — ChatGPT app / workbench

`docs/architecture/ENTERPRISE_AI_CONNECTIONS.md:110-126` (§5): the cloud
reviewer is already live; the app/workbench side issues the project keys
(platform.openai.com) that light up surfaces 2–3. Owner-operated; nothing in
the repo configures it.

## Routing codegen to the ChatGPT lane

Task-routing chains where codex leads (`config/aihub.json:87-130`):

| Task type | Chain |
|---|---|
| `code_generation` | `codex → openai-codex → openai → azure-openai → anthropic` |
| `code_refactoring` | `codex → openai-codex → anthropic → openai` |
| `test_creation` | `codex → openai-codex → openai → anthropic` |
| `debugging` | `claude-cli → codex → openai-codex → openai` |

Commands (usage strings in `src/ai/HELIOS.AIHub.Cli/Program.cs:321-324`):

```bash
helios-ai route code_generation "<prompt>" [--system S]     # routed, codex leads
helios-ai ask "<prompt>" --provider openai-codex [--model M] # pin the specialist
helios-ai tandem code_generation "<prompt>"                  # run the whole chain concurrently
```

Workspace vs payload (`docs/architecture/LLM_STRENGTHS_PLAYBOOK.md:56-68`):
`codex` CLI for repo-scale agentic edits; the API form when you control the
entire prompt. Reviews are Claude-led (`code_review: anthropic → claude-cli →
openai`) — never route a paste-in diff to codex.

**Reconcile before commit**: hub output is a draft — the same discipline as
`.claude/agents/ui-designer.md` Rule 1. Check every draft against the target
stack's skill (`csharp-orchestrator`, `powershell-automation`,
`python-agents`, …) and the CLAUDE.md hard rules (glob guard, no secrets)
before it touches the tree. `.claude/agents/codex-liaison.md` operationalizes this.

## Instruction files — the three-way contract

| File | Read by | Cite |
|---|---|---|
| `AGENTS.md` | Codex (cloud reviewer + CLI) | `docs/architecture/CONNECTIONS_SETUP.md:116-117` |
| `.github/copilot-instructions.md` | Copilot (all surfaces) | `docs/architecture/CONNECTIONS_SETUP.md:126` |
| `CLAUDE.md` | Claude Code | `docs/architecture/CONNECTIONS_SETUP.md:153` |

Each must carry the same four blocks (today `AGENTS.md` and `CLAUDE.md` mirror
each other nearly verbatim): (1) build/test commands exactly as CI runs them;
(2) the hard rules — root csproj `**/*.cs` glob guard, new-C#-under-`src/`+sln,
no secrets (env-var names only in `config/aihub.json`), untrusted root status
docs; (3) the hub surface inventory — CLI verbs, API endpoints, the full MCP
tool list; (4) pointers into `docs/architecture/`. A convention change that
lands in only one file trains the other two vendors' agents on stale rules —
PR #10 spent two commits re-syncing tool inventories across all three, and at
authoring time `.github/copilot-instructions.md` still trails the other two
(.NET 8 wording, pre-Foundry MCP list), so check for drift before trusting it.
Copilot-side mechanics live in the `github-copilot` skill (authored in
parallel; reference by path: `.claude/skills/github-copilot/`).

## Automatic use

**Auth for unattended use.** The API providers read exactly one credential:
`OPENAI_API_KEY` from the environment, or the `openai-api-key` Key Vault secret
(`config/aihub.json:10-16`; custody preference:
`docs/architecture/ENTERPRISE_AI_CONNECTIONS.md:122-126`). `codex login` is the
ChatGPT-plan path for the CLI only — `.env.template:17-20` documents both facts
in one place: the CLI and the `openai-codex` provider share `OPENAI_API_KEY`,
while a plan login covers just the CLI. Automatic diagnosis of this lane is the
doctor's `codex` lane (`scripts/bootstrap/auth-doctor.ps1`, authored in
parallel; reference by path) via `.claude/agents/auth-broker.md`.

**Lanes that exercise Codex with no human in the loop:**

1. **The cloud reviewer** — a wave on every PR open/ready/push, plus the
   `@codex review` / `@codex address that feedback` commands; trigger table and
   wave choreography in `docs/architecture/REVIEW_LOOP.md:14-17,30-48`.
2. **The codex-liaison agent** (`.claude/agents/codex-liaison.md`) — pulls
   drafts through the hub and reconciles them before anything lands.
3. **The task-routing chains** — `codex`/`openai-codex` lead `code_generation`,
   `code_refactoring`, and `test_creation`, and sit second/third in `debugging`
   (`config/aihub.json:87-130`), so any `helios-ai route`/`tandem` call for
   those task types reaches this lane with no human step in between.
