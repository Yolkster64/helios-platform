#!/usr/bin/env bash
# One-shot cross-LLM bring-up for Azure Cloud Shell (also works in Codespaces and on
# any local Linux/macOS shell — the point is that every step behaves identically in
# all three, with Cloud Shell as the reference environment).
#
# What it does, in order:
#   1. Detects the environment and verifies/installs the CLI fleet:
#      az, gh (pre-installed in Cloud Shell), then claude / codex / copilot via npm
#      (under the durable clouddrive prefix in Cloud Shell — see persistence below),
#      then writes the Cloud Shell shell hooks.
#   2. Browser-authenticates GitHub (device code) and Azure (device code).
#   3. Env wiring: sources Key Vault keys INTO THIS RUN when AZURE_KEY_VAULT_URI is
#      set and az is logged in (so the codex verify and the smoke test see them),
#      prints the source commands for YOUR shell, and verifies the codex lane
#      (report-only — a login is never started here).
#   4. Smoke-tests the AIHub: builds helios-ai, then runs `status` and `routing`
#      in parallel — the same fan-out pattern CompareAsync/TandemAsync use.
#   5. Prints the unified readiness inventory (scripts/setup/setup-all.ps1 — the
#      absorption-epic-E1 command surface): one table, a fix command per gap.
#
# Cloud Shell persistence (Cloud Shell only, when $HOME/clouddrive is mounted):
#   Everything outside the clouddrive file share is rebuilt from the image on every
#   new session, so a global npm install to /usr/local is gone tomorrow. The npm
#   prefix is therefore pointed at $HOME/clouddrive/helios/npm before the CLI
#   installs, and ONE marker-delimited block is appended to ~/.bashrc (and, via a
#   small profile.ps1 under clouddrive, dot-sourced from pwsh's $PROFILE) that puts
#   that prefix on PATH, sources .helios/azure.env when it exists, and defines a
#   lazy loader — `helios-env` in bash, `Enter-HeliosEnv` in pwsh — for the Key
#   Vault keys instead of pulling them at every shell start. The block is
#   refreshed in place, never duplicated; --no-persist opts out; --verify-only
#   never writes it.
#
# No secrets are written to disk at any step.
#
# Usage: scripts/bootstrap/cloud-shell-setup.sh [--skip-auth] [--skip-smoke] [--verify-only] [--no-persist]
#
# --verify-only reports CLI presence and GitHub/Azure auth state without mutating
# anything: no installs, no login flows, no builds, no persistence. Exit 0 when
# both auths are ready, 1 otherwise.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
skip_auth=""
skip_smoke=""
verify_only=""
no_persist=""
for arg in "$@"; do
  case "$arg" in
    --skip-auth) skip_auth=1 ;;
    --skip-smoke) skip_smoke=1 ;;
    --verify-only) verify_only=1 ;;
    --no-persist) no_persist=1 ;;
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

# Persistence is decided once, up front, because the npm prefix must be in place
# BEFORE the installs below: only Cloud Shell loses /usr/local between sessions, and
# only a mounted clouddrive can hold the durable copy.
persist_root=""
if [[ "$environment" == "Azure Cloud Shell" && -d "$HOME/clouddrive" && -z "$no_persist" ]]; then
  persist_root="$HOME/clouddrive/helios"
fi

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
    if [[ -n "$persist_root" ]]; then
      npm_prefix="$persist_root/npm"
      mkdir -p "$npm_prefix"
      # Idempotent: the effective global prefix is compared first (`npm prefix -g`;
      # `npm config get prefix` is a protected option on current npm and errors),
      # so a re-run neither rewrites ~/.npmrc nor prints a change that did not happen.
      if [[ "$(npm prefix -g 2>/dev/null || true)" != "$npm_prefix" ]]; then
        npm config set prefix "$npm_prefix"
        echo "  npm prefix -> $npm_prefix (survives Cloud Shell session resets)"
      fi
      case ":$PATH:" in
        *":$npm_prefix/bin:"*) ;;
        *) export PATH="$npm_prefix/bin:$PATH" ;;
      esac
    fi
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

