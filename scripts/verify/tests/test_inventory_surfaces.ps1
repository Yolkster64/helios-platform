# Offline contract suite for scripts/github/inventory-surfaces.ps1.
#
# The inventory answers one question - of everything this repository declares about itself,
# what is actually a CONTROL right now? - so the properties under test are about what it SAYS.
# It changes nothing, and a mutating call from an inventory would be a defect all by itself.
#
# The load-bearing property is the one that is easy to get wrong in the reassuring direction:
# an unreadable answer must read as `unknown`, never as `absent`. Reporting a 403 as absent
# would send the owner to create a ruleset or an environment that already exists.
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

$temp = Join-Path ([IO.Path]::GetTempPath()) ('helios-inventory-' + [guid]::NewGuid())
$bin = Join-Path $temp 'bin'
$emptyBin = Join-Path $temp 'emptybin'
$config = Join-Path $temp 'config'
$rulesets = Join-Path $temp 'rulesets'
foreach ($dir in @($bin, $emptyBin, $config, $rulesets)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$log = Join-Path $temp 'gh.log'
$savedPath = $env:PATH
$script = Join-Path $root 'scripts/github/inventory-surfaces.ps1'
$realPwsh = [Environment]::ProcessPath
if (-not $realPwsh) { $realPwsh = 'pwsh' }
$savedDecoy = $env:AZURE_CLIENT_ID

'{ "name": "main", "target": "branch", "rules": [] }' |
    Set-Content -LiteralPath (Join-Path $rulesets 'main.json') -Encoding utf8
'{ "environments": [ { "name": "production" } ] }' |
    Set-Content -LiteralPath (Join-Path $config 'environments.json') -Encoding utf8
'{ "labels": [ { "name": "automerge" }, { "name": "hygiene" } ] }' |
    Set-Content -LiteralPath (Join-Path $config 'labels.json') -Encoding utf8
'{ "milestones": [ { "title": "Control fabric" } ] }' |
    Set-Content -LiteralPath (Join-Path $config 'milestones.json') -Encoding utf8

function Invoke-Inventory {
    param([string[]]$Arguments = @(), [string]$Case = 'all-in-force', [string]$PathOverride)
    Set-Content -LiteralPath $log -Value '' -NoNewline
    $env:GH_SHIM_CASE = $Case
    $previousPath = $env:PATH
    if ($PathOverride) { $env:PATH = $PathOverride }
    try {
        $argv = @('-NoProfile', '-File', $script, '-ConfigDirectory', $config,
                  '-RulesetDirectory', $rulesets) + $Arguments
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
repo_on='{"allow_auto_merge":true,"has_wiki":true,"delete_branch_on_merge":true}'
repo_off='{"allow_auto_merge":false,"has_wiki":true,"delete_branch_on_merge":true}'
for arg in "$@"; do
  case "$arg" in
    */rulesets|*/rulesets\?*)
      case "${GH_SHIM_CASE:-all-in-force}" in
        # Nothing is applied - the ordinary state of this repository today.
        no-rulesets)  printf 'HTTP/2.0 200 OK\n\n[]\n'; exit 0 ;;
        # A 403 is NOT evidence of absence. Reported as absent it would send the owner to
        # create a ruleset that already exists.
        rulesets-403) printf 'HTTP/2.0 403 Forbidden\n\n{"message":"Resource not accessible"}\n'; exit 1 ;;
        # GET /rulesets lists ORG rulesets too. One of those is not ours and cannot be
        # reconciled from this repository, so it must not satisfy `main`.
        org-ruleset)  printf 'HTTP/2.0 200 OK\n\n[{"name":"main","source_type":"Organization"}]\n'; exit 0 ;;
        *)            printf 'HTTP/2.0 200 OK\n\n[{"name":"main","source_type":"Repository"}]\n'; exit 0 ;;
      esac ;;
    */environments|*/environments\?*)
      case "${GH_SHIM_CASE:-all-in-force}" in
        no-environment) printf 'HTTP/2.0 200 OK\n\n{"environments":[]}\n'; exit 0 ;;
        *)              printf 'HTTP/2.0 200 OK\n\n{"environments":[{"name":"production"}]}\n'; exit 0 ;;
      esac ;;
    */labels|*/labels\?*)
      case "${GH_SHIM_CASE:-all-in-force}" in
        # One of two declared labels exists: partial, not absent, and it must name the one
        # that is missing rather than the count alone.
        partial-labels) printf 'HTTP/2.0 200 OK\n\n[{"name":"automerge"}]\n'; exit 0 ;;
        *)              printf 'HTTP/2.0 200 OK\n\n[{"name":"automerge"},{"name":"hygiene"}]\n'; exit 0 ;;
      esac ;;
    # GitHub defaults this endpoint to state=open, so a query without state=all answers []
    # here exactly as it would live - which is what makes "a closed milestone still exists"
    # a testable property rather than an assumption.
    *state=all*)  printf 'HTTP/2.0 200 OK\n\n[{"title":"Control fabric","state":"closed"}]\n'; exit 0 ;;
    */milestones|*/milestones\?*)
      printf 'HTTP/2.0 200 OK\n\n[]\n'; exit 0 ;;
    */pages)
      case "${GH_SHIM_CASE:-all-in-force}" in
        # GitHub's own 404 body is the ONLY thing that means "no site".
        no-pages)     printf 'HTTP/2.0 404 Not Found\n\n{"message":"Not Found","status":"404"}\n'; exit 1 ;;
        # This proxy answers 403 on this endpoint. Read as absence it would tell the owner to
        # POST a site that already exists, which answers 409.
        pages-403)    printf 'HTTP/2.0 403 Forbidden\n\n{"message":"not permitted through this proxy"}\n'; exit 1 ;;
        # The site exists but deploys from a branch, not the workflow that builds the
        # dashboard. Enabled-but-wrong is partial; it is not absence.
        pages-branch) printf 'HTTP/2.0 200 OK\n\n{"build_type":"legacy"}\n'; exit 0 ;;
        *)            printf 'HTTP/2.0 200 OK\n\n{"build_type":"workflow"}\n'; exit 0 ;;
      esac ;;
    # `repos/OWNER/NAME` with no leading slash, so `*/repos/*` would NOT match it and the
    # repository read would fall through to `{}` - which the script would then correctly
    # report as "carries no allow_auto_merge". Last in the case: the endpoint patterns above
    # are more specific and are tried first.
    repos/*/*)
      case "${GH_SHIM_CASE:-all-in-force}" in
        repo-500)   printf 'HTTP/2.0 500 Server Error\n\n{}\n'; exit 1 ;;
        automerge-off) printf 'HTTP/2.0 200 OK\n\n%s\n' "$repo_off"; exit 0 ;;
        *)          printf 'HTTP/2.0 200 OK\n\n%s\n' "$repo_on"; exit 0 ;;
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

    # 1. Everything declared exists. This is the state the repository is working towards, and
    #    the only one that exits 0.
    $ok = Invoke-Inventory -Case 'all-in-force'
    Assert-Equal 0 $ok.Exit 'a fully applied repository did not exit 0'
    Assert-True ($ok.Out -match 'Every surface this repository declares is in force') 'the clean verdict was not printed'
    Assert-True ($ok.Out -notmatch 'absent') 'a clean repository reported something absent'
    # An inventory that writes is a defect on its own.
    Assert-True ($ok.Log -notmatch '--method') 'the inventory made a mutating call'

    # 2. The state today: main.json declares a ruleset and none exists.
    $none = Invoke-Inventory -Case 'no-rulesets'
    Assert-Equal 2 $none.Exit 'an unapplied ruleset did not exit 2'
    Assert-True ($none.Out -match 'rulesets\s+absent') 'the absent ruleset was not reported'
    Assert-True ($none.Out -match 'main') 'the absent ruleset was not named'
    Assert-True ($none.Out -match 'apply-rulesets\.ps1') 'the reconciler that owns it was not named'

    # 3. THE property worth having: an unreadable answer is `unknown`, never `absent`.
    #    Reported as absent, this row would send the owner to create what may already exist.
    $forbidden = Invoke-Inventory -Case 'rulesets-403'
    Assert-Equal 2 $forbidden.Exit 'an unreadable surface did not exit 2'
    Assert-True ($forbidden.Out -match 'rulesets\s+unknown') 'a 403 was not reported as unknown'
    Assert-True ($forbidden.Out -match 'HTTP 403') 'the status behind the unknown was not reported'
    Assert-True ($forbidden.Out -notmatch 'rulesets\s+absent') 'a 403 was reported as absence'

    # 4. GET /rulesets lists org rulesets too. One of those does not make ours applied.
    $org = Invoke-Inventory -Case 'org-ruleset'
    Assert-Equal 2 $org.Exit 'an org ruleset was counted as this repository''s'
    Assert-True ($org.Out -match 'rulesets\s+absent') 'an org-owned ruleset satisfied a repository declaration'

    # 5. Some but not all: partial, naming the one that is missing.
    $partial = Invoke-Inventory -Case 'partial-labels'
    Assert-Equal 2 $partial.Exit 'a partial surface did not exit 2'
    Assert-True ($partial.Out -match 'labels\s+partial') 'the partial state was not reported'
    Assert-True ($partial.Out -match 'hygiene') 'the missing label was not named'
    Assert-True ($partial.Out -notmatch 'labels\s+absent') 'a partial surface was reported as wholly absent'

    # 6. A closed milestone still EXISTS. Reporting it absent would ask for a duplicate.
    Assert-True ($ok.Out -match 'milestones\s+in-force') 'a closed milestone was reported absent'

    # 7. Scalar settings come from the repository object already read - one call, no way for
    #    two reads to disagree.
    $offRun = Invoke-Inventory -Case 'automerge-off'
    Assert-Equal 2 $offRun.Exit 'a disabled setting did not exit 2'
    Assert-True ($offRun.Out -match 'settings:auto-merge\s+absent') 'allow_auto_merge=false was not reported'
    Assert-True ($offRun.Out -match 'settings:wiki\s+in-force') 'an enabled setting was misreported'

    # 7b. Pages is the one setting that is not a field on the repository object, so it has its
    #     own call and its own three answers. The 404-only rule is apply-repo-settings.ps1's,
    #     copied deliberately: any other failed read is unreadable, not absent.
    Assert-True ($ok.Out -match 'settings:pages\s+in-force') 'a workflow-sourced Pages site was not reported in force'

    $noPages = Invoke-Inventory -Case 'no-pages'
    Assert-Equal 2 $noPages.Exit 'an absent Pages site did not exit 2'
    Assert-True ($noPages.Out -match 'settings:pages\s+absent') 'GitHub''s own 404 was not read as absence'

    $pages403 = Invoke-Inventory -Case 'pages-403'
    Assert-Equal 2 $pages403.Exit 'an unreadable Pages endpoint did not exit 2'
    Assert-True ($pages403.Out -match 'settings:pages\s+unknown') 'a 403 on pages was not reported as unknown'
    Assert-True ($pages403.Out -notmatch 'settings:pages\s+absent') 'a 403 on pages was reported as absence'

    $pagesBranch = Invoke-Inventory -Case 'pages-branch'
    Assert-True ($pagesBranch.Out -match 'settings:pages\s+partial') 'a branch-sourced Pages site was not reported partial'
    Assert-True ($pagesBranch.Out -notmatch 'settings:pages\s+absent') 'an existing Pages site was reported absent'

    # 8. Not being able to run at all is exit 1, distinct from "ran and found gaps" (2). A
    #    report nobody can trust must not look like a report of gaps.
    $noGh = Invoke-Inventory -Case 'all-in-force' -PathOverride $emptyBin
    Assert-Equal 1 $noGh.Exit 'a missing gh did not exit 1'
    Assert-True ($noGh.Out -match 'gh is not on PATH') 'the missing gh was not reported'

    $dead = Invoke-Inventory -Case 'repo-500'
    Assert-Equal 1 $dead.Exit 'an unreadable repository did not exit 1'
    Assert-True ($dead.Out -notmatch 'absent') 'an unreadable repository reported surfaces as absent'

    # 9. -Json carries the same verdict as the table.
    $okJson = (Invoke-Inventory -Arguments @('-Json') -Case 'all-in-force').Out | ConvertFrom-Json
    Assert-Equal 'all-in-force' $okJson.state '-Json disagreed with the table about a clean repository'
    Assert-Equal 0 $okJson.gaps '-Json reported gaps on a clean repository'
    $gapRun = Invoke-Inventory -Arguments @('-Json') -Case 'no-rulesets'
    $gapJson = $gapRun.Out | ConvertFrom-Json
    Assert-Equal 'gaps' $gapJson.state '-Json did not record the gap'
    Assert-True (@($gapJson.surfaces | Where-Object { $_.surface -eq 'rulesets' }).Count -eq 1) '-Json lost the rulesets row'
    Assert-Equal 2 $gapRun.Exit '-Json changed the exit code'

    # 10. No secret VALUE anywhere in any of it.
    $allOutput = $ok.Out + $none.Out + $forbidden.Out + $org.Out + $partial.Out + $offRun.Out +
                 $noGh.Out + $dead.Out + $gapRun.Out
    Assert-True ($allOutput -notmatch [regex]::Escape($decoy)) 'a secret VALUE reached the output'
    foreach ($shape in 'ghp_', 'github_pat_', 'sk-') {
        Assert-True ($allOutput -notmatch [regex]::Escape($shape)) "output contained a secret-shaped string: $shape"
    }

    # 11. The script parses.
    $errors = $null; $tokens = $null
    [Management.Automation.Language.Parser]::ParseFile($script, [ref]$tokens, [ref]$errors) | Out-Null
    Assert-Equal 0 $errors.Count 'inventory-surfaces.ps1 does not parse'
}
finally {
    $env:PATH = $savedPath
    $env:AZURE_CLIENT_ID = $savedDecoy
    [Environment]::SetEnvironmentVariable('GH_SHIM_LOG', $null)
    [Environment]::SetEnvironmentVariable('GH_SHIM_CASE', $null)
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Passed $($script:cases) offline inventory-surfaces cases."
exit 0
