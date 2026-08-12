#!/usr/bin/env bash
# Register a self-hosted GitHub Actions runner for Yolkster64/helios-platform
# (PowerShell twin: register-runner.ps1 — use that on Windows).
#
# What this does, in order:
#   1. requires an authenticated `gh` CLI — the caller must have ADMIN on the
#      repo, because the registration-token endpoint is admin-only;
#   2. downloads the latest actions/runner release for this OS/arch into the
#      target directory (default ./actions-runner), skipping the download when
#      a runner is already unpacked there;
#   3. mints a SHORT-LIVED registration token via
#        gh api -X POST repos/{owner}/{repo}/actions/runners/registration-token
#      The token is SINGLE-USE and expires in ~1 hour. It is held in a shell
#      variable only — never echoed, never written to disk, and this script
#      never enables `set -x`;
#   4. runs `./config.sh --url --token --name --labels helios,xcore[,extras]
#      --unattended` (plus --ephemeral behind the -e/--ephemeral switch);
#   5. prints the run command (`./run.sh`) and the systemd service hint —
#      it deliberately does NOT auto-start the runner.
#
# Labels: every runner gets `helios,xcore`. Pools that need more add them with
# --extra-labels — e.g. the fleet's xcore-9-native pool
# (config/fleet/fleet-topology.json) wants a dedicated runner carrying
# `xcore-native` before its autoscaling mode may leave "local":
#     scripts/runners/register-runner.sh --extra-labels xcore-native
#
# Removing a runner later (mirror of step 3/4 — remove tokens are also
# single-use, ~1h):
#     token=$(gh api -X POST repos/Yolkster64/helios-platform/actions/runners/remove-token --jq .token)
#     (cd ./actions-runner && ./config.sh remove --token "$token")
#
# --dry-run prints every step of the plan and exits WITHOUT touching the
# network or gh. Proof of life after registering: dispatch the
# "Self-Hosted Runner Smoke" workflow (.github/workflows/runner-smoke.yml).
# Scale-out beyond hand-registered runners is ARC — see
# docs/architecture/GITHUB_ECOSYSTEM_DESIGN.md "Self-hosted runners (ARC)".
#
# Usage:
#   scripts/runners/register-runner.sh                             # defaults below
#   scripts/runners/register-runner.sh --dry-run                   # plan only
#   scripts/runners/register-runner.sh -d /opt/actions-runner --extra-labels xcore-native --ephemeral
set -euo pipefail

repo="Yolkster64/helios-platform"
# The default lives inside the checkout and is covered by .gitignore
# (actions-runner/) because config.sh writes LIVE credentials (.credentials,
# RSA params) into it. A custom --dir inside the repo must be gitignored too —
# otherwise a routine `git add -A` can stage runner credentials.
runner_dir="./actions-runner"
runner_name="$(hostname)-helios"
extra_labels=""
ephemeral=false
dry_run=false
base_labels="helios,xcore"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="${2:?--repo needs a value (owner/repo)}"; shift 2 ;;
    -d|--dir) runner_dir="${2:?--dir needs a value}"; shift 2 ;;
    -n|--name) runner_name="${2:?--name needs a value}"; shift 2 ;;
    -l|--extra-labels) extra_labels="${2:?--extra-labels needs a value (comma-separated)}"; shift 2 ;;
    -e|--ephemeral) ephemeral=true; shift ;;
    --dry-run) dry_run=true; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1 (see --help)" >&2; exit 1 ;;
  esac
done

labels="$base_labels${extra_labels:+,$extra_labels}"

# --- OS/arch → actions/runner asset naming ----------------------------------------
case "$(uname -s)" in
  Linux)  os="linux" ;;
  Darwin) os="osx" ;;
  *) echo "error: unsupported OS '$(uname -s)' — use register-runner.ps1 on Windows." >&2; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64)        arch="x64" ;;
  aarch64|arm64) arch="arm64" ;;
  *) echo "error: unsupported architecture '$(uname -m)' (need x86_64 or arm64)." >&2; exit 1 ;;
esac

config_flags=(--unattended)
if [[ "$ephemeral" == true ]]; then
  # Ephemeral runners take exactly one job, then deregister — the right mode for
  # throwaway VMs; persistent boxes (the Xcore pools) omit it.
  config_flags+=(--ephemeral)
fi

