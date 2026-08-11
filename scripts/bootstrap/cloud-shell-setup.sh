#!/usr/bin/env bash
# One-shot cross-LLM bring-up for Azure Cloud Shell (also works in Codespaces and on
# any local Linux/macOS shell — the point is that every step behaves identically in
# all three, with Cloud Shell as the reference environment).
#
# What it does, in order:
#   1. Detects the environment and verifies/installs the CLI fleet:
#      az, gh (pre-installed in Cloud Shell), then claude / codex / copilot via npm.
#   2. Browser-authenticates GitHub (device code) and Azure (device code).
#   3. Prints the env-wiring commands (gh token -> GitHub Models, Key Vault -> API keys).
#   4. Smoke-tests the AIHub: builds helios-ai, then runs `status` and `routing`
#      in parallel — the same fan-out pattern CompareAsync/TandemAsync use.
#   5. Prints the unified readiness inventory (scripts/setup/setup-all.ps1 — the
#      absorption-epic-E1 command surface): one table, a fix command per gap.
#
# No secrets are written to disk at any step.
#
# Usage: scripts/bootstrap/cloud-shell-setup.sh [--skip-auth] [--skip-smoke] [--verify-only]
#
# --verify-only reports CLI presence and GitHub/Azure auth state without mutating
# anything: no installs, no login flows, no builds. Exit 0 when both auths are
# ready, 1 otherwise.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
skip_auth=""
skip_smoke=""
verify_only=""
for arg in "$@"; do
  case "$arg" in
    --skip-auth) skip_auth=1 ;;
    --skip-smoke) skip_smoke=1 ;;
    --verify-only) verify_only=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 1 ;;
  esac
done

if [[ -n "${AZUREPS_HOST_ENVIRONMENT:-}" || -n "${ACC_CLOUD:-}" ]]; then
  environment="Azure Cloud Shell"
elif [[ -n "${CODESPACES:-}" ]]; then
  environment="GitHub Codespaces"
else
  environment="local shell"
fi
echo "== HELIOS cross-LLM setup ($environment) =="

# --- 1. CLI fleet -----------------------------------------------------------------
echo
echo "-- CLI fleet --"

require() {
  if command -v "$1" >/dev/null 2>&1; then
    echo "  $1: present"
  else
    echo "  $1: MISSING — $2" >&2
    return 1
  fi
}

missing_base=0
require az "install: https://aka.ms/azure-cli (pre-installed in Cloud Shell)" || missing_base=1
require gh "install: https://cli.github.com (pre-installed in Cloud Shell)" || missing_base=1

# The agent CLIs ship via npm. Installs run sequentially on purpose: concurrent
# `npm install -g` invocations race on the shared global prefix. Verify-only mode
# reports presence without installing.
if command -v npm >/dev/null 2>&1; then
  if [[ -z "$verify_only" ]]; then
    command -v claude >/dev/null 2>&1 || { echo "  claude: installing..."; npm install -g @anthropic-ai/claude-code >/dev/null; }
    command -v codex  >/dev/null 2>&1 || { echo "  codex: installing...";  npm install -g @openai/codex >/dev/null; }
    command -v copilot >/dev/null 2>&1 || { echo "  copilot: installing..."; npm install -g @github/copilot >/dev/null; }
  fi
  for cli in claude codex copilot; do
    require "$cli" "npm install failed — rerun with npm output visible" || true
  done
else
  echo "  npm: MISSING — claude/codex/copilot CLIs skipped (install Node.js to add them)" >&2
fi
command -v ollama >/dev/null 2>&1 && echo "  ollama: present (local models available)" \
  || echo "  ollama: not installed (optional — https://ollama.com)"

[[ "$missing_base" == 1 ]] && { echo "error: az/gh are required. Fix the MISSING lines above." >&2; exit 1; }

