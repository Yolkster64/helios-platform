# HC-029 Fabric topology and checksums

This document is the upload packet companion for SharePoint publication and
checksum re-read verification.

## Topology snapshot

- Migration issue: `HC-029`
- Contract file:
  `/home/runner/work/helios-platform/helios-platform/config/fabric/helios-fabric.v1.json`
- Source Fabric PR: `Yolkster64/helios-platform#154` (issue tracker: `#184`)
- Slack target (reconciled 2026-09-09): workspace `T0B8Z1H0MV1`, channel `C0BHWDBHG1W`
- Linear target: team `JOH`, issue `JOH-208`
- SharePoint root: `Helios/Governance`
- Rename-gated target: `Yolkster64/helios-control`

The 2026-09-06 snapshot used workspace `T0BAFGSNY5P` and conversation
`D0BB80HRZFA`; no delivery receipt was recorded. The current
[operator canvas](https://helios-xk97943.slack.com/docs/T0B8Z1H0MV1/F0BGVRND8GK)
has been updated, and the canonical coordination project is
[HELIOS](https://linear.app/641974/project/helios-4f592efea071). Runtime Slack
delivery, SharePoint upload verification and cloud activation are separate
pending receipts. The following MCP catalog remains dated historical evidence.

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
| config/fabric/helios-fabric.v1.json | `521095fdf1d659f05d19a8962213d68c4011ec84b30b03fd5e0dedb97d856bc8` |
| config/schemas/helios-fabric.v1.schema.json | `bdb3a6bce3e483cdab53ad15e32a07d69b23d60828b306865a765f0c1018addf` |
| scripts/validation/validate_helios_fabric_contract.py | `415583a517cf12a6f41de3fdfd0ac7e9b944e670c20e4eb0599f2c485c352b21` |
| docs/migration/yolkster-control-cutover/FABRIC-RUNBOOK.md | `ab08ee4c61539c06530723c985c562d4ed2e0a90847e66c66fc9a7aaf108fbbe` |
| docs/migration/yolkster-control-cutover/FABRIC-ACTIVATION-CHECKLIST.md | `b7e04f16163c8be60e0f7e0d19f5325cdfc06a3f18fadf9c6ce846aacdc8deee` |
