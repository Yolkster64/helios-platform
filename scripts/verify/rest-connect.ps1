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
            1. CI OIDC        GITHUB_ACTIONS=true + non-blank ACTIONS_ID_TOKEN_REQUEST_URL
                              + non-blank ACTIONS_ID_TOKEN_REQUEST_TOKEN (names only)
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
                              never logged). If this selected credential cannot obtain
                              a token, stop as DefaultAzureCredential does: rejections
                              need repair; transient failures remain retryable without
                              masking the failure with a later credential source.
                              With AZURE_CLIENT_CERTIFICATE_PATH instead
                              of a secret, the JWT client assertion is never hand-rolled
                              here — the flow is delegated to `az login
                              --service-principal --certificate` + `az account
                              get-access-token` when az is on PATH, and reported as
                              available-but-needs-az otherwise.
            2b. workload id   AZURE_CLIENT_ID + AZURE_TENANT_ID + AZURE_FEDERATED_TOKEN_FILE
                              => the file's assertion posted once as a jwt-bearer
                              client_assertion to the same token endpoint (read into
                              memory, never echoed) — WorkloadIdentityCredential's rung,
                              with the same continuation policy as the secret: a
                              rejection needs repair, a transient failure stays
                              retryable, and neither is masked by a later source.
            3. managed id     IDENTITY_ENDPOINT (+IDENTITY_HEADER; the Azure Arc shape on
                              40342 instead uses its own two-step handshake — Metadata
                              request, then the WWW-Authenticate realm's local .key file
                              as Basic authorization), else MSI_ENDPOINT
                              (+MSI_SECRET) — each honored only on a documented local
                              token-endpoint shape (host, scheme, port AND path; the
                              user-assigned identity is selected with AZURE_CLIENT_ID
                              where the shape supports it), and an IDENTITY_ENDPOINT that is
                              rejected or yields no token falls through to MSI_ENDPOINT;
                              else the IMDS endpoint (169.254.169.254,
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
$script:paddedEnvSources = [System.Collections.Generic.List[string]]::new()   # env candidates refused for surrounding whitespace (review finding)
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
    # Canonical ORIGIN only (review finding): a known host on another port
    # (https://login.microsoftonline.com:444), or with userinfo, a path, query or
    # fragment, is a different origin from the one that was approved — the
    # client-secret exchange and the bearer probes go only to the bare https origin.
    if (-not $parsedEndpoint.IsDefaultPort -or $parsedEndpoint.UserInfo -or $parsedEndpoint.Query -or $parsedEndpoint.Fragment -or $parsedEndpoint.AbsolutePath -notin '', '/') {
        $Warnings.Add("ignored $Label — not a canonical https origin (default port, no userinfo, path, query or fragment; value never echoed); no credential is sent to it")
        return ''
    }
    return $parsedEndpoint.GetLeftPart([System.UriPartial]::Authority)
}
# Managed-identity endpoints have a DOCUMENTED shape (review findings): App Service /
# Functions / Container Apps / Azure ML inject http://127.0.0.1:41xxx/msi/token or
# http://localhost:42356/msi/token (the port is chosen per instance, the path is not),
# Azure Arc http://127.0.0.1:40342/metadata/identity/oauth2/token, Cloud Shell
# http://localhost:50342/oauth2/token, and IMDS is exactly
# http://169.254.169.254/metadata/identity/oauth2/token. Anything else in
# IDENTITY_ENDPOINT / MSI_ENDPOINT — mistyped, stale, or planted, including a loopback
# listener on another path such as http://localhost:8080/capture — would receive
# IDENTITY_HEADER / MSI_SECRET, so a value is contacted only when scheme, host AND
# token path match one of those shapes (no userinfo, query or fragment); a rejected
# value is reported as chain evidence and never counts as a credential source.
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
    $endpointAddress = $null
    $isLoopback = ($endpointHost -eq 'localhost') -or
        ([System.Net.IPAddress]::TryParse($endpointHost, [ref]$endpointAddress) -and
            [System.Net.IPAddress]::IsLoopback($endpointAddress))
    $isImds = ($endpointHost -eq '169.254.169.254')
    if (-not $isLoopback -and -not $isImds) {
        $Notes.Add("managed-identity: ignored $Label — host '$endpointHost' is not a platform-local endpoint (loopback or 169.254.169.254); no identity header or secret was sent to it")
        return ''
    }
    # The token PATH is the shape (review finding): a loopback host alone admits any
    # local listener, so only the documented endpoint paths are accepted, bare.
    $tokenPath = $parsed.AbsolutePath.TrimEnd('/')
    $knownTokenPaths = @('/msi/token', '/metadata/identity/oauth2/token', '/oauth2/token')
    $pathKnown = [bool]@($knownTokenPaths | Where-Object { $tokenPath.Equals($_, [System.StringComparison]::OrdinalIgnoreCase) }).Count
    if (-not $pathKnown -or $parsed.UserInfo -or $parsed.Query -or $parsed.Fragment) {
        $Notes.Add("managed-identity: ignored $Label — local host but not a documented token endpoint (expected path /msi/token, /metadata/identity/oauth2/token or /oauth2/token with no userinfo, query or fragment; value never echoed); no identity header or secret was sent to it")
        return ''
    }
    if ($isImds -and ($parsed.Scheme -ne 'http' -or -not $parsed.IsDefaultPort -or -not $tokenPath.Equals('/metadata/identity/oauth2/token', [System.StringComparison]::OrdinalIgnoreCase))) {
        $Notes.Add("managed-identity: ignored $Label — 169.254.169.254 is only ever http://169.254.169.254/metadata/identity/oauth2/token (value never echoed); no identity header or secret was sent to it")
        return ''
    }
    # Loopback shapes are bound to their documented scheme AND port per path (review
    # finding): on the path alone a planted http://localhost:8080/msi/token would pass
    # and receive IDENTITY_HEADER. App Service / Functions inject 127.0.0.1:41xxx,
    # Container Apps localhost:42356 and Azure ML localhost:46808 for /msi/token; Arc
    # is 127.0.0.1:40342 for /metadata/identity/oauth2/token; Cloud Shell is
    # localhost:50342 for /oauth2/token — all plain http. (Linux App Service publishes
    # a link-local 169.254.129.x:8081 endpoint, not a loopback host: reported as
    # ignored today — a documented limitation, not a planted value.)
    if ($isLoopback) {
        $endpointPort = [int]$parsed.Port
        $portKnown = switch ($tokenPath.ToLowerInvariant()) {
            '/msi/token' { (($endpointPort -ge 41000) -and ($endpointPort -le 41999)) -or ($endpointPort -in 42356, 46808) }
            '/metadata/identity/oauth2/token' { $endpointPort -eq 40342 }
            '/oauth2/token' { $endpointPort -eq 50342 }
            default { $false }
        }
        if ($parsed.Scheme -ne 'http' -or -not $portKnown) {
            $Notes.Add("managed-identity: ignored $Label — loopback endpoint on an undocumented scheme or port for its path (documented shapes: http://127.0.0.1:41xxx/msi/token, http://localhost:42356/msi/token, http://localhost:46808/msi/token, http://127.0.0.1:40342/metadata/identity/oauth2/token, http://localhost:50342/oauth2/token; value never echoed); no identity header or secret was sent to it")
            return ''
        }
    }
    return $parsed.GetLeftPart([System.UriPartial]::Path).TrimEnd('/')
}
function Get-TrustedArcKeyPath {
    param([string]$Path, [string[]]$TokenDirectories)
    # Reject links/reparse points in EVERY component, including the token directory
    # and its ancestors. A leaf-only ResolveLinkTarget misses directory escapes.
    # Failure to inspect a component is a refusal, never permission to read it.
    try {
        if (-not [System.IO.Path]::IsPathFullyQualified($Path)) { return '' }
        $full = [System.IO.Path]::GetFullPath($Path)
        if (-not $full.EndsWith('.key', [System.StringComparison]::OrdinalIgnoreCase)) { return '' }
        $comparison = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
        $contained = $false
        foreach ($directory in $TokenDirectories) {
            if (-not [System.IO.Path]::IsPathFullyQualified($directory)) { continue }
            $prefix = [System.IO.Path]::GetFullPath($directory).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
            if ($full.StartsWith($prefix, $comparison)) { $contained = $true; break }
        }
        if (-not $contained) { return '' }
        $current = [System.IO.Path]::GetPathRoot($full)
        foreach ($part in $full.Substring($current.Length).Split([System.IO.Path]::DirectorySeparatorChar, [System.StringSplitOptions]::RemoveEmptyEntries)) {
            $current = Join-Path $current $part
            $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return '' }
        }
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return '' }
        return $full
    }
    catch { return '' }
}
function Resolve-AzureCloudEndpoints {
    $warnings = [System.Collections.Generic.List[string]]::new()
    $authority = Test-TrustedAzureEndpoint -Value ([string][Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST')) -KnownHosts $script:knownAzureAuthorityHosts -Label 'AZURE_AUTHORITY_HOST' -Warnings $warnings
    $arm = ''
    $armLabel = ''
    foreach ($candidate in @('AZURE_RESOURCE_MANAGER_ENDPOINT', 'ARM_ENDPOINT')) {
        $value = ([string][Environment]::GetEnvironmentVariable($candidate)).Trim()
        if (-not $value) { continue }
        # The walk continues past a REJECTED value (review finding): a broken preferred
        # override must not silence a usable ARM_ENDPOINT behind it — only an accepted
        # origin ends the walk (each rejection is already a warning above).
        $arm = Test-TrustedAzureEndpoint -Value $value -KnownHosts $script:knownAzureArmHosts -Label $candidate -Warnings $warnings
        if ($arm) { $armLabel = $candidate; break }
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
    # The current hub's token probe and ArmClient use public ARM. A successful
    # sovereign-cloud probe would not verify that runtime, so fail before OAuth.
    if (-not $unresolved -and ($authority.TrimEnd('/') -ne 'https://login.microsoftonline.com' -or $arm.TrimEnd('/') -ne 'https://management.azure.com')) {
        $unresolved = 'the selected cloud is unsupported by the current hub: its token probe and ArmClient target public Azure; configure matching runtime cloud support before verification'
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
            # No redirects (second-reviewer finding): Invoke-WebRequest follows 3xx by
            # default and would replay a bearer token, identity header, or client-secret
            # POST body at whatever Location the server named — an endpoint this script
            # never validated. A 3xx is reported as the status it is and never followed.
            MaximumRedirection = 0
        }
        if ($Headers.Count -gt 0) { $request['Headers'] = $Headers }
        if ($Body) { $request['Body'] = $Body }
        if ($ContentType) { $request['ContentType'] = $ContentType }
        # IMDS is link-local and must never be routed through HTTPS_PROXY — proxied,
        # it would neither reach 169.254.169.254 nor fail fast.
        if ($NoProxy) { $request['NoProxy'] = $true }
        $response = Invoke-WebRequest @request
        # Response headers are returned too (review finding): the Azure Arc managed-identity
        # handshake carries its challenge in WWW-Authenticate, and nothing else reads them.
        [pscustomobject]@{ Status = [int]$response.StatusCode; Body = [string]$response.Content; Transport = ''; Headers = $response.Headers }
    }
    catch {
        [pscustomobject]@{ Status = 0; Body = ''; Transport = $_.Exception.Message; Headers = @{} }
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
        # The configured COMMAND alone, untrimmed (review finding): an entry without a
        # command is unconfigured whatever its name says (IsOnPath('') is false).
        $cmd = if ($agent.PSObject.Properties['command'] -and $null -ne $agent.command) { [string]$agent.command } else { '' }
        $leaf = ''
        if ($cmd) { try { $leaf = [System.IO.Path]::GetFileNameWithoutExtension($cmd) } catch { $leaf = $cmd } }
        $key = if ($leaf) { $leaf.ToLowerInvariant() } else { '' }
        if ($key -eq 'codex') { $names.Add('OPENAI_API_KEY') }
        elseif ($key -in 'claude', 'claude-cli') { $names.Add('ANTHROPIC_API_KEY') }
    }
    return $names.ToArray()
}

# Typed MEMBERS of the hub config (review finding): System.Text.Json rejects a JSON
# string where AIHubOptions declares a bool or an int, a non-integer number for an
# int, and null for a non-nullable bool / int; a string member accepts a string or
# null, except provider.type, learning.localPath and an ENABLED cliAgents entry's name
# and argsTemplate, which the hub dereferences (review findings).
# Same rules as auto-login.ps1's step 0 and auth-doctor's Get-AIHubConfigState.
$script:aihubMemberSchemas = @{
    provider        = @{ type = 'string!'; enabled = 'bool'; model = 'string'; apiKeyEnv = 'string'; apiKeySecretName = 'string'; endpointEnv = 'string'; baseUrl = 'string' }
    cliAgent        = @{ name = 'string'; enabled = 'bool'; command = 'string'; argsTemplate = 'string'; model = 'string'; timeoutSeconds = 'int' }
    # An ENABLED entry's name is required (the hub keys its provider map on it) and,
    # when learning is enabled, mode / tableEndpointEnv are dereferenced by
    # CreateLearningStore (review findings) — the same rule as auto-login / auth-doctor.
    cliAgentEnabled = @{ name = 'string!'; enabled = 'bool'; command = 'string'; argsTemplate = 'string!'; model = 'string'; timeoutSeconds = 'seconds' }
    learning        = @{ enabled = 'bool'; mode = 'string'; localPath = 'string!'; tableEndpointEnv = 'string'; adaptiveRouting = 'bool'; historyWindow = 'int' }
    learningEnabled = @{ enabled = 'bool'; mode = 'string!'; localPath = 'string!'; tableEndpointEnv = 'string!'; adaptiveRouting = 'bool'; historyWindow = 'int' }
}
function Get-AIHubRoutingProblem {
    param([Parameter(Mandatory)]$Routing)
    $shapeOf = { param($v) if ($null -eq $v) { 'null' } elseif ($v -is [System.Array]) { 'an array' } elseif ($v -is [System.Management.Automation.PSCustomObject]) { 'an object' } elseif ($v -is [string]) { 'a JSON string' } elseif ($v -is [bool]) { 'a JSON boolean' } else { 'a JSON number' } }
    $chainProblem = {
        param($chainValue, [string]$path)
        $i = 0
        foreach ($e in @($chainValue)) { if ($e -isnot [string]) { return "$path[$i] is $(& $shapeOf $e), not a provider name (string)" }; $i++ }
        return ''
    }
    $chainProp = $Routing.PSObject.Properties['defaultChain']
    if ($null -ne $chainProp) {
        if ((& $shapeOf $chainProp.Value) -ne 'an array') { return "routing.defaultChain is $(& $shapeOf $chainProp.Value), not an array" }
        $problem = & $chainProblem $chainProp.Value 'routing.defaultChain'
        if ($problem) { return $problem }
    }
    $tableProp = $Routing.PSObject.Properties['taskRouting']
    if ($null -ne $tableProp) {
        if ((& $shapeOf $tableProp.Value) -ne 'an object') { return "routing.taskRouting is $(& $shapeOf $tableProp.Value), not an object" }
        foreach ($entry in $tableProp.Value.PSObject.Properties) {
            if ((& $shapeOf $entry.Value) -ne 'an array') { return "routing.taskRouting.$($entry.Name) is $(& $shapeOf $entry.Value), not an array" }
            $problem = & $chainProblem $entry.Value "routing.taskRouting.$($entry.Name)"
            if ($problem) { return $problem }
        }
    }
    return ''
}
# enabled absent → the hub's default (cliAgents true, learning false); exactly true → enabled.
function Test-AIHubMemberEnabled {
    param([Parameter(Mandatory)]$Object, [Parameter(Mandatory)][bool]$Default)
    $enabledProp = $Object.PSObject.Properties['enabled']
    if ($null -eq $enabledProp) { return $Default }
    return ($enabledProp.Value -is [bool] -and $enabledProp.Value)
}
function Get-AIHubMemberProblem {
    param([Parameter(Mandatory)]$Object, [Parameter(Mandatory)][hashtable]$Schema, [Parameter(Mandatory)][string]$Path)
    foreach ($member in $Object.PSObject.Properties) {
        $kind = $Schema[$member.Name]
        if (-not $kind) { continue }
        $v = $member.Value
        $ok = switch ($kind) {
            'string' { ($null -eq $v) -or ($v -is [string]) }
            'string!' { $v -is [string] }
            'bool' { $v -is [bool] }
            'int' { (($v -is [int]) -or ($v -is [long])) -and $v -ge [int]::MinValue -and $v -le [int]::MaxValue }
            # Enabled cliAgents timeouts are range-checked (review finding): CancelAfter
            # throws on a negative TimeSpan after the child was started, zero cancels
            # every request before it answers.
            'seconds' { (($v -is [int]) -or ($v -is [long])) -and $v -ge 1 -and $v -le 2147483 }
        }
        if (-not $ok) {
            $shape = if ($null -eq $v) { 'null' } elseif ($v -is [System.Array]) { 'an array' } elseif ($v -is [System.Management.Automation.PSCustomObject]) { 'an object' } elseif ($v -is [string]) { 'a JSON string' } elseif ($v -is [bool]) { 'a JSON boolean' } else { 'a JSON number' }
            $expected = switch ($kind) { 'string' { 'a string' } 'string!' { 'a non-null string' } 'bool' { 'true or false' } 'int' { 'an integer' } 'seconds' { 'an integer from 1 to 2147483 (seconds — CliProcessAgent hands it to CancellationTokenSource.CancelAfter, which throws on a negative value and cancels a zero before the first byte; the child process is already running by then)' } }
            return "$Path.$($member.Name) is $shape, not $expected"
        }
    }
    return ''
}

function Get-ConfiguredGitHubModelsEnvs {
    # Enabled providers of TYPE github-models (review finding: ProviderFactory
    # dispatches on provider.type, never on a canonical key), each contributing its
    # apiKeyEnv — or the factory default GITHUB_MODELS_TOKEN when unset — but ONLY
    # when the provider resolves to the public GitHub Models endpoint (no baseUrl,
    # or a baseUrl on models.github.ai). A credential bound to a custom baseUrl
    # belongs to THAT endpoint and must never be sent to api.github.com (review
    # finding: the verifier would otherwise disclose an unrelated service credential
    # to GitHub). An unreadable config — explicit or the repo default — contributes
    # NO candidate (review finding: AIHubService.ResolveConfigPath / AIHubOptions.Load
    # fail on the same file, so there is no hub to probe for); a parsed config with no
    # qualifying provider → no candidate from config at all.
    $default = 'GITHUB_MODELS_TOKEN'
    $explicitProfile = Test-EnvValue 'AIHUB_CONFIG'
    # Literal value (review finding): AIHubService.ResolveConfigPath hands it to
    # File.OpenRead untouched, so a padded value names a different file for the hub.
    $configPath = if ($explicitProfile) { [string]$env:AIHUB_CONFIG }
    else { Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'config' 'aihub.json' }
    # A profile the hub cannot load contributes NO candidate (review findings): the
    # built-in name would be an invented profile's, and the dry-run walk says why.
    $script:configuredModelsNote = ''
    $script:nonGitHubReaderEnvs = [System.Collections.Generic.HashSet[string]]::new($script:EnvNameComparer)
    $unreadableExplicit = "(AIHUB_CONFIG selects '$configPath' but it is missing, unparseable, or not a JSON object — the hub cannot load it either; no config candidate)"
    $unreadableDefault = "(the repo default '$configPath' is missing, unparseable, or not a JSON object — AIHubService.ResolveConfigPath / AIHubOptions.Load fail on it too, so no hub can start; no config candidate)"
    try {
        $parsed = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        # The hub binds the document to an object; anything else is unreadable to it too.
        if ($parsed -isnot [System.Management.Automation.PSCustomObject]) {
            $script:configuredModelsNote = if ($explicitProfile) { $unreadableExplicit } else { $unreadableDefault }
            return @()
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
        # The other typed sections fail the hub the same way (review finding): a null
        # or wrong-shaped cliAgents (List<CliAgentOptions>, enumerated by CreateAll with
        # every element dereferenced), routing or learning (objects the hub and
        # AIHubOptions.Load dereference) means there is no hub to probe for.
        foreach ($rule in @(@{ Name = 'cliAgents'; Wanted = 'an array' }, @{ Name = 'routing'; Wanted = 'an object' }, @{ Name = 'learning'; Wanted = 'an object' })) {
            $sectionProp = $parsed.PSObject.Properties[$rule.Name]
            if ($null -eq $sectionProp) { continue }
            $sectionValue = $sectionProp.Value
            $shape = if ($null -eq $sectionValue) { 'null' } elseif ($sectionValue -is [System.Array]) { 'an array' } elseif ($sectionValue -is [System.Management.Automation.PSCustomObject]) { 'an object' } else { "a $($sectionValue.GetType().Name)" }
            $badElement = ''
            if ($shape -eq $rule.Wanted -and $rule.Name -eq 'cliAgents') {
                $cliIndex = 0
                foreach ($element in @($sectionValue)) {
                    if ($null -eq $element -or $element -isnot [System.Management.Automation.PSCustomObject]) { $badElement = "cliAgents[$cliIndex] is $(if ($null -eq $element) { 'null' } else { 'a non-object' })"; break }
                    $badElement = Get-AIHubMemberProblem -Object $element -Schema $(if (Test-AIHubMemberEnabled -Object $element -Default $true) { $script:aihubMemberSchemas.cliAgentEnabled } else { $script:aihubMemberSchemas.cliAgent }) -Path "cliAgents[$cliIndex]"
                    if ($badElement) { break }
                    $cliIndex++
                }
            }
            elseif ($shape -eq $rule.Wanted -and $rule.Name -eq 'learning') {
                $badElement = Get-AIHubMemberProblem -Object $sectionValue -Schema $(if (Test-AIHubMemberEnabled -Object $sectionValue -Default $false) { $script:aihubMemberSchemas.learningEnabled } else { $script:aihubMemberSchemas.learning }) -Path 'learning'
            }
            elseif ($shape -eq $rule.Wanted -and $rule.Name -eq 'routing') {
                # Nested routing members too (review finding): defaultChain binds a
                # List<string>, taskRouting a Dictionary<string, List<string>>.
                $badElement = Get-AIHubRoutingProblem -Routing $sectionValue
            }
            if ($shape -ne $rule.Wanted -or $badElement) {
                $what = if ($badElement) { $badElement } else { "`"$($rule.Name)`" is $shape, not $($rule.Wanted)" }
                $script:configuredModelsNote = "(the active config '$configPath' declares $what — AIHubOptions cannot bind it and the hub fails to load or start; no config candidate)"
                return @()
            }
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
            $entryProblem = Get-AIHubMemberProblem -Object $prov -Schema $script:aihubMemberSchemas.provider -Path "providers.$($prop.Name)"
            if ($entryProblem) {
                $script:configuredModelsNote = "(the active config '$configPath' declares $entryProblem — AIHubOptions.Load cannot bind it and the hub fails to load or start; no config candidate)"
                return @()
            }
            # Exactly as ProviderFactory.Create dispatches (review finding): case-folded,
            # never trimmed — a padded type is an unknown provider that reads no key.
            $provType = ([string](Get-OptionalProperty $prov 'type' '')).ToLowerInvariant()
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
            # LITERAL name (review finding): blank is detected with IsNullOrWhiteSpace —
            # the only normalization SecretResolver applies — and any other value is
            # probed exactly as declared, whitespace included, because the factory
            # hands it to Environment.GetEnvironmentVariable untouched.
            $envName = if ($null -eq $envProp -or $null -eq $envProp.Value) { $typeDefault } elseif ([string]::IsNullOrWhiteSpace([string]$envProp.Value)) { '' } else { [string]$envProp.Value }
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
                        # Default port only (review finding): https://models.github.ai:444 is another origin.
                        $isPublicModels = ($parsedBase.Scheme -eq 'https' -and $parsedBase.Host.Equals('models.github.ai', [System.StringComparison]::OrdinalIgnoreCase) -and $parsedBase.IsDefaultPort)
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
        $script:configuredModelsNote = if ($explicitProfile) { $unreadableExplicit } else { $unreadableDefault }
        return @()
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
    $script:paddedEnvSources = [System.Collections.Generic.List[string]]::new()
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
        if ([string]::IsNullOrWhiteSpace($value)) { continue }
        # Literal VALUE too (review finding): SecretResolver.Resolve hands the hub the
        # variable unchanged, so a value with surrounding whitespace / control characters
        # (a secret loader's trailing newline) is exactly what ApiKeyCredential would
        # receive — and header construction fails on it. Probing a trimmed copy would
        # certify a credential the hub never sends, so the padded value is not probed at
        # all; its repair (re-export it exactly) is definitive, never "retry later".
        if ($value -ne $value.Trim()) {
            $script:candidateNotes.Add("env:$envName carries surrounding whitespace / control characters (a secret loader's trailing newline?) — SecretResolver.Resolve hands it to the provider unchanged, so the hub's request would fail; not probed")
            $script:paddedEnvSources.Add($envName)
            continue
        }
        $candidates.Add([pscustomobject]@{ Source = "env:$envName"; Token = $value })
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
        $alreadyCandidate = @($candidates | Where-Object { [string]::Equals($_.Token, $ghToken, [StringComparison]::Ordinal) }).Count -gt 0
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
    # A padded variable is a definitive wiring defect (review finding): the value is
    # present but unusable as the hub reads it, and only re-exporting it exactly repairs
    # that — so it is an owner step whether or not another candidate exists.
    $paddedNames = @($script:paddedEnvSources | Select-Object -Unique)
    $paddedAction = if ($paddedNames.Count -gt 0) {
        "re-export $($paddedNames -join ' / ') exactly, without the surrounding whitespace / trailing newline the value carries (bash: NAME=`$(printf '%s' `"`$NAME`"); pwsh: `$env:NAME = `$env:NAME.Trim()) — SecretResolver hands the variable to the provider unchanged"
    } else { '' }
    if (@($candidates).Count -eq 0) {
        if ($paddedAction) {
            return New-LaneResult -Lane 'github' -State 'needs-owner' -Source 'none' `
                -Detail ("the only candidate token(s) present carry surrounding whitespace / control characters and were not probed: $($script:candidateNotes -join '; ') — re-exporting the value exactly is an owner step") `
                -OwnerAction $paddedAction
        }
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
        if ($paddedAction) {
            # The padded variable is definitive even when every probed candidate was only
            # transient: retrying cannot strip the newline from the value the hub reads.
            return New-LaneResult -Lane 'github' -State 'needs-owner' -Source 'none' `
                -Detail ("no probed candidate got a definitive answer (transient: $chainText), but a configured variable carries surrounding whitespace and was not probed — re-exporting it exactly is the owner step") `
                -OwnerAction $paddedAction
        }
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
        -OwnerAction ((@($paddedAction, $rotateAction, $loginAction) | Where-Object { $_ }) -join '; or: ')
}

# --- azure lane -------------------------------------------------------------------------
# Probes ARM with the selected token. Every outcome carries a terminal Lane:
# success, RBAC failure, token rejection, or retryable/unverifiable response.
# Once a credential acquires a token, ARM cannot select another principal.
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
            return [pscustomobject]@{ Outcome = 'transient'; Lane = (New-LaneResult -Lane azure -State unavailable -Source $Source -Identity $Identity -Detail ($ChainNotes -join '; ') -OwnerAction 'retry the selected identity after checking ARM connectivity; no later principal was used') }
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
        # never fix that. Token acquisition already selected the identity, so this
        # result is terminal even if another principal could access ARM.
        $ChainNotes.Add("$Source acquired a token but ARM answered 403 — principal lacks an RBAC role (selected identity; no fallback)")
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
        return [pscustomobject]@{ Outcome = 'auth-rejected'; Lane = (New-LaneResult -Lane azure -State 'needs-owner' -Source $Source -Identity $Identity -Detail ($ChainNotes -join '; ') -OwnerAction 'verify the selected identity, tenant and ARM token audience; no later principal was used') }
    }
    elseif ($probe.Status -eq 0) {
        $ChainNotes.Add("$Source acquired a token but the ARM probe hit a transport failure ($($probe.Transport))")
    }
    else {
        $ChainNotes.Add("$Source acquired a token but ARM answered HTTP $($probe.Status)")
    }
    return [pscustomobject]@{ Outcome = 'transient'; Lane = (New-LaneResult -Lane azure -State unavailable -Source $Source -Identity $Identity -Detail ($ChainNotes -join '; ') -OwnerAction 'retry the selected identity after checking ARM connectivity; no later principal was used') }
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
            -Detail ("the Azure control-plane endpoints do not resolve to a cloud supported by this hub, so no credential source was tried and nothing was sent anywhere: $($chainNotes -join '; ')") `
            -OwnerAction 'align the selected cloud with the hub runtime before retrying; current ArmClient/token-probe support is public Azure only; sovereign deployments require matching runtime cloud support, not a public-cloud sign-in'
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
    # A USABLE Actions OIDC environment (review finding): the URL variable alone can be
    # empty, stale, or inherited on a non-Actions host, and a false "available" would
    # end the lane ci-delegated ("the job already has id-token: write") instead of the
    # real no-credential setup action. All three must hold — GITHUB_ACTIONS = true, a
    # non-blank ACTIONS_ID_TOKEN_REQUEST_URL and a non-blank
    # ACTIONS_ID_TOKEN_REQUEST_TOKEN (names / emptiness only; values never read).
    $inActionsJob = ([string][Environment]::GetEnvironmentVariable('GITHUB_ACTIONS')).Trim().Equals('true', [System.StringComparison]::OrdinalIgnoreCase)
    $oidcUrlSet = Test-EnvValue 'ACTIONS_ID_TOKEN_REQUEST_URL'
    $oidcTokenSet = Test-EnvValue 'ACTIONS_ID_TOKEN_REQUEST_TOKEN'
    $ciOidcAvailable = $inActionsJob -and $oidcUrlSet -and $oidcTokenSet
    if ($ciOidcAvailable) {
        $chainNotes.Add('ci-oidc: GITHUB_ACTIONS job with ACTIONS_ID_TOKEN_REQUEST_URL + ACTIONS_ID_TOKEN_REQUEST_TOKEN set — OIDC is available to this job (azure/login owns the exchange; never duplicated here)')
    }
    elseif ($oidcUrlSet -or $oidcTokenSet -or (Test-Path env:ACTIONS_ID_TOKEN_REQUEST_URL)) {
        $chainNotes.Add("ci-oidc: OIDC request variables present but not a usable Actions environment (GITHUB_ACTIONS $(if ($inActionsJob) { 'true' } else { 'not true' }); ACTIONS_ID_TOKEN_REQUEST_URL $(if ($oidcUrlSet) { 'set' } else { 'blank' }); ACTIONS_ID_TOKEN_REQUEST_TOKEN $(if ($oidcTokenSet) { 'set' } else { 'blank' })) — not counted as a credential source")
    }

    $azCmd = Get-CliCommand -Name 'az'
    # Failure classification across the whole chain (review findings): MFA/re-login
    # advice requires at least one DEFINITIVE auth rejection — transient-only runs
    # (transport/429/5xx) end as unavailable-retryable, never credential advice.
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
    # Inspect certificate availability independently, but a configured secret takes
    # precedence. Selecting the certificate requires unsetting the secret first.
    $spCertReady = (Test-EnvValue 'AZURE_CLIENT_ID') -and
        (Test-EnvValue 'AZURE_TENANT_ID') -and (Test-EnvValue 'AZURE_CLIENT_CERTIFICATE_PATH')
    # A set-but-missing certificate FILE cannot run the flow either (review
    # finding): auth-doctor -Apply would just fail on the same absent file, so the
    # terminal cert action must not be armed. Path existence only — contents are
    # never read here.
    # -PathType Leaf (review finding): a directory at that path passes a bare
    # Test-Path, and the epilogue would then advertise auth-doctor -Apply — which
    # requires a leaf itself and skips the certificate — as a working repair.
    # Remembered, not just noted (review finding): with no other rung holding a token
    # the terminal branch would otherwise prescribe installing / logging into az, or a
    # bare retry, and setup-everything.ps1 harvests ownerAction alone — so the mount
    # repair would vanish from the consolidated guidance. Rung 2c below returns it.
    $spCertFileProblem = ''
    if ($spCertReady -and -not (Test-Path -LiteralPath ([string]$env:AZURE_CLIENT_CERTIFICATE_PATH).Trim() -PathType Leaf)) {
        $spCertFileProblem = 'AZURE_CLIENT_CERTIFICATE_PATH is set but no FILE exists at that path (a directory does not count; path checked only, contents never read)'
        $chainNotes.Add("env-service-principal-cert: $spCertFileProblem — the certificate flow cannot run until the file is present")
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
        $spToken = ''
        if ($tokenProbe.Status -eq 200) {
            $tokenReply = Test-ParsedJson $tokenProbe.Body
            $spToken = [string](Get-OptionalProperty $tokenReply 'access_token' '')
            if ($spToken) {
                $tokenHeld = $true
                $arm = Invoke-ArmProbe -Token $spToken -Source 'env-service-principal' `
                    -Identity "service principal $clientId" -ChainNotes $chainNotes
                # Token selection is complete; ARM errors cannot select a different principal.
                return $arm.Lane
            }
            else {
                $chainNotes.Add('env-service-principal: token endpoint 200 but no access_token field (raw body never echoed)')
            }
        }
        else {
            $spStatus = if ($tokenProbe.Status -eq 0) { "transport failure ($($tokenProbe.Transport))" } else { "HTTP $($tokenProbe.Status)" }
            $chainNotes.Add("env-service-principal: token endpoint $spStatus (raw error body never echoed)")
            # 400/401/403 from the token endpoint = the SP credential was rejected
            # (invalid_client and friends) — a definitive rejection, unlike 5xx/transport.
            if ($tokenProbe.Status -in 400, 401, 403) {
                # TERMINAL (review finding): Azure.Identity's DefaultAzureCredential stops at
                # a configured EnvironmentCredential that FAILS authentication — only an
                # unavailable credential falls through — so while these three variables
                # are set the hub never reaches managed identity or the az cache. A healthy
                # later rung must therefore not report the lane ready; rotation is the repair.
                $sawAuthRejection = $true
                return New-LaneResult -Lane 'azure' -State 'needs-owner' -Source 'env-service-principal' `
                    -Identity "service principal $clientId" `
                    -Detail ("the configured service principal (AZURE_CLIENT_ID + AZURE_TENANT_ID + AZURE_CLIENT_SECRET) was rejected by the token endpoint ($spStatus; raw error body never echoed) — DefaultAzureCredential stops at a configured credential that fails authentication and never tries managed identity or the az cache, so the hub fails here whatever the later rungs hold; chain so far: $($chainNotes -join '; ')") `
                    -OwnerAction 'repair the selected AZURE_CLIENT_ID / AZURE_TENANT_ID / AZURE_CLIENT_SECRET credential, or deliberately unset AZURE_CLIENT_SECRET when choosing another credential mode; a later login cannot override this selected environment credential'
            }
        }
        if (-not $spToken) {
            # Deployed-credential continuation also stops on transport/service
            # failures and malformed token responses. They are retryable, but a
            # later MI/CLI token cannot prove the selected SDK credential ready.
            return New-LaneResult -Lane 'azure' -State 'unavailable' -Source 'env-service-principal' `
                -Detail ("the selected environment service principal did not obtain a token ($($chainNotes -join '; ')); DefaultAzureCredential stops here, so later sources were not tried; check service/transport health and retry without rotating credentials on this evidence")
        }
    }
    # 2b. Federated workload identity (review finding): AKS / Container Apps with a
    #     federated credential supply AZURE_CLIENT_ID + AZURE_TENANT_ID +
    #     AZURE_FEDERATED_TOKEN_FILE and no secret, and DefaultAzureCredential's
    #     WorkloadIdentityCredential exchanges the file's assertion (jwt-bearer
    #     client_assertion) for a token — mirrored here in memory: the assertion is
    #     read into a local, posted once to the active cloud's authority, and never
    #     echoed. It is a credential source in its own right, so an application
    #     container without az is not told to install the CLI.
    $wiReady = (Test-EnvValue 'AZURE_CLIENT_ID') -and (Test-EnvValue 'AZURE_TENANT_ID') -and (Test-EnvValue 'AZURE_FEDERATED_TOKEN_FILE')
    # The token FILE is validated before the source counts (review finding): a
    # configured-but-unreadable file is a definitive wiring problem — no retry repairs
    # a missing mount — so it is remembered as its own owner step below, and the
    # source is recorded only once a non-blank assertion was actually read.
    $wiFileProblem = ''
    if ($wiReady) {
        $wiPath = ([string]$env:AZURE_FEDERATED_TOKEN_FILE).Trim()
        if (-not (Test-Path -LiteralPath $wiPath -PathType Leaf)) {
            $wiFileProblem = 'AZURE_FEDERATED_TOKEN_FILE is set but no FILE exists at that path (a directory does not count; path checked only)'
            $chainNotes.Add("workload-identity: $wiFileProblem — the federated exchange cannot run")
        }
        else {
            $assertion = ''
            try { $assertion = ([string](Get-Content -LiteralPath $wiPath -Raw -ErrorAction Stop)).Trim() } catch { $assertion = '' }
            if (-not $assertion) {
                $wiFileProblem = 'AZURE_FEDERATED_TOKEN_FILE is empty or unreadable (contents never echoed)'
                $chainNotes.Add("workload-identity: $wiFileProblem — the federated exchange cannot run")
            }
            else {
                $credentialSourcePresent = $true
                $wiClientId = [string]$env:AZURE_CLIENT_ID     # appId — an identifier, not a secret
                $wiTenantId = [string]$env:AZURE_TENANT_ID
                $body = ('grant_type=client_credentials&client_id={0}&client_assertion_type={1}&client_assertion={2}&scope={3}' -f
                    [uri]::EscapeDataString($wiClientId),
                    [uri]::EscapeDataString('urn:ietf:params:oauth:client-assertion-type:jwt-bearer'),
                    [uri]::EscapeDataString($assertion),
                    [uri]::EscapeDataString($armScope))
                $assertion = ''
                $tokenUrl = "$($azureCloud.Authority)/$wiTenantId/oauth2/v2.0/token"
                $tokenProbe = Invoke-HttpProbe -Url $tokenUrl -Method 'Post' -Body $body `
                    -ContentType 'application/x-www-form-urlencoded' -TimeoutSec $TimeoutSeconds
                $body = ''   # done with the assertion
                $wiToken = ''
                if ($tokenProbe.Status -eq 200) {
                    $tokenReply = Test-ParsedJson $tokenProbe.Body
                    $wiToken = [string](Get-OptionalProperty $tokenReply 'access_token' '')
                    if ($wiToken) {
                        $tokenHeld = $true
                        $arm = Invoke-ArmProbe -Token $wiToken -Source 'workload-identity' `
                            -Identity "workload identity (client $wiClientId, federated assertion from AZURE_FEDERATED_TOKEN_FILE)" -ChainNotes $chainNotes
                        # Token selection is complete; ARM errors cannot select a different principal.
                        return $arm.Lane
                    }
                    else {
                        $chainNotes.Add('workload-identity: token endpoint 200 but no access_token field (raw body never echoed)')
                    }
                }
                else {
                    $wiStatus = if ($tokenProbe.Status -eq 0) { "transport failure ($($tokenProbe.Transport))" } else { "HTTP $($tokenProbe.Status)" }
                    $chainNotes.Add("workload-identity: token endpoint $wiStatus (raw error body never echoed)")
                    # 400/401/403 = the federated credential itself was rejected (same
                    # rejection set as the env service principal above).
                    if ($tokenProbe.Status -in 400, 401, 403) {
                        # TERMINAL too (review finding): WorkloadIdentityCredential is a
                        # configured credential; its authentication failure stops
                        # DefaultAzureCredential before managed identity and the az cache.
                        $sawAuthRejection = $true
                        return New-LaneResult -Lane 'azure' -State 'needs-owner' -Source 'workload-identity' `
                            -Identity "workload identity (client $wiClientId)" `
                            -Detail ("the configured workload identity (AZURE_CLIENT_ID + AZURE_TENANT_ID + AZURE_FEDERATED_TOKEN_FILE) was rejected by the token endpoint ($wiStatus; raw error body never echoed) — DefaultAzureCredential stops at a configured credential that fails authentication and never tries managed identity or the az cache; chain so far: $($chainNotes -join '; ')") `
                            -OwnerAction 'fix the federated credential of the app behind AZURE_CLIENT_ID (issuer / subject / audience must match the assertion in AZURE_FEDERATED_TOKEN_FILE — az ad app federated-credential list --id <AZURE_CLIENT_ID>) or the AZURE_TENANT_ID pairing, or unset AZURE_FEDERATED_TOKEN_FILE so DefaultAzureCredential falls through to managed identity or the az cache'
                    }
                }
                if (-not $wiToken) {
                    # Same continuation policy as the env service principal (rung 2): a
                    # transport / service failure or a malformed token response from a
                    # SELECTED credential stops DefaultAzureCredential too — it is
                    # retryable, but a later managed-identity / CLI token would only
                    # prove a source the hub never reaches.
                    return New-LaneResult -Lane 'azure' -State 'unavailable' -Source 'workload-identity' `
                        -Detail ("the selected workload identity (AZURE_CLIENT_ID + AZURE_TENANT_ID + AZURE_FEDERATED_TOKEN_FILE) did not obtain a token ($($chainNotes -join '; ')); DefaultAzureCredential stops here, so later sources were not tried; check service/transport health and retry without changing the federated credential on this evidence")
                }
            }
        }
    }
    elseif (Test-EnvValue 'AZURE_FEDERATED_TOKEN_FILE') {
        $chainNotes.Add('workload-identity: AZURE_FEDERATED_TOKEN_FILE is set but AZURE_CLIENT_ID / AZURE_TENANT_ID are not both set (names checked only) — the federated exchange cannot run')
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
    # No-token outcomes are chain evidence (review findings): a declared endpoint's
    # 401/403 is a rejected credential (configuration, not an outage); anything else —
    # unreachable, another status, 200 without access_token — is recorded and the
    # chain moves on. Returns $true only for the rejected-credential case.
    function Add-ManagedIdentityOutcomeNote {
        param([Parameter(Mandatory)][string]$Kind, [Parameter(Mandatory)]$Probe)
        if ($Probe.Status -eq 200) {
            $chainNotes.Add("managed-identity ($Kind): endpoint 200 but no access_token field (raw body never echoed)")
            return $false
        }
        $miStatus = if ($Probe.Status -eq 0) { 'unreachable (expected off-Azure; failed fast)' } else { "HTTP $($Probe.Status)" }
        if ($Kind -ne 'imds' -and $Probe.Status -in 401, 403) {
            # Only a DECLARED endpoint (IDENTITY_ENDPOINT / MSI_ENDPOINT) can reject the
            # request for a configuration reason; raw IMDS non-200s stay what they are
            # (a non-Azure host or a metadata firewall — not a credential source).
            $chainNotes.Add("managed-identity ($Kind): endpoint answered $miStatus — the identity header/secret (IDENTITY_HEADER / MSI_SECRET) or the endpoint wiring is rejected; this is configuration, not an outage")
            return $true
        }
        if ($Kind -ne 'imds' -and $Probe.Status -eq 400) {
            # Identity selection refused (review finding): a declared endpoint answers 400
            # when the requested identity — the client_id selector taken from
            # AZURE_CLIENT_ID — is not assigned to this host, or the resource is refused.
            # That is configuration too: a retry cannot assign an identity, so it must
            # end in the wiring verdict, never in "transient — retry later".
            $selectorNote = if (-not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable('AZURE_CLIENT_ID'))) {
                ' — AZURE_CLIENT_ID is set (name checked only) and its user-assigned identity is not assigned to this host, or the resource was refused: assign that identity, or unset AZURE_CLIENT_ID to use the system-assigned one; configuration, not an outage'
            } else { ' — the endpoint refused the token request parameters (identity / resource); configuration, not an outage' }
            $chainNotes.Add("managed-identity ($Kind): endpoint answered HTTP 400 to the identity selection$selectorNote")
            return $true
        }
        $chainNotes.Add("managed-identity ($Kind): $miStatus")
        return $false
    }
    # Probe declared implementations in order so MSI_ENDPOINT can still be tried
    # when IDENTITY_ENDPOINT is set but unusable.
    $miDeclared = $false
    $miUsableDeclared = $false   # at least one declared endpoint passed the shape check
    $miKind = ''
    $miToken = ''
    $miProbe = $null
    # AZURE_CLIENT_ID (when set) selects the USER-ASSIGNED identity, exactly as
    # ManagedIdentityCredential does (review finding): without the selector an
    # endpoint answers for the system-assigned identity — a different principal, so
    # the lane would report a false failure or readiness for the wrong identity. The
    # selector is `client_id` on the 2019-08-01 App Service shape and on IMDS,
    # `clientid` on the legacy 2017-09-01 MSI shape; the Arc and Cloud Shell shapes
    # serve the system-assigned identity only and get a note instead. An identifier,
    # not a secret (never echoed anyway).
    $miClientId = if (Test-EnvValue 'AZURE_CLIENT_ID') { ([string]$env:AZURE_CLIENT_ID).Trim() } else { '' }
    $miCandidates = @(
        [pscustomobject]@{ Kind = 'identity-endpoint'; Env = 'IDENTITY_ENDPOINT'; HeaderEnv = 'IDENTITY_HEADER'; HeaderName = 'X-IDENTITY-HEADER'; ApiVersion = '2019-08-01'; Metadata = $false; Selector = 'client_id' }
        [pscustomobject]@{ Kind = 'msi-endpoint'; Env = 'MSI_ENDPOINT'; HeaderEnv = 'MSI_SECRET'; HeaderName = 'Secret'; ApiVersion = '2017-09-01'; Metadata = $true; Selector = 'clientid' }
    )
    $miCandidates = @($miCandidates | Where-Object { Test-EnvValue $_.Env })
    foreach ($miCandidate in $miCandidates) {
        if (-not (Test-EnvValue $miCandidate.Env)) { continue }
        $miDeclared = $true
        $miKind = $miCandidate.Kind
        $miBase = Test-TrustedManagedIdentityEndpoint -Value ([string][Environment]::GetEnvironmentVariable($miCandidate.Env)) -Label $miCandidate.Env -Notes $chainNotes
        if (-not $miBase) { continue }   # rejected by shape: the note above is the evidence, nothing was sent
        $miUsableDeclared = $true
        $miHeaders = @{}
        if ($miCandidate.Metadata) { $miHeaders['Metadata'] = 'true' }
        $miHeaderValue = [Environment]::GetEnvironmentVariable($miCandidate.HeaderEnv)
        if ($null -ne $miHeaderValue) { $miHeaders[$miCandidate.HeaderName] = [string]$miHeaderValue }
        $miHeaderValue = $null
        # Azure Arc speaks a DIFFERENT protocol on the same shape (review finding): the
        # 40342 endpoint answers a Metadata request with 401 + `WWW-Authenticate: Basic
        # realm=<local secret file>`, and the token is fetched on a second request whose
        # Authorization is that file's contents — it never reads IDENTITY_HEADER. Probing
        # it with the App Service protocol reports Arc rejected while
        # DefaultAzureCredential authenticates fine, so the two flows are separated here.
        $miIsArc = $miBase.EndsWith('/metadata/identity/oauth2/token', [System.StringComparison]::OrdinalIgnoreCase)
        if ($miIsArc) { $miKind = 'arc-endpoint' }
        $miSelector = ''
        if ($miClientId -and $miIsArc) {
            $chainNotes.Add("managed-identity ($miKind): AZURE_CLIENT_ID is set, but the Azure Arc endpoint serves the system-assigned identity only — no user-assigned selector exists, so any token it returns is that identity's, not the configured client's")
        }
        elseif ($miClientId) {
            if ($miBase.EndsWith('/msi/token', [System.StringComparison]::OrdinalIgnoreCase)) {
                $miSelector = "&$($miCandidate.Selector)=$([uri]::EscapeDataString($miClientId))"
            }
            else {
                $chainNotes.Add("managed-identity ($miKind): AZURE_CLIENT_ID is set, but this endpoint shape (Cloud Shell) serves the system-assigned identity only — no user-assigned selector exists, so any token it returns is that identity's, not the configured client's")
            }
        }
        if ($miIsArc) {
            # Arc's own api-version and header set; the identity header is never sent here.
            $miHeaders = @{ Metadata = 'true' }
        }
        # An Arc challenge 401 is the PROTOCOL, not a rejected credential: when the
        # handshake stops early the specific reason is already recorded below, and the
        # generic "identity header/secret rejected" note (and the terminal verdict it
        # arms) would prescribe re-wiring IDENTITY_HEADER, which Arc never reads.
        $miSkipOutcomeNote = $false
        $miApiVersion = if ($miIsArc) { '2019-11-01' } else { $miCandidate.ApiVersion }
        $miUrl = "$miBase`?api-version=$miApiVersion&resource=$([uri]::EscapeDataString($armResource))$miSelector"
        $miProbe = Invoke-HttpProbe -Url $miUrl -Headers $miHeaders -TimeoutSec $TimeoutSeconds -NoProxy
        $miHeaders = $null
        if ($miIsArc -and $miProbe.Status -eq 401) {
            # Step two of the Arc handshake. The realm is accepted ONLY as an absolute
            # path under the documented Arc token directories with a .key extension, so a
            # rogue challenge cannot make this read an arbitrary file; the contents go
            # straight into one Authorization header and are never echoed or stored.
            # Enumerated, not indexed: the header collection's shape varies across
            # PowerShell / .NET versions, and the name compares case-insensitively.
            $miChallenge = ''
            try {
                foreach ($headerEntry in $miProbe.Headers.GetEnumerator()) {
                    if (([string]$headerEntry.Key).Equals('WWW-Authenticate', [System.StringComparison]::OrdinalIgnoreCase)) {
                        $miChallenge = (@($headerEntry.Value) -join ' ')
                        break
                    }
                }
            }
            catch { $miChallenge = '' }
            $miKeyPath = ''
            if ($miChallenge -match '(?i)realm\s*=\s*"?([^",]+)"?') { $miKeyPath = $Matches[1].Trim() }
            $arcTokenDirs = @('/var/opt/azcmagent/tokens/', 'C:\ProgramData\AzureConnectedMachineAgent\Tokens\')
            # CANONICAL containment (review finding): a textual prefix test accepts
            # /var/opt/azcmagent/tokens/../../../../home/victim/service.key — it satisfies
            # both the prefix and the .key suffix, and Get-Content then resolves the
            # traversal and ships that file out as Basic authorization. The realm comes
            # from whoever answers the loopback endpoint, so the path is collapsed with
            # GetFullPath FIRST and every test runs on the canonical result; a symlink
            # inside the directory is resolved and re-checked below before any read.
            $miKeyTrusted = $false
            $miKeyResolved = ''
            $arcDirsFull = [System.Collections.Generic.List[string]]::new()
            foreach ($arcDir in $arcTokenDirs) {
                try {
                    $arcDirFull = [System.IO.Path]::GetFullPath($arcDir)
                    if (-not $arcDirFull.EndsWith([string][System.IO.Path]::DirectorySeparatorChar)) { $arcDirFull += [System.IO.Path]::DirectorySeparatorChar }
                    $arcDirsFull.Add($arcDirFull)
                }
                catch { }
            }
            if ($miKeyPath -and [System.IO.Path]::IsPathRooted($miKeyPath)) {
                try { $miKeyResolved = [System.IO.Path]::GetFullPath($miKeyPath) } catch { $miKeyResolved = '' }
            }
            if ($miKeyResolved -and $miKeyResolved.EndsWith('.key', [System.StringComparison]::OrdinalIgnoreCase)) {
                foreach ($arcDirFull in $arcDirsFull) {
                    if ($miKeyResolved.StartsWith($arcDirFull, [System.StringComparison]::OrdinalIgnoreCase)) { $miKeyTrusted = $true; break }
                }
            }
            if (-not $miKeyPath) {
                $chainNotes.Add("managed-identity ($miKind): the Arc endpoint answered 401 without a parseable 'WWW-Authenticate: Basic realm=<file>' challenge — the handshake cannot continue and nothing further was sent")
                $miSkipOutcomeNote = $true
            }
            elseif (-not $miKeyTrusted) {
                $chainNotes.Add("managed-identity ($miKind): the Arc challenge named a key file that, once canonicalized, is outside the documented agent token directories ($($arcTokenDirs -join ', ')) or does not end .key — refused; no file was read and no second request was made")
                $miSkipOutcomeNote = $true
            }
            elseif (-not (Test-Path -LiteralPath $miKeyResolved -PathType Leaf)) {
                $chainNotes.Add("managed-identity ($miKind): the Arc challenge named a key file that does not exist (path checked only) — the himds agent may not have provisioned it for this user; no second request was made")
                $miSkipOutcomeNote = $true
            }
            else {
                # Reject every linked/reparse component before reading. Lexical
                # containment and a leaf-only link check cannot establish containment.
                $miKeyFinal = Get-TrustedArcKeyPath -Path $miKeyResolved -TokenDirectories $arcTokenDirs
                $miLinkTrusted = -not [string]::IsNullOrWhiteSpace($miKeyFinal)
                $arcSecret = ''
                if (-not $miLinkTrusted) {
                    $chainNotes.Add("managed-identity ($miKind): the Arc key path is outside the token directory, contains a link/reparse point, or could not be inspected — refused; the file was not read and no second request was made")
                    $miSkipOutcomeNote = $true
                }
                else { try { $arcSecret = ([string](Get-Content -LiteralPath $miKeyFinal -Raw -ErrorAction Stop)).Trim() } catch { $arcSecret = '' } }
                if (-not $arcSecret -and $miLinkTrusted) {
                    $chainNotes.Add("managed-identity ($miKind): the Arc key file is empty or unreadable by this user (contents never echoed) — the second request was not made")
                    $miSkipOutcomeNote = $true
                }
                elseif (-not $arcSecret) { }
                else {
                    $miProbe = Invoke-HttpProbe -Url $miUrl -Headers @{ Metadata = 'true'; Authorization = "Basic $arcSecret" } -TimeoutSec $TimeoutSeconds -NoProxy
                    $arcSecret = ''
                }
            }
        }
        if ($miProbe.Status -eq 200) {
            $miReply = Test-ParsedJson $miProbe.Body
            $miToken = [string](Get-OptionalProperty $miReply 'access_token' '')
            if ($miToken) { break }
        }
        if ($miSkipOutcomeNote) { $miSkipOutcomeNote = $false }
        elseif (Add-ManagedIdentityOutcomeNote -Kind $miKind -Probe $miProbe) { $miAuthRejected = $true }
    }
    if (-not $miDeclared) {
        $miKind = 'imds'
        # HARD 2s + -NoProxy: 169.254.169.254 is link-local; on a non-Azure host the
        # connect must fail fast, and a proxy must never swallow it into a long hang.
        $imdsSelector = if ($miClientId) { "&client_id=$([uri]::EscapeDataString($miClientId))" } else { '' }
        $miProbe = Invoke-HttpProbe -Url ($imdsUrl + $imdsSelector) -Headers @{ Metadata = 'true' } -TimeoutSec $imdsTimeoutSec -NoProxy
        if ($miProbe.Status -eq 200) {
            $miReply = Test-ParsedJson $miProbe.Body
            $miToken = [string](Get-OptionalProperty $miReply 'access_token' '')
        }
        if (-not $miToken) { [void](Add-ManagedIdentityOutcomeNote -Kind 'imds' -Probe $miProbe) }
    }
    if ($miToken) {
        $tokenHeld = $true
        $arm = Invoke-ArmProbe -Token $miToken -Source "managed-identity ($miKind)" `
            -Identity 'managed identity (principal not re-queried here)' -ChainNotes $chainNotes
        # Token selection is complete; ARM errors cannot select a different principal.
        return $arm.Lane
    }
    if ($miDeclared) {
        $miState = if ($miAuthRejected -or -not $miUsableDeclared) { 'needs-owner' } else { 'unavailable' }
        return New-LaneResult -Lane 'azure' -State $miState -Source "managed-identity ($miKind)" `
            -Detail ("selected managed identity did not yield a token; no alternate endpoint or CLI identity was tried: " + ($chainNotes -join '; ')) `
            -OwnerAction 'verify the selected managed-identity endpoint and identity assignment on this host; retry transient failures without changing credentials'
    }
    # A managed-identity SOURCE exists when a declared endpoint passed the shape check
    # (App Service / Functions / Arc / Cloud Shell hosts) or IMDS actually answered a
    # token request with 200. Unreachable IMDS (status 0) is the normal off-Azure
    # state, and a non-200 HTTP answer at that address (e.g. a container fabric's
    # metadata firewall returning 403 — measured) is just as permanently unusable:
    # neither is a credential source, and "retry later" cannot fix either. A declared
    # endpoint that failed the shape check is not a source either (review finding):
    # nothing was contacted, so it can neither succeed nor be retried.
    if ($miUsableDeclared -or ($null -ne $miProbe -and $miProbe.Status -eq 200)) {
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
                # Token selection is complete; ARM errors cannot select a different principal.
                return $arm.Lane
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
    # 1. A configured certificate is a usable NON-INTERACTIVE repair that this
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
            -Detail ("OIDC is AVAILABLE (a GITHUB_ACTIONS job with ACTIONS_ID_TOKEN_REQUEST_URL + ACTIONS_ID_TOKEN_REQUEST_TOKEN set) but no chain entry held a usable ARM token: $chainText — " +
                'the azure/login step performs the OIDC exchange and must run before this probe; this probe never duplicates it') `
            -OwnerAction 'add an azure/login@v2 step (client-id / tenant-id / subscription-id of the federated credential from scripts/bootstrap/azure-oidc-setup.ps1) before this probe in the workflow job — the job already has id-token: write, so no secret is needed'
    }
    # 2c. The configured certificate's FILE is unusable and nothing else held a token
    #     (review finding): definitive — mounting or fixing the path is the repair, not
    #     an az install, another workload identity, or a retry.
    if ($spCertFileProblem -and -not $tokenHeld) {
        return New-LaneResult -Lane 'azure' -State 'needs-owner' -Source 'env-service-principal-cert' `
            -Identity 'the configured service principal (AZURE_CLIENT_ID + AZURE_TENANT_ID + AZURE_CLIENT_CERTIFICATE_PATH)' `
            -Detail ("the configured certificate credential cannot run: $spCertFileProblem ($chainText) — retrying cannot help; the certificate the platform is expected to mount is absent") `
            -OwnerAction 'fix AZURE_CLIENT_CERTIFICATE_PATH: point it at the PEM/PFX file holding the service principal certificate (and mount it into this container / host), or unset AZURE_CLIENT_CERTIFICATE_PATH so the chain falls through to a managed identity or the az cache; then re-run'
    }
    # 3b. The configured workload identity's token file is unusable and nothing else
    #     held a token (review finding): definitive — the mount / path is the repair,
    #     not a retry and not an MFA login.
    if ($wiFileProblem -and -not $tokenHeld) {
        return New-LaneResult -Lane 'azure' -State 'needs-owner' -Source 'workload-identity' `
            -Identity 'the configured workload identity (AZURE_CLIENT_ID + AZURE_TENANT_ID + AZURE_FEDERATED_TOKEN_FILE)' `
            -Detail ("the configured workload identity cannot run: $wiFileProblem ($chainText) — retrying cannot help; the token file the platform projects is missing or empty") `
            -OwnerAction 'fix AZURE_FEDERATED_TOKEN_FILE: point it at the projected service-account token file the platform mounts (AKS workload identity: /var/run/secrets/azure/tokens/azure-identity-token) and make sure the mount exists, or unset AZURE_CLIENT_ID / AZURE_TENANT_ID / AZURE_FEDERATED_TOKEN_FILE so the chain falls through to a managed identity or the az cache; then re-run'
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
    # 4b. A declared managed-identity endpoint REJECTED the request (401/403, or 400 to
    #     the identity selection): the host's identity wiring is wrong, and no retry or
    #     MFA login repairs that — the exact wiring check is the owner step (review
    #     findings). A 400 with AZURE_CLIENT_ID set names the selector as the first fix.
    if ($miAuthRejected -and -not $sawAuthRejection) {
        $miWiringAction = 'verify the managed-identity wiring the host injects — IDENTITY_ENDPOINT + IDENTITY_HEADER (App Service / Functions / Container Apps) or MSI_ENDPOINT + MSI_SECRET — by redeploying with a system- or user-assigned identity that has access, or unset the stale endpoint variables so the chain can use another credential source'
        if ($chainText -like '*HTTP 400 to the identity selection*' -and -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable('AZURE_CLIENT_ID'))) {
            $miWiringAction = 'assign the user-assigned identity named by AZURE_CLIENT_ID to this host (az vm identity assign / az webapp identity assign --identities <resource-id>), or unset AZURE_CLIENT_ID so the endpoint issues the system-assigned identity; the endpoint answered HTTP 400 to that identity selection, so retrying cannot help; then: ' + $miWiringAction
        }
        return New-LaneResult -Lane 'azure' -State 'needs-owner' -Source 'managed-identity' `
            -Detail ("the declared managed-identity endpoint rejected the token request ($chainText) — retrying cannot help; the endpoint/header pair the host injects is stale, the selected identity is not assigned, or the identity has no access$oidcHeldNote") `
            -OwnerAction $miWiringAction
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
    Write-Host '           env value with surrounding whitespace / control characters => NOT probed (the hub reads it literally) => needs-owner (re-export it exactly)'
    Write-Host '           no candidate at all => unavailable (Invoke-WebRequest is built in — only the token can be missing)'
    Write-Host '           note: the REST probe is the ground truth — gh auth status can exit 1 for a fully REST-valid token'
    Write-Host '  azure    1. GITHUB_ACTIONS=true + non-blank ACTIONS_ID_TOKEN_REQUEST_URL + ACTIONS_ID_TOKEN_REQUEST_TOKEN => OIDC available (evidence, not a completed login) — chain continues; nothing usable => ci-delegated (azure/login must run first); an incomplete set is a note, never a source'
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
    Write-Host '           an override counts only as the canonical https origin of a known cloud host (default port, no userinfo, path, query or fragment); a rejected AZURE_RESOURCE_MANAGER_ENDPOINT still lets ARM_ENDPOINT be tried'
    Write-Host '              (with AZURE_CLIENT_CERTIFICATE_PATH instead: delegated to az login --service-principal --certificate)'
    Write-Host '           2/2b: a 400/401/403 from the token endpoint => needs-owner IMMEDIATELY (DefaultAzureCredential stops at a configured credential that fails authentication; managed identity and the az cache are never consulted); transport / 5xx / malformed responses from either selected credential => unavailable WITHOUT falling through (retry the selected credential; do not rotate on transient evidence)'
    Write-Host '           2b. AZURE_CLIENT_ID+AZURE_TENANT_ID+AZURE_FEDERATED_TOKEN_FILE => the file''s assertion posted once as a jwt-bearer client_assertion to the same token endpoint (read into memory, never echoed) — WorkloadIdentityCredential''s rung, a credential source once a non-blank assertion is read; a missing / empty file is a definitive owner step (fix the mount), never retry advice'
    Write-Host '           3. IDENTITY_ENDPOINT/MSI_ENDPOINT if set — honored only as an absolute http(s) URL on a loopback host or 169.254.169.254 AND on a documented token path (/msi/token, /metadata/identity/oauth2/token, /oauth2/token — the App Service / Container Apps / Arc / Cloud Shell / IMDS shapes); any other host or path is ignored and no identity header or secret is sent, and an IDENTITY_ENDPOINT that is rejected or yields no token still lets MSI_ENDPOINT be tried — else IMDS 169.254.169.254 (Metadata:true, hard 2s, no proxy)'
    Write-Host '              the Arc shape (40342/metadata/identity/oauth2/token) runs its documented two-step handshake: Metadata request, then Basic authorization read from the WWW-Authenticate realm file, accepted only under the agent token directories with a .key extension (contents never echoed)'
    Write-Host '              loopback shapes are bound to their documented scheme and port per path (http://127.0.0.1:41xxx|localhost:42356|localhost:46808/msi/token, http://127.0.0.1:40342/metadata/identity/oauth2/token, http://localhost:50342/oauth2/token); AZURE_CLIENT_ID (when set) selects the user-assigned identity — client_id on IMDS and the App Service shape, clientid on the legacy MSI shape; Arc / Cloud Shell serve the system-assigned identity only'
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
