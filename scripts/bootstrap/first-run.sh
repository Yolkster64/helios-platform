#!/usr/bin/env bash
# ==============================================================================
# scripts/bootstrap/first-run.sh — the ONE command for a fresh shell.
#
# From a fresh Azure Cloud Shell, GitHub Codespace, or local shell this runs the
# whole HELIOS bring-up as an ordered chain over the EXISTING scripts (orchestrator
# only — nothing is reimplemented here), records every step and lane in
# .helios/bootstrap-state.json, and ends with ONE numbered checklist of the steps
# only a human can do. The PowerShell twin (first-run.ps1) has the same contract.
#
# Chain — every step is SOFT: its exit code is captured and the chain continues,
# because a lane that needs the owner is a checklist item, not a failure:
#   1. scripts/bootstrap/cloud-shell-setup.sh --skip-smoke   CLI fleet, device-code
#      logins (gh, az), Cloud Shell persistence, env wiring, readiness inventory.
#      --verify-only is forwarded (read-only). --skip-auth is added when stdin is
#      not a terminal or --json is given: a device-code login blocks on a human
#      typing a code, and a code hidden in a log helps nobody.
#   2. pwsh scripts/bootstrap/auto-login.ps1 -Json           acquire-and-report: az
#      repair is delegated to auth-doctor.ps1 -Apply (NON-interactive only — service
#      principal or managed identity — but still a login that rewrites the az
#      profile), then the Key Vault pulls; -UseManagedIdentity is forwarded.
#      SKIPPED under --verify-only, because a read-only pass must never change the
#      cached identity. (A child process cannot export into this shell either way.)
#   3. pwsh scripts/verify/rest-connect.ps1 -Json            wire truth (REST probes).
#   4. pwsh scripts/bootstrap/auth-doctor.ps1 -Json          lane table + owner actions
#      (report-only: the doctor mutates nothing without -Apply).
#   5. pwsh scripts/bootstrap/setup-everything.ps1 -Json     toolchain/identity/
#      inventory/smoke rollup (skipped with --skip-setup).
#   6. pwsh scripts/bootstrap/provision-github-secrets.ps1 -Json   repository
#      secrets/variables by NAME (dry run, never mutates): the wire truth behind the
#      repo-secret checklist items, so HELIOS_ADMIN_TOKEN is asked for because the
#      repo lacks it — not because the local gh keyring happens to be empty.
#
# Output — .helios/bootstrap-state.json (gitignored):
#   {generatedUtc, environment, verifyOnly,
#    steps[{name, script, exitCode, ok, note?}],   exitCode -1 = skipped (note says
#                                                   why), 127 = interpreter missing
#    lanes{<doctor lanes>..., "rest:github", "rest:azure"},
#    repoSecrets{<target>: "present" | "absent" | "unknown (<reason>)"},
#    ownerActions[{lane, action}],
#    checklist[{title, lines[]}]   the numbered human steps with their exact commands
#    reports{<step>: "bootstrap/<step>.json"}}      only the reports THIS run produced
# plus the raw per-step reports under .helios/bootstrap/*.json and the chain log
# .helios/bootstrap/first-run.log.
#
# Usage:
#   bash scripts/bootstrap/first-run.sh                      # full bring-up
#   bash scripts/bootstrap/first-run.sh --verify-only        # read-only: no installs, no logins
#                                                            # (step 2 skipped — see above)
#   bash scripts/bootstrap/first-run.sh --json               # the state JSON only on stdout
#   bash scripts/bootstrap/first-run.sh --skip-setup         # skip step 5 (setup-everything)
#   bash scripts/bootstrap/first-run.sh --managed-identity   # forward -UseManagedIdentity
#   bash scripts/bootstrap/first-run.sh --connect            # step 0: both device codes in one sitting
#
# Exit codes: 0 = the chain ran (needs-owner lanes NEVER gate — they ARE the
# checklist); 1 = internal failure (pwsh missing so no lane could be probed, or the
# state file could not be written).
#
# Secrets: nothing here reads a credential value; the child reports carry env-var
# NAMES only, and the checklist prints commands, never values.
# ==============================================================================
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
verify_only=""
json_mode=""
skip_setup=""
managed_identity=""
connect=""
for arg in "$@"; do
  case "$arg" in
    --verify-only) verify_only=1 ;;
    --json) json_mode=1 ;;
    --skip-setup) skip_setup=1 ;;
    --managed-identity) managed_identity=1 ;;
    --connect) connect=1 ;;
    -h|--help)
      echo "usage: bash scripts/bootstrap/first-run.sh [--verify-only] [--json] [--skip-setup] [--managed-identity] [--connect]"
      exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 1 ;;
  esac
