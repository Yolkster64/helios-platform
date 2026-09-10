# Offline contract suite for scripts/github/audit-main-commit.ps1.
#
# The audit exists because .github/rulesets/main.json is NOT applied: creating it needs
# repository administration no workflow token has, so every rule in it is currently a
# description rather than a control. This script asks after the fact what the ruleset would
# have asked before it, and its whole product is the report - so the properties under test are
# about what it SAYS, not about anything it changes. It changes nothing; a mutating call from
# an auditor would be a defect all by itself.
#
# Its posture is the opposite of verify-environment-gate.ps1 on purpose. That one gates a
# deployment before it happens and refuses when it cannot tell. This one runs after a push has
# already landed, where a 5xx that reds main teaches people to ignore the signal - so an
# unreadable answer is `unknown` and exit 0, and only a real bypass is exit 1.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$script:cases = 0

function Assert-True($Value, $Message) { if (-not $Value) { throw $Message }; $script:cases++ }
function Assert-Equal($Expected, $Actual, $Message) {
    if ($Expected -ne $Actual) { throw "$Message (expected '$Expected', got '$Actual')" }
    $script:cases++
}

if ($IsWindows) {
    Write-Host 'SKIPPED: this suite shims gh with a bash script, so it needs a POSIX shell.'
    exit 0
}

