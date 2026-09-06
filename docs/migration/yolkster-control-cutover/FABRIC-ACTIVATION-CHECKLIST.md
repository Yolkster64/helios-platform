# HC-029 Fabric activation checklist

Reference contract: `/home/runner/work/helios-platform/helios-platform/config/fabric/helios-fabric.v1.json`

- [x] Record Cutover/Fabric PR #154 merge SHA and required-check evidence for issue #184.
- [x] Validate Fabric schema and instance contract.
- [x] Verify `helios_fabric_plan_get` and catalog contract wiring.
- [ ] Connect Slack workspace `T0BAFGSNY5P` and resolve `D0BB80HRZFA`.
- [ ] Keep JOH-208 and HC-029 synchronized idempotently.
- [ ] Publish runbook/checklist/topology/checksums to SharePoint and re-read uploads.
- [ ] Configure GitHub OIDC and Azure DevOps WIF mirror after rename.
- [ ] Run development Azure `what-if` with `apply=false` and capture plan hash.
- [ ] Complete correlated smoke tests and rollback rehearsal.

## PR-154 required-check evidence

- Merge SHA: `50337e3faace1cdf8834db895fa5c5cf1f904a47`
- Source PR URL: `https://github.com/Yolkster64/helios-platform/pull/154`
- Required checks:
  - CI - Code Validation & Testing: `success` (`https://github.com/Yolkster64/helios-platform/actions/runs/33998245259`, head `3daefb0d3734dd05a10ddb864274d59d511f61d4`)
  - PR Pipeline: `success` (`https://github.com/Yolkster64/helios-platform/actions/runs/33998245249`, head `3daefb0d3734dd05a10ddb864274d59d511f61d4`)
  - Infra Validation: `n/a` (no pull_request run for this head; branch filter query returned zero runs)
- Evidence links:
  - Merge commit: `https://github.com/Yolkster64/helios-platform/commit/50337e3faace1cdf8834db895fa5c5cf1f904a47`
  - CI workflow run: `https://github.com/Yolkster64/helios-platform/actions/runs/33998245259`
  - PR pipeline workflow run: `https://github.com/Yolkster64/helios-platform/actions/runs/33998245249`
  - Infra workflow branch query: `https://github.com/Yolkster64/helios-platform/actions/workflows/infra-validate.yml`

## Slack receipt

- Workspace: `T0BAFGSNY5P`
- Conversation: `D0BB80HRZFA`
- Message permalink or timestamp: `pending`
- Verification note: `pending`

## Linear receipt

- Team: `JOH`
- Issue: `JOH-208`
- Sync evidence (Linear URL + GitHub comment URL): `https://linear.app/641974/issue/JOH-208` + `https://github.com/Yolkster64/helios-platform/issues/184#issuecomment-5555420685`
- Idempotency re-run note: `Linkback exists; explicit connector re-run evidence is still pending.`

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

- Smoke run IDs/evidence: `scripts/verify/stack-smoke.ps1 -Json` at `2026-09-06T10:20:24Z`, summary `ok=5,degraded=0,failed=0,buildMissing=0`
- Rollback rehearsal evidence: `pending`
- Final status: `BLOCKED (awaiting external owner actions)`
