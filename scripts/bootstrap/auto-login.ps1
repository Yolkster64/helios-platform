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
tells you which invocation you used. The whole implementation runs inside a function
scope, so dot-sourcing does NOT change the caller's StrictMode or
$ErrorActionPreference (review finding); on an internal failure a dot-sourced run
RETHROWS so the caller can detect the partial setup, while a normal run exits 1.

Chain (reuse-first — this script orchestrates, it does not reimplement):
  az lane        pwsh scripts/bootstrap/auth-doctor.ps1 -Apply -Json  → repaired/ready
                 or needs-owner (the one-time `az login --tenant ...` MFA +
                 setup-tenant.ps1 -OpsIdentity permanence path is printed verbatim).
  Key Vault      only when the az lane is usable AND AZURE_KEY_VAULT_URI holds a real
                 value (the vault provisioned by infra/main.bicep): openai-api-key →
                 OPENAI_API_KEY (codex CLI + openai providers/SDKs), anthropic-api-key
                 → ANTHROPIC_API_KEY (claude CLI + anthropic provider),
                 github-models-token → GITHUB_MODELS_TOKEN (gh-models provider).
                 Same secret names as scripts/bootstrap/load-env-from-keyvault.sh
                 (the bash twin). Env vars carrying a NON-EMPTY value are never
                 clobbered; an empty/whitespace value counts as unset (review
                 finding — matching the bash twin's nonempty rule).
  gh-models      when GITHUB_MODELS_TOKEN is still effectively unset and
                 `gh auth token` yields a token, export it (the connect-github.sh
                 sourcing behavior, in pwsh). The models:read scope CANNOT be
                 verified here when `gh auth status` is unusable, so the step says
                 so and prints the refresh command to run if model calls 403.
  summary        which env NAMES were set this run, which lanes remain owner-gated.

Secrets policy (CLAUDE.md rule): secret values flow az → local variable → $env:NAME
and die there; no value is ever printed, logged, or written to a file. Names only in
every report line.

.PARAMETER Json
Emit one machine-readable rollup {script, generatedUtc, dotSourced, steps[],
exportedNames[], ownerActions[], exitCode} instead of the human report.

Exit contract: 0 = ran to completion (owner-gated lanes are reported, not failures);
1 = internal failure. Dot-sourced, exit codes are not asserted (exiting would kill
the caller's shell): completion is silent success and an internal failure RETHROWS.
#>
[CmdletBinding()]
param(
    [switch]$Json
)

# Everything lives in this function so StrictMode and ErrorActionPreference are
# FUNCTION-scoped: dot-sourcing the script must never rewrite the caller's shell
# preferences (review finding). Environment exports are process-wide, so they still
# reach the dot-sourcing caller.
function Invoke-HeliosAutoLogin {
    param(
        [switch]$Json,
        [bool]$DotSourced,
        [Parameter(Mandatory)][string]$RepoRoot
    )
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

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

    # Empty or whitespace counts as unset (review finding): CI shells commonly define
    # variables as '' — the bash twin (load-env-from-keyvault.sh) preserves only
    # nonempty values, and this script matches that rule everywhere.
    function Test-EnvValue {
        param([Parameter(Mandatory)][string]$Name)
        if (-not (Test-Path "env:$Name")) { return $false }
        return -not [string]::IsNullOrWhiteSpace([string](Get-Item "env:$Name").Value)
    }

    Write-Report '== HELIOS auto-login (non-interactive acquire + export; zero prompts) =='
    if (-not $DotSourced) {
        Write-Report '   NOTE: not dot-sourced — env exports die with this process. For your shell:  . scripts/bootstrap/auto-login.ps1'
    }
    Write-Report ''

    # --- 1. az lane: delegate repair to auth-doctor -Apply (non-interactive only) ----
    $azUsable = $false
    $doctorPath = Join-Path $RepoRoot 'scripts/bootstrap/auth-doctor.ps1'
    if (Test-Path -LiteralPath $doctorPath) {
        # stdout ONLY: the -Json contract puts the report there, and merging stderr
        # (warnings, progress lines) would break the JSON parse (review finding —
        # the same lesson learn-fleet.ps1's capture already encodes).
        $doctorLines = @(& pwsh -NoProfile -File $doctorPath -Apply -Json 2>$null | ForEach-Object { "$_" })
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
            # Carry the doctor's own detail through (review finding): 'unavailable'
            # means az is not installed — collapsing that to needs-owner with a bare
            # state name loses the installation guidance for both humans and JSON.
            $azLaneDetail = if ($azLane.PSObject.Properties['detail']) { [string]$azLane.detail } else { '' }
            $azDetail = "auth-doctor -Apply: az lane $azState" +
                $(if ($azLaneDetail) { " — $azLaneDetail" } else { '' })
            $azStepState = if ($azUsable) { 'ok' } elseif ($azState -eq 'unavailable') { 'unavailable' } else { 'needs-owner' }
            if (-not $azUsable -and $azLane.PSObject.Properties['ownerAction'] -and "$($azLane.ownerAction)".Trim()) {
                $ownerActions.Add("$($azLane.ownerAction)".Trim())
            }
            Add-Step -Step 'az' -State $azStepState -Detail $azDetail
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
    # SecretName is a Key Vault secret IDENTIFIER (which secret to fetch), never a
    # value — named so the code-checks security scanner's hardcoded-secret pattern
    # (`secret =` followed by a literal) does not false-positive on identifiers.
    $vaultPairs = @(
        # Lights lists the PUBLIC OpenAI lanes only (review finding): the
        # azure-openai provider needs AZURE_OPENAI_ENDPOINT + AZURE_OPENAI_API_KEY
        # and stays Unconfigured without them — this key does not light it.
        [pscustomobject]@{ SecretName = 'openai-api-key'; Env = 'OPENAI_API_KEY'; Lights = 'codex CLI + openai/openai-codex providers & SDKs' }
        [pscustomobject]@{ SecretName = 'anthropic-api-key'; Env = 'ANTHROPIC_API_KEY'; Lights = 'claude CLI + anthropic provider' }
        [pscustomobject]@{ SecretName = 'github-models-token'; Env = 'GITHUB_MODELS_TOKEN'; Lights = 'gh-models provider' }
    )
    $vaultUri = if (Test-EnvValue 'AZURE_KEY_VAULT_URI') { ([string]$env:AZURE_KEY_VAULT_URI).Trim() } else { '' }
    # -CommandType Application (review finding): a dot-sourcing caller may carry an
    # `az` alias/function whose .Source is not an invocable path — resolve the real
    # executable only, as the verifier and auth doctor do.
    $azCmd = Get-Command az -CommandType Application -ErrorAction SilentlyContinue
    if (-not $azUsable) {
        Add-Step -Step 'keyvault' -State 'skipped' -Detail 'az lane is not usable — Key Vault pulls need an authenticated az (see owner actions)'
    }
    elseif (-not $vaultUri) {
        Add-Step -Step 'keyvault' -State 'skipped' -Detail ('AZURE_KEY_VAULT_URI is not set (name checked only) — provisioned by infra/main.bicep; ' +
            'azure-up.sh writes .helios/azure.env (bash) and azure-up.ps1 writes .helios/azure.env.ps1 (PowerShell)')
        # Both shells get a working remediation (review finding): this script is
        # dot-sourced from PowerShell, where bash `source`/`export` do nothing.
        $ownerActions.Add('set AZURE_KEY_VAULT_URI so auto-login can pull provider keys — PowerShell: . .helios/azure.env.ps1 (or $env:AZURE_KEY_VAULT_URI = "https://<vault>.vault.azure.net/"); bash: source .helios/azure.env')
    }
    elseif (-not $azCmd) {
        Add-Step -Step 'keyvault' -State 'unavailable' -Detail 'az CLI not on PATH'
    }
    else {
        # A malformed AZURE_KEY_VAULT_URI is a configuration problem, not an internal
        # failure — the [uri] cast throws on scheme-less/garbage values (review
        # finding), so it is guarded into a skipped step instead of aborting the run.
        $vaultName = ''
        try { $vaultName = ([uri]$vaultUri).Host.Split('.')[0] } catch { }
        if (-not $vaultName) {
            Add-Step -Step 'keyvault' -State 'skipped' -Detail 'AZURE_KEY_VAULT_URI is set but does not parse as a URI (expected https://<vault>.vault.azure.net/) — fix the value; nothing was pulled'
            $ownerActions.Add('fix AZURE_KEY_VAULT_URI: it is set but not a parseable https://<vault>.vault.azure.net/ URI')
        }
        else {
            # Identity pinning (review finding): auth-doctor -Apply returns ready on
            # ANY healthy cached az login before reaching its service-principal
            # repair, so a developer login can mask the configured workload identity —
            # and the developer may lack the vault's RBAC grant that the ops service
            # principal holds. The cached identity is an identifier, never a secret:
            # detect the mismatch up front, and if a pull then fails, report the
            # exact non-interactive switch command instead of a generic RBAC shrug.
            $cachedAzIdentity = ''
            $azIdentityMismatch = $false
            if (Test-EnvValue 'AZURE_CLIENT_ID') {
                $acctLines = @(& $azCmd.Source account show --query user.name --output tsv --only-show-errors 2>$null)
                if ([int]$LASTEXITCODE -eq 0) { $cachedAzIdentity = (@($acctLines) -join '').Trim() }
                if ($cachedAzIdentity -and $cachedAzIdentity -ne ([string]$env:AZURE_CLIENT_ID).Trim()) {
                    $azIdentityMismatch = $true
                    Add-Step -Step 'az-identity' -State 'ok' -Detail ("cached az login is '$cachedAzIdentity', not the configured AZURE_CLIENT_ID workload identity — vault pulls proceed under the cached identity, whose Key Vault RBAC may differ")
                }
            }
            $anyPullFailed = $false
            foreach ($pair in $vaultPairs) {
                if (Test-EnvValue $pair.Env) {
                    Add-Step -Step $pair.Env -State 'skipped' -Detail 'already holds a value in this session — never clobbered'
                    continue
                }
                # Value: az stdout → local → $env:NAME. It is never interpolated anywhere.
                $secretValue = ''
                $secretLines = @(& $azCmd.Source keyvault secret show --vault-name $vaultName --name $pair.SecretName --query value --output tsv --only-show-errors 2>$null)
                $secretExit = [int]$LASTEXITCODE
                if ($secretExit -eq 0) { $secretValue = (@($secretLines) -join '').Trim() }
                if ($secretValue) {
                    Set-Item -Path "env:$($pair.Env)" -Value $secretValue
                    $secretValue = ''
                    $exportedNames.Add($pair.Env)
                    Add-Step -Step $pair.Env -State 'exported' -Detail "from Key Vault secret '$($pair.SecretName)' — lights: $($pair.Lights)"
                }
                else {
                    Add-Step -Step $pair.Env -State 'skipped' -Detail "Key Vault secret '$($pair.SecretName)' not readable (missing, empty, or no RBAC grant) — value state not probed further"
                    $anyPullFailed = $true
                }
            }
            if ($anyPullFailed -and $azIdentityMismatch) {
                # The switch is fully non-interactive — the operator (or automation)
                # just has to run it; auto-login itself only mutates the az profile
                # through auth-doctor -Apply, which stops at the first healthy cache.
                $ownerActions.Add('Key Vault pull failed under the cached az identity while AZURE_CLIENT_ID declares a workload identity — switch non-interactively: az login --service-principal --username $env:AZURE_CLIENT_ID --tenant $env:AZURE_TENANT_ID --password $env:AZURE_CLIENT_SECRET (or --certificate $env:AZURE_CLIENT_CERTIFICATE_PATH), then re-run auto-login')
            }
        }
    }

    # --- 3. gh-models from the gh CLI (connect-github.sh sourcing behavior) ----------
    if (-not (Test-EnvValue 'GITHUB_MODELS_TOKEN')) {
        $ghCmd = Get-Command gh -CommandType Application -ErrorAction SilentlyContinue
        if (-not $ghCmd) {
            # Record the lane even when gh is absent — an unevaluated-looking steps
            # list is ambiguous (review finding).
            Add-Step -Step 'GITHUB_MODELS_TOKEN' -State 'unavailable' -Detail 'gh CLI not on PATH and Key Vault did not provide the token'
        }
        else {
            # --hostname github.com (review finding): never export a GitHub
            # Enterprise credential (GH_HOST context) into the github.com models lane.
            $ghLines = @(& $ghCmd.Source auth token --hostname github.com 2>$null)
            $ghExit = [int]$LASTEXITCODE
            $ghToken = (@($ghLines) -join '').Trim()
            if ($ghExit -eq 0 -and $ghToken) {
                $env:GITHUB_MODELS_TOKEN = $ghToken
                $ghToken = ''
                $exportedNames.Add('GITHUB_MODELS_TOKEN')
                # Scope honesty (review finding): connect-github.sh verifies the
                # models:read scope, but that check needs a usable `gh auth status`,
                # which this environment may not have — so the export is made with
                # the caveat stated instead of a silent claim of usability.
                Add-Step -Step 'GITHUB_MODELS_TOKEN' -State 'exported' `
                    -Detail ('from `gh auth token` — lights: gh-models provider IF the token carries models:read ' +
                        '(not verifiable here); if model calls 403: gh auth refresh -h github.com --scopes models:read')
            }
            else {
                Add-Step -Step 'GITHUB_MODELS_TOKEN' -State 'skipped' -Detail 'gh CLI yielded no token (logged out or unavailable) and Key Vault did not provide one'
            }
        }
    }

    # Owner actions were collected BEFORE the export steps ran (review finding): the
    # auth-doctor's provider-lane actions say things like "pull openai-api-key into
    # OPENAI_API_KEY" — and when the Key Vault or gh rung supplies that exact env var
    # later in this same run, the pre-export action is already satisfied. The
    # summary's contract is "the only steps that need a human", so any action naming
    # a provider env var that NOW holds a value is dropped, with the drop reported.
    $exportResolvableEnvNames = @('OPENAI_API_KEY', 'ANTHROPIC_API_KEY', 'GITHUB_MODELS_TOKEN')
    $resolvedActionCount = 0
    $remainingOwnerActions = [System.Collections.Generic.List[string]]::new()
    foreach ($action in $ownerActions) {
        $resolvedByExport = $false
        foreach ($name in $exportResolvableEnvNames) {
            if ($action.Contains($name) -and (Test-EnvValue $name)) { $resolvedByExport = $true; break }
        }
        if ($resolvedByExport) { $resolvedActionCount++ } else { $remainingOwnerActions.Add($action) }
    }
    $uniqueOwnerActions = @($remainingOwnerActions | Select-Object -Unique)

    Write-Report ''
    if ($resolvedActionCount -gt 0) {
        Write-Report ("{0} pre-export owner action(s) dropped — the provider env var each referenced was satisfied later in this run" -f $resolvedActionCount)
    }
    if ($exportedNames.Count -gt 0) {
        Write-Report ('Exported this run (names only): ' + (@($exportedNames) -join ', '))
        if (-not $DotSourced) { Write-Report 'These exports died with this process — dot-source the script to keep them.' }
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
            dotSourced    = $DotSourced
            steps         = @($steps)
            exportedNames = @($exportedNames)
            ownerActions  = @($uniqueOwnerActions)
            exitCode      = 0
        } | ConvertTo-Json -Depth 4
    }
}

$autoLoginDotSourced = $MyInvocation.InvocationName -eq '.'
try {
    Invoke-HeliosAutoLogin -Json:$Json -DotSourced $autoLoginDotSourced -RepoRoot (Resolve-Path (Join-Path $PSScriptRoot '..' '..'))
    if (-not $autoLoginDotSourced) { exit 0 }
}
catch {
    [Console]::Error.WriteLine("auto-login: internal failure: $($_.Exception.Message)")
    # Dot-sourced: rethrow so the caller can DETECT the partial setup (review
    # finding) — exiting would kill their shell, and swallowing would fake success.
    if ($autoLoginDotSourced) { throw }
    exit 1
}
