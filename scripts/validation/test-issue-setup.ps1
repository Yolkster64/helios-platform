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
$bash = (Get-Command bash -CommandType Application | Select-Object -First 1).Source
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
    $isBash = $Relative.EndsWith('.sh')
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = if ($isBash) { $bash } else { $pwsh }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = $sandbox
    # Never inherit any credential, cloud, or MCP environment into the fixture.
    $psi.Environment.Clear()
    $psi.Environment['PATH'] = $fixtureBin
    $psi.Environment['HOME'] = $sandbox
    $psi.Environment['USERPROFILE'] = $sandbox
    $prefix = if ($isBash) { @() } else { @('-NoProfile', '-File') }
    foreach ($arg in $prefix + @((Join-Path $sandbox $Relative)) + $Arguments) {
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
$firstPsPath = 'scripts/bootstrap/first-run.ps1'
$firstShPath = 'scripts/bootstrap/first-run.sh'
$doctorPath = 'scripts/bootstrap/auth-doctor.ps1'
$autoPath = 'scripts/bootstrap/auto-login.ps1'
$doctorAst = Read-Ast (Join-Path $root $doctorPath)
$autoAst = Read-Ast (Join-Path $root $autoPath)
$allAst = Read-Ast (Join-Path $root $allPath)
$chainAst = Read-Ast (Join-Path $root $chainPath)
$null = Read-Ast (Join-Path $root $firstPsPath)
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
    # Only these offline interpreters/utilities are reachable, never gh/az/dotnet.
    $fixtureBin = Join-Path $sandbox 'fixture-bin'
    $null = New-Item -ItemType Directory -Path $fixtureBin
    foreach ($tool in 'pwsh', 'bash', 'python3', 'dirname', 'mkdir', 'rm', 'tee', 'date', 'cat') {
        $source = (Get-Command $tool -CommandType Application | Select-Object -First 1).Source
        $null = New-Item -ItemType SymbolicLink -Path (Join-Path $fixtureBin $tool) -Target $source
    }
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
        Put-Fixture $path "param([switch]`$Json, [switch]`$Apply, [string]`$Repository)`n'{`"lanes`":[]}'`nexit 0"
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
        $run = Invoke-Inert $allPath (@('-Json', '-Repository', $Repository) + $extra)
        Assert ($run.Code -eq 2) 'automatic issue attention exit'
        $report = $run.Text | ConvertFrom-Json
        $issues = @($report.components | Where-Object component -like 'issue-*')
        Assert ($issues.Count -eq 2) 'two automatic issue components'
        Assert (@($issues | Where-Object detail -notmatch 'live state unknown').Count -eq 0) 'real argv accepted; unknown exit0 nonready'
        Assert ($run.Text -notmatch 'UNTRUSTED') 'no raw producer output at process boundary'
    }
    foreach ($extra in @(), @('-Apply')) {
        $run = Invoke-Inert $chainPath (@('-Json', '-Repository', $Repository) + $extra)
        Assert ($run.Code -eq 0) 'report-first rollup exit preserved'
        $report = $run.Text | ConvertFrom-Json
        Assert (-not $report.ready) 'rollup degraded with unknown issue state'
        foreach ($kind in 'labels', 'milestones') {
            $expected = "pwsh scripts/github/apply-$kind.ps1 -Repository $Repository -Json"
            Assert (@($report.ownerActions | Where-Object { $_ -ceq $expected }).Count -eq 1) 'deduped owner aggregation'
        }
        Assert ($run.Text -notmatch 'UNTRUSTED') 'rollup contains no raw producer output'
    }
    $run = Invoke-Inert $chainPath @('-Json')
    Assert ($run.Code -eq 0) 'no-target chain exit preserved'
    Assert ($run.Text -notmatch 'issue-labels|issue-milestones|apply-labels|apply-milestones') 'no-target chain excludes issue probes'

    # Both real first-run twins -> real setup chain -> real inventory -> inert producers.
    # Cloud setup / auto-login / provisioning are spies ONLY: never install, log in,
    # look up credentials, or run live external commands, even in full mode.
    foreach ($entrypoint in $firstPsPath, $firstShPath) {
        Put-Fixture $entrypoint (Get-Content -Raw (Join-Path $root $entrypoint))
    }
    # Real connector command producers and metadata resolver, with every probe inert.
    # A different checkout/default catches accidentally consulting origin for a target.
    $doctorFixture = $doctorAst.ParamBlock.Extent.Text + @'

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
function Test-EnvValue { param($Name) $false }
function Get-CheckoutRepositorySlug { 'Yolkster64/helios-platform' }
function Get-CliCommand { param($Name) [pscustomobject]@{ Source = 'inert-never-executed' } }
function Get-NonGitHubOwnedTokenNames { @() }
function Invoke-Probe {
    param($Executable, $Arguments)
    $expected = if ($Repository) { $Repository } else { 'Yolkster64/helios-platform' }
    if ($Arguments.Count -ne 3 -or $Arguments[0] -ne 'api' -or $Arguments[1] -ne '-i' -or
        $Arguments[2] -notlike "repos/$expected/actions/secrets*") {
        throw 'Repository metadata escaped the explicit target / no-target default'
    }
    $status = if ($Arguments[2].EndsWith('?per_page=1')) { 200 } else { 404 }
    [pscustomobject]@{ ExitCode = 0; Output = @("HTTP/2 $status") }
}
'@
    foreach ($name in 'New-LaneResult', 'Get-RepositorySecretState', 'Get-ConnectorSecretLane',
        'Test-LinearLane', 'Test-SlackLane') {
        $fn = $doctorAst.Find({ param($n)
            $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name
        }, $true)
        Assert ($null -ne $fn) "real connector producer seam: $name"
        $doctorFixture += "`n" + $fn.Extent.Text
    }
    $doctorFixture += @'

