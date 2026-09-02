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

  github  Candidate tokens tried IN ORDER: env GH_TOKEN, env GITHUB_TOKEN, then — only
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
                              => state ci-delegated: azure/login owns the OIDC exchange
                              in CI and this probe does not duplicate it. No token is
                              attempted.
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

Secrets policy (CLAUDE.md rule): env vars are gated by NAME (Test-Path env:). Where a
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

# --- github lane ------------------------------------------------------------------------
function Get-GitHubTokenCandidates {
    # Candidate ORDER is the contract: explicit env wins over the CLI keyring, and
    # GH_TOKEN (gh's own precedence rule) wins over GITHUB_TOKEN. Token values are read
    # into the candidate objects here and die when the github lane function returns —
    # they are never interpolated into any reported string.
    $candidates = [System.Collections.Generic.List[object]]::new()
    foreach ($envName in @('GH_TOKEN', 'GITHUB_TOKEN')) {
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
        $tokenLines = @(& $ghCmd.Source auth token 2>$null)
        $ghExit = $LASTEXITCODE
        $ghToken = (@($tokenLines) -join '').Trim()
        if ($ghExit -eq 0 -and -not [string]::IsNullOrWhiteSpace($ghToken)) {
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
        if ($anonLimitIsNumeric -and $anonLimitValue -ne 60) {
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
# Probes ARM with an acquired token. Returns the ready lane result on 200; $null on
# 401/403 or any other failure (the caller notes it and continues the chain). The token
# parameter exists only for the Authorization header — never logged or stored.
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
        $subs = @(Get-OptionalProperty $parsed 'value' @())
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
        return New-LaneResult -Lane 'azure' -State 'ready' -Source $Source -Identity $Identity `
            -Detail ("ARM /subscriptions 200 — $subCount subscription(s); $firstText (token value never printed)")
    }
    if ($probe.Status -eq 403) {
        # AUTHORIZATION, not authentication (review finding): the token is real and
        # ARM recognized the principal — it just lacks an RBAC role. Re-login can
        # never fix that, so this is a terminal needs-owner with a role-assignment
        # action, never a fall-through to MFA advice.
        return New-LaneResult -Lane 'azure' -State 'needs-owner' -Source $Source -Identity $Identity `
            -Detail ('a valid token was acquired but ARM answered 403 — the principal lacks an RBAC role ' +
                'on the subscription; re-authentication cannot grant permissions') `
            -OwnerAction ("grant the principal an RBAC role (e.g. Reader) on the target subscription/resource " +
                "group — az role assignment create --assignee <principal> --role Reader --scope <scope> " +
                '(role assignment is deliberately owner-gated in this repo)')
    }
    if ($probe.Status -eq 401) {
        $ChainNotes.Add("$Source acquired a token but ARM answered HTTP 401 — the token itself was rejected")
    }
    elseif ($probe.Status -eq 0) {
        $ChainNotes.Add("$Source acquired a token but the ARM probe hit a transport failure ($($probe.Transport))")
    }
    else {
        $ChainNotes.Add("$Source acquired a token but ARM answered HTTP $($probe.Status)")
    }
    return $null
}

function Test-AzureLane {
    # 1. CI OIDC — name check only; azure/login owns the exchange and this probe never
    #    duplicates (or races) it.
    if (Test-Path env:ACTIONS_ID_TOKEN_REQUEST_URL) {
        return New-LaneResult -Lane 'azure' -State 'ci-delegated' -Source 'ci-oidc' `
            -Identity 'the workflow federated identity' `
            -Detail 'azure/login performs the OIDC exchange in CI — this probe does not duplicate it'
    }

    $chainNotes = [System.Collections.Generic.List[string]]::new()
    $azCmd = Get-CliCommand -Name 'az'

    # 2. Env service principal — fully non-interactive. Secret variant: the credential
    #    values are read into locals, flow into an in-memory POST body, and die with
    #    this scope; the response token lives in a local and only ever becomes an
    #    Authorization header. Nothing from this exchange is echoed.
    # Preference note (deliberate divergence, documented): auth-doctor -Apply prefers
    # the CERTIFICATE when both credentials are present; this report-only script
    # prefers the SECRET, because the secret flow is pure in-memory REST while the
    # certificate flow requires an az login that mutates the shared profile — which a
    # diagnostic run must never do (see the cert rung below).
    $spSecretReady = (Test-Path env:AZURE_CLIENT_ID) -and (Test-Path env:AZURE_TENANT_ID) -and
        (Test-Path env:AZURE_CLIENT_SECRET)
    # Cert availability is INDEPENDENT of the secret (review finding): during
    # credential rotation a stale secret with a valid certificate is a normal state,
    # and the cert path must still be reported after the secret exchange fails.
    $spCertReady = (Test-Path env:AZURE_CLIENT_ID) -and
        (Test-Path env:AZURE_TENANT_ID) -and (Test-Path env:AZURE_CLIENT_CERTIFICATE_PATH)
    if ($spSecretReady) {
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
                $armResult = Invoke-ArmProbe -Token $spToken -Source 'env-service-principal' `
                    -Identity "service principal $clientId" -ChainNotes $chainNotes
                if ($null -ne $armResult) { return $armResult }
            }
            else {
                $chainNotes.Add('env-service-principal: token endpoint 200 but no access_token field (raw body never echoed)')
            }
        }
        else {
            $spStatus = if ($tokenProbe.Status -eq 0) { "transport failure ($($tokenProbe.Transport))" } else { "HTTP $($tokenProbe.Status)" }
            $chainNotes.Add("env-service-principal: token endpoint $spStatus (raw error body never echoed)")
        }
    }
    elseif ($spCertReady) {
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
    else {
        $chainNotes.Add('env-service-principal: AZURE_CLIENT_ID/AZURE_TENANT_ID + credential not all set (names checked only)')
    }

    # 3. Managed identity — endpoint env vars first (App Service / Functions / Container
    #    Apps and the legacy MSI shape), else raw IMDS with the hard 2s no-proxy timeout.
    $miProbe = $null
    $miKind = ''
    if (Test-Path env:IDENTITY_ENDPOINT) {
        $miKind = 'identity-endpoint'
        $miHeaders = @{}
        if (Test-Path env:IDENTITY_HEADER) { $miHeaders['X-IDENTITY-HEADER'] = [string]$env:IDENTITY_HEADER }
        $miBase = ([string]$env:IDENTITY_ENDPOINT).TrimEnd('/')
        $miUrl = "$miBase`?api-version=2019-08-01&resource=$([uri]::EscapeDataString('https://management.azure.com/'))"
        $miProbe = Invoke-HttpProbe -Url $miUrl -Headers $miHeaders -TimeoutSec $TimeoutSeconds -NoProxy
    }
    elseif (Test-Path env:MSI_ENDPOINT) {
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
            $armResult = Invoke-ArmProbe -Token $miToken -Source "managed-identity ($miKind)" `
                -Identity 'managed identity (principal not re-queried here)' -ChainNotes $chainNotes
            if ($null -ne $armResult) { return $armResult }
        }
        else {
            $chainNotes.Add("managed-identity ($miKind): endpoint 200 but no access_token field (raw body never echoed)")
        }
    }
    else {
        $miStatus = if ($miProbe.Status -eq 0) { 'unreachable (expected off-Azure; failed fast)' } else { "HTTP $($miProbe.Status)" }
        $chainNotes.Add("managed-identity ($miKind): $miStatus")
    }

    # 4. az cached login — last automatic rung. Nonzero exit = this chain entry fails;
    #    the AADSTS50078 MFA-expired state (the measured broken state in
    #    ENTERPRISE_AI_CONNECTIONS.md §0) lands exactly here.
    if ($azCmd) {
        $azOut = @(& $azCmd.Source account get-access-token --resource-type arm --output json 2>$null)
        $azExit = $LASTEXITCODE
        if ($azExit -eq 0) {
            $azReply = Test-ParsedJson (@($azOut) -join '')
            $azToken = [string](Get-OptionalProperty $azReply 'accessToken' '')
            if ($azToken) {
                $armResult = Invoke-ArmProbe -Token $azToken -Source 'az-cli-cache' `
                    -Identity 'the cached az login (whoever scripts/bootstrap/connect-account.ps1 pins)' -ChainNotes $chainNotes
                if ($null -ne $armResult) { return $armResult }
            }
            else {
                $chainNotes.Add('az-cli-cache: exit 0 but no accessToken field in the JSON (raw output never echoed)')
            }
        }
        else {
            $chainNotes.Add("az-cli-cache: az account get-access-token exited $azExit — no usable cached login (the AADSTS50078 MFA-expired state lands here; stderr suppressed, never echoed)")
        }
    }
    else {
        $chainNotes.Add('az-cli-cache: az is not on PATH (scripts/bootstrap/cloud-shell-setup.sh installs it)')
    }

    # Chain exhausted: the one owner step, reported — never run.
    $chainText = $chainNotes -join '; '
    return New-LaneResult -Lane 'azure' -State 'needs-owner' -Source 'none' `
        -Detail ("automatic chain exhausted (ci-oidc -> env service principal -> managed identity -> az cache): $chainText. " +
            "The zero-human-input paths that exist today are Azure Cloud Shell's implicit login and CI OIDC; everywhere " +
            'else the first token costs one MFA login, after which the ops workload identity removes the human forever') `
        -OwnerAction $azureOwnerAction
}

