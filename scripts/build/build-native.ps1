# Build the C++ spoke (helios_aihub_native) so dotnet build picks it up and
# copies it next to the AIHub/test/CLI outputs. Safe to skip: AIHub degrades
# to managed fallbacks when the library is absent.
#
# Usage: scripts/build/build-native.ps1
#Requires -Version 7
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
$src = Join-Path $repoRoot 'src/ai/HELIOS.AIHub.Native'

cmake -S $src -B (Join-Path $src 'build') -DCMAKE_BUILD_TYPE=Release
if ($LASTEXITCODE -ne 0) { throw "cmake configure failed ($LASTEXITCODE)" }
cmake --build (Join-Path $src 'build') --config Release
if ($LASTEXITCODE -ne 0) { throw "cmake build failed ($LASTEXITCODE)" }

Get-ChildItem (Join-Path $src 'build') -Recurse -Include 'helios_aihub_native.dll', 'libhelios_aihub_native.*' |
    ForEach-Object { Write-Host "Built: $($_.FullName)" }
