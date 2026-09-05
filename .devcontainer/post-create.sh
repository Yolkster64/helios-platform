#!/usr/bin/env bash
# Build the checked-out portable solution. Required failures stop initialization.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if command -v cmake >/dev/null 2>&1 && command -v g++ >/dev/null 2>&1; then
  bash scripts/build/build-native.sh
else
  echo 'Native compiler unavailable; using the supported managed implementation.'
fi

dotnet restore HELIOS.sln
dotnet build HELIOS.sln -c Release --no-restore
python3 -m pip install -e 'src/ai/python[dev]'

# Resolve the output framework from the project instead of retaining a stale
# net8.0 path when the solution advances to another SDK.
target_framework="$(python3 - <<'PY'
import xml.etree.ElementTree as ET
project = ET.parse('src/ai/HELIOS.AIHub.Cli/HELIOS.AIHub.Cli.csproj')
target = project.findtext('./PropertyGroup/TargetFramework')
if not target:
    raise SystemExit('CLI TargetFramework is missing')
print(target)
PY
)"
cli_path="$repo_root/src/ai/HELIOS.AIHub.Cli/bin/Release/$target_framework/helios-ai"
test -x "$cli_path"
sudo ln -sf "$cli_path" /usr/local/bin/helios-ai
echo 'Portable solution built. Run the setup inventory to check accounts and integrations.'
