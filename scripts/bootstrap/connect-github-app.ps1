#Requires -Version 7
<#
.SYNOPSIS
Registers the HELIOS GitHub App through GitHub's manifest flow and stores its identity
in the repository, so every admin write the control fabric makes runs on a per-run
installation token instead of a personal access token.

.DESCRIPTION
Why an App and not the PAT: a fine-grained PAT is a human's credential - it expires,
it lives in a password manager, and a push or merge made with it does not fire the
next workflow. A GitHub App is a repository-scoped identity of its own: the workflow
mints an installation token at run time (actions/create-github-app-token@v3 in
.github/workflows/governance-run.yml), the token dies within the hour, nothing is
ever pasted, and pushes made with it raise `on: push` like any collaborator's. The
PAT path (scripts/bootstrap/connect-admin.ps1) stays as the manual fallback.

Why the manifest flow: it is the only way to create an App without the owner filling
in a form by hand. This script builds the manifest (name, permissions, no webhook,
not public), submits it from a self-submitting HTML page in the owner's browser, and
receives GitHub's one-hour, single-use `code` on a loopback listener. The owner makes
exactly two clicks: "Create GitHub App" and "Install".

What is stored, and where:
  repository VARIABLES (identifiers, readable by anyone with repo access):
    HELIOS_APP_CLIENT_ID   the App's client id (the `client-id` input of the action)
    HELIOS_APP_ID          the numeric App id
    HELIOS_APP_SLUG        the App's URL slug (https://github.com/apps/<slug>)
  repository SECRET (over STDIN to `gh secret set`, never argv, never a file):
    HELIOS_APP_PRIVATE_KEY the PEM GitHub returns once from the conversion call
  The conversion response also carries client_secret and webhook_secret. Neither is
  needed (no OAuth, no webhook) and neither is kept: the variables are cleared as soon
  as the response is parsed. They remain on the App's settings page where the owner
  can delete them.

Verify-first: gh must be logged in as the repository owner; then the anonymous
/rate_limit control from connect-github.ps1 runs BEFORE any credentialed probe. An
answer above the 60/hour anonymous cap proves an injecting transport (the agent
container: every GitHub Authorization header is rewritten to the proxy's own
restricted token), and there a manifest conversion, a JWT probe or a `gh secret set`
would all be meaningless or refused - the lane reports it and the script stops with
exit 2. Run it from your own machine, Cloud Shell or a Codespace.

Report lanes (one row each, one object under -Json): transport, app-registered,
variables-stored, secret-stored, app-installed, governance-dispatched.

.PARAMETER VerifyOnly
Report every lane and change nothing: no browser, no listener, no variables, no
secret, no dispatch.

.PARAMETER Json
Emit exactly one JSON object on stdout (report rows, owner actions, replay list,
exit code) and nothing else.

.PARAMETER Repository
Target repository as owner/name. Defaults to Yolkster64/helios-platform.

.PARAMETER AppName
Display name of the App. Defaults to helios-control-<owner>. GitHub App names are
global; the owner can change it on the creation page.

.PARAMETER CallbackPort
0 (default) picks a free loopback port for the one-request listener that receives
the manifest code. -1 disables the listener: the redirect lands on
https://github.com/settings/apps and the owner pastes the ?code= value from the
address bar into a masked prompt. Any other value binds that port.

.PARAMETER TimeoutMinutes
How long to wait for the browser callback and, later, for the installation to appear.

.PARAMETER SkipInstallWait
Open the install page but do not poll for the installation; re-run later to verify.

.PARAMETER DispatchGovernance
After the installation is verified: gh workflow run governance-apply.yml -f apply=true
-f scope=all, so rulesets, settings, labels and milestones reconcile immediately.

.PARAMETER FromCode
NAME of an environment variable holding a manifest code obtained elsewhere (for
example pasted from a -CallbackPort -1 run that could not finish). The value is
never printed.

.EXAMPLE
pwsh scripts/bootstrap/connect-github-app.ps1
pwsh scripts/bootstrap/connect-github-app.ps1 -VerifyOnly -Json
pwsh scripts/bootstrap/connect-github-app.ps1 -DispatchGovernance
#>
[CmdletBinding()]
param(
    [switch]$VerifyOnly,
    [switch]$Json,
    [string]$Repository = 'Yolkster64/helios-platform',
    [string]$AppName = '',
    [int]$CallbackPort = 0,
    [int]$TimeoutMinutes = 15,
    [switch]$SkipInstallWait,
    [switch]$DispatchGovernance,
    [string]$FromCode = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Constants ------------------------------------------------------------------------
$script:scriptRel = 'scripts/bootstrap/connect-github-app.ps1'
$script:apiBase = 'https://api.github.com'
$script:variableNames = @('HELIOS_APP_CLIENT_ID', 'HELIOS_APP_ID', 'HELIOS_APP_SLUG')
$script:secretName = 'HELIOS_APP_PRIVATE_KEY'
$script:jsonMode = $false
$script:transportState = 'unprobed'
$script:lanes = [System.Collections.Generic.List[object]]::new()
$script:replay = [System.Collections.Generic.List[string]]::new()

# The permission set is the whole point of the App: exactly what governance-run.yml
# and branch-prune.yml need for admin writes, plus actions/workflows so a workflow
# dispatched or a workflow file pushed by the App is accepted. Nothing account-wide.
function Get-AppPermissionSet {
    return [ordered]@{
        administration = 'write'
        contents       = 'write'
        issues         = 'write'
        pull_requests  = 'write'
        pages          = 'write'
        metadata       = 'read'
        actions        = 'write'
        workflows      = 'write'
    }
}

function Get-ApiHeaders {
    return @{ Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }
}

# --- Report idioms (connect-admin.ps1 / provision-github-secrets.ps1) ------------------
function Write-Report {
    param([string]$Message = '')
    if (-not $script:jsonMode) { Write-Host $Message }
}

function Get-OptionalProperty {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object -or $Object -isnot [System.Management.Automation.PSObject]) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -ne $prop -and $null -ne $prop.Value) { return $prop.Value }
    return $Default
}

