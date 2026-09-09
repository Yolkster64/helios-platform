#!/usr/bin/env bash
# ==============================================================================
# scripts/bootstrap/connect.sh — connect everything, in one sitting, from Cloud Shell.
#
# Azure Cloud Shell is the home surface: your Azure sign-in is already there, the
# checkout and the CLIs persist under clouddrive, and nothing has to live on a
# laptop. Codespaces and any local Linux/macOS shell work the same way; the
# PowerShell twin (connect.ps1) is the Windows path.
#
# This is an ORCHESTRATOR. Every lane is an existing script called by path — no
# credential logic is reimplemented here — and every lane is SOFT: its exit code
# is recorded and the run continues, because a lane that needs you is a checklist
# item, not a failure.
#
# Lanes, in order:
#   0 persistence      cloud-shell-setup.sh          (Cloud Shell only)
#   1 github           gh device login IN THE FOREGROUND, so the code is visible
#   2 app              connect-github-app.ps1        (App install = admin, once)
#   3 oidc             azure-oidc-setup.sh           (the three repo variables)
#   4 secrets          set-provider-secrets.ps1      (masked prompts, Key Vault)
#   5 hub              auto-login.ps1                (pull what the vault holds)
#   6 codex            codex login + write-codex-config.ps1
#   7 foundry          Connect-ClaudeFoundry.ps1     (Entra, no key)
#   8 connectors       Linear + Slack secret NAMES, and the Linear sync switch
#   9 workspace        editor + agent surfaces: MCP servers, devcontainer, workspace
#  10 agents           the GitHub agents: Codex cloud, Copilot, Claude on Foundry
#  11 fleet            Hermes / XCore locally; the burst pool waits for your word
#  12 m365             Microsoft 365 — tenant consent, a decision and not a key
#  13 verify           first-run.sh --verify-only
#
# Lanes 8-12 are REPORT-ONLY: they never write, they say what is wired and what
# is one click of yours away, so the single command covers every surface rather
# than the ones a script can act on.
#
# It ends with ONE numbered list of what is left for you, each item a single
# paste-able command or one click, and remembers where it got to in
# .helios/connect-state.json, so a second run picks up and prints a shorter list.
#
# Exit codes are the contract: 0 = nothing left for you, 2 = items remain (they
# are listed), 1 = a lane failed for a reason that is not yours to fix.
#
# Secrets: every credential is referenced by the NAME of its environment
# variable or Key Vault secret. No value is printed, logged or stored here.
# ==============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="$REPO_ROOT/.helios"
STATE_FILE="$STATE_DIR/connect-state.json"

verify_only=0
json_mode=0
github_code_only=0
declare -A skip=()

usage() {
    cat <<'USAGE'
usage: bash scripts/bootstrap/connect.sh [options]

  --status            read-only lane table; runs nothing that changes anything
  --verify-only       every lane in its verify mode (no login, no write)
  --github-code       ONLY the GitHub sign-in, in the foreground, then stop
  --json              one JSON object on stdout (implies non-interactive)
  --skip-<lane>       skip one lane: persistence github app oidc secrets hub
                      codex foundry connectors workspace agents fleet m365 verify
  -h, --help          this text

Cloud Shell is the intended home: paste one line there and answer at most five
prompts. See docs/CONNECT.md.
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --status) verify_only=1 ;;
        --verify-only) verify_only=1 ;;
        --github-code) github_code_only=1 ;;
        --json) json_mode=1 ;;
        --skip-*) skip["${1#--skip-}"]=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
    shift
done

# --json must never block on a prompt: a device code hidden in a log helps nobody.
interactive=1
if [ "$json_mode" -eq 1 ] || [ ! -t 0 ]; then interactive=0; fi

# ---------------------------------------------------------------------------
# Surface: Cloud Shell first. In Cloud Shell the Azure session already exists,
# so no az device code is ever needed there.
# ---------------------------------------------------------------------------
surface="local"
if [ -n "${AZUREPS_HOST_ENVIRONMENT:-}" ] || [ -n "${ACC_CLOUD:-}" ]; then
    surface="cloud-shell"
elif [ -n "${CODESPACES:-}" ]; then
    surface="codespaces"
fi

lane_names=(); lane_states=(); lane_details=(); lane_actions=()

