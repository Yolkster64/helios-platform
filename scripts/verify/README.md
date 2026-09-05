# scripts/verify

Live verification scripts: each one proves a running property of the stack (not just
that files parse — that is `scripts/build/verify-readiness.ps1`'s job). Report-first:
default runs mutate nothing, and `-Json` emits one machine-readable object (the
`auth-doctor.ps1` convention).

| Script | Proves | Run |
| --- | --- | --- |
| `stack-smoke.ps1` | End-to-end communication across the whole local stack: API launched and probed live (health, reads, the 400 contract, `/v1/metrics` — a 404 on that mapped route is flagged as a stale build or route regression), MCP stdio handshake with the tool count checked against `docs/mcp/CLIENT_SETUP.md` at run time, CLI `status` + `fleet-plan --json`. Never builds (`--no-build` only); exits 1 only on a hard communication failure — degraded providers are the designed pre-owner-unlock state. | `pwsh scripts/verify/stack-smoke.ps1` (also `-Json`, `-DryRun`) |

## MCP transport and repository evidence

`python3 scripts/verify/mcp-health.py` verifies the built local MCP server through
initialize, tools/list, and ping. It calls no tools or providers. The portable .NET
workflow runs it after build; setup-all includes its result as `mcp-runtime`.

`python3 scripts/verify/repository-health.py --inventory` checks current repository
inputs. The Continuous Verification workflow generates JSON and Markdown from actual
job conclusions, including failed, skipped, cancelled, and missing evidence. These
reports describe repository checks; they do not establish runtime or deployment health.

Offline regression checks (Python 3.11+ for TOML configuration parsing):

```bash
python3 -m unittest discover -s scripts/verify/tests -p 'test_*health.py'
```