function Test-EnvValue {
    param([Parameter(Mandatory)][string]$Name)
    -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($Name))
}

# Application only: a function or alias shadowing `gh` would pass a bare Get-Command
# and then fail as an OS subprocess.
function Get-CliCommand {
    param([Parameter(Mandatory)][string]$Name)
    Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
}

function Add-Lane {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('ready', 'needs-owner', 'failed', 'skipped')][string]$State,
        [Parameter(Mandatory)][string]$Detail,
        [string]$OwnerAction = ''
    )
    $script:lanes.Add([ordered]@{ name = $Name; state = $State; detail = $Detail; ownerAction = $OwnerAction })
}

function Add-Replay {
    param([Parameter(Mandatory)][string]$Command)
    $script:replay.Add($Command)
}

function New-ReportObject {
    param([int]$ExitCode, [string]$Repository, [string]$Mode, [string]$FailedPrecondition = '', [string[]]$Fix = @())
    $object = [ordered]@{
        script       = $script:scriptRel
        generatedUtc = (Get-Date).ToUniversalTime().ToString('o')
        mode         = $Mode
        repository   = $Repository
        transport    = $script:transportState
    }
    if ($FailedPrecondition) {
        $object['failedPrecondition'] = $FailedPrecondition
        $object['fix'] = @($Fix)
    }
    $object['lanes'] = @($script:lanes)
    $object['replay'] = @($script:replay)
    $object['exitCode'] = $ExitCode
    return $object
}

# A failed precondition still honors the -Json one-object promise (exit code 2 travels
# inside the object), so a piped consumer never parses empty input.
function Write-Precondition {
    param([Parameter(Mandatory)][string]$Message, [string[]]$Fix = @(), [string]$Repository = '', [string]$Mode = '')
    if ($script:jsonMode) {
        New-ReportObject -ExitCode 2 -Repository $Repository -Mode $Mode -FailedPrecondition $Message -Fix $Fix | ConvertTo-Json -Depth 5
        return 2
    }
    Write-Report "connect-github-app: FAILED PRECONDITION - $Message"
    foreach ($line in $Fix) { Write-Report "  $line" }
    Write-Report 'Nothing was changed.'
    return 2
}

function Write-Summary {
    param([string]$Repository, [string]$Mode)
    $failedCount = @($script:lanes | Where-Object { $_.state -eq 'failed' }).Count
    $ownerCount = @($script:lanes | Where-Object { $_.state -eq 'needs-owner' }).Count
    $exitCode = if ($failedCount -gt 0 -or $script:replay.Count -gt 0) { 1 } elseif ($ownerCount -gt 0) { 2 } else { 0 }
    if ($script:jsonMode) {
        New-ReportObject -ExitCode $exitCode -Repository $Repository -Mode $Mode | ConvertTo-Json -Depth 5
        return $exitCode
    }
    Write-Report ''
    Write-Report '== Summary =='
    $rows = $script:lanes | ForEach-Object {
        [pscustomobject]@{ Lane = $_.name; State = $_.state; Next = $(if ($_.ownerAction) { $_.ownerAction } else { '-' }) }
    }
    $table = $rows | Format-Table -AutoSize -Property Lane, State, Next | Out-String -Width 4096
    Write-Report $table.TrimEnd()
    Write-Report ''
    if ($script:replay.Count -gt 0) {
        Write-Report "connect-github-app: $($script:replay.Count) item(s) FAILED - replay list:"
        foreach ($r in $script:replay) { Write-Report "  $r" }
    }
    elseif ($ownerCount -gt 0) {
        Write-Report "connect-github-app: $ownerCount lane(s) need the owner - the Next column names the step."
    }
    else {
        Write-Report "connect-github-app: every lane is ready ($Mode)."
    }
    return $exitCode
}

# --- Child processes --------------------------------------------------------------------
# gh runs with GH_TOKEN / GITHUB_TOKEN removed from ITS environment: a stub token in
# the parent (agent containers export one) would otherwise pre-empt the owner's
# keyring login and every probe would answer for the wrong identity. -StdIn carries
# the one value that must reach a child (the PEM to `gh secret set`); it is never an
# argument.
function Invoke-Captured {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [AllowNull()][AllowEmptyString()][string]$StdIn = $null
    )
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FilePath
    foreach ($a in $Arguments) { $psi.ArgumentList.Add($a) }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    foreach ($name in 'GH_TOKEN', 'GITHUB_TOKEN') { $null = $psi.Environment.Remove($name) }
    $proc = [System.Diagnostics.Process]::Start($psi)
    try {
        # stderr is drained asynchronously so a chatty child can never deadlock on a
        # full pipe while this process waits on stdout.
        $stderrTask = $proc.StandardError.ReadToEndAsync()
        if ($null -ne $StdIn) { $proc.StandardInput.Write($StdIn) }
        $proc.StandardInput.Close()
        $stdout = $proc.StandardOutput.ReadToEnd()
        $proc.WaitForExit()
        return [pscustomobject]@{ ExitCode = $proc.ExitCode; StdOut = $stdout; StdErr = $stderrTask.Result }
    }
    finally { $proc.Dispose() }
}

