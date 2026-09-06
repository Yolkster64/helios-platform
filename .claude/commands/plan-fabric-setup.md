Plan the HELIOS Fabric setup without changing external state.

1. Read `CLAUDE.md`, `AGENTS.md`, `config/fabric/helios-fabric.v1.json`,
   `docs/fabric/HELIOS_FABRIC_SETUP.md`, and
   `docs/fabric/FABRIC_ACTIVATION_CHECKLIST.md`.
2. Run the Fabric validator, sanitized planner, Fabric unit tests, Yolkster cutover
   validator, and HELIOS MCP Release build.
3. Inspect named environment references only when explicitly requested. Never print,
   compare, hash, or persist secret values.
4. Summarize:
   - canonical core and GUI targets;
   - ready, approval-required, connection-required, and admin-binding phases;
   - failing tests or contract violations;
   - exact external administrator actions still required;
   - evidence and rollback outputs expected from the next phase.
5. Propose only a reviewed branch or issue update. Do not merge, rename repositories,
   configure identities, post messages, publish SharePoint files, deploy Azure, change
   workstation state, or use an unrestricted shell/network fallback.

Binding product rules:

```text
C# / .NET 10
WinUI 3
Microsoft.UI.Xaml
Microsoft.UI.Composition
no WPF/UWP fallback
productionEnabled=false
applyDefault=false
```
