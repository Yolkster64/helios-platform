<#
.SYNOPSIS
Automatic authentication doctor for the HELIOS auth lanes — gh, az, openai-codex,
claude, copilot — plus the verify-only connector lanes: linear, slack, sharepoint,
azure-devops. Report-first: the default run diagnoses every lane, mutates nothing,
and exits 0. -Apply adds automatic NON-INTERACTIVE repair only; whatever cannot be
automated (MFA, device-code) is reported honestly as an exact owner-action command.

.DESCRIPTION
The automatic-repair sibling of `setup-ai-clis.ps1 -ProbeAuth` (which is read-only and
informational). This script stands alone: it probes each lane, attempts the safe
non-interactive repairs when -Apply is given, and emits one result per lane:

  {lane, state (ready|repaired|needs-owner|unavailable), method, detail,
   ownerAction (exact command when needs-owner)}

Lanes:

  gh            env token first (GH_TOKEN / GITHUB_TOKEN — names checked only, gh
                honors env tokens ahead of its keyring), validated by `gh auth status`
                (exit code only; raw output is never echoed — it can name accounts and
                scopes). In GitHub Actions (GITHUB_ACTIONS=true) the workflow-provided
                GITHUB_TOKEN is the auth and the fix is workflow wiring, not a login.
                Otherwise the device-code web login is the owner action.
  az            `az account show` plus a live token refresh
                (`az account get-access-token --output none`, exit code only): the
                show probe alone stays green in the exact broken state
                docs/architecture/ENTERPRISE_AI_CONNECTIONS.md §0 measured on
                2026-08-13 — profile cached but every ARM/Graph call failing
                AADSTS50078 (MFA expired). Repairs under -Apply: service principal
                from AZURE_CLIENT_ID + AZURE_TENANT_ID + AZURE_CLIENT_CERTIFICATE_PATH
                (only when that file exists) and then AZURE_CLIENT_SECRET — a
                rejected certificate falls back to the secret — or managed identity when
                IDENTITY_ENDPOINT / MSI_ENDPOINT is present (or -UseManagedIdentity).
                In Actions with ACTIONS_ID_TOKEN_REQUEST_URL present the azure/login
                step owns the OIDC exchange (ci-oidc) and is never fought. The
                interactive fallback is the tenant-scoped re-login from
                ENTERPRISE_AI_CONNECTIONS.md §1 — reported, never run.
  openai-codex  a non-empty value in an env var the ENABLED openai / openai-codex
                providers declare (providers.*.apiKeyEnv from the active config,
                AIHUB_CONFIG-first; OPENAI_API_KEY only as the fallback when the
                config is unreadable or only the codex agent is enabled) — one key
                covers the codex CLI and those API providers; when the codex agent is
                enabled and the CLI is on PATH, `codex login status` is probed
                non-interactively (a CLI login covers the CLI only — connect-all.ps1
                honesty rule).
  claude        a non-empty value in the env var the active config declares for the
                anthropic provider (providers.anthropic.apiKeyEnv, read at run time
                from AIHUB_CONFIG when set, else config/aihub.json — never hardcoded).
                Any provider/CLI lane whose every consumer is disabled or absent in
                that config reports `disabled` with no owner action — the hub never
                instantiates it, so a credential demand would be a false step. A cached `claude` login cannot be probed
                headlessly (probing would launch an interactive session), so it is
                never counted.
  copilot       presence probe: standalone copilot CLI (@github/copilot — the shape
                config/aihub.json invokes) or the gh-copilot extension. Its auth rides
                the GitHub login, so the lane defers to the gh lane's result.

Connector lanes (verify-only, NEVER gate the exit code — they diagnose wiring, and
their fixes are repository secrets or tenant consent, not logins this doctor can run):

  linear        LINEAR_API_KEY presence (name only — config/connectors.json
                linear.apiKeyEnv). .github/workflows/linear-sync.yml skips green
                without the repository secret of the same name.
  slack         SLACK_WEBHOOK_URL presence (connectors.json slack.webhookUrlEnv);
                notify-slack.yml skips green without the repository secret. Also
                reports SLACK_BOT_TOKEN honestly: declared in connectors.json
                (botTokenEnv) but nothing in the repo consumes it today.
  sharepoint    no headless probe exists: SharePoint/M365 Graph access is owner-gated
                (admin consent for integrations/m365/, MFA-bound tenant session —
                AADSTS50078 per docs/architecture/ENTERPRISE_AI_CONNECTIONS.md §0).
                Always reported as the exact owner runbook.
  azure-devops  informational: az devops extension + AZURE_DEVOPS_EXT_PAT presence.
                No Azure DevOps org is configured in this repo today — nothing
                consumes either; the lane exists so wiring an org later starts from
                a truthful baseline.

Ordering principle — automatic-first, interactive-last:

  CI OIDC -> env token / service principal -> managed identity -> device-code

WHY this order: the automatic methods are deterministic and safe on a headless host —
they either succeed or fail fast with an error code this script can report, so a
doctor may apply them with nobody watching. Device-code/MFA flows are the opposite:
they block on a human with a second device (AADSTS50078 literally means the MFA
session expired, and only the owner can satisfy MFA again), so interactive login is
always the LAST resort and is only ever REPORTED as an ownerAction command. -Apply
never falls back to anything interactive.

Secrets policy (CLAUDE.md rule): environment variables are checked by NAME only —
values never enter a script variable, are never interpolated into a logged string, and
are never printed. The service-principal repair reads credentials from the environment
into an argument ARRAY handed straight to the az process. Raw output of auth probes is
never echoed.