# --- Dry run: print the full plan, touch nothing ----------------------------------
if [[ "$dry_run" == true ]]; then
  echo "DRY RUN — plan only; no network calls, no gh calls, nothing executed."
  echo
  echo "  1. Check: gh auth status   (caller must have admin on $repo)"
  echo "  2. Resolve latest release: gh api repos/actions/runner/releases/latest --jq .tag_name"
  echo "  3. Download + extract into $runner_dir:"
  echo "       https://github.com/actions/runner/releases/download/v<latest>/actions-runner-${os}-${arch}-<latest>.tar.gz"
  echo "     (skipped if $runner_dir/config.sh already exists)"
  echo "  4. Mint single-use registration token (expires ~1h; kept in memory only):"
  echo "       gh api -X POST repos/$repo/actions/runners/registration-token --jq .token"
  echo "  5. Configure:"
  echo "       cd $runner_dir && ./config.sh --url https://github.com/$repo --token *** \\"
  echo "         --name $runner_name --labels $labels ${config_flags[*]}"
  echo "  6. Print next steps (never auto-starts):"
  echo "       run now:            cd $runner_dir && ./run.sh"
  echo "       install as service: cd $runner_dir && sudo ./svc.sh install && sudo ./svc.sh start"
  echo "       proof of life:      gh workflow run runner-smoke.yml --repo $repo"
  exit 0
fi

# --- Preflight: gh present and authenticated --------------------------------------
if ! command -v gh >/dev/null 2>&1; then
  echo "error: gh CLI not found — install it and run gh auth login." >&2
  exit 1
fi
# gh auth status tests EVERY stored account and exits 1 when any is stale;
# --active scopes the check to the account the gh api calls below will use.
# Fall back to the unscoped form only on a gh too old to know the flag.
gh_auth_ok=false
auth_out=$(gh auth status --hostname github.com --active 2>&1) && gh_auth_ok=true
if [[ "$gh_auth_ok" != true ]] && grep -qi 'unknown flag' <<< "$auth_out"; then
  gh auth status --hostname github.com >/dev/null 2>&1 && gh_auth_ok=true
fi
if [[ "$gh_auth_ok" != true ]]; then
  echo "error: gh is not authenticated. Run gh auth login as a user with ADMIN on $repo" >&2
  echo "       (the registration-token endpoint requires repo admin)." >&2
  exit 1
fi

# --- Download the latest runner release (idempotent) ------------------------------
if [[ -x "$runner_dir/config.sh" ]]; then
  echo "Runner package already present in $runner_dir — skipping download."
else
  tag="$(gh api repos/actions/runner/releases/latest --jq .tag_name)"
  version="${tag#v}"
  asset="actions-runner-${os}-${arch}-${version}.tar.gz"
  url="https://github.com/actions/runner/releases/download/${tag}/${asset}"
  echo "Downloading actions/runner ${tag} (${os}/${arch}) into $runner_dir..."
  mkdir -p "$runner_dir"
  curl -fsSL -o "$runner_dir/$asset" "$url"
  tar -xzf "$runner_dir/$asset" -C "$runner_dir"
  rm -f "$runner_dir/$asset"
fi

# --- Mint the registration token (single-use, ~1h; memory only) -------------------
echo "Minting a short-lived registration token for $repo..."
token="$(gh api -X POST "repos/${repo}/actions/runners/registration-token" --jq .token)"
if [[ -z "$token" ]]; then
  echo "error: could not mint a registration token — do you have admin on $repo?" >&2
  exit 1
fi

# --- Configure (does not start) ---------------------------------------------------
echo "Configuring runner '$runner_name' with labels: $labels"
(
  cd "$runner_dir"
  ./config.sh --url "https://github.com/${repo}" --token "$token" \
    --name "$runner_name" --labels "$labels" "${config_flags[@]}"
)
unset token

echo
echo "Registered. This script never auto-starts the runner — pick one:"
echo "  run in the foreground:      cd $runner_dir && ./run.sh"
echo "  install as a service:       cd $runner_dir && sudo ./svc.sh install && sudo ./svc.sh start"
echo
echo "Proof of life (dispatch-only smoke workflow):"
echo "  gh workflow run runner-smoke.yml --repo $repo"
echo
echo "To remove this runner later (remove tokens are also single-use, ~1h):"
echo "  token=\$(gh api -X POST repos/$repo/actions/runners/remove-token --jq .token)"
echo "  (cd $runner_dir && ./config.sh remove --token \"\$token\")"
