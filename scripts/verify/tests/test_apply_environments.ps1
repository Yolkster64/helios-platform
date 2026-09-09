# Offline contract suite for scripts/github/apply-environments.ps1.
#
# The script is run for real with `gh` replaced by a shim first on PATH, so no call reaches
# GitHub and every call it WOULD make is logged. That log is the evidence for the two
# properties that matter most here:
#
#   * A dry run makes no mutating call. This script configures the gate in front of
#     `az deployment group create`; a "preview" that quietly wrote would be the worst
#     possible place to have that bug.
#   * An unresolved reviewer BLOCKS the write instead of shrinking it. GitHub's PUT replaces
#     the reviewer list wholesale, so writing a partial list removes the reviewers that could
#     not be resolved - turning a protected environment into an open one while reporting
#     success.
#
# And the repository's hard rule, checked rather than assumed: no secret VALUE is ever
# printed. The manifest carries names; the script must too.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$script:cases = 0

function Assert-True($Value, $Message) { if (-not $Value) { throw $Message }; $script:cases++ }
function Assert-Equal($Expected, $Actual, $Message) {
    if ($Expected -ne $Actual) { throw "$Message (expected '$Expected', got '$Actual')" }
    $script:cases++
}

# The shims are bash scripts made executable with chmod, so this is a Linux/macOS suite.
if ($IsWindows) {
    Write-Host 'SKIPPED: this suite shims gh with a bash script, so it needs a POSIX shell.'
    exit 0
}

$temp = Join-Path ([IO.Path]::GetTempPath()) ('helios-applyenv-' + [guid]::NewGuid())
$bin = Join-Path $temp 'bin'
New-Item -ItemType Directory -Path $bin -Force | Out-Null
$log = Join-Path $temp 'gh.log'
$savedPath = $env:PATH
$script = Join-Path $root 'scripts/github/apply-environments.ps1'
$realPwsh = [Environment]::ProcessPath
if (-not $realPwsh) { $realPwsh = 'pwsh' }

function Invoke-Script {
    param([string[]]$Arguments = @())
    Set-Content -LiteralPath $log -Value '' -NoNewline
    $argv = @('-NoProfile', '-File', $script) + $Arguments
    $out = & $realPwsh @argv 2>$null | Out-String
    return [pscustomobject]@{
        Exit = $LASTEXITCODE
        Out  = $out
        Log  = if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Raw } else { '' }
    }
}

try {
    # gh shim: answers the reads the script makes and logs every argv it is handed. The user
    # lookup succeeds so the reviewer resolves; the environment read 404s, which is the
    # interesting state - the environment does not exist yet, so the workflow naming it would
    # get one with no protection rules at all.
    @'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >> "$GH_SHIM_LOG"
for arg in "$@"; do
  case "$arg" in
    users/*)
      printf 'HTTP/2.0 200 OK\n\n{"id":195981509,"login":"Yolkster64"}\n'; exit 0 ;;
    repos/*/environments/*)
      printf 'HTTP/2.0 404 Not Found\n\n{"message":"Not Found","status":"404"}\n'; exit 1 ;;
    orgs/*)
      printf 'HTTP/2.0 404 Not Found\n\n{"message":"Not Found","status":"404"}\n'; exit 1 ;;
  esac
done
printf 'HTTP/2.0 200 OK\n\n{}\n'
exit 0
'@ -replace "`r`n", "`n" | Set-Content -LiteralPath (Join-Path $bin 'gh') -NoNewline -Encoding utf8
    & chmod +x (Join-Path $bin 'gh')

    $env:GH_SHIM_LOG = $log
    $env:PATH = "$bin$([IO.Path]::PathSeparator)$savedPath"

    # 1. A dry run reads, and writes nothing.
    $dry = Invoke-Script
    Assert-True ($dry.Log -match 'users/Yolkster64') 'the dry run did not resolve the reviewer'
    Assert-True ($dry.Log -match 'repos/.*/environments/production') 'the dry run did not read the live environment'
    Assert-True ($dry.Log -notmatch '--method PUT') 'the DRY RUN made a mutating call'
    Assert-True ($dry.Log -notmatch '--method (POST|PATCH|DELETE)') 'the dry run made a mutating call'
    Assert-True ($dry.Out -match 'would run:') 'the dry run did not print the call it would make'
    Assert-Equal 2 $dry.Exit 'a dry run with work outstanding did not exit 2'

    # 2. The absent environment is reported as the unprotected state it really is, not as
    #    "not configured yet" - the workflow that names it creates it with no rules.
    Assert-True ($dry.Out -match 'absent') 'an absent environment was not reported'
    Assert-True ($dry.Out -match 'UNPROTECTED') 'an absent environment was not called unprotected'

    # 3. An unresolved reviewer blocks the write rather than shrinking the gate.
    @'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >> "$GH_SHIM_LOG"
printf 'HTTP/2.0 404 Not Found\n\n{"message":"Not Found","status":"404"}\n'
exit 1
'@ -replace "`r`n", "`n" | Set-Content -LiteralPath (Join-Path $bin 'gh') -NoNewline -Encoding utf8
    & chmod +x (Join-Path $bin 'gh')
    $blocked = Invoke-Script -Arguments @('-Apply')
    Assert-True ($blocked.Log -notmatch '--method PUT') `
        'an unresolved reviewer still produced a PUT, which would remove the reviewers it could not resolve'
    Assert-True ($blocked.Out -match 'SKIPPED') 'an unresolved reviewer did not skip the environment'
    Assert-Equal 2 $blocked.Exit 'a blocked apply did not exit 2'

    # 4. -Json is one object on stdout, and carries the same verdict as the table.
    $jsonRun = Invoke-Script -Arguments @('-Json')
    $report = $jsonRun.Out | ConvertFrom-Json
    Assert-True ($null -ne $report.environments) '-Json emitted no environments'
    Assert-Equal 'dry-run' $report.mode '-Json did not record the mode'
    Assert-True (@($report.ownerActions).Count -gt 0) '-Json reported no owner actions while the table did'

    # 5. No secret VALUE anywhere in the output - the repository's hard rule. The manifest
    #    carries NAMES, and a script that echoed a value would put it in a CI log forever.
    $allOutput = $dry.Out + $blocked.Out + $jsonRun.Out
    foreach ($shape in 'ghp_', 'github_pat_', 'sk-', 'AZURE_CLIENT_SECRET=') {
        Assert-True ($allOutput -notmatch [regex]::Escape($shape)) "output contained a secret-shaped string: $shape"
    }

    # 6. A manifest that is not there is a failure, not an empty success.
    $missing = Invoke-Script -Arguments @('-ManifestPath', (Join-Path $temp 'nope.json'))
    Assert-Equal 1 $missing.Exit 'a missing manifest did not exit 1'

    # 7. The script parses.
    $errors = $null; $tokens = $null
    [Management.Automation.Language.Parser]::ParseFile($script, [ref]$tokens, [ref]$errors) | Out-Null
    Assert-Equal 0 $errors.Count 'apply-environments.ps1 does not parse'
}
finally {
    $env:PATH = $savedPath
    [Environment]::SetEnvironmentVariable('GH_SHIM_LOG', $null)
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Passed $($script:cases) offline apply-environments cases."
exit 0
