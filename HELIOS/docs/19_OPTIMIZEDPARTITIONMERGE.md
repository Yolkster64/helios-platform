# OPTIMIZEDPARTITIONMERGE

## Purpose

Bring back the original HELIOS partition idea and merge it with the newer semantic partition model into one optimized layout.

## Design principle

Use physical partitioning where it improves control, security, and performance. Use logical folders where rigid partitions would waste space.

## Physical disks

### SSD0 / Drive 0: Precision disk

Fast, trusted, low-latency, intentionally underfilled. Target total active use under roughly 1TB.

Primary roles:

- CORE
- DEVDRIVE
- COMMON
- CROSS
- VAULT
- reserved / unallocated performance headroom

### SSD1 / Drive 1: Heavy domain disk

Bulk, flexible, growth-oriented. Prefer fewer hard partitions unless the user intentionally wants strict drive letters.

Primary roles:

- Games
- MusicStudio
- Work
- Media
- ServerNode
- Cleanout / quarantine / temp

## Canonical optimized model

### C: CORE (SSD0)

- Windows
- drivers
- firmware
- security stack
- Microsoft 365 core
- Razer / NVIDIA / Intel tooling

### P: DEVDRIVE (SSD0)

- DevDrive / ReFS if enabled
- repos
- containers
- SDKs
- Python / Node
- MCP / Codex
- build cache

### D: COMMON (SSD0)

- trusted personal and shared references
- docs
- recovery
- licenses
- mail bridge
- media common

### X: CROSS (SSD0)

- cross-role shared infrastructure
- GPU / CPU / thermal / validation artifacts
- AI runtime support
- connectors
- productivity / Power / Copilot / BI support

### V: VAULT (SSD0 or VHDX mounted letter)

- encrypted helper vault
- certificates
- recovery references
- BitLocker refs
- key maps
- import staging

### SSD0 reserved space

Leave remaining space unallocated or unused as performance headroom and future expansion.

## SSD1 domain model

Recommended flexible model: one large E: partition with strict top-level domains.

### E:\Games

Target: up to ~1TB.

- Libraries
- Mods
- Saves
- Captures
- Plugins
- ShaderCache

### E:\MusicStudio

Target: ~300GB+ depending on samples.

- Projects
- Samples
- Plugins
- Presets
- Exports
- Recording
- Masters

### E:\Work

- Docs
- Projects
- Office
- MailExports
- Planning
- Power
- PowerBI
- PowerPlatform
- Copilot365

### E:\Media

- Downloads
- Watch
- Audio
- Video
- Archive

### E:\Sandbox

- VMs
- Unsafe
- Temp
- Snapshots

### E:\ServerNode

Target: ~50GB+ depending on logs and queues.

- Automation
- Runs
- Logs
- State
- Queues
- Schedules
- AgentInbox
- AgentOutbox
- Approvals

### E:\Cleanout

- Incoming
- Review
- Blocked
- TempInstall
- Cleanup
- Extracted
- PurgeQueue

## Alternative strict-letter model

If strict separation is preferred:

- E: Games
- M: MusicStudio
- W: Work
- B: Media
- S: ServerNode
- T: Cleanout

## Final recommendation

Use strict letters on SSD0 for Core / DevDrive / Common / Cross / Vault. Use one large flexible SSD1 partition unless strong isolation is needed. This preserves performance, minimizes wasted space, and keeps HELIOS semantics intact.
