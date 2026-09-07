#Requires -Version 7
<#
.SYNOPSIS
  PSScriptAnalyzer gate for quality.yml (powershell-lint): Error-severity findings and
  analyzer failures outside the legacy baseline fail the job; warnings are advisory.

.DESCRIPTION
  Runs Invoke-ScriptAnalyzer (-Severity Error, Warning) file by file over the given
  roots. Invoke-ScriptAnalyzer's -Path parameter is a single string, so the two roots are
  enumerated here instead of being passed as one array (the workflow's previous
  invocation failed to bind and its continue-on-error hid that on every run).

  Verdict rules:
    - an Error-severity record whose "<path>|<rule>" pair is not in the baseline → fail
    - a file the analyzer throws on whose "<path>|analyzer-exception" line is not in the
      baseline → fail (a crash is a tool failure, not a clean file)
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

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    Write-Host 'PSScriptAnalyzer is not installed: Install-Module -Name PSScriptAnalyzer -RequiredVersion 1.25.0 -Scope CurrentUser -Force'
    exit 2
}
Import-Module PSScriptAnalyzer
$onActions = [bool]$env:GITHUB_ACTIONS

$baselineFile = if ([IO.Path]::IsPathRooted($BaselinePath)) { $BaselinePath } else { Join-Path $Root $BaselinePath }
$baseline = @{}
if (Test-Path -LiteralPath $baselineFile) {
    Get-Content -LiteralPath $baselineFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith('#')) { $baseline[$line] = $false }
    }
}

$files = foreach ($p in $Paths) {
    $dir = Join-Path $Root $p
    if (Test-Path -LiteralPath $dir) { Get-ChildItem -LiteralPath $dir -Recurse -Filter '*.ps1' -File }
}
$files = @($files | Sort-Object FullName)
$rootPrefix = $Root.TrimEnd('/', '\') + [IO.Path]::DirectorySeparatorChar

$records = New-Object System.Collections.Generic.List[object]
$exceptions = New-Object System.Collections.Generic.List[string]
$failures = New-Object System.Collections.Generic.List[string]
foreach ($f in $files) {
    $rel = $f.FullName.Replace($rootPrefix, '').Replace('\', '/')
    try {
        $r = Invoke-ScriptAnalyzer -Path $f.FullName -Severity Error, Warning -ErrorAction Stop
        if ($r) { $records.AddRange(@($r)) }
    } catch {
        $key = "$rel|analyzer-exception"
        $first = $_.Exception.Message.Split("`n")[0]
        $exceptions.Add("$rel : $first")
        if ($baseline.ContainsKey($key)) { $baseline[$key] = $true }
        else { $failures.Add("$rel : PSScriptAnalyzer threw ($first)") ; if ($onActions) { Write-Host "::error file=$rel::PSScriptAnalyzer threw: $first" } }
    }
}

$errorRecords = @($records | Where-Object Severity -eq 'Error')
$warningRecords = @($records | Where-Object Severity -eq 'Warning')
foreach ($e in $errorRecords) {
    $rel = $e.ScriptPath.Replace($rootPrefix, '').Replace('\', '/')
    $key = "$rel|$($e.RuleName)"
    if ($baseline.ContainsKey($key)) { $baseline[$key] = $true; continue }
    $failures.Add(("{0}:{1} {2} — {3}" -f $rel, $e.Line, $e.RuleName, $e.Message))
    if ($onActions) { Write-Host ("::error file={0},line={1}::{2}: {3}" -f $rel, $e.Line, $e.RuleName, $e.Message) }
}
$stale = @($baseline.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key } | Sort-Object)
$newExceptions = @($failures | Where-Object { $_ -like '* : PSScriptAnalyzer threw*' }).Count
$newErrors = $failures.Count - $newExceptions

$outFile = if ([IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $Root $OutputPath }
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add(("PSScriptAnalyzer gate: {0} files; {1} error-severity ({2} outside the baseline); {3} warnings (advisory); {4} analyzer exceptions ({5} outside the baseline)" -f $files.Count, $errorRecords.Count, $newErrors, $warningRecords.Count, $exceptions.Count, $newExceptions))
foreach ($r in $records) { $lines.Add(("{0} {1}:{2} {3} {4}" -f $r.Severity, $r.ScriptPath.Replace($rootPrefix, '').Replace('\', '/'), $r.Line, $r.RuleName, $r.Message)) }
foreach ($x in $exceptions) { $lines.Add("Exception $x") }
Set-Content -LiteralPath $outFile -Value $lines -Encoding utf8

Write-Host ("psa-gate: {0} files, {1} error-severity ({2} outside the baseline), {3} warnings (advisory), {4} analyzer exceptions ({5} outside the baseline), {6} stale baseline line(s)" -f $files.Count, $errorRecords.Count, $newErrors, $warningRecords.Count, $exceptions.Count, $newExceptions, $stale.Count)
foreach ($s in $stale) { Write-Host "  notice: baseline line no longer triggers, delete it: $s" }
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
