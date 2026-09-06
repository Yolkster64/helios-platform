# Exercise the reviewed production paths without invoking GitHub or setup entrypoints.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Read-Ast($Path) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $Path), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "Parse failed: $Path" }
    return $ast
}
function Import-Function($Ast, $Name) {
    $function = $Ast.Find({
        param($n)
        $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name
    }, $true)
    if (-not $function) { throw "Function not found: $Name" }
    Set-Item "Function:script:$Name" -Value $function.Body.GetScriptBlock()
}
$script:cases = 0
function Assert-True($Value, $Message) { if (-not $Value) { throw $Message }; $script:cases++ }

$setup = Read-Ast 'scripts/bootstrap/setup-everything.ps1'
Import-Function $setup 'Get-StepSummary'
$inventory = Read-Ast 'scripts/setup/setup-all.ps1'
Import-Function $inventory 'New-InformationalComponent'
foreach ($status in @('ready', 'unhealthy', 'skipped')) {
    $health = New-InformationalComponent -Name 'mcp-health' -Status $status -Detail 'fixture'
    $report = [pscustomobject]@{ ready = $true; components = @($health) }
    Assert-True ((Get-StepSummary $report 0) -eq 'ready=True') "Informational $status needs attention."
    Assert-True ($health.Fix -eq '') "Informational $status creates an owner action."
    $report.ready = $false
    $report.components += @(
        [pscustomobject]@{ component = 'legacy'; status = 'needs-attention' }
        [pscustomobject]@{ component = 'required'; status = 'needs-attention'; informational = $false }
        [pscustomobject]@{ component = 'healthy'; status = 'ready'; informational = $false }
    )
    Assert-True ((Get-StepSummary $report 0) -eq 'ready=False; needs-attention: legacy, required') 'Required failures were hidden.'
}

$provision = Read-Ast 'scripts/bootstrap/provision-github-secrets.ps1'
Import-Function $provision 'Test-EnvValue'
$loop = $provision.Find({
    param($n)
    $n -is [System.Management.Automation.Language.ForEachStatementAst] -and $n.Variable.VariablePath.UserPath -eq 'target'
}, $true)
if (-not $loop) { throw 'Provisioning loop not found.' }
function Write-Report { param($Message) $script:messages.Add($Message) }
function Fake-Gh {
    Assert-True (($args[0..5] -join ' ') -eq "variable set $fixtureName --repo $Repository --body") 'Variable must use --body.'
    Assert-True ($args.Count -eq 7 -and $args[6] -ceq $fixtureValue) 'Variable body must remain a single exact argument.'
    $script:variableCalls++
    $global:LASTEXITCODE = $script:ghExitCode
}
function Invoke-GhWithStdin {
    param($Arguments, $Value)
    Assert-True (($Arguments -join ' ') -eq "secret set $fixtureName --repo $Repository") 'Secret must not use --body.'
    Assert-True ($Value -ceq $fixtureValue) 'Secret must be passed to the stdin helper unchanged.'
    $script:secretCalls++
    [pscustomobject]@{ ExitCode = $script:ghExitCode; StdErr = '' }
}
$fixtureName = 'HELIOS_BOOTSTRAP_REVIEW_FIXTURE'
$fixtureValue = 'inert fixture with spaces'
$saved = [Environment]::GetEnvironmentVariable($fixtureName)
try {
    $gh = [pscustomobject]@{ Source = 'Fake-Gh' }
    $Repository = 'fixture/repository'
    $variableListing = $secretListing = [pscustomobject]@{ Known = $true; Names = @() }
    foreach ($Apply in @($false, $true)) {
        foreach ($present in @($false, $true)) {
            [Environment]::SetEnvironmentVariable($fixtureName, $(if ($present) { $fixtureValue } else { $null }))
            foreach ($script:ghExitCode in @(0, 1)) {
                $targets = @(
                    [pscustomobject]@{ Name = $fixtureName; Kind = 'variable'; Why = 'fixture' }
                    [pscustomobject]@{ Name = $fixtureName; Kind = 'secret'; Why = 'fixture' }
                )
                $rows = [Collections.Generic.List[object]]::new()
                $failures = [Collections.Generic.List[string]]::new()
                $script:messages = [Collections.Generic.List[string]]::new()
                $applied = 0; $skippedCount = 0
                $script:variableCalls = 0; $script:secretCalls = 0
                . ([scriptblock]::Create($loop.Extent.Text))
                $expectedCalls = [int]($Apply -and $present)
                Assert-True ($variableCalls -eq $expectedCalls -and $secretCalls -eq $expectedCalls) 'Incorrect apply/skip behavior.'
                $expectedFailures = if ($expectedCalls -and $ghExitCode -ne 0) { 2 } else { 0 }
                Assert-True ($failures.Count -eq $expectedFailures) 'Failed mutations were not reported.'
                $expectedResult = if (-not $Apply) { '' } elseif (-not $present) { 'skipped' } elseif ($ghExitCode) { 'failed (gh exited 1)' } else { 'applied' }
                Assert-True ($rows.Count -eq 2 -and @($rows | Where-Object Result -ne $expectedResult).Count -eq 0) 'Unexpected target result.'
                Assert-True (-not (($messages -join "`n") + ($rows | ConvertTo-Json)).Contains($fixtureValue)) 'Reports exposed a value.'
            }
        }
    }
}
finally { [Environment]::SetEnvironmentVariable($fixtureName, $saved) }
Write-Host "PASS: $cases bootstrap review assertions"
# Do not propagate the last mocked CLI failure through the Actions pwsh epilogue.
$global:LASTEXITCODE = 0
