#!/usr/bin/env bash
# GitHub authentication: browser device-code flow, plus a NON-INTERACTIVE lane.
#
# Runs `gh auth login --web` by default: gh prints a one-time code, opens a browser
# where one exists, and prints the URL to open on any other device where one doesn't
# (Cloud Shell, SSH, containers). `--from-env` instead persists an already-present,
# WIRE-VALIDATED env token into gh's keyring without any human step.
#
# Nothing is written to this repo — gh stores its token in its own keyring/config
# (~/.config/gh/hosts.yml), outside the working tree. That store is the same custody
# class as ~/.azure (which auth-doctor.ps1 -Apply already writes via az login): the
# no-secrets rule governs repo files and script OUTPUT, not a CLI's own credential
# store in the user profile. Token values never appear in argv, output, or logs.
#
# Usage:
#   scripts/bootstrap/connect-github.sh                # login if not already (browser)
#   scripts/bootstrap/connect-github.sh --force        # re-run login even if logged in
#   scripts/bootstrap/connect-github.sh --from-env     # persist a REST-valid GH_TOKEN/
#                                                      #   GITHUB_TOKEN to the keyring;
#                                                      #   never opens a browser
#   scripts/bootstrap/connect-github.sh --verify-only  # report auth state; never mutates
#   source scripts/bootstrap/connect-github.sh         # also exports GITHUB_MODELS_TOKEN
#
# Sourcing is the deep AIHub integration: after auth, the gh token doubles as the
# GitHub Models API key, so the `github-models` provider in config/aihub.json turns
# Ready with no manually-handled secret. The export is WIRE-VALIDATED first — see
# the probe functions below.
set -uo pipefail
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && set -e

# gh auth status checks EVERY stored account by default and exits 1 when any
# of them is stale — a healthy active account would still read as broken here.
# --active restricts the check to the account subsequent gh commands actually
# use; fall back to the unscoped form only on CLIs too old to know the flag.
gh_auth_status() {
  local out
  if out=$(gh auth status --hostname github.com --active 2>&1); then
    printf '%s\n' "$out"
    return 0
  fi
  if grep -qi 'unknown flag' <<< "$out"; then
    gh auth status --hostname github.com 2>&1
    return
  fi
  printf '%s\n' "$out"
  return 1
}

# --- Wire-truth probes (scripts/verify/rest-connect.ps1 doctrine, in bash) --------
# `gh auth status` can lie both ways: a REST-valid fine-grained token can fail it,
# and a credential-injecting transport can make garbage look valid. So persistence
# and export decisions below are grounded in a direct probe of api.github.com.
# The bearer value reaches curl via a stdin config (-K -), never argv (argv is
# visible to other processes), and is never echoed.

have_curl() { command -v curl >/dev/null 2>&1; }

