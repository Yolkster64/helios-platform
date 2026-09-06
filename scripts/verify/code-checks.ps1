#Requires -Version 7
[CmdletBinding()]
param(
    [ValidateSet('run')]
    [string]$Mode = 'run',
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path,
    [string]$EventName = 'workflow_dispatch',
    [string]$BaseRef,
    [string]$Before,
    [string]$ReportPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-GitText {
    param(
        [string]$RepoRoot,
        [string[]]$Arguments
    )

    $output = @(& git -C $RepoRoot @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    [pscustomobject]@{
        ExitCode = $exitCode
        Output   = @($output | ForEach-Object { [string]$_ })
    }
}

function Get-GitTextOrThrow {
    param(
        [string]$RepoRoot,
        [string[]]$Arguments,
        [string]$FailureMessage
    )

    $result = Invoke-GitText -RepoRoot $RepoRoot -Arguments $Arguments
    if ($result.ExitCode -ne 0) {
        $detail = ($result.Output -join [Environment]::NewLine).Trim()
        if ([string]::IsNullOrWhiteSpace($detail)) {
            throw $FailureMessage
        }
        throw "$FailureMessage`n$detail"
    }
    @($result.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Test-GitRef {
    param(
        [string]$RepoRoot,
        [string]$Ref
    )

    (Invoke-GitText -RepoRoot $RepoRoot -Arguments @('rev-parse', '--verify', '--quiet', "$Ref^{commit}")).ExitCode -eq 0
}

function Get-TrackedPowerShellFiles {
    param([string]$RepoRoot)

    @(Get-GitTextOrThrow -RepoRoot $RepoRoot -Arguments @('ls-files') -FailureMessage 'Unable to enumerate tracked files.' |
        Where-Object { $_ -match '\.ps(m)?1$' } |
        Sort-Object -Unique)
}

function Get-DiffPowerShellFiles {
    param(
        [string]$RepoRoot,
        [string]$Range
    )

    $changed = [System.Collections.Generic.List[string]]::new()
    $lines = @(Get-GitTextOrThrow -RepoRoot $RepoRoot -Arguments @('diff', '--name-status', '--find-renames', $Range) -FailureMessage "Unable to diff files for range $Range.")
    foreach ($line in $lines) {
        $parts = @($line -split "`t")
        if ($parts.Count -lt 2) {
            continue
        }

        $status = $parts[0]
        if ($status -match '^[RC]' -and $parts.Count -ge 3) {
            $oldPath = $parts[1]
            $newPath = $parts[2]
            if ($newPath -match '\.ps(m)?1$') {
                $changed.Add($newPath)
            }
            elseif ($oldPath -match '\.ps(m)?1$') {
                $changed.Add($oldPath)
            }
            continue
        }

        if ($status -notmatch '^[AM]') {
            continue
        }

        $path = $parts[1]
        if ($path -match '\.ps(m)?1$') {
            $changed.Add($path)
        }
    }

    @($changed | Sort-Object -Unique)
}

function Resolve-PullRequestBaseRef {
    param(
        [string]$RepoRoot,
        [string]$BaseRef
    )

    if ($BaseRef -notmatch '^(?!/)(?!.*//)(?!.*\.\.)(?!.*@$)[A-Za-z0-9._/-]+(?<!/)$') {
        throw "Unsafe pull request base ref '$BaseRef'."
    }

    foreach ($candidate in @("refs/remotes/origin/$BaseRef", "refs/heads/$BaseRef")) {
        if (Test-GitRef -RepoRoot $RepoRoot -Ref $candidate) {
            return $candidate
        }
    }

    $fetch = Invoke-GitText -RepoRoot $RepoRoot -Arguments @('fetch', '--no-tags', 'origin', "+refs/heads/$BaseRef:refs/remotes/origin/$BaseRef")
    if ($fetch.ExitCode -ne 0 -or -not (Test-GitRef -RepoRoot $RepoRoot -Ref "refs/remotes/origin/$BaseRef")) {
        $detail = ($fetch.Output -join [Environment]::NewLine).Trim()
        if ([string]::IsNullOrWhiteSpace($detail)) {
            throw "Could not resolve pull request base ref '$BaseRef'."
        }
        throw "Could not resolve pull request base ref '$BaseRef'.`n$detail"
    }

    "refs/remotes/origin/$BaseRef"
}

function Get-CodeCheckTargetFiles {
    param(
        [string]$RepoRoot,
        [string]$EventName,
        [string]$BaseRef,
        [string]$Before
    )

    switch ($EventName) {
        'pull_request' {
            if ([string]::IsNullOrWhiteSpace($BaseRef)) {
                throw 'pull_request events require BaseRef.'
            }

            $baseSpec = Resolve-PullRequestBaseRef -RepoRoot $RepoRoot -BaseRef $BaseRef
            $mergeBase = @(Get-GitTextOrThrow -RepoRoot $RepoRoot -Arguments @('merge-base', 'HEAD', $baseSpec) -FailureMessage "Unable to compute a merge base for HEAD and $baseSpec.")
            if ($mergeBase.Count -eq 0) {
                throw "No merge base found for HEAD and $baseSpec."
            }
            return @(Get-DiffPowerShellFiles -RepoRoot $RepoRoot -Range "$($mergeBase[0])..HEAD")
        }
        'push' {
            if ($Before -and $Before -ne ('0' * 40) -and (Test-GitRef -RepoRoot $RepoRoot -Ref $Before)) {
                return @(Get-DiffPowerShellFiles -RepoRoot $RepoRoot -Range "$Before..HEAD")
            }
            return @(Get-TrackedPowerShellFiles -RepoRoot $RepoRoot)
        }
        default {
            return @(Get-TrackedPowerShellFiles -RepoRoot $RepoRoot)
        }
    }
}

function New-CheckResult {
    param(
        [string]$Name,
        [string]$Status,
        [string[]]$Messages = @(),
        [int]$Checked = 0
    )

    [pscustomobject]@{
        Name     = $Name
        Status   = $Status
        Checked  = $Checked
        Messages = @($Messages)
    }
}

function Test-PowerShellSyntax {
    param(
        [string]$RepoRoot,
        [string[]]$Paths
    )

    $Paths = @($Paths)
    if ($Paths.Count -eq 0) {
        return New-CheckResult -Name 'Syntax' -Status 'skipped'
    }

    $errors = [System.Collections.Generic.List[string]]::new()
    foreach ($relativePath in $Paths) {
        $absolutePath = Join-Path $RepoRoot $relativePath
        if (-not (Test-Path -LiteralPath $absolutePath)) {
            continue
        }
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($absolutePath, [ref]$tokens, [ref]$parseErrors) | Out-Null
        foreach ($parseError in @($parseErrors)) {
            $errors.Add(('{0}:{1}: {2}' -f $relativePath, $parseError.Extent.StartLineNumber, $parseError.Message))
        }
    }

    if ($errors.Count -gt 0) {
        return New-CheckResult -Name 'Syntax' -Status 'fail' -Messages $errors -Checked $Paths.Count
    }

    New-CheckResult -Name 'Syntax' -Status 'pass' -Checked $Paths.Count
}

function Test-PowerShellSecrets {
    param(
        [string]$RepoRoot,
        [string[]]$Paths
    )

    $Paths = @($Paths)
    if ($Paths.Count -eq 0) {
        return New-CheckResult -Name 'Security' -Status 'skipped'
    }

    $issues = [System.Collections.Generic.List[string]]::new()
    $patternMap = [ordered]@{
        'password\s*=\s*[''"]([^''"]+)[''"]' = 'Hardcoded password'
        'apikey\s*=\s*[''"]([^''"]+)[''"]'   = 'Hardcoded API key'
        'secret\s*=\s*[''"]([^''"]+)[''"]'   = 'Hardcoded secret'
        'token\s*=\s*[''"]([^''"]+)[''"]'    = 'Hardcoded token'
    }
    $placeholder = 'xxx|^\*+$|^<[^>]*>$|placeholder|example|changeme|dummy|your[-_]'

    foreach ($relativePath in $Paths) {
        $absolutePath = Join-Path $RepoRoot $relativePath
        if (-not (Test-Path -LiteralPath $absolutePath)) {
            continue
        }
        $raw = Get-Content -LiteralPath $absolutePath -Raw
        if ($relativePath -match '(^|[\\/])test-' -or $raw -match '# EXAMPLE CODE') {
            continue
        }

        $lines = @(Get-Content -LiteralPath $absolutePath)
        for ($index = 0; $index -lt $lines.Count; $index++) {
            foreach ($pattern in $patternMap.Keys) {
                if ($lines[$index] -match $pattern -and $Matches[1] -notmatch $placeholder) {
                    $issues.Add(('{0}:{1}: {2}' -f $relativePath, $index + 1, $patternMap[$pattern]))
                }
            }
        }
    }

    if ($issues.Count -gt 0) {
        return New-CheckResult -Name 'Security' -Status 'fail' -Messages $issues -Checked $Paths.Count
    }

    New-CheckResult -Name 'Security' -Status 'pass' -Checked $Paths.Count
}

function Test-RegistryDocumentation {
    param(
        [string]$RepoRoot,
        [string[]]$Paths
    )

    $Paths = @($Paths)
    if ($Paths.Count -eq 0) {
        return New-CheckResult -Name 'Registry' -Status 'skipped'
    }

    $issues = [System.Collections.Generic.List[string]]::new()
    foreach ($relativePath in $Paths) {
        $absolutePath = Join-Path $RepoRoot $relativePath
        if (-not (Test-Path -LiteralPath $absolutePath)) {
            continue
        }
        $content = Get-Content -LiteralPath $absolutePath -Raw
        if ($content -match '(New-Item|Set-ItemProperty|Remove-Item).*(HKLM|HKCU|HKU)' -and
            $content -notmatch '# Registry:') {
            $issues.Add(('{0}: missing ''# Registry:'' documentation' -f $relativePath))
        }
    }

    if ($issues.Count -gt 0) {
        return New-CheckResult -Name 'Registry' -Status 'fail' -Messages $issues -Checked $Paths.Count
    }

    New-CheckResult -Name 'Registry' -Status 'pass' -Checked $Paths.Count
}

function Test-PathWarnings {
    param(
        [string]$RepoRoot,
        [string[]]$Paths
    )

    $Paths = @($Paths)
    if ($Paths.Count -eq 0) {
        return New-CheckResult -Name 'Path warnings' -Status 'skipped'
    }

    $warnings = [System.Collections.Generic.List[string]]::new()
    foreach ($relativePath in $Paths) {
        $absolutePath = Join-Path $RepoRoot $relativePath
        if (-not (Test-Path -LiteralPath $absolutePath)) {
            continue
        }
        $content = Get-Content -LiteralPath $absolutePath -Raw
        if ($relativePath -notmatch '(^|[\\/])test-' -and $content -match '[''"]C:\\Users\\[^''"]*[''"]') {
            $warnings.Add(('{0}: consider using environment variables for user-profile paths' -f $relativePath))
        }
        if ($content -match '[''"][A-Za-z]:\\[^''"]*[<>|?*][^''"]*[''"]') {
            $warnings.Add(('{0}: quoted Windows path contains invalid filename characters' -f $relativePath))
        }
    }

    if ($warnings.Count -gt 0) {
        return New-CheckResult -Name 'Path warnings' -Status 'pass' -Messages $warnings -Checked $Paths.Count
    }

    New-CheckResult -Name 'Path warnings' -Status 'pass' -Checked $Paths.Count
}

function Test-DocumentationHeaders {
    param(
        [string]$RepoRoot,
        [string[]]$Paths
    )

    $Paths = @($Paths)
    $phaseFiles = @($Paths | Where-Object { $_ -match '(^|[\\/])Phase-.*\.ps1$' })
    if ($phaseFiles.Count -eq 0) {
        return New-CheckResult -Name 'Documentation' -Status 'skipped'
    }

    $issues = [System.Collections.Generic.List[string]]::new()
    foreach ($relativePath in $phaseFiles) {
        $absolutePath = Join-Path $RepoRoot $relativePath
        $content = Get-Content -LiteralPath $absolutePath -Raw
        if ($content -notmatch '<#' -or $content -notmatch '\.SYNOPSIS' -or $content -notmatch '\.DESCRIPTION') {
            $issues.Add(('{0}: missing comment-based help header' -f $relativePath))
        }
    }

    if ($issues.Count -gt 0) {
        return New-CheckResult -Name 'Documentation' -Status 'fail' -Messages $issues -Checked $phaseFiles.Count
    }

    New-CheckResult -Name 'Documentation' -Status 'pass' -Checked $phaseFiles.Count
}

function Invoke-CodeChecks {
    param(
        [string]$RepoRoot,
        [string]$EventName,
        [string]$BaseRef,
        [string]$Before
    )

    $targets = @(Get-CodeCheckTargetFiles -RepoRoot $RepoRoot -EventName $EventName -BaseRef $BaseRef -Before $Before)
    $report = [pscustomobject]@{
        RepoRoot    = $RepoRoot
        EventName   = $EventName
        BaseRef     = $BaseRef
        Before      = $Before
        TargetFiles = $targets
        Checks      = @(
            Test-PowerShellSyntax -RepoRoot $RepoRoot -Paths $targets
            Test-PowerShellSecrets -RepoRoot $RepoRoot -Paths $targets
            Test-RegistryDocumentation -RepoRoot $RepoRoot -Paths $targets
            Test-PathWarnings -RepoRoot $RepoRoot -Paths $targets
            Test-DocumentationHeaders -RepoRoot $RepoRoot -Paths $targets
        )
    }

    $report | Add-Member -NotePropertyName Failed -NotePropertyValue ([bool]($report.Checks | Where-Object { $_.Status -eq 'fail' }))
    $report
}

function Write-CodeCheckSummary {
    param([pscustomobject]$Report)

    Write-Host "Code checks target files: $($Report.TargetFiles.Count)"
    foreach ($target in $Report.TargetFiles) {
        Write-Host "  - $target"
    }
    foreach ($check in $Report.Checks) {
        Write-Host ('[{0}] {1} ({2})' -f $check.Status.ToUpperInvariant(), $check.Name, $check.Checked)
        foreach ($message in $check.Messages) {
            Write-Host "  - $message"
        }
    }
}

$dotSourced = $MyInvocation.InvocationName -eq '.'
if (-not $dotSourced -and $Mode -eq 'run') {
    $report = Invoke-CodeChecks -RepoRoot $RepoRoot -EventName $EventName -BaseRef $BaseRef -Before $Before
    Write-CodeCheckSummary -Report $report

    if ($ReportPath) {
        $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ReportPath -Encoding utf8
    }

    if ($report.Failed) {
        exit 1
    }
}