record() {   # record <lane> <state> <detail> [owner action]
    lane_names+=("$1"); lane_states+=("$2"); lane_details+=("$3"); lane_actions+=("${4:-}")
}

say() { [ "$json_mode" -eq 1 ] || printf '%s\n' "$*"; }
step() { [ "$json_mode" -eq 1 ] || printf '\n-- %s --\n' "$*"; }

skipped() { [ -n "${skip[$1]:-}" ]; }

have() { command -v "$1" >/dev/null 2>&1; }

pwsh_bin=""
for candidate in "$REPO_ROOT/.tools/pwsh/pwsh" pwsh; do
    if [ -x "$candidate" ] || have "$candidate"; then pwsh_bin="$candidate"; break; fi
done

run_pwsh() {   # run_pwsh <script-relative-path> [args...]; echoes nothing, returns the exit code
    if [ -z "$pwsh_bin" ]; then return 127; fi
    "$pwsh_bin" -NoProfile -File "$REPO_ROOT/$1" "${@:2}" >/dev/null 2>&1
}

run_pwsh_json() {   # like run_pwsh, but echoes stdout so the caller can read the report
    if [ -z "$pwsh_bin" ]; then return 127; fi
    "$pwsh_bin" -NoProfile -File "$REPO_ROOT/$1" "${@:2}" 2>/dev/null
}

owner_action_count() {   # stdin: a -Json report; echoes the number of owner actions, or "?"
    # An exit code is not the verdict: auto-login.ps1 exits 0 whether or not providers are
    # unconfigured and reserves non-zero for internal failure, so reading $? alone reported
    # "every provider resolved" for a host where none had. The report says what is left.
    if ! have python3; then printf '?'; return; fi
    # Two shapes, because the two scripts report differently: auto-login carries ownerActions[],
    # auth-doctor carries lanes[] with a per-lane state. Either answers "how much is left".
    python3 -c '
import json, sys
try:
    report = json.load(sys.stdin)
except Exception:
    print("?"); sys.exit(0)
actions = report.get("ownerActions")
if isinstance(actions, list):
    print(len(actions)); sys.exit(0)
lanes = report.get("lanes")
if isinstance(lanes, dict):
    lanes = list(lanes.values())
if isinstance(lanes, list):
    print(sum(1 for lane in lanes
              if isinstance(lane, dict) and lane.get("state") not in ("ready", "ok")))
else:
    print("?")
' 2>/dev/null || printf '?'
}

# ---------------------------------------------------------------------------
# 1. GitHub — the device code is printed by gh itself, in the foreground.
#
# The older path started gh with stdin closed and grepped its output for the
# code, which silently produced nothing whenever the capture missed. Here the
# terminal is attached, so gh prints its own code and URL and waits; only a
# non-interactive run falls back to naming the command.
# ---------------------------------------------------------------------------
GH_SCOPES="repo,workflow,project,read:org,models:read"
GH_LOGIN_CMD="env -u GH_TOKEN -u GITHUB_TOKEN gh auth login --hostname github.com --git-protocol https --web --scopes $GH_SCOPES"

github_lane() {
    step "1. GitHub sign-in"
    if ! have gh; then
        record github needs-owner "the gh CLI is not installed on this host" \
            "install the GitHub CLI (https://cli.github.com), then re-run this script"
        say "   gh is not installed."
        return
    fi
    if env -u GH_TOKEN -u GITHUB_TOKEN gh auth status --hostname github.com >/dev/null 2>&1; then
        record github ok "gh is signed in on this host"
        say "   already signed in."
        return
    fi
    if [ "$verify_only" -eq 1 ] || [ "$interactive" -eq 0 ]; then
        record github needs-owner "gh is not signed in; the device flow needs a terminal" "$GH_LOGIN_CMD"
        say "   not signed in. Run this where you can read the code it prints:"
        say "     $GH_LOGIN_CMD"
        return
    fi
    say "   gh prints a one-time code and a URL below. Open the URL on any device,"
    say "   type the code, and this waits for you."
    say ""
    if env -u GH_TOKEN -u GITHUB_TOKEN gh auth login --hostname github.com \
            --git-protocol https --web --scopes "$GH_SCOPES"; then
        record github ok "signed in through the device flow"
    else
        record github needs-owner "the device flow did not complete" "$GH_LOGIN_CMD"
    fi
}

