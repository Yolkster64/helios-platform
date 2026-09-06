#Requires -Version 7
<#
.SYNOPSIS
The ONE command for a fresh shell (PowerShell twin of scripts/bootstrap/first-run.sh):
runs the whole HELIOS bring-up as an ordered chain over the EXISTING scripts, records
every step and lane in .helios/bootstrap-state.json, and ends with ONE numbered
checklist of the steps only a human can do.

.DESCRIPTION
Orchestrator only (repo rule: PowerShell wraps, it never reimplements). Every step
is SOFT — its exit code is captured and the chain continues — because a lane that
needs the owner is a checklist item, not a failure:

  1. pwsh scripts/bootstrap/cloud-shell-setup.ps1 -SkipSmoke   the bash bring-up (CLI
     fleet, device-code logins gh/az, Cloud Shell persistence, env wiring, readiness
     inventory) through its twin, which owns bash resolution: Git Bash first on
     Windows, the System32 WSL launcher never used silently, the exact steps printed
     and exit 2 without a usable bash. -VerifyOnly forwards (read-only). -SkipAuth is
     added when stdin is redirected or -Json is given: a device-code login blocks on
     a human typing the code, and a code hidden in a captured stream helps nobody.
  2. pwsh scripts/bootstrap/auto-login.ps1 -Json            acquire-and-report: az
     repair is delegated to auth-doctor.ps1 -Apply (NON-interactive only — service
     principal or managed identity — but still a login that rewrites the az profile),
     then the Key Vault pulls; -UseManagedIdentity is forwarded. SKIPPED under
     -VerifyOnly, because a read-only pass must never change the cached identity.
     (A child process cannot export into this session either way; dot-source
     auto-login.ps1 yourself for that.)
  3. pwsh scripts/verify/rest-connect.ps1 -Json             wire truth (REST probes).
  4. pwsh scripts/bootstrap/auth-doctor.ps1 -Json           lane table + owner actions
     (report-only: the doctor mutates nothing without -Apply).
  5. pwsh scripts/bootstrap/setup-everything.ps1 -Json      toolchain/identity/inventory/
     smoke rollup (skipped with -SkipSetup).
  6. pwsh scripts/bootstrap/provision-github-secrets.ps1 -Json   repository secrets and
     variables by NAME (dry run, never mutates): the wire truth behind the repo-secret
     checklist items, so HELIOS_ADMIN_TOKEN is asked for because the repo lacks it —
     not because the local gh keyring happens to be empty.

Output — .helios/bootstrap-state.json (gitignored):
  {generatedUtc, environment, verifyOnly,
   steps[{name, script, exitCode, ok, note?}],    exitCode -1 = skipped (note says why),
                                                  127 = interpreter missing
   lanes{<doctor lanes>..., "rest:github", "rest:azure"},
   repoSecrets{<target>: "present" | "absent" | "unknown (<reason>)"},
   ownerActions[{lane, action}],
   checklist[{title, lines[]}]   the numbered human steps with their exact commands
   reports{<step>: "bootstrap/<step>.json"}}       only the reports THIS run produced
