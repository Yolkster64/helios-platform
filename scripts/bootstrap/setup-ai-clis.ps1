<#
.SYNOPSIS
Installs/verifies the AI agent CLIs that config/aihub.json's cliAgents section drives:
claude, codex, copilot, plus the gh CLI the gh-models agent shells out to.

.DESCRIPTION
One CLI per cliAgents entry, matched to the exact binary shape the hub invokes:

  claude  — npm: @anthropic-ai/claude-code  -> `claude -p {prompt}`
  codex   — npm: @openai/codex              -> `codex exec {prompt}`
  copilot — npm: @github/copilot            -> `copilot -p {prompt}`
  gh      — verified only, never installed  -> `gh models run {model} {prompt}`

Copilot packaging decision: config/aihub.json invokes a standalone `copilot` binary
with `-p {prompt}`. Only the npm package @github/copilot (the GitHub Copilot CLI)
provides that shape. The gh-extension route (`gh extension install github/gh-copilot`)
would instead add a `gh copilot suggest|explain` subcommand — different binary (gh),
different argument grammar, no -p prompt mode — so it cannot back the cliAgents entry.
@github/copilot is also what cloud-shell-setup.sh already installs; this script stays
consistent with it.

Idempotent: CLIs already on PATH are detected (Get-Command) and skipped, with their
version printed. Installs run sequentially on purpose — concurrent `npm install -g`
invocations race on the shared global prefix. Never prompts and never stores secrets:
headless auth guidance is printed per CLI instead (repo rule: keys live in environment
variables or Key Vault only).

Exit codes: 0 every non-skipped CLI is present (already, or after install);
2 something is missing (including npm absent when installs are needed).
-ProbeAuth results are informational only and NEVER change the exit code.

.PARAMETER VerifyOnly
Report presence/versions only; never install anything (the repo's verify-only
convention — see connect-github.sh/connect-azure.* --verify-only).

.PARAMETER Skip
CLI names to leave out entirely: claude, codex, copilot, gh. Skipped CLIs never
count toward the exit code.

.PARAMETER ProbeAuth
Opt-in, read-only authentication probe for each CLI that is present: codex
(`codex login status`), gh (`gh auth status --hostname github.com --active`,
falling back automatically when an older gh lacks --active), claude/copilot
(whether ANTHROPIC_API_KEY / GH_TOKEN / GITHUB_TOKEN are SET — variable names
only, values are never read or printed), and — when it is already on PATH —
ant (stdout of `ant auth status` is grepped; per the CLI authentication docs
its exit status must not be scripted against, so it never is). Results are
informational (authenticated | not-authenticated | unknown), shown as an extra
summary-table column, and NEVER counted in the exit code; an unknown
subcommand on an older CLI degrades to `unknown` instead of failing setup.
The script's contract is preserved: no login flow is ever run, nothing is
prompted for, nothing is stored.

.EXAMPLE
pwsh scripts/bootstrap/setup-ai-clis.ps1

.EXAMPLE
pwsh scripts/bootstrap/setup-ai-clis.ps1 -VerifyOnly

.EXAMPLE
pwsh scripts/bootstrap/setup-ai-clis.ps1 -VerifyOnly -ProbeAuth

