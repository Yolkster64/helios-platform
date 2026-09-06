#Requires -Version 7
<#
.SYNOPSIS
Provisions the repository's Actions variables and secrets from environment variables
of the SAME NAME — the OIDC identifiers as variables, the connector/PAT values as
secrets — as an idempotent GET-diff-then-print-then-apply pass. Dry-run by default.

.DESCRIPTION
Targets (the OIDC variables and connector secrets from docs/architecture/CONNECTIONS_SETUP.md
"Connection checklist"; HELIOS_ADMIN_TOKEN from the .github/workflows/governance-apply.yml
header, which holds its exact fine-grained permission list):

  variable  AZURE_CLIENT_ID          OIDC app (client) id   printed by azure-oidc-setup
  variable  AZURE_TENANT_ID          tenant id              printed by azure-oidc-setup
  variable  AZURE_SUBSCRIPTION_ID    subscription id        printed by azure-oidc-setup
  secret    LINEAR_API_KEY           .github/workflows/linear-sync.yml
  secret    SLACK_WEBHOOK_URL        .github/workflows/notify-slack.yml
  secret    COPILOT_DISPATCH_TOKEN   copilot-dispatch.yml (fine-grained PAT: Issues + Pull requests write)
  secret    HELIOS_ADMIN_TOKEN       governance-apply.yml admin writes (fine-grained PAT:
                                     Administration, Contents, Issues, Pull requests, Pages RW)

Dry-run prints one row per target: kind, whether the source env var holds a value
(NAME only), and the current repository state from `gh api .../actions/variables`
and `.../actions/secrets` (names only; when the listing is refused - proxy policy,
missing scope - the state reads "unknown" with the reason, never a guess).

-Apply sets only the targets whose source env var is non-empty; the others are
skipped by name. Every mutation prints its exact command FIRST, a failed item never
aborts the pass, and the script exits 1 with a replay list.

SECURITY - values never on argv, never printed, never logged: `gh secret set` /
`gh variable set` read the body from STDIN when --body is absent, so the value is
written to the child's stdin by this process and nowhere else. gh's own stderr on
failure (HTTP status, permission text) is value-free and is shown truncated.

.PARAMETER Repository
Target repository as owner/name. Defaults to Yolkster64/helios-platform.

.PARAMETER Apply
Execute the `gh` calls. Without it the script only reports (dry run).

.PARAMETER Json
Emit one machine-readable object (nothing else on stdout).

.EXAMPLE
pwsh scripts/bootstrap/provision-github-secrets.ps1
# dry run: target table with source presence and repository state

.EXAMPLE
$env:LINEAR_API_KEY -and (pwsh scripts/bootstrap/provision-github-secrets.ps1 -Apply)
# sets every target whose env var holds a value

.NOTES
Exit codes: 0 = success (or clean dry run); 1 = one or more targets failed to apply
(replay list printed); 2 = in -Apply mode only: gh CLI missing, the wire probe cannot
read the repo, or the wire credential lacks collaborator write (`.permissions.push`) -
Actions secrets and variables need at least that. A dry run never exits 2: it degrades
instead (every row reads "unknown (<reason>)" and the reason is printed), mirroring the
scripts/github/apply-*.ps1 siblings' "re-run without -Apply for a dry run that needs
neither" rule. With -Json a failed precondition still emits one object (exitCode 2,
failedPrecondition) so a `| ConvertFrom-Json` consumer gets the reason, not empty input.
The precondition mirrors scripts/github/apply-*.ps1: `gh api repos/{repo}` exit code
plus one boolean permission field; `gh auth status` is never consulted (it can lie both
ways - scripts/verify/rest-connect.ps1 doctrine).
#>
[CmdletBinding()]
param(
    [string]$Repository = 'Yolkster64/helios-platform',

    [switch]$Apply,

    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$mode = if ($Apply) { 'apply' } else { 'dry-run' }

# -Json promises one object and nothing else on stdout.
function Write-Report {
    param([string]$Message = '')
    if (-not $Json) { Write-Host $Message }
}

# Presence = a NON-WHITESPACE value (auth-doctor.ps1 rule). Read only for this test.
function Test-EnvValue {
    param([Parameter(Mandatory)][string]$Name)
    -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($Name))
}

