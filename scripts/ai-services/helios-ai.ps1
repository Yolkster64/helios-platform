# Thin PowerShell wrapper for the cross-LLM shell. All logic lives in the C# CLI
# (src/ai/HELIOS.AIHub.Cli); this exists so PowerShell-based automation and profiles can
# call `helios-ai` before the binary is on PATH. Requires the .NET 10 SDK.
#
# Usage: ./scripts/ai-services/helios-ai.ps1 status
#        ./scripts/ai-services/helios-ai.ps1 ask "explain this error" --provider anthropic

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
$project = Join-Path $repoRoot 'src/ai/HELIOS.AIHub.Cli/HELIOS.AIHub.Cli.csproj'

dotnet run --project $project -c Release -- @args
exit $LASTEXITCODE
