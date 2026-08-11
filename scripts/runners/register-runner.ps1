<#
.SYNOPSIS
Register a self-hosted GitHub Actions runner for Yolkster64/helios-platform —
PowerShell 7 twin of register-runner.sh (this one also covers Windows).

.DESCRIPTION
What this does, in order:

  1. requires an authenticated gh CLI — the caller must have ADMIN on the repo,
     because the registration-token endpoint is admin-only;
  2. downloads the latest actions/runner release for this OS/arch into the
     target directory (default ./actions-runner), skipping the download when a
     runner is already unpacked there;
  3. mints a SHORT-LIVED registration token via
       gh api -X POST repos/{owner}/{repo}/actions/runners/registration-token
     The token is SINGLE-USE and expires in ~1 hour. It is held in a local
     variable only — never echoed, never written to disk;
  4. runs ./config.sh (config.cmd on Windows) with
     --url --token --name --labels helios,xcore[,extras] --unattended
     (plus --ephemeral behind the -Ephemeral switch);
  5. prints the run command (./run.sh / .\run.cmd) and the service-install hint —
     it deliberately does NOT auto-start the runner.

Labels: every runner gets helios,xcore. Pools that need more add them with
-ExtraLabels — e.g. the fleet's xcore-9-native pool
(config/fleet/fleet-topology.json) wants a dedicated runner carrying
xcore-native (Windows SDK + MSVC + GPU box) before its autoscaling mode may
leave "local":

    pwsh scripts/runners/register-runner.ps1 -ExtraLabels xcore-native

Removing a runner later (remove tokens are also single-use, ~1h):

    $t = gh api -X POST repos/Yolkster64/helios-platform/actions/runners/remove-token --jq .token
    ./config.sh remove --token $t     # .\config.cmd remove on Windows

-DryRun prints every step of the plan and exits WITHOUT touching the network
or gh. Proof of life after registering: dispatch the "Self-Hosted Runner Smoke"
workflow (.github/workflows/runner-smoke.yml). Scale-out beyond hand-registered
runners is ARC — see docs/architecture/GITHUB_ECOSYSTEM_DESIGN.md
"Self-hosted runners (ARC)".

.PARAMETER Repo
GitHub repository as owner/repo. Default: Yolkster64/helios-platform.

.PARAMETER TargetDir
Directory to download/unpack the runner into. Default: ./actions-runner — inside
the checkout but covered by .gitignore (actions-runner/), because config.cmd/.sh
writes LIVE credentials (.credentials, RSA params) into it. A custom TargetDir
inside the repo must be gitignored too, or git add -A can stage runner
credentials.

.PARAMETER RunnerName
Runner name shown in Settings -> Actions -> Runners. Default: <hostname>-helios.

.PARAMETER ExtraLabels
Comma-separated labels appended to the base helios,xcore set
(e.g. xcore-native for the xcore-9-native pool).

.PARAMETER Ephemeral
Configure with --ephemeral: the runner takes exactly one job, then deregisters —
the right mode for throwaway VMs; persistent boxes (the Xcore pools) omit it.

.PARAMETER RunAsService
Windows only: configure with --runasservice so config.cmd installs the runner
as a Windows service during INITIAL registration. This cannot be added later —
config.cmd refuses to reconfigure an already-configured runner (GitHub's
documented path is remove + reconfigure). On Linux/macOS use the printed
svc.sh sequence instead (valid after configuration).

.PARAMETER DryRun
Print the full plan and exit; no network calls, no gh calls, nothing executed.

.EXAMPLE
pwsh scripts/runners/register-runner.ps1 -DryRun

