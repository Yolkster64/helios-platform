# HELIOS Fabric Activation Checklist

This checklist is an execution gate, not an authorization. Check a box only when a live
system returns a verifiable receipt tied to the exact source SHA.

## 1. Canonical source and repository cutover

- [ ] Current `main` SHA and complete required-check matrix recorded.
- [ ] Repository, fork, issue, pull request, release, package, ruleset, environment,
      webhook, and GitHub App inventory exported.
- [ ] `Yolkster64/helios-control` availability confirmed immediately before cutover.
- [ ] Existing `Yolkster64/helios-platform` renamed in place by an authenticated admin.
- [ ] Redirects, default branch, issues, pull requests, Actions, releases, and app access
      verified after rename.
- [ ] Old repository name remains only in provenance and redirect records.

## 2. WinUI 3 GUI extraction

- [ ] `Yolkster64/helios-gui` created with `main`, README, license, security policy,
      CODEOWNERS, branch rules, and Actions enabled only after review.
- [ ] `src/gui/HELIOS.Shell.sln` extracted with full file/source provenance.
- [ ] Useful visual logic from WPF-era inputs ported to `Microsoft.UI` types rather than
      copied with WPF dependencies.
- [ ] Target framework upgraded to .NET 10 through a dedicated Windows-tested PR.
- [ ] Windows x64 build, tests, accessibility checks, reduced-motion checks, and MSIX
      packaging pass.
- [ ] Core functionality is consumed through versioned contracts; no duplicated core
      business logic remains in the GUI repository.

## 3. HELIOS MCP and AIHub

- [ ] `src/mcp/HELIOS.Mcp` builds on the exact core SHA.
- [ ] MCP tool catalog captured and classified as read, plan, request, or consequential.
- [ ] `helios_fabric_plan_get` returns a sanitized contract and no secret values.
- [ ] No unrestricted shell, arbitrary HTTP, arbitrary SQL, secret readback, or implicit
      external-write tool is exposed.
- [ ] AIHub binds to loopback by default and requires authenticated scopes for every
      non-health route before provider credentials are injected.
- [ ] Request limits, rate limits, timeouts, safe errors, replay protection, atomic state,
      correlation IDs, redaction, audit events, readiness, and recovery tests pass.

## 4. OpenAI, Claude, Copilot, Foundry, Hermes, and XCore

- [ ] OpenAI/Codex project and key/reference selected outside source control.
- [ ] Anthropic/Claude organization and key/reference selected outside source control.
- [ ] Foundry project endpoint and dedicated identity verified.
- [ ] GitHub Copilot instructions and dispatch workflow reviewed.
- [ ] Claude project settings, skills, commands, subagents, MCP configuration, and
      credential-bearing workflow trust boundary reviewed.
- [ ] Hermes/XCore source SHA and licenses frozen before selected-delta import.
- [ ] Routing, budget, timeout, fallback, quality, latency, and redaction tests pass.
- [ ] Model/agent providers cannot approve their own repository, Azure, tenant, secret,
      disk, security, or production actions.

## 5. Collaboration fabric

- [ ] Slack app connected to workspace `T0BAFGSNY5P`.
- [ ] Conversation `D0BB80HRZFA` resolves and the app has only required scopes.
- [ ] Slack signing-secret, timestamp, replay, rate, and idempotency tests pass.
- [ ] Redacted checkpoint posted and concrete message receipt recorded.
- [ ] Linear project `Helios Integration Fabric` and issue `JOH-208` verified.
- [ ] GitHub-to-Linear create-once and update/comment behavior passes dedupe tests.
- [ ] Slack and Linear are notification/work surfaces, never deployment authorities.

## 6. SharePoint governance

- [ ] Site, drive, and `Helios/Governance` folder IDs resolved with selected/delegated
      permission scope.
- [ ] Architecture, Runbooks, Security, Compliance, Releases, Deployment-Evidence,
      Rollback, Checksums, AIHub, and MonadoBlade destinations verified.
- [ ] Publication manifest regenerated immediately before upload.
- [ ] Uploaded bytes and metadata re-read and compared with source hashes.
- [ ] Graph request IDs and file receipts recorded without tokens or secret values.

## 7. Azure and Azure DevOps

- [ ] Renamed GitHub repository identity observed before creating OIDC subjects.
- [ ] `azure-dev`, `azure-test`, and `azure-prod` protected environments configured with
      branch restrictions and reviewers.
- [ ] Plan, image-build, deploy, runtime, and Claude/Foundry identities are separate.
- [ ] RBAC is scoped to environment resource groups or individual resources.
- [ ] Pipeline identities have no broad Key Vault data-plane secret-read permission.
- [ ] Azure DevOps Entra-issued WIF service connections created and verified:
      `helios-control-azure-wif-dev`, `-test`, and `-prod`.
- [ ] Azure DevOps remains validation/evidence only and cannot bypass GitHub approvals.
- [ ] Fresh development Bicep `what-if` executed with `apply=false`.
- [ ] Canonicalized plan hash, exact source SHA, parameters, identity, timestamp, and
      evidence URI recorded.

## 8. End-to-end proof and rollback

- [ ] One correlation ID crosses GitHub, HELIOS MCP/AIHub, Linear, Slack, SharePoint,
      Azure development planning, and evidence storage.
- [ ] Duplicate and replay events do not create duplicate issues/messages/records.
- [ ] Provider, connector, and cloud outages degrade to explicit states rather than
      uncontrolled fallback.
- [ ] Repository URL, package, connector, identity, and Azure development rollback
      rehearsals pass.
- [ ] Source SHAs, imported-path licenses, checksums, release IDs, issue mappings, and
      receipts are sealed in a machine-readable manifest.

## 9. Production decision

- [ ] HC-018 and every inherited production blocker are closed with evidence.
- [ ] Immutable image digest, retention, provenance, SBOM, signature, and rollback pass.
- [ ] Fresh pre-deploy what-if matches the reviewed canonical plan hash.
- [ ] Independent production-owner approval is recorded after plan review.
- [ ] `productionEnabled` and `applyDefault` change only in a separate reviewed PR.

Until the final section is independently approved:

```text
productionEnabled=false
applyDefault=false
live Azure deployment not authorized
```
