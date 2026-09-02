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
Scope hygiene: the helper symbols are removed from the caller's scope on every
path; the one unavoidable residue is the -Json PARAMETER binding, which
overwrites (and cleanup then deletes) any caller variable named $Json/$json —
do not rely on that name surviving the call.

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
  gh-models      when GITHUB_MODELS_TOKEN is still effectively unset: a raw
                 GITHUB_TOKEN satisfies the provider only when the wire PROVES
                 models:read (X-OAuth-Scopes); otherwise `gh auth token` is read
                 env-cleared and probed the same way — a proven token is exported,
                 an unverifiable one (no scopes header, or an injecting transport)
                 is exported with the scope/vault repair left standing, and a token
                 proven to lack models:read (or rejected) is NOT exported at all.
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
    # Owner actions carry the env var whose satisfaction retires them (review
    # finding): Env = the exact variable for actions this script composes ('' for
    # actions no export can retire), $null for auth-doctor's imported free text,
    # whose variable is recovered by an exact-identifier match at reconcile time.
    $ownerActions = [System.Collections.Generic.List[object]]::new()
    function Add-OwnerAction {
        param([Parameter(Mandatory)][string]$Text, [AllowNull()][AllowEmptyString()][string]$Env = '', [switch]$Imported)
        $ownerActions.Add([pscustomobject]@{ Text = $Text.Trim(); Env = $(if ($Imported) { $null } else { [string]$Env }) })
    }

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
                Add-OwnerAction -Text "$($azLane.ownerAction)" -Imported
            }
            Add-Step -Step 'az' -State $azStepState -Detail $azDetail
            # Surface the rest of the doctor's owner actions too — auto-login's summary
            # is meant to be the single list of what still needs a human.
            foreach ($lane in @($doctorReport.lanes)) {
                if ($lane.lane -ne 'az' -and $lane.PSObject.Properties['ownerAction'] -and "$($lane.ownerAction)".Trim()) {
                    Add-OwnerAction -Text "$($lane.ownerAction)" -Imported
                }
            }
        }
        else {
            # An unparseable/failed auth-doctor is an INTERNAL failure, not a lane
            # state (review finding): converting it into an 'unavailable' step let
            # the run finish with exitCode 0 — a dot-sourced caller then continued
            # after a partial setup with neither the promised rethrow nor a
            # failure status. Throw so the outer handler propagates it.
            throw "auth-doctor -Apply produced no parseable az lane (exit $doctorExit) — az repair state unknown; aborting instead of reporting success"
        }
    }
    else {
        throw 'scripts/bootstrap/auth-doctor.ps1 not found in this checkout — the az lane cannot be established; aborting instead of reporting success'
    }

    # --- 2. Key Vault → env (the pwsh twin of load-env-from-keyvault.sh) ------------
    # SecretName is a Key Vault secret IDENTIFIER (which secret to fetch), never a
    # value — named so the code-checks security scanner's hardcoded-secret pattern
    # (`secret =` followed by a literal) does not false-positive on identifiers.
    # The pairs come from config/aihub.json (review finding): the hub's
    # SecretResolver honors each provider's apiKeyEnv/apiKeySecretName, so this
    # script reads the SAME source of truth — a hardcoded triplet would silently
    # stop configuring a provider the moment an operator renames its mapping.
    # Providers lacking either field are excluded on purpose (azure-openai, for
    # example, declares no vault custody and needs its own endpoint wiring).
    $vaultPairs = @()
    # AIHUB_CONFIG precedence (review finding): AIHubService.ResolveConfigPath gives
    # the env var precedence over the repo default, so when a custom/cloud profile
    # is selected these exports must follow it — otherwise auto-login configures a
    # hub other than the one that will actually run.
    $aihubConfigExplicit = Test-EnvValue 'AIHUB_CONFIG'
    $aihubConfigPath = if ($aihubConfigExplicit) { ([string]$env:AIHUB_CONFIG).Trim() }
    else { Join-Path $RepoRoot 'config/aihub.json' }
    $aihubProviders = $null
    try {
        $aihubParsed = Get-Content -LiteralPath $aihubConfigPath -Raw | ConvertFrom-Json
        if ($aihubParsed.PSObject.Properties['providers']) { $aihubProviders = $aihubParsed.providers }
    }
    catch { }
    # An EXPLICITLY selected profile that cannot be read is an internal failure
    # (review finding): the hub itself will fail to load that same file, so
    # silently exporting the built-in default mapping would configure a hub other
    # than the one selected — and report success doing it. The fallback below is
    # reserved for the absent/unreadable REPO DEFAULT only.
    if ($aihubConfigExplicit -and $null -eq $aihubProviders) {
        throw "AIHUB_CONFIG selects '$aihubConfigPath' but it is missing, unparseable, or has no providers section — fix the file or unset AIHUB_CONFIG; aborting instead of exporting the default profile's secrets"
    }
    if ($null -ne $aihubProviders) {
        $pairIndex = [ordered]@{}
        foreach ($provProp in $aihubProviders.PSObject.Properties) {
            $prov = $provProp.Value
            # ProviderFactory.CreateAll excludes disabled providers (review
            # finding): a lane the hub will not instantiate must not have its
            # credential pulled into the process.
            if ($prov.PSObject.Properties['enabled'] -and $prov.enabled -eq $false) { continue }
            $envName = ''
            $providerSecretName = ''
            if ($prov.PSObject.Properties['apiKeyEnv']) { $envName = [string]$prov.apiKeyEnv }
            if ($prov.PSObject.Properties['apiKeySecretName']) { $providerSecretName = [string]$prov.apiKeySecretName }
            if ([string]::IsNullOrWhiteSpace($envName) -or [string]::IsNullOrWhiteSpace($providerSecretName)) { continue }
            $pairKey = "$providerSecretName -> $envName"
            if (-not $pairIndex.Contains($pairKey)) {
                $pairIndex[$pairKey] = [pscustomobject]@{
                    SecretName = $providerSecretName
                    Env        = $envName
                    Consumers  = [System.Collections.Generic.List[string]]::new()
                }
            }
            $pairIndex[$pairKey].Consumers.Add($provProp.Name)
        }
        foreach ($entry in $pairIndex.Values) {
            # The agent CLIs read two of these env names directly — that fact is
            # not in config, so it rides along as a fixed hint.
            $cliHint = switch ($entry.Env) {
                'OPENAI_API_KEY' { ' + codex CLI' }
                'ANTHROPIC_API_KEY' { ' + claude CLI' }
                default { '' }
            }
            $vaultPairs += [pscustomobject]@{
                SecretName = $entry.SecretName
                Env        = $entry.Env
                Lights     = (($entry.Consumers -join ', ') + $cliHint + ' — per config/aihub.json')
            }
        }
    }
    if ($null -eq $aihubProviders -and @($vaultPairs).Count -eq 0) {
        # Stated fallback, never silent — and ONLY for an unreadable REPO DEFAULT
        # config (the explicit AIHUB_CONFIG case threw above). A config that
        # parsed fine but declares zero enabled vault-backed providers is a
        # deliberate profile (review finding): pulling the built-in triplet for it
        # would export credentials for lanes that hub will never instantiate.
        Write-Report '  note: config/aihub.json unreadable — falling back to the built-in secret/env mapping'
        $vaultPairs = @(
            [pscustomobject]@{ SecretName = 'openai-api-key'; Env = 'OPENAI_API_KEY'; Lights = 'codex CLI + openai/openai-codex providers & SDKs (fallback mapping)' }
            [pscustomobject]@{ SecretName = 'anthropic-api-key'; Env = 'ANTHROPIC_API_KEY'; Lights = 'claude CLI + anthropic provider (fallback mapping)' }
            [pscustomobject]@{ SecretName = 'github-models-token'; Env = 'GITHUB_MODELS_TOKEN'; Lights = 'gh-models provider (fallback mapping)' }
        )
    }
    elseif (@($vaultPairs).Count -eq 0) {
        Write-Report '  note: the active config declares no enabled vault-backed providers — nothing to pull from Key Vault'
    }
    # The gh-fallback's target env also follows the config (review finding):
    # ProviderFactory.CreateGitHubModels reads the CONFIGURED apiKeyEnv, so
    # exporting a hardcoded name would light nothing after a rename. A DISABLED
    # github-models provider disables the whole fallback (review finding): the
    # hub will not instantiate that lane, so no credential is fetched for it.
    $ghModelsEnv = 'GITHUB_MODELS_TOKEN'
    $ghModelsEnabled = $true
    # The vault-repair guidance follows the provider's apiKeySecretName the same way
    # (review finding): the config-driven pull reads ONLY that secret, so telling the
    # owner to store the default name under a customized config would advertise a
    # repair that can never light the lane. No apiKeySecretName at all means no
    # vault path exists for this provider, and the guidance omits it.
    $ghModelsSecretName = 'github-models-token'
    if ($null -ne $aihubProviders -and $aihubProviders.PSObject.Properties['github-models']) {
        $ghModelsProv = $aihubProviders.PSObject.Properties['github-models'].Value
        if ($ghModelsProv.PSObject.Properties['apiKeyEnv'] -and
            -not [string]::IsNullOrWhiteSpace([string]$ghModelsProv.apiKeyEnv)) {
            $ghModelsEnv = ([string]$ghModelsProv.apiKeyEnv).Trim()
        }
        $ghModelsSecretName = if ($ghModelsProv.PSObject.Properties['apiKeySecretName']) { ([string]$ghModelsProv.apiKeySecretName).Trim() } else { '' }
        if ($ghModelsProv.PSObject.Properties['enabled'] -and $ghModelsProv.enabled -eq $false) {
            $ghModelsEnabled = $false
        }
    }
    $ghModelsVaultClause = if ($ghModelsSecretName) { ", or store Key Vault secret '$ghModelsSecretName' (the configured github-models apiKeySecretName)" } else { '' }
    $vaultUri = if (Test-EnvValue 'AZURE_KEY_VAULT_URI') { ([string]$env:AZURE_KEY_VAULT_URI).Trim() } else { '' }
    # -CommandType Application (review finding): a dot-sourcing caller may carry an
    # `az` alias/function whose .Source is not an invocable path — resolve the real
    # executable only, as the verifier and auth doctor do.
    # First PATH hit only (see the gh lookup below for the duplicate-name failure).
    $azCmd = Get-Command az -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    # Unresolved pairs FIRST (review finding): when every configured provider env
    # already holds a value, or the profile declares no enabled vault-backed
    # providers, the vault stage has nothing to acquire — demanding a vault URI
    # (and adding a human action for it) would leave the "only steps that need
    # a human" list non-empty for an already-satisfied configuration.
    $unresolvedPairs = @($vaultPairs | Where-Object { -not (Test-EnvValue $_.Env) })
    if (@($unresolvedPairs).Count -eq 0) {
        $nothingToPullWhy = if (@($vaultPairs).Count -eq 0) { 'the active config declares no enabled vault-backed providers' }
        else { 'every configured provider env already holds a value in this session (never clobbered)' }
        Add-Step -Step 'keyvault' -State 'skipped' -Detail "$nothingToPullWhy — nothing to pull, vault prerequisite not required"
    }
    elseif (-not $azUsable) {
        Add-Step -Step 'keyvault' -State 'skipped' -Detail 'az lane is not usable — Key Vault pulls need an authenticated az (see owner actions)'
    }
    elseif (-not $vaultUri) {
        Add-Step -Step 'keyvault' -State 'skipped' -Detail ('AZURE_KEY_VAULT_URI is not set (name checked only) — provisioned by infra/main.bicep; ' +
            'azure-up.sh writes .helios/azure.env (bash) and azure-up.ps1 writes .helios/azure.env.ps1 (PowerShell)')
        # Both shells get a working remediation (review finding): this script is
        # dot-sourced from PowerShell, where bash `source`/`export` do nothing.
        Add-OwnerAction -Text 'set AZURE_KEY_VAULT_URI so auto-login can pull provider keys — PowerShell: . .helios/azure.env.ps1 (or $env:AZURE_KEY_VAULT_URI = "https://<vault>.vault.azure.net/"); bash: source .helios/azure.env'
    }
    elseif (-not $azCmd) {
        Add-Step -Step 'keyvault' -State 'unavailable' -Detail 'az CLI not on PATH'
    }
    else {
        # A malformed AZURE_KEY_VAULT_URI is a configuration problem, not an internal
        # failure — the [uri] cast throws on scheme-less/garbage values (review
        # finding), so it is guarded into a skipped step instead of aborting the run.
        # Strict shape too (review finding): any parseable https host used to pass,
        # so a stray value like https://example.com/ derived a vault named 'example',
        # ran az against it, and told the owner to populate the WRONG vault. Only
        # https plus a Key Vault hostname — <vault>.vault.<public or sovereign cloud
        # suffix> — derives a name; anything else is reported as the URI problem it is.
        $vaultName = ''
        $vaultUriParsed = $null
        try { $vaultUriParsed = [uri]$vaultUri } catch { }
        if ($null -ne $vaultUriParsed -and $vaultUriParsed.Scheme -eq 'https' -and
            $vaultUriParsed.Host -match '^(?<vault>[A-Za-z0-9-]{3,24})\.vault\.(azure\.net|azure\.cn|usgovcloudapi\.net|microsoftazure\.de)$') {
            $vaultName = $Matches['vault']
        }
        if (-not $vaultName) {
            Add-Step -Step 'keyvault' -State 'skipped' -Detail 'AZURE_KEY_VAULT_URI is set but is not an https://<vault>.vault.azure.net/ Key Vault URI (sovereign suffixes azure.cn, usgovcloudapi.net, microsoftazure.de also accepted) — fix the value; nothing was pulled and no vault was contacted'
            Add-OwnerAction -Text 'fix AZURE_KEY_VAULT_URI: it is set but is not an https://<vault>.vault.azure.net/ (or sovereign-cloud) Key Vault URI'
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
                    # A FAILED read is not a 'skipped' (review finding): 'skipped'
                    # is the intentional already-populated no-op, while this is an
                    # unresolved acquisition — JSON consumers must be able to tell
                    # them apart, and the run must leave an actionable remediation.
                    Add-Step -Step $pair.Env -State 'needs-owner' -Detail "Key Vault secret '$($pair.SecretName)' could not be read (missing, empty, no RBAC grant, or transient; az exited $secretExit) — the consumers it lights stay unconfigured"
                    # The action names the env var it lights (review finding): the
                    # post-export reconcile filter recognizes a resolved action only
                    # by that name, so a gh-fallback export can retire this one.
                    Add-OwnerAction -Env $pair.Env -Text "store or authorize Key Vault secret '$($pair.SecretName)' in vault '$vaultName' — az keyvault secret set --vault-name $vaultName --name $($pair.SecretName) (owner supplies the value), or grant the running identity 'Key Vault Secrets User'; then re-run auto-login (lights $($pair.Env))"
                    $anyPullFailed = $true
                }
            }
            if ($anyPullFailed -and $azIdentityMismatch) {
                # The switch is fully non-interactive — the operator (or automation)
                # just has to run it; auto-login itself only mutates the az profile
                # through auth-doctor -Apply, which stops at the first healthy cache.
                Add-OwnerAction -Text 'Key Vault pull failed under the cached az identity while AZURE_CLIENT_ID declares a workload identity — switch non-interactively: az login --service-principal --username $env:AZURE_CLIENT_ID --tenant $env:AZURE_TENANT_ID --password $env:AZURE_CLIENT_SECRET (or --certificate $env:AZURE_CLIENT_CERTIFICATE_PATH), then re-run auto-login'
            }
        }
    }

    # --- 3. gh-models from the gh CLI (connect-github.sh sourcing behavior) ----------
    # Target env is $ghModelsEnv — the github-models provider's CONFIGURED apiKeyEnv
    # (review finding), not a hardcoded name; a disabled provider skips the
    # fallback entirely.

    # models:read PROOF for a raw GITHUB_TOKEN (review finding): non-emptiness is
    # not usability — the github-models provider 403s on every call without
    # models:read (connect-github.sh and setup-all.ps1 both treat it as required).
    # Classic PATs expose their granted scopes in the X-OAuth-Scopes response
    # header; fine-grained/Actions tokens do not, and an injecting transport makes
    # per-token proof impossible (rest-connect.ps1 doctrine) — both read as
    # 'unverifiable', never a false 'proven'. The token value exists only in the
    # request header and is never printed.
    function Get-GitHubTokenModelsScope {
        param([Parameter(Mandatory)][string]$EnvName)
        $ghHeaders = @{ Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }
        try {
            $anon = Invoke-WebRequest -Uri 'https://api.github.com/rate_limit' -Headers $ghHeaders -TimeoutSec 20 -SkipHttpErrorCheck -UserAgent 'helios-auto-login'
            if ([int]$anon.StatusCode -eq 200) {
                $anonParsed = $null
                try { $anonParsed = $anon.Content | ConvertFrom-Json } catch { }
                $anonLimit = 0
                if ($null -ne $anonParsed -and $anonParsed.PSObject.Properties['rate'] -and
                    [int]::TryParse([string]$anonParsed.rate.limit, [ref]$anonLimit) -and $anonLimit -gt 60) {
                    return 'unverifiable'   # injecting transport: any token would look valid
                }
            }
            $authHeaders = $ghHeaders.Clone()
            $authHeaders['Authorization'] = "Bearer $([string](Get-Item "env:$EnvName").Value)"
            $resp = Invoke-WebRequest -Uri 'https://api.github.com/rate_limit' -Headers $authHeaders -TimeoutSec 20 -SkipHttpErrorCheck -UserAgent 'helios-auto-login'
            $authHeaders = $null
            if ([int]$resp.StatusCode -ne 200) { return 'invalid' }
            $scopeKey = @($resp.Headers.Keys | Where-Object { $_ -ieq 'X-OAuth-Scopes' }) | Select-Object -First 1
            $scopesText = if ($scopeKey) { (@($resp.Headers[$scopeKey]) -join ',') } else { '' }
            if ([string]::IsNullOrWhiteSpace($scopesText)) { return 'unverifiable' }
            if ($scopesText -match '(^|[,\s])models:read([,\s]|$)') { return 'proven' }
            return 'missing-scope'
        }
        catch { return 'unverifiable' }
    }

    # True only when a models:read PROOF exists for the credential feeding the
    # lane (a raw GITHUB_TOKEN or the gh-rung export) — the reconcile filter
    # retires the lane's scope/vault actions on this flag, never on mere presence.
    $ghModelsScopeProven = $false
    # True when the gh rung exported a token whose scope could not be verified:
    # that export is the best available credential, but it must not retire a
    # repair action (review finding) until a run proves it.
    $ghModelsUnprovenExport = $false
    $ghModelsRepairAction = "grant models:read to the GitHub credential feeding $ghModelsEnv — gh auth refresh -h github.com --scopes models:read, or a PAT that includes models:read$ghModelsVaultClause"
    $ghFallbackNeeded = $false
    if (-not $ghModelsEnabled) {
        Add-Step -Step $ghModelsEnv -State 'skipped' -Detail 'github-models provider is disabled in the active config — no token fetched or exported for a lane the hub will not instantiate'
    }
    elseif (-not (Test-EnvValue $ghModelsEnv) -and (Test-EnvValue 'GITHUB_TOKEN')) {
        # ProviderFactory.CreateGitHubModels falls back to GITHUB_TOKEN when the
        # configured env is unset (review finding) — the documented CI path — but
        # only a token that actually carries models:read satisfies the provider.
        switch (Get-GitHubTokenModelsScope -EnvName 'GITHUB_TOKEN') {
            'proven' {
                $ghModelsScopeProven = $true
                Add-Step -Step $ghModelsEnv -State 'ok' -Detail ('GITHUB_TOKEN carries models:read (X-OAuth-Scopes) and ProviderFactory.CreateGitHubModels falls back to it — ' +
                    'the github-models provider is satisfied without an export')
            }
            'unverifiable' {
                Add-Step -Step $ghModelsEnv -State 'ok' -Detail ('GITHUB_TOKEN holds a value and ProviderFactory.CreateGitHubModels falls back to it, but its models:read ' +
                    'permission is NOT verifiable here (fine-grained/Actions token exposes no scopes, or an injecting transport) — any vault ' +
                    'repair stays listed as the deterministic path; if model calls 403, grant models: read')
            }
            'missing-scope' {
                Add-Step -Step $ghModelsEnv -State 'needs-owner' -Detail 'GITHUB_TOKEN is REST-valid but its X-OAuth-Scopes lack models:read — the github-models provider would 403 on every call; trying the gh keyring next'
                Add-OwnerAction -Env $ghModelsEnv -Text $ghModelsRepairAction
                $ghFallbackNeeded = $true
            }
            default {
                Add-Step -Step $ghModelsEnv -State 'needs-owner' -Detail 'GITHUB_TOKEN was rejected by api.github.com — it cannot satisfy the github-models provider; trying the gh keyring next'
                $ghFallbackNeeded = $true
            }
        }
    }
    elseif (-not (Test-EnvValue $ghModelsEnv)) {
        $ghFallbackNeeded = $true
    }
    if ($ghFallbackNeeded) {
        # First PATH hit only: Get-Command returns EVERY matching application when
        # the name resolves more than once (a shim or a second install ahead of the
        # real binary), and an array .Source would then be invoked as one bogus
        # command name — measured as an internal failure, not a lane result.
        $ghCmd = Get-Command gh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $ghCmd) {
            # Record the lane even when gh is absent — an unevaluated-looking steps
            # list is ambiguous (review finding).
            Add-Step -Step $ghModelsEnv -State 'unavailable' -Detail 'gh CLI not on PATH and Key Vault did not provide the token'
        }
        else {
            # --hostname github.com (review finding): never export a GitHub
            # Enterprise credential (GH_HOST context) into the github.com models lane.
            # Env-cleared (review finding): gh gives GH_TOKEN/GITHUB_TOKEN precedence
            # over its keyring, so with a stale env token set this would export that
            # dead value instead of the STORED login. The shadowing variables are
            # removed for this one call and restored immediately (values move only
            # between env slots in-process; rest-connect.ps1 does the same).
            $savedGhToken = $env:GH_TOKEN
            $savedGithubToken = $env:GITHUB_TOKEN
            try {
                Remove-Item env:GH_TOKEN -ErrorAction SilentlyContinue
                Remove-Item env:GITHUB_TOKEN -ErrorAction SilentlyContinue
                $ghLines = @(& $ghCmd.Source auth token --hostname github.com 2>$null)
                $ghExit = [int]$LASTEXITCODE
            }
            finally {
                if ($null -ne $savedGhToken) { $env:GH_TOKEN = $savedGhToken }
                if ($null -ne $savedGithubToken) { $env:GITHUB_TOKEN = $savedGithubToken }
                $savedGhToken = ''
                $savedGithubToken = ''
            }
            $ghToken = (@($ghLines) -join '').Trim()
            if ($ghExit -eq 0 -and $ghToken) {
                # Scope PROOF before the export counts (review finding): the stored
                # gh login is probed exactly like GITHUB_TOKEN above. A token the
                # wire proves to lack models:read is not exported at all (the
                # provider would 403 on every call) and the repair action stands; an
                # unverifiable one is exported as the best available credential but
                # leaves every scope/vault repair listed until a run proves it.
                Set-Item -Path "env:$ghModelsEnv" -Value $ghToken
                $ghToken = ''
                switch (Get-GitHubTokenModelsScope -EnvName $ghModelsEnv) {
                    'proven' {
                        $ghModelsScopeProven = $true
                        $exportedNames.Add($ghModelsEnv)
                        Add-Step -Step $ghModelsEnv -State 'exported' -Detail 'from `gh auth token` — X-OAuth-Scopes carries models:read; lights: gh-models provider'
                    }
                    'unverifiable' {
                        $ghModelsUnprovenExport = $true
                        $exportedNames.Add($ghModelsEnv)
                        Add-Step -Step $ghModelsEnv -State 'exported' `
                            -Detail ('from `gh auth token` — exported as the best available credential, but its models:read permission is NOT ' +
                                'verifiable here (no X-OAuth-Scopes header, or an injecting transport); any scope/vault repair stays listed ' +
                                'until a run proves it; if model calls 403: gh auth refresh -h github.com --scopes models:read')
                    }
                    'missing-scope' {
                        Remove-Item -Path "env:$ghModelsEnv" -ErrorAction SilentlyContinue
                        Add-Step -Step $ghModelsEnv -State 'needs-owner' -Detail 'the stored gh login is REST-valid but its X-OAuth-Scopes lack models:read — NOT exported (the github-models provider would 403 on every call)'
                        Add-OwnerAction -Env $ghModelsEnv -Text $ghModelsRepairAction
                    }
                    default {
                        Remove-Item -Path "env:$ghModelsEnv" -ErrorAction SilentlyContinue
                        Add-Step -Step $ghModelsEnv -State 'needs-owner' -Detail 'the stored gh login was rejected by api.github.com — NOT exported'
                        Add-OwnerAction -Env $ghModelsEnv -Text "re-login gh with models:read — gh auth login --hostname github.com --web --scopes models:read$ghModelsVaultClause (lights $ghModelsEnv)"
                    }
                }
            }
            else {
                Add-Step -Step $ghModelsEnv -State 'skipped' -Detail 'gh CLI yielded no token (logged out or unavailable) and Key Vault did not provide one'
            }
        }
    }

    # Owner actions were collected BEFORE the export steps ran (review finding): the
    # auth-doctor's provider-lane actions say things like "pull openai-api-key into
    # OPENAI_API_KEY" — and when the Key Vault or gh rung supplies that exact env var
    # later in this same run, the pre-export action is already satisfied. The
    # summary's contract is "the only steps that need a human", so any action naming
    # a provider env var that NOW holds a value is dropped, with the drop reported.
    # Derived from the config-driven pairs (plus the gh-rung's configured target)
    # so the reconcile filter tracks config/aihub.json the same way the pulls do.
    $exportResolvableEnvNames = @(@($vaultPairs | ForEach-Object { $_.Env }) + $ghModelsEnv | Select-Object -Unique)
    $resolvedActionCount = 0
    $remainingOwnerActions = [System.Collections.Generic.List[string]]::new()
    foreach ($action in $ownerActions) {
        # Structural match (review finding): every action this script composes carries
        # the exact env var it retires on. A substring test let a satisfied 'API_KEY'
        # retire the unrelated OPENAI_API_KEY repair under a custom profile. The
        # auth-doctor's imported free-text actions carry no env, so the variable they
        # name is recovered by an exact-identifier match (bounded by the [A-Za-z0-9_]
        # class) — never a substring.
        $candidateEnvNames = if ($null -ne $action.Env) { @($action.Env | Where-Object { $_ }) }
        else {
            @($exportResolvableEnvNames | Where-Object {
                $action.Text -match ('(^|[^A-Za-z0-9_])' + [regex]::Escape($_) + '([^A-Za-z0-9_]|$)') })
        }
        $resolvedByExport = $false
        foreach ($name in $candidateEnvNames) {
            # The models env counts as satisfied via the provider's documented
            # GITHUB_TOKEN fallback too (review finding) — a run that ends with a
            # working github-models lane must not still demand a vault repair —
            # but never on the strength of an unproven gh-rung export (review
            # finding): a stored token that also lacks models:read would otherwise
            # retire the very repair it needs. A vault-pulled or pre-set value is
            # the deterministic path and counts as before.
            $envSatisfied = if ($name -eq $ghModelsEnv) {
                $ghModelsScopeProven -or ((Test-EnvValue $name) -and -not $ghModelsUnprovenExport)
            }
            else { Test-EnvValue $name }
            if ($envSatisfied) { $resolvedByExport = $true; break }
        }
        if ($resolvedByExport) { $resolvedActionCount++ } else { $remainingOwnerActions.Add($action.Text) }
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

# Dot-source hygiene (review finding): the documented contract mutates exactly
# two surfaces (the az profile via auth-doctor -Apply, and process env vars), so
# every helper symbol this file necessarily creates in a dot-sourcing caller's
# scope is removed again on every path below. ONE residue is not removable:
# PowerShell binds the -Json parameter into the calling scope BEFORE any code
# runs, so a caller variable named $Json/$json (names are case-insensitive) is
# overwritten by the binding itself — cleanup deletes the symbol rather than
# restoring a prior value. Do not rely on that name surviving this call.
function Remove-HeliosAutoLoginScopeResidue {
    Remove-Item -Path function:Invoke-HeliosAutoLogin -ErrorAction SilentlyContinue
    Remove-Item -Path variable:Json -ErrorAction SilentlyContinue
    Remove-Item -Path variable:autoLoginDotSourced -ErrorAction SilentlyContinue
    # Self-removal last: the already-loaded body keeps executing to completion.
    Remove-Item -Path function:Remove-HeliosAutoLoginScopeResidue -ErrorAction SilentlyContinue
}

$autoLoginDotSourced = $MyInvocation.InvocationName -eq '.'
try {
    Invoke-HeliosAutoLogin -Json:$Json -DotSourced $autoLoginDotSourced -RepoRoot (Resolve-Path (Join-Path $PSScriptRoot '..' '..'))
    if (-not $autoLoginDotSourced) { exit 0 }
    Remove-HeliosAutoLoginScopeResidue
}
catch {
    [Console]::Error.WriteLine("auto-login: internal failure: $($_.Exception.Message)")
    # Dot-sourced: rethrow so the caller can DETECT the partial setup (review
    # finding) — exiting would kill their shell, and swallowing would fake
    # success. Scope residue is removed first; `throw` rethrows $_ regardless.
    if ($autoLoginDotSourced) {
        Remove-HeliosAutoLoginScopeResidue
        throw
    }
    exit 1
}
