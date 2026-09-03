<#
.SYNOPSIS
REST-level connectivity verifier and NON-INTERACTIVE token acquirer for the two control
planes: GitHub REST (api.github.com) and Azure ARM (the active cloud's Resource Manager
endpoint — management.azure.com for the public cloud, resolved from AZURE_AUTHORITY_HOST /
ARM_ENDPOINT or `az cloud show` for sovereign clouds; a lone override is completed from
the known-cloud table, and a pair naming two clouds resolves to NO cloud — reported as
needs-owner before any request is made). Report-first:
every run diagnoses, mutates nothing gate-worthy, never starts an interactive flow, and
exits 0 — needs-owner is a truthful reported state, never a failure.

.DESCRIPTION
The REST sibling of scripts/bootstrap/auth-doctor.ps1: the doctor asks each CLI whether
it is authenticated; this script goes UNDER the CLIs and proves the control planes
answer a real REST call with a real token. That distinction is load-bearing —

  CRITICAL DESIGN FACT (corrected by adversarial review): some transports INJECT
  credentials. Measured in the Claude remote container: a garbage Bearer token AND a
  request with no Authorization header at all BOTH returned 200 from /rate_limit at
  15000/hr, authenticated as Yolkster64 — the agent proxy on that host owns a real
  GitHub session and injects it into every request. On such a transport, a per-token
  REST probe proves nothing about the token (any candidate would look valid), so this
  script runs an ANONYMOUS control probe first: unauthenticated GitHub is capped at
  60/hr, and a no-auth 200 above that cap proves an injecting intermediary — readiness
  is then attributed to the TRANSPORT, never to a specific token. Only on a clean
  transport is the wire the per-token ground truth (where it beats a CLI's opinion:
  fine-grained and app tokens can be REST-valid while `gh auth status` complains).

Lanes (one row each: {lane, state ready|needs-owner|unavailable|ci-delegated, source,
identity, detail, ownerAction}):

  github  Candidate tokens tried IN ORDER: env GH_TOKEN, env GITHUB_TOKEN, then the
          github-models provider's CONFIGURED apiKeyEnv (GITHUB_MODELS_TOKEN by default;
          read from AIHUB_CONFIG or config/aihub.json — the token auto-login.ps1 exports
          from Key Vault), then — only
          when the gh CLI is on PATH — the output of `gh auth token` (stderr suppressed;
          a failure there just ends the chain early, it is not an error). Each candidate
          is probed with GET https://api.github.com/rate_limit (Authorization: Bearer,
          X-GitHub-Api-Version: 2022-11-28, User-Agent helios-rest-connect). 200 means
          that token IS REST-valid — the chain stops and GET /user names the identity
          (401/403 on /user with rate_limit 200 is still ready: fine-grained and
          app-installation tokens may not carry the /user surface, so identity reports
          'unknown (token valid; /user not permitted for this token type)'). 401 on
          rate_limit means that candidate is invalid — the next one is tried.
          unavailable = no candidate token present at all (Invoke-WebRequest is built
          into PowerShell 7, so there is no "no HTTP client" case); needs-owner = every
          candidate present but REST-invalid, ownerAction `gh auth login --web` (device
          code).

  azure   Automatic-first chain; interactive login is NEVER run, only ever reported:
            1. CI OIDC        ACTIONS_ID_TOKEN_REQUEST_URL present (name check only)
                              => OIDC is AVAILABLE — evidence, not a completed login
                              (the variable exists the moment a job grants id-token:
                              write, even when azure/login never runs). The chain
                              keeps walking for a token that actually exists; only
                              when no rung holds one does the lane end ci-delegated,
                              stating the azure/login prerequisite. The exchange
                              itself is never duplicated here.
            2. env SP         AZURE_CLIENT_ID + AZURE_TENANT_ID + AZURE_CLIENT_SECRET
                              => client_credentials POST to the active cloud's authority
                              (login.microsoftonline.com for the public cloud; scope
                              <ARM endpoint>/.default; body built
                              in memory, response token held in a local variable only,
                              never logged). With AZURE_CLIENT_CERTIFICATE_PATH instead
                              of a secret, the JWT client assertion is never hand-rolled
                              here — the flow is delegated to `az login
                              --service-principal --certificate` + `az account
                              get-access-token` when az is on PATH, and reported as
                              available-but-needs-az otherwise.
            3. managed id     IDENTITY_ENDPOINT (+IDENTITY_HEADER) or MSI_ENDPOINT when
                              present; else the IMDS endpoint (169.254.169.254,
                              Metadata:true) with a HARD 2-second no-proxy timeout so a
                              non-Azure host fails fast instead of hanging.
            4. az cached      `az account get-access-token --resource-type arm` (stderr
                              suppressed, exit code gates the chain entry — the
                              AADSTS50078 MFA-expired state lands here).
          The FIRST chain entry that yields a token is probed live with GET
          <ARM endpoint>/subscriptions?api-version=2022-12-01: 200 =>
          ready (detail: subscription count + first display name/id — identifiers, not
          secrets); 401/403 => that token is not authorized for ARM and the chain
          continues. Nothing working => needs-owner with the exact tenant-scoped MFA
          command plus the setup-tenant.ps1 -OpsIdentity step that makes every future
          session non-interactive.

          NOTE: the zero-human-input Azure paths that exist TODAY are Azure Cloud
          Shell's implicit login and CI OIDC (the azure/login federation from
          scripts/bootstrap/azure-oidc-setup.ps1). Everywhere else, the first token
          costs the owner one MFA login — after which setup-tenant.ps1 -OpsIdentity
          mints the workload identity that removes the human forever.

Secrets policy (CLAUDE.md rule): env vars are gated by NAME plus non-emptiness (an
empty/whitespace value counts as unset; the value is read only for that test). Where a
credential VALUE must be read to be USED (a bearer token cannot be sent by name), it is
read into a function-local variable, flows only into an Authorization header or a POST
body held in memory, and dies with the function scope — it never enters a detail
string, a table, the JSON rollup, a log line, or a file. Raw error bodies from the
token endpoints are never echoed either (they can embed correlation data).

Exit contract: report-first — ALWAYS 0. needs-owner/unavailable/ci-delegated never
gate. Only an internal script failure (the outer try/catch) writes one stderr line and
exits 1.

.PARAMETER Json
Emit one machine-readable rollup object {script, generatedUtc, lanes[], summary,
exitCode} instead of the human table (nothing else on stdout — same convention as
scripts/verify/stack-smoke.ps1 -Json / scripts/bootstrap/auth-doctor.ps1 -Json).
Ignored when -DryRun is set (the dry run is a human plan printer and takes precedence).

.PARAMETER DryRun
Print the full probe plan — every candidate source, every URL that would be probed, in
order — WITHOUT any network call or token read, then exit 0 (mirrors
scripts/verify/stack-smoke.ps1 -DryRun). Takes precedence over -Json.

.PARAMETER TimeoutSeconds
Bound for each HTTP probe (default 20). The IMDS managed-identity probe ignores this
and uses its own hard 2-second timeout by design — a non-Azure host must fail fast.

.EXAMPLE
pwsh scripts/verify/rest-connect.ps1

.EXAMPLE
pwsh scripts/verify/rest-connect.ps1 -Json | ConvertFrom-Json

