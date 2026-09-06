#!/usr/bin/env bash
# One sitting for the two device codes a human must type - GitHub (gh) and Azure (az) -
# then the whole bring-up chain without another prompt. Bash twin of
# scripts/bootstrap/connect-devices.ps1 (same lanes, flags, table and exit codes).
#
# Why: a device code exists so a human proves presence in a browser and MFA cannot be
# delegated. Everything around the two codes can be automatic - both flows started at
# once, both codes on one screen, the shell polling until both complete, the rest of
# the bring-up chained without another prompt - and that is what this script does.
#
#   1. Verify-first: `gh auth status --hostname github.com --active` (unknown-flag
#      fallback) and `az account get-access-token --tenant <tenant> --output none`;
#      a lane that is already ready is never asked for a code.
#   2. Both flows start together, stdin from /dev/null (gh then prints its code instead
#      of waiting for Enter), output captured to per-lane files:
#        env -u GH_TOKEN -u GITHUB_TOKEN gh auth login --hostname github.com \
#            --git-protocol https --web --scopes repo,workflow,project,read:org,models:read
#        az login --use-device-code --tenant <tenant>
#      GH_TOKEN / GITHUB_TOKEN are cleared for the gh child: a stub token in this shell
#      (agent containers export one) would otherwise pre-empt the keyring login.
#   3. One table with both codes and URLs as soon as both are known. Device CODES are
#      meant to be shown; no token value ever is.
#   4. Both children polled until they exit or --timeout-minutes passes: ready
#      (re-verified with the probes above), expired (--retry re-issues once), refused
#      (AADSTS / declined / authentication failed) or failed.
#   5. Both ready -> the chain: `source scripts/bootstrap/connect-github.sh` (exports
#      GITHUB_MODELS_TOKEN when THIS script is sourced), connect-github-app.ps1
#      -DispatchGovernance (--skip-github-app), connect-admin.ps1 -SkipGitHub
#      (--skip-ops-identity), auto-login.ps1 as a child for its report (a bash shell
#      loads the vault keys with `source scripts/bootstrap/load-env-from-keyvault.sh`),
#      auth-doctor.ps1 -Json, first-run.sh --verify-only. --skip-chain stops after the
#      logins.
#
# Exit 0 = every lane ready (or skipped by a flag); 1 = a chained script failed; 2 = a
# login lane needs the owner or a precondition is missing. --json prints one object.
# Sourced (`source scripts/bootstrap/connect-devices.sh`) it returns instead of
# exiting and exports into your shell.
#
# Usage:
#   bash scripts/bootstrap/connect-devices.sh [--verify-only] [--json] [--retry]
#        [--tenant <id>] [--repository <owner/name>] [--skip-github-app]
#        [--skip-ops-identity] [--skip-chain] [--timeout-minutes <n>]
#   source scripts/bootstrap/connect-devices.sh        # also exports GITHUB_MODELS_TOKEN

_cd_sourced=0
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && _cd_sourced=1
if (( ! _cd_sourced )); then set -euo pipefail; fi

_cd_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_cd_script_rel='scripts/bootstrap/connect-devices.sh'
_cd_verify_only=0
_cd_json=0
_cd_retry=0
_cd_tenant='349e1399-dccf-45b1-af7e-05d7b0676abf'
_cd_repository='Yolkster64/helios-platform'
_cd_skip_app=0
_cd_skip_ops=0
_cd_skip_chain=0
_cd_timeout_minutes=15
_cd_scopes='repo,workflow,project,read:org,models:read'
_cd_lane_names=()
_cd_lane_states=()
_cd_lane_details=()
_cd_lane_actions=()
_cd_replay=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --verify-only) _cd_verify_only=1 ;;
    --json) _cd_json=1 ;;
    --retry) _cd_retry=1 ;;
    --tenant) _cd_tenant="${2:-}"; shift ;;
    --repository) _cd_repository="${2:-}"; shift ;;
    --skip-github-app) _cd_skip_app=1 ;;
    --skip-ops-identity) _cd_skip_ops=1 ;;
    --skip-chain) _cd_skip_chain=1 ;;
    --timeout-minutes) _cd_timeout_minutes="${2:-15}"; shift ;;
    -h|--help) sed -n '2,45p' "${BASH_SOURCE[0]}"; if (( _cd_sourced )); then return 0; else exit 0; fi ;;
    *) echo "connect-devices: unknown option: $1" >&2; if (( _cd_sourced )); then return 2; else exit 2; fi ;;
  esac
  shift
