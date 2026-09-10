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
$bodyLog = Join-Path $temp 'gh-body.log'
$savedPath = $env:PATH
$script = Join-Path $root 'scripts/github/apply-environments.ps1'
$realPwsh = [Environment]::ProcessPath
if (-not $realPwsh) { $realPwsh = 'pwsh' }
# Captured out here, not next to the decoy below: the finally block restores it, and under
# StrictMode a failure before the assignment would make the finally throw "variable not set"
# over the top of the assertion that actually failed.
$savedDecoy = $env:AZURE_CLIENT_ID

function Invoke-Script {
    param([string[]]$Arguments = @(), [string]$Case = 'absent')
    Set-Content -LiteralPath $log -Value '' -NoNewline
    Set-Content -LiteralPath $bodyLog -Value '' -NoNewline
    $env:GH_SHIM_CASE = $Case
    $argv = @('-NoProfile', '-File', $script) + $Arguments
    $out = & $realPwsh @argv 2>$null | Out-String
    return [pscustomobject]@{
        Exit = $LASTEXITCODE
        Out  = $out
        Log  = if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Raw } else { '' }
        Body = if (Test-Path -LiteralPath $bodyLog) { Get-Content -LiteralPath $bodyLog -Raw } else { '' }
    }
}

try {
    # gh shim, driven by GH_SHIM_CASE so the suite can reach states the script actually has.
    # The first version answered 404 to EVERY environment read, which meant `in sync`,
    # `applied.`, the branch-pattern calls and the secret/variable notes were never executed
    # by any case - four code paths the suite silently never saw. It also records the --input
    # body, so an assertion can check WHAT was sent and not merely that something was.
    @'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >> "$GH_SHIM_LOG"
prev=""
method="GET"
for a in "$@"; do
  if [ "$prev" = "--method" ]; then method="$a"; fi
  if [ "$prev" = "--input" ] && [ -n "${GH_SHIM_BODY:-}" ]; then cat "$a" >> "$GH_SHIM_BODY"; fi
  prev="$a"
done
reviewers='{"reviewer":{"id":195981509,"type":"User"}}'
case "${GH_SHIM_CASE:-absent}" in
  in-sync)      env_body='{"protection_rules":[{"type":"wait_timer","wait_timer":0},{"type":"required_reviewers","prevent_self_review":true,"reviewers":['"$reviewers"']}],"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}'
                patterns='{"branch_policies":[{"id":1,"name":"main"}]}' ;;
  self-review-off) env_body='{"protection_rules":[{"type":"wait_timer","wait_timer":0},{"type":"required_reviewers","prevent_self_review":false,"reviewers":['"$reviewers"']}],"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}'
                patterns='{"branch_policies":[{"id":1,"name":"main"}]}' ;;
  extra-pattern) env_body='{"protection_rules":[{"type":"wait_timer","wait_timer":0},{"type":"required_reviewers","prevent_self_review":true,"reviewers":['"$reviewers"']}],"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}'
                patterns='{"branch_policies":[{"id":1,"name":"main"},{"id":2,"name":"feature/*"}]}' ;;
  # Both at once: the write path runs (self-review is off, so it is not in sync) AND a
  # pattern the script will not delete remains afterwards. Neither single-fault case reaches
  # that combination - extra-pattern alone never gets past the in-sync branch.
  extra-and-drifted) env_body='{"protection_rules":[{"type":"wait_timer","wait_timer":0},{"type":"required_reviewers","prevent_self_review":false,"reviewers":['"$reviewers"']}],"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}'
                patterns='{"branch_policies":[{"id":1,"name":"main"},{"id":2,"name":"feature/*"}]}' ;;
  # A wait timer nobody asked for, everything else matching - the only case that isolates
  # that term of the comparison.
  wrong-timer)  env_body='{"protection_rules":[{"type":"wait_timer","wait_timer":30},{"type":"required_reviewers","prevent_self_review":true,"reviewers":['"$reviewers"']}],"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}'
                patterns='{"branch_policies":[{"id":1,"name":"main"}]}' ;;
  # Somebody else on the reviewer list, everything else matching. Without this case the
  # reviewer comparison could be deleted outright and every other case still passed.
  wrong-reviewer) env_body='{"protection_rules":[{"type":"wait_timer","wait_timer":0},{"type":"required_reviewers","prevent_self_review":true,"reviewers":[{"reviewer":{"id":42,"type":"User"}}]}],"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}'
                patterns='{"branch_policies":[{"id":1,"name":"main"}]}' ;;
  # The environment reads fine; its branch-policy endpoint does not. Not the same as
  # `unreadable`, where nothing about the environment is known.
  patterns-unreadable) env_body='{"protection_rules":[{"type":"wait_timer","wait_timer":0},{"type":"required_reviewers","prevent_self_review":true,"reviewers":['"$reviewers"']}],"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}'
                patterns='' ;;
  unreadable)   env_body='' ; patterns='' ;;
  *)            env_body='' ; patterns='{"branch_policies":[]}' ;;
