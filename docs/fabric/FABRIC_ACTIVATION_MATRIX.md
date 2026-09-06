# HELIOS Fabric Activation Matrix

| Plane | Source of truth | Readiness proof | First permitted write | Production condition |
|---|---|---|---|---|
| GitHub core | `Yolkster64/helios-control` after in-place rename | Repository ID, redirect, `main` SHA, rulesets, environments, CI | Reviewed pull request | Protected environment plus independent production approval |
| GitHub GUI | `Yolkster64/helios-gui` | Windows x64 build, WinUI contract, MSIX artifact, provenance | Reviewed GUI pull request | Signed package, rollback, local approval |
| GitHub governance | `Yolkster64/.github-enterprise-control` | Ruleset/runner/repository-factory validation | Pilot repository policy | Enterprise-owner approval and rollback plan |
| Azure | Bicep in canonical core | Exact-source compile and development what-if JSON/hash | Separately approved dev deployment | Fresh production what-if, immutable image, reviewers, runtime identity proof |
| Azure DevOps | `Heli0sDev` | WIF service-connection read, pipeline validation, artifact receipt | Development what-if/evidence mirror | Never independent deployment authority |
| SharePoint | `Helios/Governance` | Site/drive/folder IDs and readback hash | Manifested governance upload | Selected/delegated permission and verified bytes |
| Slack | `T0BAFGSNY5P / D0BB80HRZFA` | App auth and conversation lookup | Approved status message | Never an approval or deployment authority |
| Linear | `Helios Integration Fabric` | Project and JOH-208 read | Idempotent status/comment update | Never an approval or deployment authority |
| OpenAI/Codex | AIHub provider contract | Project/reference metadata and bounded health request | Typed model request | Budget, tracing, redaction, Key Vault reference, production approval |
| Claude Code | Repository policy and project MCP | Version, instructions, plugin/MCP validation, tests | Reviewed branch/PR preparation | No merge or deployment authority |
| Microsoft Copilot/Foundry | Agent registry and scoped Graph/Foundry identity | Package validation and permission inventory | Dev/test agent publication request | Tenant-admin approval and data-boundary proof |
| Hermes/XCore | AIHub/fleet contracts | Worker registry, routing/evaluation tests, redacted memory | Approved bounded task execution | Cannot self-enable tools, approval, or deployment |
| Windows/Recovery | Local reviewed scripts/manifests | AST parsing, simulation, backups, exact device identity | Explicit local plan/preview | Physical confirmation and rollback evidence |

## Global fail-closed rules

A plane remains inactive when any required identity, scope, resource, protected environment, source SHA, evidence artifact, reviewer, or rollback proof is absent.

The following never count as successful activation:

- a prepared document without a remote file receipt;
- a Slack URL that the connected app cannot resolve;
- a GitHub branch without exact-head CI;
- an Azure template without a current what-if;
- an environment variable name without a stored reference;
- an issue description without executed validation;
- a model/provider key created outside the approved project or vault path;
- a fork copied wholesale without license and source-SHA review.