$temp = Join-Path ([IO.Path]::GetTempPath()) ('helios-mainaudit-' + [guid]::NewGuid())
$bin = Join-Path $temp 'bin'
$emptyBin = Join-Path $temp 'emptybin'
$rulesets = Join-Path $temp 'rulesets'
foreach ($dir in @($bin, $emptyBin, $rulesets)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$log = Join-Path $temp 'gh.log'
$savedPath = $env:PATH
$script = Join-Path $root 'scripts/github/audit-main-commit.ps1'
$realPwsh = [Environment]::ProcessPath
if (-not $realPwsh) { $realPwsh = 'pwsh' }
$savedDecoy = $env:AZURE_CLIENT_ID

# One ruleset, gating main, requiring two contexts - one reported as a check run and one as a
# legacy commit status, because a required context can be either and reading one surface only
# would call a green check missing.
@'
{
  "name": "main",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/heads/main"], "exclude": [] } },
  "bypass_actors": [],
  "rules": [
    { "type": "required_status_checks",
      "parameters": { "required_status_checks": [ { "context": "Build solution & run tests" }, { "context": "legacy status" } ] } }
  ]
}
'@ | Set-Content -LiteralPath (Join-Path $rulesets 'main.json') -Encoding utf8

# A second ruleset that gates a DIFFERENT branch: its contexts must not be demanded here.
@'
{
  "name": "release",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/heads/release/v9"], "exclude": [] } },
  "bypass_actors": [],
  "rules": [
    { "type": "required_status_checks",
      "parameters": { "required_status_checks": [ { "context": "never demanded on main" } ] } }
  ]
}
'@ | Set-Content -LiteralPath (Join-Path $rulesets 'release.json') -Encoding utf8

function Invoke-Audit {
    param([string[]]$Arguments = @(), [string]$Case = 'reviewed', [string]$PathOverride)
    Set-Content -LiteralPath $log -Value '' -NoNewline
    $env:GH_SHIM_CASE = $Case
    $previousPath = $env:PATH
    if ($PathOverride) { $env:PATH = $PathOverride }
    try {
        # -RetryDelaySeconds 0: the retry BEHAVIOUR is under test, its wall-clock is not.
        $argv = @('-NoProfile', '-File', $script, '-RulesetDirectory', $rulesets,
                  '-Sha', 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef', '-RetryDelaySeconds', '0') + $Arguments
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
    @'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >> "$GH_SHIM_LOG"
pr_green='[{"number":42,"merged_at":"2026-09-10T01:00:00Z","head":{"sha":"feedfacefeedfacefeedfacefeedfacefeedface"}}]'
checks_green='{"check_runs":[{"name":"Build solution & run tests","conclusion":"success"}]}'
status_green='{"statuses":[{"context":"legacy status","state":"success"}]}'
for arg in "$@"; do
  case "$arg" in
    */pulls)
      case "${GH_SHIM_CASE:-reviewed}" in
        # A direct push: no pull request references this commit at all.
        direct-push)  printf 'HTTP/2.0 200 OK\n\n[]\n'; exit 0 ;;
        # A pull request exists but was never merged - the commit did not come through it.
        open-pr)      printf 'HTTP/2.0 200 OK\n\n[{"number":7,"merged_at":null,"head":{"sha":"feedfacefeedfacefeedfacefeedfacefeedface"}}]\n'; exit 0 ;;
        # The association GitHub indexes asynchronously: empty on the first read, there on the
        # second. Believing the first answer would report a bypass on an ordinary merge.
        late-pulls)
          if [ "$(grep -c '/pulls' "$GH_SHIM_LOG")" -le 1 ]; then printf 'HTTP/2.0 200 OK\n\n[]\n'
          else printf 'HTTP/2.0 200 OK\n\n%s\n' "$pr_green"; fi
          exit 0 ;;
        pulls-5xx)    printf 'HTTP/2.0 500 Server Error\n\n{}\n'; exit 1 ;;
        # A 200 whose body does not parse. Read as "no pull requests" this would accuse a
        # properly reviewed commit; `[]` is how GitHub actually says "none", and that parses.
        pulls-garbage) printf 'HTTP/2.0 200 OK\n\n<html>maintenance</html>\n'; exit 0 ;;
        no-head)      printf 'HTTP/2.0 200 OK\n\n[{"number":9,"merged_at":"2026-09-10T01:00:00Z","head":{}}]\n'; exit 0 ;;
        *)            printf 'HTTP/2.0 200 OK\n\n%s\n' "$pr_green"; exit 0 ;;
      esac ;;
    */check-runs|*/check-runs\?*)
      case "${GH_SHIM_CASE:-reviewed}" in
        # The build check is RED on the head the pull request merged from.
        red-check)    printf 'HTTP/2.0 200 OK\n\n{"check_runs":[{"name":"Build solution & run tests","conclusion":"failure"}]}\n'; exit 0 ;;
        # Skipped counts: GitHub treats a skipped required check as satisfied, which is why
        # the workflows owning these contexts trigger on every PR and skip the work inside.
        skipped)      printf 'HTTP/2.0 200 OK\n\n{"check_runs":[{"name":"Build solution & run tests","conclusion":"skipped"}]}\n'; exit 0 ;;
        checks-5xx)   printf 'HTTP/2.0 500 Server Error\n\n{}\n'; exit 1 ;;
        # More check runs exist than this page carried. Reporting the contexts as missing
        # here would be a false accusation on main; the honest answer is "not audited".
        truncated)    printf 'HTTP/2.0 200 OK\n\n{"total_count":137,"check_runs":[{"name":"Build solution & run tests","conclusion":"success"}]}\n'; exit 0 ;;
        checks-garbage) printf 'HTTP/2.0 200 OK\n\n<html>maintenance</html>\n'; exit 0 ;;
        # Both required contexts arrive as check runs here, so an unreadable status list below
        # cannot change the verdict and must not downgrade it.
        both-as-checks) printf 'HTTP/2.0 200 OK\n\n{"check_runs":[{"name":"Build solution & run tests","conclusion":"success"},{"name":"legacy status","conclusion":"success"}]}\n'; exit 0 ;;
        *)            printf 'HTTP/2.0 200 OK\n\n%s\n' "$checks_green"; exit 0 ;;
      esac ;;
    */status|*/status\?*)
      case "${GH_SHIM_CASE:-reviewed}" in
        # The legacy commit status is missing entirely.
        no-legacy)    printf 'HTTP/2.0 200 OK\n\n{"statuses":[]}\n'; exit 0 ;;
        # Unreadable, in the three ways it can be: a 5xx, a body that does not parse, and a
        # page that carried fewer statuses than the server says exist.
        status-5xx|both-as-checks) printf 'HTTP/2.0 500 Server Error\n\n{}\n'; exit 1 ;;
        status-garbage) printf 'HTTP/2.0 200 OK\n\n<html>maintenance</html>\n'; exit 0 ;;
        status-truncated) printf 'HTTP/2.0 200 OK\n\n{"total_count":9,"statuses":[]}\n'; exit 0 ;;
        *)            printf 'HTTP/2.0 200 OK\n\n%s\n' "$status_green"; exit 0 ;;
      esac ;;
  esac