if [ "$github_code_only" -eq 1 ]; then
    github_lane
    exit $([ "${lane_states[0]}" = "ok" ] && echo 0 || echo 2)
fi

say "HELIOS — connect everything"
say "surface: $surface   repo: $REPO_ROOT"
[ "$verify_only" -eq 1 ] && say "mode: read-only (nothing is changed)"

# ---------------------------------------------------------------------------
# 0. Persistence (Cloud Shell): the checkout, the CLIs and .helios survive a reset.
# ---------------------------------------------------------------------------
if ! skipped persistence && [ "$surface" = "cloud-shell" ]; then
    step "0. Cloud Shell persistence"
    if [ "$verify_only" -eq 1 ]; then
        bash "$REPO_ROOT/scripts/bootstrap/cloud-shell-setup.sh" --verify-only >/dev/null 2>&1
        rc=$?
    else
        bash "$REPO_ROOT/scripts/bootstrap/cloud-shell-setup.sh" --skip-smoke --skip-auth
        rc=$?
    fi
    case $rc in
        0) record persistence ok "clouddrive persistence and the CLI fleet are in place" ;;
        2) record persistence needs-owner "persistence reported items for you" \
               "bash scripts/bootstrap/cloud-shell-setup.sh" ;;
        *) record persistence failed "cloud-shell-setup.sh exited $rc" ;;
    esac
    say "   exit $rc"
elif [ "$surface" != "cloud-shell" ]; then
    record persistence skipped "not Azure Cloud Shell (surface: $surface)"
fi

skipped github || github_lane

# ---------------------------------------------------------------------------
# 2. GitHub App — one install click buys admin authority for every workflow, for
#    good: governance-run.yml mints a fresh installation token per run, so no
#    personal token is stored and no device code is ever needed again.
# ---------------------------------------------------------------------------
if ! skipped app; then
    step "2. GitHub App (admin authority for the workflows)"
    if [ -z "$pwsh_bin" ]; then
        record app needs-owner "PowerShell 7 is not on this host, so the App flow cannot run" \
            "install PowerShell 7 (https://aka.ms/powershell), then re-run this script"
    else
        run_pwsh scripts/bootstrap/connect-github-app.ps1 -VerifyOnly
        rc=$?
        if [ $rc -eq 0 ]; then
            record app ok "the App is registered and its credentials are stored as repository secrets"
        elif [ "$verify_only" -eq 1 ] || [ "$interactive" -eq 0 ]; then
            record app needs-owner "the App is not registered yet" \
                "pwsh scripts/bootstrap/connect-github-app.ps1   # opens one page; click Create, then Install"
        else
            "$pwsh_bin" -NoProfile -File "$REPO_ROOT/scripts/bootstrap/connect-github-app.ps1" -DispatchGovernance
            rc=$?
            case $rc in
                0) record app ok "the App was registered and installed" ;;
                2) record app needs-owner "the App flow is waiting on the install page" \
                       "pwsh scripts/bootstrap/connect-github-app.ps1   # finish the Install step" ;;
                *) record app failed "connect-github-app.ps1 exited $rc" ;;
            esac
        fi
        say "   exit $rc"
    fi
fi