function Invoke-Gh {
    param([Parameter(Mandatory)][string[]]$Arguments, [AllowNull()][AllowEmptyString()][string]$StdIn = $null)
    $gh = Get-CliCommand -Name 'gh'
    if (-not $gh) { throw 'gh is not installed' }
    return Invoke-Captured -FilePath $gh.Source -Arguments $Arguments -StdIn $StdIn
}

# The stdin feed for `gh secret set` (provision-github-secrets.ps1 shape): the value
# goes down the pipe and nowhere else.
function Invoke-GhWithStdin {
    param([Parameter(Mandatory)][string[]]$Arguments, [Parameter(Mandatory)][string]$Value)
    return Invoke-Gh -Arguments $Arguments -StdIn $Value
}

function Get-FirstLine {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    $line = (@(("$Text" -split "`n") | Where-Object { $_.Trim() }) | Select-Object -First 1)
    $line = if ($line) { "$line".Trim() } else { '' }
    if ($line.Length -gt 160) { $line = $line.Substring(0, 160) + '...' }
    return $line
}

# --- Wire-truth probes (verbatim from scripts/bootstrap/connect-github.ps1) -------------
function Get-GitHubRateLimit {
    param([AllowNull()][AllowEmptyString()][string]$Token = '')
    $headers = Get-ApiHeaders
    if ($Token) { $headers['Authorization'] = "Bearer $Token" }
    try {
        $response = Invoke-WebRequest -Uri "$($script:apiBase)/rate_limit" -Headers $headers -TimeoutSec 20 -SkipHttpErrorCheck -UseBasicParsing
        $body = $response.Content | ConvertFrom-Json
        $rate = if ($body.PSObject.Properties['rate']) { $body.rate } else { $null }
        if ($rate -and $rate.PSObject.Properties['limit']) { return [int]$rate.limit }
    }
    catch { Write-Verbose "rate_limit probe failed: $($_.Exception.Message)" }
    return $null
}

# $true = an injecting transport is PROVEN (anonymous answer above the 60/hr cap).
function Test-TransportInjected {
    $anon = Get-GitHubRateLimit
    $script:transportState = if ($null -eq $anon) { 'unprobed' } elseif ($anon -gt 60) { 'injected' } else { 'clean' }
    return ($null -ne $anon -and $anon -gt 60)
}

# gh auth status exit code only (raw output never echoed). --active restricts the
# check to the active account; older gh builds lack the flag, hence the fallback.
function Test-GhLoggedIn {
    $result = Invoke-Gh -Arguments @('auth', 'status', '--hostname', 'github.com', '--active')
    if ($result.ExitCode -ne 0 -and (("$($result.StdOut)`n$($result.StdErr)") -match 'unknown flag')) {
        $result = Invoke-Gh -Arguments @('auth', 'status', '--hostname', 'github.com')
    }
    return ($result.ExitCode -eq 0)
}

function Get-GhJson {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $result = Invoke-Gh -Arguments $Arguments
    if ($result.ExitCode -ne 0) { return $null }
    try { return ($result.StdOut | ConvertFrom-Json) } catch { return $null }
}

# --- Manifest -----------------------------------------------------------------------------
function New-Nonce {
    $bytes = [byte[]]::new(16)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    return ([BitConverter]::ToString($bytes) -replace '-', '').ToLowerInvariant()
}

# No hook_attributes: the App receives no webhooks, so there is no endpoint to protect.
# Not public: nobody else can install it. default_events empty for the same reason.
function New-AppManifest {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$RedirectUrl
    )
    $manifest = [ordered]@{
        name                = $Name
        url                 = "https://github.com/$Repository"
        description         = "HELIOS governance automation identity for $Repository (rulesets, settings, labels, milestones, branch prune) - installation tokens only, no webhook."
        public              = $false
        default_events      = @()
        default_permissions = (Get-AppPermissionSet)
        redirect_url        = $RedirectUrl
    }
    return ($manifest | ConvertTo-Json -Depth 5)
}

# GitHub only accepts the manifest as a browser form POST (field `manifest`), so the
# page below submits itself the moment it loads; the <noscript> button is the
# fallback. The state nonce rides in the action URL and comes back on the redirect.
function New-ManifestFormHtml {
    param([Parameter(Mandatory)][string]$ManifestJson, [Parameter(Mandatory)][string]$TargetUrl)
    $encoded = [System.Net.WebUtility]::HtmlEncode($ManifestJson)
    $target = [System.Net.WebUtility]::HtmlEncode($TargetUrl)
    return @"
<!doctype html>
<html><head><meta charset="utf-8"><title>HELIOS GitHub App registration</title></head>
<body onload="document.forms[0].submit()">
<p>Submitting the HELIOS GitHub App manifest to GitHub. On the page that opens, review the permissions and click <strong>Create GitHub App</strong>.</p>
<form method="post" action="$target">
<input type="hidden" name="manifest" value="$encoded">
<noscript><button type="submit">Create the HELIOS GitHub App</button></noscript>
</form>
</body></html>
"@
}

