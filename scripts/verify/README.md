# scripts/verify

Live verification scripts: each one proves a running property of the stack (not just
that files parse — that is `scripts/build/verify-readiness.ps1`'s job). Report-first:
default runs mutate nothing, and `-Json` emits one machine-readable object (the
`auth-doctor.ps1` convention).

| Script | Proves | Run |
| --- | --- | --- |
| `stack-smoke.ps1` | End-to-end communication across the whole local stack: API launched and probed live (health, reads, the 400 contract, `/v1/metrics` — a 404 on that mapped route is flagged as a stale build or route regression), MCP stdio handshake with the tool count checked against `docs/mcp/CLIENT_SETUP.md` at run time, CLI `status` + `fleet-plan --json`. Never builds (`--no-build` only); exits 1 only on a hard communication failure — degraded providers are the designed pre-owner-unlock state. | `pwsh scripts/verify/stack-smoke.ps1` (also `-Json`, `-DryRun`) |
