#Requires -Version 7
<#
.SYNOPSIS
GitHub authentication, PowerShell twin of scripts/bootstrap/connect-github.sh: the
browser device-code flow by default, -FromEnv to persist an already-present
WIRE-VALIDATED env token into gh's keyring, -VerifyOnly to report and mutate nothing.

.DESCRIPTION
Wire-first rule (scripts/verify/rest-connect.ps1 doctrine): `gh auth status` can lie
both ways - a REST-valid fine-grained token can fail it, and a credential-injecting
transport can make garbage look valid - so every decision here is grounded in a
direct probe of https://api.github.com/rate_limit:

  anonymous probe answers above the 60/hr unauthenticated cap
      -> an injecting transport owns this session's GitHub credentials: the lane is
         reported transport-ready and NOTHING is persisted (per-token validity is
         unprovable here, and persisting an unproven token is how a dead credential
         ends up in a keyring).
  token probe answers 200 with a limit above 60
      -> the token is REST-valid on a clean transport.

Modes:
  default       `gh auth login --hostname github.com --git-protocol https --web
                --scopes models:read` when not already authenticated (-Force re-runs
                it). models:read is required by the github-models provider this token
                feeds; without it the provider looks configured and every call 403s.
  -FromEnv      persist a REST-valid GH_TOKEN / GITHUB_TOKEN into gh's keyring via
                `gh auth login --with-token` fed through STDIN, env-cleared (gh
                refuses to log in while GH_TOKEN is set). Never opens a browser.
  -VerifyOnly   report the auth state and stop.

Custody: gh stores its token in its own keyring/config (~/.config/gh/hosts.yml),
outside the working tree - the same custody class as ~/.azure. Token values never
appear in argv, output, or logs; raw `gh auth status` output is never echoed (it can
name accounts and scopes). For the GITHUB_MODELS_TOKEN export, dot-source
scripts/bootstrap/auto-login.ps1 - the PowerShell owner of session exports.

.PARAMETER VerifyOnly
Report the auth state; never mutates. Exit 0 when authenticated (keyring, transport,
or a REST-valid env token), 1 when not.

.PARAMETER FromEnv
Persist a wire-validated GH_TOKEN / GITHUB_TOKEN to gh's keyring; never interactive.

.PARAMETER Force
Re-run the device-code login even when a login already exists.

.EXAMPLE
pwsh scripts/bootstrap/connect-github.ps1

.EXAMPLE
pwsh scripts/bootstrap/connect-github.ps1 -FromEnv

.EXAMPLE
pwsh scripts/bootstrap/connect-github.ps1 -VerifyOnly

.NOTES
Exit codes: 0 = authenticated / persisted / transport-ready; 1 = not authenticated,
no env token proved REST-valid, or the persist failed (the manual command is
printed); 2 = gh is not on PATH.
#>
[CmdletBinding()]
param(
    [switch]$VerifyOnly,

    [switch]$FromEnv,

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$gh = Get-Command gh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $gh) {
    Write-Host 'connect-github: gh (GitHub CLI) is not installed - run scripts/bootstrap/cloud-shell-setup.sh first, or see https://cli.github.com'
    exit 2
}

# --- Wire-truth probes ---------------------------------------------------------------
# Returns the numeric rate.limit (anonymous when no token is given) or $null on
# transport failure / unparsable body. A 401 body carries no rate.limit -> $null ->
# the token is treated as not proven. The bearer value lives only in the header
# dictionary of this one request.
function Get-GitHubRateLimit {
    param([AllowNull()][AllowEmptyString()][string]$Token = '')
    $headers = @{ Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }
    if ($Token) { $headers['Authorization'] = "Bearer $Token" }
    try {
        $response = Invoke-WebRequest -Uri 'https://api.github.com/rate_limit' -Headers $headers -TimeoutSec 20 -SkipHttpErrorCheck -UseBasicParsing
        $body = $response.Content | ConvertFrom-Json
        $rate = if ($body.PSObject.Properties['rate']) { $body.rate } else { $null }
        if ($rate -and $rate.PSObject.Properties['limit']) { return [int]$rate.limit }
    }
    catch { Write-Verbose "rate_limit probe failed: $($_.Exception.Message)" }
    return $null
}

# $true = an injecting transport is PROVEN (anonymous answer above the 60/hr cap).
function Test-TransportInjected {
    $anon = Get-GitHubRateLimit
    return ($null -ne $anon -and $anon -gt 60)
}

# $true = the token is REST-valid on a clean transport: at/below 60 means the
# Authorization header was stripped in transit (a legitimate anonymous payload that
# proves nothing about the token).
function Test-TokenValid {
    param([Parameter(Mandatory)][string]$Token)
    $limit = Get-GitHubRateLimit -Token $Token
    return ($null -ne $limit -and $limit -gt 60)
}

# gh with GH_TOKEN / GITHUB_TOKEN removed from the child's environment: with an env
# token set, plain `gh auth status` judges the env token, not the keyring, and
# `gh auth login` refuses outright. Optional stdin carries the --with-token value;
# stdout/stderr are captured and returned, never printed by callers.
function Invoke-GhEnvCleared {
    param([Parameter(Mandatory)][string[]]$Arguments, [AllowNull()][AllowEmptyString()][string]$StdIn = $null)
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $gh.Source
    foreach ($a in $Arguments) { $psi.ArgumentList.Add($a) }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    foreach ($name in 'GH_TOKEN', 'GITHUB_TOKEN') { $null = $psi.Environment.Remove($name) }
    $proc = [System.Diagnostics.Process]::Start($psi)
    try {
        $stderrTask = $proc.StandardError.ReadToEndAsync()
        if ($null -ne $StdIn) { $proc.StandardInput.Write($StdIn) }
        $proc.StandardInput.Close()
        $stdout = $proc.StandardOutput.ReadToEnd()
        $proc.WaitForExit()
        return [pscustomobject]@{ ExitCode = $proc.ExitCode; Output = ($stdout + "`n" + $stderrTask.Result) }
    }
    finally { $proc.Dispose() }
}