done

# Documented env vars only, never heuristics (setup-ai-clis.ps1 / auth-doctor.ps1
# use the same probe): Cloud Shell is pre-authenticated to Azure and ships pwsh,
# which changes what the checklist even needs to say.
if [[ -n "${AZUREPS_HOST_ENVIRONMENT:-}" || -n "${ACC_CLOUD:-}" ]]; then
  environment="cloud-shell"
elif [[ -n "${CODESPACES:-}" ]]; then
  environment="codespaces"
else
  environment="local"
fi

state_dir="$repo_root/.helios/bootstrap"
state_file="$repo_root/.helios/bootstrap-state.json"
mkdir -p "$state_dir"
chain_log="$state_dir/first-run.log"
steps_file="$state_dir/steps.tsv"
: > "$chain_log"
: > "$steps_file"
# Stale reports from an earlier run must never feed this run's merge: a --skip-setup
# pass would otherwise re-read yesterday's setup-everything.json as if it ran today.
rm -f "$state_dir"/auto-login.json "$state_dir"/rest-connect.json "$state_dir"/auth-doctor.json \
  "$state_dir"/setup-everything.json "$state_dir"/provision-github-secrets.json

# --json promises the state object and nothing else on stdout, so every progress
# line gates on it (the -Json convention of the chained PowerShell scripts).
say() {
  [[ -n "$json_mode" ]] && return 0
  printf '%s\n' "$*"
}

# name, script, exit code, optional note (why a step was skipped) — one TSV row.
record_step() {
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "${4:-}" >> "$steps_file"
}

mode_label="full"
[[ -n "$verify_only" ]] && mode_label="verify-only"
say "== HELIOS first-run ($environment, $mode_label) — ordered chain over the existing scripts =="

# pwsh is resolved once: steps 2-6 are PowerShell, and a missing pwsh is the one
# condition that leaves the chain with no lane data at all (exit 1 below).
pwsh_exe="$(command -v pwsh 2>/dev/null || true)"
internal_failure=""
if [[ -z "$pwsh_exe" ]]; then
  say "   pwsh (PowerShell 7) is not on PATH — steps 2-6 cannot run; only step 1 will."
  internal_failure=1
fi

# --- 0. --connect: both device codes in one sitting (scripts/bootstrap/connect-devices.ps1)
# Runs before step 1 with the console inherited, logins only (-SkipChain): this
# script IS the chain. Step 1 then skips its own auth prompts. Never under
# --verify-only (a read-only pass changes no cached identity) and never without a
# terminal on stdin (a device code needs a human).
connect_done=""
if [[ -n "$connect" ]]; then
  if [[ -n "$verify_only" ]]; then
    say "   --connect ignored under --verify-only (a read-only pass performs no login)."
  elif [[ ! -t 0 || -n "$json_mode" ]]; then
    say "   --connect needs a terminal on stdin and a visible console (not --json); the logins stay checklist items."
  elif [[ -z "$pwsh_exe" ]]; then
    say "   --connect needs pwsh; the logins stay checklist items."
  else
    say ""
    say "-- 0. connect-devices (pwsh scripts/bootstrap/connect-devices.ps1 -SkipChain) --"
    set +e
    "$pwsh_exe" -NoProfile -File "$repo_root/scripts/bootstrap/connect-devices.ps1" -SkipChain
    connect_exit=$?
    set -e
    say "   connect-devices exited $connect_exit (0 = both logins ready; 2 = a lane still needs you - see its table)"
    connect_done=1
  fi
fi

# --- 1. cloud-shell-setup.sh (visible output; the device-code prompts must reach a human)
setup_args=()
if [[ -n "$verify_only" ]]; then
  setup_args+=(--verify-only)
else
  setup_args+=(--skip-smoke)
  # A device-code login blocks on a human typing the code: no terminal on stdin,
  # or stdout captured for --json, means the login is a checklist item instead;
  # after --connect the logins were just handled, so step 1 must not prompt again.
  if [[ ! -t 0 || -n "$json_mode" || -n "$connect_done" ]]; then
    setup_args+=(--skip-auth)
  fi
