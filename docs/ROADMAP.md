# HELIOS Roadmap

**Status:** Active consolidation, not production-ready  
**Current repository authority:** `Yolkster64/helios-platform`  
**Reviewed target after cutover:** `Yolkster64/helios-control`

This page is the current high-level roadmap summary. For the detailed multi-LLM execution
plan, see [architecture/ROADMAP_MULTI_LLM.md](architecture/ROADMAP_MULTI_LLM.md). For the
repository cutover contract, see
[migration/yolkster-control-cutover/CUTOVER-RUNBOOK.md](migration/yolkster-control-cutover/CUTOVER-RUNBOOK.md).

## Current phase

The repository is in a consolidation phase focused on preserving the buildable AIHub/MCP
slice, keeping infrastructure and workflow contracts honest, and separating current
engineering guidance from historical generated status documents.

## Active tracks

1. **Canonical repository cutover**
   - Keep `Yolkster64/helios-platform` as the live authority until the reviewed rename.
   - Preserve the cutover ledger and runbook as the migration source of truth.
2. **AIHub and MCP hardening**
   - Maintain the buildable .NET solution, Python spoke, and governed MCP surface.
   - Keep provider routing, engine recommendations, and learning flows advisory and bounded.
3. **Documentation consolidation**
   - Direct contributors to the maintained setup, owner, playbook, architecture, MCP, and
     cutover documents.
   - Mark older generated status/template documents as historical instead of current state.
4. **WinUI 3 desktop boundary**
   - Keep new desktop work in `src/gui` under the WinUI 3 contract.
   - Avoid expanding the legacy root WPF baseline while HC-002 remains open.
5. **Deployment and governance safety**
   - Keep production disabled by default.
   - Preserve GitHub protected environments, OIDC-only Azure access, and no-secrets-in-Git
     rules.

## What is not current status

The repository still contains many older completion reports, summaries, and generated
template docs. They may be useful for provenance or recovery research, but they do not
represent the current shipped state by themselves.

## Detailed planning references

- [CONSOLIDATION_BLUEPRINT.md](CONSOLIDATION_BLUEPRINT.md)
- [architecture/ROADMAP_MULTI_LLM.md](architecture/ROADMAP_MULTI_LLM.md)
- [architecture/MULTI_LLM_INTEGRATION.md](architecture/MULTI_LLM_INTEGRATION.md)
- [migration/yolkster-control-cutover/CANONICAL-ISSUE-LEDGER.md](migration/yolkster-control-cutover/CANONICAL-ISSUE-LEDGER.md)
- [migration/yolkster-control-cutover/CURRENT-AUTHORITY.md](migration/yolkster-control-cutover/CURRENT-AUTHORITY.md)