# ---------------------------------------------------------------------------
# 3. Azure OIDC — the three repository variables that let workflows reach Azure
#    with no stored cloud credential at all.
# ---------------------------------------------------------------------------
if ! skipped oidc; then
    step "3. Azure OIDC variables"
    if ! have az; then
        record oidc needs-owner "the az CLI is not installed on this host" \
            "install the Azure CLI (https://aka.ms/azure-cli), then re-run this script"
    elif ! az account show >/dev/null 2>&1; then
        if [ "$surface" = "cloud-shell" ]; then
            record oidc failed "Cloud Shell should already hold an Azure session but az account show failed"
        else
            record oidc needs-owner "no Azure session on this host" \
                "az login --use-device-code   # or run this script in Azure Cloud Shell, where you are already signed in"
        fi
    elif [ "$verify_only" -eq 1 ]; then
        record oidc ok "an Azure session exists; the variables are applied on a full run"
    else
        oidc_out=$(bash "$REPO_ROOT/scripts/bootstrap/azure-oidc-setup.sh" 2>&1)
        rc=$?
        case $rc in
            0)
                # Exit 0 means the identity and its federated credentials exist. It does NOT mean
                # the repository variables do: azure-oidc-setup.sh PRINTS three `gh variable set`
                # lines and never runs them, so recording "in place" here left helios-deploy.yml
                # unable to authenticate with nothing on the owner's list. Ask GitHub instead.
                oidc_cmds=$(printf '%s\n' "$oidc_out" | sed -n 's/^[[:space:]]*\(gh variable set .*\)$/\1/p')
                oidc_present=0
                if have gh && gh variable list --repo "$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)" \
                        --json name -q '.[].name' 2>/dev/null | grep -qx 'AZURE_CLIENT_ID'; then
                    oidc_present=1
                fi
                if [ "$oidc_present" -eq 1 ]; then
                    record oidc ok "the OIDC identity exists and AZURE_CLIENT_ID is set on the repository"
                elif [ -n "$oidc_cmds" ]; then
                    record oidc needs-owner \
                        "the OIDC identity exists; the three repository variables are printed by that script, not written" \
                        "$(printf '%s' "$oidc_cmds" | paste -sd';' - | sed 's/;/ ; /g')"
                else
                    record oidc needs-owner \
                        "the OIDC identity exists; the three repository variables could not be confirmed" \
                        "bash scripts/bootstrap/azure-oidc-setup.sh   # prints the three gh variable set lines to run"
                fi ;;
            2) record oidc needs-owner "the OIDC lane printed steps for you" \
                   "bash scripts/bootstrap/azure-oidc-setup.sh" ;;
            *) record oidc failed "azure-oidc-setup.sh exited $rc" ;;
        esac
        say "   exit $rc"
    fi
fi

# ---------------------------------------------------------------------------
# 4. Provider keys — masked prompts, straight into Key Vault. Azure OpenAI,
#    Foundry and Claude-on-Foundry need no key at all: they use your Entra
#    sign-in. Skipping a key leaves that lane "unconfigured", which is a valid
#    state, not an error.
# ---------------------------------------------------------------------------
if ! skipped secrets; then
    step "4. Provider keys (optional, masked)"
    if [ -z "${AZURE_KEY_VAULT_URI:-}" ]; then
        record secrets needs-owner "AZURE_KEY_VAULT_URI is not set, so there is no vault to store keys in" \
            "bash scripts/bootstrap/azure-up.sh   # creates the vault and writes .helios/azure.env"
    elif [ "$verify_only" -eq 1 ] || [ "$interactive" -eq 0 ] || [ -z "$pwsh_bin" ]; then
        record secrets needs-owner "keys are entered at a masked prompt, which needs a terminal" \
            "pwsh scripts/bootstrap/set-provider-secrets.ps1 -Apply   # OPENAI_API_KEY, ANTHROPIC_API_KEY, GITHUB_MODELS_TOKEN; skip any you do not want"
    else
        "$pwsh_bin" -NoProfile -File "$REPO_ROOT/scripts/bootstrap/set-provider-secrets.ps1" -Apply
        rc=$?
        case $rc in
            0) record secrets ok "the keys you entered are stored in Key Vault by name" ;;
            2) record secrets needs-owner "some keys were left unset" \
                   "pwsh scripts/bootstrap/set-provider-secrets.ps1 -Apply" ;;
            *) record secrets failed "set-provider-secrets.ps1 exited $rc" ;;
        esac
        say "   exit $rc"
    fi
fi

