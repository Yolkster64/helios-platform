# Offline contract suite for scripts/github/verify-environment-gate.ps1.
#
# The script is the last thing between a push to main and `az deployment group create`, so
# the property under test is one-sided: it must exit 0 ONLY when a person has to approve the
# deployment, and exit 1 for everything else INCLUDING every way of not being able to tell.
# That is the opposite of the dry-run scripts in scripts/github/, which treat an unreadable
# state as unknown and exit 0 so one transient error cannot red a pull request.
#
# Each scenario below is one live state driven through a `gh` shim first on PATH, so no call
# reaches GitHub. The one that must pass and the ones that must refuse differ by a single
# field, which is what makes the refusals real rather than incidental.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$script:cases = 0

function Assert-True($Value, $Message) { if (-not $Value) { throw $Message }; $script:cases++ }
function Assert-Equal($Expected, $Actual, $Message) {
    if ($Expected -ne $Actual) { throw "$Message (expected '$Expected', got '$Actual')" }
    $script:cases++
}

# The shim is a bash script made executable with chmod, so this is a Linux/macOS suite.
if ($IsWindows) {
    Write-Host 'SKIPPED: this suite shims gh with a bash script, so it needs a POSIX shell.'
    exit 0
}

$temp = Join-Path ([IO.Path]::GetTempPath()) ('helios-envgate-' + [guid]::NewGuid())
$bin = Join-Path $temp 'bin'
New-Item -ItemType Directory -Path $bin -Force | Out-Null
$emptyBin = Join-Path $temp 'emptybin'
New-Item -ItemType Directory -Path $emptyBin -Force | Out-Null
$log = Join-Path $temp 'gh.log'
$savedPath = $env:PATH
$script = Join-Path $root 'scripts/github/verify-environment-gate.ps1'
$realPwsh = [Environment]::ProcessPath
if (-not $realPwsh) { $realPwsh = 'pwsh' }
# Captured before the try so the finally cannot throw on an unset variable under StrictMode
# and hide the assertion that actually failed.
$savedDecoy = $env:AZURE_CLIENT_ID

function Invoke-Gate {
    param([string[]]$Arguments = @(), [string]$Case = 'protected', [string]$PathOverride)
    Set-Content -LiteralPath $log -Value '' -NoNewline
    $env:GH_SHIM_CASE = $Case
    $previousPath = $env:PATH
    if ($PathOverride) { $env:PATH = $PathOverride }
    try {
        $argv = @('-NoProfile', '-File', $script) + $Arguments
        $out = & $realPwsh @argv 2>$null | Out-String
        return [pscustomobject]@{
            Exit = $LASTEXITCODE
            Out  = $out
            Log  = if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Raw } else { '' }
        }
    }
    finally { $env:PATH = $previousPath }
}

try {
    # One reviewer object, reused: the difference between the scenarios has to be the RULE,
    # not the reviewer, or a refusal could be passing for the wrong reason.
    @'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >> "$GH_SHIM_LOG"
reviewer='{"type":"User","reviewer":{"id":195981509,"login":"Yolkster64","type":"User"}}'
pinned='"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}'
case "${GH_SHIM_CASE:-protected}" in
  protected)        body='{"name":"production","protection_rules":[{"type":"wait_timer","wait_timer":0},{"type":"required_reviewers","prevent_self_review":true,"reviewers":['"$reviewer"']}],'"$pinned"'}' ;;
  self-review-off)  body='{"name":"production","protection_rules":[{"type":"required_reviewers","prevent_self_review":false,"reviewers":['"$reviewer"']}],'"$pinned"'}' ;;
  any-branch)       body='{"name":"production","protection_rules":[{"type":"required_reviewers","prevent_self_review":true,"reviewers":['"$reviewer"']}],"deployment_branch_policy":null}' ;;
  # The state a fresh `environment: production` in a workflow leaves behind: it exists, and
  # it gates nothing.
  no-rules)         body='{"name":"production","protection_rules":[],"deployment_branch_policy":null}' ;;
  # A timer delays the deployment and then runs it unattended.
  timer-only)       body='{"name":"production","protection_rules":[{"type":"wait_timer","wait_timer":30}],"deployment_branch_policy":null}' ;;
  # What a UI edit leaves when the last reviewer is removed: the rule stays, the list empties,
  # and GitHub approves everything.
  zero-reviewers)   body='{"name":"production","protection_rules":[{"type":"required_reviewers","prevent_self_review":true,"reviewers":[]}],'"$pinned"'}' ;;
  absent)           printf 'HTTP/2.0 404 Not Found\n\n{"message":"Not Found","status":"404"}\n'; exit 1 ;;
  forbidden)        printf 'HTTP/2.0 403 Forbidden\n\n{"message":"Resource not accessible by integration","status":"403"}\n'; exit 1 ;;
  server-error)     printf 'HTTP/2.0 500 Internal Server Error\n\n{}\n'; exit 1 ;;
  # No status line at all - a proxy or a dead connection. HttpStatus reads 0.
  no-reply)         printf ''; exit 1 ;;
