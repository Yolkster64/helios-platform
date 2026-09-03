<#
.SYNOPSIS
REST-level connectivity verifier and NON-INTERACTIVE token acquirer for the two control
planes: GitHub REST (api.github.com) and Azure ARM (management.azure.com). Report-first:
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
                              => client_credentials POST to login.microsoftonline.com
                              (scope https://management.azure.com/.default; body built
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
          https://management.azure.com/subscriptions?api-version=2022-12-01: 200 =>
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
$armSubscriptionsUrl = 'https://management.azure.com/subscriptions?api-version=2022-12-01'
$armScope = 'https://management.azure.com/.default'
$imdsUrl = 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/'
$imdsTimeoutSec = 2   # HARD by design: a non-Azure host must fail fast, not hang.
$userAgent = 'helios-rest-connect'
# Exact owner runbook (ENTERPRISE_AI_CONNECTIONS.md §1 + setup-tenant.ps1 -OpsIdentity):
# one MFA login now, then the workload identity makes every future session automatic.
$azureOwnerAction = 'az login --tenant "349e1399-dccf-45b1-af7e-05d7b0676abf" (MFA once), then pwsh scripts/bootstrap/setup-tenant.ps1 -OpsIdentity to mint the service principal that makes every future session non-interactive'

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
    if (-not (Test-Path "env:$Name")) { return $false }
    return -not [string]::IsNullOrWhiteSpace([string](Get-Item "env:$Name").Value)
}