.EXAMPLE
pwsh scripts/bootstrap/setup-ai-clis.ps1 -Skip codex,copilot
#>
#Requires -Version 7
[CmdletBinding()]
param(
    [switch]$VerifyOnly,

    [switch]$ProbeAuth,

    [ValidateSet('claude', 'codex', 'copilot', 'gh', 'hermes')]
    [string[]]$Skip = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Cloud Shell surfaces as AZUREPS_HOST_ENVIRONMENT/ACC_CLOUD (bash bootstrap checks
# these) or CLOUD_SHELL (what start-fleet.ps1 keys workspace mode off).
$inCloudShell = [bool]($env:AZUREPS_HOST_ENVIRONMENT -or $env:ACC_CLOUD -or $env:CLOUD_SHELL)
$environment = if ($inCloudShell) { 'Azure Cloud Shell' }
elseif ($env:CODESPACES) { 'GitHub Codespaces' }
else { 'local shell' }
$mode = if ($VerifyOnly) { 'verify-only' } else { 'install' }
Write-Host "== HELIOS AI CLI setup ($environment, $mode) =="

# One entry per config/aihub.json cliAgent this script is responsible for. gh has no
# NpmPackage: it is a base tool owned by the OS/package manager (pre-installed in
# Cloud Shell), so this script verifies it but never installs it.
$cliSpecs = @(
    [pscustomobject]@{
        Name        = 'claude'
        Command     = 'claude'
        NpmPackage  = '@anthropic-ai/claude-code'
        Optional    = $false
        AgentShape  = 'claude -p {prompt}'
        InstallHint = 'npm install -g @anthropic-ai/claude-code (or rerun without -VerifyOnly)'
        Auth        = 'set ANTHROPIC_API_KEY (Key Vault: anthropic-api-key), or mint a long-lived token once with: claude setup-token'
        AuthProbe   = {
            param($Command)
            # Presence only — Test-Path never surfaces the value, and a stored
            # `claude` login is not probeable headlessly, so absence is 'unknown'.
            if (Test-Path env:ANTHROPIC_API_KEY) {
                [pscustomobject]@{ Status = 'authenticated'; Detail = 'ANTHROPIC_API_KEY is set (name reported only, value never read)' }
            }
            else {
                [pscustomobject]@{ Status = 'unknown'; Detail = 'ANTHROPIC_API_KEY not set; a stored claude login cannot be probed headlessly' }
            }
        }
    }
    [pscustomobject]@{
        Name        = 'codex'
        Command     = 'codex'
        NpmPackage  = '@openai/codex'
        Optional    = $false
        AgentShape  = 'codex exec {prompt}'
        InstallHint = 'npm install -g @openai/codex (or rerun without -VerifyOnly)'
        Auth        = 'headless: set OPENAI_API_KEY (Key Vault: openai-api-key); `codex login` works where a browser exists'
        AuthProbe   = {
            param($Command)
            # Capture all output, THEN read $LASTEXITCODE (the pipeline-slice trap
            # documented in Get-CliVersion applies here too).
            $raw = @(& $Command.Source login status 2>&1 | ForEach-Object { "$_" })
            $code = $LASTEXITCODE
            $text = $raw -join '; '
            if ($text -match '(?i)unrecognized subcommand|unexpected argument|unknown (sub)?command') {
                # Older codex without `login status` — informational, never a failure.
                [pscustomobject]@{ Status = 'unknown'; Detail = 'this codex version has no `login status` subcommand' }
            }
            elseif ($code -eq 0) {
                $first = if ($raw.Count -gt 0 -and $raw[0]) { ([string]$raw[0]).Trim() } else { 'codex login status: OK' }
                [pscustomobject]@{ Status = 'authenticated'; Detail = $first }
            }
            else {
                [pscustomobject]@{ Status = 'not-authenticated'; Detail = "codex login status exited $code" }
            }
        }
    }
    [pscustomobject]@{
        Name        = 'copilot'
        Command     = 'copilot'
        NpmPackage  = '@github/copilot'
        Optional    = $false
        AgentShape  = 'copilot -p {prompt}'
        InstallHint = 'npm install -g @github/copilot (or rerun without -VerifyOnly)'
        Auth        = 'reuses GitHub login: gh auth login --web device-code flow (scripts/bootstrap/connect-github.sh); GH_TOKEN is honored headlessly'
        AuthProbe   = {
            param($Command)
            # copilot rides the GitHub login: report which token env var is SET —
            # names only, values never read (Test-Path) and never printed.
            $set = @(@('GH_TOKEN', 'GITHUB_TOKEN') | Where-Object { Test-Path "env:$_" })
            if ($set.Count -gt 0) {
                [pscustomobject]@{ Status = 'authenticated'; Detail = "$($set[0]) is set (name reported only, value never read)" }
            }
            else {
                [pscustomobject]@{ Status = 'unknown'; Detail = 'neither GH_TOKEN nor GITHUB_TOKEN is set; copilot may reuse a stored gh login' }
            }
        }
    }
    [pscustomobject]@{
        Name        = 'gh'
        Command     = 'gh'
        NpmPackage  = $null
        Optional    = $false
        AgentShape  = 'gh models run {model} {prompt}'
        InstallHint = 'gh itself: https://cli.github.com (base tool, not installed here); models subcommand: gh extension install github/gh-models'
        Auth        = 'gh auth login --web device-code flow; gh-models needs the models:read scope — connect-github.sh sets both'
        AuthProbe   = {
            param($Command)
            $raw = @(& $Command.Source auth status --hostname github.com --active 2>&1 | ForEach-Object { "$_" })
            $code = $LASTEXITCODE
            if (($raw -join '; ') -match '(?i)unknown flag') {
                # Older gh without --active: retry one flag narrower rather than fail.
                $raw = @(& $Command.Source auth status --hostname github.com 2>&1 | ForEach-Object { "$_" })
                $code = $LASTEXITCODE
            }
            if ($code -eq 0) {
                $logged = @($raw | Where-Object { $_ -match 'Logged in to' })
                $detail = if ($logged.Count -gt 0) { ([string]$logged[0]).Trim() } else { 'gh auth status: authenticated' }
                [pscustomobject]@{ Status = 'authenticated'; Detail = $detail }
            }
            else {
                [pscustomobject]@{ Status = 'not-authenticated'; Detail = 'gh auth status reports no active github.com login' }
            }
        }
    }
    # The fifth cliAgent in config/aihub.json. Optional: there is no public
    # installer, and start-fleet.ps1 deliberately falls back to the non-model
    # local stub without it — but a "complete" inventory must still SAY so
    # rather than report 4/4 and let setup-all claim full readiness.
    [pscustomobject]@{
        Name        = 'hermes'
        Command     = 'hermes'
        NpmPackage  = $null
        Optional    = $true
        AgentShape  = 'hermes -p {assignee} chat -q {prompt}'
        InstallHint = 'no public installer — see docs/architecture/HERMES_FLEET_AND_XCORE.md; without it the fleet runs the local stub (no model work)'
        Auth        = 'authenticates via its own login/config; the fleet env contract (HERMES_KANBAN_*) needs no key'
        AuthProbe   = $null # no public CLI surface to probe — -ProbeAuth reports 'unknown'
    }
)

function Get-CliCommand {
    param([Parameter(Mandatory)][string]$Name)
    # Application only: AIHub launches these agents as OS subprocesses, which can
    # never resolve a PowerShell alias or function shadowing the name — counting
    # one as "present" would pass setup and fail at first invocation.
    Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
}

function Get-CliVersion {
    param([Parameter(Mandatory)][System.Management.Automation.CommandInfo]$Command)

    # First line only (gh prints a multi-line banner). Capture all output, THEN slice —
    # piping into Select-Object -First 1 stops the pipeline before $LASTEXITCODE is
    # set, which is an error under StrictMode (same pattern as verify-readiness.ps1).
    $version = 'unknown'
    try {
        $raw = @(& $Command.Source '--version' 2>$null)
        if ($LASTEXITCODE -eq 0 -and $raw.Count -gt 0 -and $raw[0]) {
            $version = ([string]$raw[0]).Trim()
        }
    }
    catch {
        Write-Verbose "Version probe failed for $($Command.Name): $_"
    }
    $version
}

$npmCommand = Get-CliCommand -Name 'npm'

Write-Host ''
Write-Host '-- CLI fleet --'
$results = @(foreach ($spec in $cliSpecs) {
    if ($Skip -contains $spec.Name) {
        Write-Host "  $($spec.Name): skipped (-Skip)"
        [pscustomobject]@{ Cli = $spec.Name; Status = 'skipped'; Version = ''; Path = ''; AgentShape = $spec.AgentShape; Optional = $spec.Optional; Auth = ''; AuthDetail = '' }
        continue
    }

    $command = Get-CliCommand -Name $spec.Command
    $status = 'present'

    if (-not $command -and -not $VerifyOnly -and $spec.NpmPackage -and $npmCommand) {
        Write-Host "  $($spec.Name): installing $($spec.NpmPackage) ..."
        # Sequential on purpose — see .DESCRIPTION. Output captured so a failure can
        # be summarized without drowning the report.
        $npmOutput = @(& $npmCommand.Source install -g $spec.NpmPackage 2>&1 | ForEach-Object { "$_" })
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "npm install -g $($spec.NpmPackage) failed (exit $LASTEXITCODE); last output lines:"
            $npmOutput | Select-Object -Last 5 | ForEach-Object { Write-Warning "    $_" }
        }
        $command = Get-CliCommand -Name $spec.Command
        if ($command) { $status = 'installed' }
    }

    # gh alone cannot run the gh-models agent shape: the `models` subcommand
    # comes from the github/gh-models extension. `gh extension list` reads local
    # state only (no network); in install mode the extension is added — that is
    # tool setup, not an auth mutation.
    if ($command -and $spec.Name -eq 'gh') {
        $extensions = @(& $command.Source extension list 2>$null | ForEach-Object { "$_" })
        if (-not ($extensions -match 'gh-models')) {
            if (-not $VerifyOnly) {
                Write-Host '  gh: installing the github/gh-models extension ...'
                & $command.Source extension install github/gh-models 2>&1 | Out-Null
                $extensions = @(& $command.Source extension list 2>$null | ForEach-Object { "$_" })
                if ($extensions -match 'gh-models') { $status = 'installed' }
            }
            if (-not ($extensions -match 'gh-models')) {
                # Report as missing: the configured agent shape fails without it.
                $command = $null
            }
        }
    }

    if ($command) {
        $version = Get-CliVersion -Command $command
        # Opt-in, per-spec, read-only auth probe. Informational ONLY: whatever it
        # returns (or however it breaks), the exit code never changes and setup
        # never fails — an unknown subcommand on an older CLI degrades to 'unknown'.
        $auth = ''
        $authDetail = ''
        if ($ProbeAuth) {
            $auth = 'unknown'
            $authDetail = "no headless auth probe for $($spec.Name)"
            if ($spec.AuthProbe) {
                try {
                    $probe = & $spec.AuthProbe $command
                    $auth = [string]$probe.Status
                    $authDetail = [string]$probe.Detail
                }
                catch {
                    $authDetail = "probe failed: $($_.Exception.Message)"
                }
            }
        }
        Write-Host "  $($spec.Name): $status ($version)"
        [pscustomobject]@{ Cli = $spec.Name; Status = $status; Version = $version; Path = $command.Source; AgentShape = $spec.AgentShape; Optional = $spec.Optional; Auth = $auth; AuthDetail = $authDetail }
    }
    else {
        $optionalTag = if ($spec.Optional) { 'missing (optional)' } else { 'MISSING' }
        Write-Host "  $($spec.Name): $optionalTag — $($spec.InstallHint)"
        [pscustomobject]@{ Cli = $spec.Name; Status = 'missing'; Version = ''; Path = ''; AgentShape = $spec.AgentShape; Optional = $spec.Optional; Auth = ''; AuthDetail = '' }
    }
})

# ant (the Anthropic CLI) is not a cliAgents entry, so it is never installed or
# required here; under -ProbeAuth it is probed opportunistically when already on
# PATH. Optional = $true keeps it out of the exit-code arithmetic entirely, and
# the detail strings are fixed classifications — raw output is never echoed.
if ($ProbeAuth) {
    $antCommand = Get-CliCommand -Name 'ant'
    if ($antCommand) {
        $antAuth = 'unknown'
        $antDetail = 'ant auth status output not recognized'
        try {
            # Per the CLI authentication docs, `ant auth status` PRINTS the selected
            # credential source but its exit status must not be scripted against —
            # so this greps stdout and deliberately never reads $LASTEXITCODE.
            $antOut = @(& $antCommand.Source auth status 2>$null | ForEach-Object { "$_" })
            $antText = $antOut -join '; '
            if ($antText -match '(?i)not logged in|not authenticated|no credentials|logged out') {
                $antAuth = 'not-authenticated'
                $antDetail = 'ant auth status reports no credentials (a human can run: ant auth login --no-browser)'
            }
            elseif ($antText -match '(?i)ANTHROPIC_API_KEY') {
                $antAuth = 'authenticated'
                $antDetail = 'credential source: ANTHROPIC_API_KEY (overrides every profile, per the CLI authentication docs)'
            }
            elseif ($antText -match '(?i)profile|workspace|logged in|credential') {
                $antAuth = 'authenticated'
                $antDetail = 'credential source: stored profile (under ANTHROPIC_CONFIG_DIR)'
            }
        }
        catch {
            $antDetail = "probe failed: $($_.Exception.Message)"
        }
        $antVersion = Get-CliVersion -Command $antCommand
        Write-Host "  ant: present ($antVersion) — not a cliAgent; auth probe only"
        $results += [pscustomobject]@{ Cli = 'ant'; Status = 'present'; Version = $antVersion; Path = $antCommand.Source; AgentShape = '(not a cliAgent; -ProbeAuth only)'; Optional = $true; Auth = $antAuth; AuthDetail = $antDetail }
    }
}

$missing = @($results | Where-Object { $_.Status -eq 'missing' })
$missingCliNames = @($missing | ForEach-Object Cli)
$npmInstallableMissing = @($cliSpecs | Where-Object { $_.NpmPackage -and $missingCliNames -contains $_.Name })
if (-not $npmCommand -and $npmInstallableMissing.Count -gt 0) {
    [Console]::Error.WriteLine(("error: npm is not installed — cannot install: {0}. " +
            'Install Node.js (https://nodejs.org or nvm) or run scripts/bootstrap/cloud-shell-setup.sh; Cloud Shell ships npm.') -f
        (($npmInstallableMissing | ForEach-Object Name) -join ', '))
}

Write-Host ''
$tableColumns = @(
    'Cli'
    'Status'
    'Version'
    @{ n = 'AIHub cliAgent shape'; e = { $_.AgentShape } }
)
if ($ProbeAuth) { $tableColumns += 'Auth' } # informational only — never in the exit code
$tableColumns += 'Path'
$table = $results |
    Format-Table -Property $tableColumns -AutoSize |
    Out-String -Width 4096
Write-Host $table.TrimEnd()

if ($ProbeAuth) {
    Write-Host ''
    Write-Host '-- Auth probe (informational only; never changes the exit code) --'
    foreach ($row in $results) {
        if ($row.Status -eq 'skipped' -or $row.Status -eq 'missing') { continue }
        Write-Host ('  {0,-8} {1,-18} {2}' -f $row.Cli, $row.Auth, $row.AuthDetail)
    }
}

# Guidance only: this script never runs a login flow, never prompts, never writes a
# key anywhere. Keys belong in environment variables or Key Vault (CLAUDE.md rule).
Write-Host ''
Write-Host '-- Headless auth (guidance only; nothing is executed or stored) --'
foreach ($spec in $cliSpecs) {
    if ($Skip -contains $spec.Name) { continue }
    Write-Host ('  {0,-8} {1}' -f $spec.Name, $spec.Auth)
}
if ($inCloudShell) {
    Write-Host ('  {0,-8} {1}' -f 'az', 'Cloud Shell detected — az is already pre-authenticated (implicit login); nothing to do')
}
else {
    Write-Host ('  {0,-8} {1}' -f 'az', 'az login --use-device-code (or scripts/bootstrap/connect-azure.sh)')
}

Write-Host ''
# Only required CLIs gate the exit code; optional ones (hermes) are reported
# honestly but never fail the run — the fleet's stub fallback is by design.
$checked = @($results | Where-Object { $_.Status -ne 'skipped' })
$requiredChecked = @($checked | Where-Object { -not $_.Optional })
$requiredPresent = @($requiredChecked | Where-Object { $_.Status -ne 'missing' }).Count
$requiredMissing = @($requiredChecked | Where-Object { $_.Status -eq 'missing' })
$optionalMissing = @($checked | Where-Object { $_.Optional -and $_.Status -eq 'missing' })
$summary = "AI CLIs: $requiredPresent/$($requiredChecked.Count) required present"
if ($requiredMissing.Count -gt 0) {
    $summary += ' — missing: ' + (@($requiredMissing | ForEach-Object Cli) -join ', ')
}
if ($optionalMissing.Count -gt 0) {
    $summary += '; optional missing: ' + (@($optionalMissing | ForEach-Object Cli) -join ', ') +
        ' (fleet falls back to the local stub)'
}
if ($Skip.Count -gt 0) { $summary += " (skipped: $($Skip -join ', '))" }
Write-Host $summary

if ($requiredMissing.Count -gt 0) { exit 2 }
exit 0
