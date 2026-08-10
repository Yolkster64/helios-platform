#!/usr/bin/env bash
# GitHub browser authentication via the device-code flow.
#
# Runs `gh auth login --web`: gh prints a one-time code, opens a browser where one
# exists, and prints the URL to open on any other device where one doesn't (Cloud
# Shell, SSH, containers). Nothing is written to this repo — gh stores its token in
# its own keyring/config, outside the working tree.
#
# Usage:
#   scripts/bootstrap/connect-github.sh            # login if not already
#   scripts/bootstrap/connect-github.sh --force    # re-run login even if logged in
#   source scripts/bootstrap/connect-github.sh     # also exports GITHUB_MODELS_TOKEN
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

  local force="${1:-}"
  if gh auth status --hostname github.com >/dev/null 2>&1 && [[ "$force" != "--force" ]]; then
    echo "GitHub: already authenticated as $(gh api user --jq .login 2>/dev/null || echo '?')."
  else
    echo "GitHub: starting browser/device-code login (a one-time code will be shown)..."
    gh auth login --hostname github.com --git-protocol https --web
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