# --- Verify-only: read-only auth state, then stop --------------------------------
if [[ -n "$verify_only" ]]; then
  echo
  echo "-- Authentication state (read-only) --"
  auth_failed=0
  "$repo_root/scripts/bootstrap/connect-github.sh" --verify-only || auth_failed=1
  "$repo_root/scripts/bootstrap/connect-azure.sh" --verify-only || auth_failed=1
  echo
  if [[ "$auth_failed" == 0 ]]; then
    echo "== Verify-only: GitHub and Azure authentication are ready. =="
  else
    echo "== Verify-only: authentication incomplete — rerun without --verify-only to log in. ==" >&2
  fi
  exit "$auth_failed"
fi

# --- 2. Browser authentication ----------------------------------------------------
if [[ -z "$skip_auth" ]]; then
  echo
  echo "-- Authentication (browser / device code) --"
  "$repo_root/scripts/bootstrap/connect-github.sh"
  "$repo_root/scripts/bootstrap/connect-azure.sh"
fi

# --- 3. Env wiring ----------------------------------------------------------------
# A child process cannot export into your shell, so the wiring itself is two
# source commands — printed here instead of silently half-working.
echo
echo "-- Env wiring (run these in your shell) --"
echo "  source scripts/bootstrap/connect-github.sh          # gh token -> GITHUB_MODELS_TOKEN"
echo "  source scripts/bootstrap/load-env-from-keyvault.sh  # Key Vault -> OPENAI/ANTHROPIC/... keys"
[[ -z "${AZURE_KEY_VAULT_URI:-}" ]] &&
  echo "  (set AZURE_KEY_VAULT_URI=https://<vault>.vault.azure.net/ first — see infra/README.md)"

# --- 4. AIHub smoke test ----------------------------------------------------------
if [[ -z "$skip_smoke" ]]; then
  echo
  echo "-- AIHub smoke test --"
  if command -v dotnet >/dev/null 2>&1; then
    [[ -x "$repo_root/scripts/build/build-native.sh" ]] && command -v cmake >/dev/null 2>&1 &&
      "$repo_root/scripts/build/build-native.sh" >/dev/null 2>&1 || true
    dotnet build "$repo_root/HELIOS.sln" -c Release --nologo -v q

    # status and routing are independent reads — run them in parallel, the same
    # fan-out shape the hub itself uses for compare/tandem across providers.
    dotnet run --project "$repo_root/src/ai/HELIOS.AIHub.Cli" -c Release --no-build -- status &
    status_pid=$!
    dotnet run --project "$repo_root/src/ai/HELIOS.AIHub.Cli" -c Release --no-build -- routing &
    routing_pid=$!
    wait "$status_pid" "$routing_pid"
    echo
    echo "Providers above marked Unconfigured just need their env vars — see step 3."
  else
    echo "  dotnet: not installed — skipped (Cloud Shell has it; locally: https://dot.net)" >&2
  fi
fi

# --- 5. Unified readiness inventory (absorption epic E1) --------------------------
# setup-all.ps1 is the one-command E1 surface: toolchain readiness, GitHub/Azure auth
# state, the AI CLI fleet (setup-ai-clis.ps1), fleet topology, and MCP registration,
# rendered as a single inventory table with a fix command per gap. -Fix lets it
# complete tool installs this script's npm step cannot (the github/gh-models
# extension in particular); auth is still never mutated by setup-all. Its exit 2
# just means "attention needed" — the table says what and how, so it must not
# abort this script under `set -e`.
if command -v pwsh >/dev/null 2>&1; then
  echo
  echo "-- Unified readiness inventory (scripts/setup/setup-all.ps1 -Fix) --"
  pwsh "$repo_root/scripts/setup/setup-all.ps1" -Fix || true
else
  echo "  pwsh: not installed — skipped scripts/setup/setup-all.ps1 (Cloud Shell ships pwsh)" >&2
fi

echo
echo "== Done. Try: dotnet run --project src/ai/HELIOS.AIHub.Cli -- compare --providers openai,anthropic \"<prompt>\" =="
