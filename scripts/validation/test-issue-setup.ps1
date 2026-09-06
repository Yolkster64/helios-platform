#Requires -Version 7
<#
Offline contract tests. Load only named function ASTs for table-driven reports;
execute the entrypoints only inside a temporary checkout with inert children.
No Pester, credentials, network, live gh/az, or real setup producers are needed.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$pwsh = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
$checks = 0
function Assert {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    $script:checks++
}
function Read-Ast {
    param([string]$Path)
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    Assert ($errors.Count -eq 0) "PowerShell syntax: $Path"
    return $ast
}
function Put-Fixture {
    param([string]$Relative, [string]$Text)
    $path = Join-Path $sandbox $Relative
    $null = New-Item -ItemType Directory -Path (Split-Path $path) -Force
    Set-Content -LiteralPath $path -Value $Text
}
function Invoke-Inert {
    param([string]$Relative, [string[]]$Arguments = @())
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $pwsh
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = $sandbox
    # Never inherit any credential, cloud, or MCP environment into the fixture.
    $psi.Environment.Clear()
    $psi.Environment['PATH'] = Split-Path $pwsh
    $psi.Environment['HOME'] = $sandbox
    $psi.Environment['USERPROFILE'] = $sandbox
    foreach ($arg in @('-NoProfile', '-File', (Join-Path $sandbox $Relative)) + $Arguments) {
        $psi.ArgumentList.Add($arg)
    }
    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    try {
        $null = $proc.Start()
        $stdout = $proc.StandardOutput.ReadToEndAsync()
        $stderr = $proc.StandardError.ReadToEndAsync()
        if (-not $proc.WaitForExit(30000)) {
            $proc.Kill($true)
            throw 'Inert boundary timed out'
        }
        # Deliberately preserve native exit state, just like an Actions pwsh step.
        $global:LASTEXITCODE = $proc.ExitCode
        return [pscustomobject]@{ Code = $proc.ExitCode; Text = $stdout.Result; Error = $stderr.Result }
    }
    finally { $proc.Dispose() }
}

$allPath = 'scripts/setup/setup-all.ps1'
$chainPath = 'scripts/bootstrap/setup-everything.ps1'
$allAst = Read-Ast (Join-Path $root $allPath)
$chainAst = Read-Ast (Join-Path $root $chainPath)
foreach ($name in 'labels', 'milestones') {
    $null = Read-Ast (Join-Path $root "scripts/github/apply-$name.ps1")
}
$null = Read-Ast $PSCommandPath
foreach ($name in 'New-Component', 'Invoke-IssueSetup') {
    $fn = $allAst.Find({ param($n)
        $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name
    }, $true)
    Assert ($null -ne $fn) "AST seam exists: $name"
    . ([scriptblock]::Create($fn.Extent.Text))
}
# Static pin on the safety-critical argv in addition to the runtime spy below.
$issueFunction = $allAst.Find({ param($n)
    $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-IssueSetup'
}, $true)
$calls = @($issueFunction.FindAll({ param($n)
    $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Invoke-Step'
}, $true))
Assert ($calls.Count -eq 1) 'one issue producer invocation seam'
Assert ($calls[0].Extent.Text -notmatch '-Apply|-Fix') 'issue argv never forwards mutation flags'

