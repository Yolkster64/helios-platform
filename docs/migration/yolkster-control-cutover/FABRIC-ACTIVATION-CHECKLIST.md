# HC-029 Fabric activation checklist

Reference contract: `/home/runner/work/helios-platform/helios-platform/config/fabric/helios-fabric.v1.json`

- [ ] Record PR #184 merge SHA and required-check evidence.
- [x] Validate Fabric schema and instance contract.
- [x] Verify `helios_fabric_plan_get` and catalog contract wiring.
- [ ] Connect Slack workspace `T0BAFGSNY5P` and resolve `D0BB80HRZFA`.
- [ ] Keep JOH-208 and HC-029 synchronized idempotently.
- [ ] Publish runbook/checklist/topology/checksums to SharePoint and re-read uploads.
- [ ] Configure GitHub OIDC and Azure DevOps WIF mirror after rename.
- [ ] Run development Azure `what-if` with `apply=false` and capture plan hash.
- [ ] Complete correlated smoke tests and rollback rehearsal.

## PR-184 required-check evidence

- Merge SHA: `pending`
- Source PR URL: `https://github.com/M0nado/helios-platform/pull/184`
- Required checks:
  - CI - Code Validation & Testing: `pending`
  - PR Pipeline: `pending`
  - Infra Validation: `pending`
- Evidence links: `pending`

## Slack receipt

- Workspace: `T0BAFGSNY5P`
- Conversation: `D0BB80HRZFA`
- Message permalink or timestamp: `pending`
- Verification note: `pending`

## Linear receipt

- Team: `JOH`
- Issue: `JOH-208`
- Sync evidence (Linear URL + GitHub comment URL): `pending`
- Idempotency re-run note: `pending`

## SharePoint receipt

- Root: `Helios/Governance`
- Uploaded files:
  - `FABRIC-RUNBOOK.md`: `pending`
  - `FABRIC-ACTIVATION-CHECKLIST.md`: `pending`
  - `FABRIC-TOPOLOGY-AND-CHECKSUMS.md`: `pending`
- Re-read/hash verification note: `pending`

## Development what-if receipt

- Rename completed: `false`
- OIDC subject used: `pending`
- ADO WIF mirror receipt: `pending`
- what-if command: `pending`
- Plan hash (sha256): `pending`
- Run timestamp (UTC): `pending`

## Smoke and rollback receipt

- Smoke run IDs/evidence: `pending`
- Rollback rehearsal evidence: `pending`
- Final status: `BLOCKED (awaiting external owner actions)`
