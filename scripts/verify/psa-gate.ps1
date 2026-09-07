#Requires -Version 7
<#
.SYNOPSIS
  PSScriptAnalyzer gate for quality.yml (powershell-lint): Error-severity findings and
  analyzer failures outside the legacy baseline fail the job; warnings are advisory.

.DESCRIPTION
  Runs Invoke-ScriptAnalyzer (-Severity Error, Warning) file by file over every .ps1,
  .psm1 and .psd1 under the given roots. Invoke-ScriptAnalyzer's -Path parameter is a single string, so the two roots are
  enumerated here instead of being passed as one array (the workflow's previous
  invocation failed to bind and its continue-on-error hid that on every run).

  Verdict rules:
    - Error-severity records are counted per "<path>|<rule>"; a baseline line
      "<path>|<rule>|<count>" tolerates exactly that many occurrences (a missing count
      means 1). More occurrences than tolerated → fail, naming the extra lines, so a
      second plaintext ConvertTo-SecureString in an already-listed file is still caught.
      Fewer → notice to lower the count.
    - a file the analyzer throws on is tolerated only by a
      "<path>|analyzer-exception|<sha256>" line whose hash matches the file's current
      content: the analyzer cannot see anything in such a file, so the only way to keep a
      new finding out of it is to freeze it — any edit changes the hash and fails the gate
      until the file is repaired (line deleted) or consciously re-baselined. A crash on an
      unlisted file fails (a tool failure is not a clean file).
    - every Warning-severity record → advisory: counted, written to the artifact, never
      failing (the legacy corpus carries thousands; the parser baseline gate in
      ci-validation.yml is the enforced syntax check)
    - a baseline line that no longer triggers → notice to delete it (never a failure)

  Exit codes: 0 gate passed, 1 new Error-severity finding or analyzer failure,
  2 PSScriptAnalyzer not importable. Writes the full record list to -OutputPath and a
  short table to $GITHUB_STEP_SUMMARY when that variable is set; emits ::error
  annotations under GitHub Actions.
#>
[CmdletBinding()]
param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path,
    [string[]]$Paths = @('src', 'scripts'),
    [string]$BaselinePath = '.github/psa-baseline.txt',
    [string]$OutputPath = 'ps-analysis.txt'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# A relative or forward-slash root must resolve to the same prefix the analyzer reports,
# otherwise every relative path misses the baseline and the gate fails in the wrong direction.
$Root = [IO.Path]::GetFullPath($Root)

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    Write-Host 'PSScriptAnalyzer is not installed: Install-Module -Name PSScriptAnalyzer -RequiredVersion 1.25.0 -Scope CurrentUser -Force'
    exit 2
}
Import-Module PSScriptAnalyzer
$onActions = [bool]$env:GITHUB_ACTIONS

$baselineFile = if ([IO.Path]::IsPathRooted($BaselinePath)) { $BaselinePath } else { Join-Path $Root $BaselinePath }
# key = "<path>|<rule>" or "<path>|analyzer-exception"; value = @{ Tolerated = n; Seen = n; Hash = <sha256 or $null> }
$baseline = @{}
if (Test-Path -LiteralPath $baselineFile) {
    Get-Content -LiteralPath $baselineFile | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith('#')) { return }
        $parts = $line.Split('|')
        if ($parts.Count -lt 2 -or $parts.Count -gt 3) { throw "psa-gate: malformed baseline line '$line' (expected <path>|<rule>[|<count>] or <path>|analyzer-exception|<sha256>)" }
        $tolerated = 1; $hash = $null
        if ($parts[1] -eq 'analyzer-exception') {
            if ($parts.Count -ne 3 -or $parts[2] -notmatch '^[0-9a-fA-F]{64}$') { throw "psa-gate: analyzer-exception lines need the file's sha256: '$line'" }
            $hash = $parts[2].ToLowerInvariant()
        } elseif ($parts.Count -eq 3) {
            if (-not [int]::TryParse($parts[2], [ref]$tolerated) -or $tolerated -lt 1) { throw "psa-gate: count must be a positive integer: '$line'" }
        }
        $baseline["$($parts[0])|$($parts[1])"] = @{ Tolerated = $tolerated; Seen = 0; Hash = $hash }
    }
}

