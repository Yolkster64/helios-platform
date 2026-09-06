#!/usr/bin/env bash
set -euo pipefail

repo_root="$(pwd)"
if [[ ! -f "${repo_root}/AGENTS.md" ]]; then
  echo "Expected to run from the HELIOS repository root (missing AGENTS.md)." >&2
  exit 1
fi

echo "HELIOS devcontainer bootstrap (idempotent, non-destructive)"
git config --global --add safe.directory "${repo_root}" || true

if [[ -f "${repo_root}/src/ai/python/pyproject.toml" ]]; then
  python3 -m pip install -e "${repo_root}/src/ai/python"
fi

echo "Bootstrap complete. Run required gates manually:"
echo "  dotnet build HELIOS.sln -c Release"
echo "  dotnet test tests/HELIOS.AIHub.Tests -c Release"
echo "  (cd src/ai/python && python3 -m pytest tests)"
