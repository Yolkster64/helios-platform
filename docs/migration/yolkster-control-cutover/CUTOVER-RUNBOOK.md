# Yolkster64 HELIOS Control Cutover Runbook

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
