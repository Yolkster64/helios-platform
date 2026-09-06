# Offline contract suite for scripts/bootstrap/connect-devices.ps1 (and the verify-only
# path of its bash twin). Functions are loaded through the AST; inert `gh` and `az`
# shims on PATH stand in for the real CLIs, so no browser, no GitHub and no Entra
# are ever touched. Every shim invocation is logged, which is how the suite proves
# that -VerifyOnly launches no login and that ready lanes are never asked for a code.
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
$script:cases = 0
$script:scriptRel = 'scripts/bootstrap/connect-devices.ps1'
$script:jsonMode = $false
$script:lanes = [System.Collections.Generic.List[object]]::new()
$script:replay = [System.Collections.Generic.List[string]]::new()
$script:ghScopes = 'repo,workflow,project,read:org,models:read'
Import-Functions (Read-Ast 'scripts/bootstrap/connect-devices.ps1')
# Invoke-Chain resolves siblings from $PSScriptRoot; the suite never reaches it
# (-SkipChain everywhere), but the variable must exist under StrictMode.
$PSScriptRoot | Out-Null

$temp = Join-Path ([IO.Path]::GetTempPath()) ('helios-devices-suite-' + [guid]::NewGuid())
$bin = Join-Path $temp 'bin'
$state = Join-Path $temp 'state'
New-Item -ItemType Directory -Path $bin, $state | Out-Null
$log = Join-Path $temp 'shim.log'
$savedPath = $env:PATH
$savedGh = $env:GH_TOKEN
$savedGithub = $env:GITHUB_TOKEN
$tenant = '00000000-0000-0000-0000-000000000000'

# gh shim. DEV_SHIM_GH: ready | ok | expired | refused | hang | expired-then-ok.
@'
#!/usr/bin/env bash
printf 'gh %s | GH_TOKEN=%s\n' "$*" "${GH_TOKEN:-<unset>}" >> "$DEV_SHIM_LOG"
mode="${DEV_SHIM_GH:-ready}"
case "$1 $2" in
  "auth status")
    if [ "$mode" = "ready" ] || [ -f "$DEV_SHIM_STATE/gh-ok" ]; then
      if [ -n "${DEV_SHIM_GH_SCOPES:-}" ]; then echo "  - Token scopes: ${DEV_SHIM_GH_SCOPES}"; fi
      exit 0
    fi; exit 1 ;;
  "auth login")
    if [ "$mode" = "expired-then-ok" ]; then
      if [ -f "$DEV_SHIM_STATE/gh-attempt" ]; then mode=ok; else touch "$DEV_SHIM_STATE/gh-attempt"; mode=expired; fi
    fi
    echo "! First copy your one-time code: ABCD-1234" >&2
    echo "Open this URL to continue in your web browser: https://github.com/login/device" >&2
    case "$mode" in
      ok) sleep 0.3; touch "$DEV_SHIM_STATE/gh-ok"; echo "✓ Logged in as owner" >&2; exit 0 ;;
      expired) sleep 0.2; echo "error: the device code has expired" >&2; exit 1 ;;
      refused) sleep 0.2; echo "error: authentication failed" >&2; exit 1 ;;
      hang) sleep 30; exit 1 ;;
    esac ;;
  "auth token") echo "gho_shim_token_value"; exit 0 ;;
esac
exit 0
'@ | Set-Content -LiteralPath (Join-Path $bin 'gh') -Encoding utf8
# az shim. DEV_SHIM_AZ: ready | ok | expired | refused | hang.
@'
#!/usr/bin/env bash
printf 'az %s\n' "$*" >> "$DEV_SHIM_LOG"
mode="${DEV_SHIM_AZ:-ready}"
case "$1 $2" in
  "account get-access-token")
    if [ "$mode" = "ready" ] || [ -f "$DEV_SHIM_STATE/az-ok" ]; then exit 0; fi; exit 1 ;;
  "login --use-device-code")
    echo "WARNING: To sign in, use a web browser to open the page https://microsoft.com/devicelogin and enter the code ABCDEFGHI to authenticate." >&2
    case "$mode" in
      ok) sleep 0.3; touch "$DEV_SHIM_STATE/az-ok"; echo '[{"name":"main"}]'; exit 0 ;;
      expired) sleep 0.2; echo "AADSTS70020: The provided value for the device code expired." >&2; exit 1 ;;
      refused) sleep 0.2; echo "AADSTS50076: Due to a configuration change, you must use multi-factor authentication." >&2; exit 1 ;;
      hang) sleep 30; exit 1 ;;
    esac ;;
