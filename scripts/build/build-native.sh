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
  # Release optimization. CMake's Release config implies -O3 -DNDEBUG for GCC/Clang
  # (and CMakeLists.txt adds -O3 -ffast-math per-target), but we pass it explicitly
  # so the intent survives toolchain-default changes. Link-time optimization (-flto,
  # via CMake's IPO switch, which handles both compile and link flags) is added only
  # after a compile+link probe: the numeric scoring loops benefit from cross-TU
  # inlining, but older g++ (< 4.9) or toolchains missing the linker LTO plugin
  # would fail the real build, so an unsupported toolchain silently keeps LTO off
  # instead of breaking CI or dev machines.
  ipo=OFF
  probe_cxx="${CXX:-g++}"
  if command -v "$probe_cxx" >/dev/null 2>&1; then
    probe_dir="$(mktemp -d)"
    trap 'rm -rf "$probe_dir"' EXIT
    printf 'int main() { return 0; }\n' > "$probe_dir/probe.cpp"
    if "$probe_cxx" -O3 -flto "$probe_dir/probe.cpp" -o "$probe_dir/probe" >/dev/null 2>&1; then
      ipo=ON
    fi
  fi
  echo "Release flags: -O3 (LTO/IPO: $ipo)"
  cmake -S "$src" -B "$src/build" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_FLAGS_RELEASE="-O3 -DNDEBUG" \
    -DCMAKE_INTERPROCEDURAL_OPTIMIZATION="$ipo"
  cmake --build "$src/build" --config Release
  echo "Built: $(ls "$src"/build/libhelios_aihub_native.* 2>/dev/null || ls "$src"/build/Release/helios_aihub_native.* 2>/dev/null)"
fi
