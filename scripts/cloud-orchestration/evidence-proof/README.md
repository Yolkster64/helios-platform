# SharePoint End-to-End Evidence Proof

One-command, repeatable proof that the HELIOS SharePoint evidence pipeline works
end to end against a live tenant. This is the runner for the owner/admin-gated
task "run the end-to-end SharePoint evidence proof" from the HELIOS tenant
activation wave.

## What it proves

| Stage | What is exercised |
|-------|-------------------|
| 1. Authentication | Graph sign-in (`Sites.ReadWrite.All`) plus site and drive resolution |
| 2. Folder operations | Creates and verifies `Helios/Governance/Deployment-Evidence/<CorrelationId>` with the GitHub, Azure, Identity-RBAC, Connectors, Hermes-AIHub, Rollback, and Checksums subfolders |
| 3. Upload transports | **Both** transports independently: a direct `PUT` to `graph.microsoft.com` and an upload session `PUT` to the SharePoint file-transfer host (the transport currently returning HTTP 407) |
| 4. Round-trip | Downloads each uploaded file back and verifies its SHA-256 against the local hash |
| 5. Checksums manifest | Publishes a correlation-bound checksum manifest into the `Checksums` subfolder |

The run emits a JSON proof report (`logs/sharepoint-evidence-proof-<timestamp>.json`)
recording every stage with status, HTTP status code, and diagnostics.

## Prerequisites (owner/admin-gated)

- PowerShell 7+ with the `Microsoft.Graph.Authentication` module
  (`Install-Module Microsoft.Graph.Authentication`).
- An account or app registration consented for `Sites.ReadWrite.All` on the
  target site. Tenant consent is one of the owner/admin gates from the
  activation wave.
- Network egress to `graph.microsoft.com` **and** `*.sharepoint.com` upload
  hosts (see HTTP 407 note below).

## Usage

```powershell
.\Invoke-SharePointEvidenceProof.ps1 `
    -SiteId "yourtenant.sharepoint.com:/sites/Helios" `
    -CorrelationId "0dcfdc41-7e6b-478f-a53f-866cdae93ffd"
```

Parameters:

- `-SiteId` (required): Graph site identifier, e.g. `hostname:/sites/name` or a site GUID.
- `-CorrelationId`: reuse the activation-wave correlation ID to write into the
  existing evidence container; omit to generate a fresh one.
- `-DriveName`: document library name (default `Documents`).
- `-LargeFileSizeMB`: size of the upload-session payload (default 4 MB).
- `-SkipLargeUpload`: skip the upload-session transport (e.g. to prove only the
  Graph direct-PUT path).

Exit codes: `0` = fully proven, `2` = partially proven (upload transport blocked
by HTTP 407), `1` = failed.

## The HTTP 407 failure mode

Upload sessions do not go to `graph.microsoft.com` — Graph returns an
`uploadUrl` on a SharePoint file-transfer host, and the chunked `PUT`s go there
directly. An outbound proxy that allowlists `graph.microsoft.com` but not the
`*.sharepoint.com` upload hosts (or that requires authentication the transfer
client never presents) returns **HTTP 407 Proxy Authentication Required** on
exactly this transport, while folder operations and small direct PUTs (which
stay on `graph.microsoft.com`) keep working. This matches the risk noted in the
activation-wave update.

When the runner hits a 407 it records the stage as `Blocked` (not `Failed`),
captures the effective system proxy and `HTTP(S)_PROXY`/`NO_PROXY` environment
variables in the report, and exits `2` so the partial proof is still usable as
evidence.

Remediation checklist:

1. Allowlist `*.sharepoint.com` (and `*.svc.ms`) on the outbound proxy for the
   host running the proof.
2. If the proxy requires authentication, configure it for the whole session,
   e.g. `[System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials`, or set
   `HTTPS_PROXY` with credentials.
3. Re-run the proof; the verdict flips from `PartiallyProven-407Blocked` to
   `Proven` once both transports pass.