# ---------------------------------------------------------------------------
# 5. Hub — pull whatever the vault already holds into this process.
# ---------------------------------------------------------------------------
if ! skipped hub; then
    step "5. Hub credentials"
    if [ -z "$pwsh_bin" ]; then
        record hub needs-owner "PowerShell 7 is not on this host" \
            "install PowerShell 7, then re-run this script"
    else
        # auto-login.ps1 delegates to auth-doctor.ps1 -Apply, which may replace the az CLI
        # profile, so a run that promises to change nothing asks auth-doctor directly instead:
        # without -Apply its contract is report-only.
        if [ "$verify_only" -eq 1 ]; then
            hub_script="auth-doctor.ps1"
            hub_json=$(run_pwsh_json scripts/bootstrap/auth-doctor.ps1 -Json)
        else
            hub_script="auto-login.ps1"
            hub_json=$(run_pwsh_json scripts/bootstrap/auto-login.ps1 -Json)
        fi
        rc=$?
        hub_actions=$(printf '%s' "$hub_json" | owner_action_count)
        if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
            record hub failed "$hub_script exited $rc"
        elif [ "$hub_actions" = "?" ]; then
            record hub failed \
                "$hub_script exited $rc but its --json report could not be read, so no provider's credential state is known" \
                "pwsh scripts/bootstrap/auth-doctor.ps1   # read the report directly"
        elif [ "$hub_actions" = "0" ]; then
            record hub ok "every configured provider resolved a credential"
        else
            record hub needs-owner "$hub_actions provider credential(s) still want something from you (a valid state)" \
                "pwsh scripts/bootstrap/auth-doctor.ps1   # names the variable or vault secret each one wants"
        fi
        say "   exit $rc; owner actions: $hub_actions"
    fi
fi

# ---------------------------------------------------------------------------
# 6. ChatGPT / OpenAI — ONE lane over the four surfaces that are easy to confuse:
#
#      cloud   Codex Cloud reviews every pull request (connected at chatgpt.com)
#      cli     the `codex` command, signed in with ChatGPT
#      tools   HELIOS's own tools registered INTO Codex, so ChatGPT drives the hub
#      api     the `openai` / `openai-codex` providers, which need OPENAI_API_KEY
#
# They are genuinely separate: signing the CLI in with ChatGPT does NOT produce an
# API key (the token file's OPENAI_API_KEY stays empty), so `api` can be missing
# while the other three are live. The lane reports all four and asks only for what
# is actually absent.
# ---------------------------------------------------------------------------
CODEX_LOGIN_CMD="codex login --device-auth"
if ! skipped codex; then
    step "6. ChatGPT / OpenAI"
    surfaces=""; codex_pending=""; codex_action=""
    if ! have codex; then
        record codex needs-owner "the codex CLI is not installed on this host" \
            "npm install -g @openai/codex   # then re-run this script"
    else
        # cli
        if codex login status >/dev/null 2>&1; then
            surfaces="cli ok"
        elif [ "$verify_only" -eq 1 ] || [ "$interactive" -eq 0 ]; then
            surfaces="cli signed-out"; codex_pending="the codex CLI is not signed in"; codex_action="$CODEX_LOGIN_CMD"
        else
            say "   codex prints a one-time code and a URL below."; say ""
            if codex login --device-auth; then surfaces="cli ok"
            else surfaces="cli signed-out"; codex_pending="the codex device flow did not complete"; codex_action="$CODEX_LOGIN_CMD"; fi
        fi
        # tools — registered into Codex so ChatGPT can call the hub's 24 governed tools
        if [ "$verify_only" -eq 0 ] && [ -n "$pwsh_bin" ]; then
            run_pwsh scripts/bootstrap/write-codex-config.ps1 -Apply
        fi
        if codex mcp list 2>/dev/null | grep -q '^helios'; then
            surfaces="$surfaces, tools registered"
        else
            surfaces="$surfaces, tools absent"
            [ -n "$codex_pending" ] || {
                codex_pending="HELIOS's tools are not registered in Codex"
                codex_action="pwsh scripts/bootstrap/write-codex-config.ps1 -Apply   # build first: dotnet build HELIOS.sln -c Release"
            }
        fi
        # cloud — the Codex Cloud control panel, listable from here once the CLI is signed in
        if codex cloud list >/dev/null 2>&1; then
            surfaces="$surfaces, cloud reachable"
        else
            surfaces="$surfaces, cloud unverified"
        fi
        # api — a separate credential from the ChatGPT sign-in
        if [ -n "${OPENAI_API_KEY:-}" ]; then
            surfaces="$surfaces, api key set"
        else
            surfaces="$surfaces, api unconfigured"
        fi
        if [ -n "$codex_pending" ]; then
            record codex needs-owner "$codex_pending ($surfaces)" "$codex_action"
        else
            record codex ok "$surfaces"
        fi
        say "   $surfaces"
    fi
fi