$lanes = if (Test-Path (Join-Path $repoRoot 'no-connector-lanes')) { @() }
    else { @(Test-LinearLane; Test-SlackLane) }
@{ lanes = @($lanes) } | ConvertTo-Json -Depth 6
exit 0
'@
    Put-Fixture $doctorPath $doctorFixture
    # Exercise the REAL auto-login argv construction and child invocation, not its
    # credential acquisition entrypoint. The child is the inert doctor above.
    $argsAssignment = $autoAst.Find({ param($n)
        $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $n.Left.Extent.Text -eq '$doctorArgs' -and $n.Operator -eq 'Equals'
    }, $true)
    Assert ($null -ne $argsAssignment) 'auto-login doctor argv seam'
    $forwarding = @($argsAssignment.Parent.Statements | Where-Object {
        $_.Extent.StartOffset -ge $argsAssignment.Extent.StartOffset
    })
    $autoForwarding = ''
    foreach ($statement in $forwarding) {
        $autoForwarding += "`n" + $statement.Extent.Text
        if ($statement -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $statement.Left.Extent.Text -eq '$doctorLines') { break }
    }
    Assert ($autoForwarding.Contains('$doctorLines =')) 'auto-login real child invocation captured'
    $autoEntry = $autoAst.Find({ param($n)
        $n -is [System.Management.Automation.Language.CommandAst] -and
        $n.GetCommandName() -eq 'Invoke-HeliosAutoLogin'
    }, $true)
    Assert ($autoEntry.Extent.Text.Contains('-Repository $Repository')) 'auto-login entry passes target to wrapper'
    $spyStub = @'
[CmdletBinding()]
param([switch]$Json, [switch]$VerifyOnly, [switch]$SkipSmoke, [switch]$SkipAuth,
      [switch]$UseManagedIdentity, [string]$Repository)