.EXAMPLE
pwsh scripts/runners/register-runner.ps1 -TargetDir C:\actions-runner -ExtraLabels xcore-native -Ephemeral
#>
[CmdletBinding()]
param(
    [string]$Repo = 'Yolkster64/helios-platform',
    [string]$TargetDir = './actions-runner',
    [string]$RunnerName = "$([Environment]::MachineName.ToLowerInvariant())-helios",
    [string]$ExtraLabels = '',
    [switch]$Ephemeral,
    [switch]$RunAsService,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$baseLabels = 'helios,xcore'
$labels = if ($ExtraLabels) { "$baseLabels,$ExtraLabels" } else { $baseLabels }

# --- OS/arch -> actions/runner asset naming ---------------------------------------
if ($IsWindows) { $os = 'win'; $ext = 'zip'; $configCmd = '.\config.cmd'; $runCmd = '.\run.cmd' }
elseif ($IsLinux) { $os = 'linux'; $ext = 'tar.gz'; $configCmd = './config.sh'; $runCmd = './run.sh' }
elseif ($IsMacOS) { $os = 'osx'; $ext = 'tar.gz'; $configCmd = './config.sh'; $runCmd = './run.sh' }
else { throw 'unsupported OS for the actions/runner package.' }

$arch = switch ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture) {
    'X64' { 'x64' }
    'Arm64' { 'arm64' }
    default { throw "unsupported architecture '$_' (need x64 or arm64)." }
}

$configFlags = @('--unattended')
if ($Ephemeral) { $configFlags += '--ephemeral' }
# Windows service mode must be chosen AT configuration time: config.cmd
# refuses to reconfigure an already-configured runner, so it cannot be
# bolted on afterwards (GitHub's docs say remove + reconfigure).
if ($RunAsService) {
    if ($IsWindows) { $configFlags += '--runasservice' }
    else { Write-Warning '-RunAsService is Windows-only (config.cmd); on Linux/macOS use svc.sh after registration - ignored.' }
}

# The hint is printed after Pop-Location, so it must carry the runner
# directory itself — a bare .\config.cmd would resolve against the caller's
# original working directory and fail.
$serviceHint = if ($IsWindows) {
    if ($RunAsService) {
        'already installed as a Windows service by --runasservice (config.cmd sets it up to start automatically)'
    }
    else {
        # config.cmd cannot add service mode to an existing registration —
        # the only path is remove + re-register with -RunAsService.
        "config.cmd refuses reconfiguration - to convert: `$t = gh api -X POST repos/$Repo/actions/runners/remove-token --jq .token; cd $TargetDir; .\config.cmd remove --token `$t; then re-run register-runner.ps1 -RunAsService"
    }
}
else {
    "cd $TargetDir && sudo ./svc.sh install && sudo ./svc.sh start"
}

# --- Dry run: print the full plan, touch nothing ----------------------------------
if ($DryRun) {
    Write-Host 'DRY RUN — plan only; no network calls, no gh calls, nothing executed.'
    Write-Host ''
    Write-Host "  1. Check: gh auth status   (caller must have admin on $Repo)"
    Write-Host '  2. Resolve latest release: gh api repos/actions/runner/releases/latest --jq .tag_name'
    Write-Host "  3. Download + extract into ${TargetDir}:"
    Write-Host "       https://github.com/actions/runner/releases/download/v<latest>/actions-runner-$os-$arch-<latest>.$ext"
    Write-Host "     (skipped if a runner is already unpacked in $TargetDir)"
    Write-Host '  4. Mint single-use registration token (expires ~1h; kept in memory only):'
    Write-Host "       gh api -X POST repos/$Repo/actions/runners/registration-token --jq .token"
    Write-Host '  5. Configure:'
    Write-Host "       $configCmd --url https://github.com/$Repo --token *** --name $RunnerName --labels $labels $($configFlags -join ' ')"
    Write-Host '  6. Print next steps (never auto-starts):'
    Write-Host "       run now:            cd $TargetDir; $runCmd"
    Write-Host "       run as a service:   $serviceHint"
    Write-Host "       proof of life:      gh workflow run runner-smoke.yml --repo $Repo"
    return
}

