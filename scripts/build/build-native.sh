#!/usr/bin/env bash
# Build the C++ spoke (helios_aihub_native) so dotnet build picks it up and
# copies it next to the AIHub/test/CLI outputs. Safe to skip: AIHub degrades
# to managed fallbacks when the library is absent.
#
# Usage: scripts/build/build-native.sh [--sanitize]
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
src="$repo_root/src/ai/HELIOS.AIHub.Native"

if [[ "${1:-}" == "--sanitize" ]]; then
  cmake -S "$src" -B "$src/build-san" -DCMAKE_BUILD_TYPE=Debug -DHELIOS_SANITIZE=ON
  cmake --build "$src/build-san"
  echo "Sanitizer build: $src/build-san"
else
  cmake -S "$src" -B "$src/build" -DCMAKE_BUILD_TYPE=Release
  cmake --build "$src/build" --config Release
  echo "Built: $(ls "$src"/build/libhelios_aihub_native.* 2>/dev/null || ls "$src"/build/Release/helios_aihub_native.* 2>/dev/null)"
fi
