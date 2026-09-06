# Load production functions/blocks through AST; entrypoints and network are never run.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Read-Ast($Path) {
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root $Path),[ref]$tokens,[ref]$errors)
    if ($errors.Count) { throw "Parse failed: $Path" }; return $ast
}
function Import-Functions($Ast) {
    foreach ($f in $Ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$true)) {
        Set-Item "Function:script:$($f.Name)" -Value $f.Body.GetScriptBlock()
    }
}
function Assert-True($Value,$Message) { if (-not $Value) { throw $Message }; $script:cases++ }
$script:cases=0
$rest=Read-Ast 'scripts/verify/rest-connect.ps1'
$doctor=Read-Ast 'scripts/bootstrap/auth-doctor.ps1'
$auto=Read-Ast 'scripts/bootstrap/auto-login.ps1'
$names=@('AZURE_CLIENT_ID','AZURE_TENANT_ID','AZURE_CLIENT_SECRET','AZURE_CLIENT_CERTIFICATE_PATH',
    'AZURE_FEDERATED_TOKEN_FILE','GITHUB_ACTIONS','ACTIONS_ID_TOKEN_REQUEST_URL','ACTIONS_ID_TOKEN_REQUEST_TOKEN',
    'IDENTITY_ENDPOINT','IDENTITY_HEADER','MSI_ENDPOINT','MSI_SECRET','GITHUB_TOKEN',
    'AZURE_AUTHORITY_HOST','AZURE_RESOURCE_MANAGER_ENDPOINT','ARM_ENDPOINT','LINEAR_API_KEY','SLACK_WEBHOOK_URL')