plus the raw per-step reports under .helios/bootstrap/*.json and the chain log
.helios/bootstrap/first-run.log (step 1's output is logged only when captured).

Secrets: nothing here reads a credential value; the child reports carry env-var NAMES
only, and the checklist prints commands, never values.

.PARAMETER VerifyOnly
Read-only pass: no installs, no logins, no persistence (forwarded to step 1); step 2
(auto-login) is skipped because it delegates to auth-doctor -Apply, which can perform
a non-interactive az login, and -UseManagedIdentity is not forwarded.

.PARAMETER Json
Emit the state object and nothing else on stdout (chained-script convention).

.PARAMETER SkipSetup
Skip step 5 (setup-everything.ps1); the auth steps and the repo-secret probe still run.

.PARAMETER UseManagedIdentity
Forwarded to auto-login.ps1 (classic IMDS-only VMs expose no managed-identity
endpoint variable, so the doctor tries `az login --identity` only when told to).
Ignored under -VerifyOnly (step 2 does not run).

.PARAMETER Connect
Step 0: run scripts/bootstrap/connect-devices.ps1 -SkipChain first (both device
codes in one sitting, console inherited), then continue the chain with step 1's own
auth prompts skipped. Ignored under -VerifyOnly, -Json, or without a console.

.EXAMPLE
pwsh scripts/bootstrap/first-run.ps1

.EXAMPLE
pwsh scripts/bootstrap/first-run.ps1 -VerifyOnly

.EXAMPLE
pwsh scripts/bootstrap/first-run.ps1 -Json | ConvertFrom-Json

.NOTES
Exit codes: 0 = the chain ran (needs-owner lanes NEVER gate — they ARE the
checklist); 1 = internal failure (no PowerShell executable resolvable for the
children, or the state file could not be written).
#>
[CmdletBinding()]
param(
    [switch]$VerifyOnly,

    [switch]$Json,

    [switch]$SkipSetup,

    [switch]$UseManagedIdentity,

    [switch]$Connect
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

# Documented env vars only, never heuristics (auth-doctor.ps1 uses the same probe).
$environment = if ($env:AZUREPS_HOST_ENVIRONMENT -or $env:ACC_CLOUD) { 'cloud-shell' }
elseif ($env:CODESPACES) { 'codespaces' }
else { 'local' }
$modeLabel = if ($VerifyOnly) { 'verify-only' } else { 'full' }

# -Json promises one object and nothing else on stdout, and Write-Host lands on
# stdout from an external caller's viewpoint, so every progress line gates on it.
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

# Children run in their own pwsh process so exit codes and StrictMode stay isolated
# and their -Json stdout comes back clean (setup-everything.ps1 pattern). Step 1 goes
# through cloud-shell-setup.ps1 for the same reason: ONE bash resolver in this lane.
$pwshCommand = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$pwshExe = if ($pwshCommand) { $pwshCommand.Source } else { [Environment]::ProcessPath }

$stateDir = Join-Path $repoRoot '.helios' 'bootstrap'
$stateFile = Join-Path $repoRoot '.helios' 'bootstrap-state.json'
$null = New-Item -ItemType Directory -Path $stateDir -Force
$chainLog = Join-Path $stateDir 'first-run.log'
Set-Content -LiteralPath $chainLog -Value '' -NoNewline
$reportNames = @('auto-login', 'rest-connect', 'auth-doctor', 'setup-everything', 'provision-github-secrets')
# Stale reports from an earlier run must never be listed as this run's: a -SkipSetup
# pass would otherwise advertise yesterday's setup-everything.json as if it ran today.
foreach ($stale in $reportNames) {
    Remove-Item -LiteralPath (Join-Path $stateDir "$stale.json") -Force -ErrorAction SilentlyContinue
}

$steps = [System.Collections.Generic.List[object]]::new()
$reports = @{}

# A step the mode rules out is recorded as skipped (exit -1 + the reason), never
# silently dropped: the state file must show what did NOT run and why.
function Add-Step {
    param([string]$Name, [string]$Script, [int]$ExitCode, [string]$Note = '')
    $entry = [ordered]@{ name = $Name; script = $Script; exitCode = $ExitCode; ok = ($ExitCode -eq 0) }
    if ($Note) { $entry['note'] = $Note }
    $steps.Add($entry)
}

function Invoke-JsonStep {
    param([int]$Number, [string]$Name, [string]$Script, [string[]]$Arguments = @())
    $scriptPath = Join-Path $repoRoot $Script
    $outPath = Join-Path $stateDir "$Name.json"
    Write-Report ''
    Write-Report ('-- {0}. {1} (pwsh {2} {3}) --' -f $Number, $Name, $Script, ($Arguments -join ' '))
    if (-not $pwshExe) {
        Write-Report '   skipped: no PowerShell 7 executable resolvable'
        Add-Step -Name $Name -Script $Script -ExitCode 127
        return
    }
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        Write-Report '   skipped: script not found'
        Add-Step -Name $Name -Script $Script -ExitCode -1 -Note 'skipped: script not found in this checkout'
        return
    }
    # Capture ALL stdout first, THEN read $LASTEXITCODE (repo pipeline-trap rule);
    # stderr goes to the chain log so the one-object stdout contract stays clean.
    $lines = @(& $pwshExe -NoProfile -File $scriptPath @Arguments 2>>$chainLog | ForEach-Object { "$_" })
    $exit = [int]$LASTEXITCODE
    $text = $lines -join "`n"
    [System.IO.File]::WriteAllText($outPath, $text + "`n")
    try { $reports[$Name] = $text | ConvertFrom-Json }
    catch { Write-Verbose "$Name emitted invalid JSON: $($_.Exception.Message)" }
    $relative = $outPath.Substring($repoRoot.Length).TrimStart('/', '\')
    if ($exit -eq 0) { Write-Report "   exit 0 (ok); report: $relative" }
    else { Write-Report "   exit $exit (not clean — the checklist below carries the fix); report: $relative" }
    Add-Step -Name $Name -Script $Script -ExitCode $exit
}

function Skip-Step {
    param([int]$Number, [string]$Name, [string]$Script, [string]$Why)
    Write-Report ''
    Write-Report ('-- {0}. {1} (pwsh {2}) -- skipped: {3}' -f $Number, $Name, $Script, $Why)
    Add-Step -Name $Name -Script $Script -ExitCode -1 -Note "skipped: $Why"
}

try {
    Write-Report "== HELIOS first-run ($environment, $modeLabel) — ordered chain over the existing scripts =="
    $internalFailure = $false
    if (-not $pwshExe) {
        Write-Report '   no PowerShell 7 executable resolvable for the child steps — steps 1-6 cannot run.'
        $internalFailure = $true
    }

    # --- 0. -Connect: both device codes in one sitting -------------------------------
    # connect-devices.ps1 -SkipChain, console inherited: this script IS the chain, so
    # only the logins run here and step 1 then skips its own auth prompts. Never
    # under -VerifyOnly (a read-only pass changes no cached identity) and never
    # without a console (a device code needs a human).
    $connectDone = $false
    if ($Connect) {
        if ($VerifyOnly) { Write-Report '   -Connect ignored under -VerifyOnly (a read-only pass performs no login).' }
        elseif ([Console]::IsInputRedirected -or $Json) { Write-Report '   -Connect needs a console (not -Json, stdin not redirected); the logins stay checklist items.' }
        elseif (-not $pwshExe) { Write-Report '   -Connect needs pwsh; the logins stay checklist items.' }
        else {
            Write-Report ''
            Write-Report '-- 0. connect-devices (pwsh scripts/bootstrap/connect-devices.ps1 -SkipChain) --'
            & $pwshExe -NoProfile -File (Join-Path $repoRoot 'scripts/bootstrap/connect-devices.ps1') -SkipChain
            $connectExit = [int]$LASTEXITCODE
            Write-Report "   connect-devices exited $connectExit (0 = both logins ready; 2 = a lane still needs you - see its table)"
            # Only a clean exit hands the logins to step 1 as done; an expired, refused
            # or precondition-stopped run leaves step 1 free to prompt for them again.
            $connectDone = ($connectExit -eq 0)
        }
    }

    # --- 1. cloud-shell-setup, through its .ps1 twin ---------------------------------
    # The twin prefers Git Bash on Windows and refuses the System32 WSL launcher (it
    # cannot open this checkout's Windows path), prints the exact steps and exits 2
    # when no usable bash exists, and otherwise forwards the bash exit code — so this
    # script never resolves bash itself and never disagrees with its sibling.
    $setupScript = 'scripts/bootstrap/cloud-shell-setup.ps1'
    $setupArgs = @(if ($VerifyOnly) { '-VerifyOnly' } else { '-SkipSmoke' })
    # A device-code login blocks on a human typing the code: redirected stdin, or
    # stdout captured for -Json, means the login becomes a checklist item instead.
    if (-not $VerifyOnly -and ([Console]::IsInputRedirected -or $Json -or $connectDone)) { $setupArgs += '-SkipAuth' }
    Write-Report ''
    Write-Report ('-- 1. cloud-shell-setup (pwsh {0} {1}) --' -f $setupScript, ($setupArgs -join ' '))
    if ($pwshExe) {
        $setupPath = Join-Path $repoRoot $setupScript
        if ($Json) {
            $setupLines = @(& $pwshExe -NoProfile -File $setupPath @setupArgs 2>&1 | ForEach-Object { "$_" })
            $setupExit = [int]$LASTEXITCODE
            Add-Content -LiteralPath $chainLog -Value $setupLines
        }
        else {
            # Console inherited on purpose: the device-code prompts must reach the
            # human unbuffered, so this step is not logged when it runs visibly.
            & $pwshExe -NoProfile -File $setupPath @setupArgs
            $setupExit = [int]$LASTEXITCODE
        }
        if ($setupExit -eq 2) { Write-Report '   exit 2: no usable bash — the twin printed the manual steps; the checklist names the install' }
        else { Write-Report "   exit $setupExit" }
    }
    else {
        Write-Report ('   skipped: no PowerShell 7 executable resolvable — run it yourself: pwsh {0} {1}' -f $setupScript, ($setupArgs -join ' '))
        $setupExit = 127
    }
    Add-Step -Name 'cloud-shell-setup' -Script $setupScript -ExitCode $setupExit

    # --- 2..6 -----------------------------------------------------------------------
    if ($VerifyOnly) {
        # auto-login.ps1 has no report-only switch: it always spawns auth-doctor -Apply,
        # which performs `az login --service-principal` / `--identity` when the env
        # holds those credentials — a login, and one that can switch the cached
        # identity. That is exactly what a verify-only pass promises not to do; step 4
        # already carries the report-only doctor, so skipping loses no lane data.
        Skip-Step -Number 2 -Name 'auto-login' -Script 'scripts/bootstrap/auto-login.ps1' -Why 'verify-only (auto-login delegates to auth-doctor -Apply, which can log in non-interactively; -UseManagedIdentity not forwarded)'
    }
    else {
        $autoLoginArgs = @('-Json') + @(if ($UseManagedIdentity) { '-UseManagedIdentity' })
        Invoke-JsonStep -Number 2 -Name 'auto-login' -Script 'scripts/bootstrap/auto-login.ps1' -Arguments $autoLoginArgs
    }
    Invoke-JsonStep -Number 3 -Name 'rest-connect' -Script 'scripts/verify/rest-connect.ps1' -Arguments @('-Json')
    Invoke-JsonStep -Number 4 -Name 'auth-doctor' -Script 'scripts/bootstrap/auth-doctor.ps1' -Arguments @('-Json')
    if ($SkipSetup) {
        Skip-Step -Number 5 -Name 'setup-everything' -Script 'scripts/bootstrap/setup-everything.ps1' -Why '-SkipSetup'
    }
    else {
        Invoke-JsonStep -Number 5 -Name 'setup-everything' -Script 'scripts/bootstrap/setup-everything.ps1' -Arguments @('-Json')
    }
    Invoke-JsonStep -Number 6 -Name 'provision-github-secrets' -Script 'scripts/bootstrap/provision-github-secrets.ps1' -Arguments @('-Json')

    # --- Merge ------------------------------------------------------------------------
    function Get-LaneRows {
        param($Report)
        $rows = Get-OptionalProperty $Report 'lanes' @()
        return @($rows | Where-Object { $_ -is [System.Management.Automation.PSObject] })
    }
    $doctor = if ($reports.ContainsKey('auth-doctor')) { $reports['auth-doctor'] } else { $null }
    $rest = if ($reports.ContainsKey('rest-connect')) { $reports['rest-connect'] } else { $null }
    $provision = if ($reports.ContainsKey('provision-github-secrets')) { $reports['provision-github-secrets'] } else { $null }

    # Lanes are keyed by name so a consumer can ask lanes.gh.state directly; the
    # rest-connect lanes get a "rest:" prefix because "github"/"azure" there mean
    # the WIRE, while the doctor's "gh"/"az" mean the CLI session.
    $lanes = [ordered]@{}
    foreach ($row in (Get-LaneRows $doctor)) {
        $entry = [ordered]@{}
        foreach ($field in 'state', 'method', 'detail', 'ownerAction') {
            $value = Get-OptionalProperty $row $field ''
            if ("$value".Trim()) { $entry[$field] = "$value" }
        }
        $lanes[[string](Get-OptionalProperty $row 'lane' '?')] = $entry
    }
    foreach ($row in (Get-LaneRows $rest)) {
        $entry = [ordered]@{}
        foreach ($field in 'state', 'source', 'identity', 'detail', 'ownerAction') {
            $value = Get-OptionalProperty $row $field ''
            if ("$value".Trim()) { $entry[$field] = "$value" }
        }
        $lanes['rest:' + [string](Get-OptionalProperty $row 'lane' '?')] = $entry
    }

    # Repository secrets/variables by NAME, straight from provision-github-secrets'
    # per-target `current` ("present" / "absent" / "unknown (<reason>)"): the checklist
    # asks for a repo secret because the REPO lacks it, never because a local CLI
    # session happens to be logged out. No report at all is its own honest reason.
    $repoSecrets = [ordered]@{}
    foreach ($row in @(Get-OptionalProperty $provision 'targets' @())) {
        $name = [string](Get-OptionalProperty $row 'name' '')
        if ($name) { $repoSecrets[$name] = [string](Get-OptionalProperty $row 'current' 'unknown (no state reported)') }
    }
    function Get-RepoSecretState {
        param([string]$Name)
        if ($repoSecrets.Contains($Name) -and $repoSecrets[$Name]) { return $repoSecrets[$Name] }
        return 'unknown (provision-github-secrets.ps1 produced no report)'
    }

    $ownerActions = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    # Dedupe on the COMMAND portion: the same `az login --tenant ...` arrives from the
    # doctor and again from setup-everything with slightly different trailing
    # comments, and a checklist that lists one command twice reads as two steps.
    function Get-ActionKey {
        param([AllowNull()][AllowEmptyString()][string]$Text)
        if (-not $Text) { return '' }
        return ($Text -split '#', 2)[0].Trim()
    }
    function Add-OwnerAction {
        param([string]$Lane, $Text)
        $trimmed = if ($Text -is [string]) { $Text.Trim() } else { '' }
        $key = Get-ActionKey $trimmed
        if (-not $key -or -not $seen.Add($key)) { return }
        $ownerActions.Add([ordered]@{ lane = $Lane; action = $trimmed })
    }
    foreach ($row in (Get-LaneRows $doctor)) { Add-OwnerAction -Lane ([string](Get-OptionalProperty $row 'lane' '?')) -Text (Get-OptionalProperty $row 'ownerAction' '') }
    foreach ($row in (Get-LaneRows $rest)) { Add-OwnerAction -Lane ('rest:' + [string](Get-OptionalProperty $row 'lane' '?')) -Text (Get-OptionalProperty $row 'ownerAction' '') }
    foreach ($source in 'auto-login', 'setup-everything') {
        if (-not $reports.ContainsKey($source)) { continue }
        foreach ($action in @(Get-OptionalProperty $reports[$source] 'ownerActions' @())) {
            Add-OwnerAction -Lane $source -Text $(if ($action -is [string]) { $action } else { ($action | ConvertTo-Json -Compress) })
        }
    }

    $reportPaths = [ordered]@{}
    foreach ($name in $reportNames) {
        if (Test-Path -LiteralPath (Join-Path $stateDir "$name.json")) { $reportPaths[$name] = "bootstrap/$name.json" }
    }

    # --- Checklist ----------------------------------------------------------------------
    # Built BEFORE the state is written so -Json and the state file carry the same
    # exact commands the terminal shows; a machine consumer must not get a vaguer
    # list than the human.
    # One item per needs-owner lane with the EXACT command, in the order a human would
    # do them: logins first, then the Key Vault wiring (the set-provider-secrets lines
    # below exit 2 until it is done), then the vault values, then the repository
    # secrets. Raw doctor text is used only where no better command exists, and every
    # raw line consumed here is remembered so the harvested tail never repeats it.
    function Get-LaneState { param([string]$Name) if ($lanes.Contains($Name) -and $lanes[$Name].Contains('state')) { $lanes[$Name]['state'] } else { $null } }
    function Test-NeedsOwner { param([string]$Name) (Get-LaneState $Name) -eq 'needs-owner' }
    function Get-RawAction { param([string]$Name) if ($lanes.Contains($Name) -and $lanes[$Name].Contains('ownerAction')) { $lanes[$Name]['ownerAction'] } else { '' } }
    function Get-LaneDetail { param([string]$Name) if ($lanes.Contains($Name) -and $lanes[$Name].Contains('detail')) { $lanes[$Name]['detail'] } else { '' } }

    $items = [System.Collections.Generic.List[object]]::new()
    $covered = [System.Collections.Generic.HashSet[string]]::new()
    function Add-Item { param([string]$Title, [string[]]$Lines) $items.Add([pscustomobject]@{ Title = $Title; Lines = $Lines }) }
    function Set-Covered { param([AllowNull()][AllowEmptyString()][string]$Text) $key = Get-ActionKey $Text; if ($key) { $null = $covered.Add($key) } }
    function Test-Covered { param([AllowNull()][AllowEmptyString()][string]$Text) $covered.Contains((Get-ActionKey $Text)) }
    # The doctor's own line is kept only when it adds a command the item does not
    # already carry — its `claude setup-token` would otherwise print twice in one item.
    function Add-RawLine {
        param([string[]]$Lines, [AllowNull()][AllowEmptyString()][string]$Raw)
        if (-not $Raw) { return , [string[]]$Lines }
        $keys = @($Lines | ForEach-Object { Get-ActionKey $_ })
        if ($keys -contains (Get-ActionKey $Raw)) { return , [string[]]$Lines }
        return , [string[]](@($Lines) + @($Raw))
    }
    $ghLogin = 'gh auth login --hostname github.com --git-protocol https --web --scopes models:read'
    $provisionApply = 'pwsh scripts/bootstrap/provision-github-secrets.ps1 -Apply'
    # The load step, once: the doctor's `(bash) or pwsh: ...` prose and connect-account's
    # `# after the az lane ...` comment are this same step in two wordings, so every
    # owner action starting with either command is covered by it.
    $loadLines = @(
        '. scripts/bootstrap/auto-login.ps1   # pwsh: Key Vault -> OPENAI_API_KEY / ANTHROPIC_API_KEY / GITHUB_MODELS_TOKEN in THIS session (dot-sourced)',
        'source scripts/bootstrap/load-env-from-keyvault.sh   # bash twin')
    $loadPrefixes = @('source scripts/bootstrap/load-env-from-keyvault.sh', '. scripts/bootstrap/auto-login.ps1')
    function Set-CoveredLoadActions {
        foreach ($action in $ownerActions) {
            $key = Get-ActionKey $action.action
            foreach ($prefix in $loadPrefixes) { if ($key.StartsWith($prefix)) { Set-Covered $action.action; break } }
        }
    }

    # --- logins ---
    # One sitting for both codes first; the two raw items after it are the by-hand path.
    if ((Test-NeedsOwner 'gh') -or (Test-NeedsOwner 'az')) {
        Add-Item -Title 'GitHub + Azure device codes in one sitting' -Lines @(
            'pwsh scripts/bootstrap/connect-devices.ps1   # both codes on one screen (verify-first), then the chain; bash twin: bash scripts/bootstrap/connect-devices.sh; or: pwsh scripts/bootstrap/first-run.ps1 -Connect')
    }
    if (Test-NeedsOwner 'gh') {
        $lines = @($ghLogin + '   # device code: gh prints a URL and a one-time code')
        if ((Get-LaneState 'rest:github') -eq 'ready') {
            $lines += '# rest:github is already ready through the transport; the keyring login matters for gh on YOUR machine / Cloud Shell'
        }
        Add-Item -Title 'GitHub CLI login (device code)' -Lines $lines
        Set-Covered (Get-RawAction 'gh')
    }
    if (Test-NeedsOwner 'az') {
        $azRaw = Get-RawAction 'az'
        Add-Item -Title 'Azure login (device code + MFA)' -Lines @($(if ($azRaw -like '*az login*') { $azRaw } else { 'az login --use-device-code   # then: az account set --subscription <id>' }))
        Set-Covered $azRaw
    }

    # --- vault wiring BEFORE the vault values: every set-provider-secrets line below
    # needs AZURE_KEY_VAULT_URI, so a human following the numbers must meet it first.
    if ([string]::IsNullOrWhiteSpace($env:AZURE_KEY_VAULT_URI)) {
        # Executable lines, not a comment: azure-up.ps1 writes .helios/azure.env.ps1, and
        # once that file exists dot-sourcing it IS the wiring; before it exists the
        # provisioning command (or a variable pointing at an existing vault) is the step.
        $wiringLines = if (Test-Path -LiteralPath (Join-Path $repoRoot '.helios' 'azure.env.ps1')) {
            @('. .helios/azure.env.ps1   # written by scripts/bootstrap/azure-up.ps1; sets AZURE_KEY_VAULT_URI for this session')
        }
        else {
            @('pwsh scripts/bootstrap/azure-up.ps1   # provisions the vault (infra/main.bicep) and writes .helios/azure.env.ps1',
              '$env:AZURE_KEY_VAULT_URI = ''https://<vault>.vault.azure.net/''   # or point at a vault that already exists')
        }
        Add-Item -Title 'Key Vault wiring (provider keys live in the vault, never in the repo)' -Lines ([string[]](@($wiringLines) + @(
            'pwsh scripts/bootstrap/set-provider-secrets.ps1 -Apply   # masked prompts for openai-api-key / anthropic-api-key / github-models-token') + @($loadLines)))
        # auto-login and setup-everything report the same wiring in their own words;
        # this item IS that step, so their lines must not resurface as a second one.
        foreach ($action in $ownerActions) {
            if ($action.action -like '*AZURE_KEY_VAULT_URI*') { Set-Covered $action.action }
        }
        Set-CoveredLoadActions
    }

    # --- vault values ---
    if (Test-NeedsOwner 'openai-codex') {
        $codexLines = @()
        # The device-code login is asked for only when the doctor did not already see
        # a cached CLI login; telling a human to redo a login that is done is noise.
        if ((Get-LaneDetail 'openai-codex') -like '*codex login status exits 0*') {
            $codexLines += '# the codex CLI already holds a cached login (codex login status exits 0); only the openai / openai-codex API providers still need OPENAI_API_KEY'
        }
        else {
            $codexLines += 'codex login --device-auth   # ChatGPT device code; covers the codex CLI only'
        }
        $codexLines += 'pwsh scripts/bootstrap/set-provider-secrets.ps1 -Only openai-api-key -Apply   # masked prompt -> Key Vault -> OPENAI_API_KEY (openai / openai-codex API providers)'
        # The doctor's raw line for this lane is the load step, which the item already
        # carries (store, then load) — appending it would print the load twice.
        Add-Item -Title 'Codex / OpenAI lane' -Lines $codexLines
        Set-Covered (Get-RawAction 'openai-codex')
    }
    if (Test-NeedsOwner 'claude') {
        $claudeLines = @(
            'claude setup-token   # long-lived CLI token; owner-only, never probed headlessly',
            'pwsh scripts/bootstrap/set-provider-secrets.ps1 -Only anthropic-api-key -Apply   # -> Key Vault -> ANTHROPIC_API_KEY (anthropic provider)')
        $claudeLines = Add-RawLine -Lines $claudeLines -Raw (Get-RawAction 'claude')
        Add-Item -Title 'Claude lane' -Lines $claudeLines
        Set-Covered (Get-RawAction 'claude')
    }
    if (Test-NeedsOwner 'copilot') {
        $copilotRaw = Get-RawAction 'copilot'
        Add-Item -Title 'Copilot lane (rides the GitHub login)' -Lines @($(if ($copilotRaw) { $copilotRaw } else { $ghLogin }))
        Set-Covered $copilotRaw
    }
    # With the vault already wired the load step has no wiring item to ride on; it is
    # still the step that turns stored values into THIS session's variables, so it is
    # printed once here and never a second time from the harvested tail.
    if (-not [string]::IsNullOrWhiteSpace($env:AZURE_KEY_VAULT_URI) -and ((Test-NeedsOwner 'openai-codex') -or (Test-NeedsOwner 'claude'))) {
        Add-Item -Title 'Load the vault keys into this session (after storing them)' -Lines ([string[]]@($loadLines))
        Set-CoveredLoadActions
    }

    # --- repository secrets: driven by the repo's own state, not the local keyring ---
    $adminState = Get-RepoSecretState 'HELIOS_ADMIN_TOKEN'
    if ($adminState -ne 'present') {
        Add-Item -Title ("HELIOS_ADMIN_TOKEN repo secret ($adminState) — owner PAT for governance-apply.yml admin writes (fine-grained: " +
            'Administration, Contents, Issues, Pull requests, Pages RW + Metadata R; permission list in the .github/workflows/governance-apply.yml header)') -Lines @(
            'gh secret set HELIOS_ADMIN_TOKEN   # paste when prompted; the value never touches argv',
            '$env:HELIOS_ADMIN_TOKEN = Read-Host -MaskInput   # or: typed hidden (PowerShell 7.1+), never on argv or in history, then:',
            "$provisionApply   # feeds every set target to gh secret set over stdin")
    }
    foreach ($pair in @(@{ Lane = 'linear'; Env = 'LINEAR_API_KEY' }, @{ Lane = 'slack'; Env = 'SLACK_WEBHOOK_URL' })) {
        $secretState = Get-RepoSecretState $pair.Env
        if (-not (Test-NeedsOwner $pair.Lane) -and $secretState -eq 'present') { continue }
        $raw = Get-RawAction $pair.Lane
        Add-Item -Title ($pair.Lane + ' connector secret (repo secret ' + $secretState + ')') -Lines @(
            $(if ($raw) { $raw } else { 'gh secret set ' + $pair.Env }),
            ('$env:{0} = Read-Host -MaskInput   # or: typed hidden (PowerShell 7.1+), never on argv or in history, then:' -f $pair.Env),
            "$provisionApply   # feeds every set target to gh secret set over stdin")
        Set-Covered $raw
    }

    # --- everything else the doctor flagged, tooling, then the harvested tail ---
    foreach ($name in @($lanes.Keys)) {
        $raw = Get-RawAction $name
        if ((Get-LaneState $name) -eq 'needs-owner' -and $raw -and -not (Test-Covered $raw)) {
            Add-Item -Title ($name + ' lane') -Lines @($raw)
            Set-Covered $raw
        }
    }
    $setupStep = @($steps | Where-Object { $_.name -eq 'cloud-shell-setup' } | Select-Object -First 1)
    $bashMissing = ($setupStep.Count -gt 0 -and $setupStep[0].exitCode -eq 2)
    if ($bashMissing -or @($steps | Where-Object { $_.exitCode -eq 127 }).Count -gt 0) {
        Add-Item -Title 'Install the missing shell tooling (a step could not run)' -Lines @(
            '# bash for step 1 (Git Bash on Windows; Cloud Shell ships it), PowerShell 7 for steps 2-6 (https://aka.ms/powershell); then re-run: pwsh scripts/bootstrap/first-run.ps1')
    }
    foreach ($action in $ownerActions) {
        if (-not (Test-Covered $action.action)) {
            Add-Item -Title ('reported by ' + $action.lane) -Lines @($action.action)
            Set-Covered $action.action
        }
    }

    $state = [ordered]@{
        generatedUtc = (Get-Date).ToUniversalTime().ToString('o')
        environment  = $environment
        verifyOnly   = [bool]$VerifyOnly
        steps        = @($steps)
        lanes        = $lanes
        repoSecrets  = $repoSecrets
        ownerActions = @($ownerActions)
        checklist    = @($items | ForEach-Object { [ordered]@{ title = $_.Title; lines = @($_.Lines) } })
        reports      = $reportPaths
    }
    $stateJson = $state | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($stateFile, $stateJson + "`n")

    if ($Json) {
        $stateJson
        exit $(if ($internalFailure) { 1 } else { 0 })
    }

    Write-Report ''
    Write-Report '== Steps =='
    foreach ($step in $steps) {
        if ($step.exitCode -eq -1) {
            Write-Report ('   {0,-26} {1}   ({2})' -f $step.name, $(if ($step.Contains('note')) { $step.note } else { 'skipped' }), $step.script)
        }
        else {
            Write-Report ('   {0,-26} exit {1,-3} {2}   ({3})' -f $step.name, $step.exitCode, $(if ($step.ok) { 'ok ' } else { 'not clean' }), $step.script)
        }
    }
    Write-Report ''
    Write-Report '== Lanes (auth-doctor + rest-connect) =='
    if ($lanes.Count -eq 0) { Write-Report '   none captured — read .helios/bootstrap/*.json and .helios/bootstrap/first-run.log' }
    foreach ($name in @($lanes.Keys)) {
        $lane = $lanes[$name]
        $via = if ($lane.Contains('method')) { $lane['method'] } elseif ($lane.Contains('source')) { $lane['source'] } else { '' }
        Write-Report ('   {0,-14} {1,-12} {2}' -f $name, $(if ($lane.Contains('state')) { $lane['state'] } else { '?' }), $via)
    }
    Write-Report ''
    Write-Report '== Repository secrets / variables (provision-github-secrets, by name) =='
    if ($repoSecrets.Count -eq 0) { Write-Report '   none captured — provision-github-secrets.ps1 produced no report (see the Steps table)' }
    foreach ($name in @($repoSecrets.Keys)) { Write-Report ('   {0,-24} {1}' -f $name, $repoSecrets[$name]) }
    Write-Report ''
    Write-Report '== Remaining human steps =='
    if ($items.Count -eq 0) { Write-Report '   none — every lane is ready; nothing is waiting on the owner.' }
    $index = 0
    foreach ($item in $items) {
        $index++
        Write-Report ('  {0}. {1}' -f $index, $item.Title)
        foreach ($line in $item.Lines) { Write-Report ('       ' + $line) }
    }
    Write-Report ''
    Write-Report 'Account creation and MFA cannot be automated: every login above needs the owner''s own browser session and second factor; this script only prepares and verifies.'
    Write-Report 'State written: .helios/bootstrap-state.json (raw reports: .helios/bootstrap/*.json)'

    if ($internalFailure) {
        [Console]::Error.WriteLine('first-run: internal failure — no PowerShell 7 executable could be resolved for the child steps; the checklist names the install.')
        exit 1
    }
    exit 0
}
catch {
    [Console]::Error.WriteLine("first-run: internal failure — $($_.Exception.Message)")
    exit 1
}
