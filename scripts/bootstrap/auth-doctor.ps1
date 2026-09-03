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
# Environment-variable NAME semantics follow the OS (review finding): case-sensitive on
# Linux/macOS (MODEL_KEY and model_key are two variables ProviderFactory reads
# literally), case-insensitive on Windows. Name comparisons and indexes use this
# comparer — never -eq / [ordered] hashtables, which would merge two Unix variables.
$script:EnvNameComparer = if ($IsWindows) { [System.StringComparer]::OrdinalIgnoreCase } else { [System.StringComparer]::Ordinal }
function Test-EnvNameEquals { param([string]$A, [string]$B) return $script:EnvNameComparer.Equals($A, $B) }

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
        # Literal value (review finding): AIHubService.ResolveConfigPath hands it to
        # File.OpenRead untouched, so a padded value names a different file for the hub.
        $path = [string]$env:AIHUB_CONFIG
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
    # ProvidersNull = an EXPLICIT `"providers": null` (review finding): System.Text.Json
    # assigns it over AIHubOptions.Providers' initializer and CreateAll fails
    # enumerating it — the hub cannot start on that file, so the main flow aborts too.
    $providersNull = $false
    $providersShape = ''
    if ($null -ne $config) {
        $providersProp = $config.PSObject.Properties['providers']
        $providersNull = [bool]($null -ne $providersProp -and $null -eq $providersProp.Value)
        # Only a JSON OBJECT binds (review finding): AIHubOptions.Load deserializes the
        # section as Dictionary<string, ProviderOptions>, so an array, string, or number
        # fails the hub exactly like null — the main flow aborts on it the same way.
        if ($null -ne $providersProp -and $null -ne $providersProp.Value -and $providersProp.Value -isnot [System.Management.Automation.PSCustomObject]) {
            $providersShape = if ($providersProp.Value -is [System.Array]) { 'an array' } else { "a $($providersProp.Value.GetType().Name)" }
        }
        # Every ENTRY must be an object too (review finding): a JSON null deserializes
        # as a null entry and ProviderFactory.CreateAll dereferences provider.Enabled
        # on each, so the hub crashes on such a file exactly like on a null table.
        elseif ($null -ne $providersProp -and $null -ne $providersProp.Value) {
            foreach ($entryProp in $providersProp.Value.PSObject.Properties) {
                if ($null -eq $entryProp.Value -or $entryProp.Value -isnot [System.Management.Automation.PSCustomObject]) {
                    $entryShape = if ($null -eq $entryProp.Value) { 'null' } elseif ($entryProp.Value -is [System.Array]) { 'an array' } else { "a $($entryProp.Value.GetType().Name)" }
                    $providersShape = "an object whose entry providers.$($entryProp.Name) is $entryShape (not an object)"
                    break
                }
            }
        }
    }
    # The OTHER typed sections (review finding): cliAgents binds List<CliAgentOptions>
    # (ProviderFactory.CreateAll enumerates it and dereferences every element), routing
    # and learning bind objects (AIHubOptions.Load dereferences learning.localPath; the
    # hub's constructor and RoutingTableView read routing, defaultChain as a list and
    # taskRouting as a dictionary of lists). System.Text.Json rejects a wrong shape and
    # an explicit null lands on the property, so either fails the hub — the main flow
    # aborts on SectionShape exactly as on ProvidersShape. Absent sections keep their
    # initializers and are fine. Same rules as auto-login.ps1's step 0.
    $sectionShape = ''
    if ($null -ne $config) {
        $shapeOf = {
            param($v)
            if ($null -eq $v) { 'null' } elseif ($v -is [System.Array]) { 'an array' } elseif ($v -is [System.Management.Automation.PSCustomObject]) { 'an object' } elseif ($v -is [string]) { 'a JSON string' } elseif ($v -is [bool]) { 'a JSON boolean' } else { 'a JSON number' }
        }
        # Typed MEMBERS bind too (review finding): System.Text.Json rejects a JSON
        # string where AIHubOptions declares a bool or an int, a non-integer number for
        # an int, and null for a non-nullable bool / int; a string member accepts a
        # string or null, except provider.type (CreateAll dereferences it) and
        # learning.localPath (Load dereferences it). Same rules as auto-login's step 0.
        $memberSchemas = @{
            provider = @{ type = 'string!'; enabled = 'bool'; model = 'string'; apiKeyEnv = 'string'; apiKeySecretName = 'string'; endpointEnv = 'string'; baseUrl = 'string' }
            cliAgent = @{ name = 'string'; enabled = 'bool'; command = 'string'; argsTemplate = 'string'; model = 'string'; timeoutSeconds = 'int' }
            learning = @{ enabled = 'bool'; mode = 'string'; localPath = 'string!'; tableEndpointEnv = 'string'; adaptiveRouting = 'bool'; historyWindow = 'int' }
        }
        $memberProblem = {
            param($obj, [hashtable]$schema, [string]$path)
            foreach ($m in $obj.PSObject.Properties) {
                $kind = $schema[$m.Name]
                if (-not $kind) { continue }
                $v = $m.Value
                $ok = switch ($kind) {
                    'string' { ($null -eq $v) -or ($v -is [string]) }
                    'string!' { $v -is [string] }
                    'bool' { $v -is [bool] }
                    'int' { (($v -is [int]) -or ($v -is [long])) -and $v -ge [int]::MinValue -and $v -le [int]::MaxValue }
                }
                if (-not $ok) {
                    $expected = switch ($kind) { 'string' { 'a string' } 'string!' { 'a non-null string' } 'bool' { 'true or false' } 'int' { 'an integer' } }
                    return "$path.$($m.Name) as $(& $shapeOf $v), not $expected"
                }
            }
            return ''
        }
        $chainProblem = {
            param([object[]]$chain, [string]$path)
            $i = 0
            foreach ($e in $chain) { if ($e -isnot [string]) { return "$path[$i] as $(& $shapeOf $e), not a provider name (string)" }; $i++ }
            return ''
        }
        foreach ($rule in @(@{ Name = 'cliAgents'; Wanted = 'an array' }, @{ Name = 'routing'; Wanted = 'an object' }, @{ Name = 'learning'; Wanted = 'an object' })) {
            $sectionProp = $config.PSObject.Properties[$rule.Name]
            if ($null -eq $sectionProp) { continue }
            $shape = & $shapeOf $sectionProp.Value
            if ($shape -ne $rule.Wanted) { $sectionShape = "`"$($rule.Name)`" as $shape, not $($rule.Wanted)"; break }
            if ($rule.Name -eq 'cliAgents') {
                $cliIndex = 0
                foreach ($element in @($sectionProp.Value)) {
                    if ($null -eq $element -or $element -isnot [System.Management.Automation.PSCustomObject]) { $sectionShape = "cliAgents[$cliIndex] as $(& $shapeOf $element), not an object"; break }
                    $sectionShape = & $memberProblem $element $memberSchemas.cliAgent "cliAgents[$cliIndex]"
                    if ($sectionShape) { break }
                    $cliIndex++
                }
            }
            elseif ($rule.Name -eq 'learning') {
                $sectionShape = & $memberProblem $sectionProp.Value $memberSchemas.learning 'learning'
            }
            elseif ($rule.Name -eq 'routing') {
                $chainProp = $sectionProp.Value.PSObject.Properties['defaultChain']
                if ($null -ne $chainProp -and (& $shapeOf $chainProp.Value) -ne 'an array') { $sectionShape = "routing.defaultChain as $(& $shapeOf $chainProp.Value), not an array" }
                elseif ($null -ne $chainProp) { $sectionShape = & $chainProblem @($chainProp.Value) 'routing.defaultChain' }
                $tableProp = $sectionProp.Value.PSObject.Properties['taskRouting']
                if (-not $sectionShape -and $null -ne $tableProp) {
                    if ((& $shapeOf $tableProp.Value) -ne 'an object') { $sectionShape = "routing.taskRouting as $(& $shapeOf $tableProp.Value), not an object" }
                    else {
                        foreach ($chainEntry in $tableProp.Value.PSObject.Properties) {
                            if ((& $shapeOf $chainEntry.Value) -ne 'an array') { $sectionShape = "routing.taskRouting.$($chainEntry.Name) as $(& $shapeOf $chainEntry.Value), not an array"; break }
                            $sectionShape = & $chainProblem @($chainEntry.Value) "routing.taskRouting.$($chainEntry.Name)"
                            if ($sectionShape) { break }
                        }
                    }
                }
            }
            if ($sectionShape) { break }
        }
        # Provider entry members, once the table itself is well-shaped.
        if (-not $sectionShape -and -not $providersShape -and -not $providersNull) {
            $providersProp = $config.PSObject.Properties['providers']
            if ($null -ne $providersProp -and $null -ne $providersProp.Value) {
                foreach ($entryProp in $providersProp.Value.PSObject.Properties) {
                    $sectionShape = & $memberProblem $entryProp.Value $memberSchemas.provider "providers.$($entryProp.Name)"
                    if ($sectionShape) { break }
                }
            }
        }
    }
    $script:aihubConfigState = [pscustomobject]@{ Label = $label; Path = $path; Config = $config; Explicit = $explicit; ProvidersNull = $providersNull; ProvidersShape = $providersShape; SectionShape = $sectionShape }
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
        # Exactly as ProviderFactory.Create dispatches (review finding): case-folded,
        # never trimmed — a padded type is an unknown provider that reads no key.
        $provType = if ($prov.PSObject.Properties['type']) { [string]$prov.type } else { '' }
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
# to the default would demand a variable the hub never reads. Conflicting secret
# mappings are NOT decided here — Get-AIHubSecretConflicts sees every type at once.
function Get-ProviderCredentialPairs {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Entries,
        [Parameter(Mandatory)][string]$DefaultEnv
    )
    $pairs = [System.Collections.Generic.List[object]]::new()
    $blank = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $Entries) {
        $prov = $entry.Value
        $envProp = $prov.PSObject.Properties['apiKeyEnv']
        # LITERAL name (review finding): blank is detected with IsNullOrWhiteSpace — the
        # only normalization SecretResolver applies — and any other value is checked
        # exactly as declared, whitespace included, because the factory hands it to
        # Environment.GetEnvironmentVariable untouched (" KEY " is not KEY).
        $declaredEnv = if ($null -eq $envProp -or $null -eq $envProp.Value) { $DefaultEnv } elseif ([string]::IsNullOrWhiteSpace([string]$envProp.Value)) { '' } else { [string]$envProp.Value }
        # Literal (review finding): SecretResolver.Resolve hands apiKeySecretName to
        # GetSecret exactly as written, so a padded name is the invalid name the hub
        # requests — Get-BlankVaultChecks reports it instead of proving a trimmed one.
        $declaredVault = if ($prov.PSObject.Properties['apiKeySecretName']) { [string]$prov.apiKeySecretName } else { '' }
        if ($declaredEnv -eq '') {
            $blank.Add([pscustomobject]@{ Name = $entry.Name; SecretName = $declaredVault })
            continue
        }
        if (-not @($pairs | Where-Object { Test-EnvNameEquals $_.Env $declaredEnv }).Count) {
            $pairs.Add([pscustomobject]@{ Env = $declaredEnv; SecretName = $declaredVault; Name = $entry.Name })
        }
    }
    return [pscustomobject]@{ Pairs = $pairs; Blank = $blank }
}
# The public GitHub Models endpoint is exactly the HTTPS origin of models.github.ai
# (review finding); anything else is its own custom endpoint. Returns { Public; Host }.
function Test-PublicModelsOrigin {
    param([AllowEmptyString()][string]$BaseUrl = '')
    if ([string]::IsNullOrWhiteSpace($BaseUrl)) { return [pscustomobject]@{ Public = $true; Host = 'models.github.ai' } }
    $parsedOrigin = $null
    if (-not [uri]::TryCreate($BaseUrl.Trim(), [System.UriKind]::Absolute, [ref]$parsedOrigin)) { return [pscustomobject]@{ Public = $false; Host = '' } }
    # Default port only (review finding): https://models.github.ai:444 is another origin.
    $isPublic = ($parsedOrigin.Scheme -eq 'https' -and $parsedOrigin.Host.Equals('models.github.ai', [System.StringComparison]::OrdinalIgnoreCase) -and $parsedOrigin.IsDefaultPort)
    $originHost = if ($parsedOrigin.IsDefaultPort) { $parsedOrigin.Host } else { "$($parsedOrigin.Host):$($parsedOrigin.Port)" }
    return [pscustomobject]@{ Public = $isPublic; Host = $originHost }
}
# Variable-level config defects across EVERY enabled consumer (review findings): built
# once from the whole providers table PLUS the enabled CLI agents (a codex entry reads
# the fixed OPENAI_API_KEY, a claude entry ANTHROPIC_API_KEY), cached, returned as a
# plain array of { Kind; Env; Readers[{ Name; Type; Family; SecretName }]; Secrets }.
#   conflict     — readers name DIFFERENT Key Vault secrets for one variable, so
#                  declaration order would choose the credential every sharer reads.
#   incompatible — readers belong to different credential FAMILIES (OpenAI, Anthropic,
#                  Azure OpenAI, the public GitHub Models origin, each custom endpoint),
#                  so no single value can be valid for all of them and a preset or
#                  exported value would reach the wrong service. A per-type view sees
#                  neither, and would report both lanes ready on such a value.
# Every enabled reader of every variable, from the whole providers table PLUS the
# enabled CLI agents (review findings), cached: { Name; Type; Family; SecretName } per
# variable under the OS name comparer. Get-AIHubVariableDefects derives the conflict /
# incompatible verdicts from it; the gh and copilot lanes ask it who owns the fixed
# GitHub variables.
$script:aihubEnvReaders = $null
function Get-AIHubEnvReaders {
    if ($null -ne $script:aihubEnvReaders) { return $script:aihubEnvReaders }
    $readers = [System.Collections.Generic.Dictionary[string, object]]::new($script:EnvNameComparer)
    $cfg = (Get-AIHubConfigState).Config
    if ($null -ne $cfg) {
        if ($cfg.PSObject.Properties['providers'] -and $null -ne $cfg.providers) {
            foreach ($prop in $cfg.providers.PSObject.Properties) {
                $prov = $prop.Value
                if ($null -eq $prov) { continue }
                if ($prov.PSObject.Properties['enabled'] -and $prov.enabled -eq $false) { continue }
                $provType = if ($prov.PSObject.Properties['type']) { ([string]$prov.type).ToLowerInvariant() } else { '' }   # untrimmed, like the factory
                $typeDefault = switch ($provType) {
                    'openai' { 'OPENAI_API_KEY' }
                    'anthropic' { 'ANTHROPIC_API_KEY' }
                    'github-models' { 'GITHUB_MODELS_TOKEN' }
                    'azure-openai' { 'AZURE_OPENAI_API_KEY' }
                    default { '' }
                }
                if (-not $typeDefault) { continue }
                $envProp = $prov.PSObject.Properties['apiKeyEnv']
                # Literal name, blank via IsNullOrWhiteSpace only (review finding — see
                # Get-ProviderCredentialPairs).
                $envName = if ($null -eq $envProp -or $null -eq $envProp.Value) { $typeDefault } elseif ([string]::IsNullOrWhiteSpace([string]$envProp.Value)) { '' } else { [string]$envProp.Value }
                if (-not $envName) { continue }
                $secretName = if ($prov.PSObject.Properties['apiKeySecretName']) { [string]$prov.apiKeySecretName } else { '' }   # literal (review finding)
                $family = $provType
                if ($provType -eq 'github-models') {
                    $baseUrl = if ($prov.PSObject.Properties['baseUrl'] -and $null -ne $prov.baseUrl) { ([string]$prov.baseUrl).Trim() } else { '' }
                    $origin = Test-PublicModelsOrigin -BaseUrl $baseUrl
                    $family = if ($origin.Public) { 'github' } else { "custom-endpoint:$($origin.Host)" }
                }
                if (-not $readers.ContainsKey($envName)) { $readers[$envName] = [System.Collections.Generic.List[object]]::new() }
                $readers[$envName].Add([pscustomobject]@{ Name = $prop.Name; Type = $provType; Family = $family; SecretName = $secretName })
            }
        }
        # CLI readers, discovered by configured command exactly like the lanes are.
        if ($cfg.PSObject.Properties['cliAgents'] -and $null -ne $cfg.cliAgents) {
            foreach ($agent in @($cfg.cliAgents)) {
                if ($null -eq $agent) { continue }
                if ($agent.PSObject.Properties['enabled'] -and $agent.enabled -eq $false) { continue }
                # The configured COMMAND alone (review finding): CliProcessAgent runs
                # options.Command as written and IsOnPath('') is false, so an entry
                # without a command is unconfigured whatever its name says; untrimmed too.
                $cmd = if ($agent.PSObject.Properties['command'] -and $null -ne $agent.command) { [string]$agent.command } else { '' }
                $leaf = ''
                if ($cmd) { try { $leaf = [System.IO.Path]::GetFileNameWithoutExtension($cmd) } catch { $leaf = $cmd } }
                $agentName = if ($agent.PSObject.Properties['name'] -and $null -ne $agent.name) { ([string]$agent.name).Trim() } else { '' }
                $key = if ($leaf) { $leaf.ToLowerInvariant() } else { '' }
                $cliReaders = @()
                if ($key -eq 'codex') { $cliReaders = @([pscustomobject]@{ Name = $agentName; Type = 'codex-cli'; Family = 'openai'; SecretName = ''; Env = 'OPENAI_API_KEY' }) }
                elseif ($key -in 'claude', 'claude-cli') { $cliReaders = @([pscustomobject]@{ Name = $agentName; Type = 'claude-cli'; Family = 'anthropic'; SecretName = ''; Env = 'ANTHROPIC_API_KEY' }) }
                # copilot / gh inherit GH_TOKEN and GITHUB_TOKEN as GitHub credentials
                # (review finding): a non-GitHub provider mapping a secret to either name
                # is an incompatible sharing, so auto-login pulls nothing into it.
                elseif ($key -in 'copilot', 'gh', 'gh-models') {
                    $cliType = if ($key -eq 'copilot') { 'copilot-cli' } else { 'gh-cli' }
                    $cliReaders = @(@('GH_TOKEN', 'GITHUB_TOKEN') | ForEach-Object { [pscustomobject]@{ Name = $agentName; Type = $cliType; Family = 'github'; SecretName = ''; Env = $_ } })
                }
                foreach ($cliReader in $cliReaders) {
                    if (-not $readers.ContainsKey($cliReader.Env)) { $readers[$cliReader.Env] = [System.Collections.Generic.List[object]]::new() }
                    $readers[$cliReader.Env].Add($cliReader)
                }
            }
        }
    }
    $script:aihubEnvReaders = $readers
    return $script:aihubEnvReaders
}
# The fixed GitHub variables (GH_TOKEN / GITHUB_TOKEN) that an enabled NON-GitHub
# consumer reads as its apiKeyEnv (review finding): their value is that service's
# key — auto-login may have exported it there — and `gh` would send it to github.com
# as a token, so the gh and copilot lanes screen them out and never pass them to gh.
# rest-connect.ps1 applies the same rule to its candidates.
function Get-NonGitHubOwnedTokenNames {
    $readers = Get-AIHubEnvReaders
    $owned = [System.Collections.Generic.List[string]]::new()
    foreach ($fixedName in @('GH_TOKEN', 'GITHUB_TOKEN')) {
        if (-not $readers.ContainsKey($fixedName)) { continue }
        $foreign = @($readers[$fixedName] | Where-Object { $_.Family -ne 'github' })
        if ($foreign.Count -gt 0) { $owned.Add($fixedName) }
    }
    return $owned.ToArray()
}
$script:aihubVariableDefects = $null
function Get-AIHubVariableDefects {
    if ($null -ne $script:aihubVariableDefects) { return $script:aihubVariableDefects }
    $defects = [System.Collections.Generic.List[object]]::new()
    $readers = Get-AIHubEnvReaders
    foreach ($envName in @($readers.Keys)) {
        $families = @($readers[$envName] | ForEach-Object { $_.Family } | Select-Object -Unique)
        # Key Vault secret names are case-insensitive: folded before the distinct count.
        $secrets = @($readers[$envName] | ForEach-Object { $_.SecretName } | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique)
        if ($families.Count -gt 1) {
            $defects.Add([pscustomobject]@{ Kind = 'incompatible'; Env = $envName; Readers = @($readers[$envName]); Secrets = $secrets })
        }
        elseif ($secrets.Count -gt 1) {
            $defects.Add([pscustomobject]@{ Kind = 'conflict'; Env = $envName; Readers = @($readers[$envName]); Secrets = $secrets })
        }
    }
    $script:aihubVariableDefects = $defects.ToArray()
    return $script:aihubVariableDefects
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
        $readerText = (@($conflict.Readers | ForEach-Object { "'$($_.Name)' ($($_.Type))" }) -join ', ')
        $readerNames = (@($conflict.Readers | ForEach-Object Name) -join ',')
        if ($conflict.Kind -eq 'incompatible') {
            # Same wording as auto-login's action, so a merged summary dedupes it.
            $details += "$($conflict.Env) is read by consumers of different credential families ($readerText) — no single value is valid for all of them, so a preset or exported value would reach the wrong service through SecretResolver's environment-first rule (auto-login pulls and exports nothing into it)"
            $actions += "give the consumers sharing $($conflict.Env) distinct apiKeyEnv names in ${ConfigLabel} ($readerNames) — they read credentials for different services"
        }
        else {
            # The split applies to the entries that NAME the secrets; a CLI reader or a
            # secretless entry on the same variable is affected but has no
            # apiKeySecretName to change (same names as auto-login's action → dedupe).
            $secretReaders = @($conflict.Readers | Where-Object { $_.SecretName })
            $secretReaderText = (@($secretReaders | ForEach-Object { "'$($_.Name)' ($($_.Type))" }) -join ', ')
            $secretReaderNames = (@($secretReaders | ForEach-Object Name) -join ',')
            $otherReaders = @($conflict.Readers | Where-Object { -not $_.SecretName } | ForEach-Object { "'$($_.Name)' ($($_.Type))" })
            $otherNote = if ($otherReaders.Count -gt 0) { "; $($otherReaders -join ', ') read(s) the same variable and would receive whichever value landed" } else { '' }
            $details += "providers $secretReaderText map different Key Vault secrets $(& $quote $conflict.Secrets) to the same variable $($conflict.Env) — SecretResolver prefers the environment, so whichever secret were pulled first would be handed to every sharer (auto-login pulls none of them)$otherNote"
            $actions += "give providers.{$secretReaderNames} distinct apiKeyEnv names in ${ConfigLabel} (or one shared apiKeySecretName)"
        }
    }
    return [pscustomobject]@{ HasDefects = ($details.Count -gt 0); DefectDetail = ($details -join '; '); DefectAction = ($actions -join '; ') }
}
# Existence proof for a blank-apiKeyEnv entry's Key Vault secret (review finding):
# readiness is never inferred from having nothing to inspect. The proof is metadata
# only — `az keyvault secret list` returns names, never values — under the az lane's
# own login; anything short of a listed name is unproven and reported as the exact
# prerequisite that is missing (vault URI, az lane, RBAC, or the secret itself).
# The credential DefaultAzureCredential will select for the hub (review findings): the
# environment service principal (AZURE_CLIENT_ID + secret / certificate), then a
# workload identity, then a managed identity, and only then the az CLI cache — and a
# configured credential that FAILS is not rescued by the next one. Names checked only.
# Raw IMDS (review finding): a VM's system-assigned or attached identity declares
# NEITHER IDENTITY_ENDPOINT nor MSI_ENDPOINT — ManagedIdentityCredential reaches it at
# http://169.254.169.254/metadata/identity/oauth2/token and DefaultAzureCredential takes
# that token BEFORE the az CLI cache, so the absence of the variables proves nothing.
# IMDS is probed the way the SDK does it (Metadata: true, hard 2 s, never through a
# proxy, no redirects); a 200 carrying a token means the hub authenticates as that
# identity. The token is discarded, never stored; the result is cached per run.
$script:imdsManagedIdentity = $null
function Test-RawImdsManagedIdentity {
    if ($null -ne $script:imdsManagedIdentity) { return $script:imdsManagedIdentity }
    $imdsHasIdentity = $false
    try {
        $imdsReply = Invoke-WebRequest -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net' -Headers @{ Metadata = 'true' } -TimeoutSec 2 -NoProxy -MaximumRedirection 0 -SkipHttpErrorCheck -UserAgent 'helios-auth-doctor'
        if ([int]$imdsReply.StatusCode -eq 200) {
            $imdsJson = $null
            try { $imdsJson = ([string]$imdsReply.Content) | ConvertFrom-Json } catch { $imdsJson = $null }
            $imdsHasIdentity = ($null -ne $imdsJson -and $imdsJson.PSObject.Properties['access_token'] -and -not [string]::IsNullOrWhiteSpace([string]$imdsJson.access_token))
            $imdsJson = $null
        }
        $imdsReply = $null
    }
    catch { $imdsHasIdentity = $false }
    $script:imdsManagedIdentity = $imdsHasIdentity
    return $script:imdsManagedIdentity
}
function Get-HubCredentialKind {
    if ((Test-EnvValue 'AZURE_CLIENT_ID') -and (Test-EnvValue 'AZURE_TENANT_ID') -and ((Test-EnvValue 'AZURE_CLIENT_SECRET') -or (Test-EnvValue 'AZURE_CLIENT_CERTIFICATE_PATH'))) { return 'environment service principal' }
    if ((Test-EnvValue 'AZURE_FEDERATED_TOKEN_FILE') -and (Test-EnvValue 'AZURE_CLIENT_ID')) { return 'workload identity' }
    if ((Test-EnvValue 'IDENTITY_ENDPOINT') -or (Test-EnvValue 'MSI_ENDPOINT')) { return 'managed identity' }
    if (Test-RawImdsManagedIdentity) { return 'managed identity' }
    return 'az-cli'
}
# Where a selected managed identity comes from, for the report text only.
function Get-HubManagedIdentitySource {
    if ((Test-EnvValue 'IDENTITY_ENDPOINT') -or (Test-EnvValue 'MSI_ENDPOINT')) { return 'IDENTITY_ENDPOINT / MSI_ENDPOINT' }
    return 'raw IMDS at 169.254.169.254 — a system-assigned or VM-attached identity, no endpoint variable'
}
# The canonical Key Vault ORIGIN only (review finding): SecretResolver builds its
# SecretClient from AZURE_KEY_VAULT_URI as written, so https://<vault>.vault.azure.net:444/
# or a URI carrying a path, query, fragment or userinfo is a different (unusable)
# endpoint for the hub even though its host names a real vault — deriving a vault
# name from it would prove a secret at an endpoint the hub never calls. Returns the
# vault name for https://<vault>.vault.<public or sovereign suffix>/ on the default
# port with no path beyond '/', else ''.
function Get-KeyVaultNameFromUri {
    param([AllowEmptyString()][string]$Value)
    $parsed = $null
    if ([string]::IsNullOrWhiteSpace($Value) -or -not [uri]::TryCreate($Value.Trim(), [System.UriKind]::Absolute, [ref]$parsed)) { return '' }
    if ($parsed.Scheme -ne 'https' -or -not $parsed.IsDefaultPort -or $parsed.UserInfo -or $parsed.Query -or $parsed.Fragment) { return '' }
    if ($parsed.AbsolutePath -notin '', '/') { return '' }
    if ($parsed.Host -notmatch '^(?<vault>[A-Za-z0-9-]{3,24})\.vault\.(azure\.net|azure\.cn|usgovcloudapi\.net|microsoftazure\.de)$') { return '' }
    return $Matches['vault']
}
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
    $vaultName = Get-KeyVaultNameFromUri -Value $vaultUri
    $azCmd = Get-CliCommand -Name 'az'
    $blocker = ''
    $blockerHint = ''
    if (-not $vaultUri) {
        $blocker = 'AZURE_KEY_VAULT_URI is unset, so the hub cannot reach any vault'
        $blockerHint = 'set AZURE_KEY_VAULT_URI (PowerShell: . .helios/azure.env.ps1; bash: source .helios/azure.env)'
    }
    elseif (-not $vaultName) {
        $blocker = 'AZURE_KEY_VAULT_URI is not the canonical https://<vault>.vault.azure.net/ (or sovereign-cloud) Key Vault origin — default port, no path, query, fragment or userinfo — which is what SecretResolver builds its client from'
        $blockerHint = 'fix AZURE_KEY_VAULT_URI'
    }
    elseif ($AzResult.state -notin 'ready', 'repaired' -or -not $azCmd) {
        $blocker = "the az lane is $($AzResult.state), so the secret cannot be listed from here"
        $blockerHint = if ("$($AzResult.ownerAction)".Trim()) { "$($AzResult.ownerAction)" } else { 'repair the az lane (see its row), then re-run' }
    }
    $listed = @()
    if (-not $blocker) {
        # Enabled secrets only (review finding): a disabled secret is still listed by
        # name, but SecretResolver's GetSecret cannot read it — presence means usable.
        $listProbe = Invoke-Probe -Executable $azCmd.Source -Arguments @('keyvault', 'secret', 'list', '--vault-name', $vaultName, '--query', '[?attributes.enabled].name', '--output', 'tsv', '--only-show-errors')
        if ($listProbe.ExitCode -eq 0) { $listed = @(@($listProbe.Output) | ForEach-Object { "$_".Trim() } | Where-Object { $_ }) }
        else {
            $blocker = "az keyvault secret list against vault '$vaultName' failed (exit $($listProbe.ExitCode): no RBAC grant, network, or wrong vault; output never echoed)"
            $blockerHint = "grant the running identity 'Key Vault Secrets User' on vault '$vaultName' (or fix AZURE_KEY_VAULT_URI)"
        }
    }
    # The principal that LISTED is not necessarily the principal that READS (review
    # finding): SecretResolver builds its client on DefaultAzureCredential, which
    # prefers the environment service principal (AZURE_CLIENT_ID + secret /
    # certificate), then a workload identity, then a managed identity, and only then
    # the az CLI cache this probe runs under. When the hub would authenticate as one
    # of those and az is not logged in as that same principal, a listed name proves
    # nothing about the hub's access — presence is reported unverifiable with the gap.
    $principalGap = ''
    $principalHint = ''
    if (-not $blocker -and $listed.Count -gt 0) {
        $hubCredential = Get-HubCredentialKind
        if ($hubCredential -ne 'az-cli') {
            $accountProbe = Invoke-Probe -Executable $azCmd.Source -Arguments @('account', 'show', '--query', '{type:user.type,name:user.name}', '--output', 'json', '--only-show-errors')
            $account = $null
            if ($accountProbe.ExitCode -eq 0) { try { $account = (@($accountProbe.Output) -join '') | ConvertFrom-Json } catch { $account = $null } }
            $accountType = if ($null -ne $account -and $account.PSObject.Properties['type'] -and $null -ne $account.type) { [string]$account.type } else { '' }
            $accountName = if ($null -ne $account -and $account.PSObject.Properties['name'] -and $null -ne $account.name) { [string]$account.name } else { '' }
            $samePrincipal = ($hubCredential -ne 'managed identity') -and ($accountType -eq 'servicePrincipal') -and $accountName.Equals(([string][Environment]::GetEnvironmentVariable('AZURE_CLIENT_ID')).Trim(), [System.StringComparison]::OrdinalIgnoreCase)
            if (-not $samePrincipal) {
                $principalGap = "listed as enabled in vault '$vaultName' for the cached az identity, but the hub's DefaultAzureCredential authenticates as the $hubCredential" + $(if ($hubCredential -eq 'managed identity') { " ($(Get-HubManagedIdentitySource))" } else { ' (AZURE_CLIENT_ID)' }) + ' — access for that principal is not proven from here'
                $principalHint = "grant that principal 'Key Vault Secrets User' on vault '$vaultName' (az role assignment create — owner-gated), or run pwsh scripts/bootstrap/auth-doctor.ps1 -Apply so az logs in as the same service principal, then re-run"
            }
        }
    }
    foreach ($entry in $Blank) {
        # An invalid NAME is a config defect before any vault question (review
        # finding): Key Vault secret names are letters, digits and hyphens (1-127) and
        # SecretResolver requests the string exactly as written, so " openai-api-key "
        # is a request Key Vault rejects — proving the trimmed name would prove a
        # secret the hub never asks for.
        if ($entry.SecretName -notmatch '^[0-9A-Za-z-]{1,127}$') {
            $results.Add([pscustomobject]@{ Name = $entry.Name; SecretName = $entry.SecretName; Status = 'invalid'; Reason = "'$($entry.SecretName)' is not a valid Key Vault secret name (letters, digits and hyphens, 1-127 characters; no surrounding whitespace) — SecretResolver requests it exactly as written and Key Vault rejects it"; Hint = "fix providers.$($entry.Name).apiKeySecretName in $((Get-AIHubConfigState).Label): '$($entry.SecretName)' is not a valid Key Vault secret name — use letters, digits and hyphens only, no surrounding whitespace"; Vault = $vaultName })
            continue
        }
        if ($blocker) {
            $results.Add([pscustomobject]@{ Name = $entry.Name; SecretName = $entry.SecretName; Status = 'unverifiable'; Reason = $blocker; Hint = $blockerHint; Vault = $vaultName })
        }
        elseif ($listed -contains $entry.SecretName) {
            if ($principalGap) {
                $results.Add([pscustomobject]@{ Name = $entry.Name; SecretName = $entry.SecretName; Status = 'unverifiable'; Reason = $principalGap; Hint = $principalHint; Vault = $vaultName })
            }
            else {
                # A listing proves the NAME, not the value (review finding): the hub calls
                # SecretClient.GetSecret, which needs secrets/get — an identity holding
                # only list/metadata rights leaves the provider unconfigured. The get is
                # non-outputting: `--query id` returns the secret identifier URL only, and
                # even that is never printed.
                $getProbe = Invoke-Probe -Executable $azCmd.Source -Arguments @('keyvault', 'secret', 'show', '--vault-name', $vaultName, '--name', $entry.SecretName, '--query', 'id', '--output', 'tsv', '--only-show-errors')
                if ($getProbe.ExitCode -eq 0 -and ((@($getProbe.Output) -join '') -match '^https://')) {
                    $results.Add([pscustomobject]@{ Name = $entry.Name; SecretName = $entry.SecretName; Status = 'present'; Reason = "listed as enabled in vault '$vaultName' and its value is readable by the az identity (non-outputting get: secret id only, never printed)"; Hint = ''; Vault = $vaultName })
                }
                else {
                    $results.Add([pscustomobject]@{ Name = $entry.Name; SecretName = $entry.SecretName; Status = 'unreadable'; Reason = "listed as enabled in vault '$vaultName' but its VALUE is not readable by the az identity (az keyvault secret show exited $($getProbe.ExitCode); output never echoed) — SecretClient.GetSecret needs secrets/get, so the hub would stay unconfigured"; Hint = "grant the running identity 'Key Vault Secrets User' on vault '$vaultName' (az role assignment create — owner-gated), then re-run"; Vault = $vaultName })
                }
            }
        }
        else {
            $results.Add([pscustomobject]@{ Name = $entry.Name; SecretName = $entry.SecretName; Status = 'absent'; Reason = "not present (or disabled) in vault '$vaultName'"; Hint = "az keyvault secret set --vault-name $vaultName --name $($entry.SecretName)   # owner supplies the value (or re-enable the existing secret)"; Vault = $vaultName })
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
        [Parameter(Mandatory)][pscustomobject]$AzResult,
        [string[]]$OwnerTypes = @()
    )
    $pairs = [System.Collections.Generic.List[object]]::new()
    $blank = [System.Collections.Generic.List[object]]::new()
    # Variable defects come from the whole-config map (review findings: cross-type
    # conflicts and incompatible families, CLI readers included) and are reported by
    # every lane that owns one of the readers — the API type or this lane's CLI agent.
    if ($OwnerTypes.Count -eq 0) { $OwnerTypes = @($Type) }
    $conflicts = @(Get-AIHubVariableDefects | Where-Object { @($_.Readers | Where-Object { $_.Type -in $OwnerTypes }).Count -gt 0 })
    $nameSource = "fallback defaults; $ConfigLabel was unreadable"
    if ($null -ne $Providers) {
        $derived = Get-ProviderCredentialPairs -Entries @($Providers) -DefaultEnv $DefaultEnv
        $pairs = $derived.Pairs
        $blank = $derived.Blank
        $names = @($Providers | ForEach-Object Name) -join ','
        $nameSource = if ($pairs.Count -gt 0) { "$ConfigLabel providers.{$names}.apiKeyEnv (type $Type; $DefaultEnv where the property is absent)" }
        elseif ($blank.Count -gt 0) { "$ConfigLabel providers.{$names}.apiKeyEnv (type $Type; every enabled entry declares a blank apiKeyEnv, so the hub reads no variable for them)" }
        else { $CliOnlySource }
    }
    # The built-in pair applies only when NO enabled entry exists to derive from — a
    # profile whose entries all declare a blank apiKeyEnv reads no variable at all.
    if ($pairs.Count -eq 0 -and $blank.Count -eq 0) { $pairs.Add([pscustomobject]@{ Env = $DefaultEnv; SecretName = $DefaultSecret; Name = '' }) }
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
    $hints = @(@($missingPairs | ForEach-Object { Get-VaultPullHint -SecretName $_.SecretName -EnvName $_.Env -ProviderName $_.Name -ConfigLabel $ConfigLabel }) +
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
# The configured command is what the hub RUNS (review finding): CliProcessAgent starts
# options.Command as written, and its IsOnPath joins the value onto each PATH directory
# — for a rooted path Path.Combine yields the path itself, so /opt/tools/codex is "on
# PATH" whenever that file exists even when /opt/tools is not in PATH. The lanes probe
# the configured value the same way instead of resolving the bare leaf, so a
# path-qualified command the hub can run is never reported missing (and a bare name
# is looked up exactly as configured).
function Get-AIHubCliAgentCommand {
    param([Parameter(Mandatory)][string]$Command)
    $cfg = (Get-AIHubConfigState).Config
    if ($null -eq $cfg -or -not $cfg.PSObject.Properties['cliAgents'] -or $null -eq $cfg.cliAgents) { return '' }
    foreach ($agent in @($cfg.cliAgents)) {
        if ($null -eq $agent) { continue }
        if ($agent.PSObject.Properties['enabled'] -and $agent.enabled -eq $false) { continue }
        $cmd = if ($agent.PSObject.Properties['command'] -and $null -ne $agent.command) { [string]$agent.command } else { '' }
        $leaf = ''
        if ($cmd) { try { $leaf = [System.IO.Path]::GetFileNameWithoutExtension($cmd) } catch { $leaf = $cmd } }
        if ($leaf -and $leaf.Equals($Command, [System.StringComparison]::OrdinalIgnoreCase)) { return $cmd }
    }
    return ''
}
function Resolve-CliAgentExecutable {
    param([AllowEmptyString()][string]$Configured = '', [Parameter(Mandatory)][string]$Fallback)
    $wanted = if ($Configured) { $Configured } else { $Fallback }
    if ($wanted -notmatch '[\\/]') {
        $cmd = Get-CliCommand -Name $wanted
        if ($cmd) { return [pscustomobject]@{ Source = $cmd.Source; Configured = $wanted; Found = $true; Note = '' } }
        return [pscustomobject]@{ Source = ''; Configured = $wanted; Found = $false; Note = "'$wanted' is not on PATH" }
    }
    $extensions = if ($IsWindows) { @('') + @(([string][Environment]::GetEnvironmentVariable('PATHEXT')).Split(';') | Where-Object { $_ }) } else { @('') }
    $dirs = if ([System.IO.Path]::IsPathRooted($wanted)) { @('') } else { @(([string][Environment]::GetEnvironmentVariable('PATH')).Split([System.IO.Path]::PathSeparator) | Where-Object { $_ }) }
    foreach ($dir in $dirs) {
        foreach ($ext in $extensions) {
            $candidate = if ($dir) { [System.IO.Path]::Combine($dir, $wanted + $ext) } else { $wanted + $ext }
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return [pscustomobject]@{ Source = $candidate; Configured = $wanted; Found = $true; Note = "the configured command '$wanted' resolves to $candidate, as CliProcessAgent runs it" }
            }
        }
    }
    return [pscustomobject]@{ Source = ''; Configured = $wanted; Found = $false; Note = "the configured command '$wanted' does not exist at that path (checked as CliProcessAgent would: rooted as written, else joined onto each PATH directory)" }
}
# Enabled CLI entries are discovered by their configured COMMAND (review finding):
# ProviderFactory.CreateAll instantiates every enabled cliAgents entry whatever its
# routing name, and CliProcessAgent runs entry.command — so a profile naming its
# codex entry 'code-prod' still launches codex. The command's leaf (directory and
# .exe/.cmd stripped) is compared case-insensitively. The command ALONE decides
# (review finding): CliProcessAgent's IsOnPath(options.Command) is false for a blank
# or missing command, so an entry named 'codex' without one is unconfigured — its
# name never makes it an enabled executable; the command is read untrimmed, as run.
function Test-AIHubCliAgentEnabled {
    param([Parameter(Mandatory)][string]$Command)
    $cfg = (Get-AIHubConfigState).Config
    if ($null -eq $cfg) { return $true }
    if (-not $cfg.PSObject.Properties['cliAgents'] -or $null -eq $cfg.cliAgents) { return $false }
    foreach ($agent in @($cfg.cliAgents)) {
        if ($null -eq $agent) { continue }
        if ($agent.PSObject.Properties['enabled'] -and $agent.enabled -eq $false) { continue }
        $cmd = if ($agent.PSObject.Properties['command'] -and $null -ne $agent.command) { [string]$agent.command } else { '' }
        $leaf = ''
        if ($cmd) { try { $leaf = [System.IO.Path]::GetFileNameWithoutExtension($cmd) } catch { $leaf = $cmd } }
        if ($leaf -and $leaf.Equals($Command, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

# The exact pull command for one (secret, env) pair (review finding): the bash loader
# scripts/bootstrap/load-env-from-keyvault.sh knows only the three built-in names, so a
# custom profile must be pointed at the config-aware auto-login.ps1 — otherwise the
# advertised repair leaves the diagnosed variable unset.
function Get-VaultPullHint {
    param([AllowEmptyString()][string]$SecretName, [Parameter(Mandatory)][string]$EnvName, [AllowEmptyString()][string]$ProviderName = '', [string]$ConfigLabel = 'the active config')
    if ([string]::IsNullOrWhiteSpace($SecretName)) {
        return "set $EnvName directly (the active config declares no apiKeySecretName for it, so no vault pull exists)"
    }
    # An invalid NAME is a config defect, not a pull (review finding): SecretResolver
    # requests it exactly as written and Key Vault rejects it — same wording as
    # auto-login's action, so a merged summary dedupes the two.
    if ($SecretName -notmatch '^[0-9A-Za-z-]{1,127}$') {
        $target = if ($ProviderName) { "providers.$ProviderName.apiKeySecretName" } else { "the apiKeySecretName mapped to $EnvName" }
        return "fix $target in ${ConfigLabel}: '$SecretName' is not a valid Key Vault secret name — use letters, digits and hyphens only, no surrounding whitespace"
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
    # -ClearedNames (review finding): fixed GitHub variables owned by a non-GitHub
    # consumer are removed from the environment for this one call and restored right
    # after (values move between env slots in-process only), so gh never receives a
    # foreign API key as its token — gh honors GH_TOKEN / GITHUB_TOKEN ahead of its
    # keyring, so leaving them in place would send that key to github.com.
    param([Parameter(Mandatory)][string]$GhExe, [AllowEmptyCollection()][string[]]$ClearedNames = @())
    $saved = @{}
    foreach ($clearedName in $ClearedNames) {
        $saved[$clearedName] = [Environment]::GetEnvironmentVariable($clearedName)
        [Environment]::SetEnvironmentVariable($clearedName, $null)
    }
    try {
        $result = Invoke-Probe -Executable $GhExe -Arguments @('auth', 'status', '--hostname', 'github.com', '--active')
        if ($result.ExitCode -ne 0 -and ((@($result.Output) -join ' ') -match 'unknown flag')) {
            $result = Invoke-Probe -Executable $GhExe -Arguments @('auth', 'status', '--hostname', 'github.com')
        }
    }
    finally {
        foreach ($clearedName in $ClearedNames) { [Environment]::SetEnvironmentVariable($clearedName, $saved[$clearedName]) }
        $saved = $null
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
    # Ownership screening (review finding): a fixed GitHub variable that an enabled
    # non-GitHub consumer reads as its apiKeyEnv holds THAT service's key — it is not
    # this lane's credential and is never passed to gh (cleared for the status call).
    $screenedTokenNames = @(Get-NonGitHubOwnedTokenNames)
    $envTokenName = @(@('GH_TOKEN', 'GITHUB_TOKEN') | Where-Object { (Test-EnvValue $_) -and ($_ -notin $screenedTokenNames) }) | Select-Object -First 1
    $screenedNote = if ($screenedTokenNames.Count -gt 0) { " ($($screenedTokenNames -join ' / ') is read by an enabled non-GitHub consumer in the active config, so its value is that service's credential: screened out of this lane and never passed to gh)" } else { '' }

    if (-not $ghCmd) {
        $suffix = if ($envTokenName) { (' ({0} is set — name checked only — but there is no gh to drive)' -f $envTokenName) }
        else { '' }
        return New-LaneResult -Lane 'gh' -State 'unavailable' -Method 'none' `
            -Detail ('gh (GitHub CLI) is not on PATH' + $suffix + ' — install via scripts/bootstrap/cloud-shell-setup.sh or https://cli.github.com')
    }

    # Exit code only; the raw status text is never echoed (it names accounts/scopes).
    $status = Invoke-GhAuthStatus -GhExe $ghCmd.Source -ClearedNames $screenedTokenNames

    if ($envTokenName) {
        # gh honors env tokens ahead of its keyring, so a set token IS the auth.
        $actionsNote = if ($inActions) { ' — GitHub Actions: the workflow-provided GITHUB_TOKEN is the auth here' } else { '' }
        if ($status.ExitCode -eq 0) {
            return New-LaneResult -Lane 'gh' -State 'ready' -Method 'env-token' `
                -Detail ("$envTokenName is set (name checked only, value never read) and gh auth status accepts it$actionsNote$screenedNote")
        }
        return New-LaneResult -Lane 'gh' -State 'needs-owner' -Method 'env-token' `
            -Detail ("$envTokenName is set (name checked only) but gh auth status exits $($status.ExitCode) — the gh CLI rejects the session, which does NOT prove the token is bad: REST-level " +
                'connectivity can still exist (a proxy-injected session, or a fine-grained/app token the CLI dislikes). Wire-level ground truth: pwsh scripts/verify/rest-connect.ps1' +
                " (raw status output never echoed)$actionsNote$screenedNote") `
            -OwnerAction 'gh auth login --web   # device-code flow; or rotate the env token — but run scripts/verify/rest-connect.ps1 first: if the transport is already authenticated, nothing may be broken'
    }

    if ($status.ExitCode -eq 0) {
        return New-LaneResult -Lane 'gh' -State 'ready' -Method 'stored-login' `
            -Detail ('gh auth status reports an active github.com login from the keyring (raw output never echoed)' + $screenedNote)
    }

    if ($inActions) {
        # Inside Actions the fix is workflow wiring, never a login flow (gh's own
        # guidance: add GH_TOKEN: ${{ github.token }} to the job env).
        return New-LaneResult -Lane 'gh' -State 'needs-owner' -Method 'ci-env-token' `
            -Detail 'GitHub Actions job with no GH_TOKEN/GITHUB_TOKEN in the env — the workflow-provided GITHUB_TOKEN is the auth; pass it to the job' `
            -OwnerAction 'add to the workflow job:  env: { GH_TOKEN: ${{ github.token }} }'
    }

    return New-LaneResult -Lane 'gh' -State 'needs-owner' -Method 'device-code' `
        -Detail ('no env token and no stored gh login — the device-code web login needs a human with a browser and is never automated' + $screenedNote) `
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
    $codexAgentEnabled = Test-AIHubCliAgentEnabled -Command 'codex'
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
        -ConfigLabel $configState.Label -CliOnlySource "fallback default; only the codex agent is enabled in $($configState.Label)" -AzResult $AzResult `
        -OwnerTypes @('openai', 'codex-cli')
    if ($eval.HasDefects) {
        return New-LaneResult -Lane 'openai-codex' -State 'needs-owner' -Method 'config' `
            -Detail $eval.DefectDetail -OwnerAction $eval.DefectAction
    }
    $nameSource = $eval.NameSource
    $envList = $eval.EnvList

    $missingList = $eval.MissingList
    $partialNote = $eval.PartialNote
    $vaultPull = $eval.VaultPull

    # The CLI half is judged on its OWN credential (review finding): the codex CLI
    # reads the fixed OPENAI_API_KEY or its cached ChatGPT-plan login — a renamed
    # provider variable never covers it, and a CLI login never covers the API
    # providers. Both halves must be satisfied before the lane is ready.
    $cliState = 'not-needed'   # not-needed | env | login | unverifiable | missing
    $cliDetail = ''
    $cliAction = ''
    if ($codexAgentEnabled) {
        if (Test-EnvValue 'OPENAI_API_KEY') {
            $cliState = 'env'
            $cliDetail = 'the codex CLI reads OPENAI_API_KEY, which is set'
        }
        else {
            $codexCmd = Resolve-CliAgentExecutable -Configured (Get-AIHubCliAgentCommand -Command 'codex') -Fallback 'codex'
            $codexNote = if ($codexCmd.Note -and $codexCmd.Found) { " — $($codexCmd.Note)" } else { '' }
            if ($codexCmd.Found) {
                $probe = Invoke-Probe -Executable $codexCmd.Source -Arguments @('login', 'status')
                $text = @($probe.Output) -join '; '
                if ($text -match '(?i)unrecognized subcommand|unexpected argument|unknown (sub)?command') {
                    # Old builds predate `login status` — reported honestly, never guessed.
                    $cliState = 'unverifiable'
                    $cliDetail = 'OPENAI_API_KEY is unset and this codex build has no `login status` subcommand, so its cached login cannot be verified headlessly'
                    $cliAction = 'codex login   # browser/device flow (owner action); or set OPENAI_API_KEY for the codex CLI'
                }
                elseif ($probe.ExitCode -eq 0) {
                    $cliState = 'login'
                    $cliDetail = "codex login status exits 0 (the codex CLI holds a cached ChatGPT-plan login)$codexNote"
                }
                else {
                    $cliState = 'missing'
                    $cliDetail = "OPENAI_API_KEY is unset and codex login status exits $($probe.ExitCode) — the ChatGPT-plan login is a browser/device flow only an owner can complete"
                    $cliAction = 'codex login   # or set OPENAI_API_KEY for the codex CLI'
                }
            }
            else {
                $cliState = 'missing'
                $cliDetail = if ($codexCmd.Configured -match '[\\/]') { "OPENAI_API_KEY is unset and $($codexCmd.Note) — fix the cliAgents command in $($configState.Label) or install the CLI there" }
                else { 'OPENAI_API_KEY is unset and no codex CLI is on PATH (pwsh scripts/bootstrap/setup-ai-clis.ps1 installs @openai/codex)' }
                $cliAction = 'pwsh scripts/bootstrap/setup-ai-clis.ps1   # installs codex; then codex login, or set OPENAI_API_KEY for the codex CLI'
            }
        }
    }
    $cliOk = $cliState -in 'not-needed', 'env', 'login'
    # With no enabled openai-type provider, the evaluation's fallback pair IS the CLI's
    # variable, which the CLI check above already judged — nothing else to satisfy.
    $providersOk = $eval.Satisfied -or $noApiProviders
    # The vault-pull hint rides on the CLI action only when no provider pair carries
    # it already (renamed provider variables) — never the same hint twice.
    if ($cliAction -and $providersOk -and -not $noApiProviders) { $cliAction += ' (source scripts/bootstrap/load-env-from-keyvault.sh, or pwsh: . scripts/bootstrap/auto-login.ps1, pulls openai-api-key into it)' }

    # EVERY distinct enabled provider variable must hold a value — and every
    # blank-apiKeyEnv entry's secret must be PROVEN present in the vault (names
    # listed, values never read) — AND the CLI half must hold its own credential
    # before the lane is ready (review findings: nothing to inspect is not readiness;
    # arbitrary provider names never cover the CLI).
    if ($providersOk -and $cliOk) {
        $cliSuffix = switch ($cliState) {
            'env' { '; the codex CLI reads OPENAI_API_KEY (set)' }
            'login' { '; the codex CLI holds a cached login (codex login status exits 0)' }
            default { '' }
        }
        if ($noApiProviders) {
            return New-LaneResult -Lane 'openai-codex' -State 'ready' -Method $(if ($cliState -eq 'login') { 'cli-login' } else { 'env-token' }) `
                -Detail "only the codex agent is enabled in the active config (no API provider needs a key)$cliSuffix"
        }
        if (-not $eval.HasEnvPairs) {
            return New-LaneResult -Lane 'openai-codex' -State 'ready' -Method 'keyvault-inprocess' `
                -Detail "no environment variable to check for the API providers (declared by $nameSource)$($eval.ProvenNote)$cliSuffix"
        }
        return New-LaneResult -Lane 'openai-codex' -State 'ready' -Method 'env-token' `
            -Detail "$envList set (declared by $nameSource; names checked only, values never read) — covers every enabled openai/openai-codex API provider$($eval.ProvenNote)$cliSuffix"
    }

    $parts = @()
    $actions = @()
    if (-not $providersOk) {
        $parts += "$missingList (declared by $nameSource) is not satisfied$partialNote"
        $actions += $vaultPull
    }
    elseif (-not $noApiProviders) {
        $parts += "the API providers are satisfied ($envList set$($eval.ProvenNote))"
    }
    if (-not $cliOk) {
        $parts += $cliDetail
        $actions = @($cliAction) + $actions
    }
    elseif ($cliState -eq 'login') { $parts += 'the codex CLI holds a cached login (codex login status exits 0) — a CLI login never covers the API providers' }
    elseif ($cliState -eq 'env') { $parts += 'the codex CLI reads OPENAI_API_KEY (set)' }
    elseif (-not $codexAgentEnabled) { $parts += "the codex agent is disabled in $($configState.Label), so only the API keys apply" }
    $method = switch ($cliState) { 'missing' { 'device-code' } 'unverifiable' { 'cli-login' } default { 'env-token' } }
    return New-LaneResult -Lane 'openai-codex' -State 'needs-owner' -Method $method `
        -Detail ($parts -join '; ') `
        -OwnerAction ((@($actions) | Where-Object { $_ }) -join '; or: ')
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
    $claudeAgentEnabled = Test-AIHubCliAgentEnabled -Command 'claude'
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
        -ConfigLabel $configLabel -CliOnlySource "fallback default; only the claude-cli agent is enabled in $configLabel" -AzResult $AzResult `
        -OwnerTypes @('anthropic', 'claude-cli')
    if ($eval.HasDefects) {
        return New-LaneResult -Lane 'claude' -State 'needs-owner' -Method 'config' `
            -Detail $eval.DefectDetail -OwnerAction $eval.DefectAction
    }
    $nameSource = $eval.NameSource
    $envList = $eval.EnvList

    $missingList = $eval.MissingList
    $partialNote = $eval.PartialNote
    $vaultPull = $eval.VaultPull

    # The CLI half is judged on its OWN credential (review finding): the claude CLI
    # reads the fixed ANTHROPIC_API_KEY or a cached login that cannot be probed
    # headlessly — a renamed provider variable never covers it.
    $noApiProviders = ($null -ne $anthropicProviders -and $anthropicProviders.Count -eq 0)
    $cliState = 'not-needed'   # not-needed | env | unverifiable
    $cliDetail = ''
    $cliAction = ''
    if ($claudeAgentEnabled) {
        if (Test-EnvValue 'ANTHROPIC_API_KEY') {
            $cliState = 'env'
            $cliDetail = 'the claude CLI reads ANTHROPIC_API_KEY, which is set'
        }
        else {
            $cliState = 'unverifiable'
            $claudeCmd = Resolve-CliAgentExecutable -Configured (Get-AIHubCliAgentCommand -Command 'claude') -Fallback 'claude'
            $cliDetail = if ($claudeCmd.Found) { 'ANTHROPIC_API_KEY is unset and a cached claude login cannot be probed headlessly — probing would launch an interactive session (connect-all.ps1 rule)' + $(if ($claudeCmd.Note) { " ($($claudeCmd.Note))" } else { '' }) }
            elseif ($claudeCmd.Configured -match '[\\/]') { "ANTHROPIC_API_KEY is unset and $($claudeCmd.Note)" }
            else { 'ANTHROPIC_API_KEY is unset and no claude CLI is on PATH (pwsh scripts/bootstrap/setup-ai-clis.ps1 installs it)' }
            $cliAction = 'claude setup-token   # mint a long-lived token for the CLI (owner action); or set ANTHROPIC_API_KEY for the claude CLI'
        }
    }
    $cliOk = $cliState -in 'not-needed', 'env'
    $providersOk = $eval.Satisfied -or $noApiProviders
    # The vault-pull hint rides on the CLI action only when no provider pair carries
    # it already (renamed provider variables) — never the same hint twice.
    if ($cliAction -and $providersOk -and -not $noApiProviders) { $cliAction += ' (source scripts/bootstrap/load-env-from-keyvault.sh, or pwsh: . scripts/bootstrap/auto-login.ps1, pulls anthropic-api-key into it)' }

    # Non-whitespace, not mere existence (same rule as the service-principal gate):
    # an empty variable lights nothing; an in-process secret counts only once its
    # name is listed in the vault (review finding); the CLI half must hold its own
    # credential (review finding). Values are never read.
    if ($providersOk -and $cliOk) {
        $cliSuffix = if ($cliState -eq 'env') { '; the claude CLI reads ANTHROPIC_API_KEY (set)' } else { '' }
        if ($noApiProviders) {
            return New-LaneResult -Lane 'claude' -State 'ready' -Method 'env-token' `
                -Detail "only the claude-cli agent is enabled in the active config (no API provider needs a key)$cliSuffix"
        }
        if (-not $eval.HasEnvPairs) {
            return New-LaneResult -Lane 'claude' -State 'ready' -Method 'keyvault-inprocess' `
                -Detail "no environment variable to check for the API providers (declared by $nameSource)$($eval.ProvenNote)$cliSuffix"
        }
        return New-LaneResult -Lane 'claude' -State 'ready' -Method 'env-token' `
            -Detail ("$envList set (declared by $nameSource; names checked only, values never read) — covers every enabled anthropic provider$($eval.ProvenNote)$cliSuffix")
    }

    $parts = @()
    $actions = @()
    if (-not $providersOk) {
        $parts += "$missingList (declared by $nameSource) is not satisfied$partialNote"
        $actions += $vaultPull
    }
    elseif (-not $noApiProviders) {
        $parts += "the API providers are satisfied ($envList set$($eval.ProvenNote))"
    }
    if (-not $cliOk) {
        $parts += $cliDetail
        $actions = @($cliAction) + $actions
    }
    elseif ($cliState -eq 'env') { $parts += 'the claude CLI reads ANTHROPIC_API_KEY (set)' }
    elseif (-not $claudeAgentEnabled) { $parts += "the claude-cli agent is disabled in $configLabel, so only the API keys apply" }
    $method = if ($cliState -eq 'unverifiable' -and $providersOk) { 'cli-login' } else { 'env-token' }
    return New-LaneResult -Lane 'claude' -State 'needs-owner' -Method $method `
        -Detail ($parts -join '; ') `
        -OwnerAction ((@($actions) | Where-Object { $_ }) -join '; or: ')
}

# --- copilot lane ----------------------------------------------------------------------
function Test-CopilotLane {
    param([Parameter(Mandatory)][pscustomobject]$GhResult)

    if (-not (Test-AIHubCliAgentEnabled -Command 'copilot')) {
        return New-LaneResult -Lane 'copilot' -State 'disabled' -Method 'config' -Gates $false `
            -Detail ("the copilot agent is disabled or absent in the active config ($((Get-AIHubConfigState).Label)) — the hub never launches it, so no login is needed and none is requested")
    }

    # Only the standalone binary satisfies this lane (review finding): the configured
    # cliAgent runs `copilot -p ...` (@github/copilot), and the gh-copilot EXTENSION
    # provides `gh copilot suggest/explain` — a different executable shape the hub
    # cannot launch. The extension is reported as information, never as readiness.
    $copilotCmd = Resolve-CliAgentExecutable -Configured (Get-AIHubCliAgentCommand -Command 'copilot') -Fallback 'copilot'
    $extensionNote = ''
    if (-not $copilotCmd.Found) {
        if ($copilotCmd.Configured -match '[\\/]') {
            return New-LaneResult -Lane 'copilot' -State 'unavailable' -Method 'none' `
                -Detail ("$($copilotCmd.Note) — fix the cliAgents command in $((Get-AIHubConfigState).Label) or install the standalone copilot CLI (@github/copilot) there")
        }
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
    $presence = if ($copilotCmd.Note) { "standalone copilot CLI (@github/copilot) is present ($($copilotCmd.Note))" } else { 'standalone copilot CLI (@github/copilot) is on PATH' }

    # A headless token authenticates copilot on its own (review finding): setup-ai-clis.ps1
    # documents GH_TOKEN / GITHUB_TOKEN as sufficient, so a host without gh must not be
    # sent to `gh auth login`. Names checked only; wire validity is rest-connect's call.
    # Screened like the gh lane (review finding): a fixed variable an enabled
    # non-GitHub consumer owns is that service's key, never copilot's token.
    $copilotScreened = @(Get-NonGitHubOwnedTokenNames)
    $copilotTokenEnv = @('GH_TOKEN', 'GITHUB_TOKEN') | Where-Object { (Test-EnvValue $_) -and ($_ -notin $copilotScreened) } | Select-Object -First 1
    if ($copilotTokenEnv) {
        $ghLaneNote = if ($GhResult.state -in 'ready', 'repaired') { '' } else { "; the gh lane is $($GhResult.state), which does not gate copilot (a gh CLI session is not required)" }
        return New-LaneResult -Lane 'copilot' -State 'ready' -Method 'env-token' `
            -Detail ("$presence; $copilotTokenEnv is set (name checked only) and copilot honors it headlessly — wire validity is scripts/verify/rest-connect.ps1's call$ghLaneNote")
    }

    # Otherwise copilot reuses the GitHub login, so its auth state IS the gh lane's state.
    if ($GhResult.state -in 'ready', 'repaired') {
        return New-LaneResult -Lane 'copilot' -State 'ready' -Method 'github-login' `
            -Detail ("$presence; copilot reuses the GitHub login and the gh lane is $($GhResult.state) ($($GhResult.method))")
    }
    $ghOnPath = [bool](Get-CliCommand -Name 'gh')
    $fix = if ("$($GhResult.ownerAction)".Trim()) { "$($GhResult.ownerAction)" }
    elseif ($ghOnPath) { 'gh auth login --web   # device-code flow' }
    else { 'set GH_TOKEN (a GitHub token) for headless copilot; or: bash scripts/bootstrap/cloud-shell-setup.sh && gh auth login --web   # installs the GitHub CLI, then the device-code flow' }
    return New-LaneResult -Lane 'copilot' -State 'needs-owner' -Method 'github-login' `
        -Detail ("$presence, but neither GH_TOKEN nor GITHUB_TOKEN is set and the gh lane is $($GhResult.state) — a headless token or one GitHub login fixes it") `
        -OwnerAction $fix
}

# --- linear lane (connector; verify-only, never gates) --------------------------------
# Repository-secret METADATA (review finding): the connector workflows read the
# REPOSITORY secret, not this shell's variable, so the two are separate states and
# neither is inferred from the other. `gh api repos/{owner}/{repo}/actions/secrets/<name>`
# returns name and dates only — never a value — and needs the actions-secrets read
# permission: a 404 counts as absent only when the listing endpoint answered 200 (GitHub
# hides secrets from a token without that permission behind the same 404), anything
# else is unknown with the reason. Screened GitHub tokens are cleared around the calls
# exactly as for the gh lane; the repo comes from gh's own {owner}/{repo} resolution
# (the current git remote, or GH_REPO).
function Get-RepositorySecretState {
    param([Parameter(Mandatory)][string]$Name)
    if ($Name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') { return [pscustomobject]@{ State = 'unknown'; Reason = "'$Name' is not a valid secret name" } }
    $ghCmd = Get-CliCommand -Name 'gh'
    if (-not $ghCmd) { return [pscustomobject]@{ State = 'unknown'; Reason = 'gh is not on PATH, so repository-secret metadata could not be read' } }
    $cleared = @(Get-NonGitHubOwnedTokenNames)
    $saved = @{}
    foreach ($clearedName in $cleared) { $saved[$clearedName] = [Environment]::GetEnvironmentVariable($clearedName); [Environment]::SetEnvironmentVariable($clearedName, $null) }
    try {
        $listProbe = Invoke-Probe -Executable $ghCmd.Source -Arguments @('api', '-i', 'repos/{owner}/{repo}/actions/secrets?per_page=1')
        $itemProbe = Invoke-Probe -Executable $ghCmd.Source -Arguments @('api', '-i', "repos/{owner}/{repo}/actions/secrets/$Name")
    }
    finally {
        foreach ($clearedName in $cleared) { [Environment]::SetEnvironmentVariable($clearedName, $saved[$clearedName]) }
        $saved = $null
    }
    $statusOf = {
        param($probe)
        $line = @($probe.Output | Where-Object { $_ -match '^HTTP/\S+\s+(\d{3})' } | Select-Object -First 1)
        if ($line.Count -gt 0 -and $line[0] -match '^HTTP/\S+\s+(\d{3})') { [int]$Matches[1] } else { 0 }
    }
    $listStatus = & $statusOf $listProbe
    $itemStatus = & $statusOf $itemProbe
    if ($itemStatus -eq 200) { return [pscustomobject]@{ State = 'configured'; Reason = 'repository-secret metadata lists it (name and dates only, never a value)' } }
    if ($itemStatus -eq 404 -and $listStatus -eq 200) { return [pscustomobject]@{ State = 'absent'; Reason = 'the repository-secret listing is readable and does not contain it' } }
    $why = if ($itemStatus -eq 0) { "gh api could not be resolved or reached (not in a git checkout with a GitHub remote, or the call failed; output never echoed)" }
    elseif ($itemStatus -in 401, 403, 404) { "HTTP $itemStatus — the wire token cannot read repository-secret metadata (GitHub answers $itemStatus without the actions-secrets read permission); a fine-grained PAT with Secrets: read, or the owner's gh login, can" }
    else { "HTTP $itemStatus from the repository-secret metadata endpoint" }
    return [pscustomobject]@{ State = 'unknown'; Reason = $why }
}
# Local variable and repository secret as two states (review finding): the connector
# workflow runs on the repository secret; this shell's variable covers local tooling
# only. Ready when the repository secret is configured; needs-owner when it is
# proven absent; when unknown, the local variable alone can only vouch for local use.
function Get-ConnectorSecretLane {
    param(
        [Parameter(Mandatory)][string]$Lane,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Declared,
        [Parameter(Mandatory)][string]$Workflow,
        [Parameter(Mandatory)][string]$Purpose,
        [Parameter(Mandatory)][string]$OwnerAction,
        [string]$Suffix = ''
    )
    $localSet = Test-EnvValue $Name
    $localText = if ($localSet) { "$Name is set in this shell (name checked only, value never read — covers local tooling only)" } else { "$Name is not set in this shell (local tooling only)" }
    $repo = Get-RepositorySecretState -Name $Name
    $repoText = "repository secret ${Name}: $($repo.State) — $($repo.Reason)"
    $suffixText = if ($Suffix) { ". $Suffix" } else { '' }
    switch ($repo.State) {
        'configured' {
            return New-LaneResult -Lane $Lane -State 'ready' -Method 'repo-secret' -Gates $false `
                -Detail ("$repoText, so $Workflow can run ($Purpose); $localText ($Declared)$suffixText")
        }
        'absent' {
            return New-LaneResult -Lane $Lane -State 'needs-owner' -Method 'repo-secret' -Gates $false `
                -Detail ("$repoText, so $Workflow skips green and $Purpose runs dark; $localText ($Declared)$suffixText") `
                -OwnerAction $OwnerAction
        }
        default {
            if ($localSet) {
                return New-LaneResult -Lane $Lane -State 'ready' -Method 'env-token' -Gates $false `
                    -Detail ("$localText ($Declared); $repoText — whether $Workflow can run is unverifiable from here: verify per the CONNECTIONS_SETUP.md owner checklist$suffixText")
            }
            return New-LaneResult -Lane $Lane -State 'needs-owner' -Method 'repo-secret' -Gates $false `
                -Detail ("$localText ($Declared); $repoText — if $Workflow is meant to run ($Purpose), store the repository secret$suffixText") `
                -OwnerAction $OwnerAction
        }
    }
}
function Test-LinearLane {
    # config/connectors.json linear.apiKeyEnv declares the name; the sync workflow
    # (.github/workflows/linear-sync.yml) reads the REPOSITORY SECRET of that name and
    # skips green without it — reported as its own state, never inferred from this
    # shell's variable (review finding).
    return Get-ConnectorSecretLane -Lane 'linear' -Name 'LINEAR_API_KEY' -Declared 'declared by config/connectors.json linear.apiKeyEnv' `
        -Workflow '.github/workflows/linear-sync.yml' -Purpose 'GitHub->Linear issue sync' `
        -OwnerAction 'gh secret set LINEAR_API_KEY   # value from Linear Settings -> Security & access -> API'
}

# --- slack lane (connector; verify-only, never gates) ----------------------------------
function Test-SlackLane {
    # SLACK_BOT_TOKEN honesty: connectors.json declares it (slack.botTokenEnv) but no
    # workflow or service in the repo consumes it today — setting it changes nothing
    # yet, and the report must not imply otherwise.
    $botTokenState = if (Test-EnvValue 'SLACK_BOT_TOKEN') { 'set in this shell' } else { 'not set' }
    $botTokenNote = "SLACK_BOT_TOKEN ($botTokenState) is declared in config/connectors.json but nothing in the repo consumes it today"
    # The repository secret is its own state (review finding), as for the Linear lane.
    return Get-ConnectorSecretLane -Lane 'slack' -Name 'SLACK_WEBHOOK_URL' -Declared 'declared by config/connectors.json slack.webhookUrlEnv' `
        -Workflow '.github/workflows/notify-slack.yml' -Purpose 'workflow notifications' `
        -OwnerAction 'gh secret set SLACK_WEBHOOK_URL   # value from the Slack app incoming-webhook config' -Suffix $botTokenNote
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
    # The repo default is no different for -Apply (review finding): AIHubService
    # resolves the same config/aihub.json and AIHubOptions.Load fails on it, so no hub
    # can start — the az profile is never mutated on behalf of a configuration that
    # cannot run. A report-only run still diagnoses with the built-in names and says so.
    if ($Apply -and $null -eq $activeConfig.Config) {
        throw "-Apply refused: the repo default config ($($activeConfig.Path)) is missing, unparseable, or not a JSON object, so the hub cannot load it either (AIHubOptions.Load); fix the file — report-only runs still diagnose with the built-in names (no lane was repaired)"
    }
    if ($activeConfig.ProvidersNull) {
        throw "the active config ($($activeConfig.Path)) declares `"providers`": null — ProviderFactory.CreateAll cannot enumerate a null providers table and the hub fails to start; omit the section for a CLI-only profile or declare an object (no lane was diagnosed or repaired)"
    }
    if ($activeConfig.ProvidersShape) {
        throw "the active config ($($activeConfig.Path)) declares `"providers`" as $($activeConfig.ProvidersShape) — AIHubOptions binds that section as a dictionary of provider objects and ProviderFactory.CreateAll dereferences every entry, so the hub fails on the file; declare objects only (or omit the section for a CLI-only profile) (no lane was diagnosed or repaired)"
    }
    if ($activeConfig.SectionShape) {
        throw "the active config ($($activeConfig.Path)) declares $($activeConfig.SectionShape) — AIHubOptions.Load (System.Text.Json) cannot bind the file to the hub's typed options, or the hub dereferences the value, so it fails to load or start; fix the section or value, or omit the section for its defaults (no lane was diagnosed or repaired)"
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