fi
setup_script="scripts/bootstrap/cloud-shell-setup.sh"
say ""
say "-- 1. cloud-shell-setup ($setup_script ${setup_args[*]}) --"
setup_rc=0
set +e
if [[ -n "$json_mode" ]]; then
  bash "$repo_root/$setup_script" "${setup_args[@]}" >> "$chain_log" 2>&1
  setup_rc=$?
else
  bash "$repo_root/$setup_script" "${setup_args[@]}" 2>&1 | tee -a "$chain_log"
  setup_rc=${PIPESTATUS[0]}
fi
set -e
say "   exit $setup_rc"
record_step "cloud-shell-setup" "$setup_script" "$setup_rc"

# --- 2..6 JSON steps: stdout (one object) captured to a file, stderr to the log.
run_json() {
  local num="$1" name="$2" script="$3"
  shift 3
  local out="$state_dir/$name.json" rc=0
  say ""
  say "-- $num. $name (pwsh $script $*) --"
  if [[ -z "$pwsh_exe" ]]; then
    say "   skipped: pwsh is not on PATH"
    record_step "$name" "$script" 127
    return 0
  fi
  set +e
  "$pwsh_exe" -NoProfile -File "$repo_root/$script" "$@" > "$out" 2>> "$chain_log"
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    say "   exit 0 (ok); report: ${out#"$repo_root"/}"
  else
    say "   exit $rc (not clean — the checklist below carries the fix); report: ${out#"$repo_root"/}"
  fi
  record_step "$name" "$script" "$rc"
}

# A step the mode rules out is recorded as skipped (exit -1 + the reason), never
# silently dropped: the state file must show what did NOT run and why.
skip_step() {
  local num="$1" name="$2" script="$3" why="$4"
  say ""
  say "-- $num. $name (pwsh $script) -- skipped: $why"
  record_step "$name" "$script" -1 "skipped: $why"
}

if [[ -n "$verify_only" ]]; then
  # auto-login.ps1 has no report-only switch: it always spawns auth-doctor -Apply,
  # which performs `az login --service-principal` / `--identity` when the env holds
  # those credentials — a login, and one that can switch the cached identity. That
  # is exactly what a verify-only pass promises not to do; step 4 already carries
  # the report-only doctor, so skipping loses no lane data.
  skip_step 2 "auto-login" "scripts/bootstrap/auto-login.ps1" \
    "verify-only (auto-login delegates to auth-doctor -Apply, which can log in non-interactively; -UseManagedIdentity not forwarded)"
else
  auto_login_args=(-Json)
  [[ -n "$managed_identity" ]] && auto_login_args+=(-UseManagedIdentity)
  run_json 2 "auto-login" "scripts/bootstrap/auto-login.ps1" "${auto_login_args[@]}"
fi
run_json 3 "rest-connect" "scripts/verify/rest-connect.ps1" -Json
run_json 4 "auth-doctor" "scripts/bootstrap/auth-doctor.ps1" -Json
if [[ -n "$skip_setup" ]]; then
  skip_step 5 "setup-everything" "scripts/bootstrap/setup-everything.ps1" "--skip-setup"
else
  run_json 5 "setup-everything" "scripts/bootstrap/setup-everything.ps1" -Json
fi
run_json 6 "provision-github-secrets" "scripts/bootstrap/provision-github-secrets.ps1" -Json

# --- Merge + checklist ----------------------------------------------------------
# python3 does the JSON merge (Cloud Shell, Codespaces, and every mainstream Linux
# or macOS shell ship it); without it the state still records the steps and the
# raw reports stay on disk, and the checklist says how to read them.
verify_flag=0
[[ -n "$verify_only" ]] && verify_flag=1
json_flag=0
[[ -n "$json_mode" ]] && json_flag=1
vault_set=0
[[ -n "${AZURE_KEY_VAULT_URI:-}" && -n "${AZURE_KEY_VAULT_URI// /}" ]] && vault_set=1

if command -v python3 >/dev/null 2>&1; then
  if ! python3 - "$state_dir" "$state_file" "$environment" "$verify_flag" "$json_flag" "$vault_set" <<'PY'
import datetime, json, os, sys

