#!/usr/bin/env bash
set -euo pipefail
connect_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if command -v python3 >/dev/null 2>&1; then
  exec python3 "$connect_root/scripts/bootstrap/connect.py" "$@"
elif command -v python >/dev/null 2>&1; then
  exec python "$connect_root/scripts/bootstrap/connect.py" "$@"
fi
echo 'HELIOS requires Python 3.10 or newer.' >&2
exit 2