$targets = @(
    [pscustomobject]@{ Name = 'AZURE_CLIENT_ID'; Kind = 'variable'; Why = 'OIDC app (client) id - helios-deploy.yml vars.AZURE_CLIENT_ID' }
    [pscustomobject]@{ Name = 'AZURE_TENANT_ID'; Kind = 'variable'; Why = 'tenant id - helios-deploy.yml vars.AZURE_TENANT_ID' }
    [pscustomobject]@{ Name = 'AZURE_SUBSCRIPTION_ID'; Kind = 'variable'; Why = 'subscription id - helios-deploy.yml vars.AZURE_SUBSCRIPTION_ID' }
    [pscustomobject]@{ Name = 'LINEAR_API_KEY'; Kind = 'secret'; Why = 'linear-sync.yml (skips green without it)' }
    [pscustomobject]@{ Name = 'SLACK_WEBHOOK_URL'; Kind = 'secret'; Why = 'notify-slack.yml (skips green without it)' }
    [pscustomobject]@{ Name = 'COPILOT_DISPATCH_TOKEN'; Kind = 'secret'; Why = 'copilot-dispatch.yml (fine-grained PAT: Issues + Pull requests write)' }
    [pscustomobject]@{ Name = 'HELIOS_ADMIN_TOKEN'; Kind = 'secret'; Why = 'governance-apply.yml admin writes (fine-grained PAT: Administration, Contents, Issues, Pull requests, Pages RW + Metadata R)' }
)

Write-Report "provision-github-secrets: mode=$mode repository=$Repository targets=$($targets.Count)"

# --- Wire-truth precondition (apply-rulesets.ps1 / apply-repo-settings.ps1 shape) ----
$gh = Get-Command gh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$wireOk = $false
$wirePush = $false
$wireAdmin = $false
if ($gh) {
    $permRaw = @(& $gh.Source api "repos/$Repository" --jq '[.permissions.push, .permissions.admin] | @tsv' 2>$null)
    if ($LASTEXITCODE -eq 0) {
        $wireOk = $true
        $fields = ((@($permRaw) -join '').Trim() -split "`t")
        $wirePush = ($fields.Count -ge 1 -and $fields[0] -eq 'true')
        $wireAdmin = ($fields.Count -ge 2 -and $fields[1] -eq 'true')
    }
}
# A failed -Apply precondition still honors the -Json one-object promise: the reason
# travels in the object (exitCode 2), so a piped consumer never parses empty input.
function Exit-Precondition {
    param([Parameter(Mandatory)][string]$Message, [string[]]$Fix = @())
    if ($Json) {
        [ordered]@{
            script             = 'scripts/bootstrap/provision-github-secrets.ps1'
            generatedUtc       = (Get-Date).ToUniversalTime().ToString('o')
            mode               = $mode
            repository         = $Repository
            wire               = [ordered]@{ readable = $wireOk; push = $wirePush; admin = $wireAdmin }
            failedPrecondition = $Message
            fix                = @($Fix)
            targets            = @()
            failures           = @()
            exitCode           = 2
        } | ConvertTo-Json -Depth 3
        exit 2
    }
    Write-Report "provision-github-secrets: FAILED PRECONDITION - $Message"
    foreach ($line in $Fix) { Write-Report $line }
    Write-Report 'Nothing was changed. Re-run without -Apply for a dry run that needs neither.'
    exit 2
}
if ($Apply -and -not $gh) {
    Exit-Precondition -Message 'the GitHub CLI (gh) is not on PATH.' -Fix @('Install it (https://cli.github.com/).')
}
if ($Apply -and -not $wireOk) {
    Exit-Precondition -Message "the wire probe could not read repos/$Repository." -Fix @(
        'No usable GitHub credential answered on the REST wire. Authenticate first: "gh auth login"',
        'or scripts/bootstrap/connect-github.sh --from-env.')
}
if ($Apply -and -not $wirePush) {
    Exit-Precondition -Message "the wire credential has no collaborator write on $Repository (.permissions.push is not true)." -Fix @(
        'Actions secrets and variables need collaborator write (fine-grained PAT: "Secrets" and',
        '"Variables" write; classic PAT: repo scope on a repository you can push to).')
}
# The dry run degrades instead of gating (sibling rule), but says so up front: a
# table of "unknown" rows without the reason on top would read like a bug.
if (-not $Apply -and -not $gh) {
    Write-Report 'provision-github-secrets: gh is not on PATH - every row below reads unknown; install it (https://cli.github.com/) for wire truth. -Apply would exit 2 here.'
}
elseif (-not $Apply -and -not $wireOk) {
    Write-Report "provision-github-secrets: the wire probe could not read repos/$Repository - every row below reads unknown; authenticate (gh auth login) for wire truth. -Apply would exit 2 here."
}

