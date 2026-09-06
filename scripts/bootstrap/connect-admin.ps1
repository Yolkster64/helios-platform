#Requires -Version 7
<#
.SYNOPSIS
The one-command admin bring-up: automates everything around the two irreducible human
clicks - generating the fine-grained HELIOS_ADMIN_TOKEN PAT, and completing the Azure
MFA device-code sign-in - and leaves every later session non-interactive.

.DESCRIPTION
Two lanes, verify-first, each reported as a row (lane / state / next command) and as
one object under -Json. Nothing here reads, prints, or persists a secret VALUE: env
vars by NAME, the token over a masked prompt or stdin, GH_TOKEN scoped to single child
processes and cleared afterwards.

  GitHub admin lane (-SkipGitHub skips it)
    1. Prints the PAT creation URL with the exact permission set the control fabric
       needs (.github/workflows/governance-apply.yml header;
       docs/architecture/CONNECTIONS_SETUP.md "The one owner step"): fine-grained,
       resource owner = the repository owner, ONLY this repository, Administration RW,
       Contents RW, Issues RW, Pull requests RW, Pages RW, Metadata R - nothing else.
    2. Reads the value from a masked prompt (Read-Host -MaskInput) or from the env var
       NAMED by -FromEnv. Never a parameter default, never argv.
    3. Anonymous control FIRST (scripts/bootstrap/connect-github.ps1 doctrine): an
       unauthenticated GET of api.github.com/rate_limit answering above the 60/hr
       anonymous cap proves an injecting transport (measured in the agent container:
       GH_TOKEN is ignored and every answer is the proxy's own identity). There a
       per-token probe proves nothing, so the lane reports "transport-injected - verify
       from your own machine" and stores nothing, instead of a false pass.
    4. On a clean transport, verifies the token LIVE by name: `gh api repos/<repo> --jq
       .permissions` with GH_TOKEN set for that ONE child process only (GITHUB_TOKEN
       removed from it), requiring .admin == true; anything else is a failed item with
       the permission checklist as its replay.
    5. Stores it: `gh secret set HELIOS_ADMIN_TOKEN --repo <repo>` fed over STDIN by
       the ambient gh login (provision-github-secrets.ps1 Invoke-GhWithStdin shape).
    6. -ApplyGovernance (only with a token verified admin this run): runs
       scripts/github/apply-rulesets.ps1, apply-repo-settings.ps1, apply-labels.ps1 and
       apply-milestones.ps1 with -Apply -Repository <repo>, each in its own pwsh child
       with GH_TOKEN scoped to that child, and reports every exit code (0 applied /
       1 failed, replay / 2 needs owner - their shared contract). Ordering guard
       (docs/OWNER_START_HERE.md section 6, item 4): rulesets are REFUSED with the
       reason unless .github/workflows/dotnet-build.yml ON MAIN - read through
       `gh api repos/<repo>/contents/.github/workflows/dotnet-build.yml?ref=main` -
       carries the no-path-filter pull_request trigger. Until PR #113 is on main, four
       of the eight required contexts never start on a PR outside their paths, strand
       as Expected, and with bypass_actors = [] nobody can override them.

  Azure lane (-SkipAzure skips it)
    1. `az account show` (subscription name / tenant / user.type only) plus a live
       token refresh, `az account get-access-token --output none` (exit code only -
       the cached-profile-but-AADSTS50078 state auth-doctor.ps1 measured).
    2. Missing session, another tenant, or AADSTS50078 (MFA expired): runs
       `az login --use-device-code --tenant <tenant>` INTERACTIVELY - the one human
       step on this lane; az prints the URL and one-time code and this script waits.
       Never under -VerifyOnly (the command is printed as the owner action instead).
    3. `pwsh scripts/bootstrap/setup-tenant.ps1 -OpsIdentity -Apply` (its own
       contract: verify-first, idempotent; the helios-ops-automation app + service
       principal with a certificate credential generated INTO Key Vault - no client
       secret ever exists - and the tier "write" role grants), then prints exactly which
       env-var NAMES every future session exports to stay non-interactive:
       AZURE_CLIENT_ID (the appId, an identifier), AZURE_TENANT_ID, and
       AZURE_CLIENT_CERTIFICATE_PATH (the PEM you download once, outside the working
       tree, mode 600). auth-doctor.ps1 -Apply / auto-login.ps1 log in from those.
       The certificate and every token value are never echoed.

.PARAMETER VerifyOnly
Report every lane and change nothing: no prompt (unless -FromEnv names a token to
probe read-only), no `gh secret set`, no `az login`, no setup-tenant.

.PARAMETER SkipGitHub
Skip the GitHub admin lane (and -ApplyGovernance, which depends on it).

.PARAMETER SkipAzure
Skip the Azure lane.

.PARAMETER ApplyGovernance
After a verified admin token, run the four scripts/github/apply-*.ps1 with -Apply.

.PARAMETER Repository
Target repository as owner/name. Defaults to Yolkster64/helios-platform.

.PARAMETER Tenant
Entra tenant id for `az login --tenant`. Defaults to the documented HELIOS tenant.

.PARAMETER FromEnv
NAME of an environment variable holding the PAT (for example HELIOS_ADMIN_TOKEN). The
value is read from the environment, never from argv; nothing is prompted.

.PARAMETER Json
Emit one machine-readable object and nothing else on stdout: {script, generatedUtc,
mode, repository, tenant, transport, lanes[{name,state,detail,ownerAction}], replay[],
exitCode}. Needs -FromEnv (or -VerifyOnly / -SkipGitHub): a masked prompt cannot share
stdout with the object.

.EXAMPLE
pwsh scripts/bootstrap/connect-admin.ps1
# both lanes: checklist, masked prompt, live verify, store; device-code login if needed,
# then the ops identity and the three AZURE_* names to export

.EXAMPLE
pwsh scripts/bootstrap/connect-admin.ps1 -FromEnv HELIOS_ADMIN_TOKEN -ApplyGovernance
# no prompt: verify + store the env-held token, then apply the four governance scripts

.EXAMPLE
pwsh scripts/bootstrap/connect-admin.ps1 -VerifyOnly -Json
# report only, one object

.NOTES
Exit codes: 0 = every non-skipped lane ready; 1 = an item failed (replay list printed:
a token that is not admin, a refused `gh secret set`, a governance script or
setup-tenant that exited non-zero); 2 = a precondition is missing (gh/az/pwsh not on
PATH, an empty -FromEnv variable, -Json without -FromEnv, no console for the masked
prompt, -ApplyGovernance without the GitHub lane or with -VerifyOnly) or a lane needs
the owner (transport-injected, device-code login pending under -VerifyOnly, the
ruleset ordering guard, setup-tenant reporting steps that need attention). 1 wins over
2. With -Json a failed precondition still emits one object (exitCode 2,
failedPrecondition) so a `| ConvertFrom-Json` consumer never parses empty input.
Sibling contract: scripts/bootstrap/README.md "Contract shared by every script added
with the Control fabric".
#>
[CmdletBinding()]
param(
    [switch]$VerifyOnly,

    [switch]$SkipGitHub,

    [switch]$SkipAzure,

    [switch]$ApplyGovernance,

    [string]$Repository = 'Yolkster64/helios-platform',

    [string]$Tenant = '349e1399-dccf-45b1-af7e-05d7b0676abf',

    [string]$FromEnv = '',

    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRel = 'scripts/bootstrap/connect-admin.ps1'
$mode = if ($VerifyOnly) { 'verify-only' } else { 'apply' }
$secretName = 'HELIOS_ADMIN_TOKEN'
$patCreateUrl = 'https://github.com/settings/personal-access-tokens/new'
$setupTenantScript = Join-Path $PSScriptRoot 'setup-tenant.ps1'
$githubScriptDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'github'
# The four governance scripts, in the order governance-apply.yml runs them. Only the
# ruleset is behind the ordering guard: labels, milestones and settings cannot strand a
# required check.
$governanceSpecs = @(
    [pscustomobject]@{ Item = 'rulesets'; File = 'apply-rulesets.ps1'; Guarded = $true; Why = '.github/rulesets/*.json (needs repo admin)' }
    [pscustomobject]@{ Item = 'settings'; File = 'apply-repo-settings.ps1'; Guarded = $false; Why = 'Pages source, auto-merge, wiki, delete-branch-on-merge, automerge label (needs repo admin)' }
    [pscustomobject]@{ Item = 'labels'; File = 'apply-labels.ps1'; Guarded = $false; Why = 'config/github/labels.json' }
    [pscustomobject]@{ Item = 'milestones'; File = 'apply-milestones.ps1'; Guarded = $false; Why = 'config/github/milestones.json' }
)
# The three NAMES auth-doctor.ps1 -Apply logs in from (certificate form; never a secret).
$opsEnvNames = @('AZURE_CLIENT_ID', 'AZURE_TENANT_ID', 'AZURE_CLIENT_CERTIFICATE_PATH')

# --- Report idioms (provision-github-secrets.ps1 / first-run.ps1) ---------------------
# -Json promises one object and nothing else on stdout.
function Write-Report {
    param([string]$Message = '')
    if (-not $Json) { Write-Host $Message }
}

# StrictMode-safe property access on parsed JSON (rest-connect.ps1 pattern).
function Get-OptionalProperty {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object -or $Object -isnot [System.Management.Automation.PSObject]) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -ne $prop -and $null -ne $prop.Value) { return $prop.Value }
    return $Default
}