esac
for arg in "$@"; do
  case "$arg" in
    users/*)
      if [ "${GH_SHIM_CASE:-absent}" = "no-user" ]; then printf 'HTTP/2.0 404 Not Found\n\n{"message":"Not Found","status":"404"}\n'; exit 1; fi
      printf 'HTTP/2.0 200 OK\n\n{"id":195981509,"login":"Yolkster64"}\n'; exit 0 ;;
    orgs/*)  printf 'HTTP/2.0 404 Not Found\n\n{"message":"Not Found","status":"404"}\n'; exit 1 ;;
    */deployment-branch-policies)
      if [ "$method" != "GET" ]; then printf 'HTTP/2.0 200 OK\n\n{"id":9,"name":"main"}\n'; exit 0; fi
      if [ -z "$patterns" ]; then printf 'HTTP/2.0 500 Server Error\n\n{}\n'; exit 1; fi
      printf 'HTTP/2.0 200 OK\n\n%s\n' "$patterns"; exit 0 ;;
    repos/*/environments/*)
      # A PUT here is create-or-update, which is why naming an environment GitHub does not
      # have creates it. Answering the PUT with the GET's 404 (the first version of this
      # shim) meant `applied.` and the branch-pattern POST were unreachable from any case.
      if [ "$method" != "GET" ]; then printf 'HTTP/2.0 200 OK\n\n{"name":"production"}\n'; exit 0; fi
      if [ "${GH_SHIM_CASE:-absent}" = "unreadable" ]; then printf 'HTTP/2.0 500 Server Error\n\n{}\n'; exit 1; fi
      if [ -z "$env_body" ]; then printf 'HTTP/2.0 404 Not Found\n\n{"message":"Not Found","status":"404"}\n'; exit 1; fi
      printf 'HTTP/2.0 200 OK\n\n%s\n' "$env_body"; exit 0 ;;
  esac
done
printf 'HTTP/2.0 200 OK\n\n{}\n'
exit 0
'@ -replace "`r`n", "`n" | Set-Content -LiteralPath (Join-Path $bin 'gh') -NoNewline -Encoding utf8
    & chmod +x (Join-Path $bin 'gh')

    $env:GH_SHIM_LOG = $log
    $env:GH_SHIM_BODY = $bodyLog
    $env:PATH = "$bin$([IO.Path]::PathSeparator)$savedPath"

    # A decoy value under a name the manifest lists in variableNames. The script reports
    # those as NAMES and must never read one; the old secret assertion could not fail
    # because nothing secret-shaped existed anywhere for it to find.
    $decoy = 'ghp_' + ('D' * 32)
    $env:AZURE_CLIENT_ID = $decoy

    # 1. A dry run reads, and writes nothing.
    $dry = Invoke-Script
    Assert-True ($dry.Log -match 'users/Yolkster64') 'the dry run did not resolve the reviewer'
    Assert-True ($dry.Log -match 'repos/.*/environments/production') 'the dry run did not read the live environment'
    Assert-True ($dry.Log -notmatch '--method PUT') 'the DRY RUN made a mutating call'
    Assert-True ($dry.Log -notmatch '--method (POST|PATCH|DELETE)') 'the dry run made a mutating call'
    Assert-True ($dry.Out -match 'would run:') 'the dry run did not print the call it would make'
    # Exit 0, not 2. governance-run.yml reads exit 2 from an admin item as "the admin
    # credential was rejected" and turns the row red telling the owner to rotate a token
    # that is fine; pending dry-run changes are reported by counting the "would run:" lines
    # this script prints. Exit 2 is reserved for a genuinely missing precondition.
    Assert-Equal 0 $dry.Exit 'a dry run with pending changes must exit 0, not 2 (see governance-run.yml)'

    # 1b. The closing line must not contradict the body. This is what CI caught that the
    #     suite had not: a dry run reported the environment absent, printed the PUT it would
    #     make, and then signed off "Nothing left for you: every environment in the manifest
    #     matches the repository." The summary keyed off an empty owner-action list rather
    #     than off the pending set.
    Assert-True ($dry.Out -notmatch 'Nothing left for you') `
        'a dry run with pending changes claimed every environment matches the repository'
    Assert-True ($dry.Out -match 'environment\(s\) would change') `
        'a dry run with pending changes did not say how many would change'

    # 2. The absent environment is reported as the unprotected state it really is, not as
    #    "not configured yet" - the workflow that names it creates it with no rules.
    Assert-True ($dry.Out -match 'absent') 'an absent environment was not reported'
    Assert-True ($dry.Out -match 'UNPROTECTED') 'an absent environment was not called unprotected'

    # 3. An unresolved reviewer blocks the write rather than shrinking the gate.
    #    Driven by the scenario, not by overwriting the shim: the previous version replaced
    #    the shim file here and never put it back, so every later case silently ran against
    #    an always-404 gh instead of the one it thought it had.
    $blocked = Invoke-Script -Arguments @('-Apply') -Case 'no-user'
    Assert-True ($blocked.Log -notmatch '--method PUT') `
        'an unresolved reviewer still produced a PUT, which would remove the reviewers it could not resolve'
    Assert-True ($blocked.Out -match 'FAILED') 'an unresolved reviewer did not fail the environment'
    # Exit 1, not 2. A reviewer the manifest names and GitHub does not have is a fault in the
    # MANIFEST, and governance-run.yml renders exit 2 from an admin item as "your admin token
    # was revoked - rotate it". A typo, a renamed account, or a Team reviewer on a user-owned
    # repo (no teams exist, so the lookup 404s by construction) would send the owner rotating
    # a perfectly healthy credential.
    Assert-Equal 1 $blocked.Exit 'an unresolvable reviewer must exit 1 (a manifest fault), not 2 (a credential fault)'

    # 4. -Json is one object on stdout, and carries the same verdict as the table.
    $jsonRun = Invoke-Script -Arguments @('-Json')
    $report = $jsonRun.Out | ConvertFrom-Json
    # .Count, not `$null -ne`: in PowerShell `$null -ne @()` is TRUE, so both of these
    # passed for an empty array - a -Json report carrying no environments at all satisfied
    # "emitted no environments".
    Assert-Equal 1 @($report.environments).Count '-Json did not report the one manifest environment'
    Assert-Equal 'would-change' $report.environments[0].state '-Json state disagrees with the table'
    Assert-Equal 'dry-run' $report.mode '-Json did not record the mode'

    # 5. No secret VALUE anywhere in the output - the repository's hard rule. AZURE_CLIENT_ID
    #    is set to a token-shaped decoy above and is named in the manifest's variableNames, so
    #    a script that resolved a name to its value would put the decoy in this output. The
    #    earlier version of this check looked for secret shapes in a run where none existed
    #    and in code paths no case reached, so it could not fail; planting a literal token in
    #    the script left the suite green at 22/22.
    $applied = Invoke-Script -Arguments @('-Apply') -Case 'absent'
    Assert-True ($applied.Out -match 'gh variable set AZURE_CLIENT_ID') `
        'the apply path never reported the variable names, so the secret check reaches nothing'
    Assert-True ($dry.Out -match 'gh variable set AZURE_CLIENT_ID') `
        'the DRY RUN hid the variables that go with the call it printed; the preview is the report'

    # 5b. What the PUT actually sends. -F cannot express deployment_branch_policy (a nested
    #     object needing BOTH booleans), so it was omitted entirely at first: custom_branches
    #     never reached GitHub, and the item reported `applied.` and then `would change`
    #     again on the very next run, forever. The body is captured from --input by the shim.
    Assert-True ($applied.Body -match '"deployment_branch_policy":\{"protected_branches":false,"custom_branch_policies":true\}') `
        'the PUT body carried no nested branch policy, so the environment would allow any branch'
    Assert-True ($applied.Body -match '"prevent_self_review":true') 'the PUT body did not carry prevent_self_review'
    Assert-True ($applied.Body -match '"reviewers":\[\{"type":"User","id":195981509\}\]') `
        'the PUT body did not carry the resolved reviewer id'
    # 5c. And the second call: the patterns live on their own endpoint, so a PUT alone leaves
    #     a custom policy allowing NOTHING. This is reachable only because the shim answers a
    #     PUT the way GitHub does (create-or-update) instead of repeating the GET's 404.
    Assert-True ($applied.Out -match 'applied\.') 'the apply path never reported a successful write'
    Assert-True ($applied.Log -match '--method POST repos/\S+/environments/production/deployment-branch-policies') `
        'the branch pattern was never POSTed, so the custom policy would allow no branch at all'
    Assert-True ($applied.Out -match "branch pattern 'main' allowed\.") 'the added branch pattern was not reported'

    # 6. An environment that already matches makes NO call and says so. Every case above
    #    answers the environment read with 404 or a mismatch, so without this one the whole
    #    live-comparison block, the `in sync` line and the clean sign-off were code no test
    #    ever executed - the suite was green on paths it had never run.
    $sync = Invoke-Script -Case 'in-sync'
    Assert-True ($sync.Out -match 'in sync; no call made\.') 'a matching environment was not reported in sync'
    Assert-True ($sync.Log -notmatch '--method') 'an in-sync environment was written to anyway'
    Assert-True ($sync.Out -notmatch 'would run:') 'an in-sync environment printed a call it would make'
    Assert-True ($sync.Out -match 'Nothing left for you') 'an in-sync run did not sign off clean'
    Assert-Equal 0 $sync.Exit 'an in-sync run did not exit 0'
    $syncJsonRun = Invoke-Script -Arguments @('-Json') -Case 'in-sync'
    $syncJson = $syncJsonRun.Out | ConvertFrom-Json
    Assert-Equal 'in-sync' $syncJson.environments[0].state '-Json disagreed with the table about an in-sync environment'

    # 7. ONE boolean apart from case 6: prevent_self_review switched off in the UI. It rides
    #    on the required_reviewers rule and was sent but never compared, so the control the
    #    manifest's `because` specifically names could be turned off and this script would
    #    still print `in sync`. Sharing a scenario with case 6 is the point - nothing else
    #    differs, so this can only pass if the comparison genuinely reads that field.
    $drifted = Invoke-Script -Case 'self-review-off'
    Assert-True ($drifted.Out -match 'prevent_self_review=False') 'the live prevent_self_review value was not reported'
    Assert-True ($drifted.Out -notmatch 'in sync') 'self-review protection switched off still read as in sync'
    Assert-True ($drifted.Out -match 'would run: .*--method PUT') 'the drifted environment produced no PUT to restore it'

    # 7a. A wait timer set in the UI that the manifest does not ask for. Same shape again:
    #     one field apart from case 6, so it can only pass if that field is compared.
    $timerDrift = Invoke-Script -Case 'wrong-timer'
    Assert-True ($timerDrift.Out -match 'wait_timer=30') 'the live wait_timer was not reported'
    Assert-True ($timerDrift.Out -notmatch 'in sync') 'a wait timer the manifest does not ask for read as in sync'

    # 7b. A different account on the reviewer list - the same shape of drift as 7, in the
    #     field that decides WHO may approve a deployment. The PUT that restores it carries
    #     the manifest's id and not the live one, which is the whole point of resolving
    #     logins to ids before writing.
    $wrongReviewer = Invoke-Script -Case 'wrong-reviewer'
    Assert-True ($wrongReviewer.Out -notmatch 'in sync') 'a different reviewer account still read as in sync'
    Assert-True ($wrongReviewer.Out -match '"id":195981509') 'the PUT would not restore the reviewer the manifest names'
    Assert-True ($wrongReviewer.Out -notmatch '"id":42') 'the PUT carried the live reviewer instead of the manifest one'

    # 7c. The branch-policy SHAPE, isolated. A manifest that names no branch policy wants
    #     "any branch may deploy"; the live environment restricts to main. Every OTHER term
    #     matches, and the extra pattern alone is now an owner note rather than a difference,
    #     so without the shape comparison this reads as "in sync apart from a pattern only
    #     you can remove" - telling the owner to delete `main` when what actually differs is
    #     that the policy exists at all.
    $anyBranch = Join-Path $temp 'any-branch.json'
    @'
{ "environments": [ { "name": "production", "wait_timer": 0, "prevent_self_review": true,
    "reviewers": [ { "type": "User", "name": "Yolkster64" } ] } ] }