# --- Current state by NAME (one listing per kind) -------------------------------------
# A refused listing (this container's proxy answers 403 for every Actions path,
# a token may lack the scope) is reported with its reason - never guessed absent.
function Get-NameListing {
    param([Parameter(Mandatory)][string]$Endpoint, [Parameter(Mandatory)][string]$JqPath)
    if (-not $gh) { return [pscustomobject]@{ Names = @(); Known = $false; Reason = 'gh not on PATH' } }
    $raw = @(& $gh.Source api "$Endpoint`?per_page=100" --jq $JqPath 2>&1)
    $exit = $LASTEXITCODE
    $lines = @($raw | ForEach-Object { "$_" })
    if ($exit -eq 0) {
        return [pscustomobject]@{ Names = @($lines | Where-Object { $_.Trim() }); Known = $true; Reason = '' }
    }
    $reason = (@($lines | Where-Object { $_.Trim() }) | Select-Object -First 1)
    if (-not $reason) { $reason = "gh api exited $exit" }
    return [pscustomobject]@{ Names = @(); Known = $false; Reason = "$reason".Trim() }
}
$variableListing = Get-NameListing -Endpoint "repos/$Repository/actions/variables" -JqPath '.variables[].name'
$secretListing = Get-NameListing -Endpoint "repos/$Repository/actions/secrets" -JqPath '.secrets[].name'

# --- One mutation: exact command printed FIRST; the value flows through stdin only ----
function Invoke-GhWithStdin {
    param([Parameter(Mandatory)][string[]]$Arguments, [Parameter(Mandatory)][string]$Value)
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $gh.Source
    foreach ($a in $Arguments) { $psi.ArgumentList.Add($a) }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    try {
        # stderr is drained asynchronously so a chatty child can never deadlock on
        # a full pipe while this process waits on stdout.
        $stderrTask = $proc.StandardError.ReadToEndAsync()
        $proc.StandardInput.Write($Value)
        $proc.StandardInput.Close()
        $null = $proc.StandardOutput.ReadToEnd()
        $proc.WaitForExit()
        return [pscustomobject]@{ ExitCode = $proc.ExitCode; StdErr = $stderrTask.Result }
    }
    finally { $proc.Dispose() }
}

$rows = [System.Collections.Generic.List[object]]::new()
$failures = [System.Collections.Generic.List[string]]::new()
$applied = 0
$skippedCount = 0

