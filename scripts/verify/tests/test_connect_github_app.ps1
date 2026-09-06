# Offline contract suite for scripts/bootstrap/connect-github-app.ps1.
# Functions are loaded through the AST; the entrypoint, the browser, GitHub and the
# real gh are never touched. Where a child process is needed, an inert `gh` shim on
# PATH answers, so the suite proves the STDIN and argv rules without a network.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Read-Ast($Path) {
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root $Path), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "Parse failed: $Path" }; return $ast
}
function Import-Functions($Ast) {
    foreach ($f in $Ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        Set-Item "Function:script:$($f.Name)" -Value $f.Body.GetScriptBlock()
    }
}
function Assert-True($Value, $Message) { if (-not $Value) { throw $Message }; $script:cases++ }
function ConvertFrom-Base64Url([string]$Text) {
    $s = $Text.Replace('-', '+').Replace('_', '/')
    switch ($s.Length % 4) { 2 { $s += '==' } 3 { $s += '=' } }
    return [Convert]::FromBase64String($s)
}
$script:cases = 0
$script:scriptRel = 'scripts/bootstrap/connect-github-app.ps1'
$script:apiBase = 'https://api.github.com'
$script:variableNames = @('HELIOS_APP_CLIENT_ID', 'HELIOS_APP_ID', 'HELIOS_APP_SLUG')
$script:secretName = 'HELIOS_APP_PRIVATE_KEY'
$script:jsonMode = $false
$script:transportState = 'unprobed'
$script:lanes = [System.Collections.Generic.List[object]]::new()
$script:replay = [System.Collections.Generic.List[string]]::new()
Import-Functions (Read-Ast 'scripts/bootstrap/connect-github-app.ps1')

