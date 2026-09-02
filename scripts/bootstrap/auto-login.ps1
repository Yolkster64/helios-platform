#Requires -Version 7
<#
.SYNOPSIS
One-command NON-INTERACTIVE auto-login: repair every credential lane that can be
repaired without a human, then export the provider keys the whole stack consumes into
the CURRENT PowerShell session — az, gh, codex (OpenAI), claude (Anthropic),
gh-models, and every SDK/REST consumer that reads the same env names. Zero prompts,
ever: anything that would need a browser or MFA is reported as an owner action, never
started.

.DESCRIPTION
The ACQUIRE-and-EXPORT companion of the report-only diagnostics
(scripts/bootstrap/auth-doctor.ps1 reports; scripts/verify/rest-connect.ps1 probes the
wire). This script deliberately MUTATES, in two well-defined places only:

  1. The az CLI profile — by delegating to `auth-doctor.ps1 -Apply`, whose contract is
     automatic NON-INTERACTIVE repair only (service principal from AZURE_CLIENT_ID/
     AZURE_TENANT_ID + secret/certificate, or managed identity). Nothing interactive
     is ever run; an MFA/device-code fix is only ever printed.
  2. This session's environment variables — Key Vault secrets are exported into the
     exact env names config/aihub.json declares, and a gh-derived token can light the
     gh-models lane. Values land ONLY in process memory ($env:*), never on disk,
     never in output.

DOT-SOURCE IT so the exports outlive the script:

    . scripts/bootstrap/auto-login.ps1

Run normally it still works, but the exports die with the child process — the summary
tells you which invocation you used.

Chain (reuse-first — this script orchestrates, it does not reimplement):
  az lane        pwsh scripts/bootstrap/auth-doctor.ps1 -Apply -Json  → repaired/ready
                 or needs-owner (the one-time `az login --tenant ...` MFA +
                 setup-tenant.ps1 -OpsIdentity permanence path is printed verbatim).
  Key Vault      only when the az lane is usable AND AZURE_KEY_VAULT_URI is set (the
                 vault provisioned by infra/main.bicep): openai-api-key →
                 OPENAI_API_KEY (codex CLI + openai providers/SDKs), anthropic-api-key
                 → ANTHROPIC_API_KEY (claude CLI + anthropic provider),
                 github-models-token → GITHUB_MODELS_TOKEN (gh-models provider).
                 Same secret names as scripts/bootstrap/load-env-from-keyvault.sh
                 (the bash twin). Existing env values are NEVER clobbered.
  gh-models      when GITHUB_MODELS_TOKEN is still unset and `gh auth token` yields a
                 token, export it (the connect-github.sh sourcing behavior, in pwsh).
  summary        which env NAMES were set this run, which lanes remain owner-gated.

Secrets policy (CLAUDE.md rule): secret values flow az → local variable → $env:NAME
and die there; no value is ever printed, logged, or written to a file. Names only in
every report line.

.PARAMETER Json
Emit one machine-readable rollup {script, generatedUtc, dotSourced, steps[],
exportedNames[], ownerActions[], exitCode} instead of the human report.

