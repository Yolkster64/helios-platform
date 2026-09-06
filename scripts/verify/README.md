# scripts/verify

Live verification scripts: each one proves a running property of the stack (not just
that files parse — that is `scripts/build/verify-readiness.ps1`'s job). Report-first:
default runs mutate nothing, and `-Json` emits one machine-readable object (the
`auth-doctor.ps1` convention).

| Script | Proves | Run |
| --- | --- | --- |
| `stack-smoke.ps1` | End-to-end communication across the whole local stack: API launched and probed live (health, reads, the 400 contract, `/v1/metrics` — a 404 on that mapped route is flagged as a stale build or route regression), MCP stdio handshake with the tool count checked against `docs/mcp/CLIENT_SETUP.md` at run time, CLI `status` + `fleet-plan --json`. Never builds (`--no-build` only); exits 1 only on a hard communication failure — degraded providers are the designed pre-owner-unlock state. | `pwsh scripts/verify/stack-smoke.ps1` (also `-Json`, `-DryRun`) |
| `rest-connect.ps1` | The two control planes answer real REST calls with non-interactively acquired tokens: GitHub (`api.github.com` — anonymous transport-control probe first, so a credential-injecting proxy is detected and readiness is attributed to the transport, never to a specific token; then GH_TOKEN → GITHUB_TOKEN → `gh auth token`) and Azure ARM (`management.azure.com` — CI OIDC reported, env service-principal via raw client-credentials REST, managed identity/IMDS with a hard 2s no-proxy bound, cached az token; interactive login never runs, and the certificate flow is reported, not executed, because `az login` would mutate the shared profile). needs-owner prints the exact one-time MFA + `setup-tenant.ps1 -OpsIdentity` unlock. | `pwsh scripts/verify/rest-connect.ps1` (also `-Json`, `-DryRun`) |

A fully configured environment service principal that cannot obtain a token
stops the Azure probe before later managed-identity or CLI sources, matching
DefaultAzureCredential's deployed-credential continuation policy. Token-endpoint
400/401/403 responses require repairing the selected credential or deliberately
selecting another mode; transient and malformed responses remain retryable.
No credential is changed by this probe.

Offline regressions (all HTTP/CLI boundaries replaced with inert fixtures):

```powershell
pwsh -NoProfile -File scripts/verify/tests/test_auth_continuation.ps1
pwsh -NoProfile -File scripts/verify/tests/test_auth_readiness.ps1
pwsh -NoProfile -File scripts/verify/tests/test_auth_boundaries.ps1
pwsh -NoProfile -File scripts/verify/tests/test_auth_config.ps1
```

These cases cover rejected/transient environment credentials, successful token
acquisition, secret-safe evidence, and Unix/Windows environment-name comparisons.
[Azure Identity continuation policy](https://learn.microsoft.com/en-us/dotnet/api/overview/azure/identity-readme#continuation-policy).

`test_auth_config.ps1` covers the config contracts the hub dereferences (an enabled
CLI entry's `argsTemplate`), the command shapes CliProcessAgent launches the same way
it checks readiness (bare names and absolute paths; a relative path with a separator
is refused), and the rule that a selected Azure credential is proven only by
`rest-connect.ps1` acquiring a token through it — a cached az identity whose client
and tenant match is context, never proof — including the secretless `azure-openai`
entry's endpoint and Entra-fallback verdicts.