$temp = Join-Path ([IO.Path]::GetTempPath()) ('helios-app-suite-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temp | Out-Null
$savedPath = $env:PATH
$savedGh = $env:GH_TOKEN
$savedGithub = $env:GITHUB_TOKEN
try {
    # --- Manifest shape ---------------------------------------------------------------------
    $manifest = New-AppManifest -Name 'helios-control-test' -Repository 'owner/repo' -RedirectUrl 'http://localhost:1/callback' | ConvertFrom-Json
    $expected = [ordered]@{ administration = 'write'; contents = 'write'; issues = 'write'; pull_requests = 'write'; pages = 'write'; metadata = 'read'; actions = 'write'; workflows = 'write' }
    $permissionNames = @($manifest.default_permissions.PSObject.Properties.Name)
    Assert-True ($permissionNames.Count -eq $expected.Count) 'Manifest permission count differs from the contract.'
    foreach ($entry in $expected.GetEnumerator()) {
        Assert-True ($manifest.default_permissions.($entry.Key) -eq $entry.Value) "Manifest permission $($entry.Key) is not $($entry.Value)."
    }
    Assert-True ($manifest.public -eq $false) 'Manifest must not be public.'
    Assert-True (-not $manifest.PSObject.Properties['hook_attributes']) 'Manifest must not declare a webhook.'
    Assert-True (@($manifest.default_events).Count -eq 0) 'Manifest must subscribe to no events.'
    Assert-True ($manifest.url -eq 'https://github.com/owner/repo') 'Manifest url must point at the repository.'
    Assert-True ($manifest.redirect_url -eq 'http://localhost:1/callback') 'Manifest redirect_url not carried.'
    Assert-True ($manifest.name -eq 'helios-control-test') 'Manifest name not carried.'

    # --- Nonce and form ------------------------------------------------------------------------
    $nonce = New-Nonce
    Assert-True ($nonce -match '^[0-9a-f]{32}$') 'Nonce is not 32 hex characters.'
    Assert-True ((New-Nonce) -ne $nonce) 'Nonce is not random.'
    $html = New-ManifestFormHtml -ManifestJson '{"a":"<b>&\"q\""}' -TargetUrl "https://github.com/settings/apps/new?state=$nonce"
    Assert-True ($html -match 'name="manifest"') 'Form field must be named manifest.'
    Assert-True ($html -match 'method="post"') 'Form must POST.'
    Assert-True ($html -notmatch 'value="\{"a"') 'Manifest JSON must be HTML-encoded inside the value attribute.'
    Assert-True ($html -match [regex]::Escape("state=$nonce")) 'State nonce must ride in the form action.'

    # --- JWT -----------------------------------------------------------------------------------
    $rsa = [System.Security.Cryptography.RSA]::Create(2048)
    try {
        $pem = $rsa.ExportRSAPrivateKeyPem()
        $jwt = New-AppJwt -ClientId 'Iv1.testclient' -Pem $pem -NowUnix 1800000000
        $parts = $jwt.Split('.')
        Assert-True ($parts.Count -eq 3) 'JWT must have three parts.'
        Assert-True ($jwt -notmatch '[+/=]') 'JWT parts must be base64url.'
        $header = [Text.Encoding]::UTF8.GetString((ConvertFrom-Base64Url $parts[0])) | ConvertFrom-Json
        Assert-True ($header.alg -eq 'RS256' -and $header.typ -eq 'JWT') 'JWT header must be RS256/JWT.'
        $payload = [Text.Encoding]::UTF8.GetString((ConvertFrom-Base64Url $parts[1])) | ConvertFrom-Json
        Assert-True ($payload.iss -eq 'Iv1.testclient') 'JWT iss must be the client id.'
        Assert-True ($payload.iat -eq 1799999940) 'JWT iat must be backdated 60 s.'
        Assert-True (($payload.exp - $payload.iat) -eq 600) 'JWT lifetime must be 600 s.'
        Assert-True ($payload.exp -le 1800000000 + 600) 'JWT exp must stay under the 10-minute cap.'
        $verified = $rsa.VerifyData(
            [Text.Encoding]::UTF8.GetBytes("$($parts[0]).$($parts[1])"),
            (ConvertFrom-Base64Url $parts[2]),
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
        Assert-True $verified 'JWT signature does not verify with the matching public key.'
    }
    finally { $rsa.Dispose() }

    # --- Callback state check ------------------------------------------------------------------
    $ok = Test-CallbackRequest -Query "?code=abc123&state=$nonce" -Nonce $nonce
    Assert-True ($ok.Ok -and $ok.Code -eq 'abc123') 'Matching state must be accepted.'
    $bad = Test-CallbackRequest -Query '?code=abc123&state=deadbeef' -Nonce $nonce
    Assert-True (-not $bad.Ok -and $null -eq $bad.Code) 'Mismatched state must be refused without a code.'
    $none = Test-CallbackRequest -Query "?state=$nonce" -Nonce $nonce
    Assert-True (-not $none.Ok) 'A callback without a code must be refused.'
    $empty = Test-CallbackRequest -Query '' -Nonce $nonce
    Assert-True (-not $empty.Ok) 'An empty query must be refused.'

    # Live loopback listener: a background request hits the listener while this
    # thread waits, once with the wrong state and once with the right one.
    $port = Get-FreeLoopbackPort
    Assert-True ($port -gt 0) 'No free loopback port.'
    foreach ($case in @(@{ State = 'wrong'; ExpectOk = $false }, @{ State = $nonce; ExpectOk = $true })) {
        $url = "http://localhost:$port/callback?code=live-code&state=$($case.State)"
        $job = Start-Job -ScriptBlock { param($u) Start-Sleep -Milliseconds 800; try { Invoke-WebRequest -Uri $u -UseBasicParsing -SkipHttpErrorCheck | Out-Null } catch {} } -ArgumentList $url
        try {
            $verdict = Wait-CallbackCode -Port $port -Nonce $nonce -TimeoutSeconds 20
            Assert-True ($null -ne $verdict) 'Listener timed out although a request was sent.'
            Assert-True ($verdict.Ok -eq $case.ExpectOk) "Listener verdict wrong for state '$($case.State)'."
            if ($case.ExpectOk) { Assert-True ($verdict.Code -eq 'live-code') 'Listener did not return the code.' }
        }
        finally { Wait-Job $job -Timeout 10 | Out-Null; Remove-Job $job -Force }
    }
    $timeout = Wait-CallbackCode -Port $port -Nonce $nonce -TimeoutSeconds 1
    Assert-True ($null -eq $timeout) 'Listener must return null on timeout.'

    # --- Conversion parser drops the two secrets it does not need --------------------------
    $body = '{"id":42,"slug":"helios-control-owner","client_id":"Iv1.abc","html_url":"https://github.com/apps/helios-control-owner","pem":"-----BEGIN RSA PRIVATE KEY-----\nMIIE\n-----END RSA PRIVATE KEY-----","client_secret":"cs-should-vanish","webhook_secret":"ws-should-vanish"}'
    $app = ConvertFrom-ConversionResponse -Body $body
    Assert-True ($app.Id -eq '42' -and $app.Slug -eq 'helios-control-owner' -and $app.ClientId -eq 'Iv1.abc') 'Conversion parser lost an identifier.'
    Assert-True ($app.Pem -like '-----BEGIN RSA PRIVATE KEY-----*') 'Conversion parser lost the pem.'
    $names = @($app.PSObject.Properties.Name)
    Assert-True (($names -notcontains 'ClientSecret') -and ($names -notcontains 'WebhookSecret')) 'Conversion parser must not carry the secrets.'
    Assert-True (($app | ConvertTo-Json -Compress) -notmatch 'should-vanish') 'Conversion parser output leaks a dropped secret.'
    $threw = $false
    try { ConvertFrom-ConversionResponse -Body '{"id":1,"slug":"s"}' | Out-Null } catch { $threw = $true }
    Assert-True $threw 'Conversion parser must reject a response without client_id/pem.'

    # --- Store step: the pem travels over stdin only -------------------------------------------
    $shimDir = Join-Path $temp 'bin'
    New-Item -ItemType Directory -Path $shimDir | Out-Null
    $log = Join-Path $temp 'gh.log'
    $shim = Join-Path $shimDir 'gh'
    @'
#!/usr/bin/env bash
# Inert gh: records argv and a digest of stdin, answers by subcommand.
printf 'ARGV:%s\n' "$*" >> "$GH_SHIM_LOG"
if [ "$1" = "secret" ] && [ "$2" = "set" ]; then
  printf 'STDIN_SHA256:%s\n' "$(sha256sum | cut -d' ' -f1)" >> "$GH_SHIM_LOG"
  printf 'ENV_GH_TOKEN:%s\n' "${GH_TOKEN:-<unset>}" >> "$GH_SHIM_LOG"
  exit 0
fi
if [ "$1" = "auth" ]; then exit "${GH_SHIM_AUTH_EXIT:-0}"; fi
if [ "$1" = "variable" ] && [ "$2" = "get" ]; then
  case "$3" in
    HELIOS_APP_CLIENT_ID) [ -n "$GH_SHIM_REGISTERED" ] && { echo "Iv1.shim"; exit 0; } ;;
    HELIOS_APP_ID)        [ -n "$GH_SHIM_REGISTERED" ] && { echo "42"; exit 0; } ;;
    HELIOS_APP_SLUG)      [ -n "$GH_SHIM_REGISTERED" ] && { echo "helios-control-owner"; exit 0; } ;;
  esac
  echo "variable not found" >&2; exit 1
