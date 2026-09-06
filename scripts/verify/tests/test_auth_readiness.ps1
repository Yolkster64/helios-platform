# Exercise production functions with inert HTTP/CLI boundaries; never run login entrypoints.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Read-Ast($Path) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $Path), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "Parse failed: $Path" }
    return $ast
}
$rest = Read-Ast 'scripts/verify/rest-connect.ps1'
$doctor = Read-Ast 'scripts/bootstrap/auth-doctor.ps1'
$auto = Read-Ast 'scripts/bootstrap/auto-login.ps1'
function Import-Functions($Ast) {
    foreach ($f in $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        Set-Item "Function:script:$($f.Name)" -Value $f.Body.GetScriptBlock()
    }
}
$names = @('AZURE_CLIENT_ID','AZURE_TENANT_ID','AZURE_CLIENT_SECRET','AZURE_CLIENT_CERTIFICATE_PATH',
    'AZURE_FEDERATED_TOKEN_FILE','GITHUB_ACTIONS','ACTIONS_ID_TOKEN_REQUEST_URL','ACTIONS_ID_TOKEN_REQUEST_TOKEN',
    'IDENTITY_ENDPOINT','IDENTITY_HEADER','MSI_ENDPOINT','MSI_SECRET','GH_TOKEN','GITHUB_TOKEN','AZURE_KEY_VAULT_URI','TEST_ENDPOINT')
