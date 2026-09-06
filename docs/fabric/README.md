# HELIOS Fabric

The HELIOS Fabric is the shared control plane connecting:

- `Yolkster64/helios-control` — canonical core after the in-place rename;
- `Yolkster64/helios-gui` — native WinUI 3 Control Center;
- GitHub Actions, protected environments, OIDC, and runners;
- Azure and Azure DevOps WIF validation;
- OpenAI/Codex, Claude Code, Foundry, Copilot, local models, Hermes, and XCore;
- Slack, Linear, SharePoint, and evidence publication;
- local Windows, recovery, security, and USB planning boundaries.

Start locally with either implementation:

```powershell
pwsh -NoProfile -File scripts/setup/Invoke-HeliosFabricSetup.ps1 -Mode Validate
```

```powershell
dotnet run --project src/fabric/HELIOS.Fabric.Cli -- validate .
dotnet run --project src/fabric/HELIOS.Fabric.Cli -- plan .
dotnet run --project src/fabric/HELIOS.Fabric.Cli -- evidence . --output artifacts/helios-fabric
```

These commands validate and plan only. They do not rename repositories, post connector messages, create identities, deploy Azure, change Windows, read secret values, or authorize production.

Read next:

1. `HELIOS_FABRIC_SETUP.md`
2. `FABRIC_ACTIVATION_MATRIX.md`
3. `OPENAI_CLAUDE_CODE_SETUP.md`
4. `../migration/yolkster-control-cutover/CUTOVER-RUNBOOK.md`
5. `../architecture/ADR-0010-WINUI3-ONLY.md`
