# HC-029 Fabric topology and checksums

This document is the upload packet companion for SharePoint publication and
checksum re-read verification.

## Topology snapshot

- Migration issue: `HC-029`
- Contract file:
  `/home/runner/work/helios-platform/helios-platform/config/fabric/helios-fabric.v1.json`
- Source Fabric PR: `Yolkster64/helios-platform#154` (issue tracker: `#184`)
- Slack target: workspace `T0BAFGSNY5P`, conversation `D0BB80HRZFA`
- Linear target: team `JOH`, issue `JOH-208`
- SharePoint root: `Helios/Governance`
- Rename-gated target: `Yolkster64/helios-control`

## MCP tool catalog

Catalog captured via stdio JSON-RPC (`initialize` -> `notifications/initialized` -> `tools/list`)
against `dotnet run --project src/mcp/HELIOS.Mcp -c Release --no-build` at
`2026-09-06T10:18:04Z` (23 tools total).

- `helios_absorb_status_get`
- `helios_ai_ask`
- `helios_ai_compare`
- `helios_ai_route`
- `helios_ai_status`
- `helios_ai_tandem`
- `helios_auth_status_get`
- `helios_azure_inventory_get`
- `helios_engine_catalog_get`
- `helios_engine_mix_recommend`
- `helios_fabric_plan_get`
- `helios_fleet_plan_get`
- `helios_fleet_status_get`
- `helios_foundry_agent_create`
- `helios_foundry_agent_list`
- `helios_infra_validate`
- `helios_operator_context_sync`
- `helios_operator_next_steps_get`
- `helios_operator_profile_get`
- `helios_operator_profile_save`
- `helios_optimal_provider_get`
- `helios_providers_list`
- `helios_task_routing_get`

## Checksums

Run from repository root:

```bash
sha256sum \
  config/fabric/helios-fabric.v1.json \
  config/schemas/helios-fabric.v1.schema.json \
  scripts/validation/validate_helios_fabric_contract.py \
  docs/migration/yolkster-control-cutover/FABRIC-RUNBOOK.md \
  docs/migration/yolkster-control-cutover/FABRIC-ACTIVATION-CHECKLIST.md
```

| File | SHA-256 |
|---|---|
| config/fabric/helios-fabric.v1.json | `ee770a3c32d5a1804b41b8c9f083c27e8cbd32f035f91c206375d6075d8f0f7a` |
| config/schemas/helios-fabric.v1.schema.json | `7bbcd9e4b04340d93f0c30dc45b740ce3a867f81af3e1cde0530a99c0520a0f9` |
| scripts/validation/validate_helios_fabric_contract.py | `4e91e9f89e1339e568131901884a085328135cf17bd7816a8743d07dbdb9c275` |
| docs/migration/yolkster-control-cutover/FABRIC-RUNBOOK.md | `708acd926d396d8d7f5fd7631464170c491461f461c4f1ea722bcf3713a625d0` |
| docs/migration/yolkster-control-cutover/FABRIC-ACTIVATION-CHECKLIST.md | `e5f2c9f19a4c3291612609c01769af2aa5fd6e95b6ce22e8c682582aca415d84` |