state_dir, state_file, environment, verify_flag, json_flag, vault_set = sys.argv[1:7]
verify_only = verify_flag == "1"
json_mode = json_flag == "1"
vault_present = vault_set == "1"
REPORT_NAMES = ("auto-login", "rest-connect", "auth-doctor", "setup-everything", "provision-github-secrets")


def load(name):
    """A child that emitted no parseable JSON is a failed step, never a crash."""
    path = os.path.join(state_dir, name + ".json")
    try:
        with open(path, encoding="utf-8") as handle:
            text = handle.read().strip()
        return json.loads(text) if text else None
    except (OSError, ValueError):
        return None


steps = []
with open(os.path.join(state_dir, "steps.tsv"), encoding="utf-8") as handle:
    for line in handle:
        line = line.rstrip("\n")
        if not line:
            continue
        parts = line.split("\t")
        name, script, rc = parts[:3]
        note = parts[3] if len(parts) > 3 else ""
        step = {"name": name, "script": script, "exitCode": int(rc), "ok": int(rc) == 0}
        if note:
            step["note"] = note
        steps.append(step)

doctor = load("auth-doctor")
rest = load("rest-connect")
auto_login = load("auto-login")
everything = load("setup-everything")
provision = load("provision-github-secrets")


def lane_rows(report):
    rows = report.get("lanes") if isinstance(report, dict) else None
    return [r for r in rows if isinstance(r, dict)] if isinstance(rows, list) else []


# Lanes are keyed by name so a consumer can ask lanes["gh"].state directly; the
# rest-connect lanes get a "rest:" prefix because "github"/"azure" there mean the
# WIRE, while the doctor's "gh"/"az" mean the CLI session.
lanes = {}
for row in lane_rows(doctor):
    lanes[str(row.get("lane", "?"))] = {
        k: row.get(k) for k in ("state", "method", "detail", "ownerAction") if row.get(k) not in (None, "")
    }
for row in lane_rows(rest):
    lanes["rest:" + str(row.get("lane", "?"))] = {
        k: row.get(k) for k in ("state", "source", "identity", "detail", "ownerAction") if row.get(k) not in (None, "")
    }

# Repository secrets/variables by NAME, straight from provision-github-secrets'
# per-target `current` ("present" / "absent" / "unknown (<reason>)"): the checklist
# asks for a repo secret because the REPO lacks it, never because a local CLI
# session happens to be logged out. No report at all is its own honest reason.
repo_secrets = {}
if isinstance(provision, dict):
    for row in provision.get("targets") or []:
        if isinstance(row, dict) and row.get("name"):
            repo_secrets[str(row["name"])] = str(row.get("current") or "unknown (no state reported)")


def repo_secret_state(name):
    return repo_secrets.get(name) or "unknown (provision-github-secrets.ps1 produced no report)"


owner_actions = []
seen = set()


def action_key(text):
    """Dedupe on the COMMAND portion: the same `az login --tenant ...` arrives from the
    doctor and again from setup-everything with slightly different trailing comments,
    and a checklist that lists one command twice reads as two steps."""
    return text.split("#", 1)[0].strip() if isinstance(text, str) else ""


def add_action(lane, text):
    text = (text or "").strip() if isinstance(text, str) else ""
    key = action_key(text)
    if not key or key in seen:
        return
    seen.add(key)
    owner_actions.append({"lane": lane, "action": text})


for row in lane_rows(doctor):
    add_action(str(row.get("lane", "?")), row.get("ownerAction"))
for row in lane_rows(rest):
    add_action("rest:" + str(row.get("lane", "?")), row.get("ownerAction"))
for source, report in (("auto-login", auto_login), ("setup-everything", everything)):
    if isinstance(report, dict):
        for action in report.get("ownerActions") or []:
            add_action(source, action if isinstance(action, str) else json.dumps(action))

# The checklist is built BEFORE the state is written so --json and the state file
# carry the same exact commands the terminal shows; a machine consumer must not
# get a vaguer list than the human.
def lane_state(name):
    return (lanes.get(name) or {}).get("state")


def needs_owner(name):
    return lane_state(name) == "needs-owner"


def raw_action(name):
    return (lanes.get(name) or {}).get("ownerAction") or ""


def lane_detail(name):
    return (lanes.get(name) or {}).get("detail") or ""


