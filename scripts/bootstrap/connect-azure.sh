#!/usr/bin/env bash
# Azure browser authentication via the device-code flow.
#
# `az login --use-device-code` prints a URL + one-time code usable from any browser
# on any device — the right default because it behaves identically in Cloud Shell,
# Codespaces, SSH sessions, and local terminals. In Azure Cloud Shell login is
# already implicit (the shell starts authenticated), so this script just verifies.
#
# Usage:
#   scripts/bootstrap/connect-azure.sh                     # login if not already
#   scripts/bootstrap/connect-azure.sh --subscription <id> # login + select subscription
#   scripts/bootstrap/connect-azure.sh --force             # re-run login regardless
set -euo pipefail

if ! command -v az >/dev/null 2>&1; then
  echo "error: az (Azure CLI) is not installed." >&2
  echo "  Run scripts/bootstrap/cloud-shell-setup.sh first, or see https://aka.ms/azure-cli" >&2
  exit 1
fi

subscription=""
force=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --subscription) subscription="${2:?--subscription needs a value}"; shift 2 ;;
    --force) force=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

in_cloud_shell=""
[[ -n "${AZUREPS_HOST_ENVIRONMENT:-}" || -n "${ACC_CLOUD:-}" ]] && in_cloud_shell=1

if [[ -z "$force" ]] && az account show >/dev/null 2>&1; then
  echo "Azure: already authenticated${in_cloud_shell:+ (Cloud Shell implicit login)}."
elif [[ -n "$in_cloud_shell" && -z "$force" ]]; then
  echo "Azure: Cloud Shell session should be pre-authenticated but 'az account show' failed." >&2
  echo "  Try 'az login --use-device-code' manually — the shell token may have expired." >&2
  exit 1
else
  echo "Azure: starting device-code login (open the URL on any device and enter the code)..."
  az login --use-device-code --output none
fi

if [[ -n "$subscription" ]]; then
  az account set --subscription "$subscription"
fi

az account show --query '{subscription: name, tenant: tenantId, user: user.name}' --output table