done

_cd_mode='apply'; (( _cd_verify_only )) && _cd_mode='verify-only'

_cd_log() { (( _cd_json )) || printf '%s\n' "$*"; }
_cd_add_lane() { _cd_lane_names+=("$1"); _cd_lane_states+=("$2"); _cd_lane_details+=("$3"); _cd_lane_actions+=("${4:-}"); }
_cd_json_escape() { local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\t'/\\t}"; printf '%s' "$s"; }

_cd_finish() {
  local exit_code="$1" precondition="${2:-}"
  local i failed=0 owner=0
  for ((i = 0; i < ${#_cd_lane_names[@]}; i++)); do
    case "${_cd_lane_states[$i]}" in failed) failed=1 ;; needs-owner) owner=1 ;; esac
  done
  if [[ -z "$precondition" ]]; then
    if (( failed || ${#_cd_replay[@]} > 0 )); then exit_code=1; elif (( owner )); then exit_code=2; else exit_code=0; fi
  fi
  if (( _cd_json )); then
    printf '{\n  "script": "%s",\n  "generatedUtc": "%s",\n  "mode": "%s",\n  "repository": "%s",\n  "tenant": "%s",\n' \
      "$_cd_script_rel" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$_cd_mode" "$(_cd_json_escape "$_cd_repository")" "$(_cd_json_escape "$_cd_tenant")"
    if [[ -n "$precondition" ]]; then printf '  "failedPrecondition": "%s",\n' "$(_cd_json_escape "$precondition")"; fi
    printf '  "lanes": ['
    for ((i = 0; i < ${#_cd_lane_names[@]}; i++)); do
      (( i > 0 )) && printf ','
      printf '\n    {"name": "%s", "state": "%s", "detail": "%s", "ownerAction": "%s"}' \
        "$(_cd_json_escape "${_cd_lane_names[$i]}")" "${_cd_lane_states[$i]}" "$(_cd_json_escape "${_cd_lane_details[$i]}")" "$(_cd_json_escape "${_cd_lane_actions[$i]}")"
    done
    printf '\n  ],\n  "replay": ['
    for ((i = 0; i < ${#_cd_replay[@]}; i++)); do (( i > 0 )) && printf ','; printf '"%s"' "$(_cd_json_escape "${_cd_replay[$i]}")"; done
    printf '],\n  "exitCode": %s\n}\n' "$exit_code"
  else
    echo
    echo '== Summary =='
    printf '  %-22s %-12s %s\n' Lane State Next
    for ((i = 0; i < ${#_cd_lane_names[@]}; i++)); do
      printf '  %-22s %-12s %s\n' "${_cd_lane_names[$i]}" "${_cd_lane_states[$i]}" "${_cd_lane_actions[$i]:--}"
    done
    echo
    if (( ${#_cd_replay[@]} > 0 )); then
      echo "connect-devices: ${#_cd_replay[@]} item(s) FAILED - replay list:"; printf '  %s\n' "${_cd_replay[@]}"
    elif (( owner )); then echo 'connect-devices: lane(s) need the owner - the Next column names the step.'
    else echo "connect-devices: every lane is ready ($_cd_mode)."; fi
  fi
  if (( _cd_sourced )); then return "$exit_code"; else exit "$exit_code"; fi
}

_cd_precondition() {
  _cd_log "connect-devices: FAILED PRECONDITION - $1"
  shift; local line; for line in "$@"; do _cd_log "  $line"; done
  _cd_log 'Nothing was changed.'
  _cd_finish 2 "$1"
}

_cd_gh_ready() {
  local out
  if out="$(env -u GH_TOKEN -u GITHUB_TOKEN gh auth status --hostname github.com --active 2>&1)"; then return 0; fi
  if grep -q 'unknown flag' <<<"$out"; then env -u GH_TOKEN -u GITHUB_TOKEN gh auth status --hostname github.com >/dev/null 2>&1; return $?; fi
  return 1
}
_cd_az_ready() { az account get-access-token --tenant "$_cd_tenant" --output none >/dev/null 2>&1; }

_cd_log "connect-devices: mode=$_cd_mode tenant=$_cd_tenant repository=$_cd_repository"
if [[ ! "$_cd_repository" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]]; then _cd_precondition "--repository must be owner/name (got '$_cd_repository')"; return $? 2>/dev/null || exit $?; fi
if [[ ! "$_cd_tenant" =~ ^[0-9a-fA-F-]{36}$ ]]; then _cd_precondition "--tenant must be a tenant id (got '$_cd_tenant')"; return $? 2>/dev/null || exit $?; fi
_cd_missing=()
command -v gh >/dev/null 2>&1 || _cd_missing+=(gh)
command -v az >/dev/null 2>&1 || _cd_missing+=(az)
if (( ${#_cd_missing[@]} > 0 )); then _cd_precondition "not installed: ${_cd_missing[*]}" 'gh: https://cli.github.com' 'az: https://aka.ms/installazurecli' 'or: pwsh scripts/bootstrap/setup-all.ps1'; return $? 2>/dev/null || exit $?; fi

_cd_gh_ok=0; _cd_az_ok=0
_cd_gh_ready && _cd_gh_ok=1
_cd_az_ready && _cd_az_ok=1
if (( _cd_gh_ok )); then _cd_add_lane github-login ready 'gh already logged in to github.com (active account)'; fi
if (( _cd_az_ok )); then _cd_add_lane azure-login ready "az already holds a live token for tenant $_cd_tenant"; fi

_cd_gh_cmd="gh auth login --hostname github.com --git-protocol https --web --scopes $_cd_scopes"
_cd_az_cmd="az login --use-device-code --tenant $_cd_tenant"

if (( _cd_verify_only )); then
  (( _cd_gh_ok )) || _cd_add_lane github-login needs-owner 'not logged in' "$_cd_gh_cmd   # or: bash $_cd_script_rel"
  (( _cd_az_ok )) || _cd_add_lane azure-login needs-owner 'not logged in' "$_cd_az_cmd   # or: bash $_cd_script_rel"
  _cd_chain='connect-github-app, connect-admin -SkipGitHub, auto-login, auth-doctor -Json, first-run --verify-only'
  (( _cd_skip_chain )) && _cd_chain='skipped (--skip-chain)'
  _cd_add_lane chain skipped "verify-only; would run: $_cd_chain"
  _cd_finish 0; return $? 2>/dev/null || exit $?
fi

# --- Device flows -----------------------------------------------------------------------
_cd_tmp="$(mktemp -d)"
_cd_cleanup() { [[ -n "${_cd_tmp:-}" ]] && rm -rf "$_cd_tmp"; }

# Starts one lane in the background: $1 lane, $2.. command. Output file: $_cd_tmp/<lane>.log
_cd_start() {
  local lane="$1"; shift
  if [[ "$lane" == github ]]; then
    env -u GH_TOKEN -u GITHUB_TOKEN "$@" </dev/null >"$_cd_tmp/$lane.log" 2>&1 &
  else
    "$@" </dev/null >"$_cd_tmp/$lane.log" 2>&1 &
  fi
  echo $! >"$_cd_tmp/$lane.pid"
}
_cd_code_of() {
  local lane="$1" file="$_cd_tmp/$1.log"
  [[ -f "$file" ]] || return 0
  if [[ "$lane" == github ]]; then grep -oiE 'one-time code:?[[:space:]]*[A-Z0-9]{4}-[A-Z0-9]{4}' "$file" | grep -oE '[A-Z0-9]{4}-[A-Z0-9]{4}' | head -n1
  else grep -oiE 'enter the code[[:space:]]+[A-Z0-9]{6,12}[[:space:]]+to authenticate' "$file" | grep -oE '[A-Z0-9]{6,12}' | head -n1; fi
}
_cd_verdict() {
  local lane="$1" code="$2" file="$_cd_tmp/$1.log" tail_text
  (( code == 0 )) && { echo ready; return; }
  (( code == 124 )) && { echo expired; return; }
  tail_text="$(tail -n 8 "$file" 2>/dev/null || true)"
  if grep -qiE 'expired|timed out|time out|timeout' <<<"$tail_text"; then echo expired
  elif grep -qiE 'AADSTS|declined|denied|access_denied|authentication failed|cancel' <<<"$tail_text"; then echo refused
  else echo failed; fi
}

# Runs the pending lanes ($1 = space-separated) together; verdicts land in
# _cd_result_<lane> and _cd_detail_<lane>.
_cd_run_flows() {
  local lanes="$1" lane deadline now printed=0 running pid rc
  local timeout_s; timeout_s="$(awk -v m="$_cd_timeout_minutes" 'BEGIN { s = m * 60; if (s < 1) s = 1; printf "%d", s }')"
  for lane in $lanes; do
    if [[ "$lane" == github ]]; then _cd_start github $_cd_gh_cmd; else _cd_start azure $_cd_az_cmd; fi
  done
  deadline=$(( $(date +%s) + timeout_s ))
  while true; do
    running=0
    for lane in $lanes; do pid="$(cat "$_cd_tmp/$lane.pid")"; kill -0 "$pid" 2>/dev/null && running=1; done
    if (( ! printed )); then
      local all=1; for lane in $lanes; do [[ -n "$(_cd_code_of "$lane")" ]] || all=0; done
      now=$(date +%s)
      if (( all || ! running || now - deadline + timeout_s > 20 )); then
        _cd_log ''; _cd_log '  Enter these codes (any browser, any device):'
        for lane in $lanes; do
          local c; c="$(_cd_code_of "$lane")"; [[ -n "$c" ]] || c='(waiting for the CLI to print it)'
          if [[ "$lane" == github ]]; then _cd_log "    GitHub -> https://github.com/login/device                code $c"
          else _cd_log "    Azure  -> https://microsoft.com/devicelogin               code $c"; fi
        done
        _cd_log ''; printed=1
      fi
    fi
    (( running )) || break
    (( $(date +%s) >= deadline )) && break
    sleep 0.5
  done
  for lane in $lanes; do
    pid="$(cat "$_cd_tmp/$lane.pid")"
    if kill -0 "$pid" 2>/dev/null; then kill "$pid" 2>/dev/null || true; sleep 0.2; kill -9 "$pid" 2>/dev/null || true; rc=124
    else wait "$pid" 2>/dev/null; rc=$?; fi
    local v; v="$(_cd_verdict "$lane" "$rc")"
    local d; if (( rc == 124 )); then d="no completion within $_cd_timeout_minutes min"; else d="$(grep -v '^[[:space:]]*$' "$_cd_tmp/$lane.log" | tail -n1 | cut -c1-160)"; fi
    printf -v "_cd_result_$lane" '%s' "$v"
    printf -v "_cd_detail_$lane" '%s' "$d"
  done
}

_cd_pending=''
(( _cd_gh_ok )) || _cd_pending="$_cd_pending github"
(( _cd_az_ok )) || _cd_pending="$_cd_pending azure"
if [[ -n "$_cd_pending" ]]; then
  _cd_log "  starting device flow(s) together:"
  for _cd_l in $_cd_pending; do if [[ "$_cd_l" == github ]]; then _cd_log "    $_cd_gh_cmd"; else _cd_log "    $_cd_az_cmd"; fi; done
  _cd_run_flows "$_cd_pending"
  if (( _cd_retry )); then
    _cd_again=''
    for _cd_l in $_cd_pending; do _cd_v="_cd_result_$_cd_l"; [[ "${!_cd_v}" == expired ]] && _cd_again="$_cd_again $_cd_l"; done
    if [[ -n "$_cd_again" ]]; then _cd_log '  re-issuing expired code(s) once (--retry):'; _cd_run_flows "$_cd_again"; fi
  fi
  for _cd_l in $_cd_pending; do
    _cd_v="_cd_result_$_cd_l"; _cd_d="_cd_detail_$_cd_l"
    _cd_lane_name='github-login'; _cd_cli=gh; _cd_probe=_cd_gh_ready; _cd_cmd="$_cd_gh_cmd"
    if [[ "$_cd_l" == azure ]]; then _cd_lane_name='azure-login'; _cd_cli=az; _cd_probe=_cd_az_ready; _cd_cmd="$_cd_az_cmd"; fi
    if [[ "${!_cd_v}" == ready ]] && "$_cd_probe"; then
      _cd_add_lane "$_cd_lane_name" ready "device code accepted; $_cd_cli session verified"
      if [[ "$_cd_l" == github ]]; then _cd_gh_ok=1; else _cd_az_ok=1; fi
    elif [[ "${!_cd_v}" == ready ]]; then
      _cd_add_lane "$_cd_lane_name" failed "$_cd_cli exited 0 but the session probe still fails" "$_cd_cmd"; _cd_replay+=("$_cd_cmd")
    else
      _cd_action="bash $_cd_script_rel"; [[ "${!_cd_v}" == expired ]] && _cd_action="bash $_cd_script_rel --retry"
      _cd_add_lane "$_cd_lane_name" needs-owner "${!_cd_v}: ${!_cd_d}" "$_cd_action"
    fi
  done
fi
_cd_cleanup

# --- Chain --------------------------------------------------------------------------------
if (( _cd_skip_chain )); then
  _cd_add_lane chain skipped '--skip-chain'
elif (( ! (_cd_gh_ok && _cd_az_ok) )); then
  _cd_add_lane chain skipped 'both logins must be ready first'
else
  _cd_log ''; _cd_log '  both logins ready - running the chain:'
  if (( _cd_sourced )); then
    # shellcheck disable=SC1091
    if source "$_cd_script_dir/connect-github.sh" >/dev/null 2>&1 && [[ -n "${GITHUB_MODELS_TOKEN:-}" ]]; then
      _cd_add_lane github-models-export ready 'GITHUB_MODELS_TOKEN exported into this shell (value not shown)'
    else
      _cd_add_lane github-models-export needs-owner 'connect-github.sh did not export a token' 'source scripts/bootstrap/connect-github.sh'
    fi
  else
    _cd_add_lane github-models-export needs-owner 'a child process cannot export into your shell' 'source scripts/bootstrap/connect-devices.sh   (or: source scripts/bootstrap/connect-github.sh)'
  fi
  _cd_pwsh="$(command -v pwsh || true)"
  if [[ -z "$_cd_pwsh" ]]; then
    _cd_add_lane github-app needs-owner 'pwsh not installed' 'install PowerShell 7, then: pwsh scripts/bootstrap/connect-github-app.ps1 -DispatchGovernance'
    _cd_add_lane ops-identity needs-owner 'pwsh not installed' 'pwsh scripts/bootstrap/connect-admin.ps1 -SkipGitHub'
    _cd_add_lane vault-keys needs-owner 'pwsh not installed' 'source scripts/bootstrap/load-env-from-keyvault.sh'
    _cd_add_lane doctor needs-owner 'pwsh not installed' 'pwsh scripts/bootstrap/auth-doctor.ps1'
  else
    if (( _cd_skip_app )); then _cd_add_lane github-app skipped '--skip-github-app'
    else
      _cd_log "  + pwsh $_cd_script_dir/connect-github-app.ps1 -Repository $_cd_repository -DispatchGovernance"
      "$_cd_pwsh" -NoProfile -File "$_cd_script_dir/connect-github-app.ps1" -Repository "$_cd_repository" -DispatchGovernance; _cd_rc=$?
      case "$_cd_rc" in
        0) _cd_add_lane github-app ready 'App registered, installed, governance dispatched' ;;
        2) _cd_add_lane github-app needs-owner 'connect-github-app.ps1 exited 2' 'pwsh scripts/bootstrap/connect-github-app.ps1 -DispatchGovernance (its Next column names the step)' ;;
        *) _cd_add_lane github-app failed "connect-github-app.ps1 exited $_cd_rc"; _cd_replay+=("pwsh scripts/bootstrap/connect-github-app.ps1 -Repository $_cd_repository -DispatchGovernance") ;;
      esac
    fi
    if (( _cd_skip_ops )); then _cd_add_lane ops-identity skipped '--skip-ops-identity'
    else
      _cd_log "  + pwsh $_cd_script_dir/connect-admin.ps1 -SkipGitHub -Repository $_cd_repository"
      "$_cd_pwsh" -NoProfile -File "$_cd_script_dir/connect-admin.ps1" -SkipGitHub -Repository "$_cd_repository"; _cd_rc=$?
      case "$_cd_rc" in
        0) _cd_add_lane ops-identity ready 'setup-tenant -OpsIdentity applied; export the three AZURE_* names it printed' ;;
        2) _cd_add_lane ops-identity needs-owner 'connect-admin.ps1 exited 2' 'pwsh scripts/bootstrap/connect-admin.ps1 -SkipGitHub (its Next column names the step)' ;;
        *) _cd_add_lane ops-identity failed "connect-admin.ps1 exited $_cd_rc"; _cd_replay+=("pwsh scripts/bootstrap/connect-admin.ps1 -SkipGitHub -Repository $_cd_repository") ;;
      esac
    fi
    _cd_log "  + pwsh $_cd_script_dir/auto-login.ps1   (report only from bash; the loader below exports)"
    "$_cd_pwsh" -NoProfile -File "$_cd_script_dir/auto-login.ps1"; _cd_rc=$?
    if (( _cd_rc == 0 )); then _cd_add_lane vault-keys ready 'auto-login.ps1 reported ready' 'source scripts/bootstrap/load-env-from-keyvault.sh   # exports into this shell'
    else _cd_add_lane vault-keys needs-owner "auto-login.ps1 exited $_cd_rc" 'source scripts/bootstrap/load-env-from-keyvault.sh'; fi
    _cd_log "  + pwsh $_cd_script_dir/auth-doctor.ps1 -Json"
    "$_cd_pwsh" -NoProfile -File "$_cd_script_dir/auth-doctor.ps1" -Json; _cd_rc=$?
    if (( _cd_rc == 0 )); then _cd_add_lane doctor ready 'auth-doctor.ps1 -Json exited 0'
    else _cd_add_lane doctor needs-owner "auth-doctor.ps1 -Json exited $_cd_rc" 'pwsh scripts/bootstrap/auth-doctor.ps1 (read its lane table)'; fi
  fi
  _cd_log "  + bash $_cd_script_dir/first-run.sh --verify-only"
  bash "$_cd_script_dir/first-run.sh" --verify-only; _cd_rc=$?
  if (( _cd_rc == 0 )); then _cd_add_lane first-run ready 'first-run verify-only exited 0 (its checklist lists what is left)'
  else _cd_add_lane first-run failed "first-run verify-only exited $_cd_rc"; _cd_replay+=('bash scripts/bootstrap/first-run.sh --verify-only'); fi
fi

_cd_finish 0; return $? 2>/dev/null || exit $?