$files = foreach ($p in $Paths) {
    $dir = Join-Path $Root $p
    if (Test-Path -LiteralPath $dir) { Get-ChildItem -LiteralPath $dir -Recurse -File | Where-Object { $_.Extension -in '.ps1', '.psm1', '.psd1' } }
}
$files = @($files | Sort-Object FullName)
$rootPrefix = $Root.TrimEnd('/', '\') + [IO.Path]::DirectorySeparatorChar
function Get-RelPath([string]$fullPath) { [IO.Path]::GetRelativePath($Root, $fullPath).Replace('\', '/') }

$records = New-Object System.Collections.Generic.List[object]
$exceptions = New-Object System.Collections.Generic.List[string]
$failures = New-Object System.Collections.Generic.List[string]
foreach ($f in $files) {
    $rel = Get-RelPath $f.FullName
    try {
        $r = Invoke-ScriptAnalyzer -Path $f.FullName -Severity Error, Warning -ErrorAction Stop
        if ($r) { $records.AddRange(@($r)) }
    } catch {
        $key = "$rel|analyzer-exception"
        $first = $_.Exception.Message.Split("`n")[0]
        $exceptions.Add("$rel : $first")
        if ($baseline.ContainsKey($key)) {
            $baseline[$key].Seen++
            $actual = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actual -ne $baseline[$key].Hash) {
                $failures.Add("$rel : changed since it was baselined as unanalyzable (sha256 $actual) — the analyzer cannot check the edit; repair the file and delete its baseline line, or re-baseline it deliberately")
                if ($onActions) { Write-Host "::error file=$rel::baselined as unanalyzable but its content changed (sha256 $actual); repair it or re-baseline deliberately" }
            }
        }
        else { $failures.Add("$rel : PSScriptAnalyzer threw ($first)") ; if ($onActions) { Write-Host "::error file=$rel::PSScriptAnalyzer threw: $first" } }
    }
}

$errorRecords = @($records | Where-Object Severity -eq 'Error')
$warningRecords = @($records | Where-Object Severity -eq 'Warning')
# Occurrences are consumed in file order: the first <count> for a listed (path, rule) are
# tolerated, every further one fails with its own line number.
foreach ($e in ($errorRecords | Sort-Object ScriptPath, Line)) {
    $rel = Get-RelPath $e.ScriptPath
    $key = "$rel|$($e.RuleName)"
    if ($baseline.ContainsKey($key)) {
        $baseline[$key].Seen++
        if ($baseline[$key].Seen -le $baseline[$key].Tolerated) { continue }
        $failures.Add(("{0}:{1} {2} — occurrence {3} of a rule the baseline tolerates {4} time(s) in this file; {5}" -f $rel, $e.Line, $e.RuleName, $baseline[$key].Seen, $baseline[$key].Tolerated, $e.Message))
        if ($onActions) { Write-Host ("::error file={0},line={1}::{2}: occurrence {3} exceeds the {4} the baseline tolerates for this file" -f $rel, $e.Line, $e.RuleName, $baseline[$key].Seen, $baseline[$key].Tolerated) }
        continue
    }
    $failures.Add(("{0}:{1} {2} — {3}" -f $rel, $e.Line, $e.RuleName, $e.Message))
    if ($onActions) { Write-Host ("::error file={0},line={1}::{2}: {3}" -f $rel, $e.Line, $e.RuleName, $e.Message) }
}
# stale = a line that no longer triggers at all, or tolerates more than the file still trips
$stale = @($baseline.GetEnumerator() | Where-Object { $_.Value.Seen -lt $_.Value.Tolerated } | ForEach-Object {
    if ($_.Value.Seen -eq 0) { "{0} (no longer triggers — delete the line)" -f $_.Key } else { "{0} (tolerates {1}, now {2} — lower the count)" -f $_.Key, $_.Value.Tolerated, $_.Value.Seen } } | Sort-Object)
$newExceptions = @($failures | Where-Object { $_ -like '* : PSScriptAnalyzer threw*' -or $_ -like '* : changed since it was baselined*' }).Count
$newErrors = $failures.Count - $newExceptions

$outFile = if ([IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $Root $OutputPath }
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add(("PSScriptAnalyzer gate: {0} files; {1} error-severity ({2} outside the baseline); {3} warnings (advisory); {4} analyzer exceptions ({5} outside the baseline)" -f $files.Count, $errorRecords.Count, $newErrors, $warningRecords.Count, $exceptions.Count, $newExceptions))
foreach ($r in $records) { $lines.Add(("{0} {1}:{2} {3} {4}" -f $r.Severity, (Get-RelPath $r.ScriptPath), $r.Line, $r.RuleName, $r.Message)) }
foreach ($x in $exceptions) { $lines.Add("Exception $x") }
Set-Content -LiteralPath $outFile -Value $lines -Encoding utf8

Write-Host ("psa-gate: {0} files, {1} error-severity ({2} outside the baseline), {3} warnings (advisory), {4} analyzer exceptions ({5} outside the baseline), {6} stale baseline line(s)" -f $files.Count, $errorRecords.Count, $newErrors, $warningRecords.Count, $exceptions.Count, $newExceptions, $stale.Count)
foreach ($s in $stale) { Write-Host "  notice: stale baseline line: $s" }
foreach ($m in $failures) { Write-Host "  FAIL: $m" }

if ($env:GITHUB_STEP_SUMMARY) {
    @(
        '### PSScriptAnalyzer',
        '',
        '| Measure | Count |',
        '| --- | --- |',
        "| Files analyzed | $($files.Count) |",
        "| Error-severity findings (baseline-tolerated / new) | $($errorRecords.Count - $newErrors) / $newErrors |",
        "| Warning-severity findings (advisory) | $($warningRecords.Count) |",
        "| Analyzer exceptions (baseline-tolerated / new) | $($exceptions.Count - $newExceptions) / $newExceptions |",
        "| Stale baseline lines | $($stale.Count) |"
    ) | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