# `gh auth status` exit code only (raw output never echoed). --active restricts the
# check to the account subsequent gh commands actually use; older CLIs fall back.
function Get-GhAuthStatus {
    $raw = @(& $gh.Source auth status --hostname github.com --active 2>&1 | ForEach-Object { "$_" })
    $exit = $LASTEXITCODE
    if ($exit -ne 0 -and (($raw -join "`n") -match 'unknown flag')) {
        $raw = @(& $gh.Source auth status --hostname github.com 2>&1 | ForEach-Object { "$_" })
        $exit = $LASTEXITCODE
    }
    return [pscustomobject]@{ ExitCode = $exit; Output = ($raw -join "`n") }
}

function Get-GhLogin {
    $raw = @(& $gh.Source api user --jq .login 2>$null)
    if ($LASTEXITCODE -eq 0 -and $raw.Count -gt 0 -and "$($raw[0])".Trim()) { return "$($raw[0])".Trim() }
    return '?'
}

# --- Verify-only ---------------------------------------------------------------------
if ($VerifyOnly) {
    if ((Get-GhAuthStatus).ExitCode -eq 0) {
        Write-Host "GitHub: authenticated as $(Get-GhLogin)."
        exit 0
    }
    if (Test-TransportInjected) {
        Write-Host 'GitHub: wire-ready via an injecting transport (gh keyring disagrees - the REST probe is'
        Write-Host '        ground truth; per-token validity is unprovable on this host).'
        exit 0
    }
    foreach ($name in 'GH_TOKEN', 'GITHUB_TOKEN') {
        $candidate = [Environment]::GetEnvironmentVariable($name)
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-TokenValid -Token $candidate)) {
            Write-Host "GitHub: wire-ready - $name is REST-valid (gh auth status disagrees; the REST probe is ground truth)."
            exit 0
        }
    }
    Write-Host 'GitHub: not authenticated. Run pwsh scripts/bootstrap/connect-github.ps1 to log in.'
    exit 1
}

# --- From-env: the zero-human lane -----------------------------------------------------
if ($FromEnv) {
    if (Test-TransportInjected) {
        Write-Host 'GitHub: transport-injected - an anonymous probe of api.github.com answered above the'
        Write-Host '        60/hr anonymous cap, so a proxy owns this session''s GitHub credentials.'
        Write-Host '        Per-token validity is unprovable here; nothing was validated or persisted.'
        exit 0
    }
    if ((Invoke-GhEnvCleared -Arguments @('auth', 'status', '--hostname', 'github.com')).ExitCode -eq 0) {
        Write-Host 'GitHub: a keyring login already exists (checked env-cleared) - nothing to do.'
        exit 0
    }
    foreach ($name in 'GH_TOKEN', 'GITHUB_TOKEN') {
        $candidate = [Environment]::GetEnvironmentVariable($name)
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if (-not (Test-TokenValid -Token $candidate)) {
            Write-Host "GitHub: $name is present but did not prove REST-valid (rejected or transient) - not persisted."
            continue
        }
        Write-Host "GitHub: $name is REST-valid on the wire - persisting to gh's keyring (--with-token via stdin, env-cleared)."
        $login = Invoke-GhEnvCleared -Arguments @('auth', 'login', '--hostname', 'github.com', '--git-protocol', 'https', '--with-token') -StdIn $candidate
        $candidate = $null
        if ($login.ExitCode -eq 0 -and (Invoke-GhEnvCleared -Arguments @('auth', 'status', '--hostname', 'github.com')).ExitCode -eq 0) {
            Write-Host "GitHub: keyring login persisted from $name (value never printed)."
            exit 0
        }
        Write-Host "GitHub: persisting $name failed (gh exited $($login.ExitCode)). Manual step (bash):"
        Write-Host "  printenv $name | env -u GH_TOKEN -u GITHUB_TOKEN gh auth login --hostname github.com --with-token"
        exit 1
    }
    Write-Host 'GitHub: no env token could be validated - owner step: gh auth login --hostname github.com --web --scopes models:read'
    exit 1
}

# --- Default: device-code login --------------------------------------------------------
if (-not $Force -and (Get-GhAuthStatus).ExitCode -eq 0) {
    Write-Host "GitHub: already authenticated as $(Get-GhLogin)."
}
else {
    Write-Host 'GitHub: starting browser/device-code login (a one-time code will be shown)...'
    Write-Host '  gh auth login --hostname github.com --git-protocol https --web --scopes models:read'
    # Console inherited on purpose: the one-time code must reach the human unbuffered.
    & $gh.Source auth login --hostname github.com --git-protocol https --web --scopes 'models:read'
    if ($LASTEXITCODE -ne 0) {
        Write-Host "GitHub: login did not complete (gh exited $LASTEXITCODE)."
        exit 1
    }
}

$status = Get-GhAuthStatus
if ($status.ExitCode -ne 0) {
    Write-Host 'GitHub: gh still reports no usable login - re-run with -Force, or -VerifyOnly for the wire view.'
    exit 1
}
if ($status.Output -notmatch 'models:read') {
    Write-Host 'GitHub: note - the current token lacks the models:read scope; the github-models'
    Write-Host '        provider will fail. Fix with: gh auth refresh --hostname github.com --scopes models:read'
}
Write-Host 'Tip: . scripts/bootstrap/auto-login.ps1 (dot-sourced) exports GITHUB_MODELS_TOKEN for the AIHub.'
exit 0
