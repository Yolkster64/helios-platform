# Yolkster64 HELIOS Fork Inventory and Disposition

This inventory is based on authenticated repository metadata observed on 2026-09-05. It controls migration policy; it is not permission to archive or delete.

| Repository | Relationship | Disposition |
|---|---|---|
| `Yolkster64/helios-platform` | Fork of `M0nado/helios-platform`; newer active line | Rename in place to `Yolkster64/helios-control` after CI and administrator review |
| `Yolkster64/WindowsDeveloperConfig` | Fork of `microsoft/WindowsDeveloperConfig` | Import only HELIOS-owned declarative configuration deltas; retain Microsoft provenance |
| `Yolkster64/azure-sdk-for-net` | Fork of `Azure/azure-sdk-for-net` | Do not vendor; use released NuGet packages and thin HELIOS adapters |
| `Yolkster64/hermes-agent-github` | Fork of `NousResearch/hermes-agent` | Keep upstream reference; import only original HELIOS adapters/contracts with license evidence |
| `Yolkster64/hermes-fleet-platforms` | Original Yolkster64 repository | Import selected HELIOS-owned runtime, routing, skills, tests, and interfaces after hash review |
| `Yolkster64/monado-blade` | Original Yolkster64 integration lab | Preserve immutable integration artifacts and provenance; archive only after target proof |
| `Yolkster64/actions-runner-controller` | Upstream infrastructure fork/copy candidate | Treat as external infrastructure; never copy wholesale into product source |

## Import rules

1. Capture the exact source commit before selecting files.
2. Produce a path-by-path hash and license plan.
3. Reject generated output, caches, logs, `.crdownload` files, credentials, and machine-specific state.
4. Import original HELIOS deltas only; do not import an upstream project's CI/release machinery.
5. Build and test in the destination before any source repository is archived.
6. Record source URL, source SHA, target SHA, file hashes, license, and reviewer receipt.

## Azure SDK rule

Azure SDK source repositories remain upstream development references. HELIOS consumes released packages through central package management and keeps only typed adapters, provider abstractions, tests, and examples in the product repository.