# The checklist: one item per needs-owner lane with the EXACT command, in the
# order a human would do them: logins first, then the Key Vault wiring (the
# set-provider-secrets lines below exit 2 until it is done), then the vault
# values, then the repository secrets. Raw doctor text is only used where no
# better command exists, and every raw line consumed here is remembered so the
# harvested tail never repeats it.
items = []
covered = set()
gh_login = "gh auth login --hostname github.com --git-protocol https --web --scopes models:read"
provision_apply = "pwsh scripts/bootstrap/provision-github-secrets.ps1 -Apply"
# The load step, once: the doctor's `(bash) or pwsh: ...` prose and connect-account's
# `# after the az lane ...` comment are this same step in two wordings, so every
# owner action starting with either command is covered by it.
load_lines = [
    "source scripts/bootstrap/load-env-from-keyvault.sh   # bash: Key Vault -> OPENAI_API_KEY / ANTHROPIC_API_KEY / GITHUB_MODELS_TOKEN in THIS shell",
    ". scripts/bootstrap/auto-login.ps1   # pwsh twin (dot-sourced)",
]
LOAD_PREFIXES = ("source scripts/bootstrap/load-env-from-keyvault.sh", ". scripts/bootstrap/auto-login.ps1")


def cover(text):
    key = action_key(text)
    if key:
        covered.add(key)


def is_covered(text):
    return action_key(text) in covered


def append_raw(lines, raw):
    """The doctor's own line is kept only when it adds a command the item does not
    already carry — its `claude setup-token` would otherwise print twice in one item."""
    if raw and action_key(raw) not in {action_key(line) for line in lines}:
        lines.append(raw)


def cover_load_actions():
    for action in owner_actions:
        if action_key(action["action"]).startswith(LOAD_PREFIXES):
            cover(action["action"])


# --- logins ---
# One sitting for both codes first; the two raw items after it are the by-hand path.
if needs_owner("gh") or needs_owner("az"):
    items.append(("GitHub + Azure device codes in one sitting",
                  ["pwsh scripts/bootstrap/connect-devices.ps1   # both codes on one screen (verify-first), then the chain; bash twin: bash scripts/bootstrap/connect-devices.sh; or: bash scripts/bootstrap/first-run.sh --connect"]))
if needs_owner("gh"):
    lines = [gh_login + "   # device code: gh prints a URL and a one-time code"]
    if lane_state("rest:github") == "ready":
        lines.append("# rest:github is already ready through the transport; the keyring login matters for gh on YOUR machine / Cloud Shell")
    items.append(("GitHub CLI login (device code)", lines))
    cover(raw_action("gh"))
if needs_owner("az"):
    az_raw = raw_action("az")
    items.append(("Azure login (device code + MFA)",
                  [az_raw if "az login" in az_raw else "az login --use-device-code   # then: az account set --subscription <id>"]))
    cover(az_raw)

# --- vault wiring BEFORE the vault values: every set-provider-secrets line below
# needs AZURE_KEY_VAULT_URI, so a human following the numbers must meet it first.
if not vault_present:
    # Executable lines, not a comment: azure-up.sh writes .helios/azure.env, and once
    # that file exists sourcing it IS the wiring; before it exists the provisioning
    # command (or an export pointing at an existing vault) is the step.
    repo_root = os.path.dirname(os.path.dirname(state_dir))
    if os.path.isfile(os.path.join(repo_root, ".helios", "azure.env")):
        wiring_lines = ["source .helios/azure.env   # written by scripts/bootstrap/azure-up.sh; sets AZURE_KEY_VAULT_URI for this shell"]
    else:
        wiring_lines = [
            "bash scripts/bootstrap/azure-up.sh   # provisions the vault (infra/main.bicep) and writes .helios/azure.env",
            "export AZURE_KEY_VAULT_URI=https://<vault>.vault.azure.net/   # or point at a vault that already exists",
        ]
    items.append(("Key Vault wiring (provider keys live in the vault, never in the repo)", wiring_lines + [
        "pwsh scripts/bootstrap/set-provider-secrets.ps1 -Apply   # masked prompts for openai-api-key / anthropic-api-key / github-models-token",
    ] + load_lines))
    # auto-login and setup-everything report the same wiring in their own words;
    # this item IS that step, so their lines must not resurface as a second one.
    for action in owner_actions:
        if "AZURE_KEY_VAULT_URI" in action["action"]:
            cover(action["action"])
    cover_load_actions()

