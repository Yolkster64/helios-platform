#Requires -Version 7
<#
.SYNOPSIS
Diffs the sections CLAUDE.md and .github/copilot-instructions.md are meant to share
("Build and test", "Binding architecture rules", "Multi-LLM hub"), pairwise, after
normalizing whitespace and line wrapping. Exit 0 when every pair is identical, 1 with a
unified diff when not.

.DESCRIPTION
Claude and Copilot read two hand-maintained instruction files that carry the same
operating rules and the same hub inventory. They drift: a tool added to one list and not
the other, a framework version bumped in one file. This script is the measurement, run
as the informational "Instructions drift (informational)" job in ci-validation.yml and
by hand before editing either file.

AGENTS.md (Codex) is deliberately NOT in the default set: the owner's HELIOS Control
cutover wrote it with its own headings and wording ("Non-negotiable boundaries",
"Multi-LLM and MCP"), so an item-for-item comparison against it is drift by design.
Pass -Files / -Sections explicitly to compare any other combination.

How a section is read:
  - located by its "## <heading>" line; it runs to the next level-1 or level-2 heading
  - each bullet (a line starting with "-", "*", "+" or "N.") becomes ONE item; wrapped
    continuation lines are joined onto it with single spaces
  - whitespace runs collapse to one space, blank lines drop, comparison is ordinal and
    case-sensitive
So re-flowing prose never counts as drift; only content does. Every file pair is compared
for every section (2 files x 3 sections = 3 comparisons by default) and a differing pair
prints a unified diff of the items, "-" from the left file and "+" from the right.

Read-only by construction. There is no -Apply: the fix is a documentation edit that a
human reviews, and this script prints exactly which file and which item.

.PARAMETER Files
Files to compare, repo-relative or absolute. Default: CLAUDE.md,
.github/copilot-instructions.md.

.PARAMETER Sections
"## " headings to compare. Default: 'Build and test', 'Binding architecture rules',
'Multi-LLM hub'.

.PARAMETER Json
Emit ONE object and nothing else on stdout:
  {script, generatedUtc, repoRoot, files[], sections[], missing[],
   comparisons[{section, left, right, identical, leftItems, rightItems, added, removed, diff[]}],
   drifted, exitCode}

.EXAMPLE
pwsh scripts/verify/instructions-drift.ps1

.EXAMPLE
pwsh scripts/verify/instructions-drift.ps1 -Json | ConvertFrom-Json

.EXAMPLE
pwsh scripts/verify/instructions-drift.ps1 -Sections 'Multi-LLM hub'

.NOTES
Exit codes: 0 = every pair identical; 1 = at least one pair drifted (diffs printed);
2 = precondition missing (a file or a section heading was not found; each is named).
#>
[CmdletBinding()]
param(
    [string[]]$Files = @('CLAUDE.md', '.github/copilot-instructions.md'),

    [string[]]$Sections = @('Build and test', 'Binding architecture rules', 'Multi-LLM hub'),

    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

# -Json promises one object and nothing else on stdout (auth-doctor convention).
function Write-Report {
    param([string]$Message = '')
    if (-not $Json) { Write-Host $Message }
}

# Extracts one "## heading" section as a list of normalized items (see .DESCRIPTION).
# Returns Found=$false when the heading is absent, which is a precondition failure for
# the caller, distinct from a present-but-empty section (Found=$true, zero items).
function Get-SectionItems {
    param(
        # AllowEmptyString: a markdown file is full of blank lines, and a mandatory
        # [string[]] rejects "" elements by default, which would fail every real file.
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory)][string]$Heading
    )
    $headingPattern = '^##\s+' + [regex]::Escape($Heading) + '\s*$'
    $start = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match $headingPattern) { $start = $i; break }
    }
    if ($start -lt 0) {
        return [pscustomobject]@{ Found = $false; Items = @() }
    }
    $items = [System.Collections.Generic.List[string]]::new()
    $inFence = $false
    for ($i = $start + 1; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        # A fenced block is compared line-for-line rather than re-flowed: code is not
        # prose, and joining its lines would hide a changed command.
        if ($line -match '^\s*```') { $inFence = -not $inFence; continue }
        if (-not $inFence -and $line -match '^#{1,2}\s') { break }
        $text = ($line.Trim() -replace '\s+', ' ')
        if (-not $text) { continue }
        if ($inFence -or $text -match '^([-*+]|\d+[.)])\s' -or $items.Count -eq 0) {
            $items.Add($text)
        }
        else {
            $items[$items.Count - 1] = $items[$items.Count - 1] + ' ' + $text
        }
    }
    [pscustomobject]@{ Found = $true; Items = @($items) }
}