$saved=@{}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('helios-auth-boundary-'+[guid]::NewGuid())
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    foreach ($name in $names) { $saved[$name]=[Environment]::GetEnvironmentVariable($name); [Environment]::SetEnvironmentVariable($name,$null) }
    Import-Functions $rest
    foreach ($hostValue in @('127.999.999.999','127.256.0.1','127.0.0.1.evil.example','192.168.1.1','[::2]','127.0.0.1','[::1]','localhost')) {
        $notes=[Collections.Generic.List[string]]::new()
        $result=Test-TrustedManagedIdentityEndpoint -Value "http://${hostValue}:41333/msi/token" -Label IDENTITY_ENDPOINT -Notes $notes
        Assert-True (([bool]$result) -eq ($hostValue -in @('127.0.0.1','[::1]','localhost'))) 'Invalid numeric host passed loopback trust.'
    }
    $tokens=Join-Path $temp 'tokens'; $outside=Join-Path $temp 'outside'
    New-Item -ItemType Directory -Path $tokens,$outside,(Join-Path $tokens 'nested') | Out-Null
    $inside=Join-Path $tokens 'nested/normal.key'; $secret=Join-Path $outside 'dummy.key'
    Set-Content $inside 'dummy-inside'; Set-Content $secret 'dummy-outside'
    Assert-True ((Get-TrustedArcKeyPath $inside @($tokens)) -eq $inside) 'Ordinary nested Arc key refused.'
    Assert-True (-not (Get-TrustedArcKeyPath $secret @($tokens))) 'Outside Arc key accepted.'
    Assert-True (-not (Get-TrustedArcKeyPath (Join-Path $tokens '../outside/dummy.key') @($tokens))) 'Arc traversal accepted.'
    Assert-True (-not (Get-TrustedArcKeyPath (Join-Path $tokens 'missing.key') @($tokens))) 'Uninspectable key accepted.'
    New-Item -ItemType SymbolicLink -Path (Join-Path $tokens 'link') -Target $outside | Out-Null
    New-Item -ItemType SymbolicLink -Path (Join-Path $tokens 'leaf.key') -Target $secret | Out-Null
    New-Item -ItemType SymbolicLink -Path (Join-Path $temp 'linked-base') -Target $tokens | Out-Null
    Assert-True (-not (Get-TrustedArcKeyPath (Join-Path $tokens 'link/dummy.key') @($tokens))) 'Ancestor symlink escaped token directory.'
    Assert-True (-not (Get-TrustedArcKeyPath (Join-Path $tokens 'leaf.key') @($tokens))) 'Leaf symlink escaped token directory.'
    Assert-True (-not (Get-TrustedArcKeyPath (Join-Path $temp 'linked-base/nested/normal.key') @((Join-Path $temp 'linked-base')))) 'Linked token base accepted.'

    function Forbidden-Cli { throw 'Alternate CLI identity was attempted.' }
    function Get-CliCommand { param($Name) [pscustomobject]@{Source='Forbidden-Cli'} }
    $azureCloud=[pscustomobject]@{Warnings=@();Unresolved=$false;Name='AzureCloud';Authority='https://login.microsoftonline.com';ArmResource='https://management.azure.com';Source='fixture'}
    $armScope='https://management.azure.com/.default'; $armResource='https://management.azure.com'; $TimeoutSeconds=1
    $env:IDENTITY_ENDPOINT='http://127.0.0.1:41333/msi/token'; $env:IDENTITY_HEADER='dummy-header'
    $env:MSI_ENDPOINT='http://127.0.0.1:41334/msi/token'; $env:MSI_SECRET='dummy-secret'
    function Invoke-HttpProbe {
        param($Url,$Headers,$TimeoutSec,[switch]$NoProxy)
        if ($Url -notlike 'http://127.0.0.1:41333/*') { throw 'Alternate identity endpoint was attempted.' }
        $script:calls++; [pscustomobject]@{Status=$script:status;Body='{}';Transport='inert'}
    }
    foreach ($status in @(0,200,400,401,403,429,500)) {
        $script:status=$status; $script:calls=0
        $result=Test-AzureLane
        $expected=if ($status -in @(400,401,403)) {'needs-owner'} else {'unavailable'}
        Assert-True ($result.state -eq $expected -and $script:calls -eq 1 -and $result.source -eq 'managed-identity (identity-endpoint)') 'Selected MI failure was hidden.'
    }
    $env:IDENTITY_ENDPOINT='http://127.999.999.999:41333/msi/token'; $script:calls=0
    $result=Test-AzureLane
    Assert-True ($result.state -eq 'needs-owner' -and $script:calls -eq 0) 'Rejected preferred endpoint fell through.'

    $script:knownAzureClouds=@(
        [pscustomobject]@{Name='AzureCloud';Authority='login.microsoftonline.com';Arm='management.azure.com'},
        [pscustomobject]@{Name='AzureUSGovernment';Authority='login.microsoftonline.us';Arm='management.usgovcloudapi.net'})
    $script:knownAzureAuthorityHosts=@($script:knownAzureClouds.Authority)
    $script:knownAzureArmHosts=@($script:knownAzureClouds.Arm)
    foreach ($cloud in $script:knownAzureClouds) {
        $env:AZURE_AUTHORITY_HOST='https://'+$cloud.Authority; $env:ARM_ENDPOINT='https://'+$cloud.Arm
        $resolved=Resolve-AzureCloudEndpoints
        Assert-True (([bool]$resolved.Unresolved) -eq ($cloud.Name -ne 'AzureCloud')) 'Probe claimed unsupported runtime cloud readiness.'
    }

    Import-Functions $doctor
    $Apply=$true; $inCloudShell=$false; $inActions=$false; $UseManagedIdentity=$false; $Json=$true
    $env:AZURE_CLIENT_ID='dummy-client'; $env:AZURE_TENANT_ID='dummy-tenant'
    $env:AZURE_CLIENT_CERTIFICATE_PATH=$inside
    function Get-CliCommand {param($Name) [pscustomobject]@{Source='Fake-Az'}}
    function Invoke-Probe {
        param($Executable,$Arguments)
        if ($Arguments[0] -eq 'login') {
            $script:logins.Add(($Arguments -join ' '))
            if ($Arguments -contains '--certificate') { return [pscustomobject]@{ExitCode=0;Output=@()} }
            return [pscustomobject]@{ExitCode=$script:secretExit;Output=@('AADSTS7000215')}
        }
        if ($Arguments[1] -eq 'show') { return [pscustomobject]@{ExitCode=1;Output=@()} }
        [pscustomobject]@{ExitCode=0;Output=@()}
    }
    foreach ($exitCode in @(0,1)) {
        $env:AZURE_CLIENT_SECRET='dummy-secret'; $script:secretExit=$exitCode; $script:logins=[Collections.Generic.List[string]]::new()
        $result=Test-AzLane
        $expected=if ($exitCode -eq 0) {'repaired'} else {'needs-owner'}
        Assert-True ($result.state -eq $expected -and $script:logins.Count -eq 1 -and $script:logins[0] -match '--password' -and $script:logins[0] -notmatch '--certificate') 'Certificate masked selected secret.'
    }
    $env:AZURE_CLIENT_SECRET=$null; $script:logins=[Collections.Generic.List[string]]::new()
    $result=Test-AzLane
    Assert-True ($result.state -eq 'repaired' -and $script:logins[0] -match '--certificate') 'Certificate-only repair stopped working.'

    Import-Functions $auto
    $ownerActions=[Collections.Generic.List[object]]::new(); $steps=[Collections.Generic.List[object]]::new()
    $Json=$true; $env:GITHUB_TOKEN='dummy-token'; $ghTokenForeignReaders=@(); $ghModelsScopeProven=$false
    $aihubConfigLabel='fixture'; $aihubConfigPath='fixture'; $blankSecretBlocker=''; $blankSecretNames=@(); $blankSecretPrincipalGap=''
    $blankGhModels=@([pscustomobject]@{Name='fixture-models';SecretName='';Public=$true})
    $loop=$auto.Find({param($n) $n -is [Management.Automation.Language.ForEachStatementAst] -and $n.Extent.Text.StartsWith('foreach ($blank in $blankGhModels)')},$true)
    foreach ($verdict in @('proven','unverifiable')) {
        $ownerActions.Clear(); $steps.Clear(); $ghTokenVerdict=$verdict
        & ([scriptblock]::Create($loop.Extent.Text))
        Assert-True (($ownerActions.Count -gt 0) -eq ($verdict -eq 'unverifiable')) 'Unverifiable model permission lost owner action.'
        Assert-True (($steps[0].state -eq 'needs-owner') -eq ($verdict -eq 'unverifiable')) 'Unverifiable model permission marked ready.'
    }
    $import=$auto.Find({param($n) $n -is [Management.Automation.Language.ForEachStatementAst] -and $n.Extent.Text.StartsWith('foreach ($lane in @($doctorReport.lanes))')},$true)
    $reconcile=$auto.Find({param($n) $n -is [Management.Automation.Language.ForEachStatementAst] -and $n.Extent.Text.StartsWith('foreach ($action in $ownerActions)')},$true)
    function Test-EnvSatisfied {param($Name) $true}
    $envNameRegexOptions=[Text.RegularExpressions.RegexOptions]::None
    foreach ($name in @('LINEAR_API_KEY','SLACK_WEBHOOK_URL')) {
        $ownerActions.Clear(); $doctorReport=[pscustomobject]@{lanes=@([pscustomobject]@{lane='connector';state='needs-owner';ownerAction="gh secret set $name --repo fixture/project"})}
        & ([scriptblock]::Create($import.Extent.Text))
        $exportResolvableEnvNames=@($name); $resolvedActionCount=0; $remainingOwnerActions=[Collections.Generic.List[string]]::new()
        & ([scriptblock]::Create($reconcile.Extent.Text))
        Assert-True ($remainingOwnerActions.Count -eq 1) 'Local export retired repository-secret action.'
    }
} finally {
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name,$saved[$name]) }
    Remove-Item -LiteralPath $temp -Recurse -Force
}
Write-Output "Passed $script:cases offline auth boundary cases."