esac
printf 'HTTP/2.0 200 OK\n\n%s\n' "$body"
exit 0
'@ -replace "`r`n", "`n" | Set-Content -LiteralPath (Join-Path $bin 'gh') -NoNewline -Encoding utf8
    & chmod +x (Join-Path $bin 'gh')

    $env:GH_SHIM_LOG = $log
    $env:PATH = "$bin$([IO.Path]::PathSeparator)$savedPath"

    # A token-shaped decoy under a name this repository's manifests reference. Nothing here
    # should ever read an env var's VALUE, and an assertion that looks for a secret in a run
    # where none exists cannot fail.
    $decoy = 'ghp_' + ('E' * 32)
    $env:AZURE_CLIENT_ID = $decoy

    # 1. The only state that may proceed: a reviewer must approve.
    $ok = Invoke-Gate -Case 'protected'
    Assert-Equal 0 $ok.Exit 'a protected environment with a reviewer was refused'
    Assert-True ($ok.Out -match 'OK: 1 reviewer\(s\) must approve') 'the passing verdict was not stated'
    Assert-True ($ok.Out -match 'reviewers=1') 'the live reviewer count was not reported'
    Assert-True ($ok.Log -match 'repos/Yolkster64/helios-platform/environments/production') `
        'the environment was never read'
    Assert-True ($ok.Log -notmatch '--method') 'a verifier made a mutating call'
    # No REFUSED anywhere in a passing run: the refusal text carries the repair instructions,
    # and printing them on a healthy gate would send the owner to fix nothing.
    Assert-True ($ok.Out -notmatch 'REFUSED') 'a passing run printed a refusal'

    # 2. Absent - the state main is in right now, and the whole reason this script exists.
    #    The deploy job names `production`; naming an environment GitHub does not have
    #    CREATES it with no rules, so without this check the gate reads as present in the
    #    YAML and holds nothing back.
    $absent = Invoke-Gate -Case 'absent'
    Assert-Equal 1 $absent.Exit 'an absent environment did not refuse the deployment'
    Assert-True ($absent.Out -match 'REFUSED') 'the refusal was not stated'
    Assert-True ($absent.Out -match 'does not exist') 'the refusal did not say the environment is absent'
    Assert-True ($absent.Out -match 'connect-github-app\.ps1') 'the refusal did not name the repair'
    Assert-True ($absent.Out -match 'apply-environments\.ps1 -Apply') 'the refusal did not name the apply command'

    # 3. Exists and gates nothing. One field apart from case 1: the rules list is empty.
    $bare = Invoke-Gate -Case 'no-rules'
    Assert-Equal 1 $bare.Exit 'an environment with no protection rules was allowed to deploy'
    Assert-True ($bare.Out -match 'no required_reviewers rule') 'the missing reviewer rule was not named'

    # 4. A wait timer is not a human. This one is worth its own case because it LOOKS
    #    protected in the UI - the environment has a rule, the deployment pauses - and then
    #    it runs with nobody having looked at it.
    $timer = Invoke-Gate -Case 'timer-only'
    Assert-Equal 1 $timer.Exit 'an environment whose only rule is a wait timer was allowed to deploy'
    Assert-True ($timer.Out -match 'wait_timer=30') 'the live wait timer was not reported'
    Assert-True ($timer.Out -match 'a timer is not a human') 'the refusal did not explain why a timer is not a gate'

    # 5. The rule with an empty list - what removing the last reviewer in the UI leaves
    #    behind. GitHub keeps the rule and approves everything, so `hasReviewerRule` alone
    #    would have passed this.
    $empty = Invoke-Gate -Case 'zero-reviewers'
    Assert-Equal 1 $empty.Exit 'a required_reviewers rule with an empty list was allowed to deploy'
    Assert-True ($empty.Out -match 'EMPTY reviewer') 'the empty reviewer list was not named'
    Assert-True ($empty.Out -match 'approves every deployment') 'the consequence was not stated'

    # 6. Every way of not being able to tell refuses. This is the whole difference in posture
    #    from the governance scripts: there, an unreadable state is `unknown` and exit 0, so
    #    one transient 5xx cannot red every pull request. Here the answer gates a deployment,
    #    and "I could not check" is not a reason to proceed.
    foreach ($row in @(
        @{ Case = 'forbidden';    Match = 'cannot read environment'; What = 'a 403' },
        @{ Case = 'server-error'; Match = 'HTTP 500';                 What = 'a 500' },
        @{ Case = 'no-reply';     Match = 'could not be read';        What = 'no reply at all' }
    )) {
        $blind = Invoke-Gate -Case $row.Case
        Assert-Equal 1 $blind.Exit "$($row.What) did not refuse the deployment (this check must fail closed)"
        Assert-True ($blind.Out -match $row.Match) "$($row.What) was not reported in the refusal"
    }

    # 6b. And the repair has to match the fault. A 403 means the rules may be in place and
    #     unreadable from here, so telling the owner to apply the manifest would send them to
    #     fix something that is not broken - confidently, which is worse than saying less.
    $forbidden = Invoke-Gate -Case 'forbidden'
    Assert-True ($forbidden.Out -match 'Grant this job a credential') `
        'a 403 did not name the credential as the repair'
    Assert-True ($forbidden.Out -notmatch 'apply-environments\.ps1 -Apply') `
        'a 403 told the owner to apply protection rules that may already be there'

    # 7. No gh at all. An empty PATH directory rather than a shim that errors, because the
    #    branch under test is the one where Get-Command finds nothing.
    $noGh = Invoke-Gate -Case 'protected' -PathOverride $emptyBin
    Assert-Equal 1 $noGh.Exit 'a host without gh was allowed to deploy on an assumption'
    # `REFUSED: gh is not on PATH`, not merely the words somewhere in the output. Without gh
    # the wire layer answers HTTP 0 and the generic unreadable branch refuses too, so an
    # assertion that only looked for the phrase passed whether or not this branch existed -
    # it would have reported a specific diagnosis the script had stopped making.
    Assert-True ($noGh.Out -match 'REFUSED: gh is not on PATH') `
        'the missing gh was not the stated reason for the refusal'
    Assert-True ($noGh.Out -match 'Install the GitHub CLI') 'the missing gh did not name its own repair'
    Assert-True ($noGh.Out -notmatch 'apply-environments\.ps1 -Apply') `
        'a host without gh was told to apply protection rules, which is not what is wrong'

    # 8. Two weakened-but-still-human states WARN and proceed. Refusing here would block a
    #    deployment over a setting that still has a person in the path, and warning nowhere
    #    would let the manifest's own `because` drift silently.
    $selfReview = Invoke-Gate -Case 'self-review-off'
    Assert-Equal 0 $selfReview.Exit 'prevent_self_review being off refused a deployment that still needs a human'
    Assert-True ($selfReview.Out -match 'WARNING: prevent_self_review is off') 'self-review drift was not warned about'
    Assert-True ($selfReview.Out -match 'can approve it themselves') 'the consequence of self-review was not stated'

    $anyBranch = Invoke-Gate -Case 'any-branch'
    Assert-Equal 0 $anyBranch.Exit 'an any-branch policy refused a deployment that still needs a human'
    Assert-True ($anyBranch.Out -match 'admits deployments from any branch') 'the any-branch policy was not warned about'

    # 9. -Json is one object on stdout and carries the same verdict as the lines.
    $okJson = Invoke-Gate -Arguments @('-Json') -Case 'protected'
    $okReport = $okJson.Out | ConvertFrom-Json
    Assert-Equal 'allowed' $okReport.verdict '-Json disagreed with the table about a protected environment'
    Assert-Equal 1 $okReport.reviewers '-Json did not carry the reviewer count'
    Assert-Equal $true $okReport.preventSelfReview '-Json did not carry prevent_self_review'

    $denyJson = Invoke-Gate -Arguments @('-Json') -Case 'absent'
    $denyReport = $denyJson.Out | ConvertFrom-Json
    Assert-Equal 'refused' $denyReport.verdict '-Json did not record the refusal'
    Assert-Equal 'absent' $denyReport.state '-Json did not record WHY it refused'
    Assert-Equal 1 $denyJson.Exit '-Json changed the exit code'

    # 10. A different environment name is read, not assumed. Otherwise the parameter could be
    #     ignored and every assertion above would still pass.
    $named = Invoke-Gate -Arguments @('-EnvironmentName', 'staging') -Case 'protected'
    Assert-True ($named.Log -match 'environments/staging') '-EnvironmentName was ignored'

    # 11. No secret VALUE anywhere in any of the output above. AZURE_CLIENT_ID holds a
    #     token-shaped decoy, so a script that resolved a name to its value would put it in a
    #     CI log forever.
    $allOutput = $ok.Out + $absent.Out + $bare.Out + $timer.Out + $empty.Out + $noGh.Out +
                 $selfReview.Out + $anyBranch.Out + $okJson.Out + $denyJson.Out + $named.Out + $forbidden.Out
    Assert-True ($allOutput -notmatch [regex]::Escape($decoy)) `
        'a secret VALUE reached the output: the script resolved an env-var name to its value'
    foreach ($shape in 'ghp_', 'github_pat_', 'sk-') {
        Assert-True ($allOutput -notmatch [regex]::Escape($shape)) "output contained a secret-shaped string: $shape"
    }

    # 12. The script parses.
    $errors = $null; $tokens = $null
    [Management.Automation.Language.Parser]::ParseFile($script, [ref]$tokens, [ref]$errors) | Out-Null
    Assert-Equal 0 $errors.Count 'verify-environment-gate.ps1 does not parse'
}
finally {
    $env:PATH = $savedPath
    $env:AZURE_CLIENT_ID = $savedDecoy
    [Environment]::SetEnvironmentVariable('GH_SHIM_LOG', $null)
    [Environment]::SetEnvironmentVariable('GH_SHIM_CASE', $null)
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Passed $($script:cases) offline verify-environment-gate cases."
exit 0