.EXAMPLE
pwsh scripts/verify/rest-connect.ps1 -DryRun
#>
#Requires -Version 7
[CmdletBinding()]
param(
    [switch]$Json,

    [switch]$DryRun,

    [ValidateRange(5, 120)]
    [int]$TimeoutSeconds = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$gitHubApi = 'https://api.github.com'
# Azure control-plane endpoints follow the ACTIVE CLOUD (review finding): a sovereign
# cloud (Azure Government, China, …) rejects tokens minted at login.microsoftonline.com
# and answers nothing useful at management.azure.com, so every otherwise valid
# credential would fail and the terminal repair would prescribe a public-cloud login.
# Resolution order: the Azure SDK environment conventions (AZURE_AUTHORITY_HOST plus
# AZURE_RESOURCE_MANAGER_ENDPOINT / ARM_ENDPOINT), then the az CLI's active cloud
# (`az cloud show` reads local config only — no network, no login), then the public
# cloud. The chosen cloud and its source are reported in the dry-run walk.
# Trusted endpoint shapes (review finding): an environment override is honored only as
# an HTTPS URL on a known Azure authority / Resource Manager host — a mistyped or
# planted value would otherwise receive AZURE_CLIENT_SECRET (token POST) or every
# bearer token (ARM probe). A custom cloud is approved explicitly through the az CLI
# (`az cloud register` + `az cloud set`), whose values are accepted when HTTPS.
# The two halves are ONE cloud (review finding): a token minted at one cloud's
# authority is not valid at another cloud's Resource Manager, so a lone override is
# completed from this table (AZURE_AUTHORITY_HOST=login.microsoftonline.us implies
# management.usgovcloudapi.net) and a pair naming two clouds resolves to no cloud at
# all — never padded with the public-cloud default, which would turn a valid
# sovereign credential into a guaranteed failure with public-cloud login advice.
$script:knownAzureClouds = @(
    [pscustomobject]@{ Name = 'AzureCloud';        Authority = 'login.microsoftonline.com';        Arm = 'management.azure.com' },
    [pscustomobject]@{ Name = 'AzureUSGovernment'; Authority = 'login.microsoftonline.us';         Arm = 'management.usgovcloudapi.net' },
    [pscustomobject]@{ Name = 'AzureChinaCloud';   Authority = 'login.chinacloudapi.cn';           Arm = 'management.chinacloudapi.cn' },
    [pscustomobject]@{ Name = 'AzureChinaCloud';   Authority = 'login.partner.microsoftonline.cn'; Arm = 'management.chinacloudapi.cn' },
    [pscustomobject]@{ Name = 'AzureGermanCloud';  Authority = 'login.microsoftonline.de';         Arm = 'management.microsoftazure.de' }
)
# Populated by Get-GitHubTokenCandidates / Get-ConfiguredGitHubModelsEnvs; declared
# here so a lane that never reaches the candidate walk still reads an empty list.
$script:candidateNotes = [System.Collections.Generic.List[string]]::new()
$script:nonGitHubReaderEnvs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$script:knownAzureAuthorityHosts = @($script:knownAzureClouds | ForEach-Object { $_.Authority } | Select-Object -Unique)
$script:knownAzureArmHosts = @($script:knownAzureClouds | ForEach-Object { $_.Arm } | Select-Object -Unique)
# The known cloud one validated origin belongs to ($null for an az-registered custom
# host). Pass exactly one origin; the China cloud lists two authority hosts, and an
# ARM-only lookup returns its first (current) authority.
function Get-KnownAzureCloud {
    param([string]$AuthorityOrigin = '', [string]$ArmOrigin = '')
    $authorityHost = if ($AuthorityOrigin) { ([uri]$AuthorityOrigin).Host } else { '' }
    $armHost = if ($ArmOrigin) { ([uri]$ArmOrigin).Host } else { '' }
    foreach ($cloud in $script:knownAzureClouds) {
        if ($authorityHost -and $cloud.Authority.Equals($authorityHost, [System.StringComparison]::OrdinalIgnoreCase)) { return $cloud }
        if ($armHost -and $cloud.Arm.Equals($armHost, [System.StringComparison]::OrdinalIgnoreCase)) { return $cloud }
    }
    return $null
}
function Test-TrustedAzureEndpoint {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Value,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$KnownHosts,
        [Parameter(Mandatory)][string]$Label,
        [switch]$AnyHttpsHost,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Warnings
    )
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $parsedEndpoint = $null
    if (-not [uri]::TryCreate($Value.Trim(), [System.UriKind]::Absolute, [ref]$parsedEndpoint) -or $parsedEndpoint.Scheme -ne 'https') {
        $Warnings.Add("ignored $Label — not an absolute https:// URL (value never echoed); no credential is sent to it")
        return ''
    }
    if (-not $AnyHttpsHost -and -not ($KnownHosts | Where-Object { $parsedEndpoint.Host.Equals($_, [System.StringComparison]::OrdinalIgnoreCase) })) {
        $Warnings.Add("ignored $Label — host '$($parsedEndpoint.Host)' is not a known Azure endpoint ($($KnownHosts -join ', ')); approve a custom cloud through 'az cloud register' + 'az cloud set' instead")
        return ''
    }
    return $parsedEndpoint.GetLeftPart([System.UriPartial]::Authority)
}
# Managed-identity endpoints are platform-local by construction (review finding): App
# Service / Functions / Container Apps inject http://127.0.0.1:41xxx/msi/token or
# http://localhost:42356/msi/token, Azure Arc http://127.0.0.1:40342/metadata/identity/oauth2/token,
# Cloud Shell http://localhost:50342/oauth2/token, and IMDS is the link-local
# 169.254.169.254. Anything else in IDENTITY_ENDPOINT / MSI_ENDPOINT — mistyped, stale,
# or planted — would receive IDENTITY_HEADER / MSI_SECRET, so only a loopback or
# link-local host is ever contacted; a rejected value is reported as chain evidence
# and never counts as a credential source.
function Test-TrustedManagedIdentityEndpoint {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Value,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Notes
    )
    $parsed = $null
    if (-not [uri]::TryCreate($Value.Trim(), [System.UriKind]::Absolute, [ref]$parsed) -or $parsed.Scheme -notin 'http', 'https') {
        $Notes.Add("managed-identity: ignored $Label — not an absolute http(s) URL (value never echoed); no identity header or secret was sent")
        return ''
    }
    $endpointHost = $parsed.DnsSafeHost
    $isLocal = ($endpointHost -eq 'localhost') -or ($endpointHost -eq '::1') -or ($endpointHost -eq '169.254.169.254') -or ($endpointHost -match '^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$')
    if (-not $isLocal) {
        $Notes.Add("managed-identity: ignored $Label — host '$endpointHost' is not a platform-local endpoint (loopback or 169.254.169.254); no identity header or secret was sent to it")
        return ''
    }
    return $parsed.GetLeftPart([System.UriPartial]::Path).TrimEnd('/')
}
function Resolve-AzureCloudEndpoints {
    $warnings = [System.Collections.Generic.List[string]]::new()
    $authority = Test-TrustedAzureEndpoint -Value ([string][Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST')) -KnownHosts $script:knownAzureAuthorityHosts -Label 'AZURE_AUTHORITY_HOST' -Warnings $warnings
    $arm = ''
    $armLabel = ''
    foreach ($candidate in @('AZURE_RESOURCE_MANAGER_ENDPOINT', 'ARM_ENDPOINT')) {
        $value = ([string][Environment]::GetEnvironmentVariable($candidate)).Trim()
        if (-not $value) { continue }
        $armLabel = $candidate
        $arm = Test-TrustedAzureEndpoint -Value $value -KnownHosts $script:knownAzureArmHosts -Label $candidate -Warnings $warnings
        break
    }
    $name = ''
    $source = ''
    $unresolved = ''
    # Pairing rule (review finding): an accepted environment override is always a
    # known-cloud host, so its counterpart is DERIVED from the table rather than
    # defaulted (a rejected override is warned about above and simply absent here);
    # two overrides naming different clouds are a mixed pair and resolve to NO cloud
    # — the lane reports that and sends no credential anywhere.
    if ($authority -and $arm) {
        $authorityCloud = Get-KnownAzureCloud -AuthorityOrigin $authority
        $armCloud = Get-KnownAzureCloud -ArmOrigin $arm
        $source = "environment (AZURE_AUTHORITY_HOST + $armLabel, validated)"
        if ($authorityCloud.Name -ne $armCloud.Name) {
            $unresolved = "AZURE_AUTHORITY_HOST names $($authorityCloud.Name) ($($authorityCloud.Authority)) but $armLabel names $($armCloud.Name) ($($armCloud.Arm)) — a mixed pair: a token minted at one cloud's authority is not valid at the other's Resource Manager, so no request is made with either"
        }
        else { $name = $authorityCloud.Name }
    }
    elseif ($authority) {
        $cloud = Get-KnownAzureCloud -AuthorityOrigin $authority
        $arm = "https://$($cloud.Arm)"
        $name = $cloud.Name
        $source = "environment (AZURE_AUTHORITY_HOST, validated; the $($cloud.Name) Resource Manager endpoint derived from it)"
    }
    elseif ($arm) {
        $cloud = Get-KnownAzureCloud -ArmOrigin $arm
        $authority = "https://$($cloud.Authority)"
        $name = $cloud.Name
        $source = "environment ($armLabel, validated; the $($cloud.Name) authority derived from it)"
    }
    else {
        $azCmd = Get-Command az -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($azCmd) {
            $cloudLines = @(& $azCmd.Source cloud show --query '{name:name,arm:endpoints.resourceManager,aad:endpoints.activeDirectory}' --output json --only-show-errors 2>$null)
            if ([int]$LASTEXITCODE -eq 0) {
                $cloud = $null
                try { $cloud = ($cloudLines -join "`n") | ConvertFrom-Json } catch { }
                if ($null -ne $cloud) {
                    $cloudName = if ($cloud.PSObject.Properties['name'] -and $null -ne $cloud.name) { ([string]$cloud.name).Trim() } else { '' }
                    $cloudAad = if ($cloud.PSObject.Properties['aad'] -and $null -ne $cloud.aad) { ([string]$cloud.aad).Trim() } else { '' }
                    $cloudArm = if ($cloud.PSObject.Properties['arm'] -and $null -ne $cloud.arm) { ([string]$cloud.arm).Trim() } else { '' }
                    if (-not $cloudName) { $cloudName = 'az-registered cloud' }
                    # The az CLI's registered cloud is the operator's explicit approval —
                    # any host, but HTTPS only.
                    if ($cloudAad) { $authority = Test-TrustedAzureEndpoint -Value $cloudAad -KnownHosts @() -Label "az cloud '$cloudName' activeDirectory endpoint" -AnyHttpsHost -Warnings $warnings }
                    if ($cloudArm) { $arm = Test-TrustedAzureEndpoint -Value $cloudArm -KnownHosts @() -Label "az cloud '$cloudName' resourceManager endpoint" -AnyHttpsHost -Warnings $warnings }
                    if ($authority -and $arm) {
                        $name = $cloudName
                        $source = 'az cloud show (the active az cloud)'
                    }
                    elseif ($authority -or $arm) {
                        # Half a registered cloud is not a cloud (review finding): the
                        # missing half is never padded with the public-cloud default.
                        $unresolved = "az cloud '$cloudName' yields only one usable HTTPS endpoint of activeDirectory / resourceManager — half a cloud is not completed with the public-cloud default; re-register it with both endpoints (az cloud register) or select another cloud (az cloud set)"
                        $source = 'az cloud show (the active az cloud)'
                    }
                }
            }
        }
    }
    if (-not $unresolved -and -not $authority -and -not $arm) {
        $authority = 'https://login.microsoftonline.com'
        $arm = 'https://management.azure.com'
        $name = 'AzureCloud'
        $source = 'public-cloud default (no valid AZURE_AUTHORITY_HOST / ARM_ENDPOINT; az absent or its cloud unreadable)'
    }
    if ($unresolved) {
        $warnings.Add("unresolved cloud — $unresolved")
        return [pscustomobject]@{
            Name             = 'unresolved'
            Source           = $source
            Authority        = ''
            ArmResource      = ''
            ArmScope         = ''
            SubscriptionsUrl = ''
            Unresolved       = $unresolved
            Warnings         = $warnings.ToArray()
        }
    }
    $armBase = $arm.TrimEnd('/')
    [pscustomobject]@{
        Name             = $name
        Source           = $source
        Authority        = $authority.TrimEnd('/')
        ArmResource      = "$armBase/"
        ArmScope         = "$armBase/.default"
        SubscriptionsUrl = "$armBase/subscriptions?api-version=2022-12-01"
        Unresolved       = ''
        Warnings         = $warnings.ToArray()
    }
}
$azureCloud = Resolve-AzureCloudEndpoints
$armSubscriptionsUrl = $azureCloud.SubscriptionsUrl
$armScope = $azureCloud.ArmScope
$armResource = $azureCloud.ArmResource
$imdsUrl = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=$([uri]::EscapeDataString($armResource))"
$imdsTimeoutSec = 2   # HARD by design: a non-Azure host must fail fast, not hang.
$userAgent = 'helios-rest-connect'
# Exact owner runbook (ENTERPRISE_AI_CONNECTIONS.md §1 + setup-tenant.ps1 -OpsIdentity):
# one MFA login now, then the workload identity makes every future session automatic.
# Executable as written in PowerShell 7 AND bash (review finding): `&&` sequences the
# steps in both shells and the prose lives in a trailing comment; setup-tenant.ps1
# defaults to dry-run, so the -Apply switch is part of the command.
$azureOwnerAction = 'az login --tenant "349e1399-dccf-45b1-af7e-05d7b0676abf" && pwsh scripts/bootstrap/setup-tenant.ps1 -OpsIdentity -Apply   # MFA once at the login; the -Apply run then mints the ops service principal that makes every future session non-interactive'

# -Json promises one object and nothing else on stdout, and from an external caller's
# viewpoint Write-Host lands on stdout too — so all progress printing gates on it
# (stack-smoke.ps1 / auth-doctor.ps1 convention).
function Write-Report {
    param([string]$Message = '')
    if (-not $Json) { Write-Host $Message }
}

function Get-CliCommand {
    param([Parameter(Mandatory)][string]$Name)
    # Application only: OS subprocesses can never resolve a PowerShell alias/function
    # shadowing the name (auth-doctor.ps1 rationale).
    Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
}

# StrictMode-safe property access on parsed JSON: never dot into a property that a
# response variant may omit (stack-smoke.ps1 pattern).
function Get-OptionalProperty {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -ne $prop -and $null -ne $prop.Value) { return $prop.Value }
    return $Default
}

function New-LaneResult {
    param(
        [Parameter(Mandatory)][string]$Lane,
        [Parameter(Mandatory)]
        [ValidateSet('ready', 'needs-owner', 'unavailable', 'ci-delegated')]
        [string]$State,
        [Parameter(Mandatory)][string]$Source,
        [string]$Identity = '',
        [Parameter(Mandatory)][string]$Detail,
        [string]$OwnerAction = ''
    )
    [pscustomobject]@{
        lane        = $Lane
        state       = $State
        source      = $Source
        identity    = $Identity
        detail      = $Detail
        ownerAction = $OwnerAction
    }
}

# Capture ALL output first, THEN classify. -SkipHttpErrorCheck turns HTTP error statuses
# into data (a probe that throws on 401 could never walk a candidate chain); transport
# failures surface as Status 0. Headers may carry a bearer token: this function never
# logs, echoes, or stores them — they exist only for the duration of the request.
function Invoke-HttpProbe {
    param(
        [Parameter(Mandatory)][string]$Url,
        [string]$Method = 'Get',
        [hashtable]$Headers = @{},
        [string]$Body = '',
        [string]$ContentType = '',
        [int]$TimeoutSec = 20,
        [switch]$NoProxy
    )
    try {
        $request = @{
            Uri                = $Url
            Method             = $Method
            TimeoutSec         = $TimeoutSec
            SkipHttpErrorCheck = $true
            UserAgent          = $userAgent
        }
        if ($Headers.Count -gt 0) { $request['Headers'] = $Headers }
        if ($Body) { $request['Body'] = $Body }
        if ($ContentType) { $request['ContentType'] = $ContentType }
        # IMDS is link-local and must never be routed through HTTPS_PROXY — proxied,
        # it would neither reach 169.254.169.254 nor fail fast.
        if ($NoProxy) { $request['NoProxy'] = $true }
        $response = Invoke-WebRequest @request
        [pscustomobject]@{ Status = [int]$response.StatusCode; Body = [string]$response.Content; Transport = '' }
    }
    catch {
        [pscustomobject]@{ Status = 0; Body = ''; Transport = $_.Exception.Message }
    }
}

function Test-ParsedJson {
    param([string]$Text = '')
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    try { return ($Text | ConvertFrom-Json) } catch { return $null }
}

# Empty or whitespace counts as unset (review finding): CI shells commonly define
# variables as '' — a blank AZURE_CLIENT_CERTIFICATE_PATH must not arm the
# terminal certificate action with an unusable empty path (the same rule
# auto-login.ps1 applies to the provider env vars). The value is read only to
# test emptiness; it is never printed or stored.
function Test-EnvValue {
    param([Parameter(Mandatory)][string]$Name)
    # .NET API, never the env: drive (review finding): a config-derived name such as
    # API_* would be expanded as a wildcard by the provider, while the hub reads the
    # literal name through Environment.GetEnvironmentVariable.
    return -not [string]::IsNullOrWhiteSpace([string][Environment]::GetEnvironmentVariable($Name))
}
# Environment-variable NAME semantics follow the OS (review finding): case-sensitive on
# Linux/macOS, case-insensitive on Windows — used for every config-derived name compare.
$script:EnvNameComparer = if ($IsWindows) { [System.StringComparer]::OrdinalIgnoreCase } else { [System.StringComparer]::Ordinal }

# --- github lane ------------------------------------------------------------------------
# The github-models provider's CONFIGURED token variable (review finding): auto-login
# exports under whatever apiKeyEnv the active hub config declares (AIHUB_CONFIG beats
# the repo default, as AIHubService.ResolveConfigPath does) and ProviderFactory reads
# that same name — so the candidate walk must probe it too, not only fixed names.
# Any read problem falls back to the default name; nothing here is fatal.
# Enabled CLI agents that read a FIXED variable (review finding): an entry whose
# command leaf is `codex` reads OPENAI_API_KEY, one running `claude` reads
# ANTHROPIC_API_KEY (the canonical name counts only for an entry declaring no
# command) — auth-doctor's discovery rule. A Models entry pointed at either name shares
# it with a non-GitHub consumer, so that variable is never a GitHub candidate.
function Get-CliOwnedEnvNames {
    param([AllowNull()]$Config)
    $names = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Config -or -not $Config.PSObject.Properties['cliAgents'] -or $null -eq $Config.cliAgents) { return $names.ToArray() }
    foreach ($agent in @($Config.cliAgents)) {
        if ($null -eq $agent) { continue }
        if ($agent.PSObject.Properties['enabled'] -and $agent.enabled -eq $false) { continue }
        $cmd = if ($agent.PSObject.Properties['command'] -and $null -ne $agent.command) { ([string]$agent.command).Trim() } else { '' }
        $leaf = ''
        if ($cmd) { try { $leaf = [System.IO.Path]::GetFileNameWithoutExtension($cmd) } catch { $leaf = $cmd } }
        $agentName = if ($agent.PSObject.Properties['name'] -and $null -ne $agent.name) { ([string]$agent.name).Trim() } else { '' }
        $key = if ($leaf) { $leaf.ToLowerInvariant() } elseif (-not $cmd) { $agentName.ToLowerInvariant() } else { '' }
        if ($key -eq 'codex') { $names.Add('OPENAI_API_KEY') }
        elseif ($key -in 'claude', 'claude-cli') { $names.Add('ANTHROPIC_API_KEY') }
    }
    return $names.ToArray()
}

