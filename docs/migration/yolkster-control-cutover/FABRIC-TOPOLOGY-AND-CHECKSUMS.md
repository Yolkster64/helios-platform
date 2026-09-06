# HC-029 Fabric topology and checksums

This document is the upload packet companion for SharePoint publication and
checksum re-read verification.

## Topology snapshot

- Migration issue: `HC-029`
- Contract file:
  `/home/runner/work/helios-platform/helios-platform/config/fabric/helios-fabric.v1.json`
- Source Fabric PR: `M0nado/helios-platform#184`
- Slack target: workspace `T0BAFGSNY5P`, conversation `D0BB80HRZFA`
- Linear target: team `JOH`, issue `JOH-208`
- SharePoint root: `Helios/Governance`
- Rename-gated target: `Yolkster64/helios-control`

## MCP tool catalog

`helios_fabric_plan_get` is part of the governed `helios_*` MCP tool surface and is
verified by stdio JSON-RPC `tools/list` in `scripts/verify/stack-smoke.ps1`.

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
| config/fabric/helios-fabric.v1.json | `eeea16a6f04ffe640017900e4205a267f3788649846f8ec71c155dce875f76d5` |
| config/schemas/helios-fabric.v1.schema.json | `65ab957ddd130198f9249244df281bf22122d2e70f483e48b9de4898dc46058d` |
| scripts/validation/validate_helios_fabric_contract.py | `61c1e60125c1a4b9a27c9bc28cf2bc998d7296ea1b445a7cacb75cd1813c3c1c` |
| docs/migration/yolkster-control-cutover/FABRIC-RUNBOOK.md | `689b18c7080f2dc5c37ceb555042c9ca0769759b14070c6e85bacb2715d90978` |
| docs/migration/yolkster-control-cutover/FABRIC-ACTIVATION-CHECKLIST.md | `9dd7216241c99b7322bbce5ac2949c2e09962e5e94cab662235f54b5277ede44` |