# Prints the numeric rate.limit for a probe (anonymous when no token is given),
# or "unknown" on transport failure / unparsable body. HTTP 401 yields a body
# with no rate.limit → "unknown" → the caller treats the token as not proven.
github_rate_limit() {
  local tok="${1:-}" body
  if [[ -n "$tok" ]]; then
    body=$(curl -sS --max-time 20 -K - \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      https://api.github.com/rate_limit 2>/dev/null <<< "header = \"Authorization: Bearer $tok\"") || { echo unknown; return 0; }
  else
    body=$(curl -sS --max-time 20 \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      https://api.github.com/rate_limit 2>/dev/null) || { echo unknown; return 0; }
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys
try:
    print(int(json.load(sys.stdin)["rate"]["limit"]))
except Exception:
    print("unknown")' <<< "$body"
  else
    grep -oE '"limit": *[0-9]+' <<< "$body" | head -n1 | grep -oE '[0-9]+' || echo unknown
  fi
}

# 0 = an injecting transport is PROVEN: an anonymous request answered above the
# unauthenticated 60/hr cap, so a proxy owns this session's GitHub credentials
# and per-token validity cannot be asserted from this host at all.
github_transport_injected() {
  local anon
  anon=$(github_rate_limit "")
  [[ "$anon" =~ ^[0-9]+$ ]] && (( anon > 60 ))
}

# 0 = the given token is REST-valid on a clean transport: 200 AND limit above the
# anonymous cap (at/below 60 means the Authorization header was stripped in
# transit — a legitimate anonymous payload that proves nothing about the token).
github_token_valid() {
  local lim
  lim=$(github_rate_limit "$1")
  [[ "$lim" =~ ^[0-9]+$ ]] && (( lim > 60 ))
}

main() {
  if ! command -v gh >/dev/null 2>&1; then
    echo "error: gh (GitHub CLI) is not installed." >&2
    echo "  Run scripts/bootstrap/cloud-shell-setup.sh first, or see https://cli.github.com" >&2
    return 1
  fi

  local mode="${1:-}"
  case "$mode" in
    ""|--force|--verify-only|--from-env) ;;
    *) echo "unknown argument: $mode" >&2; return 1 ;;
  esac

  # Verify-only: report the auth state and stop — no login flow, no token refresh,
  # nothing written anywhere. Exit 0 when authenticated, 1 when not.
  if [[ "$mode" == "--verify-only" ]]; then
    if gh_auth_status >/dev/null; then
      echo "GitHub: authenticated as $(gh api user --jq .login 2>/dev/null || echo '?')."
      return 0
    fi
    # gh's opinion is not the wire: before declaring the lane broken, probe REST
    # directly — an injecting transport or a REST-valid env token IS ready even
    # when the CLI disagrees (rest-connect doctrine).
    if have_curl; then
      if github_transport_injected; then
        echo "GitHub: wire-ready via an injecting transport (gh keyring disagrees — the REST probe is"
        echo "        ground truth; per-token validity is unprovable on this host)."
        return 0
      fi
      local name
      for name in GH_TOKEN GITHUB_TOKEN; do
        if [[ -n "${!name:-}" ]] && github_token_valid "${!name}"; then
          echo "GitHub: wire-ready — $name is REST-valid (gh auth status disagrees; the REST probe is ground truth)."
          return 0
        fi
      done
    fi
    echo "GitHub: not authenticated. Run scripts/bootstrap/connect-github.sh to log in." >&2
    return 1
  fi

  # From-env: the zero-human lane. Persist an already-present env token into gh's
  # keyring — but only after the wire proves it, and never on an injecting
  # transport (where a garbage token would look valid). Never falls through to
  # the browser flow; exit 1 hands the owner the exact command instead.
  if [[ "$mode" == "--from-env" ]]; then
    if ! have_curl; then
      echo "GitHub: --from-env needs curl for the wire probe and none was found — persisting an" >&2
      echo "        unvalidated token is unsafe. Install curl, or use the browser flow (--web)." >&2
      return 1
    fi
    if github_transport_injected; then
      echo "GitHub: transport-injected — an anonymous probe of api.github.com answered above the"
      echo "        60/hr anonymous cap, so a proxy owns this session's GitHub credentials."
      echo "        Per-token validity is unprovable here; nothing was validated or persisted."
      return 0
    fi
    # Keyring check runs env-cleared: with GH_TOKEN set, plain `gh auth status`
    # judges the env token, not the stored login.
    if env -u GH_TOKEN -u GITHUB_TOKEN gh auth status --hostname github.com >/dev/null 2>&1; then
      echo "GitHub: a keyring login already exists (checked env-cleared) — nothing to do."
      return 0
    fi
    local name tok
    for name in GH_TOKEN GITHUB_TOKEN; do
      tok="${!name:-}"
      [[ -n "${tok// /}" ]] || continue
      if github_token_valid "$tok"; then
        echo "GitHub: $name is REST-valid on the wire — persisting to gh's keyring (--with-token)."
        # env-cleared: gh refuses to log in while GH_TOKEN is set. The token
        # flows through the pipe only — never argv, never echoed.
        if printf '%s' "$tok" | env -u GH_TOKEN -u GITHUB_TOKEN gh auth login --hostname github.com --git-protocol https --with-token &&
           env -u GH_TOKEN -u GITHUB_TOKEN gh auth status --hostname github.com >/dev/null 2>&1; then
          echo "GitHub: keyring login persisted from $name (value never printed)."
          return 0
        fi
        echo "GitHub: persisting $name failed. Manual step:" >&2
        echo "  printf '%s' \"\$$name\" | env -u GH_TOKEN -u GITHUB_TOKEN gh auth login --hostname github.com --with-token" >&2
        return 1
      fi
      echo "GitHub: $name is present but did not prove REST-valid (rejected or transient) — not persisted."
    done
    echo "GitHub: no env token could be validated — owner step: gh auth login --hostname github.com --web --scopes models:read" >&2
    return 1
  fi

  local force="$mode"
  if gh_auth_status >/dev/null && [[ "$force" != "--force" ]]; then
    echo "GitHub: already authenticated as $(gh api user --jq .login 2>/dev/null || echo '?')."
  else
    echo "GitHub: starting browser/device-code login (a one-time code will be shown)..."
    # models:read is required for the github-models provider this token feeds;
    # without it the provider looks configured but every call 403s.
    gh auth login --hostname github.com --git-protocol https --web --scopes "models:read"
  fi

  if ! gh_auth_status | grep -q "models:read"; then
    echo "GitHub: note — the current token lacks the models:read scope; the github-models"
    echo "        provider will fail. Fix with: gh auth refresh --hostname github.com --scopes models:read"
  fi

  # Export only when sourced — an exported var in a subshell would vanish anyway.
  # WIRE-VALIDATED first (review finding): with an invalid GH_TOKEN in the env,
  # `gh auth token` just echoes that dead value back, and exporting it would hand
  # the github-models provider a credential that 401s on every call.
  if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    if [[ -z "${GITHUB_MODELS_TOKEN:-}" ]]; then
      local models_tok
      # --hostname github.com: never hand a GitHub Enterprise credential (GH_HOST
      # context) to the github.com models lane.
      models_tok="$(gh auth token --hostname github.com 2>/dev/null || true)"
      if [[ -z "$models_tok" ]]; then
        echo "GitHub: gh yielded no token — GITHUB_MODELS_TOKEN not exported."
      elif ! have_curl; then
        GITHUB_MODELS_TOKEN="$models_tok"
        export GITHUB_MODELS_TOKEN
        echo "GitHub: exported GITHUB_MODELS_TOKEN from gh (curl absent — wire validation skipped)."
      elif github_transport_injected; then
        echo "GitHub: transport-injected — gh's token is unprovable from this host, so it was NOT"
        echo "        exported (never copy a token on the strength of an injected transport)."
      elif github_token_valid "$models_tok"; then
        GITHUB_MODELS_TOKEN="$models_tok"
        export GITHUB_MODELS_TOKEN
        echo "GitHub: exported GITHUB_MODELS_TOKEN from gh — wire-validated (github-models provider is now configured)."
      else
        echo "GitHub: gh's token failed the wire probe (rejected or transient) — NOT exported."
        echo "        If model calls 403 later: gh auth refresh --hostname github.com --scopes models:read"
      fi
      models_tok=""
    fi
  else
    echo "Tip: 'source scripts/bootstrap/connect-github.sh' also exports GITHUB_MODELS_TOKEN for the AIHub."
  fi
}

main "${1:-}"
