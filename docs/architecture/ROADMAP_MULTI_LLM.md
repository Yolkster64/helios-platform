# Multi-LLM Roadmap — Follow-up PRs & Known-Red Inventory

PR1 (this branch) shipped: `infra/` (Foundry account+project + Key Vault + validate/deploy
workflows), `HELIOS.sln` baseline, `src/ai/HELIOS.AIHub` (+31 tests), `helios-ai` CLI,
`src/mcp/HELIOS.Mcp` (+`.mcp.json`), `.claude/skills` + agents, fleet topology config,
this doc set, and CI repairs (dotnet-build/ci-validation/quality rewritten or fixed).

## PR2 — Core wiring & cleanup
- Wire the `ai` command into `Core/CLI/CliCommandExecutor.cs` (blocked in PR1: core does
  not compile — 323 errors; the seam fix in `IRouter.cs` was applied, the rest remains).
- Begin core repair: resolve duplicate-interface ambiguities (`Core/Intelligence` vs
  `Core/ML`), fix `VaultSystemTests` mocks; flip `legacy-core-status` job to blocking
  once green.
- Archive `cloud-integration/` (ported: FallbackChain/CircuitBreaker/configs) and the
  fictional `copilot.config.json`; quarantine `docs/ui-xenoblade` (stray git store).
- Delete or fix the broken `src/tests/HELIOS.Platform.Tests.csproj` (dangling
  ProjectReference); consolidate on `tests/`.
- Extend `.editorconfig` with a `[*.cs]` section (4-space, Allman) so analyzers have rules.

## PR3 — Foundry depth & retrieval
- Foundry agent tools: AI Search connection (restore the legacy `aiSearchName` surface as
  a module), file search, and connected Azure data sources; project capability-host
  configuration where BYO storage is needed.
- Key-Vault-backed config end-to-end test; managed-identity path in CI.
- MCP additions: `helios_foundry_agent_create/list` (still non-destructive by default).
- Wire real per-call `CostUsd` into `RoutingOutcome` (currently a placeholder `0`) from
  provider usage via `Pricing.fs`; wire `HELIOS.AIHub.Native` cosine similarity into
  `CompareAsync` for response dedup; enable `learning.enabled` by default once the cost
  wiring lands and document the `.helios/` gitignore entry.

## PR4 — Connectors
- Slack + SharePoint via the Hermes gateway reuse; Linear via `src/connectors/
  HELIOS.Connectors` or a Hermes plugin (spike decides). Same Key Vault credential flow.
- Gateway webhook wiring for GitHub-event-driven fleet dispatch (untrusted-input rules).

## PR5 — GitHub ecosystem & fleet execution
- ARC deployment (scale set values in GITHUB_ECOSYSTEM_DESIGN.md), org Project board,
  epic issues automation, repo templates.
- Hermes fleet + Xcore-9s live bring-up per HERMES_FLEET_AND_XCORE.md runbook.
- WindowsDeveloperConfig `cross-llm-shell` workload (az/gh/copilot/claude/codex/ollama).

## PR6 — Platform upgrades
- net8.0 → **net10.0** across all projects + workflows (net8.0 EOL 2026-11-10;
  .NET 11 remains preview — do not target).
- WinUI 3 shell per GUI_THEME_ANALYSIS.md; retire root WPF csproj; `winui3-reviewer`
  gate active.

## Known-red workflow inventory (pre-existing, not touched by PR1)
| Workflow | Problem | Disposition |
|---|---|---|
| `deploy.yml` | All-echo fake deployment incl. fake "AI initialized" lines | Replace or delete in PR2 |
| `ai-code-review.yml` | Regex-only "AI review", canned comment (its comment-post 403 is fixed — workflow now declares `permissions`) | Replace with real `code_review` routing in PR2 |
| `nuget.yml` | Builds/packs the broken core project, for net6/7 the csproj doesn't even target; can only go red | PR trigger removed and restores made explicit in PR1 (PR builds live in `dotnet-build.yml`); main/tag path stays red until the core compiles — PR2 |
| `build-variant-test.yml` | Node.js variant matrix in a .NET-first repo; its `$GITHUB_OUTPUT` multi-line bug is fixed and a package.json guard skips the matrix cleanly | Delete or repurpose for real Node modules in PR2 |
| `microsoft-ecosystem/.github/workflows/azure-deploy.yml` | Nested path (never runs), missing `./infrastructure/main.bicep` | Salvage OIDC/staging patterns, then delete |
| `publish-to-packagemanagers.yml` | **Invalid YAML** — embedded PowerShell here-string (`@'`) starts at column 0 (line 62), de-indenting out of the `run: |` block scalar. Workflow cannot parse, so it has never run | Re-indent the here-string body inside the block scalar, or move the script to a `.ps1` file and call it (preferred) — PR2 |
| `documentation-update.yml` | **Invalid YAML** — block mapping broken at line 33 (same embedded-script class of defect) | Same fix as above — PR2 |
| `build-all-modules.yml`, `multi-repo-sync.yml`, others | Reference phase/module structures that don't exist | Audit in PR2; delete what cannot go green |
| `ci-validation.yml` markdownlint step | `.markdownlint.json` missing | Add config or drop step (PR2) |
| 54 legacy `.ps1` files | Genuine parse errors (broken `foreach`, unterminated here-strings, invalid class code) — masked for years because the old syntax checks used the shallow tokenizer or never gated | Baselined in `.github/ps1-parse-baseline.txt`; the ci-validation gate fails any NON-baseline parse error and reports repaired files. Repair scripts area-by-area in PR2+, deleting baseline lines as they fix |
| `.gitmodules` | ~~Declared 7 nonexistent `modules/` submodules (zero gitlinks — pure manifest debris); `.gitignore` also ignored `.gitmodules` and `.dockerignore`~~ | **Retired in PR1**: manifest deleted, ignore-rule traps removed. Real submodule governance (upstream PR #215's fail-closed pinned-approval gate) is an absorption-pipeline candidate |
| `azure-pipelines.yml` | "Hello world" starter, git-ignored | Delete in PR2 |

Rule: nothing new may depend on a known-red item, and each PR that touches an area
retires its entries from this table.
