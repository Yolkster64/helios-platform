# Offline contract for the Azure control-plane REST reachability interpreter (issue #207,
# audit-first half) of scripts/setup/setup-all.ps1. Imports the pure
# Get-AzureControlPlaneReadiness function via the AST (same pattern as the board leg and the
# auth lanes) and exercises it against synthetic probe results. No network, no az CLI, no
# login entrypoints -- the function only classifies an exit code plus output lines.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))

function Read-Ast($Path) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $Path), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "Parse failed: $Path" }
    return $ast
}
function Import-Functions($Ast) {
    foreach ($f in $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        Set-Item "Function:script:$($f.Name)" -Value $f.Body.GetScriptBlock()
    }
}

$setupAll = Read-Ast 'scripts/setup/setup-all.ps1'
Import-Functions $setupAll

$script:cases = 0
function Assert-True($Value, $Message) { if (-not $Value) { throw $Message }; $script:cases++ }

# 1. Exit 0 is reachable-and-ready, regardless of output.
$r = Get-AzureControlPlaneReadiness -ExitCode 0 -Output @()
Assert-True ($r.Ready -and $r.Detail -match 'reachable') 'Exit 0 was not reported as reachable/ready.'

# 2. An expired/unauthorized token (ARM 401 shapes) is not-ready and points at re-login,
#    distinct from a network failure.
foreach ($authText in @(
        'AADSTS700082: The refresh token has expired',
        'InvalidAuthenticationToken',
        "ERROR: Please run 'az login' to setup account.",
        'The access token is expired, please re-authenticate')) {
    $r = Get-AzureControlPlaneReadiness -ExitCode 1 -Output @($authText)
    Assert-True (-not $r.Ready -and $r.Detail -match 'token was rejected') "Auth failure not classified: $authText"
}

# 3. A connectivity failure is not-ready and is classified as network, not auth.
foreach ($netText in @(
        'Could not resolve host: management.azure.com',
        'Temporary failure in name resolution',
        'Connection refused',
        'Network is unreachable',
        'Failed to establish a new connection')) {
    $r = Get-AzureControlPlaneReadiness -ExitCode 1 -Output @($netText)
    Assert-True (-not $r.Ready -and $r.Detail -match 'not reachable') "Network failure not classified: $netText"
}

# 4. Any other non-zero exit is not-ready and surfaces the first output line + exit code.
$r = Get-AzureControlPlaneReadiness -ExitCode 3 -Output @('', 'Some unexpected azure error', 'more')
Assert-True (-not $r.Ready -and $r.Detail -match 'exit 3' -and $r.Detail -match 'Some unexpected azure error') 'Generic failure did not surface exit code and first line.'

# 5. Empty output on a non-zero exit still yields a not-ready verdict without throwing.
$r = Get-AzureControlPlaneReadiness -ExitCode 2 -Output @()
Assert-True (-not $r.Ready -and $r.Detail -match 'exit 2') 'Empty non-zero output was not handled.'

# 6. Auth classification wins over a stray network-looking word when a 401 shape is present,
#    because the actionable fix (re-login) differs from a connectivity fix.
$r = Get-AzureControlPlaneReadiness -ExitCode 1 -Output @('AADSTS50173 token expired; connection was fine')
Assert-True (-not $r.Ready -and $r.Detail -match 'token was rejected') 'Auth precedence over network wording failed.'

Write-Output "Passed $script:cases offline Azure control-plane readiness cases."