function Get-FreeLoopbackPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try { return [int]$listener.LocalEndpoint.Port }
    finally { $listener.Stop() }
}

# The callback carries ?code=<one-hour single-use code>&state=<nonce>. A request whose
# state does not match the nonce this run generated is somebody else's redirect (CSRF)
# and is refused before the code is even read.
function Test-CallbackRequest {
    param([AllowNull()][AllowEmptyString()][string]$Query, [Parameter(Mandatory)][string]$Nonce)
    $parsed = [System.Web.HttpUtility]::ParseQueryString("$Query")
    $state = $parsed['state']
    $code = $parsed['code']
    if ([string]::IsNullOrEmpty($state) -or -not [string]::Equals($state, $Nonce, [StringComparison]::Ordinal)) {
        return [pscustomobject]@{ Ok = $false; Code = $null; Reason = 'state mismatch - the callback did not come from this run' }
    }
    if ([string]::IsNullOrWhiteSpace($code)) {
        return [pscustomobject]@{ Ok = $false; Code = $null; Reason = 'callback carried no code' }
    }
    return [pscustomobject]@{ Ok = $true; Code = $code; Reason = '' }
}

# One request on the loopback interface only (localhost prefix: HttpListener needs no
# URL reservation for it on Windows and binds 127.0.0.1 elsewhere), then the listener
# closes. Returns the Test-CallbackRequest verdict, or $null on timeout.
function Wait-CallbackCode {
    param([Parameter(Mandatory)][int]$Port, [Parameter(Mandatory)][string]$Nonce, [int]$TimeoutSeconds = 900)
    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add("http://localhost:$Port/")
    $listener.Start()
    try {
        $task = $listener.GetContextAsync()
        if (-not $task.Wait([Math]::Max(1, $TimeoutSeconds) * 1000)) { return $null }
        $context = $task.Result
        $verdict = Test-CallbackRequest -Query $context.Request.Url.Query -Nonce $Nonce
        $text = if ($verdict.Ok) { 'HELIOS: registration code received. You can close this tab and return to the terminal.' } else { "HELIOS: callback refused ($($verdict.Reason))." }
        $bytes = [Text.Encoding]::UTF8.GetBytes($text)
        $context.Response.StatusCode = if ($verdict.Ok) { 200 } else { 400 }
        $context.Response.ContentType = 'text/plain; charset=utf-8'
        $context.Response.ContentLength64 = $bytes.Length
        $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $context.Response.OutputStream.Close()
        return $verdict
    }
    finally {
        $listener.Stop()
        $listener.Close()
    }
}

function Open-Browser {
    param([Parameter(Mandatory)][string]$Target)
    try {
        if ($IsWindows) { Start-Process $Target | Out-Null; return $true }
        if ($IsMacOS) { Start-Process 'open' -ArgumentList $Target | Out-Null; return $true }
        $xdg = Get-CliCommand -Name 'xdg-open'
        if ($xdg) { Start-Process $xdg.Source -ArgumentList $Target | Out-Null; return $true }
    }
    catch { Write-Verbose "browser launch failed: $($_.Exception.Message)" }
    return $false
}

# --- Conversion -----------------------------------------------------------------------------
# Keeps id / slug / client_id / html_url / pem. client_secret and webhook_secret are
# dropped here, on purpose, before anything else can see them.
function ConvertFrom-ConversionResponse {
    param([Parameter(Mandatory)]$Body)
    $object = if ($Body -is [string]) { $Body | ConvertFrom-Json } else { $Body }
    foreach ($required in 'id', 'slug', 'client_id', 'pem') {
        if ([string]::IsNullOrWhiteSpace([string](Get-OptionalProperty $object $required ''))) {
            throw "conversion response lacks '$required'"
        }
    }
    return [pscustomobject]@{
        Id       = [string](Get-OptionalProperty $object 'id' '')
        Slug     = [string](Get-OptionalProperty $object 'slug' '')
        ClientId = [string](Get-OptionalProperty $object 'client_id' '')
        HtmlUrl  = [string](Get-OptionalProperty $object 'html_url' '')
        Pem      = [string](Get-OptionalProperty $object 'pem' '')
    }
}

# POST /app-manifests/{code}/conversions needs no Authorization. Exceptions are
# rewritten because the runtime's own message can embed the request URL, and the URL
# carries the code.
function Invoke-ManifestConversion {
    param([Parameter(Mandatory)][string]$Code)
    $uri = "$($script:apiBase)/app-manifests/$([uri]::EscapeDataString($Code))/conversions"
    try {
        $response = Invoke-WebRequest -Method Post -Uri $uri -Headers (Get-ApiHeaders) -TimeoutSec 30 -MaximumRedirection 0 -SkipHttpErrorCheck -UseBasicParsing
    }
    catch {
        throw [System.InvalidOperationException]::new('manifest conversion: no response from api.github.com (transport error or redirect); the code is single-use, re-run to mint a new one')
    }
    if ([int]$response.StatusCode -ne 201) {
        throw [System.InvalidOperationException]::new("manifest conversion: HTTP $([int]$response.StatusCode) (a used or expired code answers 404; re-run to mint a new one)")
    }
    return ConvertFrom-ConversionResponse -Body $response.Content
}