# Unified-style diff over item lists via a plain LCS table. Item lists are a handful of
# bullets, so quadratic space is nothing; a real diff tool is avoided because git may be
# absent on the host and its output would have to be captured and re-parsed anyway.
function Get-UnifiedDiff {
    param(
        [AllowEmptyCollection()][AllowEmptyString()][string[]]$Left = @(),
        [AllowEmptyCollection()][AllowEmptyString()][string[]]$Right = @(),
        [Parameter(Mandatory)][string]$LeftName,
        [Parameter(Mandatory)][string]$RightName
    )
    $n = $Left.Count
    $m = $Right.Count
    $lcs = [int[, ]]::new($n + 1, $m + 1)
    for ($i = $n - 1; $i -ge 0; $i--) {
        for ($j = $m - 1; $j -ge 0; $j--) {
            $lcs[$i, $j] = if ($Left[$i] -ceq $Right[$j]) { $lcs[($i + 1), ($j + 1)] + 1 }
            else { [math]::Max($lcs[($i + 1), $j], $lcs[$i, ($j + 1)]) }
        }
    }
    $ops = [System.Collections.Generic.List[string]]::new()
    $i = 0
    $j = 0
    while ($i -lt $n -and $j -lt $m) {
        if ($Left[$i] -ceq $Right[$j]) { $ops.Add(' ' + $Left[$i]); $i++; $j++ }
        elseif ($lcs[($i + 1), $j] -ge $lcs[$i, ($j + 1)]) { $ops.Add('-' + $Left[$i]); $i++ }
        else { $ops.Add('+' + $Right[$j]); $j++ }
    }
    while ($i -lt $n) { $ops.Add('-' + $Left[$i]); $i++ }
    while ($j -lt $m) { $ops.Add('+' + $Right[$j]); $j++ }
    @("--- $LeftName", "+++ $RightName", "@@ -1,$n +1,$m @@") + @($ops)
}

# --- Load the files -------------------------------------------------------------------------
$loaded = [System.Collections.Generic.List[object]]::new()
$missing = [System.Collections.Generic.List[string]]::new()
foreach ($file in $Files) {
    $full = if ([System.IO.Path]::IsPathRooted($file)) { $file } else { Join-Path $repoRoot $file }
    if (Test-Path -LiteralPath $full -PathType Leaf) {
        $loaded.Add([pscustomobject]@{ Name = $file; Lines = @(Get-Content -LiteralPath $full) })
    }
    else {
        $missing.Add("file not found: $file")
    }
}

Write-Report "instructions-drift: files=$($Files.Count) sections=$($Sections.Count) (repo $repoRoot)"

# --- Compare every pair for every section ---------------------------------------------------
$comparisons = [System.Collections.Generic.List[object]]::new()
foreach ($section in $Sections) {
    Write-Report ''
    Write-Report "-- $section --"
    $extracted = @{}
    foreach ($doc in $loaded) {
        $result = Get-SectionItems -Lines $doc.Lines -Heading $section
        if ($result.Found) {
            $extracted[$doc.Name] = @($result.Items)
        }
        else {
            $missing.Add("section '## $section' not found in $($doc.Name)")
            Write-Report "  $($doc.Name): section not found"
        }
    }
    $names = @($loaded | ForEach-Object Name | Where-Object { $extracted.ContainsKey($_) })
    for ($a = 0; $a -lt $names.Count; $a++) {
        for ($b = $a + 1; $b -lt $names.Count; $b++) {
            $left = @($extracted[$names[$a]])
            $right = @($extracted[$names[$b]])
            $diff = @(Get-UnifiedDiff -Left $left -Right $right -LeftName "$($names[$a]) [$section]" -RightName "$($names[$b]) [$section]")
            $body = @($diff | Select-Object -Skip 3)
            $added = @($body | Where-Object { $_.StartsWith('+') }).Count
            $removed = @($body | Where-Object { $_.StartsWith('-') }).Count
            $identical = ($added -eq 0 -and $removed -eq 0)
            $comparisons.Add([pscustomobject]@{
                    section    = $section
                    left       = $names[$a]
                    right      = $names[$b]
                    identical  = $identical
                    leftItems  = $left.Count
                    rightItems = $right.Count
                    added      = $added
                    removed    = $removed
                    diff       = @(if ($identical) { } else { $diff })
                })
            if ($identical) {
                Write-Report "  $($names[$a]) vs $($names[$b]): identical ($($left.Count) items)"
            }
            else {
                Write-Report "  $($names[$a]) vs $($names[$b]): DRIFT (+$added / -$removed items)"
                foreach ($line in $diff) { Write-Report "    $line" }
            }
        }
    }
}

# --- Verdict --------------------------------------------------------------------------------
$drifted = @($comparisons | Where-Object { -not $_.identical })
$exitCode = if ($missing.Count -gt 0) { 2 } elseif ($drifted.Count -gt 0) { 1 } else { 0 }

if ($Json) {
    [ordered]@{
        script       = 'scripts/verify/instructions-drift.ps1'
        generatedUtc = (Get-Date).ToUniversalTime().ToString('o')
        repoRoot     = $repoRoot
        files        = @($Files)
        sections     = @($Sections)
        missing      = @($missing)
        comparisons  = @($comparisons)
        drifted      = ($drifted.Count -gt 0)
        exitCode     = $exitCode
    } | ConvertTo-Json -Depth 5
}
else {
    Write-Report ''
    if ($missing.Count -gt 0) {
        Write-Report 'instructions-drift: FAILED PRECONDITION -'
        foreach ($item in $missing) { Write-Report "  $item" }
        Write-Report 'Restore the file or heading (the compared files share these headings by contract), then re-run.'
    }
    elseif ($drifted.Count -gt 0) {
        Write-Report "instructions-drift: DRIFT in $($drifted.Count) of $($comparisons.Count) comparison(s)."
        Write-Report 'Fix: edit the drifted file(s) until the shared sections match item for item (prose wrapping'
        Write-Report 'is ignored, content is not), then re-run: pwsh scripts/verify/instructions-drift.ps1'
    }
    else {
        Write-Report "instructions-drift: clean - $($comparisons.Count) comparison(s), every shared section identical."
    }
}
exit $exitCode
