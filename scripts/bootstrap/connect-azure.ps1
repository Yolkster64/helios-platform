<#
.SYNOPSIS
Azure browser authentication via the device-code flow — Azure PowerShell twin of
connect-azure.sh.

.DESCRIPTION
Connect-AzAccount -UseDeviceAuthentication prints a URL + one-time code usable from
any browser on any device — identical behavior in Cloud Shell, Codespaces, SSH
sessions, and local terminals. Azure Cloud Shell starts pre-authenticated, so there
this script only verifies the context.

.EXAMPLE
pwsh scripts/bootstrap/connect-azure.ps1
pwsh scripts/bootstrap/connect-azure.ps1 -Subscription <id-or-name>
pwsh scripts/bootstrap/connect-azure.ps1 -Force
pwsh scripts/bootstrap/connect-azure.ps1 -VerifyOnly   # report auth state; never mutates
#>
[CmdletBinding()]
param(
    [string]$Subscription,
    [switch]$Force,
    [switch]$VerifyOnly
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command Connect-AzAccount -ErrorAction SilentlyContinue)) {
    Write-Error ("Az.Accounts module not found. Install-Module Az.Accounts -Scope CurrentUser " +
        "(or run scripts/bootstrap/cloud-shell-setup.sh; Cloud Shell ships it preinstalled).")
}

# Verify-only: report the auth state and stop — no login flow and no Set-AzContext
# (which mutates the persisted context). Exits 0 authenticated, non-zero when not.
if ($VerifyOnly) {
    $verifyContext = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $verifyContext) {
        Write-Error 'Azure PowerShell: not authenticated. Run scripts/bootstrap/connect-azure.ps1 to log in.'
    }
    Write-Host 'Azure PowerShell: authenticated.'
    $verifyContext | Select-Object @{n = 'Subscription'; e = { $_.Subscription.Name } },
        @{n = 'Tenant'; e = { $_.Tenant.Id } },
        @{n = 'Account'; e = { $_.Account.Id } } | Format-Table -AutoSize
    exit 0
}

$inCloudShell = [bool]($env:AZUREPS_HOST_ENVIRONMENT -or $env:ACC_CLOUD)
$context = Get-AzContext -ErrorAction SilentlyContinue

if (-not $Force -and $context) {
    $suffix = if ($inCloudShell) { ' (Cloud Shell implicit login)' } else { '' }
    Write-Host "Azure PowerShell: already authenticated$suffix."
}
elseif ($inCloudShell -and -not $Force) {
    Write-Error ("Cloud Shell session should be pre-authenticated but Get-AzContext is empty. " +
        "Try Connect-AzAccount -UseDeviceAuthentication manually — the shell token may have expired.")
}
else {
    Write-Host 'Azure PowerShell: starting device-code login (open the URL on any device and enter the code)...'
    Connect-AzAccount -UseDeviceAuthentication | Out-Null
}

if ($Subscription) {
    Set-AzContext -Subscription $Subscription | Out-Null
}

Get-AzContext | Select-Object @{n = 'Subscription'; e = { $_.Subscription.Name } },
    @{n = 'Tenant'; e = { $_.Tenant.Id } },
    @{n = 'Account'; e = { $_.Account.Id } } | Format-Table -AutoSize