# --- App JWT --------------------------------------------------------------------------------
function ConvertTo-Base64Url {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

# iat backdated 60 s (clock skew), exp 9 minutes out (GitHub caps at 10), iss = the
# client id. The PEM is imported into an RSA object that is disposed right after.
function New-AppJwt {
    param(
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$Pem,
        [long]$NowUnix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    )
    $header = ConvertTo-Base64Url -Bytes ([Text.Encoding]::UTF8.GetBytes('{"alg":"RS256","typ":"JWT"}'))
    $claims = [ordered]@{ iat = $NowUnix - 60; exp = $NowUnix + 540; iss = $ClientId }
    $payload = ConvertTo-Base64Url -Bytes ([Text.Encoding]::UTF8.GetBytes(($claims | ConvertTo-Json -Compress)))
    $rsa = [System.Security.Cryptography.RSA]::Create()
    try {
        $rsa.ImportFromPem($Pem.ToCharArray())
        $signature = $rsa.SignData(
            [Text.Encoding]::UTF8.GetBytes("$header.$payload"),
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    }
    finally { $rsa.Dispose() }
    return "$header.$payload.$(ConvertTo-Base64Url -Bytes $signature)"
}

# GET /app/installations as the App itself. Returns the installation on the owner's
# account (or $null). The JWT is a Bearer header for this one call.
function Get-AppInstallationForOwner {
    param([Parameter(Mandatory)][string]$Jwt, [Parameter(Mandatory)][string]$Owner)
    $headers = Get-ApiHeaders
    $headers['Authorization'] = "Bearer $Jwt"
    try {
        $response = Invoke-WebRequest -Uri "$($script:apiBase)/app/installations" -Headers $headers -TimeoutSec 30 -MaximumRedirection 0 -SkipHttpErrorCheck -UseBasicParsing
    }
    catch { return $null }
    if ([int]$response.StatusCode -ne 200) { return $null }
    $installations = @($response.Content | ConvertFrom-Json)
    foreach ($installation in $installations) {
        $account = Get-OptionalProperty $installation 'account' $null
        if ($account -and [string]::Equals([string](Get-OptionalProperty $account 'login' ''), $Owner, [StringComparison]::OrdinalIgnoreCase)) {
            return $installation
        }
    }
    return $null
}

# Repositories an installation can reach, through the OWNER's login (not the App):
# /user/installations/{id}/repositories lists what the owner granted, which is the
# question being asked.
function Get-UserInstallationRepositories {
    param([Parameter(Mandatory)][string]$InstallationId)
    $body = Get-GhJson -Arguments @('api', "/user/installations/$InstallationId/repositories", '--paginate')
    if ($null -eq $body) { return @() }
    $repositories = Get-OptionalProperty $body 'repositories' @()
    return @($repositories | ForEach-Object { [string](Get-OptionalProperty $_ 'full_name' '') } | Where-Object { $_ })
}

# The owner's view of the App: /user/installations lists the Apps installed on the
# accounts the login can see, each with its app_slug.
function Get-UserInstallationBySlug {
    param([Parameter(Mandatory)][string]$Slug)
    $body = Get-GhJson -Arguments @('api', '/user/installations', '--paginate')
    if ($null -eq $body) { return $null }
    foreach ($installation in @(Get-OptionalProperty $body 'installations' @())) {
        if ([string]::Equals([string](Get-OptionalProperty $installation 'app_slug' ''), $Slug, [StringComparison]::Ordinal)) { return $installation }
    }
    return $null
}

function Get-RepositoryVariable {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Repository)
    $result = Invoke-Gh -Arguments @('variable', 'get', $Name, '--repo', $Repository)
    if ($result.ExitCode -ne 0) { return $null }
    $value = "$($result.StdOut)".Trim()
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }
    return $value
}

function Test-RepositorySecretPresent {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Repository)
    $names = Get-GhJson -Arguments @('secret', 'list', '--repo', $Repository, '--json', 'name')
    if ($null -eq $names) { return $false }
    return (@($names | ForEach-Object { [string](Get-OptionalProperty $_ 'name' '') }) -contains $Name)
}

function Get-InstallationAdminState {
    param([Parameter(Mandatory)]$Installation)
    $permissions = Get-OptionalProperty $Installation 'permissions' $null
    $admin = [string](Get-OptionalProperty $permissions 'administration' '')
    return $admin
}

