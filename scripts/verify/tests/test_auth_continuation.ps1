# Offline regressions: load function definitions through the parser, never execute
# either script's entrypoint. All HTTP and CLI boundaries are inert replacements.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
foreach ($entry in @(
    @{ Path = 'scripts/verify/rest-connect.ps1'; Names = @() },
    @{ Path = 'scripts/bootstrap/auth-doctor.ps1'; Names = @('Get-VaultPullHint', 'Test-EnvNameEquals') }
)) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $entry.Path), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "Parse failed: $($entry.Path)" }
    foreach ($definition in $ast.EndBlock.Statements) {
        if ($definition -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            ($entry.Names.Count -eq 0 -or $definition.Name -in $entry.Names)) {
            Set-Item "Function:script:$($definition.Name)" -Value $definition.Body.GetScriptBlock()
        }
    }
}

function Get-CliCommand { param($Name) return $null }
function Invoke-HttpProbe {
    param($Url, $Method, $Body, $ContentType, $TimeoutSec)
    $script:ProbeCalls++
    if ($Method -ne 'Post' -or $Url -notlike 'https://login.microsoftonline.com/*/oauth2/v2.0/token') {
        throw 'A later credential was attempted after the selected environment credential failed.'
    }
    return [pscustomobject]@{ Status = $script:ProbeStatus; Body = $script:ProbeBody; Transport = 'inert transport failure' }
}
function Invoke-ArmProbe {
    param($Token, $Source, $Identity, $ChainNotes)
    if ($Token -ne 'inert-access-token') { throw 'Unexpected token' }
    return [pscustomobject]@{ Outcome = 'ready'; Lane = (New-LaneResult -Lane azure -State ready -Source $Source -Detail 'inert ARM response') }
}

$azureCloud = [pscustomobject]@{ Warnings=@(); Unresolved=$false; Name='AzureCloud'; Authority='https://login.microsoftonline.com'; ArmResource='https://management.azure.com'; Source='offline fixture' }
$armScope = 'https://management.azure.com/.default'
$TimeoutSeconds = 1
$script:ProbeBody = '{"error":"dummy-secret-must-not-leak"}'
$script:ProbeStatus = 400
$script:ProbeCalls = 0

# Isolate all environment names the tested lane reads, then restore them even
# on assertion failure. Fake credentials never reach a real request boundary.
$names = @('AZURE_CLIENT_ID','AZURE_TENANT_ID','AZURE_CLIENT_SECRET','AZURE_CLIENT_CERTIFICATE_PATH',
    'AZURE_FEDERATED_TOKEN_FILE','GITHUB_ACTIONS','ACTIONS_ID_TOKEN_REQUEST_URL',
    'ACTIONS_ID_TOKEN_REQUEST_TOKEN','IDENTITY_ENDPOINT','IDENTITY_HEADER','MSI_ENDPOINT','MSI_SECRET')
$saved = @{}
try {
    foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name); [Environment]::SetEnvironmentVariable($name, $null) }
    $env:AZURE_CLIENT_ID = 'inert-client'
    $env:AZURE_TENANT_ID = 'inert-tenant'
    $env:AZURE_CLIENT_SECRET = 'dummy-secret-must-not-leak'
    # A later managed identity is deliberately present. It must not be probed.
    $env:IDENTITY_ENDPOINT = 'http://127.0.0.1:42333/msi/token'
    $env:IDENTITY_HEADER = 'inert-header'
    foreach ($status in @(400,401,403,0,429,500,200)) {
        $script:ProbeStatus = $status; $script:ProbeCalls = 0
        $result = Test-AzureLane
        $expected = if ($status -in 400,401,403) { 'needs-owner' } else { 'unavailable' }
        if ($result.state -ne $expected -or $result.source -ne 'env-service-principal') {
            throw "HTTP $status did not preserve the selected credential failure."
        }
        if ($script:ProbeCalls -ne 1) { throw "HTTP $status attempted another credential." }
        if (($result | ConvertTo-Json -Depth 5) -like '*dummy-secret-must-not-leak*') { throw 'Secret/body leaked into evidence.' }
    }
    $script:ProbeStatus = 200; $script:ProbeBody = '{"access_token":"inert-access-token"}'
    if ((Test-AzureLane).state -ne 'ready') { throw 'Successful selected credential no longer reports ready.' }

    # Rung 2b (workload identity) follows the same continuation policy: the federated
    # assertion is the selected credential, so its rejection or transient failure is
    # never masked by the managed identity that is still deliberately present.
    $env:AZURE_CLIENT_SECRET = $null
    $assertionFile = Join-Path ([IO.Path]::GetTempPath()) ("helios-inert-assertion-" + [Guid]::NewGuid().ToString('N') + '.jwt')
    Set-Content -LiteralPath $assertionFile -Value 'inert-assertion-must-not-leak' -NoNewline
    $env:AZURE_FEDERATED_TOKEN_FILE = $assertionFile
    try {
        $script:ProbeBody = '{"error":"inert-assertion-must-not-leak"}'
        foreach ($status in @(400,401,403,0,429,500,200)) {
            $script:ProbeStatus = $status; $script:ProbeCalls = 0
            $result = Test-AzureLane
            $expected = if ($status -in 400,401,403) { 'needs-owner' } else { 'unavailable' }
            if ($result.state -ne $expected -or $result.source -ne 'workload-identity') {
                throw "Workload identity HTTP $status did not preserve the selected credential failure."
            }
            if ($script:ProbeCalls -ne 1) { throw "Workload identity HTTP $status attempted another credential." }
            if (($result | ConvertTo-Json -Depth 5) -like '*inert-assertion-must-not-leak*') { throw 'Assertion/body leaked into evidence.' }
        }
        $script:ProbeStatus = 200; $script:ProbeBody = '{"access_token":"inert-access-token"}'
        if ((Test-AzureLane).state -ne 'ready') { throw 'Successful workload identity no longer reports ready.' }
    } finally {
        Remove-Item -LiteralPath $assertionFile -Force -ErrorAction SilentlyContinue
    }
} finally {
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
}

# Exercise each OS comparison contract explicitly, regardless of CI host OS.
$script:EnvNameComparer = [StringComparer]::Ordinal
$hint = Get-VaultPullHint -SecretName openai-api-key -EnvName openai_api_key
if ($hint.StartsWith('source ')) { throw 'Unix lowercase mapping advertised the uppercase-only loader.' }
if (-not (Get-VaultPullHint -SecretName openai-api-key -EnvName OPENAI_API_KEY).StartsWith('source ')) { throw 'Built-in exact mapping lost its loader.' }
$script:EnvNameComparer = [StringComparer]::OrdinalIgnoreCase
if (-not (Get-VaultPullHint -SecretName openai-api-key -EnvName openai_api_key).StartsWith('source ')) { throw 'Windows case-insensitive mapping changed.' }
Write-Output 'Passed 19 offline authentication continuation and environment-name cases.'