fi
if [ "$1" = "secret" ] && [ "$2" = "list" ]; then
  if [ -n "${GH_SHIM_SECRET_LIST_EXIT:-}" ]; then echo "HTTP 403: Resource not accessible" >&2; exit 1; fi
  if [ -n "$GH_SHIM_KEY_PRESENT" ]; then echo '[{"name":"HELIOS_APP_PRIVATE_KEY"}]'; else echo '[]'; fi; exit 0
fi
# Paged listings: the path carries ?per_page=100&page=N; page 2+ is empty unless
# GH_SHIM_PAGES asks for the two-page repository shape (100 fillers, then the target).
if [ "$1" = "api" ] && [ "${2%%\?*}" = "/user/installations" ]; then
  page="${2##*page=}"; [ "$page" = "$2" ] && page=1
  if [ -n "$GH_SHIM_INSTALLED" ] && [ "$page" = "1" ]; then
    echo '{"installations":[{"id":777,"app_slug":"helios-control-owner","repository_selection":"selected","permissions":{"administration":"write","contents":"write"}}]}'
  else echo '{"installations":[]}'; fi; exit 0
fi
if [ "$1" = "api" ] && [ "${2%%\?*}" = "/user/installations/777/repositories" ]; then
  if [ -n "${GH_SHIM_REPOS_EXIT:-}" ]; then echo "HTTP 403: Resource not accessible" >&2; exit 1; fi
  page="${2##*page=}"; [ "$page" = "$2" ] && page=1
  if [ -n "$GH_SHIM_PAGES" ] && [ "$page" = "1" ]; then
    names=""; for i in $(seq 1 100); do names="${names}{\"full_name\":\"owner/filler-$i\"},"; done
    echo "{\"repositories\":[${names%,}]}"
  elif [ -n "$GH_SHIM_PAGES" ] && [ "$page" = "2" ]; then echo '{"repositories":[{"full_name":"owner/repo"}]}'
  elif [ "$page" = "1" ]; then echo '{"repositories":[{"full_name":"owner/repo"}]}'
  else echo '{"repositories":[]}'; fi; exit 0