function Get-ConfiguredGitHubModelsEnvs {
    # Enabled providers of TYPE github-models (review finding: ProviderFactory
    # dispatches on provider.type, never on a canonical key), each contributing its
    # apiKeyEnv — or the factory default GITHUB_MODELS_TOKEN when unset — but ONLY
    # when the provider resolves to the public GitHub Models endpoint (no baseUrl,
    # or a baseUrl on models.github.ai). A credential bound to a custom baseUrl
    # belongs to THAT endpoint and must never be sent to api.github.com (review
    # finding: the verifier would otherwise disclose an unrelated service credential
    # to GitHub). Unreadable config → the default name; a parsed config with no
    # qualifying provider → no candidate from config at all.
    $default = 'GITHUB_MODELS_TOKEN'
    $explicitProfile = Test-EnvValue 'AIHUB_CONFIG'
    $configPath = if ($explicitProfile) { ([string]$env:AIHUB_CONFIG).Trim() }
    else { Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'config' 'aihub.json' }
    # An EXPLICITLY selected profile the hub cannot load contributes NO candidate
    # (review finding): the built-in name would be an invented profile's, and the
    # dry-run walk must say why instead. Only the unreadable REPO DEFAULT keeps it.
    $script:configuredModelsNote = ''
    $script:nonGitHubReaderEnvs = [System.Collections.Generic.HashSet[string]]::new($script:EnvNameComparer)
    $unreadableExplicit = "(AIHUB_CONFIG selects '$configPath' but it is missing, unparseable, or not a JSON object — the hub cannot load it either; no config candidate)"
    try {
        $parsed = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        # The hub binds the document to an object; anything else is unreadable to it too.
        if ($parsed -isnot [System.Management.Automation.PSCustomObject]) {
            if ($explicitProfile) { $script:configuredModelsNote = $unreadableExplicit; return @() }
            return @($default)
        }
        # An absent providers section is an EMPTY table (review finding):
        # AIHubOptions.Providers starts empty, so the hub loads a CLI-only profile and
        # instantiates no github-models provider from it — no candidate, not the default.
        # An EXPLICIT null is different (review finding): the hub fails enumerating it,
        # so there is no hub to probe for and the walk says so.
        $providersProp = $parsed.PSObject.Properties['providers']
        if ($null -ne $providersProp -and $null -eq $providersProp.Value) {
            $script:configuredModelsNote = "(the active config '$configPath' declares `"providers`": null — ProviderFactory.CreateAll cannot enumerate it and the hub fails to start; no config candidate)"
            return @()
        }
        $providers = Get-OptionalProperty $parsed 'providers'
        if ($null -eq $providers) { return @() }
        # Pass 1 — every enabled KEYED entry (github-models, openai, anthropic,
        # azure-openai) that reads a variable, with whether it is a PUBLIC github-models
        # provider. apiKeyEnv follows ProviderFactory exactly (review finding): the
        # per-type default applies only when the property is absent/null; a
        # declared-blank name means the hub reads NO variable (SecretResolver skips a
        # blank name), so there is nothing to probe for that entry.
        $entries = [System.Collections.Generic.List[object]]::new()
        foreach ($prop in $providers.PSObject.Properties) {
            $prov = $prop.Value
            # A null or non-object ENTRY fails the hub too (review finding):
            # AIHubOptions binds Dictionary<string, ProviderOptions> and CreateAll
            # dereferences every entry, so there is no hub to probe for — the walk
            # says so instead of quietly skipping the entry.
            if ($null -eq $prov -or $prov -isnot [System.Management.Automation.PSCustomObject]) {
                $script:configuredModelsNote = "(the active config '$configPath' declares providers.$($prop.Name) as $(if ($null -eq $prov) { 'null' } else { 'a non-object' }) — ProviderFactory.CreateAll dereferences every provider entry and the hub fails to start; no config candidate)"
                return @()
            }
            $provType = ([string](Get-OptionalProperty $prov 'type' '')).Trim().ToLowerInvariant()
            $typeDefault = switch ($provType) {
                'github-models' { $default }
                'openai' { 'OPENAI_API_KEY' }
                'anthropic' { 'ANTHROPIC_API_KEY' }
                'azure-openai' { 'AZURE_OPENAI_API_KEY' }
                default { '' }
            }
            if (-not $typeDefault) { continue }   # keyless types read no variable
            if ((Get-OptionalProperty $prov 'enabled' $true) -eq $false) { continue }
            $envProp = $prov.PSObject.Properties['apiKeyEnv']
            $envName = if ($null -eq $envProp -or $null -eq $envProp.Value) { $typeDefault } else { ([string]$envProp.Value).Trim() }
            if (-not $envName) { continue }
            $isPublicModels = $false
            if ($provType -eq 'github-models') {
                # Public means the exact HTTPS origin (review finding): an http:// or
                # non-http(s) URL on the public host never gets a GitHub credential.
                $isPublicModels = $true
                $baseUrl = ([string](Get-OptionalProperty $prov 'baseUrl' '')).Trim()
                if ($baseUrl) {
                    $isPublicModels = $false
                    $parsedBase = $null
                    if ([uri]::TryCreate($baseUrl, [System.UriKind]::Absolute, [ref]$parsedBase)) {
                        $isPublicModels = ($parsedBase.Scheme -eq 'https' -and $parsedBase.Host.Equals('models.github.ai', [System.StringComparison]::OrdinalIgnoreCase))
                    }
                }
            }
            $entries.Add([pscustomobject]@{ Env = $envName; PublicModels = $isPublicModels })
        }
        # CLI-owned variables (review finding): an enabled codex agent reads the fixed
        # OPENAI_API_KEY and an enabled claude agent ANTHROPIC_API_KEY, so a Models
        # entry pointed at either name shares it with a non-GitHub consumer.
        foreach ($cliOwned in @(Get-CliOwnedEnvNames -Config $parsed)) {
            $entries.Add([pscustomobject]@{ Env = $cliOwned; PublicModels = $false })
        }
        # Pass 2 — a variable is a candidate only when EVERY enabled entry reading it
        # is a PUBLIC github-models provider (review findings, mixed and cross-type
        # ownership): one also read by a custom-baseUrl Models entry or by an
        # openai/anthropic/azure-openai entry may hold THAT service's credential,
        # which must never be sent to api.github.com — the same rule auto-login.ps1
        # applies before exporting into such a variable. Names compare under the OS
        # rule (case-sensitive on Unix — review finding).
        $names = [System.Collections.Generic.List[string]]::new()
        $seenNames = [System.Collections.Generic.HashSet[string]]::new($script:EnvNameComparer)
        # Every variable a NON-GitHub consumer reads is remembered (review finding):
        # the two fixed candidates GH_TOKEN / GITHUB_TOKEN bypass this function's
        # result, yet an openai/anthropic/azure-openai entry or a CLI agent may be
        # configured to read exactly those names — their value then belongs to that
        # service and must not be sent to api.github.com either.
        foreach ($entry in $entries) {
            if (-not $entry.PublicModels) { [void]$script:nonGitHubReaderEnvs.Add($entry.Env) }
        }
        foreach ($entry in $entries) {
            if (-not $seenNames.Add($entry.Env)) { continue }
            if (@($entries | Where-Object { $script:EnvNameComparer.Equals($_.Env, $entry.Env) -and -not $_.PublicModels }).Count) { continue }
            $names.Add($entry.Env)
        }
        return @($names)
    }
    catch {
        if ($explicitProfile) { $script:configuredModelsNote = $unreadableExplicit; return @() }
        return @($default)
    }
}

function Get-GitHubTokenCandidates {
    # Candidate ORDER is the contract: explicit env wins over the CLI keyring, and
    # GH_TOKEN (gh's own precedence rule) wins over GITHUB_TOKEN. GITHUB_MODELS_TOKEN
    # is third (review finding): it is a real github.com credential — config/aihub.json
    # and ProviderFactory treat it as the github-models provider's primary token, and
    # auto-login.ps1 exports exactly this variable from Key Vault — so a host whose
    # ONLY GitHub credential is the models token must not read as lane-unavailable.
    # Token values are read into the candidate objects here and die when the github
    # lane function returns — they are never interpolated into any reported string.
    $candidates = [System.Collections.Generic.List[object]]::new()
    $script:candidateNotes = [System.Collections.Generic.List[string]]::new()
    # Third slot is the CONFIGURED models env (GITHUB_MODELS_TOKEN by default) —
    # review finding: a renamed apiKeyEnv must still be probed. The configured list
    # is resolved FIRST so the non-GitHub reader set it records is complete before
    # the two fixed names are screened against it.
    $configuredEnvs = @(Get-ConfiguredGitHubModelsEnvs)
    foreach ($envName in @(@('GH_TOKEN', 'GITHUB_TOKEN') + $configuredEnvs | Select-Object -Unique)) {
        # The fixed names are screened too (review finding): a provider or CLI agent
        # configured to read GH_TOKEN / GITHUB_TOKEN owns that value — auto-login may
        # even have populated it from that provider's Key Vault secret — so it is that
        # service's credential, never a GitHub candidate.
        if ($script:nonGitHubReaderEnvs.Contains($envName)) {
            $script:candidateNotes.Add("env:$envName is read by an enabled non-GitHub consumer in the active config (openai / anthropic / azure-openai / custom-endpoint provider or CLI agent) — its value belongs to that service and was not offered to api.github.com")
            continue
        }
        # Literal name through the .NET API (review finding): the env: drive would
        # expand wildcard characters in a config-derived name.
        $value = [string][Environment]::GetEnvironmentVariable($envName)
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $candidates.Add([pscustomobject]@{ Source = "env:$envName"; Token = $value.Trim() })
        }
    }
    $ghCmd = Get-CliCommand -Name 'gh'
    if ($ghCmd) {
        # Capture output BEFORE reading $LASTEXITCODE (StrictMode rule: a pipeline that
        # stops early can leave $LASTEXITCODE unassigned). `gh auth token` may fail —
        # that is fine, the chain just has one fewer candidate.
        # --hostname github.com (review finding): with GH_HOST pointing at a GitHub
        # Enterprise host, an unqualified `gh auth token` would hand back the
        # ENTERPRISE credential — which this lane would then send to api.github.com,
        # disclosing it to the wrong control plane.
        # Env-cleared (review finding): gh gives GH_TOKEN/GITHUB_TOKEN precedence
        # over its keyring, so with a stale env token set an unqualified call would
        # echo the same candidate the chain already tested instead of the STORED
        # login. The two shadowing variables are removed for this one call and
        # restored immediately — values move only between env slots in-process.
        $savedGhToken = $env:GH_TOKEN
        $savedGithubToken = $env:GITHUB_TOKEN
        try {
            Remove-Item env:GH_TOKEN -ErrorAction SilentlyContinue
            Remove-Item env:GITHUB_TOKEN -ErrorAction SilentlyContinue
            $tokenLines = @(& $ghCmd.Source auth token --hostname github.com 2>$null)
            $ghExit = $LASTEXITCODE
        }
        finally {
            if ($null -ne $savedGhToken) { $env:GH_TOKEN = $savedGhToken }
            if ($null -ne $savedGithubToken) { $env:GITHUB_TOKEN = $savedGithubToken }
        }
        $ghToken = (@($tokenLines) -join '').Trim()
        $alreadyCandidate = @($candidates | Where-Object { $_.Token -eq $ghToken }).Count -gt 0
        if ($ghExit -eq 0 -and -not [string]::IsNullOrWhiteSpace($ghToken) -and -not $alreadyCandidate) {
            $candidates.Add([pscustomobject]@{ Source = 'gh-cli'; Token = $ghToken })
        }
    }
    return $candidates
}

function Test-GitHubLane {
    # TRANSPORT CONTROL PROBE FIRST (review finding): a credential-injecting proxy
    # makes every candidate token look valid — a garbage Bearer and no Authorization
    # header at all both came back 200/15000-per-hour in the measured environment. An
    # anonymous request is the control: unauthenticated GitHub is capped at 60/hr, so
    # a no-auth 200 above that cap proves an intermediary owns the session, and
    # per-candidate validity CANNOT be asserted from this host.
    $anonHeaders = @{
        Accept                 = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
    }
    $anonProbe = Invoke-HttpProbe -Url "$gitHubApi/rate_limit" -Headers $anonHeaders -TimeoutSec $TimeoutSeconds
    if ($anonProbe.Status -eq 200) {
        $anonParsed = Test-ParsedJson $anonProbe.Body
        $anonRate = Get-OptionalProperty $anonParsed 'rate'
        $anonLimit = [string](Get-OptionalProperty $anonRate 'limit' 'unknown')
        # Injection is asserted only on a NUMERIC limit above the anonymous 60/hr cap
        # (review finding: an unexpected body shape parsing to 'unknown' must fall
        # through to the per-candidate walk, not falsely classify the transport).
        $anonLimitValue = 0
        $anonLimitIsNumeric = [int]::TryParse($anonLimit, [ref]$anonLimitValue)
        # -gt, not -ne (review finding): injection is only proven by a limit ABOVE the
        # anonymous 60/hr cap — a numeric-but-bogus payload (limit 0) must fall
        # through to the per-candidate walk like any other malformed body.
        if ($anonLimitIsNumeric -and $anonLimitValue -gt 60) {
            $anonIdentity = 'unknown'
            $anonUser = Invoke-HttpProbe -Url "$gitHubApi/user" -Headers $anonHeaders -TimeoutSec $TimeoutSeconds
            if ($anonUser.Status -eq 200) {
                $anonUserParsed = Test-ParsedJson $anonUser.Body
                $anonIdentity = [string](Get-OptionalProperty $anonUserParsed 'login' 'unknown (no login field in /user)')
            }
            return New-LaneResult -Lane 'github' -State 'ready' `
                -Source 'transport (proxy-injected credentials)' -Identity $anonIdentity `
                -Detail ("GitHub REST is live THROUGH the transport: an anonymous probe (no Authorization " +
                    "header) answered 200 with rate limit $anonLimit/hr where unauthenticated GitHub is " +
                    'capped at 60/hr — a credential-injecting proxy owns this session. Per-candidate token ' +
                    'validity cannot be asserted from this host, so env/CLI tokens are deliberately NOT ' +
                    'attributed; do not copy a token elsewhere on the strength of this result.')
        }
    }

    $candidates = Get-GitHubTokenCandidates
    if (@($candidates).Count -eq 0) {
        # unavailable is ONLY "no candidate token present": Invoke-WebRequest is built
        # into PowerShell 7, so there is no missing-HTTP-client case on this lane.
        return New-LaneResult -Lane 'github' -State 'unavailable' -Source 'none' `
            -Detail ('no candidate token present: GH_TOKEN and GITHUB_TOKEN are unset and the gh CLI ' +
                'yielded no token (absent, logged out, or `gh auth token` failed) — nothing to probe')
    }

    $attemptNotes = [System.Collections.Generic.List[string]]::new()
    # A fixed candidate screened out because a non-GitHub consumer reads it is
    # evidence the operator must see (review finding): the walk would otherwise
    # look as if the variable had simply been empty.
    foreach ($screenedNote in @($script:candidateNotes)) { $attemptNotes.Add($screenedNote) }
    $sawDefinitiveRejection = $false
    $rejectedEnvSources = [System.Collections.Generic.List[string]]::new()
    foreach ($candidate in $candidates) {
        $sourceName = [string]$candidate.Source
        # The bearer value exists only inside this header hashtable for the two probes
        # below; it is never written anywhere else.
        $headers = @{
            Authorization          = "Bearer $($candidate.Token)"
            Accept                 = 'application/vnd.github+json'
            'X-GitHub-Api-Version' = '2022-11-28'
        }

        # On a CLEAN transport (the anonymous control probe above came back capped or
        # rejected) the wire IS the per-token ground truth — a fine-grained or app
        # token can be fully REST-valid while `gh auth status` exits 1, so REST
        # connectivity is asserted with a direct call, not a CLI's opinion.
        $rateProbe = Invoke-HttpProbe -Url "$gitHubApi/rate_limit" -Headers $headers -TimeoutSec $TimeoutSeconds
        if ($rateProbe.Status -eq 200) {
            $rateParsed = Test-ParsedJson $rateProbe.Body
            $rate = Get-OptionalProperty $rateParsed 'rate'
            $remaining = [string](Get-OptionalProperty $rate 'remaining' 'unknown')
            $limit = [string](Get-OptionalProperty $rate 'limit' 'unknown')
            # Same payload discipline as the anonymous control (review finding): a 200
            # whose body is not a real rate-limit payload (intermediary HTML, garbage
            # JSON) proves nothing about THIS token — note it and try the next
            # candidate instead of declaring ready on unknown/unknown.
            $authLimitValue = 0
            if ($null -eq $rateParsed -or -not [int]::TryParse($limit, [ref]$authLimitValue)) {
                $attemptNotes.Add("$sourceName rate_limit 200 but the body is not a parseable GitHub rate-limit payload (intermediary?)")
                continue
            }
            # Above the anonymous cap only (review finding): an intermediary that
            # STRIPS the Authorization header makes the candidate's request
            # effectively anonymous — GitHub then answers a legitimate 200 at the
            # 60/hr cap, which is parseable but proves nothing about THIS token
            # (every authenticated GitHub limit starts at 1000/hr). The anonymous
            # control probe above already fell through in that scenario, so the
            # same cap must gate the per-candidate attribution too.
            if ($authLimitValue -le 60) {
                $attemptNotes.Add("$sourceName rate_limit 200 but at the anonymous cap ($limit/hr) — Authorization likely stripped in transit; validity not attributed to this token")
                continue
            }

            # Identity is best-effort: some REST-valid token types (fine-grained with
            # narrow scopes, app installation tokens) cannot call /user. That does NOT
            # demote readiness — rate_limit 200 already proved the token.
            $identity = ''
            $userProbe = Invoke-HttpProbe -Url "$gitHubApi/user" -Headers $headers -TimeoutSec $TimeoutSeconds
            if ($userProbe.Status -eq 200) {
                $userParsed = Test-ParsedJson $userProbe.Body
                $identity = [string](Get-OptionalProperty $userParsed 'login' 'unknown (no login field in /user)')
            }
            elseif ($userProbe.Status -in 401, 403) {
                $identity = 'unknown (token valid; /user not permitted for this token type)'
            }
            else {
                $userStatus = if ($userProbe.Status -eq 0) { "transport: $($userProbe.Transport)" } else { "HTTP $($userProbe.Status)" }
                $identity = "unknown (/user $userStatus)"
            }

            $skippedNote = if ($attemptNotes.Count -gt 0) { '; earlier candidates: ' + ($attemptNotes -join '; ') } else { '' }
            return New-LaneResult -Lane 'github' -State 'ready' -Source $sourceName -Identity $identity `
                -Detail ("rate_limit 200 with $remaining/$limit core requests remaining this hour — the token is " +
                    "REST-valid on the wire (the REST probe is the ground truth: 'gh auth status' can exit 1 for " +
                    "this exact token; token value never printed)$skippedNote")
        }
        if ($rateProbe.Status -eq 401) {
            $sawDefinitiveRejection = $true
            $attemptNotes.Add("$sourceName rate_limit 401 (candidate not REST-valid)")
            if ($sourceName -like 'env:*') { $rejectedEnvSources.Add($sourceName.Substring(4)) }
        }
        elseif ($rateProbe.Status -eq 0) {
            $attemptNotes.Add("$sourceName transport failure ($($rateProbe.Transport))")
        }
        else {
            $attemptNotes.Add("$sourceName rate_limit HTTP $($rateProbe.Status)")
        }
    }

    $chainText = $attemptNotes -join '; '
    # Re-login advice only on a DEFINITIVE rejection (review finding): a 401 proves a
    # candidate credential is bad, but transport failures / 429 / 5xx are transient —
    # rotating a healthy token on those would destroy a working credential for nothing.
    if (-not $sawDefinitiveRejection) {
        return New-LaneResult -Lane 'github' -State 'unavailable' -Source 'none' `
            -Detail ("no candidate got a definitive answer from api.github.com — every attempt was transient " +
                "(transport/429/5xx): $chainText — retry later; do NOT rotate credentials on this evidence")
    }
    # The action must be runnable on THIS host (review finding): with gh absent, a bare
    # `gh auth login` cannot execute — name the rejected variable(s) for rotation and
    # put the CLI installation before the login command.
    $ghOnPath = [bool](Get-Command gh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
    $rotateAction = if ($rejectedEnvSources.Count -gt 0) { "rotate $(@($rejectedEnvSources | Select-Object -Unique) -join ' / ') (each answered 401 from api.github.com) with a valid token" } else { '' }
    $loginAction = if ($ghOnPath) { 'gh auth login --web   # device-code flow' } else { 'bash scripts/bootstrap/cloud-shell-setup.sh && gh auth login --web   # step 1 installs the GitHub CLI (or https://cli.github.com); then the device-code flow' }
    return New-LaneResult -Lane 'github' -State 'needs-owner' -Source 'none' `
        -Detail ("every candidate token failed the direct REST probe: $chainText — a rotated token in the rejected variable, or a fresh device-code login, is an owner step") `
        -OwnerAction ((@($rotateAction, $loginAction) | Where-Object { $_ }) -join '; or: ')
}

# --- azure lane -------------------------------------------------------------------------
# Probes ARM with an acquired token. Returns {Outcome; Lane}: 'ready' (Lane = the ready
# result), 'forbidden' (Lane = a needs-owner RBAC diagnosis the CALLER stashes and only
# uses if no later chain entry succeeds — review finding: an early 403 must not stop a
# later authorized candidate), 'auth-rejected' (definitive 401 — the caller marks the
# rejection flag), or 'transient' (transport/5xx/garbage — never grounds for credential
# advice). The token parameter exists only for the Authorization header — never logged.
function Invoke-ArmProbe {
    param(
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Identity,
        [Parameter(Mandatory)][System.Collections.Generic.List[string]]$ChainNotes
    )
    $probe = Invoke-HttpProbe -Url $armSubscriptionsUrl -Headers @{ Authorization = "Bearer $Token" } -TimeoutSec $TimeoutSeconds
    if ($probe.Status -eq 200) {
        $parsed = Test-ParsedJson $probe.Body
        # A 200 whose body is not a real subscriptions payload (HTML from an
        # intermediary, malformed JSON, no 'value' ARRAY) proves NOTHING (review
        # finding) — and `value` must actually BE an array: a scalar there would
        # otherwise get wrapped into a one-item collection and fabricate a
        # subscription count out of an error body.
        # Direct property access, no helper (review finding): a PowerShell function
        # return ENUMERATES arrays crossing the boundary — zero visible
        # subscriptions came back $null and exactly one came back a scalar, so the
        # array check below rejected perfectly valid ARM responses.
        $armValue = $null
        if ($null -ne $parsed) {
            $armValueProp = $parsed.PSObject.Properties['value']
            if ($null -ne $armValueProp) { $armValue = $armValueProp.Value }
        }
        if ($null -eq $parsed -or -not ($armValue -is [array])) {
            $ChainNotes.Add("$Source ARM answered 200 but the body is not a parseable subscriptions payload with a 'value' array (intermediary?) — not treated as connectivity proof")
            return [pscustomobject]@{ Outcome = 'transient'; Lane = $null }
        }
        $subs = @($armValue)
        $subCount = $subs.Count
        # Display name + id are identifiers, not secrets (connect-account.ps1 rule:
        # pinning identities is the point).
        $firstText = 'no subscriptions visible to this principal'
        if ($subCount -gt 0) {
            $first = $subs[0]
            $firstName = [string](Get-OptionalProperty $first 'displayName' 'unnamed')
            $firstId = [string](Get-OptionalProperty $first 'subscriptionId' 'unknown-id')
            $firstText = "first: '$firstName' ($firstId)"
        }
        return [pscustomobject]@{
            Outcome = 'ready'
            Lane    = (New-LaneResult -Lane 'azure' -State 'ready' -Source $Source -Identity $Identity `
                -Detail ("ARM /subscriptions 200 — $subCount subscription(s); $firstText (token value never printed)"))
        }
    }
    if ($probe.Status -eq 403) {
        # AUTHORIZATION, not authentication (review finding): the token is real and
        # ARM recognized the principal — it just lacks an RBAC role, and re-login can
        # never fix that. The diagnosis is deferred: a later chain entry may still be
        # authorized (second review finding), so the caller stashes this and returns
        # it only if nothing later succeeds.
        $ChainNotes.Add("$Source acquired a token but ARM answered 403 — principal lacks an RBAC role (diagnosis kept; chain continues)")
        return [pscustomobject]@{
            Outcome = 'forbidden'
            Lane    = (New-LaneResult -Lane 'azure' -State 'needs-owner' -Source $Source -Identity $Identity `
                -Detail ('a valid token was acquired but ARM answered 403 — the principal lacks an RBAC role ' +
                    'on the subscription; re-authentication cannot grant permissions') `
                -OwnerAction ("grant the principal an RBAC role (e.g. Reader) on the target subscription/resource " +
                    "group — az role assignment create --assignee <principal> --role Reader --scope <scope> " +
                    '(role assignment is deliberately owner-gated in this repo)'))
        }
    }
    if ($probe.Status -eq 401) {
        $ChainNotes.Add("$Source acquired a token but ARM answered HTTP 401 — the token itself was rejected")
        return [pscustomobject]@{ Outcome = 'auth-rejected'; Lane = $null }
    }
    elseif ($probe.Status -eq 0) {
        $ChainNotes.Add("$Source acquired a token but the ARM probe hit a transport failure ($($probe.Transport))")
    }
    else {
        $ChainNotes.Add("$Source acquired a token but ARM answered HTTP $($probe.Status)")
    }
    return [pscustomobject]@{ Outcome = 'transient'; Lane = $null }
}

function Test-AzureLane {
    $chainNotes = [System.Collections.Generic.List[string]]::new()
    # An ignored endpoint override is part of the lane's evidence (review finding): the
    # operator must see that their AZURE_AUTHORITY_HOST / ARM_ENDPOINT was NOT used.
    foreach ($cloudWarning in @($azureCloud.Warnings)) { $chainNotes.Add("cloud: $cloudWarning") }
    if ($azureCloud.Unresolved) {
        # No cloud, no request (review finding): a mixed or half endpoint pair would
        # post AZURE_CLIENT_SECRET to one cloud's authority for another cloud's scope,
        # or present a sovereign token to the public Resource Manager — every rung
        # would fail and the terminal advice would prescribe a public-cloud login.
        return New-LaneResult -Lane 'azure' -State 'needs-owner' -Source 'cloud-config' `
            -Detail ("the Azure control-plane endpoints do not resolve to ONE cloud, so no credential source was tried and nothing was sent anywhere: $($chainNotes -join '; ')") `
            -OwnerAction 'set AZURE_AUTHORITY_HOST and AZURE_RESOURCE_MANAGER_ENDPOINT (or ARM_ENDPOINT) to the SAME cloud — e.g. https://login.microsoftonline.us + https://management.usgovcloudapi.net for Azure Government — or unset both and select the cloud with: az cloud set --name <AzureCloud|AzureUSGovernment|AzureChinaCloud|registered-name>'
    }
    $chainNotes.Add("cloud: $($azureCloud.Name) (authority $($azureCloud.Authority), ARM $($azureCloud.ArmResource); from $($azureCloud.Source))")
    # 1. CI OIDC — AVAILABILITY evidence, not a completed login (review finding):
    #    GitHub sets ACTIONS_ID_TOKEN_REQUEST_URL the moment a job grants
    #    `id-token: write`, including in jobs that never run azure/login. So its
    #    presence no longer short-circuits the chain: the walk continues probing for
    #    a token that actually exists (azure/login's product surfaces at the az-cache
    #    rung), and only when no rung holds one does the lane end ci-delegated with
    #    the azure/login prerequisite stated. The OIDC exchange itself is still never
    #    duplicated (or raced) here.
    $ciOidcAvailable = Test-Path env:ACTIONS_ID_TOKEN_REQUEST_URL
    if ($ciOidcAvailable) {
        $chainNotes.Add('ci-oidc: ACTIONS_ID_TOKEN_REQUEST_URL present — OIDC is available to this job (azure/login owns the exchange; never duplicated here)')
    }

    $azCmd = Get-CliCommand -Name 'az'
    # Failure classification across the whole chain (review findings): a 403 RBAC
    # diagnosis is stashed and only used if nothing later succeeds; MFA/re-login
    # advice requires at least one DEFINITIVE auth rejection — transient-only runs
    # (transport/429/5xx) end as unavailable-retryable, never credential advice.
    $armForbidden = $null
    $sawAuthRejection = $false
    # A DECLARED managed-identity endpoint answering 401/403 is a configuration
    # failure (review finding): the identity header/secret or the endpoint wiring is
    # wrong, and "retry later" cannot repair it — it gets its own terminal verdict.
    $miAuthRejected = $false
    # No-candidate detection (review finding): "transient — retry later" is only
    # honest when a credential source actually EXISTED and failed. On a fresh
    # non-Azure host (no SP env vars, no managed-identity endpoint, no az CLI) no
    # outage recovery can ever help, so the sources are tracked and their total
    # absence reports as unavailable WITH the setup path instead of retry advice.
    $credentialSourcePresent = $false
    # Token-held tracking (review finding): once ANY rung obtained a token and probed
    # ARM, a later transient failure (timeout/429/5xx/garbage) is an outage, not an
    # unexchanged OIDC — in an Actions job where azure/login already populated the
    # az cache, "add the azure/login step" would prescribe a step that has run.
    $tokenHeld = $false

    # 2. Env service principal — fully non-interactive. Secret variant: the credential
    #    values are read into locals, flow into an in-memory POST body, and die with
    #    this scope; the response token lives in a local and only ever becomes an
    #    Authorization header. Nothing from this exchange is echoed.
    # Preference note (deliberate divergence, documented): auth-doctor -Apply prefers
    # the CERTIFICATE when both credentials are present; this report-only script
    # prefers the SECRET, because the secret flow is pure in-memory REST while the
    # certificate flow requires an az login that mutates the shared profile — which a
    # diagnostic run must never do (see the cert rung below).
    $spSecretReady = (Test-EnvValue 'AZURE_CLIENT_ID') -and (Test-EnvValue 'AZURE_TENANT_ID') -and
        (Test-EnvValue 'AZURE_CLIENT_SECRET')
    # Cert availability is INDEPENDENT of the secret (review finding): during
    # credential rotation a stale secret with a valid certificate is a normal state,
    # and the cert path must still be reported after the secret exchange fails.
    $spCertReady = (Test-EnvValue 'AZURE_CLIENT_ID') -and
        (Test-EnvValue 'AZURE_TENANT_ID') -and (Test-EnvValue 'AZURE_CLIENT_CERTIFICATE_PATH')
    # A set-but-missing certificate FILE cannot run the flow either (review
    # finding): auth-doctor -Apply would just fail on the same absent file, so the
    # terminal cert action must not be armed. Path existence only — contents are
    # never read here.
    # -PathType Leaf (review finding): a directory at that path passes a bare
    # Test-Path, and the epilogue would then advertise auth-doctor -Apply — which
    # requires a leaf itself and skips the certificate — as a working repair.
    if ($spCertReady -and -not (Test-Path -LiteralPath ([string]$env:AZURE_CLIENT_CERTIFICATE_PATH).Trim() -PathType Leaf)) {
        $chainNotes.Add('env-service-principal-cert: AZURE_CLIENT_CERTIFICATE_PATH is set but no FILE exists at that path (a directory does not count) — the certificate flow cannot run until the file is present (path checked only, contents never read)')
        $spCertReady = $false
    }
    if ($spSecretReady) {
        $credentialSourcePresent = $true
        $clientId = [string]$env:AZURE_CLIENT_ID     # appId — an identifier, not a secret
        $tenantId = [string]$env:AZURE_TENANT_ID
        $body = ('grant_type=client_credentials&client_id={0}&client_secret={1}&scope={2}' -f
            [uri]::EscapeDataString($clientId),
            [uri]::EscapeDataString([string]$env:AZURE_CLIENT_SECRET),
            [uri]::EscapeDataString($armScope))
        $tokenUrl = "$($azureCloud.Authority)/$tenantId/oauth2/v2.0/token"   # the active cloud's authority
        $tokenProbe = Invoke-HttpProbe -Url $tokenUrl -Method 'Post' -Body $body `
            -ContentType 'application/x-www-form-urlencoded' -TimeoutSec $TimeoutSeconds
        $body = ''   # done with the credential material
        if ($tokenProbe.Status -eq 200) {
            $tokenReply = Test-ParsedJson $tokenProbe.Body
            $spToken = [string](Get-OptionalProperty $tokenReply 'access_token' '')
            if ($spToken) {
                $tokenHeld = $true
                $arm = Invoke-ArmProbe -Token $spToken -Source 'env-service-principal' `
                    -Identity "service principal $clientId" -ChainNotes $chainNotes
                if ($arm.Outcome -eq 'ready') { return $arm.Lane }
                if ($arm.Outcome -eq 'forbidden' -and $null -eq $armForbidden) { $armForbidden = $arm.Lane }
                if ($arm.Outcome -eq 'auth-rejected') { $sawAuthRejection = $true }
            }
            else {
                $chainNotes.Add('env-service-principal: token endpoint 200 but no access_token field (raw body never echoed)')
            }
        }
        else {
            $spStatus = if ($tokenProbe.Status -eq 0) { "transport failure ($($tokenProbe.Transport))" } else { "HTTP $($tokenProbe.Status)" }
            $chainNotes.Add("env-service-principal: token endpoint $spStatus (raw error body never echoed)")
            # 400/401 from the token endpoint = the SP credential itself was rejected
            # (invalid_client and friends) — a definitive rejection, unlike 5xx/transport.
            if ($tokenProbe.Status -in 400, 401) { $sawAuthRejection = $true }
        }
    }
    # Independent `if`, not `elseif` (review finding): when a configured secret FAILS
    # its exchange, the certificate's availability must still be reported — otherwise
    # a normal rotation state (stale secret, valid cert) dead-ends in MFA advice.
    # A secret SUCCESS never reaches here (it returned above).
    if ($spCertReady) {
        $credentialSourcePresent = $true
        # Certificate variant: the OAuth client assertion is a signed JWT — hand-rolling
        # that signature would re-implement a solved, security-critical flow, and the
        # az-delegated route (`az login --service-principal --certificate`) REWRITES the
        # shared ~/.azure profile, which a report-only script must never do (review
        # finding: the sibling auth-doctor.ps1 runs that exact login only under -Apply).
        # So this rung only REPORTS availability; the mutation belongs to auth-doctor
        # -Apply or the operator.
        $chainNotes.Add('env-service-principal-cert: AZURE_CLIENT_CERTIFICATE_PATH is set — the certificate ' +
            'flow is AVAILABLE but deliberately not executed report-only (az login rewrites the shared az ' +
            'profile). Non-interactive path: pwsh scripts/bootstrap/auth-doctor.ps1 -Apply, or manually: ' +
            'az login --service-principal --username $AZURE_CLIENT_ID --tenant $AZURE_TENANT_ID ' +
            '--certificate $AZURE_CLIENT_CERTIFICATE_PATH && az account get-access-token --resource-type arm')
    }
    if (-not $spSecretReady -and -not $spCertReady) {
        $chainNotes.Add('env-service-principal: AZURE_CLIENT_ID/AZURE_TENANT_ID + credential not all set (names checked only)')
    }

    # 3. Managed identity — endpoint env vars first (App Service / Functions / Container
    #    Apps and the legacy MSI shape), else raw IMDS with the hard 2s no-proxy timeout.
    $miProbe = $null
    $miKind = ''
    # Non-whitespace values only (review finding): an EMPTY IDENTITY_ENDPOINT must
    # not win the branch on mere existence — it would build a relative URL and
    # shadow a valid legacy MSI_ENDPOINT sitting right next to it.
    # A declared endpoint is validated BEFORE any header exists (review finding): the
    # identity header / secret is read only after the URL passed the local-host shape
    # check, so a bad value never sees a credential-bearing request.
    $miEndpointRejected = $false
    if (Test-EnvValue 'IDENTITY_ENDPOINT') {
        $miKind = 'identity-endpoint'
        $miBase = Test-TrustedManagedIdentityEndpoint -Value ([string]$env:IDENTITY_ENDPOINT) -Label 'IDENTITY_ENDPOINT' -Notes $chainNotes
        if ($miBase) {
            $miHeaders = @{}
            if (Test-Path env:IDENTITY_HEADER) { $miHeaders['X-IDENTITY-HEADER'] = [string]$env:IDENTITY_HEADER }
            $miUrl = "$miBase`?api-version=2019-08-01&resource=$([uri]::EscapeDataString($armResource))"
            $miProbe = Invoke-HttpProbe -Url $miUrl -Headers $miHeaders -TimeoutSec $TimeoutSeconds -NoProxy
        }
        else { $miEndpointRejected = $true }
    }
    elseif (Test-EnvValue 'MSI_ENDPOINT') {
        $miKind = 'msi-endpoint'
        $miBase = Test-TrustedManagedIdentityEndpoint -Value ([string]$env:MSI_ENDPOINT) -Label 'MSI_ENDPOINT' -Notes $chainNotes
        if ($miBase) {
            $miHeaders = @{ Metadata = 'true' }
            if (Test-Path env:MSI_SECRET) { $miHeaders['Secret'] = [string]$env:MSI_SECRET }
            $miUrl = "$miBase`?api-version=2017-09-01&resource=$([uri]::EscapeDataString($armResource))"
            $miProbe = Invoke-HttpProbe -Url $miUrl -Headers $miHeaders -TimeoutSec $TimeoutSeconds -NoProxy
        }
        else { $miEndpointRejected = $true }
    }
    else {
        $miKind = 'imds'
        # HARD 2s + -NoProxy: 169.254.169.254 is link-local; on a non-Azure host the
        # connect must fail fast, and a proxy must never swallow it into a long hang.
        $miProbe = Invoke-HttpProbe -Url $imdsUrl -Headers @{ Metadata = 'true' } -TimeoutSec $imdsTimeoutSec -NoProxy
    }
    if ($null -ne $miProbe -and $miProbe.Status -eq 200) {
        $miReply = Test-ParsedJson $miProbe.Body
        $miToken = [string](Get-OptionalProperty $miReply 'access_token' '')
        if ($miToken) {
            $tokenHeld = $true
            $arm = Invoke-ArmProbe -Token $miToken -Source "managed-identity ($miKind)" `
                -Identity 'managed identity (principal not re-queried here)' -ChainNotes $chainNotes
            if ($arm.Outcome -eq 'ready') { return $arm.Lane }
            if ($arm.Outcome -eq 'forbidden' -and $null -eq $armForbidden) { $armForbidden = $arm.Lane }
            if ($arm.Outcome -eq 'auth-rejected') { $sawAuthRejection = $true }
        }
        else {
            $chainNotes.Add("managed-identity ($miKind): endpoint 200 but no access_token field (raw body never echoed)")
        }
    }
    elseif ($null -eq $miProbe) {
        # A rejected declared endpoint: the validation note above is the evidence and
        # nothing was sent, so there is no status to classify.
    }
    else {
        $miStatus = if ($miProbe.Status -eq 0) { 'unreachable (expected off-Azure; failed fast)' } else { "HTTP $($miProbe.Status)" }
        if ($miKind -ne 'imds' -and $miProbe.Status -in 401, 403) {
            # Only a DECLARED endpoint (IDENTITY_ENDPOINT / MSI_ENDPOINT) can reject
            # the request for a configuration reason; raw IMDS non-200s stay what they
            # are (a non-Azure host or a metadata firewall — not a credential source).
            $miAuthRejected = $true
            $chainNotes.Add("managed-identity ($miKind): endpoint answered $miStatus — the identity header/secret (IDENTITY_HEADER / MSI_SECRET) or the endpoint wiring is rejected; this is configuration, not an outage")
        }
        else {
            $chainNotes.Add("managed-identity ($miKind): $miStatus")
        }
    }
    # A managed-identity SOURCE exists when an endpoint env var declares one (App
    # Service / Functions hosts) or IMDS actually answered a token request with 200.
    # Unreachable IMDS (status 0) is the normal off-Azure state, and a non-200 HTTP
    # answer at that address (e.g. a container fabric's metadata firewall returning
    # 403 — measured) is just as permanently unusable: neither is a credential
    # source, and "retry later" cannot fix either.
    # A declared endpoint that failed the local-host shape check is not a source either
    # (review finding): nothing was contacted, so it can neither succeed nor be retried.
    if (((-not $miEndpointRejected) -and ((Test-EnvValue 'IDENTITY_ENDPOINT') -or (Test-EnvValue 'MSI_ENDPOINT'))) -or
        ($null -ne $miProbe -and $miProbe.Status -eq 200)) {
        $credentialSourcePresent = $true
    }

    # 4. az cached login — last automatic rung. Nonzero exit = this chain entry fails;
    #    the AADSTS50078 MFA-expired state (the measured broken state in
    #    ENTERPRISE_AI_CONNECTIONS.md §0) lands exactly here.
    if ($azCmd) {
        $credentialSourcePresent = $true
        # 2>&1 with type-based split (review finding): stderr must be INSPECTED —
        # never echoed — to tell a definitive auth rejection (AADSTS code, "az
        # login" advice) from a transport/service failure that credential churn
        # cannot repair. Discarding it made every nonzero exit read as rejection.
        $azAll = @(& $azCmd.Source account get-access-token --resource-type arm --output json 2>&1)
        $azExit = $LASTEXITCODE
        $azOut = @($azAll | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" })
        $azErrText = (@($azAll | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" }) -join ' ')
        if ($azExit -eq 0) {
            $azReply = Test-ParsedJson (@($azOut) -join '')
            $azToken = [string](Get-OptionalProperty $azReply 'accessToken' '')
            if ($azToken) {
                $tokenHeld = $true
                $arm = Invoke-ArmProbe -Token $azToken -Source 'az-cli-cache' `
                    -Identity 'the cached az login (whoever scripts/bootstrap/connect-account.ps1 pins)' -ChainNotes $chainNotes
                if ($arm.Outcome -eq 'ready') { return $arm.Lane }
                if ($arm.Outcome -eq 'forbidden' -and $null -eq $armForbidden) { $armForbidden = $arm.Lane }
                if ($arm.Outcome -eq 'auth-rejected') { $sawAuthRejection = $true }
            }
            else {
                $chainNotes.Add('az-cli-cache: exit 0 but no accessToken field in the JSON (raw output never echoed)')
            }
        }
        else {
            # Definitive only on a recognizable auth error (review finding): DNS,
            # throttling, and service outages also make az exit nonzero, and MFA
            # advice cannot fix those. The stderr text is regex-scanned only —
            # never echoed.
            if ($azErrText -match 'AADSTS\d+' -or $azErrText -match "az login" -or $azErrText -match 'No subscription found') {
                $chainNotes.Add("az-cli-cache: az account get-access-token exited $azExit with a definitive auth error (AADSTS/no-login; raw output never echoed) — the AADSTS50078 MFA-expired state lands here")
                $sawAuthRejection = $true
            }
            else {
                $chainNotes.Add("az-cli-cache: az account get-access-token exited $azExit without a recognizable auth error (transport/throttling/service failure suspected; raw output never echoed) — treated as transient")
            }
        }
    }
    else {
        $chainNotes.Add('az-cli-cache: az is not on PATH (scripts/bootstrap/cloud-shell-setup.sh installs it)')
    }

    # Chain exhausted — classify honestly (review findings):
    $chainText = $chainNotes -join '; '
    # 1. A stashed 403 diagnosis wins: some rung authenticated but lacks RBAC — the
    #    role-assignment action is the accurate remediation, never MFA.
    #    …unless a certificate service principal is configured (review finding): the
    #    principal that got 403 (managed identity / az cache) and the certificate
    #    principal can differ, so the non-interactive certificate path is advertised
    #    first, with the 403 evidence attached, rather than discarded behind an RBAC
    #    grant for a principal the hub may never use.
    if ($null -ne $armForbidden -and -not $spCertReady) { return $armForbidden }
    # 2. A configured certificate is a usable NON-INTERACTIVE repair that this
    #    report-only script deliberately does not execute (its az login rewrites the
    #    shared profile). When the chain ends without a ready lane, that repair must
    #    be the terminal ownerAction (review finding): setup-everything.ps1 harvests
    #    only ownerAction/nextCommand, so leaving it inside a chain note buries the
    #    one path that needs no MFA — the lane would otherwise end as retry advice
    #    or the generic MFA action. It also OUTRANKS unexchanged CI OIDC (review
    #    finding): the certificate works right now with no workflow edit, so it
    #    must not be discarded in favor of "add azure/login" advice.
    if ($spCertReady) {
        # The repair runs through az (review finding): auth-doctor -Apply returns
        # immediately when az is missing, so on an az-less host the action must
        # name the install prerequisite or it sends the operator into a dead end.
        $certAction = if ($azCmd) {
            'pwsh scripts/bootstrap/auth-doctor.ps1 -Apply   # non-interactive certificate service-principal login; no MFA needed'
        }
        else {
            'install the Azure CLI first (scripts/bootstrap/cloud-shell-setup.sh, or https://aka.ms/azure-cli), then: pwsh scripts/bootstrap/auth-doctor.ps1 -Apply   # non-interactive certificate login; no MFA needed'
        }
        # Both actions preserved when OIDC is also available (review finding): the
        # certificate wins the ownerAction slot (it works right now with no
        # workflow edit), and the azure/login alternative rides in the detail.
        $certOidcNote = if ($ciOidcAvailable) { ' — alternative: this Actions job can also mint an OIDC token, so adding the azure/login step before this probe works too' } else { '' }
        # A stashed 403 rides along as evidence (review finding): if the certificate
        # principal turns out to be the SAME identity, the RBAC grant is the real repair.
        $certForbiddenNote = if ($null -ne $armForbidden) { " — note: another credential source ($($armForbidden.source)) already authenticated but ARM answered 403 for that principal; if the certificate service principal is the same identity, the RBAC grant (az role assignment create --assignee <principal> --role Reader --scope <scope>, owner-gated) is the repair instead" } else { '' }
        return New-LaneResult -Lane 'azure' -State 'needs-owner' -Source 'env-service-principal-cert' `
            -Detail ("the certificate service-principal flow is configured (AZURE_CLIENT_ID/AZURE_TENANT_ID/" +
                "AZURE_CLIENT_CERTIFICATE_PATH set) and is a non-interactive repair this report-only probe " +
                "deliberately does not execute: $chainText$certOidcNote$certForbiddenNote") `
            -OwnerAction $certAction
    }
    # 3. CI OIDC available and NO rung ever held a token (and no certificate to
    #    prefer): the exchange has not run in this job (yet) — the remediation is a
    #    workflow step (azure/login), never MFA advice or a retry (review finding:
    #    the request URL's presence is availability evidence, not a completed login).
    #    When a rung DID hold a token (review finding: azure/login already populated
    #    the az cache and ARM then timed out / 429 / 5xx / answered garbage), the
    #    exchange has run — that case stays transient or definitive below, with the
    #    OIDC availability noted rather than prescribed.
    if ($ciOidcAvailable -and -not $tokenHeld) {
        # The workflow edit IS the owner action (review finding): setup-everything.ps1
        # and JSON consumers consolidate ownerAction/nextCommand, so a repair that
        # lives only in the detail text vanishes from the advertised action list.
        return New-LaneResult -Lane 'azure' -State 'ci-delegated' -Source 'ci-oidc' `
            -Identity 'the workflow federated identity' `
            -Detail ("OIDC is AVAILABLE (ACTIONS_ID_TOKEN_REQUEST_URL present) but no chain entry held a usable ARM token: $chainText — " +
                'the azure/login step performs the OIDC exchange and must run before this probe; this probe never duplicates it') `
            -OwnerAction 'add an azure/login@v2 step (client-id / tenant-id / subscription-id of the federated credential from scripts/bootstrap/azure-oidc-setup.ps1) before this probe in the workflow job — the job already has id-token: write, so no secret is needed'
    }
    $oidcHeldNote = if ($ciOidcAvailable -and $tokenHeld) {
        ' — OIDC is also available to this job, but a credential source already yielded a token here (azure/login has evidently run), so adding another azure/login step is not the remedy'
    }
    else { '' }
    # 4. No credential source EXISTED at all (review finding): nothing was actually
    #    attempted, so neither "retry later" nor credential-rotation advice is
    #    honest — the host needs a first credential source, and that is the exact
    #    guidance returned.
    if (-not $credentialSourcePresent) {
        # The action must carry the prerequisite (review finding): this branch only
        # exists when az is absent (an installed az is itself a credential source), and
        # setup-everything.ps1 harvests ownerAction alone — an `az login` that cannot
        # run would be its whole advertised repair.
        return New-LaneResult -Lane 'azure' -State 'unavailable' -Source 'none' `
            -Detail ("no Azure credential source exists on this host — no CI OIDC, no service-principal env vars, no managed-identity endpoint yielded a token, and az is not on PATH: $chainText — " +
                'retrying cannot help; install the Azure CLI (scripts/bootstrap/cloud-shell-setup.sh) and log in once, or set AZURE_CLIENT_ID/AZURE_TENANT_ID plus a credential for a workload identity') `
            -OwnerAction ("bash scripts/bootstrap/cloud-shell-setup.sh && $azureOwnerAction   # step 1 installs the Azure CLI (or https://aka.ms/azure-cli)")
    }
    # 4b. A declared managed-identity endpoint REJECTED the request (401/403): the
    #     host's identity wiring is wrong, and no retry or MFA login repairs that —
    #     the exact wiring check is the owner step (review finding).
    if ($miAuthRejected -and -not $sawAuthRejection) {
        return New-LaneResult -Lane 'azure' -State 'needs-owner' -Source 'managed-identity' `
            -Detail ("the declared managed-identity endpoint rejected the token request ($chainText) — retrying cannot help; the endpoint/header pair the host injects is stale or does not belong to an identity with access$oidcHeldNote") `
            -OwnerAction 'verify the managed-identity wiring the host injects — IDENTITY_ENDPOINT + IDENTITY_HEADER (App Service / Functions / Container Apps) or MSI_ENDPOINT + MSI_SECRET — by redeploying with a system- or user-assigned identity that has access, or unset the stale endpoint variables so the chain can use another credential source'
    }
    # 5. No definitive rejection anywhere = transient-only evidence (transport, 429,
    #    5xx, garbage bodies): MFA/workload-identity advice cannot fix an outage and
    #    would prompt needless credential churn.
    if (-not $sawAuthRejection) {
        return New-LaneResult -Lane 'azure' -State 'unavailable' -Source 'none' `
            -Detail ("no chain entry got a definitive answer — every attempt failed transiently: $chainText — " +
                "retry later; do NOT change credentials on this evidence$oidcHeldNote")
    }
    # 6. Definitive rejection(s): the one owner step, reported — never run.
    return New-LaneResult -Lane 'azure' -State 'needs-owner' -Source 'none' `
        -Detail ("automatic chain exhausted (ci-oidc -> env service principal -> managed identity -> az cache): $chainText. " +
            "The zero-human-input paths that exist today are Azure Cloud Shell's implicit login and CI OIDC; everywhere " +
            "else the first token costs one MFA login, after which the ops workload identity removes the human forever$oidcHeldNote") `
        -OwnerAction $azureOwnerAction
}

# --- Dry run: plan printer only — no token read, no network call ------------------------
if ($DryRun) {
    Write-Host ''
    Write-Host "REST connectivity probe plan (HTTP probes bounded at ${TimeoutSeconds}s; IMDS hard ${imdsTimeoutSec}s):"
    $configuredModelsEnvs = @(Get-ConfiguredGitHubModelsEnvs)
    $configuredModelsText = if ($configuredModelsEnvs.Count -gt 0) { "env $($configuredModelsEnvs -join ' -> env ') (each enabled github-models-type provider's apiKeyEnv; public endpoint only, and never a variable a custom-endpoint provider also reads)" }
    elseif ($script:configuredModelsNote) { $script:configuredModelsNote }
    else { '(no enabled github-models-type provider on the public endpoint — no config candidate)' }
    $screenedFixed = @(@('GH_TOKEN', 'GITHUB_TOKEN') | Where-Object { $script:nonGitHubReaderEnvs.Contains($_) })
    $screenedFixedText = if ($screenedFixed.Count -gt 0) { " (screened out here: env $($screenedFixed -join ' / env ') — read by an enabled non-GitHub provider or CLI agent in the active config, so never offered to api.github.com)" } else { '' }
    Write-Host "  github   candidates in order: env GH_TOKEN -> env GITHUB_TOKEN -> $configuredModelsText -> gh auth token (only if gh is on PATH)$screenedFixedText"
    Write-Host "           each: GET $gitHubApi/rate_limit (Bearer, X-GitHub-Api-Version: 2022-11-28, User-Agent $userAgent)"
    Write-Host "           200 above the anonymous 60/hr cap => ready (stop; GET $gitHubApi/user for identity; 401/403 there still ready)"
    Write-Host '           200 at/below the cap => Authorization likely stripped in transit; not attributed, next candidate'
    Write-Host '           401 => next candidate; all 401 => needs-owner (gh auth login --web); transient-only => unavailable (retry, never rotate)'
    Write-Host '           no candidate at all => unavailable (Invoke-WebRequest is built in — only the token can be missing)'
    Write-Host '           note: the REST probe is the ground truth — gh auth status can exit 1 for a fully REST-valid token'
    Write-Host '  azure    1. ACTIONS_ID_TOKEN_REQUEST_URL present => OIDC available (evidence, not a completed login) — chain continues; nothing usable => ci-delegated (azure/login must run first)'
    Write-Host '           2. AZURE_CLIENT_ID+AZURE_TENANT_ID+AZURE_CLIENT_SECRET => client_credentials POST to'
    if ($azureCloud.Unresolved) {
        Write-Host '              <no authority: the cloud is UNRESOLVED, so the live run makes no Azure request at all and reports needs-owner>'
        Write-Host "           cloud: UNRESOLVED (from $($azureCloud.Source)) — see the cloud warning below; fix the endpoint pair before any rung can run"
    }
    else {
        Write-Host "              $($azureCloud.Authority)/<tenant>/oauth2/v2.0/token (scope $armScope)"
        Write-Host "           cloud: $($azureCloud.Name) — authority $($azureCloud.Authority), ARM $($azureCloud.ArmResource) (resolved from $($azureCloud.Source))"
    }
    foreach ($cloudWarning in @($azureCloud.Warnings)) { Write-Host "           cloud warning: $cloudWarning" }
    Write-Host '           a lone AZURE_AUTHORITY_HOST / ARM override is completed from the known-cloud table; a pair naming two clouds (or half an az-registered cloud) => needs-owner before any rung, nothing sent'
    Write-Host '              (with AZURE_CLIENT_CERTIFICATE_PATH instead: delegated to az login --service-principal --certificate)'
    Write-Host '           3. IDENTITY_ENDPOINT/MSI_ENDPOINT if set — honored only as an absolute http(s) URL on a loopback host or 169.254.169.254 (the App Service / Container Apps / Arc / Cloud Shell shapes); any other host is ignored and no identity header or secret is sent — else IMDS 169.254.169.254 (Metadata:true, hard 2s, no proxy)'
    Write-Host '           4. az account get-access-token --resource-type arm (exit code gates; AADSTS50078 lands here)'
    Write-Host "           first token => GET $(if ($azureCloud.Unresolved) { '<unresolved cloud — no ARM endpoint>' } else { $armSubscriptionsUrl })"
    Write-Host '           200+parsed payload => ready (subscription count + first name/id); 401 => continue; 403 => RBAC diagnosis kept, chain continues'
    Write-Host '           exhausted: stashed 403 => needs-owner (RBAC grant); OIDC available and no rung ever held a token => ci-delegated (azure/login must run first; a held token that then failed transiently stays transient); certificate configured => needs-owner (auth-doctor -Apply, non-interactive, no MFA); no credential source at all => unavailable (setup guidance, retry cannot help); declared managed-identity endpoint answering 401/403 => needs-owner (identity wiring, never a retry); definitive rejection => needs-owner (MFA once + setup-tenant -OpsIdentity, reported never run); transient-only => unavailable (retry)'
    Write-Host '  exit     always 0 (report-first; needs-owner never gates); internal failure only => 1'
    Write-Host ''
    Write-Host 'Dry run - no token read, no network call made, nothing written.'
    exit 0
}

# --- Live run ---------------------------------------------------------------------------
try {
    Write-Report '== HELIOS REST connectivity (control-plane probes, report-only) =='
    Write-Report ''

    $laneResults = @(
        Test-GitHubLane
        Test-AzureLane
    )

    $summary = [ordered]@{
        ready       = @($laneResults | Where-Object { $_.state -eq 'ready' }).Count
        needsOwner  = @($laneResults | Where-Object { $_.state -eq 'needs-owner' }).Count
        unavailable = @($laneResults | Where-Object { $_.state -eq 'unavailable' }).Count
        ciDelegated = @($laneResults | Where-Object { $_.state -eq 'ci-delegated' }).Count
    }
    # Exit contract: report-first — ALWAYS 0 here. needs-owner never gates; only the
    # outer catch (an internal script failure) exits nonzero.
    $exitCode = 0

    if ($Json) {
        [ordered]@{
            script       = 'scripts/verify/rest-connect.ps1'
            generatedUtc = (Get-Date).ToUniversalTime().ToString('o')
            lanes        = @($laneResults)
            summary      = $summary
            exitCode     = $exitCode
        } | ConvertTo-Json -Depth 6
    }
    else {
        $table = $laneResults |
            Format-Table -AutoSize -Property @(
                @{ n = 'Lane'; e = { $_.lane } }
                @{ n = 'State'; e = { $_.state } }
                @{ n = 'Source'; e = { $_.source } }
                @{ n = 'Identity'; e = { $_.identity } }
                @{ n = 'Owner action (exact command)'; e = { $_.ownerAction } }
                @{ n = 'Detail'; e = { $_.detail } }
            ) |
            Out-String -Width 4096
        Write-Report $table.TrimEnd()
        Write-Report ''
        $readyCount = [int]$summary['ready']
        $needsOwnerCount = [int]$summary['needsOwner']
        Write-Report ("REST connectivity: {0} ready, {1} needs-owner — report-only, exit 0 (needs-owner never gates)" -f
            $readyCount, $needsOwnerCount)
    }

    exit $exitCode
}
catch {
    [Console]::Error.WriteLine("rest-connect: internal failure — $($_.Exception.Message)")
    exit 1
}
