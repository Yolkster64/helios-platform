#!/usr/bin/env bash
# SessionStart self-check for Claude Code sessions (wired in .claude/settings.json).
#
# Emits ONE short line summarizing the account/auth state so every session starts
# knowing which identity each surface is bound to and what (if anything) only the
# owner can fix. Read-only by construction: it runs connect-account.ps1 in its
# default report mode, which mutates nothing.
#
# Contract with the hook harness:
#   - ALWAYS exits 0 — a broken self-check must never break a session start.
#   - Bounded runtime (the probes hit az/gh; TIMEOUT_SECONDS caps the worst case).
#   - Output is context, not control: one summary line, no secret values ever
#     (connect-account checks env vars by NAME only and prints identities, which
#     are names, not credentials).
set -u

TIMEOUT_SECONDS=25
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if ! command -v pwsh >/dev/null 2>&1; then
    echo "HELIOS auth self-check: skipped (pwsh not installed — run scripts/bootstrap/connect-account.ps1 manually when available)"
    exit 0
fi

report="$(timeout "${TIMEOUT_SECONDS}" pwsh -NoProfile "${REPO_ROOT}/scripts/bootstrap/connect-account.ps1" -Json 2>/dev/null)" || {
    echo "HELIOS auth self-check: skipped (connect-account probe failed or timed out — run: pwsh scripts/bootstrap/connect-account.ps1)"
    exit 0
}

summary="$(printf '%s' "${report}" | python3 -c '
import json, sys
try:
    r = json.load(sys.stdin)
except Exception:
    sys.exit(1)
lanes = r.get("lanes", [])
states = {l["lane"]: l["state"] for l in lanes}
s = r.get("summary", {})
mismatch = [l["lane"] for l in lanes if l.get("state") == "mismatch"]
parts = [f"{lane}={state}" for lane, state in states.items()]
line = "HELIOS auth self-check: " + " ".join(parts)
line += " | " + str(s.get("ready", 0)) + "/" + str(len(lanes)) + " ready"
if mismatch:
    line += " | IDENTITY MISMATCH: " + ",".join(mismatch) + " — fix before any cloud action"
else:
    line += " | identities consistent (az/M365 -> " + r.get("expected", {}).get("azureUpn", "?") + ", gh -> " + r.get("expected", {}).get("gitHubLogin", "?") + ")"
print(line)
' 2>/dev/null)" || {
    echo "HELIOS auth self-check: ran but report was unparseable — run: pwsh scripts/bootstrap/connect-account.ps1"
    exit 0
}

echo "${summary}"
exit 0