Exit contract: 0 = ran to completion (owner-gated lanes are reported, not failures);
1 = internal failure. Dot-sourced, the exit code is not asserted (exiting would kill
the caller's shell) — read the summary instead.
#>
[CmdletBinding()]
param(
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir '..' '..')
# Dot-sourced => $MyInvocation.InvocationName is '.', and exports persist for the caller.
$dotSourced = $MyInvocation.InvocationName -eq '.'

$steps = [System.Collections.Generic.List[object]]::new()
$exportedNames = [System.Collections.Generic.List[string]]::new()
$ownerActions = [System.Collections.Generic.List[string]]::new()

function Write-Report {
    param([string]$Line = '')
    if (-not $Json) { Write-Host $Line }
}

function Add-Step {
    param(
        [Parameter(Mandatory)][string]$Step,
        [Parameter(Mandatory)][ValidateSet('ok', 'exported', 'skipped', 'needs-owner', 'unavailable')][string]$State,
        [Parameter(Mandatory)][string]$Detail
    )
    $steps.Add([pscustomobject]@{ step = $Step; state = $State; detail = $Detail })
    Write-Report ('  {0,-14} {1,-12} {2}' -f $Step, $State, $Detail)
}

try {
    Write-Report '== HELIOS auto-login (non-interactive acquire + export; zero prompts) =='
    if (-not $dotSourced) {
        Write-Report '   NOTE: not dot-sourced — env exports die with this process. For your shell:  . scripts/bootstrap/auto-login.ps1'
    }
    Write-Report ''

    # --- 1. az lane: delegate repair to auth-doctor -Apply (non-interactive only) ----
    $azUsable = $false
    $doctorPath = Join-Path $repoRoot 'scripts/bootstrap/auth-doctor.ps1'
    if (Test-Path -LiteralPath $doctorPath) {
        $doctorLines = @(& pwsh -NoProfile -File $doctorPath -Apply -Json 2>&1 | ForEach-Object { "$_" })
        $doctorExit = [int]$LASTEXITCODE
        $doctorReport = $null
        try { $doctorReport = ($doctorLines -join "`n") | ConvertFrom-Json } catch { }
        $azLane = $null
        if ($doctorReport -and $doctorReport.PSObject.Properties['lanes']) {
            $azLane = @($doctorReport.lanes | Where-Object { $_.lane -eq 'az' }) | Select-Object -First 1
        }
        if ($null -ne $azLane) {
            $azState = [string]$azLane.state
            $azUsable = $azState -in @('ready', 'repaired')
            $azDetail = "auth-doctor -Apply: az lane $azState"
            if (-not $azUsable -and $azLane.PSObject.Properties['ownerAction'] -and "$($azLane.ownerAction)".Trim()) {
                $ownerActions.Add("$($azLane.ownerAction)".Trim())
            }
            Add-Step -Step 'az' -State $(if ($azUsable) { 'ok' } else { 'needs-owner' }) -Detail $azDetail
            # Surface the rest of the doctor's owner actions too — auto-login's summary
            # is meant to be the single list of what still needs a human.
            foreach ($lane in @($doctorReport.lanes)) {
                if ($lane.lane -ne 'az' -and $lane.PSObject.Properties['ownerAction'] -and "$($lane.ownerAction)".Trim()) {
                    $ownerActions.Add("$($lane.ownerAction)".Trim())
                }
            }
        }
        else {
            Add-Step -Step 'az' -State 'unavailable' -Detail "auth-doctor -Apply produced no parseable az lane (exit $doctorExit) — az repair state unknown"
        }
    }
    else {
        Add-Step -Step 'az' -State 'unavailable' -Detail 'scripts/bootstrap/auth-doctor.ps1 not found in this checkout'
    }

    # --- 2. Key Vault → env (the pwsh twin of load-env-from-keyvault.sh) ------------
    # Secret NAME → env NAME, exactly the pairs the bash twin and config/aihub.json use.
    $vaultPairs = @(
        [pscustomobject]@{ Secret = 'openai-api-key'; Env = 'OPENAI_API_KEY'; Lights = 'codex CLI + openai/azure-openai SDK & providers' }
        [pscustomobject]@{ Secret = 'anthropic-api-key'; Env = 'ANTHROPIC_API_KEY'; Lights = 'claude CLI + anthropic provider' }
        [pscustomobject]@{ Secret = 'github-models-token'; Env = 'GITHUB_MODELS_TOKEN'; Lights = 'gh-models provider' }
    )
    $vaultUri = if (Test-Path env:AZURE_KEY_VAULT_URI) { ([string]$env:AZURE_KEY_VAULT_URI).Trim() } else { '' }
    $azCmd = Get-Command az -ErrorAction SilentlyContinue
    if (-not $azUsable) {
        Add-Step -Step 'keyvault' -State 'skipped' -Detail 'az lane is not usable — Key Vault pulls need an authenticated az (see owner actions)'
    }
    elseif (-not $vaultUri) {
        Add-Step -Step 'keyvault' -State 'skipped' -Detail 'AZURE_KEY_VAULT_URI is not set (name checked only) — provisioned by infra/main.bicep; azure-up.sh writes it into .helios/azure.env'
        $ownerActions.Add('source .helios/azure.env (or export AZURE_KEY_VAULT_URI) so auto-login can pull provider keys from Key Vault')
    }
    elseif (-not $azCmd) {
        Add-Step -Step 'keyvault' -State 'unavailable' -Detail 'az CLI not on PATH'
    }
    else {
        $vaultName = ([uri]$vaultUri).Host.Split('.')[0]
        foreach ($pair in $vaultPairs) {
            if (Test-Path "env:$($pair.Env)") {
                Add-Step -Step $pair.Env -State 'skipped' -Detail 'already set in this session — never clobbered'
                continue
            }
            # Value: az stdout → local → $env:NAME. It is never interpolated anywhere.
            $secretValue = ''
            $secretLines = @(& $azCmd.Source keyvault secret show --vault-name $vaultName --name $pair.Secret --query value --output tsv --only-show-errors 2>$null)
            $secretExit = [int]$LASTEXITCODE
            if ($secretExit -eq 0) { $secretValue = (@($secretLines) -join '').Trim() }
            if ($secretValue) {
                Set-Item -Path "env:$($pair.Env)" -Value $secretValue
                $secretValue = ''
                $exportedNames.Add($pair.Env)
                Add-Step -Step $pair.Env -State 'exported' -Detail "from Key Vault secret '$($pair.Secret)' — lights: $($pair.Lights)"
            }
            else {
                Add-Step -Step $pair.Env -State 'skipped' -Detail "Key Vault secret '$($pair.Secret)' not readable (missing, empty, or no RBAC grant) — value state not probed further"
            }
        }
    }

    # --- 3. gh-models from the gh CLI (connect-github.sh sourcing behavior) ----------
    if (-not (Test-Path env:GITHUB_MODELS_TOKEN)) {
        $ghCmd = Get-Command gh -ErrorAction SilentlyContinue
        if ($ghCmd) {
            $ghLines = @(& $ghCmd.Source auth token 2>$null)
            $ghExit = [int]$LASTEXITCODE
            $ghToken = (@($ghLines) -join '').Trim()
            if ($ghExit -eq 0 -and $ghToken) {
                $env:GITHUB_MODELS_TOKEN = $ghToken
                $ghToken = ''
                $exportedNames.Add('GITHUB_MODELS_TOKEN')
                Add-Step -Step 'GITHUB_MODELS_TOKEN' -State 'exported' -Detail 'from `gh auth token` — lights: gh-models provider'
            }
            else {
                Add-Step -Step 'GITHUB_MODELS_TOKEN' -State 'skipped' -Detail 'gh CLI yielded no token (logged out or unavailable) and Key Vault did not provide one'
            }
        }
    }

    $uniqueOwnerActions = @($ownerActions | Select-Object -Unique)

    Write-Report ''
    if ($exportedNames.Count -gt 0) {
        Write-Report ('Exported this run (names only): ' + (@($exportedNames) -join ', '))
        if (-not $dotSourced) { Write-Report 'These exports died with this process — dot-source the script to keep them.' }
    }
    else {
        Write-Report 'Nothing newly exported this run.'
    }
    if ($uniqueOwnerActions.Count -gt 0) {
        Write-Report ''
        Write-Report '== OWNER ACTIONS (the only steps that need a human) =='
        $i = 0
        foreach ($action in $uniqueOwnerActions) { $i++; Write-Report ('  {0}. {1}' -f $i, $action) }
    }

    if ($Json) {
        [ordered]@{
            script        = 'scripts/bootstrap/auto-login.ps1'
            generatedUtc  = (Get-Date).ToUniversalTime().ToString('o')
            dotSourced    = $dotSourced
            steps         = @($steps)
            exportedNames = @($exportedNames)
            ownerActions  = @($uniqueOwnerActions)
            exitCode      = 0
        } | ConvertTo-Json -Depth 4
    }
    if (-not $dotSourced) { exit 0 }
}
catch {
    [Console]::Error.WriteLine("auto-login: internal failure: $($_.Exception.Message)")
    if (-not $dotSourced) { exit 1 }
}