$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('helios-issue-tests-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $sandbox
try {
    $repoRoot = $sandbox
    $Repository = 'test-owner/test.repo'
    $pwshExe = $pwsh
    foreach ($kind in 'labels', 'milestones') { Put-Fixture "scripts/github/apply-$kind.ps1" '# inert' }
    $script:transform = {}
    $script:childExit = 0
    $script:raw = $null
    $script:spy = [System.Collections.Generic.List[object]]::new()
    function Invoke-Step {
        param([string]$Executable, [string[]]$Arguments)
        $script:spy.Add($Arguments)
        Assert ($Executable -eq $pwshExe) 'uses isolated pwsh executable'
        $kind = if ($Arguments[2] -like '*apply-labels.ps1') { 'labels' } else { 'milestones' }
        Assert (($Arguments -join '|') -eq (
            @('-NoProfile', '-File', (Join-Path $repoRoot "scripts/github/apply-$kind.ps1"),
                '-Repository', $Repository, '-Json') -join '|')) 'exact dry-run argv'
        $row = @{ state = 'in-sync'; command = ''; detail = '' }
        $row[$(if ($kind -eq 'labels') { 'name' } else { 'title' })] = 'test'
        $report = @{
            script = "apply-$kind"; repository = $Repository; mode = 'dry-run'; exitCode = 0
            precondition = @{ ghFound = $true; wireReadable = $true; existenceKnown = $true }
            items = @($row)
            counts = @{ create = 0; update = 0; inSync = 1; invalid = 0; failed = 0 }
            notes = @('UNTRUSTED-CHILD-TEXT'); unmanaged = @('UNTRUSTED-CHILD-TEXT')
        }
        if ($kind -eq 'milestones') { $report.counts.closed = 0 }
        & $script:transform $report
        $text = if ($null -ne $script:raw) { $script:raw } else { ConvertTo-Json $report -Depth 12 -Compress }
        [pscustomobject]@{ ExitCode = $script:childExit; Output = @($text) }
    }
    $rows = @(Invoke-IssueSetup)
    Assert ($rows.Count -eq 2 -and @($rows | Where-Object Status -ne 'ready').Count -eq 0) 'in-sync ready'
    Assert (@($rows | Where-Object Fix -ne '').Count -eq 0) 'ready has no next command'
    Assert (($rows | ConvertTo-Json) -notmatch 'UNTRUSTED') 'raw child content suppressed'
    Assert (@($rows | Where-Object Detail -notmatch 'write access not verified').Count -eq 0) 'no write authority claim'

    $cases = @(
        @{ Name = 'wrong repository'; Change = { param($r) $r.repository = 'other/repo' } }
        @{ Name = 'repository wrong type'; Change = { param($r) $r.repository = @($r.repository) } }
        @{ Name = 'wrong script'; Change = { param($r) $r.script = 'other' } }
        @{ Name = 'script wrong type'; Change = { param($r) $r.script = @($r.script) } }
        @{ Name = 'apply mode'; Change = { param($r) $r.mode = 'apply' } }
        @{ Name = 'mode wrong type'; Change = { param($r) $r.mode = @('dry-run') } }
        @{ Name = 'exit string'; Change = { param($r) $r.exitCode = '0' } }
        @{ Name = 'exit boolean'; Change = { param($r) $r.exitCode = $false } }
        @{ Name = 'exit mismatch'; Change = { param($r) $r.exitCode = 1 } }
        @{ Name = 'exit missing'; Change = { param($r) $r.Remove('exitCode') } }
        @{ Name = 'unknown live exit zero'; Change = { param($r) $r.precondition.existenceKnown = $false } }
        @{ Name = 'no gh exit zero'; Change = { param($r) $r.precondition.ghFound = $false } }
        @{ Name = 'unreadable wire exit zero'; Change = { param($r) $r.precondition.wireReadable = $false } }
        @{ Name = 'string boolean'; Change = { param($r) $r.precondition.wireReadable = 'true' } }
        @{ Name = 'numeric boolean'; Change = { param($r) $r.precondition.ghFound = 1 } }
        @{ Name = 'missing boolean'; Change = { param($r) $r.precondition.Remove('existenceKnown') } }
        @{ Name = 'missing preconditions'; Change = { param($r) $r.Remove('precondition') } }
        @{ Name = 'empty items'; Change = { param($r) $r.items = @() } }
        @{ Name = 'scalar items'; Change = { param($r) $r.items = $r.items[0] } }
        @{ Name = 'null item'; Change = { param($r) $r.items = @($null) } }
        @{ Name = 'string item'; Change = { param($r) $r.items = @('in-sync') } }
        @{ Name = 'missing row state'; Change = { param($r) $r.items[0].Remove('state') } }
        @{ Name = 'unknown row state'; Change = { param($r) $r.items[0].state = 'unknown' } }
        @{ Name = 'array row state'; Change = { param($r) $r.items[0].state = @('in-sync') } }
        @{ Name = 'pending row'; Change = { param($r) $r.items[0].state = 'pending' } }
        @{ Name = 'mutation result'; Change = { param($r) $r.items[0].state = 'created' } }
        @{ Name = 'row command wrong type'; Change = { param($r) $r.items[0].command = @() } }
        @{ Name = 'in-sync carries mutation'; Change = { param($r) $r.items[0].command = 'UNTRUSTED-CHILD-TEXT' } }
        @{ Name = 'row detail wrong type'; Change = { param($r) $r.items[0].detail = 42 } }
        @{ Name = 'identity missing'; Change = { param($r) $r.items[0].Remove('name'); $r.items[0].Remove('title') } }
        @{ Name = 'counts inconsistent'; Change = { param($r) $r.counts.inSync = 0 } }
        @{ Name = 'counts wrong type'; Change = { param($r) $r.counts.inSync = '1' } }
    )
    foreach ($state in 'create', 'update', 'closed', 'failed', 'invalid') {
        $cases += @{ Name = $state; Change = {
            param($r)
            $r.items[0].state = $state
            $r.items[0].command = 'UNTRUSTED-CHILD-TEXT'
            $r.counts.inSync = 0
            $r.counts[$state] = 1
        }.GetNewClosure() }
    }
    foreach ($case in $cases) {
        $script:transform = $case.Change
        $rows = @(Invoke-IssueSetup)
        Assert (@($rows | Where-Object Status -ne 'needs-attention').Count -eq 0) $case.Name
        Assert (($rows | ConvertTo-Json) -notmatch 'UNTRUSTED') "bounded output: $($case.Name)"
        foreach ($row in $rows) {
            $kind = $row.Component -replace '^issue-', ''
            Assert ($row.Fix -eq "pwsh scripts/github/apply-$kind.ps1 -Repository $Repository -Json") 'dry-run nextCommand only'
            Assert ($row.Detail.Length -lt 180) 'bounded detail'
        }
    }
    $script:transform = {}
    foreach ($raw in 'not-json UNTRUSTED-CHILD-TEXT', 'null', '[]', '[{}]', '{}', ('x' * 1048577)) {
        $script:raw = $raw
        Assert (@(Invoke-IssueSetup | Where-Object Status -eq 'ready').Count -eq 0) 'malformed document rejected'
    }
    $script:raw = $null
    foreach ($code in 1, 2, 7) {
        $script:childExit = $code
        Assert (@(Invoke-IssueSetup | Where-Object Status -eq 'ready').Count -eq 0) 'nonzero child exit rejected'
    }
    $script:childExit = 0
    Remove-Item (Join-Path $sandbox 'scripts/github/apply-labels.ps1')
    Assert (@(Invoke-IssueSetup | Where-Object Status -eq 'needs-attention').Count -eq 1) 'missing producer nonready'

    # Whole entrypoints at the real process boundary, all dependencies replaced.
    Put-Fixture $allPath (Get-Content -Raw (Join-Path $root $allPath))
    Put-Fixture $chainPath (Get-Content -Raw (Join-Path $root $chainPath))
    Put-Fixture 'scripts/build/tool-resolver.ps1' @'
function Resolve-HeliosTool { param($Name, $RepoRoot) [pscustomobject]@{ Found = $false; Path = '' } }
'@
    Put-Fixture 'scripts/build/verify-readiness.ps1' @'
param([switch]$Json)
'{"ready":false,"required":[],"optional":[]}'
exit 0
'@
    Put-Fixture 'scripts/bootstrap/connect-github.sh' "exit 0"
    Put-Fixture 'scripts/bootstrap/connect-azure.ps1' "param([switch]`$VerifyOnly)`n'fixture'`nexit 0"
    Put-Fixture 'scripts/bootstrap/setup-ai-clis.ps1' "param([switch]`$VerifyOnly)`n'AI CLIs: fixture'`nexit 0"
    foreach ($path in 'scripts/bootstrap/connect-account.ps1', 'scripts/bootstrap/auth-doctor.ps1',
        'scripts/verify/stack-smoke.ps1', 'scripts/verify/rest-connect.ps1') {
        Put-Fixture $path "param([switch]`$Json, [switch]`$Apply)`n'{`"lanes`":[]}'`nexit 0"
    }
    foreach ($kind in 'labels', 'milestones') {
        Put-Fixture "scripts/github/apply-$kind.ps1" @'
[CmdletBinding()]
param([string]$Repository, [switch]$Json)
if ($Repository -cne 'test-owner/test.repo' -or -not $Json) { exit 9 }
$kind = [IO.Path]::GetFileNameWithoutExtension($PSCommandPath) -replace '^apply-', ''
$row = @{ state = 'create'; command = 'UNTRUSTED-CHILD-TEXT'; detail = 'UNTRUSTED-CHILD-TEXT' }
$row[$(if ($kind -eq 'labels') { 'name' } else { 'title' })] = 'test'
$counts = @{ create = 1; update = 0; inSync = 0; failed = 0; invalid = 0 }
if ($kind -eq 'milestones') { $counts.closed = 0 }
@{
    script = "apply-$kind"; mode = 'dry-run'; repository = $Repository; exitCode = 0
    precondition = @{ ghFound = $true; wireReadable = $true; existenceKnown = $false }
    items = @($row); counts = $counts
} | ConvertTo-Json -Depth 6
exit 0
'@
    }
    $default = Invoke-Inert $allPath @('-Json')
    Assert ($default.Code -eq 2) 'default inventory exit preserved with absent toolchain'
    $defaultReport = $default.Text | ConvertFrom-Json
    Assert (@($defaultReport.components | Where-Object component -like 'issue-*').Count -eq 0) 'default excludes issue setup'
    foreach ($extra in @(), @('-Fix')) {
        $run = Invoke-Inert $allPath (@('-Json', '-IncludeIssueSetup', '-Repository', $Repository) + $extra)
        Assert ($run.Code -eq 2) 'opt-in attention exit'
        $report = $run.Text | ConvertFrom-Json
        $issues = @($report.components | Where-Object component -like 'issue-*')
        Assert ($issues.Count -eq 2) 'two opt-in components'
        Assert (@($issues | Where-Object detail -notmatch 'live state unknown').Count -eq 0) 'real argv accepted; unknown exit0 nonready'
        Assert ($run.Text -notmatch 'UNTRUSTED') 'no raw producer output at process boundary'
    }
    foreach ($extra in @(), @('-Apply')) {
        $run = Invoke-Inert $chainPath (@('-Json', '-IncludeIssueSetup', '-Repository', $Repository) + $extra)
        Assert ($run.Code -eq 0) 'report-first rollup exit preserved'
        $report = $run.Text | ConvertFrom-Json
        Assert (-not $report.ready) 'rollup degraded with unknown issue state'
        foreach ($kind in 'labels', 'milestones') {
            $expected = "pwsh scripts/github/apply-$kind.ps1 -Repository $Repository -Json"
            Assert (@($report.ownerActions | Where-Object { $_ -ceq $expected }).Count -eq 1) 'deduped owner aggregation'
        }
        Assert ($run.Text -notmatch 'UNTRUSTED') 'rollup contains no raw producer output'
    }
    $run = Invoke-Inert $chainPath @('-Json', '-Repository', $Repository)
    Assert ($run.Text -notmatch 'issue-labels|issue-milestones|apply-labels|apply-milestones') 'repository alone does not opt in'
    # Parameter guards must fail BEFORE any dependency is accessed.
    Remove-Item (Join-Path $sandbox 'scripts/build') -Recurse
    foreach ($entrypoint in $allPath, $chainPath) {
        foreach ($bad in '', 'owner', 'https://github.com/owner/repo', 'a/b/c', 'a/b;exit', 'a/..', "a/b`n", '-a/b') {
            $argv = @('-IncludeIssueSetup')
            if ($bad) { $argv += @('-Repository', $bad) }
            $run = Invoke-Inert $entrypoint $argv
            Assert ($run.Code -ne 0 -and $run.Text.Trim() -eq '') 'invalid/missing target fails before execution'
        }
    }
    Assert ($global:LASTEXITCODE -ne 0) 'expected failure leaves native exit state nonzero'
    Write-Host "PASS: $checks offline assertions (AST, strict reports, inert forwarding, owner aggregation, no mutation)."
}
finally {
    Remove-Item -LiteralPath $sandbox -Recurse -Force
}
# GitHub Actions appends `if (Test-Path variable:\LASTEXITCODE) { exit $LASTEXITCODE }`.
# Expected nonzero fixture exits above must not turn a passing test step red.
exit 0