# --- github lane ------------------------------------------------------------------------
# The github-models provider's CONFIGURED token variable (review finding): auto-login
# exports under whatever apiKeyEnv the active hub config declares (AIHUB_CONFIG beats
# the repo default, as AIHubService.ResolveConfigPath does) and ProviderFactory reads
# that same name — so the candidate walk must probe it too, not only fixed names.
# Any read problem falls back to the default name; nothing here is fatal.
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
        $providers = Get-OptionalProperty $parsed 'providers'
        if ($null -eq $providers) { return @() }
        # Pass 1 — every enabled github-models entry that reads a variable, with its
        # endpoint ownership. apiKeyEnv follows ProviderFactory exactly (review
        # finding): the default applies only when the property is absent/null; a
        # declared-blank name means the hub reads NO variable (SecretResolver skips a
        # blank name), so there is nothing to probe for that entry.
        $entries = [System.Collections.Generic.List[object]]::new()
        foreach ($prop in $providers.PSObject.Properties) {
            $prov = $prop.Value
            if ($null -eq $prov) { continue }
            $provType = ([string](Get-OptionalProperty $prov 'type' '')).Trim()
            if (-not $provType.Equals('github-models', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            if ((Get-OptionalProperty $prov 'enabled' $true) -eq $false) { continue }
            $envProp = $prov.PSObject.Properties['apiKeyEnv']
            $envName = if ($null -eq $envProp -or $null -eq $envProp.Value) { $default } else { ([string]$envProp.Value).Trim() }
            if (-not $envName) { continue }
            $baseUrl = ([string](Get-OptionalProperty $prov 'baseUrl' '')).Trim()
            $isPublic = $true
            if ($baseUrl) {
                $baseHost = ''
                try { $baseHost = ([uri]$baseUrl).Host } catch { }
                $isPublic = $baseHost.Equals('models.github.ai', [System.StringComparison]::OrdinalIgnoreCase)
            }
            $entries.Add([pscustomobject]@{ Env = $envName; Public = $isPublic })
        }
        # Pass 2 — a variable is a candidate only when EVERY entry reading it is
        # public (review finding, mixed ownership): one shared by a public and a
        # custom-baseUrl provider may hold the custom endpoint's credential, which
        # must never reach api.github.com — the same rule as the custom-only case.
        $names = [System.Collections.Generic.List[string]]::new()
        foreach ($envName in @($entries | ForEach-Object { $_.Env } | Select-Object -Unique)) {
            if (@($entries | Where-Object { $_.Env -eq $envName -and -not $_.Public }).Count) { continue }
            $names.Add($envName)
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
    # Third slot is the CONFIGURED models env (GITHUB_MODELS_TOKEN by default) —
    # review finding: a renamed apiKeyEnv must still be probed.
    foreach ($envName in @(@('GH_TOKEN', 'GITHUB_TOKEN') + @(Get-ConfiguredGitHubModelsEnvs) | Select-Object -Unique)) {
        if (Test-Path "env:$envName") {
            $value = [string](Get-Item "env:$envName").Value
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $candidates.Add([pscustomobject]@{ Source = "env:$envName"; Token = $value.Trim() })
            }
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
    $sawDefinitiveRejection = $false
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
    return New-LaneResult -Lane 'github' -State 'needs-owner' -Source 'none' `
        -Detail ("every candidate token failed the direct REST probe: $chainText — a fresh device-code " +
            'login (or a rotated token in GH_TOKEN) is an owner step') `
        -OwnerAction 'gh auth login --web (device code)'
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
        $tokenUrl = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
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
    if (Test-EnvValue 'IDENTITY_ENDPOINT') {
        $miKind = 'identity-endpoint'
        $miHeaders = @{}
        if (Test-Path env:IDENTITY_HEADER) { $miHeaders['X-IDENTITY-HEADER'] = [string]$env:IDENTITY_HEADER }
        $miBase = ([string]$env:IDENTITY_ENDPOINT).TrimEnd('/')
        $miUrl = "$miBase`?api-version=2019-08-01&resource=$([uri]::EscapeDataString('https://management.azure.com/'))"
        $miProbe = Invoke-HttpProbe -Url $miUrl -Headers $miHeaders -TimeoutSec $TimeoutSeconds -NoProxy
    }
    elseif (Test-EnvValue 'MSI_ENDPOINT') {
        $miKind = 'msi-endpoint'
        $miHeaders = @{ Metadata = 'true' }
        if (Test-Path env:MSI_SECRET) { $miHeaders['Secret'] = [string]$env:MSI_SECRET }
        $miBase = ([string]$env:MSI_ENDPOINT).TrimEnd('/')
        $miUrl = "$miBase`?api-version=2017-09-01&resource=$([uri]::EscapeDataString('https://management.azure.com/'))"
        $miProbe = Invoke-HttpProbe -Url $miUrl -Headers $miHeaders -TimeoutSec $TimeoutSeconds -NoProxy
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
    if ((Test-EnvValue 'IDENTITY_ENDPOINT') -or (Test-EnvValue 'MSI_ENDPOINT') -or
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
    if ($null -ne $armForbidden) { return $armForbidden }
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
        return New-LaneResult -Lane 'azure' -State 'needs-owner' -Source 'env-service-principal-cert' `
            -Detail ("the certificate service-principal flow is configured (AZURE_CLIENT_ID/AZURE_TENANT_ID/" +
                "AZURE_CLIENT_CERTIFICATE_PATH set) and is a non-interactive repair this report-only probe " +
                "deliberately does not execute: $chainText$certOidcNote") `
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
            -OwnerAction ("install the Azure CLI first (bash scripts/bootstrap/cloud-shell-setup.sh, or https://aka.ms/azure-cli), then: $azureOwnerAction")
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
    Write-Host "  github   candidates in order: env GH_TOKEN -> env GITHUB_TOKEN -> $configuredModelsText -> gh auth token (only if gh is on PATH)"
    Write-Host "           each: GET $gitHubApi/rate_limit (Bearer, X-GitHub-Api-Version: 2022-11-28, User-Agent $userAgent)"
    Write-Host "           200 above the anonymous 60/hr cap => ready (stop; GET $gitHubApi/user for identity; 401/403 there still ready)"
    Write-Host '           200 at/below the cap => Authorization likely stripped in transit; not attributed, next candidate'
    Write-Host '           401 => next candidate; all 401 => needs-owner (gh auth login --web); transient-only => unavailable (retry, never rotate)'
    Write-Host '           no candidate at all => unavailable (Invoke-WebRequest is built in — only the token can be missing)'
    Write-Host '           note: the REST probe is the ground truth — gh auth status can exit 1 for a fully REST-valid token'
    Write-Host '  azure    1. ACTIONS_ID_TOKEN_REQUEST_URL present => OIDC available (evidence, not a completed login) — chain continues; nothing usable => ci-delegated (azure/login must run first)'
    Write-Host '           2. AZURE_CLIENT_ID+AZURE_TENANT_ID+AZURE_CLIENT_SECRET => client_credentials POST to'
    Write-Host "              https://login.microsoftonline.com/<tenant>/oauth2/v2.0/token (scope $armScope)"
    Write-Host '              (with AZURE_CLIENT_CERTIFICATE_PATH instead: delegated to az login --service-principal --certificate)'
    Write-Host '           3. IDENTITY_ENDPOINT/MSI_ENDPOINT if set, else IMDS 169.254.169.254 (Metadata:true, hard 2s, no proxy)'
    Write-Host '           4. az account get-access-token --resource-type arm (exit code gates; AADSTS50078 lands here)'
    Write-Host "           first token => GET $armSubscriptionsUrl"
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