$saved = @{}
$script:cases = 0
function Assert-True($Value, $Message) { if (-not $Value) { throw $Message }; $script:cases++ }
try {
    foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name); [Environment]::SetEnvironmentVariable($name, $null) }
    Import-Functions $rest
    function Forbidden-Cli { throw 'A later CLI identity was attempted.' }
    function Get-CliCommand { param($Name) [pscustomobject]@{Source='Forbidden-Cli'} }
    $azureCloud = [pscustomobject]@{ Warnings=@(); Unresolved=$false; Name='AzureCloud'; Authority='https://login.microsoftonline.com'; ArmResource='https://management.azure.com'; Source='fixture' }
    $armScope = 'https://management.azure.com/.default'
    $armResource = 'https://management.azure.com'
    $armSubscriptionsUrl = 'https://management.azure.com/subscriptions?api-version=2022-12-01'
    $TimeoutSeconds = 1
    function Invoke-HttpProbe {
        param($Url, $Method, $Body, $Headers, $ContentType, $TimeoutSec, [switch]$NoProxy, $MaximumRedirection)
        $script:calls++
        if ($Url -eq $armSubscriptionsUrl) { return [pscustomobject]@{ Status=$script:armStatus; Body=$script:armBody; Transport='inert' } }
        if ($Url -like 'https://login.microsoftonline.com/*/oauth2/v2.0/token' -or $Url -like 'http://127.0.0.1:41333/*') {
            return [pscustomobject]@{ Status=200; Body='{"access_token":"dummy-token"}'; Transport='' }
        }
        throw 'Unexpected credential request.'
    }
    $assertion = New-TemporaryFile
    Set-Content -LiteralPath $assertion -Value 'dummy-assertion' -NoNewline
    try {
        foreach ($kind in @('env-service-principal','workload-identity','managed-identity (identity-endpoint)')) {
            $env:AZURE_CLIENT_ID='client-a'; $env:AZURE_TENANT_ID='tenant-a'
            $env:AZURE_CLIENT_SECRET = if ($kind -eq 'env-service-principal') { 'dummy-secret' } else { $null }
            $env:AZURE_FEDERATED_TOKEN_FILE = if ($kind -eq 'workload-identity') { "$assertion" } else { $null }
            $env:IDENTITY_ENDPOINT='http://127.0.0.1:41333/msi/token'; $env:IDENTITY_HEADER='dummy-header'
            foreach ($status in @(200,401,403,429,500,0)) {
                $script:armStatus=$status; $script:armBody='{"value":[]}'; $script:calls=0
                $result=Test-AzureLane
                $expected=if ($status -eq 200) { 'ready' } elseif ($status -in 401,403) { 'needs-owner' } else { 'unavailable' }
                Assert-True ($result.state -eq $expected -and $result.source -eq $kind -and $script:calls -eq 2) "ARM $status lost selected identity $kind."
            }
            $script:armStatus=200; $script:armBody='{"value":null}'; $script:calls=0
            $result=Test-AzureLane
            Assert-True ($result.state -eq 'unavailable' -and $result.source -eq $kind -and $script:calls -eq 2) 'Malformed ARM response fell through.'
        }
    } finally { Remove-Item -LiteralPath $assertion -Force }

    # A case-distinct stored GitHub token must remain a separate candidate.
    function Fake-Gh { $global:LASTEXITCODE=0; 'dummy-case-token' }
    function Get-CliCommand { param($Name) [pscustomobject]@{ Source='Fake-Gh' } }
    function Get-ConfiguredGitHubModelsEnvs { @() }
    $script:nonGitHubReaderEnvs=[Collections.Generic.HashSet[string]]::new()
    $script:candidateNotes=[Collections.Generic.List[string]]::new()
    $script:paddedEnvSources=[Collections.Generic.List[string]]::new()
    $env:GH_TOKEN='DUMMY-CASE-TOKEN'
    $candidates=@(Get-GitHubTokenCandidates)
    Assert-True ($candidates.Count -eq 2) 'Case-distinct GitHub token was deduplicated.'
    $env:GH_TOKEN='dummy-case-token'
    Assert-True (@(Get-GitHubTokenCandidates).Count -eq 1) 'Identical GitHub token was not deduplicated.'

    Import-Functions $doctor
    function Get-RepositorySecretState { param($Name) [pscustomobject]@{ State=$script:repoState; Reason='fixture' } }
    function Test-EnvValue { param($Name) $script:localSet }
    foreach ($local in @($false,$true)) {
        $script:localSet=$local
        foreach ($state in @('unknown','absent','configured')) {
            $script:repoState=$state
            $lane=Get-ConnectorSecretLane -Lane slack -Name SLACK_WEBHOOK_URL -Declared fixture -Workflow fixture -Purpose fixture -OwnerAction fixture
            $expected=if ($state -eq 'unknown') { 'unavailable' } elseif ($state -eq 'absent') { 'needs-owner' } else { 'ready' }
            Assert-True ($lane.state -eq $expected) 'Local variable masked repository-secret state.'
        }
    }
    function Test-EnvValue { param($Name) -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($Name)) }
    function Get-HubCredentialKind { 'environment service principal' }
    function Get-CliCommand { param($Name) [pscustomobject]@{ Source='Fake-Az' } }
    function Invoke-Probe {
        param($Executable,$Arguments)
        if ($Arguments[0] -eq 'account') { return [pscustomobject]@{ ExitCode=0; Output=$script:accountJson } }
        if ($Arguments[2] -eq 'list') { return [pscustomobject]@{ ExitCode=0; Output='dummy-secret-name' } }
        return [pscustomobject]@{ ExitCode=0; Output='https://fixture.vault.azure.net/secrets/dummy-secret-name' }
    }
    $env:AZURE_KEY_VAULT_URI='https://fixture.vault.azure.net/'
    $blank=@([pscustomobject]@{ Name='fixture'; SecretName='dummy-secret-name' })
    foreach ($tenant in @('tenant-a','tenant-b','')) {
        $script:accountJson=@{ type='servicePrincipal'; name='client-a'; tenantId=$tenant } | ConvertTo-Json -Compress
        $result=@(Get-BlankVaultChecks -Blank $blank -AzResult ([pscustomobject]@{ state='ready'; ownerAction='' }))[0]
        Assert-True (($result.Status -eq 'present') -eq ($tenant -eq 'tenant-a')) 'Doctor credited another tenant with vault access.'
    }
    Import-Functions $auto
    function Fake-Az { $global:LASTEXITCODE=0; $script:accountJson }
    $azCmd=[pscustomobject]@{ Source='Fake-Az' }
    foreach ($tenant in @('tenant-a','tenant-b','')) {
        $script:accountJson=@{ type='servicePrincipal'; name='client-a'; tenantId=$tenant } | ConvertTo-Json -Compress
        Assert-True ((Test-HubPrincipalIsAzLogin -Kind 'environment service principal') -eq ($tenant -eq 'tenant-a')) 'Auto-login credited another tenant.'
    }
    # Run the actual blank-entry loop with inert reporting; catches endpoint checks
    # being bypassed by either secret-backed or Entra-only entries.
    $loop=$auto.Find({ param($n) $n -is [System.Management.Automation.Language.ForEachStatementAst] -and $n.Extent.Text.StartsWith('foreach ($blank in @($blankEnvProviders | Where-Object') },$true)
    if (-not $loop) { throw 'Blank-entry loop not found.' }
    function Add-OwnerAction { param($Text) $script:actions.Add($Text) }
    function Add-Step { param($Step,$State,$Detail) $script:steps.Add([pscustomobject]@{Step=$Step;State=$State}) }
    $aihubConfigLabel='fixture'
    # The Entra-capable type list the loop reads, evaluated from the script's own literal.
    $entraTypesNode=$auto.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$entraProviderTypes' },$true)
    if (-not $entraTypesNode) { throw 'Entra provider type list not found.' }
    $entraProviderTypes=Invoke-Expression $entraTypesNode.Right.Extent.Text
    foreach ($secret in @('','dummy-secret-name')) {
        foreach ($endpoint in @('','bad endpoint','https://fixture.openai.azure.com/')) {
            $env:TEST_ENDPOINT=$endpoint
            $script:actions=[Collections.Generic.List[string]]::new(); $script:steps=[Collections.Generic.List[object]]::new()
            $blankEnvProviders=@([pscustomobject]@{ Name='azure-test'; Type='azure-openai'; SecretName=$secret; EndpointEnv='TEST_ENDPOINT'; BaseUrl='' })
            & ([scriptblock]::Create($loop.Extent.Text))
            $bad=@($script:steps | Where-Object State -eq 'needs-owner').Count -gt 0
            Assert-True ($bad -eq ($endpoint -notlike 'https://*')) 'Blank-key Azure endpoint state was hidden.'
        }
        # The Foundry twin: a bare resource name is usable, a padded one is not.
        foreach ($resource in @('','helios aijcut','fixture-foundry')) {
            $env:TEST_ENDPOINT=$resource
            $script:actions=[Collections.Generic.List[string]]::new(); $script:steps=[Collections.Generic.List[object]]::new()
            $blankEnvProviders=@([pscustomobject]@{ Name='foundry-test'; Type='anthropic-foundry'; SecretName=$secret; EndpointEnv='TEST_ENDPOINT'; BaseUrl='' })
            & ([scriptblock]::Create($loop.Extent.Text))
            $bad=@($script:steps | Where-Object State -eq 'needs-owner').Count -gt 0
            Assert-True ($bad -eq ($resource -ne 'fixture-foundry')) 'Blank-key Foundry resource state was hidden.'
        }
    }
} finally {
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name,$saved[$name]) }
}
Write-Output "Passed $script:cases offline auth readiness cases."