esac
exit 0
'@ | Set-Content -LiteralPath (Join-Path $bin 'az') -Encoding utf8
& chmod +x (Join-Path $bin 'gh') (Join-Path $bin 'az')

function Reset-Shims([string]$Gh, [string]$Az) {
    Get-ChildItem -LiteralPath $state | Remove-Item -Force
    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
    $env:DEV_SHIM_GH = $Gh
    $env:DEV_SHIM_AZ = $Az
}
function Get-ShimLog { if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Raw } else { '' } }
function Invoke-Flow([hashtable]$Splat) {
    $lines = @(Invoke-ConnectDevices @Splat 6>&1 | ForEach-Object { "$_" })
    $code = [int]($lines | Select-Object -Last 1)
    $text = ($lines -join "`n")
    $object = $null
    if ($Splat.ContainsKey('Json') -and $Splat['Json']) {
        $json = ($lines | Where-Object { $_ -match '^\{' -or $_ -match '^\s' -or $_ -match '^\}' }) -join "`n"
        $object = $json | ConvertFrom-Json
    }
    return [pscustomobject]@{ Object = $object; ExitCode = $code; Text = $text }
}
function Get-Lane($Object, [string]$Name) { return @($Object.lanes | Where-Object { $_.name -eq $Name })[0] }

