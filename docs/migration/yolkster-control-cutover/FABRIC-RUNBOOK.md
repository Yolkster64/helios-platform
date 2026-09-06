# HC-029 Fabric activation runbook

This runbook operationalizes the executable Fabric contract at
`/home/runner/work/helios-platform/helios-platform/config/fabric/helios-fabric.v1.json`.
It is activation-only guidance: production stays disabled and `applyDefault=false`.

## Contract wiring map

1. **Schema contract**  
   Producer: `config/schemas/helios-fabric.v1.schema.json`  
   Consumers: `scripts/validation/validate_helios_fabric_contract.py`,
   `.github/workflows/fabric-contract.yml`, `azure-pipelines.yml`.
2. **MCP contract**  
   Producer: `src/mcp/HELIOS.Mcp/HeliosFabricPlanTools.cs` (`helios_fabric_plan_get`)  
   Consumers: `docs/mcp/CLIENT_SETUP.md`, `scripts/verify/stack-smoke.ps1`.
3. **Connector contract**  
   Producer: `config/fabric/helios-fabric.v1.json` (workspace/team/issue targets)  
   Consumers: owner-run Slack/Linear operations and receipts in
   `FABRIC-ACTIVATION-CHECKLIST.md`.
4. **Rename gate contract**  
   Producer: `config/fabric/helios-fabric.v1.json` (`requiresRepositoryRename`)  
   Consumers: Fabric planner (`effectiveStatus=blocked` until rename completes),
   OIDC/WIF and what-if steps.

## Activation sequence

1. Validate the Fabric contract:
   - `python3 scripts/validation/validate_helios_fabric_contract.py`
2. Validate MCP/AIHub Fabric planner changes:
   - `dotnet test tests/HELIOS.AIHub.Tests -c Release --filter "FullyQualifiedName~Fabric"`
3. Capture stdio JSON-RPC tool-catalog evidence:
   - `pwsh scripts/verify/stack-smoke.ps1 -Json > stack-smoke.fabric.json`
4. Record PR #184 merge SHA and required-check URLs in
   `FABRIC-ACTIVATION-CHECKLIST.md#pr-184-required-check-evidence`.
5. Connect Slack workspace `T0BAFGSNY5P`, resolve `D0BB80HRZFA`, store receipt in
   `FABRIC-ACTIVATION-CHECKLIST.md#slack-receipt`.
6. Confirm `JOH-208` synchronization receipt in
   `FABRIC-ACTIVATION-CHECKLIST.md#linear-receipt`.
7. Publish this runbook, the checklist, and
   `FABRIC-TOPOLOGY-AND-CHECKSUMS.md` to SharePoint; re-read uploads and copy
   URLs/hash confirmations to `#sharepoint-receipt`.
8. After repository rename to `Yolkster64/helios-control`, configure GitHub OIDC
   and Azure DevOps WIF mirror, then run Azure `what-if` with `apply=false` and
   record plan hash in `#development-what-if-receipt`.
9. Execute correlated smoke and rollback rehearsal; store run IDs and verdict in
   `#smoke-and-rollback-receipt`.

## Non-negotiable safety boundaries

- Never store token/key values in config or receipts.
- Do not run deployment `create/apply` in this runbook path.
- Keep GitHub protected environments as the only deployment authority.
- Treat Slack, Linear, SharePoint, and Azure DevOps as coordination/evidence
  surfaces only.
