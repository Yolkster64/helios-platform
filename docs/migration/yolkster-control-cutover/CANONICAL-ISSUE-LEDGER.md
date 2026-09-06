# Canonical HELIOS Issue Ledger (HC-001 through HC-028)

> Current issue host: `Yolkster64/helios-platform`. These issues must survive the in-place rename to `Yolkster64/helios-control`; do not duplicate them in a competing repository.

Core target: `Yolkster64/helios-control`  
GUI target: `Yolkster64/helios-gui`  
Profile target: `Yolkster64/Yolkster64`

| ID | Title | Milestone | Source provenance |
|---|---|---|---|
| HC-001 | [EPIC] Cut over canonical authority to Yolkster64/helios-control | Canonical Cutover | M0nado/helios-platform |
| HC-002 | Lock WinUI 3-only desktop architecture and remove WPF/UWP drift | Desktop Control Center | M0nado PR #179 |
| HC-003 | Preserve merged typed communication and integration-broker contracts | Canonical Cutover | M0nado PRs #180/#181 |
| HC-004 | Migrate HELIOS Control Fabric plugin and 11 read/plan MCP tools | Agent Fabric | M0nado PR #190 |
| HC-005 | Rewrite GitHub OIDC and Azure contracts for Yolkster64/helios-control | Azure Development Activation | M0nado PRs #182/#193 |
| HC-006 | Configure Azure DevOps Entra-issued WIF validation and evidence mirror | Azure Development Activation | M0nado PR #169 |
| HC-007 | Deep Claude Code project integration with governed MCP and subagents | Agent Fabric | Current Claude/Foundry line |
| HC-008 | Unify Claude, Codex, Copilot, OpenAI, Foundry, Hermes, and XCore provider contracts | Agent Fabric | Communication/broker line |
| HC-009 | Harden AIHub runtime before provider credentials or external bind | Agent Fabric | AIHub prototype audit |
| HC-010 | Consolidate Windows environment repair and boot-security lanes | Windows Security | M0nado PRs #163/#166/#186 |
| HC-011 | Implement Platform 2 storage, profiles, vault, and quarantine contracts | Desktop Control Center | M0nado PRs #179/#184 |
| HC-012 | Extract and finish reusable WinUI 3 Control Center shell | Desktop Control Center | M0nado issue #172 |
| HC-013 | SOLGATE guarded USB Wizard: simulation, WinPE, VHDX, and signed drivers | USB and Recovery | M0nado issue #171 |
| HC-014 | Publish canonical governance and deployment evidence to SharePoint | Collaboration Activation | Evidence program |
| HC-015 | Activate idempotent Slack and Linear synchronization for the new canonical repo | Collaboration Activation | Connector program |
| HC-016 | Bind OpenAI and Anthropic providers through governed secret references | Agent Fabric | Provider program |
| HC-017 | Repository convergence: remove duplicate implementations and archive superseded branches | Canonical Cutover | M0nado issue #149 |
| HC-018 | Keep production blocked until Azure activation defects and evidence gates close | Azure Development Activation | M0nado issues #162/#192 |
| HC-019 | [EPIC] Inventory and collapse the Yolkster64 fork network into core plus GUI | Repository Consolidation | Authenticated Yolkster inventory |
| HC-020 | Rename the active Yolkster64/helios-platform repository to Yolkster64/helios-control | Repository Consolidation | Current fork authority |
| HC-021 | Extract the Control Center into Yolkster64/helios-gui and enforce WinUI 3 only | Desktop Control Center | src/gui + historical Control Center |
| HC-022 | Import unique Hermes/XCore contracts and archive the specialist lab | Agent Fabric | Yolkster64/hermes-fleet-platforms |
| HC-023 | Convert WindowsDeveloperConfig fork work into HELIOS-owned declarative configs | Repository Consolidation | microsoft/WindowsDeveloperConfig |
| HC-024 | Replace Azure SDK source forks with versioned packages and thin HELIOS adapters | Repository Consolidation | Azure SDK upstreams |
| HC-025 | Publish the Yolkster64 GitHub profile README and canonical project map | Public Profile and Handoff | Yolkster64 profile |
| HC-026 | Retarget Slack, Linear, SharePoint, Azure DevOps, OpenAI, and Claude to Yolkster64 authority | Public Profile and Handoff | Collaboration map |
| HC-027 | Archive superseded Yolkster64 and M0nado repositories after target proof | Repository Consolidation | Source archive policy |
| HC-028 | Seal provenance, licenses, release redirects, and final two-repository cutover evidence | Canonical Cutover | Final evidence |

Every live issue body must include an idempotency marker of the form `<!-- helios-migration-id: HC-NNN -->` and must state that production remains disabled unless a separate authorization issue explicitly says otherwise.

Historical links preserve provenance; they do not confer authority on M0nado after verified cutover.