Exit codes: 0 = report-only run (the default: diagnose everything, mutate nothing), or
an -Apply run where every lane ended ready/repaired (unavailable lanes — the tool
itself is missing — are reported but never gate; installing tools is
setup-ai-clis.ps1's job); 2 = an -Apply run left at least one lane needs-owner;
1 = internal failure.

.PARAMETER Apply
Enable automatic NON-INTERACTIVE repair (currently: the az lane's service-principal
and managed-identity logins). Never starts a device-code, browser, or MFA flow —
those remain owner actions in the report.

.PARAMETER Json
Emit one machine-readable report object instead of the human report (nothing else on
stdout — same convention as setup-all.ps1 -Json / verify-readiness.ps1 -Json).

.PARAMETER UseManagedIdentity
Treat managed identity as available even when no IDENTITY_ENDPOINT / MSI_ENDPOINT is
visible (some hosts, e.g. classic IMDS-only VMs, expose neither variable). Only acts
together with -Apply.

.EXAMPLE
pwsh scripts/bootstrap/auth-doctor.ps1

.EXAMPLE
pwsh scripts/bootstrap/auth-doctor.ps1 -Json | ConvertFrom-Json

.EXAMPLE
pwsh scripts/bootstrap/auth-doctor.ps1 -Apply

.EXAMPLE
pwsh scripts/bootstrap/auth-doctor.ps1 -Apply -UseManagedIdentity
#>
#Requires -Version 7
[CmdletBinding()]
param(
    [switch]$Apply,

    [switch]$Json,

    [switch]$UseManagedIdentity
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

# Same environment probe as setup-ai-clis.ps1 / connect-all.ps1: documented env vars,
# never heuristics. GitHub Actions is detected first because it changes what the
# right fix even is (workflow wiring / azure-login OIDC, never a login flow).
$inActions = $env:GITHUB_ACTIONS -eq 'true'
$inCloudShell = [bool]($env:AZUREPS_HOST_ENVIRONMENT -or $env:ACC_CLOUD -or $env:CLOUD_SHELL)
$environment = if ($inActions) { 'GitHub Actions' }
elseif ($inCloudShell) { 'Azure Cloud Shell' }
elseif ($env:CODESPACES) { 'GitHub Codespaces' }
else { 'local shell' }
$modeLabel = if ($Apply) { 'apply' } else { 'report-only' }

# -Json promises one object and nothing else on stdout, and from an external caller's
# viewpoint Write-Host lands on stdout too — so all progress printing gates on it
# (setup-all.ps1 convention).
function Write-Report {
    param([string]$Message = '')
    if (-not $Json) { Write-Host $Message }
}

function Get-CliCommand {
    param([Parameter(Mandatory)][string]$Name)
    # Application only: these tools are invoked as OS subprocesses, which can never
    # resolve a PowerShell alias or function shadowing the name (setup-ai-clis.ps1
    # rationale).
    Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
}

# Credential presence = a NON-WHITESPACE value (review finding): Actions expressions
# and dotenv loaders routinely materialize optional secrets as EMPTY variables, and an
# existence-only test would report a lane ready that lights nothing. The value is read
# only for this emptiness test and never logged.
function Test-EnvValue {
    param([Parameter(Mandatory)][string]$Name)
    return -not [string]::IsNullOrWhiteSpace([string][Environment]::GetEnvironmentVariable($Name))
}

# The active hub config — AIHUB_CONFIG over the repo default, the same precedence the
# hub, auto-login.ps1 and rest-connect.ps1 apply — parsed once. Config = $null when
# unreadable, so each lane falls back to its defaults and says so.
$script:aihubConfigState = $null
function Get-AIHubConfigState {
    if ($null -ne $script:aihubConfigState) { return $script:aihubConfigState }
    $label = 'config/aihub.json'
    $path = Join-Path $repoRoot 'config' 'aihub.json'
    $explicit = $false
    if (-not [string]::IsNullOrWhiteSpace([string]$env:AIHUB_CONFIG)) {
        $path = ([string]$env:AIHUB_CONFIG).Trim()
        $label = 'AIHUB_CONFIG'
        $explicit = $true
    }
    $config = $null
    try { $config = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json }
    catch { Write-Verbose "$label read failed: $($_.Exception.Message)" }
    # The hub binds the document to an object; anything else fails there the same way.
    if ($config -isnot [System.Management.Automation.PSCustomObject]) { $config = $null }
    # Explicit = AIHUB_CONFIG selected this file: the main flow aborts before any lane
    # when such a profile is unreadable (review finding) — the fallback names belong
    # to an unreadable REPO DEFAULT only, never to an invented custom profile.
    $script:aihubConfigState = [pscustomobject]@{ Label = $label; Path = $path; Config = $config; Explicit = $explicit }
    return $script:aihubConfigState
}

# Enablement exactly as ProviderFactory.CreateAll applies it (review finding): every
# enabled provider entry is instantiated and its implementation is chosen from
# provider.type — a custom profile may name its OpenAI provider 'gpt-prod' — so
# lanes discover providers BY TYPE, never by canonical key. A provider or cliAgent
# with enabled=false (or a cliAgent absent from the list) is never instantiated, so
# a lane whose EVERY consumer is off reports 'disabled' and carries no owner action;
# demanding a credential for it would be a false step. Returns $null when the config
# is unreadable (callers then diagnose the fallback names), else the enabled entries
# of that type as { Name; Value } — possibly none.
function Get-AIHubEnabledProvidersOfType {
    param([Parameter(Mandatory)][string]$Type)
    $cfg = (Get-AIHubConfigState).Config
    if ($null -eq $cfg) { return $null }
    $found = [System.Collections.Generic.List[object]]::new()
    # An absent (or null) providers section is an EMPTY table, not an unreadable
    # config (review finding): AIHubOptions.Providers starts empty, so the hub loads
    # a CLI-only profile and instantiates no API provider from it — the fallback
    # names are for a file the hub could not read, never for one it reads fine.
    if (-not $cfg.PSObject.Properties['providers'] -or $null -eq $cfg.providers) { return , $found }
    foreach ($prop in $cfg.providers.PSObject.Properties) {
        $prov = $prop.Value
        if ($null -eq $prov) { continue }
        $provType = if ($prov.PSObject.Properties['type']) { ([string]$prov.type).Trim() } else { '' }
        if (-not $provType.Equals($Type, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($prov.PSObject.Properties['enabled'] -and $prov.enabled -eq $false) { continue }
        $found.Add([pscustomobject]@{ Name = $prop.Name; Value = $prov })
    }
    return , $found
}
# One (Env, SecretName) pair per DISTINCT variable the given enabled entries read,
# plus the entries that declare a BLANK apiKeyEnv (review finding): ProviderFactory
# applies the per-type default (`ApiKeyEnv ?? <default>`) only when the property is
# absent or JSON null, and SecretResolver reads no variable for a blank name — such
# an entry resolves only its apiKeySecretName, in-process, so no variable can prove
# it here, and without a secret it can never be configured at all. Normalizing blank
# to the default would demand a variable the hub never reads. Entries that map
# DIFFERENT secrets to ONE variable come back as conflicts (review finding): the
# vault hint would otherwise name whichever secret was declared first, and
# auto-login pulls nothing into such a variable.
function Get-ProviderCredentialPairs {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Entries,
        [Parameter(Mandatory)][string]$DefaultEnv
    )
    $pairs = [System.Collections.Generic.List[object]]::new()
    $blank = [System.Collections.Generic.List[object]]::new()
    $readers = [ordered]@{}
    foreach ($entry in $Entries) {
        $prov = $entry.Value
        $envProp = $prov.PSObject.Properties['apiKeyEnv']
        $declaredEnv = if ($null -eq $envProp -or $null -eq $envProp.Value) { $DefaultEnv } else { ([string]$envProp.Value).Trim() }
        $declaredVault = if ($prov.PSObject.Properties['apiKeySecretName']) { ([string]$prov.apiKeySecretName).Trim() } else { '' }
        if ($declaredEnv -eq '') {
            $blank.Add([pscustomobject]@{ Name = $entry.Name; SecretName = $declaredVault })
            continue
        }
        if (-not $readers.Contains($declaredEnv)) { $readers[$declaredEnv] = [System.Collections.Generic.List[object]]::new() }
        $readers[$declaredEnv].Add([pscustomobject]@{ Name = $entry.Name; SecretName = $declaredVault })
        if (-not @($pairs | Where-Object { $_.Env -eq $declaredEnv }).Count) {
            $pairs.Add([pscustomobject]@{ Env = $declaredEnv; SecretName = $declaredVault })
        }
    }
    $conflicts = [System.Collections.Generic.List[object]]::new()
    foreach ($envName in @($readers.Keys)) {
        $secrets = @($readers[$envName] | ForEach-Object { $_.SecretName } | Where-Object { $_ } | Select-Object -Unique)
        if ($secrets.Count -gt 1) {
            $conflicts.Add([pscustomobject]@{ Env = $envName; Names = @($readers[$envName] | ForEach-Object Name); Secrets = $secrets })
        }
    }
    return [pscustomobject]@{ Pairs = $pairs; Blank = $blank; Conflicts = $conflicts }
}
# Config defects the API-key lanes report as owner actions, never as readiness:
# blank-apiKeyEnv entries with no secret path, and conflicting secret mappings. Blank
# entries WITH a secret are not defects — Get-BlankVaultChecks proves or fails them.
function Get-ConfigDefectVerdict {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Blank,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Conflicts,
        [Parameter(Mandatory)][string]$Type,
        [Parameter(Mandatory)][string]$DefaultEnv,
        [Parameter(Mandatory)][string]$ConfigLabel
    )
    $defects = @($Blank | Where-Object { -not $_.SecretName })
    $quote = { param($names) (@($names | ForEach-Object { "'$_'" }) -join ', ') }
    $details = @()
    $actions = @()
    if ($defects.Count -gt 0) {
        $defectNames = @($defects | ForEach-Object Name)
        $details += "provider(s) $(& $quote $defectNames) (type $Type) declare an explicitly blank apiKeyEnv and no apiKeySecretName — ProviderFactory reads no variable and no secret for them ($DefaultEnv applies only when the property is absent), so they can never be configured"
        $actions += "fix providers.{$($defectNames -join ',')}.apiKeyEnv in ${ConfigLabel}: set a variable name (or remove the property to use $DefaultEnv) and/or add apiKeySecretName"
    }
    foreach ($conflict in $Conflicts) {
        $details += "providers $(& $quote $conflict.Names) (type $Type) map different Key Vault secrets $(& $quote $conflict.Secrets) to the same variable $($conflict.Env) — SecretResolver prefers the environment, so whichever secret were pulled first would be handed to every sharer (auto-login pulls none of them)"
        $actions += "give providers.{$($conflict.Names -join ',')} distinct apiKeyEnv names in ${ConfigLabel} (or one shared apiKeySecretName)"
    }
    return [pscustomobject]@{ HasDefects = ($details.Count -gt 0); DefectDetail = ($details -join '; '); DefectAction = ($actions -join '; ') }
}
# Existence proof for a blank-apiKeyEnv entry's Key Vault secret (review finding):
# readiness is never inferred from having nothing to inspect. The proof is metadata
# only — `az keyvault secret list` returns names, never values — under the az lane's
# own login; anything short of a listed name is unproven and reported as the exact
# prerequisite that is missing (vault URI, az lane, RBAC, or the secret itself).
function Get-BlankVaultChecks {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Blank,
        [Parameter(Mandatory)][pscustomobject]$AzResult
    )
    # Returned as a plain array (not the comma-wrapped list): the caller's @() must
    # see the ITEMS — a wrapped list would arrive as one element and an empty one
    # would fail member enumeration under StrictMode.
    $results = [System.Collections.Generic.List[object]]::new()
    if ($Blank.Count -eq 0) { return $results.ToArray() }
    $vaultUri = if (Test-EnvValue 'AZURE_KEY_VAULT_URI') { ([string]$env:AZURE_KEY_VAULT_URI).Trim() } else { '' }
    $vaultName = ''
    if ($vaultUri) {
        try {
            $parsedUri = [uri]$vaultUri
            if ($parsedUri.Scheme -eq 'https' -and $parsedUri.Host -match '^(?<vault>[A-Za-z0-9-]{3,24})\.vault\.(azure\.net|azure\.cn|usgovcloudapi\.net|microsoftazure\.de)$') { $vaultName = $Matches['vault'] }
        }
        catch { }
    }
    $azCmd = Get-CliCommand -Name 'az'
    $blocker = ''
    $blockerHint = ''
    if (-not $vaultUri) {
        $blocker = 'AZURE_KEY_VAULT_URI is unset, so the hub cannot reach any vault'
        $blockerHint = 'set AZURE_KEY_VAULT_URI (PowerShell: . .helios/azure.env.ps1; bash: source .helios/azure.env)'
    }
    elseif (-not $vaultName) {
        $blocker = 'AZURE_KEY_VAULT_URI is not an https://<vault>.vault.azure.net/ (or sovereign-cloud) Key Vault URI'
        $blockerHint = 'fix AZURE_KEY_VAULT_URI'
    }
    elseif ($AzResult.state -notin 'ready', 'repaired' -or -not $azCmd) {
        $blocker = "the az lane is $($AzResult.state), so the secret cannot be listed from here"
        $blockerHint = if ("$($AzResult.ownerAction)".Trim()) { "$($AzResult.ownerAction)" } else { 'repair the az lane (see its row), then re-run' }
    }
    $listed = @()
    if (-not $blocker) {
        $listProbe = Invoke-Probe -Executable $azCmd.Source -Arguments @('keyvault', 'secret', 'list', '--vault-name', $vaultName, '--query', '[].name', '--output', 'tsv', '--only-show-errors')
        if ($listProbe.ExitCode -eq 0) { $listed = @(@($listProbe.Output) | ForEach-Object { "$_".Trim() } | Where-Object { $_ }) }
        else {
            $blocker = "az keyvault secret list against vault '$vaultName' failed (exit $($listProbe.ExitCode): no RBAC grant, network, or wrong vault; output never echoed)"
            $blockerHint = "grant the running identity 'Key Vault Secrets User' on vault '$vaultName' (or fix AZURE_KEY_VAULT_URI)"
        }
    }
    foreach ($entry in $Blank) {
        if ($blocker) {
            $results.Add([pscustomobject]@{ Name = $entry.Name; SecretName = $entry.SecretName; Status = 'unverifiable'; Reason = $blocker; Hint = $blockerHint; Vault = $vaultName })
        }
        elseif ($listed -contains $entry.SecretName) {
            $results.Add([pscustomobject]@{ Name = $entry.Name; SecretName = $entry.SecretName; Status = 'present'; Reason = "listed in vault '$vaultName'"; Hint = ''; Vault = $vaultName })
        }
        else {
            $results.Add([pscustomobject]@{ Name = $entry.Name; SecretName = $entry.SecretName; Status = 'absent'; Reason = "not present in vault '$vaultName'"; Hint = "az keyvault secret set --vault-name $vaultName --name $($entry.SecretName)   # owner supplies the value"; Vault = $vaultName })
        }
    }
    return $results.ToArray()
}
# Shared evaluation for the two API-key lanes (openai-codex, claude): pairs and blank
# entries from the enabled entries of one type, config defects, the Key Vault
# existence proof for blank+vaulted entries, and the missing/satisfied split — one
# rule set for both lanes. Satisfied means every variable holds a value AND every
# in-process secret is proven present; nothing else counts as ready.
function Get-ApiKeyLaneEvaluation {
    param(
        [AllowNull()][object]$Providers,
        [Parameter(Mandatory)][string]$Type,
        [Parameter(Mandatory)][string]$DefaultEnv,
        [Parameter(Mandatory)][string]$DefaultSecret,
        [Parameter(Mandatory)][string]$ConfigLabel,
        [Parameter(Mandatory)][string]$CliOnlySource,
        [Parameter(Mandatory)][pscustomobject]$AzResult
    )
    $pairs = [System.Collections.Generic.List[object]]::new()
    $blank = [System.Collections.Generic.List[object]]::new()
    $conflicts = @()
    $nameSource = "fallback defaults; $ConfigLabel was unreadable"
    if ($null -ne $Providers) {
        $derived = Get-ProviderCredentialPairs -Entries @($Providers) -DefaultEnv $DefaultEnv
        $pairs = $derived.Pairs
        $blank = $derived.Blank
        $conflicts = @($derived.Conflicts)
        $names = @($Providers | ForEach-Object Name) -join ','
        $nameSource = if ($pairs.Count -gt 0) { "$ConfigLabel providers.{$names}.apiKeyEnv (type $Type; $DefaultEnv where the property is absent)" }
        elseif ($blank.Count -gt 0) { "$ConfigLabel providers.{$names}.apiKeyEnv (type $Type; every enabled entry declares a blank apiKeyEnv, so the hub reads no variable for them)" }
        else { $CliOnlySource }
    }
    # The built-in pair applies only when NO enabled entry exists to derive from — a
    # profile whose entries all declare a blank apiKeyEnv reads no variable at all.
    if ($pairs.Count -eq 0 -and $blank.Count -eq 0) { $pairs.Add([pscustomobject]@{ Env = $DefaultEnv; SecretName = $DefaultSecret }) }
    $defect = Get-ConfigDefectVerdict -Blank @($blank) -Conflicts @($conflicts) -Type $Type -DefaultEnv $DefaultEnv -ConfigLabel $ConfigLabel
    $vaultChecks = @(Get-BlankVaultChecks -Blank @($blank | Where-Object { $_.SecretName }) -AzResult $AzResult)
    $provenVault = @($vaultChecks | Where-Object { $_.Status -eq 'present' })
    $unprovenVault = @($vaultChecks | Where-Object { $_.Status -ne 'present' })
    # Name-only presence checks; values never enter a variable.
    $missingPairs = @($pairs | Where-Object { -not (Test-EnvValue $_.Env) })
    $setEnvNames = @($pairs | Where-Object { Test-EnvValue $_.Env } | ForEach-Object Env)
    $quote = { param($names) (@($names | ForEach-Object { "'$_'" }) -join ', ') }
    $provenNote = if ($provenVault.Count -gt 0) {
        "; provider(s) $(& $quote @($provenVault | ForEach-Object Name)) declare a blank apiKeyEnv and their Key Vault secret(s) $(& $quote @($provenVault | ForEach-Object SecretName | Select-Object -Unique)) are listed in vault '$($provenVault[0].Vault)' (names only, values never read) — the hub resolves them in-process under AZURE_KEY_VAULT_URI"
    }
    else { '' }
    $missingItems = @(@($missingPairs | ForEach-Object Env) +
        @($unprovenVault | ForEach-Object { "the in-process Key Vault path of provider '$($_.Name)' (blank apiKeyEnv; secret '$($_.SecretName)': $($_.Reason))" }))
    $hints = @(@($missingPairs | ForEach-Object { Get-VaultPullHint -SecretName $_.SecretName -EnvName $_.Env }) +
        @($unprovenVault | ForEach-Object { $_.Hint } | Where-Object { $_ } | Select-Object -Unique))
    [pscustomobject]@{
        NameSource   = $nameSource
        EnvList      = (@($pairs | ForEach-Object Env) -join ' / ')
        HasEnvPairs  = ($pairs.Count -gt 0)
        HasDefects   = $defect.HasDefects
        DefectDetail = $defect.DefectDetail
        DefectAction = $defect.DefectAction
        Satisfied    = ($missingPairs.Count -eq 0 -and $unprovenVault.Count -eq 0)
        ProvenNote   = $provenNote
        MissingList  = ($missingItems -join ' / ')
        PartialNote  = $(if ($setEnvNames.Count -gt 0) { " ($($setEnvNames -join ' / ') is set, but each enabled provider reads its own variable)" } else { '' })
        VaultPull    = ($hints -join '; ')
    }
}
# Enabled CLI entries are discovered by their configured COMMAND (review finding):
# ProviderFactory.CreateAll instantiates every enabled cliAgents entry whatever its
# routing name, and CliProcessAgent runs entry.command — so a profile naming its
# codex entry 'code-prod' still launches codex. The command's leaf (directory and
# .exe/.cmd stripped) is compared case-insensitively; the canonical name is accepted
# only for an entry that declares no command at all.
function Test-AIHubCliAgentEnabled {
    param([Parameter(Mandatory)][string]$Command, [string]$CanonicalName = '')
    $cfg = (Get-AIHubConfigState).Config
    if ($null -eq $cfg) { return $true }
    if (-not $cfg.PSObject.Properties['cliAgents'] -or $null -eq $cfg.cliAgents) { return $false }
    foreach ($agent in @($cfg.cliAgents)) {
        if ($null -eq $agent) { continue }
        if ($agent.PSObject.Properties['enabled'] -and $agent.enabled -eq $false) { continue }
        $cmd = if ($agent.PSObject.Properties['command'] -and $null -ne $agent.command) { ([string]$agent.command).Trim() } else { '' }
        $leaf = ''
        if ($cmd) { try { $leaf = [System.IO.Path]::GetFileNameWithoutExtension($cmd) } catch { $leaf = $cmd } }
        if ($leaf -and $leaf.Equals($Command, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        if (-not $cmd -and $CanonicalName -and $agent.PSObject.Properties['name'] -and ([string]$agent.name).Trim().Equals($CanonicalName, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

# The exact pull command for one (secret, env) pair (review finding): the bash loader
# scripts/bootstrap/load-env-from-keyvault.sh knows only the three built-in names, so a
# custom profile must be pointed at the config-aware auto-login.ps1 — otherwise the
# advertised repair leaves the diagnosed variable unset.
function Get-VaultPullHint {
    param([AllowEmptyString()][string]$SecretName, [Parameter(Mandatory)][string]$EnvName)
    if ([string]::IsNullOrWhiteSpace($SecretName)) {
        return "set $EnvName directly (the active config declares no apiKeySecretName for it, so no vault pull exists)"
    }
    $builtIn = @{ 'openai-api-key' = 'OPENAI_API_KEY'; 'anthropic-api-key' = 'ANTHROPIC_API_KEY'; 'github-models-token' = 'GITHUB_MODELS_TOKEN' }
    if ($builtIn.ContainsKey($SecretName) -and $builtIn[$SecretName] -eq $EnvName) {
        return "source scripts/bootstrap/load-env-from-keyvault.sh (bash) or pwsh: . scripts/bootstrap/auto-login.ps1 — pulls $SecretName into $EnvName"
    }
    return "pwsh: . scripts/bootstrap/auto-login.ps1 (config-aware; pulls $SecretName into $EnvName — load-env-from-keyvault.sh knows only the built-in names)"
}

function Invoke-Probe {
    param(
        [Parameter(Mandatory)][string]$Executable,
        [string[]]$Arguments = @()
    )
    # Capture ALL output first, THEN read $LASTEXITCODE. Piping into anything that can
    # stop the pipeline early (Select-Object -First 1) may halt it before
    # $LASTEXITCODE is assigned — an error under StrictMode (setup-ai-clis.ps1 /
    # connect-all.ps1 pattern). Callers must never print Output raw: auth status text
    # can embed account names, scopes, or worse.
    $lines = @(& $Executable @Arguments 2>&1 | ForEach-Object { "$_" })
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $lines }
}

function Invoke-GhAuthStatus {
    # --active restricts the check to the account subsequent gh commands actually use;
    # pre-2.40 gh lacks the flag — fall back one flag narrower (connect-all.ps1 /
    # connect-github.sh probe).
    param([Parameter(Mandatory)][string]$GhExe)
    $result = Invoke-Probe -Executable $GhExe -Arguments @('auth', 'status', '--hostname', 'github.com', '--active')
    if ($result.ExitCode -ne 0 -and ((@($result.Output) -join ' ') -match 'unknown flag')) {
        $result = Invoke-Probe -Executable $GhExe -Arguments @('auth', 'status', '--hostname', 'github.com')
    }
    $result
}

function New-LaneResult {
    param(
        [Parameter(Mandatory)][string]$Lane,
        [Parameter(Mandatory)]
        [ValidateSet('ready', 'repaired', 'needs-owner', 'unavailable', 'disabled')]
        [string]$State,
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Detail,
        [string]$OwnerAction = '',
        # Connector lanes are verify-only: they report wiring state but never gate the
        # -Apply exit code (their fixes are repo secrets / tenant consent, not logins).
        [bool]$Gates = $true
    )
    [pscustomobject]@{
        lane        = $Lane
        state       = $State
        method      = $Method
        detail      = $Detail
        ownerAction = $OwnerAction
        gates       = $Gates
    }
}

# --- gh lane -------------------------------------------------------------------------
function Test-GhLane {
    $ghCmd = Get-CliCommand -Name 'gh'
    $envTokenName = @(@('GH_TOKEN', 'GITHUB_TOKEN') | Where-Object { Test-EnvValue $_ }) | Select-Object -First 1

    if (-not $ghCmd) {
        $suffix = if ($envTokenName) { (' ({0} is set — name checked only — but there is no gh to drive)' -f $envTokenName) }
        else { '' }
        return New-LaneResult -Lane 'gh' -State 'unavailable' -Method 'none' `
            -Detail ('gh (GitHub CLI) is not on PATH' + $suffix + ' — install via scripts/bootstrap/cloud-shell-setup.sh or https://cli.github.com')
    }

    # Exit code only; the raw status text is never echoed (it names accounts/scopes).
    $status = Invoke-GhAuthStatus -GhExe $ghCmd.Source

    if ($envTokenName) {
        # gh honors env tokens ahead of its keyring, so a set token IS the auth.
        $actionsNote = if ($inActions) { ' — GitHub Actions: the workflow-provided GITHUB_TOKEN is the auth here' } else { '' }
        if ($status.ExitCode -eq 0) {
            return New-LaneResult -Lane 'gh' -State 'ready' -Method 'env-token' `
                -Detail ("$envTokenName is set (name checked only, value never read) and gh auth status accepts it$actionsNote")
        }
        return New-LaneResult -Lane 'gh' -State 'needs-owner' -Method 'env-token' `
            -Detail ("$envTokenName is set (name checked only) but gh auth status exits $($status.ExitCode) — the gh CLI rejects the session, which does NOT prove the token is bad: REST-level " +
                'connectivity can still exist (a proxy-injected session, or a fine-grained/app token the CLI dislikes). Wire-level ground truth: pwsh scripts/verify/rest-connect.ps1' +
                " (raw status output never echoed)$actionsNote") `
            -OwnerAction 'gh auth login --web   # device-code flow; or rotate the env token — but run scripts/verify/rest-connect.ps1 first: if the transport is already authenticated, nothing may be broken'
    }

    if ($status.ExitCode -eq 0) {
        return New-LaneResult -Lane 'gh' -State 'ready' -Method 'stored-login' `
            -Detail 'gh auth status reports an active github.com login from the keyring (raw output never echoed)'
    }

    if ($inActions) {
        # Inside Actions the fix is workflow wiring, never a login flow (gh's own
        # guidance: add GH_TOKEN: ${{ github.token }} to the job env).
        return New-LaneResult -Lane 'gh' -State 'needs-owner' -Method 'ci-env-token' `
            -Detail 'GitHub Actions job with no GH_TOKEN/GITHUB_TOKEN in the env — the workflow-provided GITHUB_TOKEN is the auth; pass it to the job' `
            -OwnerAction 'add to the workflow job:  env: { GH_TOKEN: ${{ github.token }} }'
    }

    return New-LaneResult -Lane 'gh' -State 'needs-owner' -Method 'device-code' `
        -Detail 'no env token and no stored gh login — the device-code web login needs a human with a browser and is never automated' `
        -OwnerAction 'gh auth login --web   # device-code flow; scripts/bootstrap/connect-github.sh adds the models:read scope'
}

# --- az lane -------------------------------------------------------------------------
function Test-AzLane {
    $azCmd = Get-CliCommand -Name 'az'
    if (-not $azCmd) {
        return New-LaneResult -Lane 'az' -State 'unavailable' -Method 'none' `
            -Detail 'az (Azure CLI) is not on PATH — install via scripts/bootstrap/cloud-shell-setup.sh or https://aka.ms/azure-cli'
    }

    # Two-step health probe. `az account show` only reads the cached profile, so it
    # stays green in the exact broken state ENTERPRISE_AI_CONNECTIONS.md §0 measured
    # (2026-08-13): profile cached, every ARM/Graph call failing AADSTS50078 (MFA
    # expired). The follow-up `az account get-access-token --output none` forces a
    # real token refresh — exit code only, nothing on stdout, and the output captured
    # from a failure is only regex-scanned for an AADSTS code, never echoed.
    $show = Invoke-Probe -Executable $azCmd.Source -Arguments @('account', 'show', '--output', 'none')
    $refreshOk = $false
    $aadCode = ''
    if ($show.ExitCode -eq 0) {
        $refresh = Invoke-Probe -Executable $azCmd.Source -Arguments @('account', 'get-access-token', '--output', 'none')
        if ($refresh.ExitCode -eq 0) { $refreshOk = $true }
        elseif ((@($refresh.Output) -join ' ') -match 'AADSTS\d+') { $aadCode = $Matches[0] }
    }

    if ($show.ExitCode -eq 0 -and $refreshOk) {
        $suffix = if ($inCloudShell) { ' (Cloud Shell implicit login)' } else { '' }
        return New-LaneResult -Lane 'az' -State 'ready' -Method 'cached-login' `
            -Detail ("az account show and a live token refresh both succeed$suffix — this Entra token backs az, the SDK credential chain, and Azure AI Foundry")
    }

    # Diagnosis for every branch below.
    $reason = if ($show.ExitCode -ne 0) { 'az has no cached login' }
    elseif ($aadCode -eq 'AADSTS50078') { 'az profile is cached but the token refresh fails AADSTS50078 — MFA expired (the exact state ENTERPRISE_AI_CONNECTIONS.md §0 measured)' }
    elseif ($aadCode) { "az profile is cached but the token refresh fails $aadCode" }
    else { 'az profile is cached but the token refresh fails (no AADSTS code in the error; raw output never echoed)' }

    # Repair ladder, automatic-first / interactive-last — see the WHY block in
    # .DESCRIPTION. Interactive login is never reached by -Apply; it only ever
    # appears as the reported ownerAction at the bottom.

    # Service-principal availability is computed FIRST because the OIDC rung yields
    # to it (review finding): ACTIONS_ID_TOKEN_REQUEST_URL only proves the exchange
    # is POSSIBLE, not that azure/login ran — a job that skipped azure/login but
    # carries AZURE_CLIENT_* workload credentials has a working non-interactive
    # repair that a short-circuit here would throw away (and every downstream Key
    # Vault pull with it).
    # Non-whitespace values required (review finding): Actions expressions routinely
    # materialize optional secrets as EMPTY variables, and an existence-only check
    # would then suppress the correct CI-OIDC branch and run az login with empty
    # arguments. Values are read only for this emptiness test, never logged.
    $spReady = (-not [string]::IsNullOrWhiteSpace([string]$env:AZURE_CLIENT_ID)) -and
        (-not [string]::IsNullOrWhiteSpace([string]$env:AZURE_TENANT_ID)) -and
        ((-not [string]::IsNullOrWhiteSpace([string]$env:AZURE_CLIENT_SECRET)) -or
         (-not [string]::IsNullOrWhiteSpace([string]$env:AZURE_CLIENT_CERTIFICATE_PATH)))

    # 1. CI OIDC: the azure/login action owns the GitHub-OIDC-to-Entra exchange
    #    (federated credentials from scripts/bootstrap/azure-oidc-setup.ps1). Doing a
    #    login here would fight it, so this is report-only by design — reached only
    #    when no service-principal repair is available.
    if ($inActions -and $env:ACTIONS_ID_TOKEN_REQUEST_URL -and -not $spReady) {
        return New-LaneResult -Lane 'az' -State 'needs-owner' -Method 'ci-oidc' `
            -Detail ("$reason; this Actions job can mint an OIDC token (ACTIONS_ID_TOKEN_REQUEST_URL is present) — the azure/login step owns that exchange and this doctor never fights it") `
            -OwnerAction 'add the azure/login step (client-id/tenant-id/subscription-id from the Actions variables scripts/bootstrap/azure-oidc-setup.ps1 prints) before this script runs'
    }

    # 2. Service principal from the environment — fully non-interactive.
    #    Credential candidates in preference order (review finding): a certificate
    #    is preferred over a shared secret, but only a certificate whose file exists
    #    is a candidate at all, and a certificate az rejects must not throw away a
    #    valid secret sitting next to it — every candidate is tried before the later
    #    rungs get a turn. Path existence only; certificate contents are never read.
    $spCandidates = [System.Collections.Generic.List[string]]::new()
    $certPathValue = ''
    if ($spReady) {
        $certPathValue = ([string]$env:AZURE_CLIENT_CERTIFICATE_PATH).Trim()
        if (-not [string]::IsNullOrWhiteSpace($certPathValue)) {
            if (Test-Path -LiteralPath $certPathValue -PathType Leaf) { $spCandidates.Add('AZURE_CLIENT_CERTIFICATE_PATH') }
            else { $reason += '; AZURE_CLIENT_CERTIFICATE_PATH is set but no file exists at that path (path checked only) — certificate login skipped' }
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$env:AZURE_CLIENT_SECRET)) { $spCandidates.Add('AZURE_CLIENT_SECRET') }
    }
    if ($spCandidates.Count -gt 0) {
        $credOrder = @($spCandidates) -join ', then '
        if (-not $Apply) {
            return New-LaneResult -Lane 'az' -State 'needs-owner' -Method 'service-principal' `
                -Detail ("$reason; service-principal credentials are in the environment (AZURE_CLIENT_ID + AZURE_TENANT_ID + $credOrder — names checked only, certificate path existence only) — automatic non-interactive repair is available") `
                -OwnerAction 'pwsh scripts/bootstrap/auth-doctor.ps1 -Apply'
        }
        $spFailures = [System.Collections.Generic.List[string]]::new()
        foreach ($credEnvName in $spCandidates) {
            Write-Report ("  az: applying az login --service-principal (credentials read from AZURE_CLIENT_ID / AZURE_TENANT_ID / $credEnvName — values never logged)")
            # Argument ARRAY on purpose: each value flows env var -> process argv and
            # never through an interpolated string that could be logged or echoed.
            $spArgs = @(
                'login', '--service-principal',
                '--username', $env:AZURE_CLIENT_ID,
                '--tenant', $env:AZURE_TENANT_ID,
                '--output', 'none'
            )
            if ($credEnvName -eq 'AZURE_CLIENT_CERTIFICATE_PATH') {
                $spArgs += @('--certificate', $certPathValue)
            }
            else {
                $spArgs += @('--password', $env:AZURE_CLIENT_SECRET)
            }
            $login = Invoke-Probe -Executable $azCmd.Source -Arguments $spArgs
            $verify = Invoke-Probe -Executable $azCmd.Source -Arguments @('account', 'get-access-token', '--output', 'none')
            if ($login.ExitCode -eq 0 -and $verify.ExitCode -eq 0) {
                $spRescue = if ($spFailures.Count -gt 0) { ' — after ' + (@($spFailures) -join '; ') } else { '' }
                return New-LaneResult -Lane 'az' -State 'repaired' -Method 'service-principal' `
                    -Detail ("az login --service-principal succeeded and a live token refresh verifies it (credentials taken from AZURE_CLIENT_ID / AZURE_TENANT_ID / $credEnvName by name; values never logged)$spRescue")
            }
            $spFailText = (@($login.Output) + @($verify.Output)) -join ' '
            $spAad = if ($spFailText -match 'AADSTS\d+') { (' ({0})' -f $Matches[0]) } else { '' }
            $spFailures.Add("$credEnvName was rejected$spAad, exit $($login.ExitCode)")
        }
        $reason += ('; service-principal repair failed — ' + (@($spFailures) -join '; ') + ' — raw output never echoed')
        # Fall through: the next automatic rung may still work.
    }

    # 3. Managed identity — also fully non-interactive. IDENTITY_ENDPOINT covers App
    #    Service/Functions/Container Apps; MSI_ENDPOINT is the legacy name; classic
    #    IMDS-only VMs expose neither, which is what -UseManagedIdentity is for.
    $miAvailable = $UseManagedIdentity -or (Test-EnvValue 'IDENTITY_ENDPOINT') -or (Test-EnvValue 'MSI_ENDPOINT')
    if ($miAvailable) {
        if (-not $Apply) {
            return New-LaneResult -Lane 'az' -State 'needs-owner' -Method 'managed-identity' `
                -Detail ("$reason; a managed-identity endpoint is present (IDENTITY_ENDPOINT/MSI_ENDPOINT, or -UseManagedIdentity was given) — automatic non-interactive repair is available") `
                -OwnerAction 'pwsh scripts/bootstrap/auth-doctor.ps1 -Apply'
        }
        Write-Report '  az: applying az login --identity (managed identity; system-assigned/default)'
        # System-assigned/default identity only: selecting a user-assigned identity
        # needs its client id under a flag name that varies across az versions, so it
        # is never guessed here.
        $mi = Invoke-Probe -Executable $azCmd.Source -Arguments @('login', '--identity', '--output', 'none')
        $verify = Invoke-Probe -Executable $azCmd.Source -Arguments @('account', 'get-access-token', '--output', 'none')
        if ($mi.ExitCode -eq 0 -and $verify.ExitCode -eq 0) {
            return New-LaneResult -Lane 'az' -State 'repaired' -Method 'managed-identity' `
                -Detail 'az login --identity succeeded and a live token refresh verifies it'
        }
        $reason += ("; managed-identity repair failed (exit $($mi.ExitCode), raw output never echoed)")
    }

    # 3.5 CI OIDC as the pre-interactive fallback (review finding): when the SP
    #    (or MI) repair FAILED but this Actions job can still mint an OIDC token,
    #    the azure/login step remains a working NON-interactive path — device-code
    #    advice would be both wrong and useless in a headless CI job.
    if ($inActions -and $env:ACTIONS_ID_TOKEN_REQUEST_URL) {
        return New-LaneResult -Lane 'az' -State 'needs-owner' -Method 'ci-oidc' `
            -Detail ("$reason; this Actions job can still mint an OIDC token (ACTIONS_ID_TOKEN_REQUEST_URL is present) — the azure/login step owns that exchange and this doctor never fights it") `
            -OwnerAction 'add the azure/login step (client-id/tenant-id/subscription-id from the Actions variables scripts/bootstrap/azure-oidc-setup.ps1 prints) before this script runs'
    }

    # 4. Interactive last — MFA/device-code needs a human and is NEVER run by this
    #    script, -Apply included. Exact command and tenant id from
    #    docs/architecture/ENTERPRISE_AI_CONNECTIONS.md §1 (Azure re-auth).
    $mfaNote = if ($aadCode -eq 'AADSTS50078') { ' Only the owner can satisfy MFA again.' } else { '' }
    return New-LaneResult -Lane 'az' -State 'needs-owner' -Method 'device-code' `
        -Detail ('{0}.{1} Tenant-scoped re-login per ENTERPRISE_AI_CONNECTIONS.md §1; if az ad calls still fail afterwards, rerun it with --scope "https://graph.microsoft.com//.default"' -f $reason, $mfaNote) `
        -OwnerAction 'az login --tenant "349e1399-dccf-45b1-af7e-05d7b0676abf"'
}

# --- openai-codex lane -----------------------------------------------------------------
function Test-CodexLane {
    param([Parameter(Mandatory)][pscustomobject]$AzResult)
    # Same enablement rule as the claude lane: this lane covers the openai and
    # openai-codex providers plus the codex agent; only when ALL are off is nothing
    # instantiated and nothing requested.
    # Providers of TYPE openai (review finding): the hub instantiates every enabled
    # entry and dispatches on provider.type, so a custom profile's OpenAI provider may
    # live under any key ('gpt-prod'); the codex agent is the lane's CLI half,
    # discovered by its configured command (any entry running `codex`).
    $openAiProviders = Get-AIHubEnabledProvidersOfType -Type 'openai'
    $codexAgentEnabled = Test-AIHubCliAgentEnabled -Command 'codex' -CanonicalName 'codex'
    $configState = Get-AIHubConfigState
    $noApiProviders = ($null -ne $openAiProviders -and $openAiProviders.Count -eq 0)
    if ($noApiProviders -and -not $codexAgentEnabled) {
        return New-LaneResult -Lane 'openai-codex' -State 'disabled' -Method 'config' -Gates $false `
            -Detail ("no enabled provider of type openai and no enabled codex agent in the active config ($($configState.Label)) — nothing instantiates them, so no credential is needed and none is requested")
    }

    # Credential names come from the ENABLED provider entries (review finding): the
    # hub reads each provider's configured apiKeyEnv — ProviderFactory.CreateOpenAi
    # defaults to OPENAI_API_KEY when the entry declares none — so probing a
    # hard-coded name under a renamed profile misses the key and demands a variable
    # nothing reads, an action auto-login could never reconcile. One (Env, Secret)
    # pair per DISTINCT variable: providers sharing a variable collapse to one pair;
    # providers with their own variables each keep theirs, because CreateAll resolves
    # every provider's credential independently (review finding) — one satisfied
    # variable never covers a sibling. The built-in pair applies only when the config
    # is unreadable or only the codex agent is enabled (the CLI honors OPENAI_API_KEY).
    $eval = Get-ApiKeyLaneEvaluation -Providers $openAiProviders -Type 'openai' -DefaultEnv 'OPENAI_API_KEY' -DefaultSecret 'openai-api-key' `
        -ConfigLabel $configState.Label -CliOnlySource "fallback default; only the codex agent is enabled in $($configState.Label)" -AzResult $AzResult
    if ($eval.HasDefects) {
        return New-LaneResult -Lane 'openai-codex' -State 'needs-owner' -Method 'config' `
            -Detail $eval.DefectDetail -OwnerAction $eval.DefectAction
    }
    $nameSource = $eval.NameSource
    $envList = $eval.EnvList

    # EVERY distinct enabled provider variable must hold a value — and every
    # blank-apiKeyEnv entry's secret must be PROVEN present in the vault (names
    # listed, values never read) — before the lane is ready (review finding: having
    # nothing to inspect is not readiness).
    if ($eval.Satisfied) {
        if (-not $eval.HasEnvPairs) {
            return New-LaneResult -Lane 'openai-codex' -State 'ready' -Method 'keyvault-inprocess' `
                -Detail "no environment variable to check (declared by $nameSource)$($eval.ProvenNote)"
        }
        return New-LaneResult -Lane 'openai-codex' -State 'ready' -Method 'env-token' `
            -Detail "$envList set (declared by $nameSource; names checked only, values never read) — covers the codex CLI and every enabled openai/openai-codex API provider$($eval.ProvenNote)"
    }
    $missingList = $eval.MissingList
    $partialNote = $eval.PartialNote
    $vaultPull = $eval.VaultPull

    # The codex CLI login is an alternative for the CLI agent only, and only when the
    # profile enables that agent — a CLI login never covers the API providers.
    $codexCmd = if ($codexAgentEnabled) { Get-CliCommand -Name 'codex' } else { $null }
    if ($codexCmd) {
        $probe = Invoke-Probe -Executable $codexCmd.Source -Arguments @('login', 'status')
        $text = @($probe.Output) -join '; '
        if ($text -match '(?i)unrecognized subcommand|unexpected argument|unknown (sub)?command') {
            # Old builds predate `login status` — reported honestly, never guessed.
            return New-LaneResult -Lane 'openai-codex' -State 'needs-owner' -Method 'cli-login' `
                -Detail 'this codex build has no `login status` subcommand, so the lane cannot be verified headlessly' `
                -OwnerAction "codex login   # browser/device flow (owner action); or: $vaultPull"
        }
        if ($probe.ExitCode -eq 0) {
            if ($noApiProviders) {
                return New-LaneResult -Lane 'openai-codex' -State 'ready' -Method 'cli-login' `
                    -Detail 'codex login status exits 0 — the codex CLI is authenticated, and only the codex agent is enabled in the active config (no API provider needs a key)'
            }
            # The CLI is fine; the enabled API providers are not — they read their own
            # variables and a CLI login never covers them (connect-all.ps1 honesty rule).
            return New-LaneResult -Lane 'openai-codex' -State 'needs-owner' -Method 'env-token' `
                -Detail "codex login status exits 0 (the codex CLI is authenticated), but the enabled openai/openai-codex API providers need $missingList (declared by $nameSource), which is not satisfied$partialNote — a CLI login does not cover them" `
                -OwnerAction $vaultPull
        }
        return New-LaneResult -Lane 'openai-codex' -State 'needs-owner' -Method 'device-code' `
            -Detail ("codex login status exits $($probe.ExitCode) and $missingList is not satisfied (declared by $nameSource)$partialNote — the ChatGPT-plan login is a browser/device flow only an owner can complete") `
            -OwnerAction "codex login   # or: $vaultPull"
    }

    $cliNote = if ($codexAgentEnabled) { 'no codex CLI is on PATH (pwsh scripts/bootstrap/setup-ai-clis.ps1 installs @openai/codex)' } else { "the codex agent is disabled in $($configState.Label), so only the API key applies" }
    return New-LaneResult -Lane 'openai-codex' -State 'needs-owner' -Method 'env-token' `
        -Detail "$missingList (declared by $nameSource) is not satisfied$partialNote and $cliNote" `
        -OwnerAction "$vaultPull   # after az login"
}

# --- claude lane -----------------------------------------------------------------------
function Test-ClaudeLane {
    param([Parameter(Mandatory)][pscustomobject]$AzResult)
    # config/aihub.json is the contract for which env var the anthropic provider reads
    # (CLAUDE.md rule: config carries env-var NAMES only) — so the doctor reads the
    # config instead of hardcoding the name, falling back only if it is unreadable.
    # Providers of TYPE anthropic (review finding): the hub instantiates every enabled
    # entry and dispatches on provider.type, so the Anthropic provider may live under
    # any key; the claude-cli agent is the lane's CLI half. A lane nobody instantiates
    # asks for nothing: with no enabled anthropic-type provider AND the claude-cli
    # agent off, a credential demand would surface as a false owner step downstream.
    $anthropicProviders = Get-AIHubEnabledProvidersOfType -Type 'anthropic'
    $claudeAgentEnabled = Test-AIHubCliAgentEnabled -Command 'claude' -CanonicalName 'claude-cli'
    $configState = Get-AIHubConfigState
    $configLabel = $configState.Label
    if ($null -ne $anthropicProviders -and $anthropicProviders.Count -eq 0 -and -not $claudeAgentEnabled) {
        return New-LaneResult -Lane 'claude' -State 'disabled' -Method 'config' -Gates $false `
            -Detail ("no enabled provider of type anthropic and no enabled claude-cli agent in the active config ($configLabel) — ProviderFactory.CreateAll instantiates neither, so no credential is needed and none is requested")
    }
    # One (Env, SecretName) pair per DISTINCT variable the enabled anthropic-type
    # providers read (AnthropicAgent defaults to ANTHROPIC_API_KEY when an entry
    # declares no apiKeyEnv); every pair must hold a value, because CreateAll resolves
    # each provider's credential independently. The built-in pair applies when the
    # config is unreadable or only the claude-cli agent is enabled (the CLI reads it).
    $eval = Get-ApiKeyLaneEvaluation -Providers $anthropicProviders -Type 'anthropic' -DefaultEnv 'ANTHROPIC_API_KEY' -DefaultSecret 'anthropic-api-key' `
        -ConfigLabel $configLabel -CliOnlySource "fallback default; only the claude-cli agent is enabled in $configLabel" -AzResult $AzResult
    if ($eval.HasDefects) {
        return New-LaneResult -Lane 'claude' -State 'needs-owner' -Method 'config' `
            -Detail $eval.DefectDetail -OwnerAction $eval.DefectAction
    }
    $nameSource = $eval.NameSource
    $envList = $eval.EnvList

    # Non-whitespace, not mere existence (same rule as the service-principal gate):
    # an empty variable lights nothing; an in-process secret counts only once its
    # name is listed in the vault (review finding). Values are never read.
    if ($eval.Satisfied) {
        if (-not $eval.HasEnvPairs) {
            return New-LaneResult -Lane 'claude' -State 'ready' -Method 'keyvault-inprocess' `
                -Detail "no environment variable to check (declared by $nameSource)$($eval.ProvenNote)"
        }
        return New-LaneResult -Lane 'claude' -State 'ready' -Method 'env-token' `
            -Detail ("$envList set (declared by $nameSource; names checked only, values never read) — covers the claude cliAgent and every enabled anthropic provider$($eval.ProvenNote)")
    }
    $missingList = $eval.MissingList
    $partialNote = $eval.PartialNote
    $vaultPull = $eval.VaultPull

    $claudeCmd = Get-CliCommand -Name 'claude'
    $cliNote = if (-not $claudeAgentEnabled) { "the claude-cli agent is disabled in $configLabel, so only the API key applies" }
    elseif ($claudeCmd) { 'a cached claude login cannot be probed headlessly — probing would launch an interactive session (connect-all.ps1 rule)' }
    else { 'no claude CLI on PATH either (pwsh scripts/bootstrap/setup-ai-clis.ps1 installs it)' }
    $ownerAction = if ($claudeAgentEnabled) { "claude setup-token   # mint a long-lived token for the CLI (owner action); or: $vaultPull" } else { "$vaultPull   # after az login" }
    return New-LaneResult -Lane 'claude' -State 'needs-owner' -Method 'env-token' `
        -Detail ("$missingList (declared by $nameSource) is not satisfied$partialNote; $cliNote") `
        -OwnerAction $ownerAction
}

# --- copilot lane ----------------------------------------------------------------------
function Test-CopilotLane {
    param([Parameter(Mandatory)][pscustomobject]$GhResult)

    if (-not (Test-AIHubCliAgentEnabled -Command 'copilot' -CanonicalName 'copilot')) {
        return New-LaneResult -Lane 'copilot' -State 'disabled' -Method 'config' -Gates $false `
            -Detail ("the copilot agent is disabled or absent in the active config ($((Get-AIHubConfigState).Label)) — the hub never launches it, so no login is needed and none is requested")
    }

    # Only the standalone binary satisfies this lane (review finding): the configured
    # cliAgent runs `copilot -p ...` (@github/copilot), and the gh-copilot EXTENSION
    # provides `gh copilot suggest/explain` — a different executable shape the hub
    # cannot launch. The extension is reported as information, never as readiness.
    $copilotCmd = Get-CliCommand -Name 'copilot'
    $extensionNote = ''
    if (-not $copilotCmd) {
        $ghCmd = Get-CliCommand -Name 'gh'
        if ($ghCmd) {
            # `gh extension list` reads local state only — no network call.
            $extensions = Invoke-Probe -Executable $ghCmd.Source -Arguments @('extension', 'list')
            if ((@($extensions.Output) -join ' ') -match 'gh-copilot') {
                $extensionNote = ' (the gh-copilot extension IS installed, but it provides `gh copilot suggest/explain`, not the standalone `copilot -p` binary config/aihub.json invokes — informational only)'
            }
        }
        return New-LaneResult -Lane 'copilot' -State 'unavailable' -Method 'none' `
            -Detail ("the standalone copilot CLI (@github/copilot) is not on PATH$extensionNote — pwsh scripts/bootstrap/setup-ai-clis.ps1 installs the shape config/aihub.json invokes")
    }
    $presence = 'standalone copilot CLI (@github/copilot) is on PATH'

    # copilot reuses the GitHub login (setup-ai-clis.ps1: GH_TOKEN/GITHUB_TOKEN are
    # honored headlessly), so its auth state IS the gh lane's state.
    if ($GhResult.state -in 'ready', 'repaired') {
        return New-LaneResult -Lane 'copilot' -State 'ready' -Method 'github-login' `
            -Detail ("$presence; copilot reuses the GitHub login and the gh lane is $($GhResult.state) ($($GhResult.method))")
    }
    $fix = if ($GhResult.ownerAction) { $GhResult.ownerAction } else { 'gh auth login --web   # device-code flow' }
    return New-LaneResult -Lane 'copilot' -State 'needs-owner' -Method 'github-login' `
        -Detail ("$presence, but copilot reuses the GitHub login and the gh lane is $($GhResult.state) — one GitHub login fixes both lanes") `
        -OwnerAction $fix
}

# --- linear lane (connector; verify-only, never gates) --------------------------------
function Test-LinearLane {
    # config/connectors.json linear.apiKeyEnv declares the name; the sync workflow
    # (.github/workflows/linear-sync.yml) reads the REPOSITORY SECRET of that name and
    # skips green without it — a local env var covers local tooling only, so the
    # detail says which of the two this shell can actually see.
    if (Test-EnvValue 'LINEAR_API_KEY') {
        return New-LaneResult -Lane 'linear' -State 'ready' -Method 'env-token' -Gates $false `
            -Detail 'LINEAR_API_KEY is set in this shell (name checked only, value never read); the linear-sync.yml workflow separately needs the repository secret of the same name — verify per the CONNECTIONS_SETUP.md owner checklist (label an issue bug)'
    }
    return New-LaneResult -Lane 'linear' -State 'needs-owner' -Method 'repo-secret' -Gates $false `
        -Detail 'LINEAR_API_KEY is not set (declared by config/connectors.json linear.apiKeyEnv); .github/workflows/linear-sync.yml skips green without the repository secret, so GitHub->Linear issue sync runs dark' `
        -OwnerAction 'gh secret set LINEAR_API_KEY   # value from Linear Settings -> Security & access -> API'
}

# --- slack lane (connector; verify-only, never gates) ----------------------------------
function Test-SlackLane {
    # SLACK_BOT_TOKEN honesty: connectors.json declares it (slack.botTokenEnv) but no
    # workflow or service in the repo consumes it today — setting it changes nothing
    # yet, and the report must not imply otherwise.
    $botTokenState = if (Test-EnvValue 'SLACK_BOT_TOKEN') { 'set in this shell' } else { 'not set' }
    $botTokenNote = "SLACK_BOT_TOKEN ($botTokenState) is declared in config/connectors.json but nothing in the repo consumes it today"
    if (Test-EnvValue 'SLACK_WEBHOOK_URL') {
        return New-LaneResult -Lane 'slack' -State 'ready' -Method 'env-token' -Gates $false `
            -Detail ("SLACK_WEBHOOK_URL is set in this shell (name checked only, value never read); notify-slack.yml separately needs the repository secret of the same name. $botTokenNote")
    }
    return New-LaneResult -Lane 'slack' -State 'needs-owner' -Method 'repo-secret' -Gates $false `
        -Detail ("SLACK_WEBHOOK_URL is not set (declared by config/connectors.json slack.webhookUrlEnv); .github/workflows/notify-slack.yml skips green without the repository secret, so workflow notifications run dark. $botTokenNote") `
        -OwnerAction 'gh secret set SLACK_WEBHOOK_URL   # value from the Slack app incoming-webhook config'
}

# --- sharepoint lane (connector; verify-only, never gates) -----------------------------
function Test-SharePointLane {
    # No headless probe exists that would not itself require a live Graph token: the
    # Graph connector + declarative agent under integrations/m365/ need tenant admin
    # consent, and the tenant session is MFA-bound (AADSTS50078 — the state
    # docs/architecture/ENTERPRISE_AI_CONNECTIONS.md §0 measured). Owner runbook only.
    return New-LaneResult -Lane 'sharepoint' -State 'needs-owner' -Method 'admin-consent' -Gates $false `
        -Detail 'SharePoint/M365 Graph access is owner-gated: integrations/m365/ (Graph connector + declarative agent) needs tenant admin consent, and the tenant session is MFA-bound (AADSTS50078 per docs/architecture/ENTERPRISE_AI_CONNECTIONS.md §0) — no headless probe exists' `
        -OwnerAction 'az login --tenant "349e1399-dccf-45b1-af7e-05d7b0676abf"   # then follow the integrations/m365/README.md admin-consent runbook'
}

# --- azure-devops lane (connector; verify-only, never gates) ---------------------------
function Test-AzureDevOpsLane {
    # Honest baseline: NO Azure DevOps org is configured in this repo today — nothing
    # consumes the extension or the PAT. The lane reports raw material presence so
    # wiring an org later starts from a truthful state, and it prefers pointing at the
    # repo's existing GitHub-OIDC federation pattern over PAT-based auth.
    $azCmd = Get-CliCommand -Name 'az'
    $extPresent = $false
    if ($azCmd) {
        $ext = Invoke-Probe -Executable $azCmd.Source -Arguments @('extension', 'list', '--output', 'tsv', '--query', '[].name')
        if ($ext.ExitCode -eq 0 -and ((@($ext.Output) -join ' ') -match '\bazure-devops\b')) { $extPresent = $true }
    }
    $extState = if (-not $azCmd) { 'az not on PATH' } elseif ($extPresent) { 'installed' } else { 'not installed' }
    $patState = if (Test-EnvValue 'AZURE_DEVOPS_EXT_PAT') { 'set in this shell (name checked only)' } else { 'not set' }
    $baseline = "no Azure DevOps org is configured in this repo today — nothing consumes either; az devops extension: $extState; AZURE_DEVOPS_EXT_PAT: $patState"

    if ($extPresent -and (Test-EnvValue 'AZURE_DEVOPS_EXT_PAT')) {
        return New-LaneResult -Lane 'azure-devops' -State 'ready' -Method 'env-token' -Gates $false `
            -Detail ("raw material present, but $baseline. Wiring an org is future owner-initiated work; prefer the GitHub-OIDC federation pattern (scripts/bootstrap/azure-oidc-setup.ps1) over PATs where ADO supports it")
    }
    return New-LaneResult -Lane 'azure-devops' -State 'unavailable' -Method 'not-configured' -Gates $false `
        -Detail ($baseline + '. Informational only: wiring an org is future owner-initiated work (az extension add --name azure-devops; prefer OIDC federation over PATs where supported)')
}

# --- Diagnose (and, with -Apply, repair), then report ---------------------------------
try {
    Write-Report "== HELIOS auth doctor ($environment, $modeLabel) =="
    Write-Report ''
    Write-Report '-- Lanes (automatic-first; interactive fixes are reported owner actions, never run) --'

    # An explicitly selected profile the hub cannot load aborts BEFORE any lane runs
    # (review finding): diagnosing — and with -Apply, repairing — an invented default
    # profile would report success for a hub that will not start, or demand
    # credentials for lanes that profile never enables.
    $activeConfig = Get-AIHubConfigState
    if ($activeConfig.Explicit -and $null -eq $activeConfig.Config) {
        throw "AIHUB_CONFIG selects '$($activeConfig.Path)' but it is missing, unparseable, or not a JSON object — the hub cannot load that profile either; fix the file or unset AIHUB_CONFIG (no lane was diagnosed or repaired)"
    }

    $ghResult = Test-GhLane
    $azResult = Test-AzLane
    $laneResults = @(
        $ghResult
        $azResult
        Test-CodexLane -AzResult $azResult
        Test-ClaudeLane -AzResult $azResult
        Test-CopilotLane -GhResult $ghResult
        Test-LinearLane
        Test-SlackLane
        Test-SharePointLane
        Test-AzureDevOpsLane
    )

    foreach ($result in $laneResults) {
        Write-Report ('  {0,-13} {1,-12} {2,-18} {3}' -f $result.lane, $result.state, $result.method, $result.detail)
    }

    $readyCount = @($laneResults | Where-Object { $_.state -eq 'ready' }).Count
    $repairedCount = @($laneResults | Where-Object { $_.state -eq 'repaired' }).Count
    $needsOwner = @($laneResults | Where-Object { $_.state -eq 'needs-owner' })
    $unavailableCount = @($laneResults | Where-Object { $_.state -eq 'unavailable' }).Count
    $disabledCount = @($laneResults | Where-Object { $_.state -eq 'disabled' }).Count

    # Exit contract (see .DESCRIPTION): report-only always exits 0 — it diagnosed and
    # mutated nothing, which is exactly what it promised. Only -Apply gates on the
    # outcome, and only GATING needs-owner lanes gate: unavailable means the TOOL is
    # missing (setup-ai-clis.ps1's job, not an auth failure), disabled means the
    # active config instantiates nothing on that lane, and connector lanes
    # (gates=false) are verify-only wiring reports whose fixes are repository secrets
    # or tenant consent — never logins this doctor could have applied.
    $exitCode = 0
    if ($Apply -and @($needsOwner | Where-Object gates).Count -gt 0) { $exitCode = 2 }

    if ($Json) {
        [ordered]@{
            script       = 'scripts/bootstrap/auth-doctor.ps1'
            generatedUtc = (Get-Date).ToUniversalTime().ToString('o')
            mode         = $modeLabel
            environment  = $environment
            lanes        = @($laneResults)
            summary      = [ordered]@{
                ready       = $readyCount
                repaired    = $repairedCount
                needsOwner  = $needsOwner.Count
                unavailable = $unavailableCount
                disabled    = $disabledCount
            }
            exitCode     = $exitCode
        } | ConvertTo-Json -Depth 6
    }
    else {
        Write-Report ''
        $table = $laneResults |
            Format-Table -AutoSize -Property @(
                @{ n = 'Lane'; e = { $_.lane } }
                @{ n = 'State'; e = { $_.state } }
                @{ n = 'Method'; e = { $_.method } }
                @{ n = 'Owner action (exact command)'; e = { $_.ownerAction } }
                @{ n = 'Detail'; e = { $_.detail } }
            ) |
            Out-String -Width 4096
        Write-Report $table.TrimEnd()

        Write-Report ''
        $gating = $laneResults.Count - $unavailableCount - $disabledCount
        $summary = "Auth lanes: $($readyCount + $repairedCount)/$gating ready or repaired"
        if ($needsOwner.Count -gt 0) {
            $summary += ' — needs-owner: ' + (@($needsOwner | ForEach-Object lane) -join ', ')
        }
        if ($unavailableCount -gt 0) { $summary += "; unavailable (never gates): $unavailableCount" }
        if ($disabledCount -gt 0) { $summary += "; disabled in the active config (never gates): " + (@($laneResults | Where-Object { $_.state -eq 'disabled' } | ForEach-Object lane) -join ', ') }
        if (-not $Apply) {
            $summary += ' [report-only: nothing was mutated, exit 0 by contract — rerun with -Apply for automatic non-interactive repair]'
        }
        Write-Report $summary
    }

    exit $exitCode
}
catch {
    # Internal failure — distinct from "a lane needs the owner" (2) so callers can
    # tell a broken doctor from a broken login.
    [Console]::Error.WriteLine("auth-doctor: internal failure — $($_.Exception.Message)")
    exit 1
}
