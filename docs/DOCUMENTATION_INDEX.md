# HELIOS Documentation Index

This index lists the maintained documentation that reflects the current HELIOS repository
state.

## Primary entry points

| Audience | Read first | Purpose |
| --- | --- | --- |
| Contributors | [PROJECT_SETUP.md](PROJECT_SETUP.md) | Toolchain, build, test, CLI, MCP |
| Repository owner | [OWNER_START_HERE.md](OWNER_START_HERE.md) | GitHub settings, Azure OIDC, secrets, connectors |
| Reviewers and operators | [TEST_RUN_PLAYBOOK.md](TEST_RUN_PLAYBOOK.md) | Exact validation and smoke-run commands |
| Architects | [CONSOLIDATION_BLUEPRINT.md](CONSOLIDATION_BLUEPRINT.md) | Product consolidation direction |

## Current-status documents

| Topic | Document |
| --- | --- |
| Repository overview | [../README.md](../README.md) |
| Documentation overview | [README.md](README.md) |
| Current repository authority | [migration/yolkster-control-cutover/CURRENT-AUTHORITY.md](migration/yolkster-control-cutover/CURRENT-AUTHORITY.md) |
| Cutover execution | [migration/yolkster-control-cutover/CUTOVER-RUNBOOK.md](migration/yolkster-control-cutover/CUTOVER-RUNBOOK.md) |
| Canonical issue tracking | [migration/yolkster-control-cutover/CANONICAL-ISSUE-LEDGER.md](migration/yolkster-control-cutover/CANONICAL-ISSUE-LEDGER.md) |
| WinUI 3 desktop contract | [architecture/ADR-0010-WINUI3-ONLY.md](architecture/ADR-0010-WINUI3-ONLY.md) |
| Claude/canonicalization guardrails | [architecture/CLAUDE-CODE-CANONICALIZATION.md](architecture/CLAUDE-CODE-CANONICALIZATION.md) |

## Engineering reference sets

### Architecture

- [architecture/README.md](architecture/README.md)
- [architecture/MULTI_LLM_INTEGRATION.md](architecture/MULTI_LLM_INTEGRATION.md)
- [architecture/GITHUB_ECOSYSTEM_DESIGN.md](architecture/GITHUB_ECOSYSTEM_DESIGN.md)
- [architecture/HERMES_FLEET_AND_XCORE.md](architecture/HERMES_FLEET_AND_XCORE.md)
- [architecture/ROADMAP_MULTI_LLM.md](architecture/ROADMAP_MULTI_LLM.md)

### MCP and client integration

- [mcp/CLIENT_SETUP.md](mcp/CLIENT_SETUP.md)
- [mcp/EVALUATION.md](mcp/EVALUATION.md)

### GUI and Windows-specific work

- [../src/gui/README.md](../src/gui/README.md)
- [architecture/GUI_THEME_ANALYSIS.md](architecture/GUI_THEME_ANALYSIS.md)
- [architecture/GUI_UPGRADE_PLAN.md](architecture/GUI_UPGRADE_PLAN.md)

## Legacy-document status

The repository still contains large numbers of generated guides, completion reports, and
status snapshots from earlier phases. Those files are kept for provenance and recovery
context, but they are not the current status source of truth unless one of the maintained
documents above points to them explicitly.

In particular, older `/docs` template pages and root-level `*_COMPLETE`, `*_REPORT`, and
`*_SUMMARY` files should be treated as historical.