fi
if [ "$1" = "api" ] && [ "$2" = "user" ]; then echo '{"id":195981509}'; exit 0; fi
exit 0
'@ | Set-Content -LiteralPath $shim -Encoding utf8
    & chmod +x $shim
    $env:PATH = "$shimDir$([IO.Path]::PathSeparator)$savedPath"
    $env:GH_SHIM_LOG = $log
    # A stub in the parent environment that must never reach a gh child (assigned
    # through the API so the repo's secret scanner sees no quoted credential).
    $stubValue = 'placeholder-stub-never-a-credential'
    [Environment]::SetEnvironmentVariable('GH_TOKEN', $stubValue)
    [Environment]::SetEnvironmentVariable('GITHUB_TOKEN', $stubValue)
    $fakePem = "-----BEGIN RSA PRIVATE KEY-----`nMIIEpAIBAAKCAQEA-suite-only`n-----END RSA PRIVATE KEY-----`n"
    $store = Invoke-GhWithStdin -Arguments @('secret', 'set', 'HELIOS_APP_PRIVATE_KEY', '--repo', 'owner/repo') -Value $fakePem
    Assert-True ($store.ExitCode -eq 0) 'gh shim did not accept the secret set.'
    $logText = Get-Content -LiteralPath $log -Raw
    Assert-True ($logText -match 'ARGV:secret set HELIOS_APP_PRIVATE_KEY --repo owner/repo') 'secret set argv differs.'
    Assert-True ($logText -notmatch 'suite-only') 'The pem reached argv.'
    $sha = [BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($fakePem))).Replace('-', '').ToLowerInvariant()
    Assert-True ($logText -match "STDIN_SHA256:$sha") 'The pem did not arrive intact over stdin.'
    Assert-True ($logText -match 'ENV_GH_TOKEN:<unset>') 'GH_TOKEN leaked into the gh child environment.'
    Assert-True ("$($store.StdOut)" -notmatch 'suite-only') 'The pem echoed back on stdout.'

    # --- -FromCode: the exported code is trimmed before it can burn its single use ----------
    [Environment]::SetEnvironmentVariable('GH_SHIM_PASTED_CODE', "  abc-123`r`n")
    Assert-True ((Get-ManifestCodeFromEnv -Name 'GH_SHIM_PASTED_CODE') -eq 'abc-123') 'A padded exported code must be trimmed.'
    [Environment]::SetEnvironmentVariable('GH_SHIM_PASTED_CODE', "`n")
    Assert-True ((Get-ManifestCodeFromEnv -Name 'GH_SHIM_PASTED_CODE') -eq '') 'A whitespace-only exported code must read as empty.'
    [Environment]::SetEnvironmentVariable('GH_SHIM_PASTED_CODE', $null)

    # --- Main flow with shims: transport control first, verify-only rows, exit codes --------
    $script:rateLimitAnswer = 60
    function Get-GitHubRateLimit { param([string]$Token = '') return $script:rateLimitAnswer }
    function Open-Browser { param([string]$Target) $script:browserOpened = $true; return $true }

    function Invoke-Flow([hashtable]$Splat) {
        $script:browserOpened = $false
        $output = Invoke-ConnectGitHubApp @Splat 6>&1
        $lines = @($output | ForEach-Object { "$_" })
        $json = ($lines | Where-Object { $_ -match '^\{' -or $_ -match '^\s' -or $_ -match '^\}' }) -join "`n"
        $code = [int]($lines | Select-Object -Last 1)
        $object = ($json | ConvertFrom-Json)
        return [pscustomobject]@{ Object = $object; ExitCode = $code; Text = ($lines -join "`n") }
    }
    function Get-Lane($Object, [string]$Name) { return @($Object.lanes | Where-Object { $_.name -eq $Name })[0] }

    # Injected transport: refuse before any probe, every other lane skipped.
    Remove-Item -LiteralPath $log -Force
    $script:rateLimitAnswer = 5000
    $run = Invoke-Flow @{ VerifyOnly = $true; Json = $true; Repository = 'owner/repo' }
    Assert-True ($run.ExitCode -eq 2) 'Injected transport must exit 2.'
    Assert-True ((Get-Lane $run.Object 'transport').state -eq 'needs-owner') 'Injected transport lane must need the owner.'
    Assert-True ((Get-Lane $run.Object 'transport').detail -match 'transport-injected') 'Injected transport must be named.'
    Assert-True ((Get-Lane $run.Object 'app-registered').state -eq 'skipped') 'Lanes must be skipped over an injecting transport.'
    Assert-True ($run.Object.transport -eq 'injected') 'Report transport field must say injected.'
    Assert-True (((Get-Content -LiteralPath $log -Raw) -notmatch 'ARGV:variable') -and ((Get-Content -LiteralPath $log -Raw) -notmatch 'ARGV:api')) 'A credentialed gh probe ran over an injecting transport.'
    Assert-True (-not $script:browserOpened) 'No browser may open over an injecting transport.'

    # Unanswered control (no network / timeout): nothing is proven, so the script refuses
    # the same way instead of treating the transport as clean.
    Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
    $script:rateLimitAnswer = $null
    $run = Invoke-Flow @{ VerifyOnly = $true; Json = $true; Repository = 'owner/repo' }
    Assert-True ($run.ExitCode -eq 2) 'Unprobed transport must exit 2.'
    Assert-True ((Get-Lane $run.Object 'transport').state -eq 'needs-owner') 'Unprobed transport lane must need the owner.'
    Assert-True ((Get-Lane $run.Object 'transport').detail -match '^unprobed') 'Unprobed transport must be named.'
    Assert-True ((Get-Lane $run.Object 'transport').ownerAction -match 'retry when api.github.com is reachable') 'Unprobed transport must ask for a retry.'
    Assert-True ((Get-Lane $run.Object 'app-registered').state -eq 'skipped') 'Lanes must be skipped over an unproven transport.'
    Assert-True ($run.Object.transport -eq 'unprobed') 'Report transport field must say unprobed.'
    Assert-True (((Get-Content -LiteralPath $log -Raw) -notmatch 'ARGV:variable') -and ((Get-Content -LiteralPath $log -Raw) -notmatch 'ARGV:api')) 'A credentialed gh probe ran over an unproven transport.'
    Assert-True (-not $script:browserOpened) 'No browser may open over an unproven transport.'

    # Clean transport, nothing registered: verify-only reports needs-owner and changes nothing.
    Remove-Item -LiteralPath $log -Force
    $script:rateLimitAnswer = 60
    $env:GH_SHIM_REGISTERED = ''
    $env:GH_SHIM_KEY_PRESENT = ''
    $env:GH_SHIM_INSTALLED = ''
    $run = Invoke-Flow @{ VerifyOnly = $true; Json = $true; Repository = 'owner/repo' }
    Assert-True ($run.ExitCode -eq 2) 'Unregistered verify-only must exit 2.'
    Assert-True ((Get-Lane $run.Object 'transport').state -eq 'ready') 'Clean transport lane must be ready.'
    Assert-True ((Get-Lane $run.Object 'app-registered').state -eq 'needs-owner') 'Unregistered app must need the owner.'
    Assert-True ((Get-Lane $run.Object 'app-registered').ownerAction -match 'connect-github-app.ps1') 'Owner action must name the script.'
    Assert-True ((Get-Lane $run.Object 'app-installed').state -eq 'needs-owner') 'Unregistered install lane must need the owner.'
    Assert-True ((Get-Lane $run.Object 'governance-dispatched').state -eq 'skipped') 'Dispatch lane must be skipped without -DispatchGovernance.'
    $logText = Get-Content -LiteralPath $log -Raw
    Assert-True ($logText -notmatch 'ARGV:variable set' -and $logText -notmatch 'ARGV:secret set' -and $logText -notmatch 'ARGV:workflow run') 'Verify-only mutated something.'
    Assert-True (-not $script:browserOpened) 'Verify-only must not open a browser.'
    Assert-True (@($run.Object.lanes).Count -eq 6) 'Report must carry exactly six lanes.'
    Assert-True ($run.Text -notmatch 'placeholder-stub') 'A token value reached the output.'

    # Registered + secret + installed: all ready, exit 0; dispatch skipped under verify-only.
    Remove-Item -LiteralPath $log -Force
    $env:GH_SHIM_REGISTERED = '1'
    $env:GH_SHIM_KEY_PRESENT = '1'
    $env:GH_SHIM_INSTALLED = '1'
    $run = Invoke-Flow @{ VerifyOnly = $true; Json = $true; Repository = 'owner/repo'; DispatchGovernance = $true }
    Assert-True ($run.ExitCode -eq 0) 'Fully registered verify-only must exit 0.'
    foreach ($lane in 'app-registered', 'variables-stored', 'secret-stored', 'app-installed') {
        Assert-True ((Get-Lane $run.Object $lane).state -eq 'ready') "$lane must be ready when everything is stored and installed."
    }
    Assert-True ((Get-Lane $run.Object 'app-installed').detail -match 'installation 777') 'Installation id must be reported.'
    Assert-True ((Get-Lane $run.Object 'governance-dispatched').state -eq 'skipped') 'Verify-only must not dispatch.'
    Assert-True ((Get-Content -LiteralPath $log -Raw) -notmatch 'ARGV:workflow run') 'Verify-only dispatched a workflow.'

    # Registered but the secret is missing: rotation guidance, exit 2.
    $env:GH_SHIM_KEY_PRESENT = ''
    $run = Invoke-Flow @{ VerifyOnly = $true; Json = $true; Repository = 'owner/repo' }
    Assert-True ($run.ExitCode -eq 2) 'Missing secret must exit 2.'
    Assert-True ((Get-Lane $run.Object 'secret-stored').state -eq 'needs-owner') 'Missing secret lane must need the owner.'
    Assert-True ((Get-Lane $run.Object 'secret-stored').ownerAction -match 'gh secret set HELIOS_APP_PRIVATE_KEY') 'Missing secret action must name the gh secret set command.'

    # Registered, not installed: exact install link.
    $env:GH_SHIM_KEY_PRESENT = '1'
    $env:GH_SHIM_INSTALLED = ''
    $run = Invoke-Flow @{ VerifyOnly = $true; Json = $true; Repository = 'owner/repo' }
    Assert-True ($run.ExitCode -eq 2) 'Uninstalled app must exit 2.'
    Assert-True ((Get-Lane $run.Object 'app-installed').ownerAction -match 'apps/helios-control-owner/installations/new') 'Install action must link the install page.'

    # Unreadable listings are "unproven", never "absent": a failed secrets listing must not
    # send the owner to a key rotation, and a failed repository listing must not tell them
    # the installation excludes the repository.
    $env:GH_SHIM_REGISTERED = '1'
    $env:GH_SHIM_KEY_PRESENT = '1'
    $env:GH_SHIM_INSTALLED = '1'
    $env:GH_SHIM_SECRET_LIST_EXIT = '1'
    Assert-True ($null -eq (Test-RepositorySecretPresent -Name 'HELIOS_APP_PRIVATE_KEY' -Repository 'owner/repo')) 'A failed secrets listing must read as null, not false.'
    $run = Invoke-Flow @{ VerifyOnly = $true; Json = $true; Repository = 'owner/repo' }
    Assert-True ($run.ExitCode -eq 2 -and (Get-Lane $run.Object 'secret-stored').state -eq 'needs-owner') 'An unprovable secret must need the owner.'
    Assert-True ((Get-Lane $run.Object 'secret-stored').detail -match 'cannot be proven') 'An unprovable secret must say so.'
    Assert-True ((Get-Lane $run.Object 'secret-stored').ownerAction -match 'gh secret list' -and (Get-Lane $run.Object 'secret-stored').ownerAction -notmatch 'generate a private key') 'An unprovable secret must ask for a re-run, never a rotation.'
    $env:GH_SHIM_REGISTERED = ''
    $run = Invoke-Flow @{ VerifyOnly = $true; Json = $true; Repository = 'owner/repo' }
    Assert-True ((Get-Lane $run.Object 'secret-stored').detail -match 'cannot be proven') 'The unregistered verify-only row must also say unproven when the listing failed.'
    $env:GH_SHIM_SECRET_LIST_EXIT = ''
    $env:GH_SHIM_REGISTERED = '1'
    $env:GH_SHIM_REPOS_EXIT = '1'
    Assert-True ($null -eq (Get-UserInstallationRepositories -InstallationId '777')) 'A failed repository listing must read as null, not an empty list.'
    $run = Invoke-Flow @{ VerifyOnly = $true; Json = $true; Repository = 'owner/repo' }
    Assert-True ((Get-Lane $run.Object 'app-installed').state -eq 'needs-owner' -and (Get-Lane $run.Object 'app-installed').detail -match 'could not be read') 'An unreadable repository list must be reported as unproven.'
    Assert-True ((Get-Lane $run.Object 'app-installed').detail -notmatch 'does not include' -and (Get-Lane $run.Object 'app-installed').ownerAction -match '/user/installations/777/repositories') 'An unreadable repository list must not claim the repository is excluded.'
    $env:GH_SHIM_REPOS_EXIT = ''
    $env:GH_SHIM_REGISTERED = ''
    $env:GH_SHIM_KEY_PRESENT = ''
    $env:GH_SHIM_INSTALLED = ''

    # Paging: the installation and repository listings are read page by page, so a
    # repository that only appears on the second page is still found (`--paginate`
    # concatenated one document per page, which ConvertFrom-Json rejected).
    $env:GH_SHIM_INSTALLED = '1'
    $env:GH_SHIM_PAGES = '1'
    Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
    $names = @(Get-UserInstallationRepositories -InstallationId '777')
    Assert-True ($names.Count -eq 101 -and ($names -contains 'owner/repo')) "A second-page repository must be found (got $($names.Count) names)."
    $pagingLog = Get-Content -LiteralPath $log -Raw
    Assert-True ($pagingLog -match 'per_page=100&page=1' -and $pagingLog -match 'per_page=100&page=2' -and $pagingLog -notmatch 'page=3' -and $pagingLog -notmatch '--paginate') 'Paging must stop after the short page and never use --paginate.'
    Assert-True ($null -ne (Get-UserInstallationBySlug -Slug 'helios-control-owner')) 'The installation must be found through the paged listing.'
    Assert-True ($null -eq (Get-UserInstallationBySlug -Slug 'other-app')) 'A missing slug must be null through the paged listing.'
    $env:GH_SHIM_PAGES = ''
    $env:GH_SHIM_INSTALLED = ''

    # Precondition failures keep the one-object promise.
    $env:GH_SHIM_AUTH_EXIT = '1'
    $run = Invoke-Flow @{ VerifyOnly = $true; Json = $true; Repository = 'owner/repo' }
    Assert-True ($run.ExitCode -eq 2 -and $run.Object.failedPrecondition -match 'not logged in') 'A logged-out gh must be a failed precondition.'
    # Child-process contract: run as a real process (the trailer, not the function), -Json
    # prints exactly one object on stdout and the exit code is the report's exitCode.
    $childOut = @(& ([Environment]::ProcessPath) -NoProfile -File (Join-Path $root 'scripts/bootstrap/connect-github-app.ps1') -VerifyOnly -Json -Repository 'owner/repo' 2>$null | ForEach-Object { "$_" })
    $childExit = [int]$LASTEXITCODE
    $childObject = ($childOut -join "`n") | ConvertFrom-Json
    Assert-True ($childExit -eq 2) "A child -Json run must exit with the report code (got $childExit)."
    Assert-True ($childObject.exitCode -eq 2 -and $childObject.failedPrecondition -match 'not logged in') 'A child -Json run must print the one report object on stdout.'
    Assert-True (@($childOut | Where-Object { $_ -match '^\d+$' }).Count -eq 0) 'A child -Json run must not print the exit code as a line.'
    $env:GH_SHIM_AUTH_EXIT = ''
    $run = Invoke-Flow @{ VerifyOnly = $true; Json = $true; Repository = 'not-a-repo' }
    Assert-True ($run.ExitCode -eq 2 -and $run.Object.failedPrecondition -match 'owner/name') 'A malformed repository must be a failed precondition.'

    # No model identifiers in the shipped files (the pattern is assembled so this
    # file cannot match itself).
    $forbidden = @(('claude', 'fable'), ('claude', 'opus'), ('claude', 'sonnet'), ('gpt', '5')) | ForEach-Object { $_ -join '[ -]' }
    foreach ($file in 'scripts/bootstrap/connect-github-app.ps1', 'scripts/verify/tests/test_connect_github_app.ps1') {
        $text = Get-Content -LiteralPath (Join-Path $root $file) -Raw
        Assert-True ($text -notmatch ('(?i)' + ($forbidden -join '|'))) "$file carries a model identifier."
    }
}
finally {
    $env:PATH = $savedPath
    $env:GH_TOKEN = $savedGh
    $env:GITHUB_TOKEN = $savedGithub
    foreach ($name in 'GH_SHIM_LOG', 'GH_SHIM_REGISTERED', 'GH_SHIM_KEY_PRESENT', 'GH_SHIM_INSTALLED', 'GH_SHIM_AUTH_EXIT', 'GH_SHIM_PAGES', 'GH_SHIM_PASTED_CODE', 'GH_SHIM_SECRET_LIST_EXIT', 'GH_SHIM_REPOS_EXIT') { [Environment]::SetEnvironmentVariable($name, $null) }
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "Passed $($script:cases) offline connect-github-app cases."
# The suite's own status is the verdict: the child processes above exit 2 on purpose
# and would otherwise leave $LASTEXITCODE = 2 for a CI step's trailing exit check.
exit 0