# Presence = a NON-WHITESPACE value (auth-doctor.ps1 rule). Read only for this test.
function Test-EnvValue {
    param([Parameter(Mandatory)][string]$Name)
    -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($Name))
}

# Application only: an alias/function shadowing the name would pass a bare Get-Command
# and then fail as an OS subprocess (script-patterns.md).
function Get-CliCommand {
    param([Parameter(Mandatory)][string]$Name)
    Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
}

$lanes = [System.Collections.Generic.List[object]]::new()
$replay = [System.Collections.Generic.List[string]]::new()

# One lane row. ready = nothing left to do; needs-owner = a human step, named in
# OwnerAction; failed = an item did not land (its replay is recorded separately);
# skipped = ruled out by a switch, recorded so the report shows what did NOT run.
function Add-Lane {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('ready', 'needs-owner', 'failed', 'skipped')][string]$State,
        [Parameter(Mandatory)][string]$Detail,
        [string]$OwnerAction = ''
    )
    $lanes.Add([ordered]@{ name = $Name; state = $State; detail = $Detail; ownerAction = $OwnerAction })
}

function Add-Replay {
    param([Parameter(Mandatory)][string]$Command)
    $replay.Add($Command)
}

$transportState = 'unprobed'

function New-ReportObject {
    param([int]$ExitCode, [string]$FailedPrecondition = '', [string[]]$Fix = @())
    $object = [ordered]@{
        script       = $scriptRel
        generatedUtc = (Get-Date).ToUniversalTime().ToString('o')
        mode         = $mode
        repository   = $Repository
        tenant       = $Tenant
        transport    = $transportState
    }
    if ($FailedPrecondition) {
        $object['failedPrecondition'] = $FailedPrecondition
        $object['fix'] = @($Fix)
    }
    $object['lanes'] = @($lanes)
    $object['replay'] = @($replay)
    $object['exitCode'] = $ExitCode
    return $object
}

# A failed precondition still honors the -Json one-object promise: the reason travels
# in the object (exitCode 2), so a piped consumer never parses empty input.
function Exit-Precondition {
    param([Parameter(Mandatory)][string]$Message, [string[]]$Fix = @())
    if ($Json) {
        New-ReportObject -ExitCode 2 -FailedPrecondition $Message -Fix $Fix | ConvertTo-Json -Depth 5
        exit 2
    }
    Write-Report "connect-admin: FAILED PRECONDITION - $Message"
    foreach ($line in $Fix) { Write-Report "  $line" }
    Write-Report 'Nothing was changed.'
    exit 2
}