# --- vault values ---
if needs_owner("openai-codex"):
    codex_lines = []
    # The device-code login is asked for only when the doctor did not already see
    # a cached CLI login; telling a human to redo a login that is done is noise.
    if "codex login status exits 0" in lane_detail("openai-codex"):
        codex_lines.append("# the codex CLI already holds a cached login (codex login status exits 0); only the openai / openai-codex API providers still need OPENAI_API_KEY")
    else:
        codex_lines.append("codex login --device-auth   # ChatGPT device code; covers the codex CLI only")
    codex_lines.append("pwsh scripts/bootstrap/set-provider-secrets.ps1 -Only openai-api-key -Apply   # masked prompt -> Key Vault -> OPENAI_API_KEY (openai / openai-codex API providers)")
    # The doctor's raw line for this lane is the load step, which the item already
    # carries (store, then load) — appending it would print the load twice.
    items.append(("Codex / OpenAI lane", codex_lines))
    cover(raw_action("openai-codex"))
if needs_owner("claude"):
    claude_lines = [
        "claude setup-token   # long-lived CLI token; owner-only, never probed headlessly",
        "pwsh scripts/bootstrap/set-provider-secrets.ps1 -Only anthropic-api-key -Apply   # -> Key Vault -> ANTHROPIC_API_KEY (anthropic provider)",
    ]
    append_raw(claude_lines, raw_action("claude"))
    items.append(("Claude lane", claude_lines))
    cover(raw_action("claude"))
if needs_owner("copilot"):
    items.append(("Copilot lane (rides the GitHub login)", [raw_action("copilot") or gh_login]))
    cover(raw_action("copilot"))
# With the vault already wired the load step has no wiring item to ride on; it is
# still the step that turns stored values into THIS shell's variables, so it is
# printed once here and never a second time from the harvested tail.
if vault_present and (needs_owner("openai-codex") or needs_owner("claude")):
    items.append(("Load the vault keys into this shell (after storing them)", list(load_lines)))
    cover_load_actions()

# --- repository secrets: driven by the repo's own state, not the local keyring ---
admin_state = repo_secret_state("HELIOS_ADMIN_TOKEN")
if admin_state != "present":
    items.append((
        "HELIOS_ADMIN_TOKEN repo secret (%s) — owner PAT for governance-apply.yml admin writes (fine-grained: "
        "Administration, Contents, Issues, Pull requests, Pages RW + Metadata R; permission list in the "
        ".github/workflows/governance-apply.yml header)" % admin_state,
        ["gh secret set HELIOS_ADMIN_TOKEN   # paste when prompted; the value never touches argv",
         "read -rs HELIOS_ADMIN_TOKEN && export HELIOS_ADMIN_TOKEN   # or: typed hidden, never on argv or in shell history, then:",
         provision_apply + "   # feeds every exported target to gh secret set over stdin"],
    ))
for lane, env_name in (("linear", "LINEAR_API_KEY"), ("slack", "SLACK_WEBHOOK_URL")):
    secret_state = repo_secret_state(env_name)
    if needs_owner(lane) or secret_state != "present":
        raw = raw_action(lane)
        items.append((lane + " connector secret (repo secret " + secret_state + ")", [
            raw if raw else ("gh secret set " + env_name),
            "read -rs " + env_name + " && export " + env_name + "   # or: typed hidden, never on argv or in shell history, then:",
            provision_apply + "   # feeds every exported target to gh secret set over stdin",
        ]))
        cover(raw)

# --- everything else the doctor flagged, tooling, then the harvested tail ---
for name, lane in lanes.items():
    if lane.get("state") == "needs-owner" and lane.get("ownerAction") and not is_covered(lane["ownerAction"]):
        items.append((name + " lane", [lane["ownerAction"]]))
        cover(lane["ownerAction"])
if any(step["exitCode"] == 127 for step in steps):
    items.append(("Install PowerShell 7 (steps 2-6 could not run)",
                  ["# https://aka.ms/powershell — Cloud Shell ships pwsh; then re-run: bash scripts/bootstrap/first-run.sh"]))
for action in owner_actions:
    if not is_covered(action["action"]):
        items.append(("reported by " + action["lane"], [action["action"]]))
        cover(action["action"])