# --- 1b. Cloud Shell persistence (shell hooks) ------------------------------------
# Writes ONE marker-delimited block per shell so the durable npm prefix is on PATH,
# .helios/azure.env is sourced in every new session, and the Key Vault loader is
# ONE function call away (helios-env / Enter-HeliosEnv) — never run at shell start.
# An existing block is compared and refreshed in place — never appended twice —
# because a stale block (old checkout path) would silently source nothing.
write_marked_block() {
  local file="$1" begin="$2" end="$3" content="$4" desired current tmp
  desired="$begin"$'\n'"$content"$'\n'"$end"
  if [[ -f "$file" ]] && grep -qF -- "$begin" "$file"; then
    current="$(awk -v b="$begin" -v e="$end" '$0==b{p=1} p{print} $0==e{p=0}' "$file")"
    if [[ "$current" == "$desired" ]]; then
      echo "  $file: block already current"
      return 0
    fi
    tmp="$(mktemp)"
    awk -v b="$begin" -v e="$end" '$0==b{p=1;next} $0==e{p=0;next} !p{print}' "$file" > "$tmp"
    cat "$tmp" > "$file"
    rm -f "$tmp"
    printf '%s\n' "$desired" >> "$file"
    echo "  $file: block refreshed"
    return 0
  fi
  mkdir -p "$(dirname "$file")"
  # A file that does not end in a newline would glue the marker onto its last line.
  if [[ -s "$file" && "$(tail -c1 "$file" | wc -l)" -eq 0 ]]; then
    printf '\n' >> "$file"
  fi
  printf '%s\n' "$desired" >> "$file"
  echo "  $file: block added"
}

if [[ -n "$persist_root" ]]; then
  echo
  echo "-- Cloud Shell persistence ($persist_root) --"
  mkdir -p "$persist_root"
  bash_marker_begin="# >>> helios bootstrap (scripts/bootstrap/cloud-shell-setup.sh) >>>"
  bash_marker_end="# <<< helios bootstrap <<<"
  # PATH is guarded so a re-sourced .bashrc never stacks duplicates. The Key Vault
  # loader is wrapped in a FUNCTION, not sourced eagerly: it costs an `az account
  # show` plus three serialized secret reads and, silenced, hides its failures — a
  # price no new tab should pay unasked. Shell options are saved and restored
  # around the source inside the function: the loader runs `set -uo pipefail`,
  # and options set by a sourced file persist in the sourcing shell, so without
  # the restore the interactive session would continue with nounset on and any
  # `$UNSET` reference (completion scripts, prompts, ad-hoc commands) would abort.
  # The hint is printed only in an interactive shell: output from .bashrc breaks
  # scp / rsync / ssh-command sessions.
  bash_block="$(cat <<EOF
case ":\$PATH:" in *":$persist_root/npm/bin:"*) ;; *) export PATH="$persist_root/npm/bin:\$PATH" ;; esac
[ -f "$repo_root/.helios/azure.env" ] && . "$repo_root/.helios/azure.env"
# helios-env is a function, not an eager source: the loader costs an az account show plus three secret reads and hides its failures when silenced, a price no new tab should pay unasked
helios-env() {
  # options saved/restored: the loader sets -u/pipefail, which must not leak into an interactive shell
  local _helios_opts _helios_rc
  _helios_opts="\$(set +o)"
  . "$repo_root/scripts/bootstrap/load-env-from-keyvault.sh"; _helios_rc=\$?
  eval "\$_helios_opts"
  return "\$_helios_rc"
}
case "\$-" in *i*) [ -n "\${AZURE_KEY_VAULT_URI:-}" ] && echo "helios: run helios-env to pull the Key Vault keys into this shell" ;; esac
EOF
)"
  write_marked_block "$HOME/.bashrc" "$bash_marker_begin" "$bash_marker_end" "$bash_block"

  if command -v pwsh >/dev/null 2>&1; then
    # The pwsh side mirrors the bash block: .helios/azure.env.ps1 is what
    # azure-up.ps1 writes, and a dot-sourced auto-login.ps1 is the PowerShell
    # owner of session exports (there is no pwsh reader for the bash loader).
    # Enter-HeliosEnv is a FUNCTION the owner calls, not a profile-time login:
    # auto-login.ps1 runs auth-doctor -Apply (a non-interactive az login that
    # rewrites the az profile) before its vault pulls. Dot-sourcing inside the
    # function is safe — auto-login sees InvocationName '.', rethrows on failure
    # instead of `exit`, and its $env: exports are process-wide.
    profile_ps1="$persist_root/profile.ps1"
    desired_profile="$(cat <<EOF