foreach ($target in $targets) {
    $listing = if ($target.Kind -eq 'variable') { $variableListing } else { $secretListing }
    $current = if (-not $listing.Known) { "unknown ($($listing.Reason))" }
    elseif ($listing.Names -contains $target.Name) { 'present' }
    else { 'absent' }
    $present = Test-EnvValue -Name $target.Name
    $verb = if ($target.Kind -eq 'variable') { 'variable' } else { 'secret' }
    $command = "gh $verb set $($target.Name) --repo $Repository   # value from env $($target.Name) via stdin"
    # The replay must paste on the host that printed it: printenv is a Unix tool, and on
    # Windows pwsh the variable itself is the pipe source (gh trims the trailing newline
    # the pipeline adds; the value still never touches argv).
    $replay = if ($IsWindows) { "`$env:$($target.Name) | gh $verb set $($target.Name) --repo $Repository" }
    else { "printenv $($target.Name) | gh $verb set $($target.Name) --repo $Repository" }
    $plan = if (-not $present) { "skip (env $($target.Name) empty)" } else { 'set' }
    $result = ''

    if ($Apply -and $present) {
        Write-Report "  [$($target.Name)] applying: $command"
        $outcome = Invoke-GhWithStdin -Arguments @($verb, 'set', $target.Name, '--repo', $Repository) -Value ([Environment]::GetEnvironmentVariable($target.Name))
        if ($outcome.ExitCode -eq 0) {
            Write-Report "  [$($target.Name)] applied."
            $result = 'applied'
            $applied++
        }
        else {
            $reason = (@(($outcome.StdErr -split "`n") | Where-Object { $_.Trim() }) | Select-Object -First 1)
            $reason = if ($reason) { "$reason".Trim() } else { '' }
            if ($reason.Length -gt 160) { $reason = $reason.Substring(0, 160) + '...' }
            Write-Report "  [$($target.Name)] FAILED (gh exited $($outcome.ExitCode)$(if ($reason) { ": $reason" })) - replay: $replay"
            $failures.Add("[$($target.Name)] $replay")
            $result = "failed (gh exited $($outcome.ExitCode))"
        }
    }
    elseif ($Apply) {
        $result = 'skipped'
        $skippedCount++
    }

    $rows.Add([pscustomobject]@{
            Target  = $target.Name
            Kind    = $target.Kind
            Source  = "env $($target.Name): " + $(if ($present) { 'present' } else { 'empty' })
            Current = $current
            Plan    = $plan
            Result  = $result
            Command = $command
            Why     = $target.Why
        })
}

if ($Json) {
    [ordered]@{
        script       = 'scripts/bootstrap/provision-github-secrets.ps1'
        generatedUtc = (Get-Date).ToUniversalTime().ToString('o')
        mode         = $mode
        repository   = $Repository
        wire         = [ordered]@{ readable = $wireOk; push = $wirePush; admin = $wireAdmin }
        listings     = [ordered]@{
            variables = [ordered]@{ known = $variableListing.Known; reason = $variableListing.Reason }
            secrets   = [ordered]@{ known = $secretListing.Known; reason = $secretListing.Reason }
        }
        targets      = @($rows | ForEach-Object {
                [ordered]@{
                    name = $_.Target; kind = $_.Kind; sourceEnv = $_.Target
                    sourcePresent = ($_.Source -like '*present'); current = $_.Current
                    plan = $_.Plan; result = $_.Result; command = $_.Command; why = $_.Why
                }
            })
        failures     = @($failures)
        exitCode     = $(if ($failures.Count -gt 0) { 1 } else { 0 })
    } | ConvertTo-Json -Depth 5
    exit $(if ($failures.Count -gt 0) { 1 } else { 0 })
}

Write-Report ''
Write-Report ("wire: readable=$wireOk push=$wirePush admin=$wireAdmin; variables listing: " +
    $(if ($variableListing.Known) { 'ok' } else { "refused ($($variableListing.Reason))" }) +
    '; secrets listing: ' + $(if ($secretListing.Known) { 'ok' } else { "refused ($($secretListing.Reason))" }))
$table = $rows | Format-Table -AutoSize -Property Target, Kind, Source, Current, Plan, Result | Out-String -Width 4096
Write-Report $table.TrimEnd()
if (-not $Apply) {
    Write-Report ''
    Write-Report 'Commands the apply pass would run for every target whose env var holds a value:'
    foreach ($row in $rows) { Write-Report "  [dry-run] $($row.Command)" }
}

Write-Report ''
if ($failures.Count -gt 0) {
    Write-Report "provision-github-secrets: $($failures.Count) target(s) FAILED to apply - replay list:"
    foreach ($f in $failures) { Write-Report "  $f" }
    exit 1
}
if ($Apply) {
    Write-Report "provision-github-secrets: complete - $applied applied, $skippedCount skipped (env var empty). Re-run to confirm every row reads 'present'."
}
else {
    Write-Report 'provision-github-secrets: dry run complete - nothing was changed. Export the env vars, then re-run with -Apply.'
}
exit 0
