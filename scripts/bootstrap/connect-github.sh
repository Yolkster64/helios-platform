#!/usr/bin/env bash
# GitHub browser authentication via the device-code flow.
#
# Runs `gh auth login --web`: gh prints a one-time code, opens a browser where one
# exists, and prints the URL to open on any other device where one doesn't (Cloud
# Shell, SSH, containers). Nothing is written to this repo — gh stores its token in
# its own keyring/config, outside the working tree.
#
# Usage:
#   scripts/bootstrap/connect-github.sh                # login if not already
#   scripts/bootstrap/connect-github.sh --force        # re-run login even if logged in
#   scripts/bootstrap/connect-github.sh --verify-only  # report auth state; never mutates
#   source scripts/bootstrap/connect-github.sh         # also exports GITHUB_MODELS_TOKEN
#
# Sourcing is the deep AIHub integration: after browser auth, the gh token doubles
# as the GitHub Models API key, so the `github-models` provider in config/aihub.json
# turns Ready with no manually-handled secret.
set -uo pipefail
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && set -e

main() {
  if ! command -v gh >/dev/null 2>&1; then
    echo "error: gh (GitHub CLI) is not installed." >&2
    echo "  Run scripts/bootstrap/cloud-shell-setup.sh first, or see https://cli.github.com" >&2
    return 1
  fi

  local mode="${1:-}"
  case "$mode" in
    ""|--force|--verify-only) ;;
    *) echo "unknown argument: $mode" >&2; return 1 ;;
  esac

  # Verify-only: report the auth state and stop — no login flow, no token refresh,
  # nothing written anywhere. Exit 0 when authenticated, 1 when not.
  if [[ "$mode" == "--verify-only" ]]; then
    if gh auth status --hostname github.com >/dev/null 2>&1; then
      echo "GitHub: authenticated as $(gh api user --jq .login 2>/dev/null || echo '?')."
      return 0
    fi
    echo "GitHub: not authenticated. Run scripts/bootstrap/connect-github.sh to log in." >&2
    return 1
  fi

  local force="$mode"
  if gh auth status --hostname github.com >/dev/null 2>&1 && [[ "$force" != "--force" ]]; then
    echo "GitHub: already authenticated as $(gh api user --jq .login 2>/dev/null || echo '?')."
  else
    echo "GitHub: starting browser/device-code login (a one-time code will be shown)..."
    # models:read is required for the github-models provider this token feeds;
    # without it the provider looks configured but every call 403s.
    gh auth login --hostname github.com --git-protocol https --web --scopes "models:read"
  fi

  if ! gh auth status --hostname github.com 2>&1 | grep -q "models:read"; then
    echo "GitHub: note — the current token lacks the models:read scope; the github-models"
    echo "        provider will fail. Fix with: gh auth refresh --hostname github.com --scopes models:read"
  fi

  # Export only when sourced — an exported var in a subshell would vanish anyway.
  if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    if [[ -z "${GITHUB_MODELS_TOKEN:-}" ]]; then
      GITHUB_MODELS_TOKEN="$(gh auth token 2>/dev/null || true)"
      export GITHUB_MODELS_TOKEN
      [[ -n "$GITHUB_MODELS_TOKEN" ]] &&
        echo "GitHub: exported GITHUB_MODELS_TOKEN from gh (github-models provider is now configured)."
    fi
  else
    echo "Tip: 'source scripts/bootstrap/connect-github.sh' also exports GITHUB_MODELS_TOKEN for the AIHub."
  fi
}

main "${1:-}"