$name = [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$bound = @{}
foreach ($key in $PSBoundParameters.Keys) {
    $value = $PSBoundParameters[$key]
    $bound[$key] = if ($value -is [switch]) { [bool]$value } else { $value }
}
$bound | ConvertTo-Json | Set-Content (Join-Path $root "$name-spy.json")
'{"lanes":[],"targets":[],"ownerActions":[]}'
exit 0
'@
    foreach ($name in 'cloud-shell-setup', 'auto-login', 'provision-github-secrets') {
        Put-Fixture "scripts/bootstrap/$name.ps1" $spyStub
    }
    $autoFixture = $spyStub.Substring(0, $spyStub.IndexOf("'{" + '"lanes"')) + @'

$doctorPath = Join-Path $root 'scripts/bootstrap/auth-doctor.ps1'
'@ + $autoForwarding + @'

if ($LASTEXITCODE -ne 0) { throw 'Inert doctor failed' }
$report = ($doctorLines -join "`n") | ConvertFrom-Json
@{ ownerActions = @($report.lanes | ForEach-Object ownerAction) } | ConvertTo-Json -Depth 6
exit 0
'@
    Put-Fixture $autoPath $autoFixture
    Put-Fixture 'scripts/bootstrap/cloud-shell-setup.sh' 'printf "CLOUD_ARG:%s\n" "$@"; exit 0'
    foreach ($entrypoint in $firstPsPath, $firstShPath) {
        $isBash = $entrypoint.EndsWith('.sh')
        foreach ($mode in 'default', 'target', 'verify', 'skip', 'fallback') {
            $noLanes = Join-Path $sandbox 'no-connector-lanes'
            if ($mode -eq 'fallback') { Put-Fixture 'no-connector-lanes' '' }
            else { Remove-Item $noLanes -ErrorAction SilentlyContinue }
            Remove-Item (Join-Path $sandbox '*-spy.json') -Force -ErrorAction SilentlyContinue
            $argv = @(if ($isBash) { '--json' } else { '-Json' })
            if ($mode -ne 'default') {
                $argv += $(if ($isBash) { @('--repository', $Repository) } else { @('-Repository', $Repository) })
                $argv += $(if ($isBash) { '--managed-identity' } else { '-UseManagedIdentity' })
            }
            if ($mode -eq 'verify') { $argv += $(if ($isBash) { '--verify-only' } else { '-VerifyOnly' }) }
            if ($mode -eq 'skip') { $argv += $(if ($isBash) { '--skip-setup' } else { '-SkipSetup' }) }
            $run = Invoke-Inert $entrypoint $argv
            Assert ($run.Code -eq 0) "$entrypoint $mode executed: $($run.Error)"
            $state = $run.Text | ConvertFrom-Json
            Assert ($state.steps.Count -eq 6) 'all six first-run steps recorded'
            Assert (@($state.steps | Where-Object { $_.exitCode -notin 0, -1 }).Count -eq 0) 'inert first-run children succeeded'
            Assert ($state.verifyOnly -eq ($mode -eq 'verify')) 'verify-only state preserved'
            $provisionArgs = Get-Content -Raw (Join-Path $sandbox 'provision-github-secrets-spy.json') | ConvertFrom-Json -AsHashtable
            Assert ($provisionArgs.Json -eq $true) 'repo-secret dry-run JSON forwarded'
            Assert ($provisionArgs.Count -eq $(if ($mode -eq 'default') { 1 } else { 2 })) 'only JSON and explicit target reach provision; never Apply'
            if ($mode -eq 'default') {
                Assert (-not $provisionArgs.ContainsKey('Repository')) 'no target preserves provisioning default'
            } else {
                Assert ($provisionArgs.Repository -ceq $Repository) 'same target reaches provision'
            }
            $setupStep = @($state.steps | Where-Object name -eq 'setup-everything')[0]
            Assert ($setupStep.exitCode -eq $(if ($mode -eq 'skip') { -1 } else { 0 })) 'skip-setup preserved'
            $issueActions = @($state.ownerActions | Where-Object action -match 'scripts/github/apply-(labels|milestones)')
            $expectedCount = if ($mode -in 'target', 'verify', 'fallback') { 2 } else { 0 }
            Assert ($issueActions.Count -eq $expectedCount) 'automatic issues reach first-run owner checklist unless no target or skipped'
            foreach ($action in $issueActions) {
                Assert ($action.action -match "-Repository $([regex]::Escape($Repository)) -Json$") 'issue target survives entire chain'
                Assert ($action.action -notmatch '-Apply|-Fix') 'issue checklist stays dry-run'
            }
            $autoSpy = Join-Path $sandbox 'auto-login-spy.json'
            Assert ((Test-Path $autoSpy) -eq ($mode -ne 'verify')) 'automatic login retained except verify-only'
            if ($mode -ne 'verify') {
                $autoArgs = Get-Content -Raw $autoSpy | ConvertFrom-Json -AsHashtable
                Assert ($autoArgs.Json -eq $true) 'automatic login JSON unchanged'
                Assert ($autoArgs.ContainsKey('UseManagedIdentity') -eq ($mode -ne 'default')) 'managed identity forwarding preserved'
                Assert ($autoArgs.ContainsKey('Repository') -eq ($mode -ne 'default')) 'auth gets only an explicit target'
                if ($mode -ne 'default') { Assert ($autoArgs.Repository -ceq $Repository) 'same target reaches auto-login' }
            }
            if ($isBash) {
                $cloudArgs = @(Get-Content (Join-Path $sandbox '.helios/bootstrap/first-run.log') |
                    Where-Object { $_ -like 'CLOUD_ARG:*' })
                $expected = if ($mode -eq 'verify') { 'CLOUD_ARG:--verify-only' } else { 'CLOUD_ARG:--skip-smoke|CLOUD_ARG:--skip-auth' }
                Assert (($cloudArgs -join '|') -eq $expected) 'Bash cloud setup mode flags unchanged'
            } else {
                $cloudArgs = Get-Content -Raw (Join-Path $sandbox 'cloud-shell-setup-spy.json') | ConvertFrom-Json -AsHashtable
                $expected = if ($mode -eq 'verify') { 'VerifyOnly' } else { 'SkipAuth|SkipSmoke' }
                Assert ((@($cloudArgs.Keys | Sort-Object) -join '|') -eq $expected) 'PowerShell cloud setup mode flags unchanged'
            }
            $checklist = @($state.checklist.lines) -join "`n"
            $replay = 'pwsh scripts/bootstrap/provision-github-secrets.ps1 -Apply'
            if ($mode -ne 'default') { $replay += " -Repository $Repository" }
            Assert ($checklist.Contains($replay)) 'printed provision replay retains same target (not executed)'
            $repoOption = if ($mode -eq 'default') { '' } else { " --repo $Repository" }
            $secretLines = @($state.checklist.lines | Where-Object { $_ -match '^gh secret set ' })
            Assert ($secretLines.Count -eq 3) 'admin and both connector commands emitted once'
            foreach ($name in 'HELIOS_ADMIN_TOKEN', 'LINEAR_API_KEY', 'SLACK_WEBHOOK_URL') {
                $expected = "gh secret set $name$repoOption"
                $matching = @($secretLines | Where-Object { ($_ -split '#', 2)[0].Trim() -ceq $expected })
                Assert ($matching.Count -eq 1) "$entrypoint $mode exact target once, before comment: $name"
            }
            # Inspect raw child reports too: aggregation must not rewrite command text
            # or append a second --repo to an already scoped producer command.
            $actions = @($state.ownerActions | ForEach-Object action) +
                @($state.lanes.PSObject.Properties | ForEach-Object { $_.Value.ownerAction })
            foreach ($source in 'auto-login', 'setup-everything') {
                if (-not $state.reports.PSObject.Properties[$source]) { continue }
                $child = Get-Content -Raw (Join-Path $sandbox ".helios/bootstrap/$source.json") | ConvertFrom-Json
                $childSecrets = @($child.ownerActions | Where-Object { $_ -match '^gh secret set ' })
                Assert ($childSecrets.Count -eq $(if ($mode -eq 'fallback') { 0 } else { 2 })) "$source inherited secret commands present"
                $actions += $childSecrets
            }
            foreach ($action in @($actions | Where-Object { $_ -match '^gh secret set ' })) {
                $command = ($action -split '#', 2)[0].Trim()
                Assert ($command -cmatch "^gh secret set (LINEAR_API_KEY|SLACK_WEBHOOK_URL)$([regex]::Escape($repoOption))$") 'inherited command already scoped exactly once (default unchanged)'
                Assert (@($secretLines | Where-Object { $_ -ceq $action }).Count -eq 1) 'producer command preserved verbatim and deduped'
            }
        }
    }
    # Parameter guards must fail BEFORE any dependency is accessed.
    Remove-Item (Join-Path $sandbox 'scripts/build') -Recurse
    Remove-Item (Join-Path $sandbox '.helios') -Recurse -Force
    Remove-Item (Join-Path $sandbox '*-spy.json') -Force
    # Bind the actual producer parameter contracts without executing either producer.
    Put-Fixture $doctorPath ($doctorAst.ParamBlock.Extent.Text + "`nthrow 'valid target reached inert body'")
    Put-Fixture $autoPath ($autoAst.ParamBlock.Extent.Text + "`nthrow 'valid target reached inert body'")
    foreach ($entrypoint in $allPath, $chainPath, $firstPsPath, $firstShPath, $doctorPath, $autoPath) {
        $flag = if ($entrypoint.EndsWith('.sh')) { '--repository' } else { '-Repository' }
        foreach ($bad in '', ' ', 'owner', 'https://github.com/owner/repo', 'a/b/c', 'a/b;exit', 'a/..', 'a/.', "a/b`n", '-a/b', 'a-/b', 'a/r?x', ('a' * 40 + '/b'), ('a/' + 'b' * 101)) {
            $argv = @($flag, $bad)
            $run = Invoke-Inert $entrypoint $argv
            Assert ($run.Code -ne 0 -and $run.Text.Trim() -eq '') "$entrypoint invalid target fails before execution"
        }
        $run = Invoke-Inert $entrypoint @($flag)
        Assert ($run.Code -ne 0 -and $run.Text.Trim() -eq '') 'missing target value rejected'
    }
    Assert (-not (Test-Path (Join-Path $sandbox '.helios'))) 'invalid first-run target creates no state'
    Assert (@(Get-ChildItem $sandbox -Filter '*-spy.json').Count -eq 0) 'invalid first-run target invokes no child'
    Assert ($global:LASTEXITCODE -ne 0) 'expected failure leaves native exit state nonzero'
    Write-Host "PASS: $checks offline assertions (AST, strict reports, inert forwarding, owner aggregation, no mutation)."
}
finally {
    Remove-Item -LiteralPath $sandbox -Recurse -Force
}
# GitHub Actions appends `if (Test-Path variable:\LASTEXITCODE) { exit $LASTEXITCODE }`.
# Expected nonzero fixture exits above must not turn a passing test step red.
exit 0