# --- Preflight: gh present and authenticated --------------------------------------
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw 'gh CLI not found — install it and run gh auth login.'
}
# gh auth status tests EVERY stored account and exits 1 when any is stale;
# --active scopes the check to the account the gh api calls below will use.
# Fall back to the unscoped form only on a gh too old to know the flag.
$authOut = & gh auth status --hostname github.com --active 2>&1
if ($LASTEXITCODE -ne 0) {
    if ("$authOut" -match 'unknown flag') {
        & gh auth status --hostname github.com *> $null
    }
    if ($LASTEXITCODE -ne 0) {
        throw "gh is not authenticated. Run gh auth login as a user with ADMIN on $Repo (the registration-token endpoint requires repo admin)."
    }
}

# --- Download the latest runner release (idempotent) ------------------------------
$configPath = Join-Path $TargetDir ($(if ($IsWindows) { 'config.cmd' } else { 'config.sh' }))
if (Test-Path $configPath) {
    Write-Host "Runner package already present in $TargetDir — skipping download."
}
else {
    $tag = & gh api repos/actions/runner/releases/latest --jq .tag_name
    if ($LASTEXITCODE -ne 0 -or -not $tag) { throw 'could not resolve the latest actions/runner release via gh api.' }
    $version = $tag.TrimStart('v')
    $asset = "actions-runner-$os-$arch-$version.$ext"
    $url = "https://github.com/actions/runner/releases/download/$tag/$asset"
    Write-Host "Downloading actions/runner $tag ($os/$arch) into $TargetDir..."
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    $archive = Join-Path $TargetDir $asset
    Invoke-WebRequest -Uri $url -OutFile $archive
    if ($ext -eq 'zip') {
        Expand-Archive -Path $archive -DestinationPath $TargetDir -Force
    }
    else {
        & tar -xzf $archive -C $TargetDir
        if ($LASTEXITCODE -ne 0) { throw "extracting $asset failed with exit code $LASTEXITCODE" }
    }
    Remove-Item $archive -Force
}

# --- Mint the registration token (single-use, ~1h; memory only) -------------------
Write-Host "Minting a short-lived registration token for $Repo..."
$token = & gh api -X POST "repos/$Repo/actions/runners/registration-token" --jq .token
if ($LASTEXITCODE -ne 0 -or -not $token) {
    throw "could not mint a registration token — do you have admin on $Repo?"
}

# --- Configure (does not start) ---------------------------------------------------
Write-Host "Configuring runner '$RunnerName' with labels: $labels"
Push-Location $TargetDir
try {
    $configExe = if ($IsWindows) { '.\config.cmd' } else { './config.sh' }
    & $configExe --url "https://github.com/$Repo" --token $token `
        --name $RunnerName --labels $labels @configFlags
    if ($LASTEXITCODE -ne 0) { throw "runner configuration failed with exit code $LASTEXITCODE" }
}
finally {
    Pop-Location
    $token = $null
}

Write-Host ''
if ($IsWindows -and $RunAsService) {
    Write-Host 'Registered. --runasservice installed the Windows service during configuration; it starts with Windows.'
    Write-Host "  service status:             Get-Service 'actions.runner.*'"
}
else {
    Write-Host 'Registered. This script never auto-starts the runner — pick one:'
    Write-Host "  run in the foreground:      cd $TargetDir; $runCmd"
    Write-Host "  run as a service:           $serviceHint"
}
Write-Host ''
Write-Host 'Proof of life (dispatch-only smoke workflow):'
Write-Host "  gh workflow run runner-smoke.yml --repo $Repo"
Write-Host ''
Write-Host 'To remove this runner later (remove tokens are also single-use, ~1h):'
Write-Host "  `$t = gh api -X POST repos/$Repo/actions/runners/remove-token --jq .token"
Write-Host "  $configCmd remove --token `$t   # from inside $TargetDir"