try {
    $env:PATH = "$bin$([IO.Path]::PathSeparator)$savedPath"
    $env:DEV_SHIM_LOG = $log
    $env:DEV_SHIM_STATE = $state
    # A stub in the parent environment that must never reach a gh child (assigned
    # through the API so the repo's secret scanner sees no quoted credential).
    $stubValue = 'placeholder-stub-never-a-credential'
    [Environment]::SetEnvironmentVariable('GH_TOKEN', $stubValue)
    [Environment]::SetEnvironmentVariable('GITHUB_TOKEN', $stubValue)

    # --- Pure parsing ---------------------------------------------------------------------------
    $ghSpec = Get-DeviceFlowSpec -Lane 'github'
    $azSpec = Get-DeviceFlowSpec -Lane 'azure' -Tenant $tenant
    Assert-True (($ghSpec.Arguments -join ' ') -eq "auth login --hostname github.com --git-protocol https --web --scopes $script:ghScopes") 'gh login arguments differ from the contract.'
    Assert-True (($azSpec.Arguments -join ' ') -eq "login --use-device-code --tenant $tenant") 'az login arguments differ from the contract.'
    Assert-True ((Get-DeviceCode -Pattern $ghSpec.CodePattern -Lines @('! First copy your one-time code: WXYZ-9876', 'Open this URL')) -eq 'WXYZ-9876') 'gh code not parsed.'
    Assert-True ((Get-DeviceCode -Pattern $azSpec.CodePattern -Lines @('WARNING: To sign in, use a web browser to open the page https://microsoft.com/devicelogin and enter the code Q7ZR3PLM2 to authenticate.')) -eq 'Q7ZR3PLM2') 'az code not parsed.'
    Assert-True ($null -eq (Get-DeviceCode -Pattern $ghSpec.CodePattern -Lines @('nothing here'))) 'A code was parsed from noise.'
    Assert-True ((Get-FlowVerdict -ExitCode 0 -Lines @()) -eq 'ready') 'Exit 0 must be ready.'
    Assert-True ((Get-FlowVerdict -ExitCode 1 -Lines @('error: the device code has expired')) -eq 'expired') 'Expired text must classify as expired.'
    Assert-True ((Get-FlowVerdict -ExitCode 1 -Lines @('AADSTS50076: Due to a configuration change')) -eq 'refused') 'AADSTS must classify as refused.'
    Assert-True ((Get-FlowVerdict -ExitCode 1 -Lines @('error: authentication failed')) -eq 'refused') 'authentication failed must classify as refused.'
    Assert-True ((Get-FlowVerdict -ExitCode 3 -Lines @('segfault')) -eq 'failed') 'Unknown failure must classify as failed.'
    Assert-True ((Get-FlowVerdict -ExitCode 0 -Lines @() -TimedOut) -eq 'expired') 'A timed-out flow must classify as expired.'

    # --- Flow lifecycle -------------------------------------------------------------------------
    # Register-ObjectEvent -Action hands back a PSEventJob (not a PSEventSubscriber): its Name
    # is the subscriber's SourceIdentifier and its Id the job id. Stop-DeviceFlow relies on
    # exactly that, so prove it against the shim and prove the teardown leaves nothing behind.
    Reset-Shims -Gh 'ok' -Az 'ready'
    $subscribersBefore = @(Get-EventSubscriber).Count
    $jobsBefore = @(Get-Job).Count
    $flow = Start-DeviceFlow -Spec $ghSpec
    Assert-True (@($flow.Subscriptions | Where-Object { $_ -is [System.Management.Automation.PSEventJob] }).Count -eq 2) 'Start-DeviceFlow must hold two PSEventJob subscriptions.'
    $liveIds = @(Get-EventSubscriber | ForEach-Object { $_.SourceIdentifier })
    Assert-True (@($flow.Subscriptions | Where-Object { $liveIds -contains $_.Name }).Count -eq 2) 'Each subscription Name must be a live subscriber SourceIdentifier.'
    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    do { Start-Sleep -Milliseconds 50; Update-DeviceFlow -Flow $flow } until ($flow.Code -or [DateTime]::UtcNow -gt $deadline)
    Assert-True ($flow.Code -eq 'ABCD-1234') 'The device code must arrive through the event queue.'
    Stop-DeviceFlow -Flow $flow
    Assert-True (@(Get-EventSubscriber).Count -eq $subscribersBefore) 'Stop-DeviceFlow left event subscribers behind.'
    Assert-True (@(Get-Job).Count -eq $jobsBefore) 'Stop-DeviceFlow left event jobs behind.'

    # A second flow that cannot start must not leak the first: the guard stops what is
    # already running before the error surfaces.
    Reset-Shims -Gh 'ok' -Az 'ready'
    $subscribersBefore = @(Get-EventSubscriber).Count
    $jobsBefore = @(Get-Job).Count
    $missingSpec = [pscustomobject]@{ Lane = 'missing'; Command = 'helios-no-such-cli'; Arguments = @('--never'); CodePattern = 'never'; ClearTokens = $false }
    $startFailed = $false
    try { $null = Invoke-DeviceFlows -Specs @($ghSpec, $missingSpec) -TimeoutMinutes 0.05 } catch { $startFailed = ("$_" -match 'helios-no-such-cli') }
    Assert-True ($startFailed) 'A CLI that cannot start must surface as an error naming it.'
    Assert-True (@(Get-EventSubscriber).Count -eq $subscribersBefore -and @(Get-Job).Count -eq $jobsBefore) 'A start failure must stop the flow that had already started.'

    # --- GitHub Models export: the scope is checked before anything is exported ---------------
    $savedModels = $env:GITHUB_MODELS_TOKEN
    [Environment]::SetEnvironmentVariable('GITHUB_MODELS_TOKEN', $null)
    $parsed = Get-TokenScopesFromStatus -Text "github.com`n  Logged in to github.com account owner (keyring)`n  - Active account: true`n  - Token scopes: 'gist', 'read:org', 'repo', 'models:read'"
    Assert-True ($parsed.Listed -and ($parsed.Scopes -contains 'models:read') -and $parsed.Scopes.Count -eq 4) 'A quoted scope list must parse.'
    $parsed = Get-TokenScopesFromStatus -Text "Token scopes: gist, read:org, repo"
    Assert-True ($parsed.Listed -and ($parsed.Scopes -notcontains 'models:read') -and ($parsed.Scopes -contains 'read:org')) 'A bare scope list must parse.'
    Assert-True (-not (Get-TokenScopesFromStatus -Text "Logged in to github.com account owner (GH_TOKEN)").Listed) 'No scope line must read as not listed.'
    $env:DEV_SHIM_GH_SCOPES = "'repo', 'workflow', 'read:org'"
    Reset-Shims -Gh 'ready' -Az 'ready'
    $script:lanes = [System.Collections.Generic.List[object]]::new()
    Invoke-ModelsExport -DotSourced
    $lane = @($script:lanes)[0]
    Assert-True ($lane.state -eq 'needs-owner' -and $lane.ownerAction -match 'gh auth refresh --hostname github.com --scopes models:read') 'A login without models:read must not be exported and must name gh auth refresh.'
    Assert-True ([string]::IsNullOrEmpty($env:GITHUB_MODELS_TOKEN)) 'No token may be exported without models:read.'
    Assert-True ((Get-ShimLog) -notmatch 'gh auth token') 'gh auth token must not run when the scope is missing.'
    $env:DEV_SHIM_GH_SCOPES = "'repo', 'workflow', 'read:org', 'models:read'"
    Reset-Shims -Gh 'ready' -Az 'ready'
    $script:lanes = [System.Collections.Generic.List[object]]::new()
    Invoke-ModelsExport -DotSourced
    $lane = @($script:lanes)[0]
    Assert-True ($lane.state -eq 'ready' -and $lane.detail -match 'models:read confirmed') 'A login with models:read must export with the proof named.'
    Assert-True ($env:GITHUB_MODELS_TOKEN -eq 'gho_shim_token_value') 'The gh token must be exported into this session.'
    Assert-True ($lane.detail -notmatch 'gho_shim') 'The token value must not appear in the lane detail.'
    Assert-True ((Get-ShimLog) -match 'gh auth token[^\n]*GH_TOKEN=<unset>') 'GH_TOKEN leaked into the gh auth token child.'
    [Environment]::SetEnvironmentVariable('GITHUB_MODELS_TOKEN', $null)
    $env:DEV_SHIM_GH_SCOPES = ''
    Reset-Shims -Gh 'ready' -Az 'ready'
    $script:lanes = [System.Collections.Generic.List[object]]::new()
    Invoke-ModelsExport -DotSourced
    $lane = @($script:lanes)[0]
    Assert-True ($lane.state -eq 'ready' -and $lane.detail -match 'lists no scopes') 'A token with no scope list is exported and handed to auto-login for the wire check.'
    Assert-True ($env:GITHUB_MODELS_TOKEN -eq 'gho_shim_token_value') 'The list-less token must still be exported.'
    [Environment]::SetEnvironmentVariable('GITHUB_MODELS_TOKEN', 'placeholder-already-set')
    $script:lanes = [System.Collections.Generic.List[object]]::new()
    Invoke-ModelsExport -DotSourced
    Assert-True (@($script:lanes)[0].detail -match 'already set') 'An existing GITHUB_MODELS_TOKEN is kept (name checked only).'
    [Environment]::SetEnvironmentVariable('GITHUB_MODELS_TOKEN', $savedModels)
    $script:lanes = [System.Collections.Generic.List[object]]::new()
    Invoke-ModelsExport
    Assert-True (@($script:lanes)[0].state -eq 'needs-owner' -and @($script:lanes)[0].ownerAction -match 'dot-source') 'A child run cannot export and must say so.'

    # --- Verify-only: probes only, never a login ---------------------------------------------------
    Reset-Shims -Gh 'ok' -Az 'ok'
    $run = Invoke-Flow @{ VerifyOnly = $true; Json = $true; Tenant = $tenant; Repository = 'owner/repo' }
    Assert-True ($run.ExitCode -eq 2) 'Verify-only with both lanes logged out must exit 2.'
    Assert-True ((Get-Lane $run.Object 'github-login').state -eq 'needs-owner') 'gh lane must need the owner.'
    Assert-True ((Get-Lane $run.Object 'azure-login').state -eq 'needs-owner') 'az lane must need the owner.'
    Assert-True ((Get-Lane $run.Object 'github-login').ownerAction -match 'gh auth login') 'gh owner action must name the login command.'
    Assert-True ((Get-Lane $run.Object 'chain').state -eq 'skipped') 'Chain must be skipped under verify-only.'
    $shimLog = Get-ShimLog
    Assert-True ($shimLog -match 'gh auth status') 'Verify-only must probe gh.'
    Assert-True ($shimLog -match 'az account get-access-token') 'Verify-only must probe az.'
    Assert-True ($shimLog -notmatch 'auth login' -and $shimLog -notmatch 'use-device-code') 'Verify-only launched a login.'
    Assert-True ($shimLog -match 'GH_TOKEN=<unset>') 'GH_TOKEN leaked into the gh child.'
    Assert-True ($run.Text -notmatch 'placeholder-stub') 'A token value reached the output.'

    Reset-Shims -Gh 'ready' -Az 'ready'
    $run = Invoke-Flow @{ VerifyOnly = $true; Json = $true; Tenant = $tenant; Repository = 'owner/repo' }
    Assert-True ($run.ExitCode -eq 0) 'Verify-only with both lanes ready must exit 0.'
    Assert-True ((Get-Lane $run.Object 'github-login').detail -match 'already') 'Ready gh lane must say already logged in.'

    # --- Apply: both flows together, one table, both accepted ------------------------------------
    Reset-Shims -Gh 'ok' -Az 'ok'
    $run = Invoke-Flow @{ Tenant = $tenant; Repository = 'owner/repo'; SkipChain = $true; TimeoutMinutes = 0.5 }
    Assert-True ($run.ExitCode -eq 0) "Both flows accepted must exit 0 (got $($run.ExitCode))."
    Assert-True ($run.Text -match 'GitHub -> https://github.com/login/device\s+code ABCD-1234') 'Table lacks the GitHub row.'
    Assert-True ($run.Text -match 'Azure\s+-> https://microsoft.com/devicelogin\s+code ABCDEFGHI') 'Table lacks the Azure row.'
    Assert-True ($run.Text -match 'every lane is ready \(apply\)') 'Summary must say every lane is ready.'
    $shimLog = Get-ShimLog
    Assert-True ($shimLog -match 'gh auth login --hostname github.com --git-protocol https --web --scopes') 'gh login was not launched.'
    Assert-True ($shimLog -match "az login --use-device-code --tenant $tenant") 'az login was not launched.'
    Assert-True ($shimLog -match 'gh auth login[^\n]*GH_TOKEN=<unset>') 'GH_TOKEN leaked into the gh login child.'
    Assert-True ($run.Text -notmatch 'gho_shim_token_value') 'A token value reached the output.'

    # Same scenario under -Json: the lane details carry the re-verification.
    Reset-Shims -Gh 'ok' -Az 'ok'
    $run = Invoke-Flow @{ Json = $true; Tenant = $tenant; Repository = 'owner/repo'; SkipChain = $true; TimeoutMinutes = 0.5 }
    Assert-True ($run.ExitCode -eq 0) 'JSON apply run must exit 0.'
    Assert-True ((Get-Lane $run.Object 'github-login').detail -eq 'device code accepted; gh session verified') 'gh lane not verified after the flow.'
    Assert-True ((Get-Lane $run.Object 'azure-login').detail -eq 'device code accepted; az session verified') 'az lane not verified after the flow.'
    Assert-True ((Get-Lane $run.Object 'chain').state -eq 'skipped' -and (Get-Lane $run.Object 'chain').detail -eq '-SkipChain') 'Chain must be skipped by -SkipChain.'
    Assert-True (@($run.Object.lanes).Count -eq 3) 'Apply with -SkipChain must report exactly three lanes.'
    Assert-True (@(Get-EventSubscriber).Count -eq 0 -and @(Get-Job).Count -eq 0) 'A completed apply run left event subscribers or jobs behind.'

    # --- Apply: a ready lane is never asked for a code -----------------------------------------------
    Reset-Shims -Gh 'ready' -Az 'ok'
    $run = Invoke-Flow @{ Json = $true; Tenant = $tenant; Repository = 'owner/repo'; SkipChain = $true; TimeoutMinutes = 0.5 }
    Assert-True ($run.ExitCode -eq 0) 'Ready gh + accepted az must exit 0.'
    Assert-True ((Get-Lane $run.Object 'github-login').detail -match 'already') 'Ready gh lane must be skipped.'
    $shimLog = Get-ShimLog
    Assert-True ($shimLog -notmatch 'gh auth login') 'A ready gh lane was asked for a code.'
    Assert-True ($shimLog -match 'az login --use-device-code') 'The pending az lane was not launched.'

    # --- Refused and expired verdicts, -Retry ------------------------------------------------------
    Reset-Shims -Gh 'refused' -Az 'ready'
    $run = Invoke-Flow @{ Json = $true; Tenant = $tenant; Repository = 'owner/repo'; SkipChain = $true; TimeoutMinutes = 0.5 }
    Assert-True ($run.ExitCode -eq 2) 'A refused login must exit 2.'
    Assert-True ((Get-Lane $run.Object 'github-login').detail -match '^refused') 'Refused lane must be classified refused.'
    Assert-True ((Get-Lane $run.Object 'chain').state -eq 'skipped') 'Chain must not run when a login is missing.'

    Reset-Shims -Gh 'expired' -Az 'ready'
    $run = Invoke-Flow @{ Json = $true; Tenant = $tenant; Repository = 'owner/repo'; SkipChain = $true; TimeoutMinutes = 0.5 }
    Assert-True ($run.ExitCode -eq 2) 'An expired code must exit 2.'
    Assert-True ((Get-Lane $run.Object 'github-login').detail -match '^expired') 'Expired lane must be classified expired.'
    Assert-True ((Get-Lane $run.Object 'github-login').ownerAction -match '-Retry') 'Expired lane must point at -Retry.'
    Assert-True (([regex]::Matches((Get-ShimLog), 'gh auth login')).Count -eq 1) 'Without -Retry the code must be issued once.'

    Reset-Shims -Gh 'expired-then-ok' -Az 'ready'
    $run = Invoke-Flow @{ Json = $true; Tenant = $tenant; Repository = 'owner/repo'; SkipChain = $true; TimeoutMinutes = 0.5; Retry = $true }
    Assert-True ($run.ExitCode -eq 0) '-Retry must re-issue an expired code once and succeed.'
    Assert-True (([regex]::Matches((Get-ShimLog), 'gh auth login')).Count -eq 2) '-Retry must launch the login exactly twice.'

    Reset-Shims -Gh 'expired' -Az 'ready'
    $run = Invoke-Flow @{ Json = $true; Tenant = $tenant; Repository = 'owner/repo'; SkipChain = $true; TimeoutMinutes = 0.5; Retry = $true }
    Assert-True ($run.ExitCode -eq 2 -and ([regex]::Matches((Get-ShimLog), 'gh auth login')).Count -eq 2) '-Retry must stop after one re-issue.'

    # --- Timeout: a hanging flow is reported expired and the child is killed ------------------------
    Reset-Shims -Gh 'hang' -Az 'ready'
    $run = Invoke-Flow @{ Json = $true; Tenant = $tenant; Repository = 'owner/repo'; SkipChain = $true; TimeoutMinutes = 0.05 }
    Assert-True ($run.ExitCode -eq 2) 'A timed-out flow must exit 2.'
    Assert-True ((Get-Lane $run.Object 'github-login').detail -match 'expired: no completion within') 'Timed-out lane must be reported as expired with the timeout.'
    # The shim's `sleep 30` grandchild must die with the tree; a just-killed process
    # can linger as a zombie for a moment, so poll briefly before judging.
    $orphans = 1
    foreach ($attempt in 1..10) {
        $orphans = @(Get-Process -Name 'sleep' -ErrorAction SilentlyContinue | Where-Object { $_.StartTime -gt [DateTime]::Now.AddSeconds(-30) }).Count
        if ($orphans -eq 0) { break }
        Start-Sleep -Milliseconds 300
    }
    Assert-True ($orphans -eq 0) 'The hanging child was not killed.'

    # --- Preconditions keep the one-object promise --------------------------------------------------
    $run = Invoke-Flow @{ Json = $true; Tenant = 'not-a-tenant'; Repository = 'owner/repo'; SkipChain = $true }
    Assert-True ($run.ExitCode -eq 2 -and $run.Object.failedPrecondition -match 'tenant') 'A malformed tenant must be a failed precondition.'
    $run = Invoke-Flow @{ Json = $true; Tenant = $tenant; Repository = 'nope'; SkipChain = $true }
    Assert-True ($run.ExitCode -eq 2 -and $run.Object.failedPrecondition -match 'owner/name') 'A malformed repository must be a failed precondition.'

    # --- The bash twin, verify-only, same shims ------------------------------------------------------
    # First match only: ubuntu-latest lists /usr/bin/bash and /bin/bash (the array trap).
    $bash = Get-Command bash -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($bash) {
        Reset-Shims -Gh 'ok' -Az 'ok'
        $twin = Join-Path $root 'scripts/bootstrap/connect-devices.sh'
        $twinOut = & $bash.Source $twin --verify-only --json --tenant $tenant --repository owner/repo 2>$null
        $twinCode = $LASTEXITCODE
        $twinObject = ($twinOut -join "`n") | ConvertFrom-Json
        Assert-True ($twinCode -eq 2) 'Twin verify-only with both lanes logged out must exit 2.'
        Assert-True ((Get-Lane $twinObject 'github-login').state -eq 'needs-owner' -and (Get-Lane $twinObject 'azure-login').state -eq 'needs-owner') 'Twin lanes must need the owner.'
        Assert-True ((Get-ShimLog) -notmatch 'auth login' -and (Get-ShimLog) -notmatch 'use-device-code') 'Twin verify-only launched a login.'
        Reset-Shims -Gh 'ready' -Az 'ready'
        $twinOut = & $bash.Source $twin --verify-only --json --tenant $tenant --repository owner/repo 2>$null
        Assert-True ($LASTEXITCODE -eq 0) 'Twin verify-only with both lanes ready must exit 0.'
        Assert-True ((($twinOut -join "`n") | ConvertFrom-Json).exitCode -eq 0) 'Twin JSON exitCode must match.'

        # Apply path under `set -euo pipefail`: the code-parsing pipelines return 1 until
        # the CLI prints a code, and `wait` returns the child's status - neither may end
        # the script. Both flows accepted -> exit 0 with both lanes ready.
        Reset-Shims -Gh 'ok' -Az 'ok'
        $twinOut = & $bash.Source $twin --json --skip-chain --timeout-minutes 0.5 --tenant $tenant --repository owner/repo 2>$null
        $twinCode = $LASTEXITCODE
        $twinObject = ($twinOut -join "`n") | ConvertFrom-Json
        Assert-True ($twinCode -eq 0) "Twin apply with both flows accepted must exit 0 (got $twinCode)."
        Assert-True ((Get-Lane $twinObject 'github-login').detail -eq 'device code accepted; gh session verified') 'Twin gh lane not verified.'
        Assert-True ((Get-Lane $twinObject 'azure-login').detail -eq 'device code accepted; az session verified') 'Twin az lane not verified.'
        $shimLog = Get-ShimLog
        Assert-True ($shimLog -match 'gh auth login[^\n]*GH_TOKEN=<unset>') 'Twin leaked GH_TOKEN into the gh login child.'
        Assert-True ($shimLog -match "az login --use-device-code --tenant $tenant") 'Twin did not launch the az flow.'
        # Text mode prints the table with both codes before the flows complete.
        Reset-Shims -Gh 'ok' -Az 'ok'
        $twinText = (& $bash.Source $twin --skip-chain --timeout-minutes 0.5 --tenant $tenant --repository owner/repo 2>&1) -join "`n"
        Assert-True ($twinText -match 'GitHub -> https://github.com/login/device\s+code ABCD-1234') 'Twin table lacks the GitHub row.'
        Assert-True ($twinText -match 'Azure\s+-> https://microsoft.com/devicelogin\s+code ABCDEFGHI') 'Twin table lacks the Azure row.'
        # A refused login is a lane verdict (exit 2), not an errexit crash.
        Reset-Shims -Gh 'refused' -Az 'ready'
        $twinOut = & $bash.Source $twin --json --skip-chain --timeout-minutes 0.5 --tenant $tenant --repository owner/repo 2>$null
        $twinCode = $LASTEXITCODE
        $twinObject = ($twinOut -join "`n") | ConvertFrom-Json
        Assert-True ($twinCode -eq 2) "Twin refused login must exit 2 (got $twinCode)."
        Assert-True ((Get-Lane $twinObject 'github-login').detail -match '^refused') 'Twin must classify the refused lane.'
        # --retry re-issues an expired code once.
        Reset-Shims -Gh 'expired-then-ok' -Az 'ready'
        $twinOut = & $bash.Source $twin --json --skip-chain --retry --timeout-minutes 0.5 --tenant $tenant --repository owner/repo 2>$null
        Assert-True ($LASTEXITCODE -eq 0) 'Twin --retry must recover an expired code.'
        Assert-True (([regex]::Matches((Get-ShimLog), 'gh auth login')).Count -eq 2) 'Twin --retry must launch the login exactly twice.'
        # Preconditions keep the one-object promise and carry the real message, not
        # the first fix line.
        $twinOut = & $bash.Source $twin --json --skip-chain --tenant $tenant --repository nope 2>$null
        $twinCode = $LASTEXITCODE
        $twinObject = ($twinOut -join "`n") | ConvertFrom-Json
        Assert-True ($twinCode -eq 2 -and $twinObject.failedPrecondition -match 'owner/name') 'Twin malformed repository must be a failed precondition naming the rule.'
        $twinOut = & $bash.Source $twin --json --skip-chain --tenant not-a-tenant --repository owner/repo 2>$null
        Assert-True ($LASTEXITCODE -eq 2 -and ((($twinOut -join "`n") | ConvertFrom-Json).failedPrecondition -match 'tenant id')) 'Twin malformed tenant must be a failed precondition naming the rule.'
    }

    # --- Dot-sourced contract ---------------------------------------------------------------------
    # Nothing but the report on the pipeline; the code in $connectDevicesExit and $LASTEXITCODE
    # (the counterpart of the bash twin's sourced `return` status).
    Reset-Shims -Gh 'expired' -Az 'expired'
    $global:LASTEXITCODE = 0
    $devicesScript = Join-Path $root 'scripts/bootstrap/connect-devices.ps1'
    $dotOut = . $devicesScript -VerifyOnly -Json -SkipChain 6>&1
    $dotLines = @($dotOut | ForEach-Object { "$_" })
    Assert-True ($connectDevicesExit -eq 2) 'A dot-sourced run must leave the exit code in $connectDevicesExit.'
    Assert-True ($LASTEXITCODE -eq 2) 'A dot-sourced run must leave the exit code in $LASTEXITCODE.'
    Assert-True ($dotLines.Count -gt 0 -and $dotLines[-1] -notmatch '^\d+$') 'A dot-sourced run must put nothing but the report on the pipeline.'
    $dotJson = ($dotLines | Where-Object { $_ -match '^\{' -or $_ -match '^\s' -or $_ -match '^\}' }) -join "`n"
    Assert-True (@(($dotJson | ConvertFrom-Json).lanes | Where-Object { $_.name -eq 'github-login' })[0].state -eq 'needs-owner') 'The dot-sourced JSON report must still parse to the lane table.'

    # --- Child-process contract ---------------------------------------------------------------
    # Run as a real process (the trailer, not the function): -Json prints exactly one object on
    # stdout and the process exit code is the report's exitCode.
    Reset-Shims -Gh 'expired' -Az 'expired'
    $childOut = @(& ([Environment]::ProcessPath) -NoProfile -File $devicesScript -VerifyOnly -Json -SkipChain 2>$null | ForEach-Object { "$_" })
    $childExit = [int]$LASTEXITCODE
    $childObject = ($childOut -join "`n") | ConvertFrom-Json
    Assert-True ($childExit -eq 2) "A child -Json run must exit with the report code (got $childExit)."
    Assert-True ($childObject.exitCode -eq 2 -and @($childObject.lanes | Where-Object { $_.name -eq 'github-login' })[0].state -eq 'needs-owner') 'A child -Json run must print the one report object on stdout.'
    Assert-True (@($childOut | Where-Object { $_ -match '^\d+$' }).Count -eq 0) 'A child -Json run must not print the exit code as a line.'

    # --- No model identifiers in the shipped files ------------------------------------------------
    $forbidden = @(('claude', 'fable'), ('claude', 'opus'), ('claude', 'sonnet'), ('gpt', '5')) | ForEach-Object { $_ -join '[ -]' }
    foreach ($file in 'scripts/bootstrap/connect-devices.ps1', 'scripts/bootstrap/connect-devices.sh', 'scripts/verify/tests/test_connect_devices.ps1') {
        $text = Get-Content -LiteralPath (Join-Path $root $file) -Raw
        Assert-True ($text -notmatch ('(?i)' + ($forbidden -join '|'))) "$file carries a model identifier."
    }
}
finally {
    $env:PATH = $savedPath
    $env:GH_TOKEN = $savedGh
    $env:GITHUB_TOKEN = $savedGithub
    foreach ($name in 'DEV_SHIM_LOG', 'DEV_SHIM_STATE', 'DEV_SHIM_GH', 'DEV_SHIM_AZ', 'DEV_SHIM_GH_SCOPES') { [Environment]::SetEnvironmentVariable($name, $null) }
    Get-EventSubscriber -ErrorAction SilentlyContinue | Unregister-Event -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "Passed $($script:cases) offline connect-devices cases."
# The suite's own status is the verdict: the child processes above exit 2 on purpose
# and would otherwise leave $LASTEXITCODE = 2 for a CI step's trailing exit check.
exit 0