function Write-SummaryAndExit {
    $failedCount = @($lanes | Where-Object { $_.state -eq 'failed' }).Count
    $ownerCount = @($lanes | Where-Object { $_.state -eq 'needs-owner' }).Count
    $exitCode = if ($failedCount -gt 0 -or $replay.Count -gt 0) { 1 } elseif ($ownerCount -gt 0) { 2 } else { 0 }
    if ($Json) {
        New-ReportObject -ExitCode $exitCode | ConvertTo-Json -Depth 5
        exit $exitCode
    }
    Write-Report ''
    Write-Report '== Summary =='
    $rows = $lanes | ForEach-Object {
        [pscustomobject]@{ Lane = $_.name; State = $_.state; Next = $(if ($_.ownerAction) { $_.ownerAction } else { '-' }) }
    }
    $table = $rows | Format-Table -AutoSize -Property Lane, State, Next | Out-String -Width 4096
    Write-Report $table.TrimEnd()
    Write-Report ''
    if ($replay.Count -gt 0) {
        Write-Report "connect-admin: $($replay.Count) item(s) FAILED - replay list:"
        foreach ($r in $replay) { Write-Report "  $r" }
    }
    elseif ($ownerCount -gt 0) {
        Write-Report "connect-admin: $ownerCount lane(s) need the owner - the Next column names the step."
    }
    else {
        Write-Report "connect-admin: every non-skipped lane is ready ($mode)."
    }
    exit $exitCode
}

# --- Captured child processes -----------------------------------------------------------
# One external process with stdin/stdout/stderr captured, never printed by this helper.
# -ScopedToken puts the candidate token into THIS child's environment block only (as
# GH_TOKEN, with the ambient GH_TOKEN / GITHUB_TOKEN removed so gh cannot silently
# answer with a different credential); it is never argv, never the parent's
# environment. -StdIn carries a value the child reads from its standard input.
function Invoke-Captured {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [AllowNull()][AllowEmptyString()][string]$StdIn = $null,
        [AllowNull()][AllowEmptyString()][string]$ScopedToken = $null
    )
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FilePath
    foreach ($a in $Arguments) { $psi.ArgumentList.Add($a) }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    if (-not [string]::IsNullOrEmpty($ScopedToken)) {
        foreach ($name in 'GH_TOKEN', 'GITHUB_TOKEN') { $null = $psi.Environment.Remove($name) }
        $psi.Environment['GH_TOKEN'] = $ScopedToken
    }
    $proc = [System.Diagnostics.Process]::Start($psi)
    try {
        # stderr is drained asynchronously so a chatty child can never deadlock on a
        # full pipe while this process waits on stdout.
        $stderrTask = $proc.StandardError.ReadToEndAsync()
        if ($null -ne $StdIn) { $proc.StandardInput.Write($StdIn) }
        $proc.StandardInput.Close()
        $stdout = $proc.StandardOutput.ReadToEnd()
        $proc.WaitForExit()
        return [pscustomobject]@{ ExitCode = $proc.ExitCode; StdOut = $stdout; StdErr = $stderrTask.Result }
    }
    finally { $proc.Dispose() }
}

# First non-blank line of a captured stream, truncated - gh/az failure text is
# value-free (HTTP status, permission text, AADSTS code) and is all a row needs.
function Get-FirstLine {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    $line = (@(("$Text" -split "`n") | Where-Object { $_.Trim() }) | Select-Object -First 1)
    $line = if ($line) { "$line".Trim() } else { '' }
    if ($line.Length -gt 160) { $line = $line.Substring(0, 160) + '...' }
    return $line
}

# A sibling script in its own pwsh child (first-run.ps1 pattern: exit codes and
# StrictMode stay isolated). Stdout is streamed to the report line by line as it
# arrives and collected; stderr is appended at the end. -ScopedToken as above.
function Invoke-PwshChild {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [string[]]$Arguments = @(),
        [AllowNull()][AllowEmptyString()][string]$ScopedToken = $null
    )
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $pwshExe
    foreach ($a in (@('-NoProfile', '-File', $ScriptPath) + $Arguments)) { $psi.ArgumentList.Add($a) }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    if (-not [string]::IsNullOrEmpty($ScopedToken)) {
        foreach ($name in 'GH_TOKEN', 'GITHUB_TOKEN') { $null = $psi.Environment.Remove($name) }
        $psi.Environment['GH_TOKEN'] = $ScopedToken
    }
    $lines = [System.Collections.Generic.List[string]]::new()
    $proc = [System.Diagnostics.Process]::Start($psi)
    try {
        $stderrTask = $proc.StandardError.ReadToEndAsync()
        $proc.StandardInput.Close()
        while ($null -ne ($line = $proc.StandardOutput.ReadLine())) {
            Write-Report "    | $line"
            $lines.Add($line)
        }
        $proc.WaitForExit()
        foreach ($errLine in @(($stderrTask.Result -split "`n") | Where-Object { $_.Trim() })) {
            Write-Report "    ! $($errLine.TrimEnd())"
            $lines.Add($errLine.TrimEnd())
        }
        return [pscustomobject]@{ ExitCode = $proc.ExitCode; Lines = $lines }
    }
    finally { $proc.Dispose() }
}

# --- Wire-truth probes (verbatim from scripts/bootstrap/connect-github.ps1) -------------
# Returns the numeric rate.limit (anonymous when no token is given) or $null on
# transport failure / unparsable body. Only the anonymous form is used here: the
# per-token probe is `gh api repos/<repo>` (permissions, not just validity).
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
    $script:transportState = if ($null -eq $anon) { 'unprobed' } elseif ($anon -gt 60) { 'injected' } else { 'clean' }
    return ($null -ne $anon -and $anon -gt 60)
}

