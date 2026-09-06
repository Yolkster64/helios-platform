#Requires -Version 7
<#
.SYNOPSIS
PowerShell twin of scripts/bootstrap/cloud-shell-setup.sh: runs the SAME bring-up by
calling the bash script (never reimplementing it), or prints the exact steps when no
bash is available.

.DESCRIPTION
The bash script is the single implementation of the cross-LLM bring-up (CLI fleet,
device-code logins, Cloud Shell persistence, env wiring, smoke test, readiness
inventory). Keeping one implementation is deliberate: two copies of an install/login
sequence drift, and the drift shows up as a Cloud Shell that behaves differently from
a workstation. This wrapper only translates switches to the bash flags and forwards
the exit code.

Without bash (a Windows host without Git Bash), the steps are printed as the exact
commands to run, and the script exits 2 - nothing is guessed or re-implemented.

.PARAMETER SkipAuth
Forward --skip-auth (no device-code logins).

.PARAMETER SkipSmoke
Forward --skip-smoke (no dotnet build / AIHub smoke test).

.PARAMETER VerifyOnly
Forward --verify-only (read-only: no installs, no logins, no persistence).

.PARAMETER NoPersist
Forward --no-persist (no Cloud Shell npm prefix / shell-hook persistence).

.EXAMPLE
pwsh scripts/bootstrap/cloud-shell-setup.ps1 -SkipSmoke

.EXAMPLE
pwsh scripts/bootstrap/cloud-shell-setup.ps1 -VerifyOnly

.NOTES
Exit codes: the bash script's own (0 = ready, 1 = a required step failed or, under
-VerifyOnly, an auth lane is not ready); 2 = no usable bash on PATH (steps printed).
Secrets: nothing is read or printed here; the bash script's contract applies.
#>
[CmdletBinding()]
param(
    [switch]$SkipAuth,

    [switch]$SkipSmoke,

    [switch]$VerifyOnly,

    [switch]$NoPersist
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot 'cloud-shell-setup.sh'
$shArgs = @(
    if ($SkipAuth) { '--skip-auth' }
    if ($SkipSmoke) { '--skip-smoke' }
    if ($VerifyOnly) { '--verify-only' }
    if ($NoPersist) { '--no-persist' }
)

# On Windows the System32 bash.exe is the WSL launcher: it runs inside the WSL
# distro, where this checkout's Windows path does not exist as-is, so Git Bash is
# preferred there and the WSL launcher is not used silently.
$bash = $null
if ($IsWindows) {
    # Only roots that exist are joined: ${env:ProgramFiles(x86)} is absent on 32-bit
    # Windows and Join-Path throws on a null Path under Set-StrictMode, which would end
    # the script with exit 1 before the PATH lookup and the documented exit-2 path.
    $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($root in @($roots)) {
        $candidate = Join-Path $root 'Git' 'bin' 'bash.exe'
        if (Test-Path -LiteralPath $candidate) { $bash = Get-Item -LiteralPath $candidate; break }
    }
}
if (-not $bash) {
    $found = Get-Command bash -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found -and -not ($IsWindows -and $found.Source -like '*\System32\*')) { $bash = Get-Item -LiteralPath $found.Source }
}

if ($bash) {
    Write-Host ('cloud-shell-setup.ps1: running bash {0} {1}' -f $scriptPath, ($shArgs -join ' '))
    & $bash.FullName $scriptPath @shArgs
    exit $LASTEXITCODE
}

Write-Host 'cloud-shell-setup.ps1: no usable bash on PATH (Git Bash on Windows, or any Linux/macOS shell; Cloud Shell ships it).'
Write-Host 'The steps the bash script performs, as the exact commands to run yourself:'
Write-Host ('  bash {0} {1}' -f $scriptPath, ($shArgs -join ' '))
Write-Host '  1. CLI fleet: az, gh (https://aka.ms/azure-cli, https://cli.github.com), then'
Write-Host '     npm install -g @anthropic-ai/claude-code @openai/codex @github/copilot'
if (-not $SkipAuth -and -not $VerifyOnly) {
    Write-Host '  2. Logins (device code): pwsh scripts/bootstrap/connect-github.ps1 ; pwsh scripts/bootstrap/connect-azure.ps1'
}
Write-Host '  3. Env wiring: . scripts/bootstrap/auto-login.ps1   # dot-sourced; pulls the Key Vault keys into this session'
if (-not $SkipSmoke -and -not $VerifyOnly) {
    Write-Host '  4. Smoke: dotnet build HELIOS.sln -c Release ; dotnet run --project src/ai/HELIOS.AIHub.Cli -c Release --no-build -- status'
}
Write-Host '  5. Inventory: pwsh scripts/setup/setup-all.ps1 -Fix'
exit 2
