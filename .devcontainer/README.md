# HELIOS development container

Open the repository in GitHub Codespaces or choose **Reopen in Container** in
VS Code. `devcontainer.json` selects the Microsoft .NET 10 development image;
the portable `HELIOS.sln` projects target `net10.0`.

The configured features add GitHub CLI, Azure CLI, PowerShell, Node, Python 3.11,
and Terraform. The API port is 5170. The Windows GUI uses its separate solution
and needs a Windows host.

`post-create.sh` restores and builds the portable solution, installs the Python
spoke with its test dependency, and links the built `helios-ai` executable. It
derives the CLI output directory from the project file. Required failures stop
initialization. If native compilers are present, their build must pass; otherwise
the hub uses its supported managed implementation. Optional ML packages can be
installed later with `python3 -m pip install -e 'src/ai/python[ml]'`.

After initialization, inspect setup without changing accounts:

```powershell
pwsh scripts/bootstrap/setup-everything.ps1 -Json -RequireReady
```

An incomplete result identifies the remaining work in `readinessIssues` and
`ownerActions`. CLI installation, account login, MCP registration, provider
inference, and Azure deployment have separate acceptance checks. Account sessions
are not provisioned by container initialization.

Use [CONNECTIONS_SETUP.md](../docs/architecture/CONNECTIONS_SETUP.md) for account
setup and [CLIENT_SETUP.md](../docs/mcp/CLIENT_SETUP.md) for Claude, Codex, and
Copilot MCP registration. The older Dockerfile, Compose file, and
`onCreateCommand.sh` are separate legacy surfaces; this configuration does not
invoke them. Their earlier documentation is preserved in
[LEGACY_COMPOSE_REFERENCE.md](LEGACY_COMPOSE_REFERENCE.md).

Image variants are defined in the
[Microsoft development-container image manifest](https://github.com/devcontainers/images/blob/main/src/dotnet/manifest.json).
