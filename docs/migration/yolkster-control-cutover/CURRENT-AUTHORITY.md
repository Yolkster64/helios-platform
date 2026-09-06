# HELIOS Current Authority and Rename Boundary

Status date: 2026-09-05

## Current live authority

The current working repository is `Yolkster64/helios-platform` on branch `main`.
It is a GitHub fork of `M0nado/helios-platform`, but it has continued independently
and contains newer work than the M0nado parent. The migration must therefore start
from the Yolkster64 repository and must not overlay the older parent onto it.

Verified planning snapshot:

- repository: `Yolkster64/helios-platform`
- current planning base: `26829ea80e0d50258c6bd867eb155a2ffcca5dd5`
- desired final repository name: `Yolkster64/helios-control`
- desired GUI repository: `Yolkster64/helios-gui`
- production deployment: disabled

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
