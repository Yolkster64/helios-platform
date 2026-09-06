# HELIOS Current Authority and Rename Boundary

Status date: 2026-09-06

## Current live authority

The current working repository is `Yolkster64/helios-platform` on branch `main`.
It is a GitHub fork of `M0nado/helios-platform`, but it has continued independently
and contains newer work than the M0nado parent. The migration must therefore start
from the Yolkster64 repository and must not overlay the older parent onto it.

Verified planning snapshot:

- repository: `Yolkster64/helios-platform`
- current planning base: `813a020f1fc0eaa9094d49406670d1c649154479`
- desired final repository name: `Yolkster64/helios-control`
- desired GUI repository: `Yolkster64/helios-gui`
- production deployment: disabled

Implementation checkpoint:

- migration PR: `Yolkster64/helios-platform#154`
- reviewed head: `3daefb0d3734dd05a10ddb864274d59d511f61d4`
- replay base on current `main`: `c21ec24f41e61941c7f335b9835aba965c8f298b`
- required checks: cutover contract, PR pipeline, .NET/build variants/module builds, complete CI, AI review, and Python Spoke are green; final security-scan is still running
- canonical issue range: `Yolkster64/helios-platform#156` through `#183`
- external tracking: SharePoint canonicalization checkpoint (linked from PR `#154`) and Linear `JOH-208`
- boundary confirmation: no repository rename, Azure mutation, secret write, source archival, or production authorization has occurred

## Cutover rule

Do not create a second competing product repository by copying this tree into an
empty `helios-control`. Merge this migration branch first, verify the complete CI
set, then rename the existing Yolkster64 repository through a repository-administrator
session. That preserves this repository's issue, pull-request, release, branch, and
commit history as one authority.

If the rename cannot be performed, stop and open an administrator gate. A bootstrap
copy is a recovery option, not the default.

## Authority after rename

- `Yolkster64/helios-control`: canonical product/control monorepo.
- `Yolkster64/helios-gui`: WinUI 3 desktop shell and reusable GUI libraries.
- `Yolkster64/Yolkster64`: public profile README only.
- `Yolkster64/.github-enterprise-control`: repository governance only.
- `M0nado/helios-platform`: historical upstream and provenance source.
- `Yolkster64/monado-blade`: immutable integration-lab history until archival proof.
- `Yolkster64/hermes-fleet-platforms`: specialist lab until selected-path import proof.

No source repository is deleted automatically. Archival occurs only after target
commits, checksums, licenses, issue mappings, and CI evidence are recorded.