# --- Dry run: plan printer only — no token read, no network call ------------------------
if ($DryRun) {
    Write-Host ''
    Write-Host "REST connectivity probe plan (HTTP probes bounded at ${TimeoutSeconds}s; IMDS hard ${imdsTimeoutSec}s):"
    Write-Host '  github   candidates in order: env GH_TOKEN -> env GITHUB_TOKEN -> gh auth token (only if gh is on PATH)'
    Write-Host "           each: GET $gitHubApi/rate_limit (Bearer, X-GitHub-Api-Version: 2022-11-28, User-Agent $userAgent)"
    Write-Host "           200 => ready (stop; GET $gitHubApi/user for identity; 401/403 there still ready)"
    Write-Host '           401 => next candidate; all fail => needs-owner: gh auth login --web (device code)'
    Write-Host '           no candidate at all => unavailable (Invoke-WebRequest is built in — only the token can be missing)'
    Write-Host '           note: the REST probe is the ground truth — gh auth status can exit 1 for a fully REST-valid token'
    Write-Host '  azure    1. ACTIONS_ID_TOKEN_REQUEST_URL present => ci-delegated (azure/login owns the exchange; no token attempted)'
    Write-Host '           2. AZURE_CLIENT_ID+AZURE_TENANT_ID+AZURE_CLIENT_SECRET => client_credentials POST to'
    Write-Host "              https://login.microsoftonline.com/<tenant>/oauth2/v2.0/token (scope $armScope)"
    Write-Host '              (with AZURE_CLIENT_CERTIFICATE_PATH instead: delegated to az login --service-principal --certificate)'
    Write-Host '           3. IDENTITY_ENDPOINT/MSI_ENDPOINT if set, else IMDS 169.254.169.254 (Metadata:true, hard 2s, no proxy)'
    Write-Host '           4. az account get-access-token --resource-type arm (exit code gates; AADSTS50078 lands here)'
    Write-Host "           first token => GET $armSubscriptionsUrl"
    Write-Host '           200 => ready (subscription count + first name/id); 401/403 => continue the chain'
    Write-Host '           chain exhausted => needs-owner (tenant-scoped MFA login + setup-tenant.ps1 -OpsIdentity, reported never run)'
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