# The ordering guard's file test: the top-level `pull_request:` trigger and every line
# nested under it. A `paths:` / `paths-ignore:` there is the filter PR #113 removes;
# a flow-style value on the same line is checked too. Comments and blanks are skipped.
function Test-UnfilteredPullRequestTrigger {
    param([Parameter(Mandatory)][string]$WorkflowText)
    $lines = @($WorkflowText -split "`r?`n")
    $prIndex = -1
    $prIndent = 0
    $prInline = ''
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^(\s*)pull_request:\s*(.*)$') {
            $prIndex = $i
            $prIndent = $Matches[1].Length
            $prInline = $Matches[2]
            break
        }
    }
    if ($prIndex -lt 0) {
        return [pscustomobject]@{ Unfiltered = $false; Reason = 'no pull_request trigger found in the file' }
    }
    if ($prInline -match '\bpaths(-ignore)?\b') {
        return [pscustomobject]@{ Unfiltered = $false; Reason = 'the pull_request trigger carries an inline paths filter' }
    }
    for ($j = $prIndex + 1; $j -lt $lines.Count; $j++) {
        $line = $lines[$j]
        if ($line -match '^\s*(#.*)?$') { continue }
        $indent = ($line -replace '^(\s*).*$', '$1').Length
        if ($indent -le $prIndent) { break }
        if ($line -match '^\s*(paths(-ignore)?):') {
            return [pscustomobject]@{ Unfiltered = $false; Reason = "the pull_request trigger still carries a $($Matches[1]): filter" }
        }
    }
    return [pscustomobject]@{ Unfiltered = $true; Reason = 'the pull_request trigger has no paths filter' }
}

function Write-TokenChecklist {
    $owner = $Repository.Split('/')[0]
    Write-Report "  Create the fine-grained PAT here: $patCreateUrl"
    Write-Report "    Resource owner         : $owner"
    Write-Report "    Repository access      : Only select repositories -> $Repository (nothing else)"
    Write-Report '    Repository permissions : Administration  Read and write'
    Write-Report '                             Contents        Read and write'
    Write-Report '                             Issues          Read and write'
    Write-Report '                             Pull requests   Read and write'
    Write-Report '                             Pages           Read and write'
    Write-Report '                             Metadata        Read (GitHub adds it itself)'
    Write-Report '    Nothing else, no account permissions; choose an expiry and calendar the renewal.'
    Write-Report "    Stored as the Actions secret $secretName (the NAME governance-apply.yml reads); the"
    Write-Report '    value goes into the masked prompt (or the env var named by -FromEnv) and nowhere else.'
}

# --- Preconditions (all of them, before any lane runs) --------------------------------
Write-Report "connect-admin: mode=$mode repository=$Repository tenant=$Tenant lanes=$(if ($SkipGitHub) { '-' } else { 'github' })$(if ($ApplyGovernance) { '+governance' })/$(if ($SkipAzure) { '-' } else { 'azure' })"

if ($Repository -notmatch '^[^/\s]+/[^/\s]+$') {
    Exit-Precondition -Message "-Repository must be owner/name (got '$Repository')."
}
if ($FromEnv -and $FromEnv -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
    Exit-Precondition -Message "-FromEnv must be an environment variable NAME (got '$FromEnv')."
}
if ($FromEnv -and -not (Test-EnvValue -Name $FromEnv)) {
    Exit-Precondition -Message "environment variable $FromEnv is empty (name given by -FromEnv)." -Fix @(
        "Export the PAT into $FromEnv in this shell (never on a command line), then re-run.")
}
if ($SkipGitHub -and $SkipAzure) {
    Exit-Precondition -Message 'both lanes are skipped - nothing to do.'
}
if ($ApplyGovernance -and $SkipGitHub) {
    Exit-Precondition -Message '-ApplyGovernance needs the GitHub lane (drop -SkipGitHub).'
}
if ($ApplyGovernance -and $VerifyOnly) {
    Exit-Precondition -Message '-ApplyGovernance mutates the repository; it cannot combine with -VerifyOnly.'
}
$gh = $null
$az = $null
if (-not $SkipGitHub) {
    $gh = Get-CliCommand -Name 'gh'
    if (-not $gh) {
        Exit-Precondition -Message 'the GitHub CLI (gh) is not on PATH.' -Fix @('Install it (https://cli.github.com/), or pass -SkipGitHub.')
    }
    if (-not $VerifyOnly -and -not $FromEnv) {
        if ($Json) {
            Exit-Precondition -Message '-Json needs -FromEnv <NAME>: a masked prompt cannot share stdout with the one object.' -Fix @(
                "Export the PAT into an env var and pass its NAME: -FromEnv $secretName")
        }
        if ([Console]::IsInputRedirected) {
            Exit-Precondition -Message 'no interactive console to read the token from (stdin is redirected).' -Fix @(
                "Run from a terminal, or export the PAT into an env var and pass its NAME: -FromEnv $secretName")
        }
    }
    if ($ApplyGovernance) {
        foreach ($spec in $governanceSpecs) {
            $path = Join-Path $githubScriptDir $spec.File
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                Exit-Precondition -Message "scripts/github/$($spec.File) is missing from this checkout (needed by -ApplyGovernance)."
            }
        }
    }
}
if (-not $SkipAzure) {
    $az = Get-CliCommand -Name 'az'
    if (-not $az) {
        Exit-Precondition -Message 'the Azure CLI (az) is not on PATH.' -Fix @('Install it (https://aka.ms/azure-cli), or pass -SkipAzure.')
    }
    if (-not $VerifyOnly -and -not (Test-Path -LiteralPath $setupTenantScript -PathType Leaf)) {
        Exit-Precondition -Message 'scripts/bootstrap/setup-tenant.ps1 is missing from this checkout.'
    }
}
# Children run in their own pwsh process (first-run.ps1 pattern).
$pwshCommand = Get-CliCommand -Name 'pwsh'
$pwshExe = if ($pwshCommand) { $pwshCommand.Source } else { [Environment]::ProcessPath }
if (-not $VerifyOnly -and ($ApplyGovernance -or -not $SkipAzure) -and -not $pwshExe) {
    Exit-Precondition -Message 'no PowerShell 7 executable is resolvable for the child scripts.'
}