# ---------------------------------------------------------------------------
# 7. Foundry — Claude and the Azure OpenAI models over Entra, with no key.
# ---------------------------------------------------------------------------
if ! skipped foundry; then
    step "7. Foundry (Claude and Azure OpenAI over Entra)"
    if [ -z "$pwsh_bin" ]; then
        record foundry needs-owner "PowerShell 7 is not on this host" "install PowerShell 7, then re-run this script"
    elif [ ! -f "$STATE_DIR/azure.env" ]; then
        record foundry needs-owner "the Foundry stack has not been deployed from this checkout" \
            "bash scripts/bootstrap/azure-up.sh   # what-if first; it writes .helios/azure.env"
    else
        run_pwsh scripts/ai-integration/Connect-ClaudeFoundry.ps1 -VerifyOnly
        rc=$?
        case $rc in
            0) record foundry ok "the Foundry resource resolves and the CLAUDE_AZURE_* identifiers are set" ;;
            2) record foundry needs-owner "the Foundry lane printed steps for you" \
                   "pwsh scripts/ai-integration/Connect-ClaudeFoundry.ps1 -VerifyOnly" ;;
            *) record foundry failed "Connect-ClaudeFoundry.ps1 exited $rc" ;;
        esac
        say "   exit $rc"
    fi
fi

# ---------------------------------------------------------------------------
# 8. Linear and Slack — two repository secrets, by NAME, plus one Linear switch.
#    Both workflows skip green without their secret, so nothing here can break a
#    build; this lane only says which of the two are set.
# ---------------------------------------------------------------------------
repo_slug="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null \
    | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##' | head -1)"

if ! skipped connectors; then
    step "8. Linear and Slack"
    if ! have gh || ! env -u GH_TOKEN -u GITHUB_TOKEN timeout 20 gh auth status --hostname github.com >/dev/null 2>&1; then
        record connectors needs-owner "the two connector secrets cannot be listed until gh is signed in" \
            "$GH_LOGIN_CMD"
        say "   gh is not signed in; skipping the secret listing."
    else
        names="$(env -u GH_TOKEN -u GITHUB_TOKEN timeout 30 gh secret list --repo "$repo_slug" --json name -q '.[].name' 2>/dev/null || true)"
        missing=""
        for wanted in LINEAR_API_KEY SLACK_WEBHOOK_URL; do
            printf '%s\n' "$names" | grep -qx "$wanted" || missing="${missing:+$missing }$wanted"
        done
        if [ -z "$missing" ]; then
            record connectors ok "LINEAR_API_KEY and SLACK_WEBHOOK_URL are set; routing lives in config/connectors.json"
            say "   both secrets present."
        else
            record connectors needs-owner "these connector secrets are not set: $missing" \
                "gh secret set ${missing%% *}   # value pasted at the prompt, never stored in the repo. Also: Linear -> Settings -> Integrations -> GitHub -> turn issue sync OFF for team JOH"
            say "   missing: $missing"
        fi
    fi
fi

# ---------------------------------------------------------------------------
# 9. Workspace — what an editor or an assistant picks up when it opens this
#    checkout: the two MCP registrations (the governed helios tools and the
#    Playwright browser server), the Codespaces container, and the themed
#    workspace file. Nothing here needs a credential.
# ---------------------------------------------------------------------------
if ! skipped workspace; then
    step "9. Workspace and MCP servers"
    present=""; absent=""
    for artefact in .mcp.json .vscode/mcp.json workspace.code-workspace .devcontainer/devcontainer.json; do
        if [ -f "$REPO_ROOT/$artefact" ]; then present="${present:+$present }$artefact"; else absent="${absent:+$absent }$artefact"; fi
    done
    mcp_dll="$REPO_ROOT/src/mcp/HELIOS.Mcp/bin/Release/net10.0/HELIOS.Mcp.dll"
    if [ -n "$absent" ]; then
        record workspace failed "missing from this checkout: $absent"
    elif [ -f "$mcp_dll" ]; then
        record workspace ok "helios + playwright MCP servers registered for Claude Code, VS Code / Copilot and Codex; the tool server is built"
    else
        record workspace needs-owner "the MCP tool server is registered but not built, so an assistant starting it waits on a build" \
            "dotnet build HELIOS.sln -c Release   # then any client starts the 24 helios_* tools instantly"
    fi
    say "   $present"
fi