# HELIOS Cloud Shell profile — written by scripts/bootstrap/cloud-shell-setup.sh; safe to delete.
\$heliosNpmBin = '$persist_root/npm/bin'
if ((\$env:PATH -split [System.IO.Path]::PathSeparator) -notcontains \$heliosNpmBin) {
    \$env:PATH = \$heliosNpmBin + [System.IO.Path]::PathSeparator + \$env:PATH
}
\$heliosAzureEnv = '$repo_root/.helios/azure.env.ps1'
if (Test-Path -LiteralPath \$heliosAzureEnv) { . \$heliosAzureEnv }
# Lazy on purpose: auto-login.ps1 runs auth-doctor -Apply (a non-interactive az login that
# rewrites the az profile) and then the Key Vault pulls; that is a deliberate step the
# owner takes once, never a side effect of opening a tab with its output thrown away.
function Enter-HeliosEnv { . '$repo_root/scripts/bootstrap/auto-login.ps1' }
if (\$env:AZURE_KEY_VAULT_URI -and -not [Console]::IsOutputRedirected) {
    Write-Host 'helios: run Enter-HeliosEnv to pull the Key Vault keys into this session'
}
EOF
)"
    if [[ -f "$profile_ps1" && "$(cat "$profile_ps1")" == "$desired_profile" ]]; then
      echo "  $profile_ps1: already current"
    else
      printf '%s\n' "$desired_profile" > "$profile_ps1"
      echo "  $profile_ps1: written"
    fi
    pwsh_profile="$(pwsh -NoProfile -Command 'Write-Output $PROFILE' 2>/dev/null || true)"
    if [[ -n "$pwsh_profile" ]]; then
      write_marked_block "$pwsh_profile" "$bash_marker_begin" "$bash_marker_end" \
        "if (Test-Path -LiteralPath '$profile_ps1') { . '$profile_ps1' }"
    else
      echo "  pwsh \$PROFILE path unknown — dot-source $profile_ps1 from your profile yourself"
    fi
  else
    echo "  pwsh not installed — no PowerShell profile hook written"
  fi
elif [[ "$environment" == "Azure Cloud Shell" && -n "$no_persist" ]]; then
  echo
  echo "-- Cloud Shell persistence -- skipped (--no-persist)"
elif [[ "$environment" == "Azure Cloud Shell" ]]; then
  echo
  echo "-- Cloud Shell persistence -- skipped (\$HOME/clouddrive is not mounted; mount a file share first)"
fi

# --- 2. Browser authentication ----------------------------------------------------
if [[ -z "$skip_auth" ]]; then
  echo
  echo "-- Authentication (browser / device code) --"
  "$repo_root/scripts/bootstrap/connect-github.sh"
  "$repo_root/scripts/bootstrap/connect-azure.sh"
fi

# --- 3. Env wiring + codex lane ---------------------------------------------------
# Sourcing the Key Vault loader INSIDE this run lights the codex verify below and
# the step-4 smoke test in the same bring-up. A child process still cannot export
# into YOUR shell, so the source commands are also printed (previous behavior).
echo
echo "-- Env wiring --"
if [[ -n "${AZURE_KEY_VAULT_URI:-}" ]] && az account show >/dev/null 2>&1; then
  # `|| true`: the sourced loader's return-1 paths (vault unreadable, secret
  # absent) are honest degraded states, not bring-up failures — they must not
  # trip this script's set -e.
  source "$repo_root/scripts/bootstrap/load-env-from-keyvault.sh" || true
  echo "  (Key Vault keys loaded for THIS run; run the commands below to load them into your shell)"
elif [[ -z "${AZURE_KEY_VAULT_URI:-}" ]]; then
  echo "  (AZURE_KEY_VAULT_URI unset — Key Vault not sourced this run)"
else
  echo "  (az not logged in — Key Vault not sourced this run)"
fi
echo "  source scripts/bootstrap/connect-github.sh          # gh token -> GITHUB_MODELS_TOKEN (wire-validated)"
echo "  source scripts/bootstrap/load-env-from-keyvault.sh  # Key Vault -> OPENAI/ANTHROPIC/... keys"
[[ -z "${AZURE_KEY_VAULT_URI:-}" ]] &&
  echo "  (set AZURE_KEY_VAULT_URI=https://<vault>.vault.azure.net/ first — see infra/README.md)"

# Codex lane verification — a report-only bash mirror of auth-doctor.ps1's
# Test-CodexLane precedence (env key first, then the CLI's own login state).
# A login is NEVER started here; needs-owner prints the two exact commands.
echo
echo "-- codex lane --"
if ! command -v codex >/dev/null 2>&1; then
  echo "  codex: unavailable (install failed above — rerun with npm output visible)"
elif [[ -n "${OPENAI_API_KEY:-}" ]]; then
  echo "  codex: ready (env OPENAI_API_KEY — covers the CLI and the openai/openai-codex API providers)"
else
  codex_out=$(codex login status 2>&1) && codex_rc=0 || codex_rc=$?
  if [[ "$codex_rc" -eq 0 ]]; then
    # Honesty caveat (auth-doctor rule): a CLI login does NOT cover the
    # openai/openai-codex API providers, which read only OPENAI_API_KEY.
    echo "  codex: ready (CLI login; the openai/openai-codex API providers still need OPENAI_API_KEY)"
  elif grep -qiE 'unrecognized subcommand|unexpected argument|unknown (sub)?command' <<< "$codex_out"; then
    echo "  codex: unverifiable headlessly (this codex build has no 'login status' subcommand)"
  else
    echo "  codex: needs-owner — run: codex login --device-auth   (browserless; docs/architecture/ENTERPRISE_AI_CONNECTIONS.md §5)"
    echo "         or store openai-api-key in Key Vault, then: source scripts/bootstrap/load-env-from-keyvault.sh"
  fi
fi

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