done
printf 'HTTP/2.0 200 OK\n\n{}\n'
exit 0
'@ -replace "`r`n", "`n" | Set-Content -LiteralPath (Join-Path $bin 'gh') -NoNewline -Encoding utf8
    & chmod +x (Join-Path $bin 'gh')

    $env:GH_SHIM_LOG = $log
    $env:PATH = "$bin$([IO.Path]::PathSeparator)$savedPath"
    $decoy = 'ghp_' + ('F' * 32)
    $env:AZURE_CLIENT_ID = $decoy

    # 1. The ordinary case: merged pull request, every required context green across BOTH
    #    surfaces. This is what every merge in this repository should look like.
    $ok = Invoke-Audit -Case 'reviewed'
    Assert-Equal 0 $ok.Exit 'a properly reviewed commit was reported as a bypass'
    Assert-True ($ok.Out -match 'OK: pull request #42') 'the pull request was not named'
    Assert-True ($ok.Out -match 'all 2 required context\(s\) reported success') 'the context count was not reported'
    Assert-True ($ok.Out -notmatch 'BYPASS') 'a clean commit was reported as a bypass'
    # An auditor that writes is a defect on its own.
    Assert-True ($ok.Log -notmatch '--method') 'the audit made a mutating call'
    # The other ruleset gates release/v9, so its context must not be demanded here - two
    # required, not three.
    Assert-True ($ok.Out -match 'requires 2 context\(s\) on main') `
        'a ruleset gating another branch had its contexts demanded on main'
    Assert-True ($ok.Out -notmatch 'never demanded on main') 'a foreign ruleset''s context leaked in'

    # 2. A direct push - the case the ruleset exists to prevent and currently cannot.
    $direct = Invoke-Audit -Case 'direct-push'
    Assert-Equal 1 $direct.Exit 'a commit pushed straight to main was not reported'
    Assert-True ($direct.Out -match 'BYPASS: commit deadbeef') 'the bypass did not name the commit'
    Assert-True ($direct.Out -match 'without a merged pull request') 'the reason was not stated'

    # 2b. ...but an empty FIRST answer is not proof of one. GitHub indexes the commit-to-pull
    #     -request association asynchronously and this runs seconds after the push, so the
    #     empty answer is re-read before it is believed. Here it is empty once and present on
    #     the second read: an ordinary merge, and it must be reported as one.
    $late = Invoke-Audit -Case 'late-pulls'
    Assert-Equal 0 $late.Exit 'a merge whose pull request was not indexed yet was reported as a bypass'
    Assert-True ($late.Out -match 'no pull request is associated with this commit yet') 'the re-read was not reported'
    Assert-True ($late.Out -match 'OK: pull request #42') 'the re-read did not reach the verdict'
    Assert-True ($late.Out -notmatch 'BYPASS') 'an indexing delay was reported as a bypass'
    # The direct push above must have exhausted the same re-reads rather than skipped them:
    # three /pulls reads, not one.
    Assert-True (@(($direct.Log -split "`n") | Where-Object { $_ -match '/pulls' }).Count -ge 3) `
        'the empty answer was believed on the first read'

    # 3. A pull request that exists but was never merged does not count as review. Reading
    #    only "is there a PR?" would pass this.
    $open = Invoke-Audit -Case 'open-pr'
    Assert-Equal 1 $open.Exit 'an unmerged pull request counted as review'
    Assert-True ($open.Out -match 'without a merged pull request') 'the unmerged case was not reported'

    # 4. Merged, but a required context was RED on the head.
    $red = Invoke-Audit -Case 'red-check'
    Assert-Equal 1 $red.Exit 'a merge with a failing required context was not reported'
    Assert-True ($red.Out -match 'without 1 required context') 'the missing count was not reported'
    Assert-True ($red.Out -match 'Build solution & run tests') 'the missing context was not named'

    # 5. Merged, but the legacy commit status never reported. Reading only check runs would
    #    miss this, and reading only statuses would miss case 4.
    $legacy = Invoke-Audit -Case 'no-legacy'
    Assert-Equal 1 $legacy.Exit 'a missing legacy status was not reported'
    Assert-True ($legacy.Out -match 'legacy status') 'the missing legacy context was not named'

    # 6. `skipped` is success. Not a loophole - GitHub itself treats a skipped required check
    #    as satisfied, which is the whole reason those workflows trigger on every pull request
    #    and skip the work in a job-level if:. Reading it as a failure would report a bypass on
    #    every docs-only merge in this repository.
    $skipped = Invoke-Audit -Case 'skipped'
    Assert-Equal 0 $skipped.Exit 'a skipped required check was reported as a bypass'

    # 7. Every way of not being able to tell is `unknown` and exit 0 - the opposite of
    #    verify-environment-gate.ps1, and deliberately so: this runs after the push, where a
    #    red main for a transient 5xx trains people to ignore the signal.
    #    Each row must also stay OUT of the accusing direction: an answer that could not be
    #    read is not evidence of a bypass, and printing one would be a false accusation on main.
    foreach ($row in @(
        @{ Case = 'pulls-5xx';        Match = 'could not read the pull requests' },
        @{ Case = 'pulls-garbage';    Match = 'pull request list did not parse' },
        @{ Case = 'checks-5xx';       Match = 'could not read the check runs' },
        @{ Case = 'checks-garbage';   Match = 'check-run list did not parse' },
        @{ Case = 'no-head';          Match = 'no head sha' },
        @{ Case = 'truncated';        Match = '137 check runs and one page carried' },
        @{ Case = 'status-5xx';       Match = 'legacy commit statuses could not be read' },
        @{ Case = 'status-garbage';   Match = 'legacy commit statuses could not be read' },
        @{ Case = 'status-truncated'; Match = 'legacy commit statuses could not be read' }
    )) {
        $unknown = Invoke-Audit -Case $row.Case
        Assert-Equal 0 $unknown.Exit "$($row.Case) failed the run instead of reporting unknown"
        Assert-True ($unknown.Out -match $row.Match) "$($row.Case) was not reported"
        Assert-True ($unknown.Out -notmatch 'BYPASS') "$($row.Case) accused the commit of a bypass it could not see"
    }

    #    ...but only when it changes the answer. With both required contexts green as check
    #    runs, an unreadable status list accounts for nothing and the clean verdict stands.
    $statusMoot = Invoke-Audit -Case 'both-as-checks'
    Assert-Equal 0 $statusMoot.Exit 'an unreadable status list downgraded an already-complete verdict'
    Assert-True ($statusMoot.Out -match 'OK: pull request #42') 'the clean verdict was not reported'
    Assert-True ($statusMoot.Out -notmatch 'not audited') 'an irrelevant unreadable status list was reported as doubt'

    $noGh = Invoke-Audit -Case 'reviewed' -PathOverride $emptyBin
    Assert-Equal 0 $noGh.Exit 'a missing gh failed the run instead of reporting unknown'
    Assert-True ($noGh.Out -match 'could not be audited') 'the missing gh was not reported'

    # 8. -Json carries the same verdict as the lines.
    $okJson = (Invoke-Audit -Arguments @('-Json') -Case 'reviewed').Out | ConvertFrom-Json
    Assert-Equal 'reviewed' $okJson.state '-Json disagreed with the table about a clean commit'
    $bypassRun = Invoke-Audit -Arguments @('-Json') -Case 'red-check'
    $bypassJson = $bypassRun.Out | ConvertFrom-Json
    Assert-Equal 'missing-checks' $bypassJson.state '-Json did not record the bypass'
    Assert-Equal 1 @($bypassJson.missing).Count '-Json did not carry the missing contexts'
    Assert-Equal 1 $bypassRun.Exit '-Json changed the exit code'

    # 9. No secret VALUE anywhere in any of it.
    $allOutput = $ok.Out + $direct.Out + $open.Out + $red.Out + $legacy.Out + $skipped.Out +
                 $noGh.Out + $bypassRun.Out
    Assert-True ($allOutput -notmatch [regex]::Escape($decoy)) 'a secret VALUE reached the output'
    foreach ($shape in 'ghp_', 'github_pat_', 'sk-') {
        Assert-True ($allOutput -notmatch [regex]::Escape($shape)) "output contained a secret-shaped string: $shape"
    }

    # 10. The script parses.
    $errors = $null; $tokens = $null
    [Management.Automation.Language.Parser]::ParseFile($script, [ref]$tokens, [ref]$errors) | Out-Null
    Assert-Equal 0 $errors.Count 'audit-main-commit.ps1 does not parse'
}
finally {
    $env:PATH = $savedPath
    $env:AZURE_CLIENT_ID = $savedDecoy
    [Environment]::SetEnvironmentVariable('GH_SHIM_LOG', $null)
    [Environment]::SetEnvironmentVariable('GH_SHIM_CASE', $null)
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Passed $($script:cases) offline audit-main-commit cases."
exit 0