# --- Main flow --------------------------------------------------------------------------------
function Invoke-ConnectGitHubApp {
    param(
        [switch]$VerifyOnly,
        [switch]$Json,
        [string]$Repository = 'Yolkster64/helios-platform',
        [string]$AppName = '',
        [int]$CallbackPort = 0,
        [int]$TimeoutMinutes = 15,
        [switch]$SkipInstallWait,
        [switch]$DispatchGovernance,
        [string]$FromCode = ''
    )
    $script:jsonMode = [bool]$Json
    $script:transportState = 'unprobed'
    $script:lanes = [System.Collections.Generic.List[object]]::new()
    $script:replay = [System.Collections.Generic.List[string]]::new()
    $mode = if ($VerifyOnly) { 'verify-only' } else { 'apply' }

    if ($Repository -notmatch '^[^/\s]+/[^/\s]+$') {
        return (Write-Precondition -Message "-Repository must be owner/name (got '$Repository')" -Repository $Repository -Mode $mode)
    }
    $owner = $Repository.Split('/')[0]
    if ([string]::IsNullOrWhiteSpace($AppName)) { $AppName = "helios-control-$($owner.ToLowerInvariant())" }
    if ($TimeoutMinutes -lt 1) { $TimeoutMinutes = 1 }
    $ownerMachineHint = "run from your own machine, Cloud Shell or a Codespace: pwsh $($script:scriptRel)$(if ($DispatchGovernance) { ' -DispatchGovernance' })"

    Write-Report "connect-github-app: mode=$mode repository=$Repository app=$AppName"

    if (-not (Get-CliCommand -Name 'gh')) {
        return (Write-Precondition -Message 'gh (GitHub CLI) is not installed' -Fix @('install: https://cli.github.com', "then: gh auth login --hostname github.com --web --scopes 'repo,workflow,read:org'") -Repository $Repository -Mode $mode)
    }
    if (-not (Test-GhLoggedIn)) {
        return (Write-Precondition -Message 'gh is not logged in to github.com' -Fix @("gh auth login --hostname github.com --git-protocol https --web --scopes 'repo,workflow,read:org'   # or: pwsh scripts/bootstrap/connect-devices.ps1") -Repository $Repository -Mode $mode)
    }

    # Transport control first: over an injecting proxy every credentialed answer below
    # would describe the proxy's identity, not the owner's.
    if (Test-TransportInjected) {
        Add-Lane -Name 'transport' -State 'needs-owner' -Detail 'transport-injected: anonymous /rate_limit answers above the 60/hr cap, so GitHub credentials are rewritten in transit here' -OwnerAction $ownerMachineHint
        foreach ($lane in 'app-registered', 'variables-stored', 'secret-stored', 'app-installed', 'governance-dispatched') {
            Add-Lane -Name $lane -State 'skipped' -Detail 'not probed over an injecting transport'
        }
        return (Write-Summary -Repository $Repository -Mode $mode)
    }
    Add-Lane -Name 'transport' -State 'ready' -Detail "anonymous /rate_limit at the anonymous cap ($($script:transportState))"

    # --- Existing registration (verify-first) ---
    $stored = [ordered]@{}
    foreach ($name in $script:variableNames) { $stored[$name] = Get-RepositoryVariable -Name $name -Repository $Repository }
    $secretPresent = Test-RepositorySecretPresent -Name $script:secretName -Repository $Repository
    $missingVariables = @($script:variableNames | Where-Object { -not $stored[$_] })
    $registered = ($missingVariables.Count -eq 0)
    $slug = if ($stored['HELIOS_APP_SLUG']) { [string]$stored['HELIOS_APP_SLUG'] } else { '' }
    $clientId = if ($stored['HELIOS_APP_CLIENT_ID']) { [string]$stored['HELIOS_APP_CLIENT_ID'] } else { '' }
    $pem = ''

    if ($registered) {
        Add-Lane -Name 'app-registered' -State 'ready' -Detail "repository variables name the App: slug=$slug client_id=$clientId id=$($stored['HELIOS_APP_ID'])"
        Add-Lane -Name 'variables-stored' -State 'ready' -Detail ($script:variableNames -join ', ')
        if ($secretPresent) {
            Add-Lane -Name 'secret-stored' -State 'ready' -Detail "$($script:secretName) is present (name only)"
        }
        else {
            Add-Lane -Name 'secret-stored' -State 'needs-owner' -Detail "$($script:secretName) is absent although the variables exist" -OwnerAction "on https://github.com/settings/apps/$slug generate a private key, then from a shell: gh secret set $($script:secretName) --repo $Repository < <downloaded>.pem ; delete the file"
        }
    }
    elseif ($VerifyOnly) {
        Add-Lane -Name 'app-registered' -State 'needs-owner' -Detail "not registered: missing $($missingVariables -join ', ')" -OwnerAction "pwsh $($script:scriptRel) (two browser clicks: Create GitHub App, Install)"
        Add-Lane -Name 'variables-stored' -State 'needs-owner' -Detail 'set by the registration run'
        Add-Lane -Name 'secret-stored' -State $(if ($secretPresent) { 'ready' } else { 'needs-owner' }) -Detail $(if ($secretPresent) { "$($script:secretName) is present (name only)" } else { 'set by the registration run' })
    }
    else {
        # --- Register through the manifest flow ---
        $code = $null
        if ($FromCode) {
            if (-not (Test-EnvValue -Name $FromCode)) {
                return (Write-Precondition -Message "-FromCode names $FromCode but it is unset or blank" -Fix @("export $FromCode=<the code from the ?code= redirect> and re-run within the hour") -Repository $Repository -Mode $mode)
            }
            $code = [Environment]::GetEnvironmentVariable($FromCode)
            Write-Report "  manifest code taken from `$env:$FromCode (value not shown)"
        }
        else {
            $nonce = New-Nonce
            $port = 0
            $redirectUrl = 'https://github.com/settings/apps'
            if ($CallbackPort -ge 0) {
                $port = if ($CallbackPort -eq 0) { Get-FreeLoopbackPort } else { $CallbackPort }
                $redirectUrl = "http://localhost:$port/callback"
            }
            $manifest = New-AppManifest -Name $AppName -Repository $Repository -RedirectUrl $redirectUrl
            $targetUrl = "https://github.com/settings/apps/new?state=$nonce"
            $tempDir = Join-Path ([IO.Path]::GetTempPath()) ("helios-app-manifest-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $tempDir | Out-Null
            if (-not $IsWindows) { & chmod 700 $tempDir; if ($LASTEXITCODE -ne 0) { Write-Verbose 'chmod 700 failed' } }
            $formPath = Join-Path $tempDir 'register.html'
            Set-Content -LiteralPath $formPath -Value (New-ManifestFormHtml -ManifestJson $manifest -TargetUrl $targetUrl) -Encoding utf8
            $permissionText = ((Get-AppPermissionSet).GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' '
            Write-Report ''
            Write-Report "  1. Your browser opens $targetUrl with the manifest pre-filled (the page is $formPath)."
            Write-Report '     Review the permissions, then click  Create GitHub App .'
            Write-Report "     Permissions requested: $permissionText"
            if ($port -gt 0) { Write-Report "  2. GitHub sends the registration code back to http://localhost:$port/callback (loopback only); this shell is waiting for it (up to $TimeoutMinutes min)." }
            else { Write-Report '  2. GitHub redirects to https://github.com/settings/apps?code=... - copy the code value from the address bar into the prompt below.' }
            Write-Report ''
            $opened = Open-Browser -Target $formPath
            if (-not $opened) { Write-Report "  (no browser could be launched here - open $formPath yourself)" }
            try {
                if ($port -gt 0) {
                    $verdict = Wait-CallbackCode -Port $port -Nonce $nonce -TimeoutSeconds ($TimeoutMinutes * 60)
                    if ($null -eq $verdict) {
                        Add-Lane -Name 'app-registered' -State 'failed' -Detail "no callback within $TimeoutMinutes min" -OwnerAction 're-run (or -CallbackPort -1 to paste the code)'
                        Add-Replay -Command "pwsh $($script:scriptRel)"
                    }
                    elseif (-not $verdict.Ok) {
                        Add-Lane -Name 'app-registered' -State 'failed' -Detail "callback refused: $($verdict.Reason)"
                        Add-Replay -Command "pwsh $($script:scriptRel)"
                    }
                    else { $code = $verdict.Code }
                }
                else {
                    $secure = Read-Host -Prompt '  Paste the code from the ?code= query (input hidden)' -MaskInput
                    $code = "$secure".Trim()
                    if (-not $code) {
                        Add-Lane -Name 'app-registered' -State 'failed' -Detail 'no code entered'
                        Add-Replay -Command "pwsh $($script:scriptRel) -CallbackPort -1"
                    }
                }
            }
            finally {
                Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        if ($code) {
            try {
                $app = Invoke-ManifestConversion -Code $code
                $code = $null
                $slug = $app.Slug
                $clientId = $app.ClientId
                $pem = $app.Pem
                Add-Lane -Name 'app-registered' -State 'ready' -Detail "created $($app.HtmlUrl) (slug=$slug id=$($app.Id) client_id=$clientId); client_secret and webhook_secret were discarded - delete them on that page if you like"
                $values = [ordered]@{ HELIOS_APP_CLIENT_ID = $clientId; HELIOS_APP_ID = $app.Id; HELIOS_APP_SLUG = $slug }
                $variableFailures = @()
                foreach ($entry in $values.GetEnumerator()) {
                    Write-Report "  + gh variable set $($entry.Key) --repo $Repository --body $($entry.Value)"
                    $result = Invoke-Gh -Arguments @('variable', 'set', $entry.Key, '--repo', $Repository, '--body', [string]$entry.Value)
                    if ($result.ExitCode -ne 0) {
                        $variableFailures += "$($entry.Key): $(Get-FirstLine $result.StdErr)"
                        Add-Replay -Command "gh variable set $($entry.Key) --repo $Repository --body $($entry.Value)"
                    }
                }
                if ($variableFailures.Count -eq 0) { Add-Lane -Name 'variables-stored' -State 'ready' -Detail ($values.Keys -join ', ') }
                else { Add-Lane -Name 'variables-stored' -State 'failed' -Detail ($variableFailures -join '; ') }

                Write-Report "  + gh secret set $($script:secretName) --repo $Repository   (PEM over stdin)"
                $storedSecret = Invoke-GhWithStdin -Arguments @('secret', 'set', $script:secretName, '--repo', $Repository) -Value $pem
                if ($storedSecret.ExitCode -eq 0) {
                    Add-Lane -Name 'secret-stored' -State 'ready' -Detail "$($script:secretName) stored over stdin"
                    $secretPresent = $true
                }
                else {
                    Add-Lane -Name 'secret-stored' -State 'failed' -Detail "gh secret set exited $($storedSecret.ExitCode): $(Get-FirstLine $storedSecret.StdErr)" -OwnerAction "on https://github.com/settings/apps/$slug generate a new private key and run: gh secret set $($script:secretName) --repo $Repository < <downloaded>.pem"
                    Add-Replay -Command "gh secret set $($script:secretName) --repo $Repository < <private-key>.pem"
                }
                $registered = $true
            }
            catch {
                $code = $null
                Add-Lane -Name 'app-registered' -State 'failed' -Detail $_.Exception.Message
                Add-Replay -Command "pwsh $($script:scriptRel)"
            }
        }
        if (-not $registered) {
            Add-Lane -Name 'variables-stored' -State 'skipped' -Detail 'registration did not complete'
            Add-Lane -Name 'secret-stored' -State 'skipped' -Detail 'registration did not complete'
        }
    }

    # --- Installation ---
    $installed = $false
    $installationId = ''
    if (-not $registered -or -not $slug) {
        Add-Lane -Name 'app-installed' -State $(if ($VerifyOnly) { 'needs-owner' } else { 'skipped' }) -Detail 'no registered App to install'
    }
    else {
        $installation = Get-UserInstallationBySlug -Slug $slug
        if ($null -eq $installation -and -not $VerifyOnly -and $pem) {
            $ownerId = [string](Get-OptionalProperty (Get-GhJson -Arguments @('api', 'user')) 'id' '')
            $installUrl = "https://github.com/apps/$slug/installations/new/permissions?target_id=$ownerId"
            Write-Report ''
            Write-Report "  3. Install the App on $Repository - your browser opens $installUrl ; click  Install ."
            $opened = Open-Browser -Target $installUrl
            if (-not $opened) { Write-Report "  (no browser could be launched here - open $installUrl yourself)" }
            if (-not $SkipInstallWait) {
                $deadline = [DateTime]::UtcNow.AddMinutes($TimeoutMinutes)
                $appView = $null
                while ([DateTime]::UtcNow -lt $deadline) {
                    $jwt = New-AppJwt -ClientId $clientId -Pem $pem
                    $appView = Get-AppInstallationForOwner -Jwt $jwt -Owner $owner
                    if ($null -ne $appView) { break }
                    Start-Sleep -Seconds 5
                }
                if ($null -ne $appView) { $installation = Get-UserInstallationBySlug -Slug $slug }
                if ($null -eq $installation -and $null -ne $appView) { $installation = $appView }
            }
        }
        if ($null -eq $installation) {
            Add-Lane -Name 'app-installed' -State 'needs-owner' -Detail "no installation of $slug on $owner" -OwnerAction "install it (one click): https://github.com/apps/$slug/installations/new"
        }
        else {
            $installationId = [string](Get-OptionalProperty $installation 'id' '')
            $admin = Get-InstallationAdminState -Installation $installation
            $repos = Get-UserInstallationRepositories -InstallationId $installationId
            $hasRepo = ($repos -contains $Repository)
            $selection = [string](Get-OptionalProperty $installation 'repository_selection' '')
            if ($admin -ne 'write') {
                Add-Lane -Name 'app-installed' -State 'needs-owner' -Detail "installation $installationId exists but administration=$admin" -OwnerAction "accept the pending permission update: https://github.com/settings/installations/$installationId"
            }
            elseif (-not $hasRepo -and $selection -ne 'all') {
                Add-Lane -Name 'app-installed' -State 'needs-owner' -Detail "installation $installationId does not include $Repository" -OwnerAction "add the repository: https://github.com/settings/installations/$installationId"
            }
            else {
                $installed = $true
                Add-Lane -Name 'app-installed' -State 'ready' -Detail "installation $installationId on $owner covers $Repository (administration=write)"
            }
        }
    }
    $pem = ''

    # --- Governance dispatch ---
    if (-not $DispatchGovernance) {
        Add-Lane -Name 'governance-dispatched' -State 'skipped' -Detail 'not requested (-DispatchGovernance)'
    }
    elseif ($VerifyOnly) {
        Add-Lane -Name 'governance-dispatched' -State 'skipped' -Detail 'verify-only'
    }
    elseif (-not ($installed -and $secretPresent)) {
        Add-Lane -Name 'governance-dispatched' -State 'needs-owner' -Detail 'requires app-installed and secret-stored ready' -OwnerAction "re-run with -DispatchGovernance once the App is installed, or: gh workflow run governance-apply.yml --repo $Repository -f apply=true -f scope=all"
    }
    else {
        Write-Report "  + gh workflow run governance-apply.yml --repo $Repository -f apply=true -f scope=all"
        $run = Invoke-Gh -Arguments @('workflow', 'run', 'governance-apply.yml', '--repo', $Repository, '-f', 'apply=true', '-f', 'scope=all')
        if ($run.ExitCode -eq 0) {
            Start-Sleep -Seconds 3
            $url = [string](Get-OptionalProperty (Get-GhJson -Arguments @('run', 'list', '--workflow', 'governance-apply.yml', '--repo', $Repository, '--limit', '1', '--json', 'url', '--jq', '.[0]')) 'url' '')
            Add-Lane -Name 'governance-dispatched' -State 'ready' -Detail $(if ($url) { "dispatched: $url" } else { 'dispatched (run URL not yet listed)' })
        }
        else {
            Add-Lane -Name 'governance-dispatched' -State 'failed' -Detail "gh workflow run exited $($run.ExitCode): $(Get-FirstLine $run.StdErr)"
            Add-Replay -Command "gh workflow run governance-apply.yml --repo $Repository -f apply=true -f scope=all"
        }
    }

    return (Write-Summary -Repository $Repository -Mode $mode)
}

# The offline suite imports the functions above through the AST and never reaches
# this line; a normal invocation runs the flow and exits with its code.
exit (Invoke-ConnectGitHubApp @PSBoundParameters)