# ---------------------------------------------------------------------------
# 10. GitHub agents — the three that act on this repository. None of them can be
#     switched on from here: Codex is a connection you made at chatgpt.com,
#     Copilot is a subscription, and the Foundry reviewer is owner-dispatched.
# ---------------------------------------------------------------------------
if ! skipped agents; then
    step "10. GitHub agents (Codex, Copilot, Claude on Foundry)"
    wired=""
    [ -f "$REPO_ROOT/.github/workflows/copilot-dispatch.yml" ] && wired="${wired:+$wired, }copilot dispatch by label + review request"
    [ -f "$REPO_ROOT/.github/workflows/claude-foundry.yml" ] && wired="${wired:+$wired, }claude on foundry (owner-dispatched)"
    [ -f "$REPO_ROOT/AGENTS.md" ] && wired="${wired:+$wired, }codex instructions"
    record agents needs-owner "wired: ${wired:-none}. Codex cloud reviews depend on the repo being connected in your ChatGPT settings" \
        "confirm the repository is listed at https://chatgpt.com/codex/cloud/settings/general   # one click, once; Copilot reviews resume when the monthly quota resets"
    say "   $wired"
fi

# ---------------------------------------------------------------------------
# 11. Fleet — Hermes and XCore run locally with no cloud at all. The burst pool
#     costs money, so it is printed, never deployed.
# ---------------------------------------------------------------------------
if ! skipped fleet; then
    step "11. Fleet (Hermes / XCore)"
    if [ -z "$pwsh_bin" ]; then
        record fleet needs-owner "PowerShell 7 is not on this host, so the fleet scripts cannot run" \
            "install PowerShell 7 (https://aka.ms/powershell)"
    else
        run_pwsh scripts/fleet/fleet-status.ps1 -Json
        rc=$?
        if [ $rc -eq 0 ]; then
            record fleet ok "the local fleet is ready: pwsh scripts/fleet/start-fleet.ps1 brings the pools up from config/fleet/fleet-topology.json"
        else
            record fleet needs-owner "the fleet has never been started in this checkout" \
                "pwsh scripts/fleet/start-fleet.ps1        # local pools, no cloud. Burst capacity is a separate, paid deploy you ask for"
        fi
        say "   fleet-status exit $rc"
    fi
fi

# ---------------------------------------------------------------------------
# 12. Microsoft 365 — a tenant administrator decision, not a credential. The
#     connector schema and the declarative agent are ready in integrations/m365.
# ---------------------------------------------------------------------------
if ! skipped m365; then
    step "12. Microsoft 365"
    record m365 needs-owner "the Graph connector and the declarative agent are built; enabling them writes to your tenant, which only you can do" \
        "pwsh scripts/bootstrap/setup-tenant.ps1            # preview first (no -Apply); the runbook is integrations/m365/README.md"
    say "   decision-gated; nothing was contacted."
fi

