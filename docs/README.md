# HELIOS Documentation Overview

**Status:** Maintained overview for the current repository documentation  
**Current repository authority:** `Yolkster64/helios-platform`  
**Target rename after reviewed cutover:** `Yolkster64/helios-control`

Use this page to find the documents that reflect the current engineering contract.

## Start here

| Need | Read |
| --- | --- |
| New here: five minutes to a working `helios-ai ask` (three paths, no paid key) | [GETTING_STARTED.md](GETTING_STARTED.md) |
| Zero-install: open the repo in a Codespace | [.github/CODESPACES_GUIDE.md](../.github/CODESPACES_GUIDE.md) |
| Contributor setup, build, CLI, MCP | [PROJECT_SETUP.md](PROJECT_SETUP.md) |
| Owner-only GitHub, Azure, and secret wiring | [OWNER_START_HERE.md](OWNER_START_HERE.md) |
| Exact build, test, and smoke-run commands | [TEST_RUN_PLAYBOOK.md](TEST_RUN_PLAYBOOK.md) |
| Product consolidation direction | [CONSOLIDATION_BLUEPRINT.md](CONSOLIDATION_BLUEPRINT.md) |
| Current documentation map | [DOCUMENTATION_INDEX.md](DOCUMENTATION_INDEX.md) |

## Current status

HELIOS is under active consolidation. The buildable cross-platform slice is the AI hub,
API, CLI, MCP server, tests, and supporting automation. The legacy root/core project and
many older generated status documents remain in the repository for provenance, but they are
not authoritative evidence of production readiness or deployment status.

For the current repository state, trust:

- [../README.md](../README.md)
- [PROJECT_SETUP.md](PROJECT_SETUP.md)
- [OWNER_START_HERE.md](OWNER_START_HERE.md)
- [TEST_RUN_PLAYBOOK.md](TEST_RUN_PLAYBOOK.md)
- [CONSOLIDATION_BLUEPRINT.md](CONSOLIDATION_BLUEPRINT.md)
- [architecture/](architecture/)
- [mcp/](mcp/)
- [migration/yolkster-control-cutover/](migration/yolkster-control-cutover/)

## Key document sets

### Architecture

- [architecture/MULTI_LLM_INTEGRATION.md](architecture/MULTI_LLM_INTEGRATION.md)
- [architecture/GITHUB_ECOSYSTEM_DESIGN.md](architecture/GITHUB_ECOSYSTEM_DESIGN.md)
- [architecture/HERMES_FLEET_AND_XCORE.md](architecture/HERMES_FLEET_AND_XCORE.md)
- [architecture/ADR-0010-WINUI3-ONLY.md](architecture/ADR-0010-WINUI3-ONLY.md)
- [architecture/CLAUDE-CODE-CANONICALIZATION.md](architecture/CLAUDE-CODE-CANONICALIZATION.md)

### Cutover and repository authority

- [migration/yolkster-control-cutover/CURRENT-AUTHORITY.md](migration/yolkster-control-cutover/CURRENT-AUTHORITY.md)
- [migration/yolkster-control-cutover/CUTOVER-RUNBOOK.md](migration/yolkster-control-cutover/CUTOVER-RUNBOOK.md)
- [migration/yolkster-control-cutover/CANONICAL-ISSUE-LEDGER.md](migration/yolkster-control-cutover/CANONICAL-ISSUE-LEDGER.md)
- [profile/YOLKSTER64-PROFILE-README.md](profile/YOLKSTER64-PROFILE-README.md)

### Multi-LLM and MCP

- [mcp/CLIENT_SETUP.md](mcp/CLIENT_SETUP.md)
- [mcp/EVALUATION.md](mcp/EVALUATION.md)
- [architecture/LLM_STRENGTHS_PLAYBOOK.md](architecture/LLM_STRENGTHS_PLAYBOOK.md)

### GUI and Windows-only work

- [../src/gui/README.md](../src/gui/README.md)
- [architecture/GUI_THEME_ANALYSIS.md](architecture/GUI_THEME_ANALYSIS.md)
- [architecture/GUI_UPGRADE_PLAN.md](architecture/GUI_UPGRADE_PLAN.md)

## Legacy and historical documents

Many older root-level `*_COMPLETE`, `*_REPORT`, and `*_SUMMARY` files, plus several
template-era `/docs` pages, are retained as historical context only. Unless a page is
explicitly maintained and linked from this overview or the current repository
[`README.md`](../README.md), treat it as archival material rather than the source of truth.

## Documentation maintenance rule

When updating current documentation, add or revise content in the maintained documents above
instead of extending legacy completion/status reports.