# ======================================================================================
# GitHub admin lane
# ======================================================================================
$tokenVerifiedAdmin = $false
if ($SkipGitHub) {
    Add-Lane -Name 'github-admin-token' -State skipped -Detail '-SkipGitHub'
    Add-Lane -Name 'github-governance' -State skipped -Detail '-SkipGitHub'
}
else {
    Write-Report ''
    Write-Report "== GitHub admin lane: $secretName for $Repository =="

    # Ambient wire (the credential gh holds for THIS shell: keyring, env, or the
    # transport) - read-only, one permissions object, never credential material.
    $ambient = Invoke-Captured -FilePath $gh.Source -Arguments @('api', "repos/$Repository", '--jq', '.permissions')
    $ambientPush = $false
    $ambientAdmin = $false
    $ambientReadable = ($ambient.ExitCode -eq 0)
    if ($ambientReadable) {
        try {
            $perms = $ambient.StdOut | ConvertFrom-Json
            $ambientPush = ((Get-OptionalProperty $perms 'push' $false) -eq $true)
            $ambientAdmin = ((Get-OptionalProperty $perms 'admin' $false) -eq $true)
        }
        catch { $ambientReadable = $false }
    }
    # Secret presence by NAME (a refused listing is reported with its reason - proxy
    # policy, missing scope - never guessed absent).
    $listing = Invoke-Captured -FilePath $gh.Source -Arguments @('api', "repos/$Repository/actions/secrets?per_page=100", '--jq', '.secrets[].name')
    $secretKnown = ($listing.ExitCode -eq 0)
    $secretPresent = $false
    $secretState = 'unknown'
    if ($secretKnown) {
        $secretPresent = (@(($listing.StdOut -split "`n") | ForEach-Object { $_.Trim() }) -contains $secretName)
        $secretState = if ($secretPresent) { 'present' } else { 'absent' }
    }
    else {
        $reason = Get-FirstLine $listing.StdErr
        if (-not $reason) { $reason = "gh api exited $($listing.ExitCode)" }
        $secretState = "unknown ($reason)"
    }
    $injected = Test-TransportInjected
    Write-Report "  wire (ambient gh credential): readable=$ambientReadable push=$ambientPush admin=$ambientAdmin; secret $secretName by name: $secretState; transport: $transportState"
    if ($injected) {
        Write-Report '  transport-injected: an anonymous probe of api.github.com/rate_limit answered above the'
        Write-Report '  60/hr anonymous cap, so a proxy owns this session''s GitHub credentials and every'
        Write-Report '  per-token answer is the proxy''s identity (GH_TOKEN is ignored). Per-token validity'
        Write-Report '  is unprovable here - verify from your own machine.'
    }
    Write-Report ''
    Write-TokenChecklist

    $storeReplay = if ($IsWindows) { "`$env:$secretName | gh secret set $secretName --repo $Repository" }
    else { "printenv $secretName | gh secret set $secretName --repo $Repository" }
    $ownMachineRerun = "pwsh $scriptRel -SkipAzure$(if ($ApplyGovernance) { ' -ApplyGovernance' })   # from your own machine"

    if ($VerifyOnly -and -not $FromEnv) {
        if ($secretPresent) {
            Add-Lane -Name 'github-admin-token' -State ready -Detail "$secretName is stored (by name)$(if ($injected) { '; its validity is unprovable from this transport' })"
        }
        else {
            Add-Lane -Name 'github-admin-token' -State 'needs-owner' -Detail "$secretName is $secretState; nothing verified or stored (-VerifyOnly)" `
                -OwnerAction "mint the PAT ($patCreateUrl), then: pwsh $scriptRel -SkipAzure   (or -FromEnv $secretName)"
        }
    }
    elseif ($injected) {
        # Nothing is read, verified, or stored: persisting an unproven token is how a
        # dead credential ends up in a secret (connect-github.ps1 -FromEnv rule).
        Add-Lane -Name 'github-admin-token' -State 'needs-owner' -Detail "transport-injected - per-token validity is unprovable on this host; $secretName by name: $secretState; nothing was verified or stored" `
            -OwnerAction $ownMachineRerun
    }
    else {
        # --- Acquire: env var NAME or masked prompt; never argv, never a default. ------
        $adminToken = $null
        if ($FromEnv) {
            $adminToken = [Environment]::GetEnvironmentVariable($FromEnv)
            Write-Report ''
            Write-Report "  token source: env $FromEnv (value never printed)"
        }
        else {
            Write-Report ''
            $adminToken = Read-Host -Prompt "  Paste the $secretName value (input is masked)" -MaskInput
        }
        $adminToken = if ($null -ne $adminToken) { "$adminToken".Trim() } else { '' }
        if (-not $adminToken) {
            Exit-Precondition -Message 'no token was entered.'
        }

        # --- Verify LIVE by name: GH_TOKEN exists only in this one child's environment.
        $probeCommand = "gh api repos/$Repository --jq .permissions   # GH_TOKEN scoped to this child only"
        Write-Report "  verifying: $probeCommand"
        $probe = Invoke-Captured -FilePath $gh.Source -Arguments @('api', "repos/$Repository", '--jq', '.permissions') -ScopedToken $adminToken
        $probeAdmin = $false
        $probeDetail = ''
        if ($probe.ExitCode -ne 0) {
            $reason = Get-FirstLine $probe.StdErr
            $probeDetail = "the wire rejected the token (gh api exited $($probe.ExitCode)$(if ($reason) { ": $reason" }))"
        }
        else {
            try {
                $tokenPerms = $probe.StdOut | ConvertFrom-Json
                $probeAdmin = ((Get-OptionalProperty $tokenPerms 'admin' $false) -eq $true)
                $probeDetail = "gh api repos/$Repository .permissions.admin = $(if ($probeAdmin) { 'true' } else { 'false' })"
            }
            catch { $probeDetail = 'the wire answered but its permissions object was unparsable' }
        }

        if (-not $probeAdmin) {
            Write-Report "  FAILED: $probeDetail - $secretName must hold Administration RW on $Repository."
            Write-Report '  Mint a token with exactly this permission set, then re-run:'
            Write-TokenChecklist
            Add-Lane -Name 'github-admin-token' -State failed -Detail "$probeDetail; nothing was stored" -OwnerAction "mint per the checklist ($patCreateUrl), then: pwsh $scriptRel -SkipAzure -FromEnv $secretName"
            Add-Replay "[$secretName] mint the PAT per the checklist above ($patCreateUrl), then: pwsh $scriptRel -SkipAzure -FromEnv $secretName"
        }
        else {
            $tokenVerifiedAdmin = $true
            Write-Report "  verified: $probeDetail"
            if ($VerifyOnly) {
                if ($secretPresent) {
                    Add-Lane -Name 'github-admin-token' -State ready -Detail "env $FromEnv verified admin=true; $secretName is stored (by name); not re-stored (-VerifyOnly)"
                }
                else {
                    Add-Lane -Name 'github-admin-token' -State 'needs-owner' -Detail "env $FromEnv verified admin=true; $secretName is $secretState; not stored (-VerifyOnly)" `
                        -OwnerAction "pwsh $scriptRel -SkipAzure -FromEnv $FromEnv"
                }
            }
            else {
                # --- Store: value over STDIN to `gh secret set`, ambient gh login. ------
                $storeCommand = "gh secret set $secretName --repo $Repository   # value via stdin"
                Write-Report "  storing: $storeCommand"
                $store = Invoke-Captured -FilePath $gh.Source -Arguments @('secret', 'set', $secretName, '--repo', $Repository) -StdIn $adminToken
                if ($store.ExitCode -eq 0) {
                    Write-Report "  stored: Actions secret $secretName on $Repository (value never printed)."
                    Add-Lane -Name 'github-admin-token' -State ready -Detail "verified admin=true and stored as Actions secret $secretName (over stdin)"
                }
                else {
                    $reason = Get-FirstLine $store.StdErr
                    Write-Report "  FAILED: gh secret set exited $($store.ExitCode)$(if ($reason) { ": $reason" }) - the ambient gh login needs collaborator write (push=$ambientPush)."
                    Write-Report "  replay (from a shell whose gh is logged in as the owner): $storeReplay"
                    Add-Lane -Name 'github-admin-token' -State failed -Detail "verified admin=true but gh secret set exited $($store.ExitCode)$(if ($reason) { " ($reason)" })" -OwnerAction $storeReplay
                    Add-Replay "[$secretName] $storeReplay"
                }
            }
        }

        # --- Governance: the four scripts, GH_TOKEN scoped per child ------------------
        if ($ApplyGovernance) {
            Write-Report ''
            Write-Report "== Governance: scripts/github/apply-*.ps1 -Apply -Repository $Repository (GH_TOKEN scoped per child) =="
            $guardEndpoint = "repos/$Repository/contents/.github/workflows/dotnet-build.yml?ref=main"
            $guardCommand = "gh api $guardEndpoint --jq .content"
            Write-Report "  ordering guard (docs/OWNER_START_HERE.md section 6, item 4): $guardCommand"
            $guard = Invoke-Captured -FilePath $gh.Source -Arguments @('api', $guardEndpoint, '--jq', '.content') -ScopedToken $adminToken
            $guardOk = $false
            $guardReason = ''
            if ($guard.ExitCode -ne 0) {
                $reason = Get-FirstLine $guard.StdErr
                $guardReason = "could not read dotnet-build.yml on main (gh api exited $($guard.ExitCode)$(if ($reason) { ": $reason" }))"
            }
            else {
                try {
                    $b64 = (@(($guard.StdOut -split "`r?`n") | ForEach-Object { $_.Trim() }) -join '')
                    $workflowText = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
                    $verdict = Test-UnfilteredPullRequestTrigger -WorkflowText $workflowText
                    $guardOk = $verdict.Unfiltered
                    $guardReason = $verdict.Reason
                }
                catch { $guardReason = "dotnet-build.yml on main could not be decoded ($($_.Exception.Message))" }
            }
            Write-Report "  guard: $(if ($guardOk) { 'PASS' } else { 'REFUSE rulesets' }) - $guardReason"
            if (-not $guardOk) {
                Write-Report '  Reason: until the no-path-filter pull_request trigger (PR #113) is on main, four of the'
                Write-Report '  eight required contexts (Build solution & run tests, bicep-validate, arm-freshness,'
                Write-Report '  terraform-validate) never start on a PR outside their paths and strand as Expected;'
                Write-Report '  with bypass_actors = [] nobody can override a stranded check, so every such merge'
                Write-Report '  would block. Merge PR #113 first, then re-run with -ApplyGovernance.'
            }

            $itemStates = [System.Collections.Generic.List[string]]::new()
            $governanceFailed = $false
            $governanceOwner = $false
            $governanceOwnerAction = ''
            foreach ($spec in $governanceSpecs) {
                $scriptPath = Join-Path $githubScriptDir $spec.File
                $rel = "scripts/github/$($spec.File)"
                $itemReplay = if ($IsWindows) { "`$env:GH_TOKEN = `$env:$secretName; pwsh $rel -Apply -Repository $Repository; Remove-Item Env:GH_TOKEN" }
                else { "GH_TOKEN=`$$secretName pwsh $rel -Apply -Repository $Repository" }
                if ($spec.Guarded -and -not $guardOk) {
                    Write-Report ''
                    Write-Report "  [$($spec.Item)] REFUSED by the ordering guard - $guardReason (not run)."
                    $itemStates.Add("$($spec.Item)=refused(guard)")
                    $governanceOwner = $true
                    $governanceOwnerAction = "merge PR #113 (no-path-filter triggers on main), then: pwsh $scriptRel -SkipAzure -ApplyGovernance -FromEnv $secretName"
                    continue
                }
                Write-Report ''
                Write-Report "  [$($spec.Item)] running: pwsh $rel -Apply -Repository $Repository   # GH_TOKEN scoped to this child ($($spec.Why))"
                $run = Invoke-PwshChild -ScriptPath $scriptPath -Arguments @('-Apply', '-Repository', $Repository) -ScopedToken $adminToken
                $itemStates.Add("$($spec.Item)=exit $($run.ExitCode)")
                switch ($run.ExitCode) {
                    0 { Write-Report "  [$($spec.Item)] exit 0 - applied / in sync." }
                    2 {
                        Write-Report "  [$($spec.Item)] exit 2 - precondition or credential missing (the script printed the owner step)."
                        $governanceOwner = $true
                        if (-not $governanceOwnerAction) { $governanceOwnerAction = "read the [$($spec.Item)] output above, then: $itemReplay" }
                    }
                    default {
                        Write-Report "  [$($spec.Item)] exit $($run.ExitCode) - FAILED (replay list printed by the script) - replay: $itemReplay"
                        $governanceFailed = $true
                        Add-Replay "[$($spec.Item)] $itemReplay"
                    }
                }
            }
            $governanceDetail = $itemStates -join ', '
            if ($governanceFailed) {
                Add-Lane -Name 'github-governance' -State failed -Detail $governanceDetail -OwnerAction 'see the replay list'
            }
            elseif ($governanceOwner) {
                Add-Lane -Name 'github-governance' -State 'needs-owner' -Detail $governanceDetail -OwnerAction $governanceOwnerAction
            }
            else {
                Add-Lane -Name 'github-governance' -State ready -Detail $governanceDetail
            }
        }

        # Clear every in-process copy of the value (setup-tenant.ps1 shape).
        $adminToken = $null
        Remove-Variable -Name adminToken
    }

    if ($ApplyGovernance -and -not ($lanes | Where-Object { $_.name -eq 'github-governance' })) {
        Add-Lane -Name 'github-governance' -State 'needs-owner' -Detail '-ApplyGovernance needs a token verified admin=true in this run (not verified this run)' `
            -OwnerAction "pwsh $scriptRel -SkipAzure -ApplyGovernance -FromEnv $secretName"
    }
    elseif (-not $ApplyGovernance) {
        Add-Lane -Name 'github-governance' -State skipped -Detail "-ApplyGovernance not passed (governance-apply.yml applies from main once $secretName is stored)"
    }
}

# ======================================================================================
# Azure lane
# ======================================================================================
if ($SkipAzure) {
    Add-Lane -Name 'azure-session' -State skipped -Detail '-SkipAzure'
    Add-Lane -Name 'azure-ops-identity' -State skipped -Detail '-SkipAzure'
}
else {
    Write-Report ''
    Write-Report "== Azure lane: tenant $Tenant =="
    $azLoginCommand = "az login --use-device-code --tenant $Tenant"

    # One probe pair, re-used after a login: cached profile (identity fields only) plus
    # a live token refresh whose exit code / stderr carries the AADSTS code.
    function Get-AzSession {
        $show = Invoke-Captured -FilePath $az.Source -Arguments @('account', 'show', '--output', 'json')
        $result = [pscustomobject]@{ Healthy = $false; Diagnosis = ''; Subscription = ''; TenantId = ''; UserType = ''; MfaExpired = $false }
        if ($show.ExitCode -ne 0) {
            $text = "$($show.StdErr) $($show.StdOut)"
            if ($text -match 'AADSTS50078|multi-?factor authentication has expired') {
                $result.MfaExpired = $true
                $result.Diagnosis = 'AADSTS50078 (UserStrongAuthExpired): the session''s MFA claim expired'
            }
            elseif ($text -match '(AADSTS\d+)') { $result.Diagnosis = "Entra rejected the cached token ($($Matches[1]))" }
            else { $result.Diagnosis = 'no az session (az account show failed - not logged in)' }
            return $result
        }
        try {
            $account = $show.StdOut | ConvertFrom-Json
            $result.Subscription = [string](Get-OptionalProperty $account 'name' '')
            $result.TenantId = [string](Get-OptionalProperty $account 'tenantId' '')
            $result.UserType = [string](Get-OptionalProperty (Get-OptionalProperty $account 'user' $null) 'type' '')
        }
        catch {
            $result.Diagnosis = 'az account show succeeded but its JSON was unparsable'
            return $result
        }
        if ($result.TenantId -and $result.TenantId -ne $Tenant) {
            $result.Diagnosis = "the cached session is for tenant $($result.TenantId), not $Tenant"
            return $result
        }
        $refresh = Invoke-Captured -FilePath $az.Source -Arguments @('account', 'get-access-token', '--output', 'none')
        if ($refresh.ExitCode -ne 0) {
            $text = "$($refresh.StdErr) $($refresh.StdOut)"
            if ($text -match 'AADSTS50078|multi-?factor authentication has expired') {
                $result.MfaExpired = $true
                $result.Diagnosis = 'AADSTS50078 (UserStrongAuthExpired): profile cached but the live token refresh fails - MFA expired'
            }
            elseif ($text -match '(AADSTS\d+)') { $result.Diagnosis = "profile cached but the live token refresh fails ($($Matches[1]))" }
            else { $result.Diagnosis = "profile cached but the live token refresh fails (az exited $($refresh.ExitCode))" }
            return $result
        }
        $result.Healthy = $true
        $result.Diagnosis = "live: subscription `"$($result.Subscription)`", tenant $($result.TenantId), user.type $($result.UserType)"
        return $result
    }

    $session = Get-AzSession
    Write-Report "  az account show + get-access-token: $(if ($session.Healthy) { 'ok' } else { 'NOT READY' }) - $($session.Diagnosis)"
    $sessionReady = $session.Healthy
    if (-not $sessionReady) {
        if ($VerifyOnly) {
            Add-Lane -Name 'azure-session' -State 'needs-owner' -Detail "$($session.Diagnosis); not logged in (-VerifyOnly)" -OwnerAction "$azLoginCommand   (or: pwsh $scriptRel -SkipGitHub)"
        }
        else {
            Write-Report ''
            Write-Report "  Owner step (the one human click on this lane): $azLoginCommand"
            Write-Report '  az prints a URL and a one-time code below; complete them in any browser. This script waits.'
            # Console inherited on purpose: the one-time code must reach the human
            # unbuffered. --output none keeps the account JSON off stdout (-Json contract).
            & $az.Source login --use-device-code --tenant $Tenant --output none
            $loginExit = $LASTEXITCODE
            if ($loginExit -ne 0) {
                Write-Report "  FAILED: az login exited $loginExit."
                Add-Lane -Name 'azure-session' -State failed -Detail "$($session.Diagnosis); az login --use-device-code exited $loginExit" -OwnerAction $azLoginCommand
                Add-Replay "[azure-session] $azLoginCommand"
            }
            else {
                $session = Get-AzSession
                Write-Report "  after login: $(if ($session.Healthy) { 'ok' } else { 'NOT READY' }) - $($session.Diagnosis)"
                $sessionReady = $session.Healthy
                if ($sessionReady) {
                    Add-Lane -Name 'azure-session' -State ready -Detail "device-code login completed; $($session.Diagnosis)"
                }
                else {
                    Add-Lane -Name 'azure-session' -State failed -Detail "az login exited 0 but the session is still not live: $($session.Diagnosis)" -OwnerAction $azLoginCommand
                    Add-Replay "[azure-session] $azLoginCommand"
                }
            }
        }
    }
    else {
        Add-Lane -Name 'azure-session' -State ready -Detail $session.Diagnosis
    }

    # --- Ops identity: the upgrade path off the MFA-bound user session ----------------
    $presentNames = @($opsEnvNames | Where-Object { Test-EnvValue -Name $_ })
    $missingNames = @($opsEnvNames | Where-Object { -not (Test-EnvValue -Name $_) })
    $namesDetail = "non-interactive names present: $(if ($presentNames.Count) { $presentNames -join ', ' } else { 'none' }); missing: $(if ($missingNames.Count) { $missingNames -join ', ' } else { 'none' })"
    $opsCommand = "pwsh scripts/bootstrap/setup-tenant.ps1 -OpsIdentity -Apply"
    Write-Report ''
    Write-Report "  ops identity: $namesDetail"
    if ($VerifyOnly) {
        if ($missingNames.Count -eq 0) {
            Add-Lane -Name 'azure-ops-identity' -State ready -Detail "$namesDetail (values never read beyond presence)"
        }
        else {
            Add-Lane -Name 'azure-ops-identity' -State 'needs-owner' -Detail "$namesDetail; setup-tenant not run (-VerifyOnly)" -OwnerAction "pwsh $scriptRel -SkipGitHub   (runs $opsCommand)"
        }
    }
    elseif (-not $sessionReady) {
        Add-Lane -Name 'azure-ops-identity' -State 'needs-owner' -Detail 'blocked: the Azure session is not live' -OwnerAction "$azLoginCommand, then: pwsh $scriptRel -SkipGitHub"
    }
    else {
        Write-Report "  running: $opsCommand"
        $ops = Invoke-PwshChild -ScriptPath $setupTenantScript -Arguments @('-OpsIdentity', '-Apply')
        # Identifiers only, parsed from setup-tenant's own printed container-login
        # runbook: the appId (--username) and the Key Vault certificate coordinates.
        $appId = ''
        $vaultName = ''
        $certName = ''
        foreach ($line in $ops.Lines) {
            if (-not $appId -and $line -match 'az login --service-principal --username (\S+)') { $appId = $Matches[1] }
            if (-not $vaultName -and $line -match 'az keyvault secret download .*--vault-name (\S+) --name (\S+)') { $vaultName = $Matches[1]; $certName = $Matches[2] }
        }
        $appIdText = if ($appId) { $appId } else { '<appId: az ad app list --display-name helios-ops-automation --query [0].appId -o tsv>' }
        $vaultText = if ($vaultName) { $vaultName } else { '<vault>' }
        $certText = if ($certName) { $certName } else { 'helios-ops-automation' }
        Write-Report ''
        Write-Report "  setup-tenant exited $($ops.ExitCode)."
        Write-Report '  Export these NAMES (values are never printed by this script) so every future session'
        Write-Report '  logs in without a human (auth-doctor.ps1 -Apply / auto-login.ps1 read them):'
        Write-Report "    AZURE_CLIENT_ID               = $appIdText"
        Write-Report "    AZURE_TENANT_ID               = $Tenant"
        Write-Report '    AZURE_CLIENT_CERTIFICATE_PATH = <path of the PEM below - outside the working tree, mode 600>'
        Write-Report '  The PEM, retrieved ONCE (it is a materialized credential while it exists; keep it out of'
        Write-Report '  the repo and out of any chat):'
        Write-Report "    az keyvault secret download --file ops-cert.pfx --vault-name $vaultText --name $certText --encoding base64"
        Write-Report '    openssl pkcs12 -in ops-cert.pfx -passin pass: -passout pass: -out ops-cert.pem -nodes && rm ops-cert.pfx'
        Write-Report '    chmod 600 ops-cert.pem   # then AZURE_CLIENT_CERTIFICATE_PATH=<absolute path of ops-cert.pem>'
        Write-Report '  Then, in every new session: pwsh scripts/bootstrap/auth-doctor.ps1 -Apply'
        $opsDetail = "setup-tenant -OpsIdentity -Apply exited $($ops.ExitCode); $namesDetail"
        switch ($ops.ExitCode) {
            0 {
                if ($missingNames.Count -eq 0) { Add-Lane -Name 'azure-ops-identity' -State ready -Detail $opsDetail }
                else {
                    Add-Lane -Name 'azure-ops-identity' -State 'needs-owner' -Detail "$opsDetail; identity minted, names not yet exported in this shell" `
                        -OwnerAction "export $($missingNames -join ', ') as printed above, then: pwsh scripts/bootstrap/auth-doctor.ps1 -Apply"
                }
            }
            2 {
                Add-Lane -Name 'azure-ops-identity' -State 'needs-owner' -Detail "$opsDetail (its summary names the steps that need attention)" -OwnerAction "read the setup-tenant summary above, fix, then: $opsCommand"
            }
            default {
                Add-Lane -Name 'azure-ops-identity' -State failed -Detail $opsDetail -OwnerAction $opsCommand
                Add-Replay "[azure-ops-identity] $opsCommand"
            }
        }
    }
}

# ======================================================================================
# Summary + exit contract
# ======================================================================================
Write-SummaryAndExit
