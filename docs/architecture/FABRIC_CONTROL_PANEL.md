# HELIOS Fabric Control Panel

The WinUI 3 shell exposes **Fabric Control** beside AI Hub as the read-only operator view for cross-system integration readiness.

It surfaces sanitized state for GitHub, Claude Code, Azure OIDC, Microsoft Foundry, Key Vault/OpenAI/Codex, Hermes/AIHub, and the Slack/Linear/Teams/SharePoint broker lane. It never displays secret values and never performs cloud writes.

Operator actions provided by the page:

```powershell
pwsh scripts/bootstrap/claude-foundry-oidc-setup.ps1 -Repo Yolkster64/helios-platform
pwsh scripts/bootstrap/claude-foundry-oidc-setup.ps1 -Repo Yolkster64/helios-platform -VerifyOnly -SkipGitHubVariables
```

The page links to the Azure portal, repository, Claude Foundry workflow, and dedicated OIDC tracking issue. Live provider health remains on the AI Hub page; Fabric Control reports integration readiness and governance boundaries.

GUI changes are compiled on Windows by `.github/workflows/gui-windows.yml` using `src/gui/HELIOS.Shell.sln`.
