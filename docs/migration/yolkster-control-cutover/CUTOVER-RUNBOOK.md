# Yolkster64 HELIOS Control Cutover Runbook

Checkpoint date: 2026-09-06

## HC-001 implementation checkpoint

- Migration PR: `Yolkster64/helios-platform#154`
- Reviewed head: `3daefb0d3734dd05a10ddb864274d59d511f61d4`
- Current-main replay base: `c21ec24f41e61941c7f335b9835aba965c8f298b`
- Merge commit: `50337e3faace1cdf8834db895fa5c5cf1f904a47`
- Required-check status: all required checks pass on the unchanged reviewed head (`CI - Code Validation & Testing` run `33998245259`, `PR Pipeline` run `33998245249`, `Security Scanning` check run `101392441801`).
- Canonical issues: `Yolkster64/helios-platform#156` through `#183`
- Evidence tracker: SharePoint canonicalization checkpoint (linked from PR `#154`) and Linear `JOH-208`
- Safety boundary: no repository rename, Azure mutation, secret write, source archival, or production authorization has occurred.

## HC-001 acceptance checklist

- [x] PR `Yolkster64/helios-platform#154` passes every required check on the unchanged reviewed head.
- [ ] Current repository issues, pull requests, releases, branches, tags, Actions, environments, and rulesets are exported.
- [ ] Repository is renamed in place by an authenticated repository administrator.
- [ ] Default branch and redirects are verified after rename.
- [ ] Active URLs, OIDC subjects, collaboration bindings, and evidence paths are retargeted through reviewed PRs.
- [ ] No source repository is archived until target SHAs, licenses, issue mappings, releases, and CI evidence are recorded.

## Phase 1 — repository truth

1. Merge this branch only after all required checks pass on its exact head.
2. Record the resulting `main` SHA and export issues, pull requests, releases, tags, branches, environments, rulesets, and Actions state.
3. Verify `Yolkster64/helios-control`, `Yolkster64/helios-gui`, and `Yolkster64/Yolkster64` names are available immediately before administration.

## Phase 2 — core rename

1. Rename the existing `Yolkster64/helios-platform` repository to `helios-control`.
2. Do not create a competing copy.
3. Verify the default branch, issue count, open pull requests, releases, Actions, environments, rulesets, and redirects after the rename.
4. Rewrite active repository URLs and OIDC subjects in a new reviewed pull request.
5. Preserve historical links inside provenance and evidence records.

## Phase 3 — GUI extraction

1. Create `Yolkster64/helios-gui` only after the core rename is verified.
2. Extract active WinUI 3 projects, themes, composition services, original assets, packaging, tests, and GUI documentation from `src/gui`.
3. Replace copied core logic with versioned contracts or packages.
4. Reject WPF/UWP and recovered partial-download content.
5. Require Windows App SDK compilation and MSIX packaging on `windows-latest`.

## Phase 4 — selected imports

- Hermes/XCore: selected original contracts/adapters only.
- WindowsDeveloperConfig: declarative HELIOS configuration deltas only.
- Azure SDK forks: package references and thin adapters only.
- Monado Blade: immutable pack/provenance only.

Every import is a separate reviewed pull request with a source SHA and license ledger.

## Phase 5 — collaboration and identity

Retarget Slack, Linear, SharePoint, Azure DevOps, OpenAI/Codex, Claude Code, GitHub Actions, and Azure federation only after the core rename is complete. Write operations must return a receipt; a prepared file is not a published record.

## Phase 6 — Azure development proof

1. Configure protected `azure-dev` on the renamed repository.
2. Create an environment-bound GitHub OIDC credential for `repo:Yolkster64/helios-control:environment:azure-dev`.
3. Configure Azure DevOps WIF as validation/evidence mirror, not a second authority.
4. Run Bicep validation and a development `what-if` with `apply=false`.
5. Preserve the exact plan and source SHA.
6. Require a distinct approval before any deployment request.

Production remains disabled until the production blocker, identity, Key Vault, immutable-image, connector, rollback, and evidence issues are closed.