state = {
    "generatedUtc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "environment": environment,
    "verifyOnly": verify_only,
    "steps": steps,
    "lanes": lanes,
    "repoSecrets": repo_secrets,
    "ownerActions": owner_actions,
    "checklist": [{"title": title, "lines": list(lines)} for title, lines in items],
    "reports": {name: os.path.relpath(os.path.join(state_dir, name + ".json"), os.path.dirname(state_dir))
                for name in REPORT_NAMES
                if os.path.exists(os.path.join(state_dir, name + ".json"))},
}
with open(state_file, "w", encoding="utf-8") as handle:
    json.dump(state, handle, indent=2, ensure_ascii=False)
    handle.write("\n")

if json_mode:
    print(json.dumps(state, indent=2, ensure_ascii=False))
    sys.exit(0)

print("")
print("== Steps ==")
for step in steps:
    if step["exitCode"] == -1:
        print("   %-26s %s   (%s)" % (step["name"], step.get("note", "skipped"), step["script"]))
    else:
        print("   %-26s exit %-3s %s   (%s)" % (step["name"], step["exitCode"], "ok " if step["ok"] else "not clean", step["script"]))
print("")
print("== Lanes (auth-doctor + rest-connect) ==")
if not lanes:
    print("   none captured — read .helios/bootstrap/*.json and .helios/bootstrap/first-run.log")
for name, lane in lanes.items():
    via = lane.get("method") or lane.get("source") or ""
    print("   %-14s %-12s %s" % (name, lane.get("state", "?"), via))
print("")
print("== Repository secrets / variables (provision-github-secrets, by name) ==")
if not repo_secrets:
    print("   none captured — provision-github-secrets.ps1 produced no report (see the Steps table)")
for name, current in repo_secrets.items():
    print("   %-24s %s" % (name, current))
print("")
print("== Remaining human steps ==")
if not items:
    print("   none — every lane is ready; nothing is waiting on the owner.")
for index, (title, lines) in enumerate(items, start=1):
    print("  %d. %s" % (index, title))
    for line in lines:
        print("       " + line)
print("")
print("Account creation and MFA cannot be automated: every login above needs the owner's own browser session and second factor; this script only prepares and verifies.")
print("State written: .helios/bootstrap-state.json (raw reports: .helios/bootstrap/*.json)")
PY
  then
    echo "first-run: internal failure — the state merge failed (see $chain_log)" >&2
    exit 1
  fi
else
  # Degraded: steps-only state, hand-rendered (no JSON tool), and the reader of the
  # raw reports is named instead of pretending to compute the lanes.
  {
    printf '{\n  "generatedUtc": "%s",\n  "environment": "%s",\n  "verifyOnly": %s,\n  "steps": [\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$environment" "$([[ -n "$verify_only" ]] && echo true || echo false)"
    first=1
    while IFS=$'\t' read -r name script rc note; do
      [[ -n "$name" ]] || continue
      [[ "$first" == 1 ]] || printf ',\n'
      first=0
      printf '    {"name": "%s", "script": "%s", "exitCode": %s, "ok": %s' \
        "$name" "$script" "$rc" "$([[ "$rc" == 0 ]] && echo true || echo false)"
      [[ -n "$note" ]] && printf ', "note": "%s"' "$note"
      printf '}'
    done < "$steps_file"
    printf '\n  ],\n  "lanes": {},\n  "repoSecrets": {},\n  "ownerActions": [],\n  "checklist": [],\n  "reports": {},\n  "note": "python3 not found: lanes not merged; read .helios/bootstrap/*.json"\n}\n'
  } > "$state_file"
  if [[ -n "$json_mode" ]]; then
    cat "$state_file"
  else
    say ""
    say "== Remaining human steps =="
    say "  1. python3 is not installed, so the lane merge was skipped — read the raw reports:"
    say "       pwsh scripts/bootstrap/auth-doctor.ps1                 # human lane table with the exact owner commands"
    say "       pwsh scripts/verify/rest-connect.ps1                   # wire truth"
    say "       pwsh scripts/bootstrap/provision-github-secrets.ps1    # repository secrets/variables by name"
    say ""
    say "Account creation and MFA cannot be automated: every login needs the owner's own browser session and second factor."
    say "State written: .helios/bootstrap-state.json (steps only)"
  fi
fi

if [[ -n "$internal_failure" ]]; then
  echo "first-run: internal failure — pwsh (PowerShell 7) is not on PATH, so no lane could be probed; the checklist names the install." >&2
  exit 1
fi
exit 0
