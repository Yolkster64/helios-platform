#Requires -Version 7.3
$ErrorActionPreference = 'Stop'
$PSNativeCommandArgumentPassing = 'Standard'
$launcher = Join-Path $PSScriptRoot 'scripts/bootstrap/connect.py'
foreach ($name in @('python3', 'python', 'py')) {
    $candidate = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue |
        Where-Object { $_.Source -notlike '*WindowsApps*' } | Select-Object -First 1
    if ($candidate) {
        if ($name -eq 'py') { & $candidate.Source -3 $launcher @args }
        else { & $candidate.Source $launcher @args }
        exit $LASTEXITCODE
    }
}
Write-Error 'HELIOS requires Python 3.10 or newer.'
exit 2