'@ | Set-Content -LiteralPath $anyBranch -Encoding utf8
    $shapeDrift = Invoke-Script -Arguments @('-ManifestPath', $anyBranch) -Case 'in-sync'
    Assert-True ($shapeDrift.Out -match 'branch-policy=any-branch') 'the wanted branch policy was not reported'
    Assert-True ($shapeDrift.Out -notmatch 'in sync') 'a live branch policy the manifest does not declare read as in sync'
    Assert-True ($shapeDrift.Out -match '"deployment_branch_policy":null') `
        'the PUT would not clear the branch policy, so "any branch" could never be restored'

    # 8. An extra branch pattern WIDENS the gate, and only a DELETE removes it - which this
    #    script never makes. So it is neither `in sync` (that hides the wider gate) nor
    #    `would change` (a PUT cannot narrow it: -Apply would report `applied.` over a gate
    #    that is still wide, and the next dry run would print the same useless PUT forever).
    $wide = Invoke-Script -Case 'extra-pattern'
    Assert-True ($wide.Out -match "also allows deployments from 'feature/\*'") 'the extra branch pattern was not reported'
    Assert-True ($wide.Out -match 'in sync apart from 1 branch pattern') 'the extra-pattern verdict was not stated'
    Assert-True ($wide.Out -notmatch 'would run:') 'an extra branch pattern printed a PUT that cannot remove it'
    Assert-True ($wide.Out -notmatch 'Nothing left for you') 'a gate wider than the manifest signed off as matching'
    # No pending call to report and no clean sign-off to print: without its own sentence the
    # run would end on the owner list with no verdict, reading as though it forgot to say.
    Assert-True ($wide.Out -match 'need a change only you can make') 'the run ended with no verdict at all'
    $wideApply = Invoke-Script -Arguments @('-Apply') -Case 'extra-pattern'
    Assert-True ($wideApply.Log -notmatch '--method') 'an extra branch pattern produced a write that cannot remove it'
    Assert-True ($wideApply.Out -notmatch 'applied\.') 'an -Apply run reported `applied.` over a gate wider than the manifest'
    Assert-Equal 0 $wideApply.Exit 'an owner-only difference must not fail the governance run'

    # 8b. The combination, which neither single-fault case reaches: an environment that IS
    #     out of sync (self-review off) AND carries a pattern this script will not delete.
    #     Only here does the write path run with extras still present, so only here can
    #     `applied.` be tested for the claim it makes - the environment now matches the
    #     manifest - when it does not.
    $wideDrift = Invoke-Script -Arguments @('-Apply') -Case 'extra-and-drifted'
    Assert-True ($wideDrift.Log -match '--method PUT') 'the drifted environment was not written'
    Assert-True ($wideDrift.Out -match 'still allow deployments the manifest does not') `
        '-Apply signed off on an environment whose gate is still wider than the manifest'
    $wideDriftJson = Invoke-Script -Arguments @('-Apply', '-Json') -Case 'extra-and-drifted'
    Assert-Equal 'needs-owner' ($wideDriftJson.Out | ConvertFrom-Json).environments[0].state `
        '-Json reported a wider-than-manifest gate as fully applied'

    # 8c. The patterns endpoint alone fails. Not knowing which patterns exist is not the
    #     same as knowing they are missing: POSTing them blind would 422 on any that already
    #     exist, and run_item turns that exit 1 into a red governance row for one transient
    #     read. The environment body is still written - a PUT is idempotent - and the
    #     patterns wait for a run that can see them.
    $blindPatterns = Invoke-Script -Case 'patterns-unreadable'
    Assert-True ($blindPatterns.Out -match 'leaving the patterns alone this run') `
        'an unreadable pattern list was not reported as unknown'
    Assert-True ($blindPatterns.Out -match 'would run: .*--method PUT') 'the environment body was not written'
    Assert-True ($blindPatterns.Out -notmatch 'deployment-branch-policies -f') `
        'a branch pattern would be POSTed although the live list could not be read'
    Assert-Equal 0 $blindPatterns.Exit 'an unreadable pattern list failed the run'

    # 9. A 5xx on the environment read is unknown, not absent. Writing here would be a blind
    #    PUT, and exit 1 would red the whole governance workflow on every pull request for
    #    one transient GitHub error, so it is reported and the environment is left alone.
    $unknown = Invoke-Script -Case 'unreadable'
    Assert-True ($unknown.Out -match 'could not be read \(HTTP 500\)') 'an unreadable environment was not reported as such'
    Assert-True ($unknown.Out -notmatch 'absent') 'an unreadable environment was reported as absent'
    Assert-True ($unknown.Log -notmatch '--method') 'an unreadable environment was written to blind'
    Assert-Equal 0 $unknown.Exit 'a transient 5xx failed the run instead of leaving the environment alone'
    $unknownJsonRun = Invoke-Script -Arguments @('-Json') -Case 'unreadable'
    $unknownJson = $unknownJsonRun.Out | ConvertFrom-Json
    Assert-Equal 'unknown' $unknownJson.environments[0].state '-Json did not record the unreadable environment as unknown'

    # 9b. The secret sweep, over EVERY run above rather than one of them, now that the runs
    #     reach the write paths as well as the read paths.
    $allOutput = $dry.Out + $blocked.Out + $jsonRun.Out + $applied.Out + $sync.Out + $syncJsonRun.Out +
                 $drifted.Out + $timerDrift.Out + $wrongReviewer.Out + $shapeDrift.Out + $wide.Out + $blindPatterns.Out + $wideApply.Out + $wideDrift.Out + $wideDriftJson.Out +
                 $unknown.Out + $unknownJsonRun.Out
    Assert-True ($allOutput -notmatch [regex]::Escape($decoy)) `
        'a secret VALUE reached the output: the script resolved an env-var name to its value'
    foreach ($shape in 'ghp_', 'github_pat_', 'sk-') {
        Assert-True ($allOutput -notmatch [regex]::Escape($shape)) "output contained a secret-shaped string: $shape"
    }

    # 10. A manifest that is not there is a failure, not an empty success.
    $missing = Invoke-Script -Arguments @('-ManifestPath', (Join-Path $temp 'nope.json'))
    Assert-Equal 1 $missing.Exit 'a missing manifest did not exit 1'

    # 11. The script parses.
    $errors = $null; $tokens = $null
    [Management.Automation.Language.Parser]::ParseFile($script, [ref]$tokens, [ref]$errors) | Out-Null
    Assert-Equal 0 $errors.Count 'apply-environments.ps1 does not parse'
}
finally {
    $env:PATH = $savedPath
    $env:AZURE_CLIENT_ID = $savedDecoy
    [Environment]::SetEnvironmentVariable('GH_SHIM_LOG', $null)
    [Environment]::SetEnvironmentVariable('GH_SHIM_BODY', $null)
    [Environment]::SetEnvironmentVariable('GH_SHIM_CASE', $null)
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Passed $($script:cases) offline apply-environments cases."
exit 0