# ---------------------------------------------------------------------------
# 13. Verify — one read-only pass over every lane.
# ---------------------------------------------------------------------------
if ! skipped verify; then
    step "13. Verify"
    # first-run looks for pwsh on PATH; this checkout may carry its own under
    # .tools/pwsh, and without it every lane it probes reports "could not run".
    verify_path="$PATH"
    case "$pwsh_bin" in */*) verify_path="$(dirname "$pwsh_bin"):$PATH" ;; esac
    # A temporary file, not a record: a read-only run leaves nothing new in the checkout.
    if [ "$verify_only" -eq 1 ]; then
        verify_json="${TMPDIR:-/tmp}/helios-firstrun-$$.json"
    else
        mkdir -p "$STATE_DIR"
        verify_json="$STATE_DIR/connect-firstrun.json"
    fi
    PATH="$verify_path" bash "$REPO_ROOT/scripts/bootstrap/first-run.sh" --verify-only --json >"$verify_json" 2>/dev/null
    rc=$?
    # --json carries the verdict in the document, not in the exit code (it exits 0
    # whether or not lanes are outstanding), so read the lanes rather than $?.
    outstanding=""
    verify_parsed=0
    if have python3; then
        if outstanding="$(python3 - "$verify_json" <<'PYVERIFY' 2>/dev/null
import json, sys
try:
    report = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(1)
lanes = report.get("lanes", {})
print(" ".join(sorted(name for name, lane in lanes.items()
                      if isinstance(lane, dict) and lane.get("state") not in ("ready", "ok"))))
PYVERIFY
)"; then verify_parsed=1; fi
    fi
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
        record verify failed "first-run.sh --verify-only exited $rc"
    elif ! have python3; then
        # Silence is not readiness: without a parser the report cannot be read, and claiming
        # every lane is ready was a verdict nothing had checked.
        record verify needs-owner "the --json report cannot be read on this host (no python3)" \
            "bash scripts/bootstrap/first-run.sh --verify-only   # the full report, one command per lane"
    elif [ "$verify_parsed" -eq 0 ]; then
        record verify failed "first-run.sh exited $rc but its --json report could not be parsed, so no lane state is known" \
            "bash scripts/bootstrap/first-run.sh --verify-only   # read the report directly"
    elif [ -z "$outstanding" ]; then
        record verify ok "first-run reports every lane ready"
    else
        record verify needs-owner "first-run still lists: $outstanding" \
            "bash scripts/bootstrap/first-run.sh --verify-only   # the full report, one command per lane"
    fi
    say "   exit $rc; outstanding: ${outstanding:-none}"
    [ "$verify_only" -eq 1 ] && rm -f "$verify_json"
fi

# ---------------------------------------------------------------------------
# State + the one list
# ---------------------------------------------------------------------------
# A JSON string, escaped the way ConvertTo-Json escapes one in the twin: the backslash and
# quote first, then the control characters, which would otherwise be emitted raw and make the
# file unparseable. No lane detail carries one today; the escaper should not be the reason.
json_string() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' \
        | sed 's/\x08/\\b/g; s/\x0c/\\f/g; s/\r/\\r/g; s/\t/\\t/g' \
        | sed ':a;N;$!ba;s/\n/\\n/g'
}

state_json=$(
    printf '{\n  "surface": %s,\n  "verifyOnly": %s,\n  "lanes": [\n' \
        "\"$surface\"" "$([ "$verify_only" -eq 1 ] && echo true || echo false)"
    for i in "${!lane_names[@]}"; do
        printf '    { "name": "%s", "state": "%s", "detail": "%s", "ownerAction": "%s" }%s\n' \
            "${lane_names[$i]}" "${lane_states[$i]}" \
            "$(json_string "${lane_details[$i]}")" \
            "$(json_string "${lane_actions[$i]}")" \
            "$([ "$i" -lt $((${#lane_names[@]} - 1)) ] && echo ,)"
    done
    printf '  ]\n}'
)

# --status / --verify-only say "nothing is changed", so they must not write this either. The
# report is still printed; only the durable record is a side effect, and a side effect is
# exactly what those flags promise not to have.
if [ "$verify_only" -eq 0 ]; then
    mkdir -p "$STATE_DIR"
    printf '%s\n' "$state_json" > "$STATE_FILE"
fi

failed=0; pending=0
for state in "${lane_states[@]}"; do
    [ "$state" = "failed" ] && failed=1
    [ "$state" = "needs-owner" ] && pending=1
done

if [ "$json_mode" -eq 1 ]; then
    printf '%s\n' "$state_json"
else
    printf '\n== lanes ==\n'
    for i in "${!lane_names[@]}"; do
        printf '  %-12s %-12s %s\n' "${lane_names[$i]}" "${lane_states[$i]}" "${lane_details[$i]}"
    done
    if [ "$pending" -eq 1 ]; then
        printf '\n== what is left for you ==\n'
        n=0
        for i in "${!lane_names[@]}"; do
            if [ "${lane_states[$i]}" = "needs-owner" ] && [ -n "${lane_actions[$i]}" ]; then
                n=$((n + 1))
                printf '  %d. %s\n     %s\n' "$n" "${lane_details[$i]}" "${lane_actions[$i]}"
            fi
        done
        if [ "$verify_only" -eq 0 ]; then
            printf '\n  State saved to .helios/connect-state.json — re-run this script and the list gets shorter.\n'
        else
            printf '\n  Read-only run: nothing was written. Run without --status to save progress.\n'
        fi
    else
        printf '\n  Nothing left for you. Everything this checkout can connect is connected.\n'
    fi
    printf '  One page: docs/CONNECT.md\n'
fi

[ "$failed" -eq 1 ] && exit 1
[ "$pending" -eq 1 ] && exit 2
exit 0
