<#
.SYNOPSIS
One-command login orchestrator: verifies every HELIOS auth lane read-only, then runs
the device-code / no-browser login flow only for the lanes that actually need one.

.DESCRIPTION
The hybrid picture this script serves (companions: connect-github.sh,
connect-azure.sh/.ps1, setup-ai-clis.ps1):

  local workstation — browsers exist, but device-code flows work here too, so every
                      lane uses the same flow everywhere instead of branching.
  Azure Cloud Shell — no local browser: logins must print a URL + one-time code to
                      open on another device. az itself starts pre-authenticated
                      (implicit login), so that lane usually just verifies.
  GitHub Codespaces — same browserless posture as Cloud Shell.
  CI / servers      — NEVER interactive. GitHub Actions federates into Azure via OIDC
                      (scripts/bootstrap/azure-oidc-setup.ps1/.sh), and per the CLI
                      authentication docs the ant CLI's non-interactive story is
                      Workload Identity Federation, not interactive login. This
                      script's login flows are for humans at a prompt; CI supplies
                      credentials through WIF/OIDC or Key Vault-sourced env vars.

Login lanes — one spec-table entry each, with a read-only Verify and an interactive
device-code/no-browser Login. Verify-first: a lane that verifies as authenticated is
never logged in again.

  github        gh auth status --hostname github.com --active (unknown-flag fallback
                for pre-2.40 gh) -> scripts/bootstrap/connect-github.sh (device-code
                web login with the models:read scope). ONE login covers: the gh CLI,
                the standalone copilot CLI (@github/copilot reuses the GitHub login),
                and Copilot sign-in inside VS Code / Visual Studio. The GitHub Models
                provider is covered only when GITHUB_MODELS_TOKEN or GITHUB_TOKEN is
                ALSO set (checked by NAME): the hub reads only those env vars (or Key
                Vault), and neither this script nor a child connect script can export
                a token back into the caller's shell — so gh-authenticated with
                neither env var set reports needs-attention (exit 2) with the export
                hint, never ready. This script never runs `gh auth token` for you.
  azure-entra   az account show -> az login --use-device-code. ONE login covers:
                Azure REST via az, every Azure SDK through AzureCliCredential /
                DefaultAzureCredential, and Azure AI Foundry — the azure-foundry
                provider's AZURE_FOUNDRY_PROJECT_ENDPOINT rides this Entra token.
  anthropic-ant per the CLI authentication docs `ant auth status` prints the selected
                credential source but its exit status must NOT be scripted against —
                Verify greps its stdout instead. Login is `ant auth login
                --no-browser`, which prints the authorize URL and accepts the pasted
                code (the flow for remote/browserless hosts like Cloud Shell).
                ANTHROPIC_API_KEY in the environment short-circuits the lane: per the
                docs it overrides every profile. ant absent = optional-not-installed.
  claude-code   verify-only: ANTHROPIC_API_KEY presence (name only), otherwise a note
                that the claude CLI manages its own cached login. This lane never
                launches an interactive claude session and never gates the exit code.
  openai-codex  codex login status (unknown-command tolerated on old builds) ->
                codex login (ChatGPT-plan browser/device flow). OPENAI_API_KEY
                short-circuits (checked by NAME): the key covers BOTH the codex CLI
                agent and the openai / openai-codex API providers in
                config/aihub.json — but the reverse is NOT true: a codex CLI login
                covers only the CLI, because the hub's ProviderFactory resolves
                those API providers exclusively from OPENAI_API_KEY (or the
                openai-api-key Key Vault secret). So, same honesty rule as the
                github lane: codex-logged-in with no OPENAI_API_KEY reports
                needs-attention (exit 2) with the export/Key Vault hint — the lane
                is ready only when OPENAI_API_KEY is set.
  visual-studio informational row only: Visual Studio and VS Code sign in through
                their own Entra + GitHub dialogs, riding the azure-entra and github
                lanes. Nothing is ever launched.

No secret is ever stored, echoed, or read beyond presence: environment variables are
checked by NAME only and their values never enter a variable. gh/az/ant/codex keep
their tokens in their own keyrings/config, outside this repo.

Exit codes (same contract as setup-ai-clis.ps1): 0 every gating lane is ready;
2 something needs attention (in -VerifyOnly that includes lanes still needing login).
Informational (visual-studio), unverifiable (claude-code without the env key, codex
builds without `login status`) and optional-not-installed (ant absent) lanes are
reported honestly but never gate.

.PARAMETER VerifyOnly
Report each lane's auth state and stop — no login flow is ever started, nothing is
mutated (the repo's verify-only convention — see connect-github.sh --verify-only).

.PARAMETER Skip
Lane names to leave out entirely: github, azure-entra, anthropic-ant, claude-code,
openai-codex, visual-studio. Skipped lanes never count toward the exit code.

.EXAMPLE
pwsh scripts/bootstrap/connect-all.ps1

.EXAMPLE
pwsh scripts/bootstrap/connect-all.ps1 -VerifyOnly

.EXAMPLE
pwsh scripts/bootstrap/connect-all.ps1 -Skip openai-codex,anthropic-ant
#>
#Requires -Version 7
[CmdletBinding()]
param(
    [switch]$VerifyOnly,

    [ValidateSet('github', 'azure-entra', 'anthropic-ant', 'claude-code', 'openai-codex', 'visual-studio')]
    [string[]]$Skip = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

# Same environment probe as setup-ai-clis.ps1: documented env vars, never heuristics.
$inCloudShell = [bool]($env:AZUREPS_HOST_ENVIRONMENT -or $env:ACC_CLOUD -or $env:CLOUD_SHELL)
$environment = if ($inCloudShell) { 'Azure Cloud Shell' }
elseif ($env:CODESPACES) { 'GitHub Codespaces' }
else { 'local shell' }
$mode = if ($VerifyOnly) { 'verify-only' } else { 'connect' }
Write-Host "== HELIOS connect-all ($environment, $mode) =="

function Get-CliCommand {
    param([Parameter(Mandatory)][string]$Name)
    # Application only: a PowerShell alias or function shadowing the name would pass
    # this probe and then fail when the tool is invoked as an OS subprocess (same
    # rationale and shape as setup-ai-clis.ps1).
    Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
}

function Invoke-Probe {
    param(
        [Parameter(Mandatory)][string]$Executable,
        [string[]]$Arguments = @()
    )
    # Capture ALL output first, THEN read $LASTEXITCODE. Piping into anything that can
    # stop the pipeline early (Select-Object -First 1) may halt it before
    # $LASTEXITCODE is assigned — an error under StrictMode (setup-ai-clis.ps1 /
    # verify-readiness.ps1 pattern).
    $lines = @(& $Executable @Arguments 2>&1 | ForEach-Object { "$_" })
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $lines }
}

function New-LaneState {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('ok', 'needs-login', 'blocked', 'unverified', 'optional', 'info')]
        [string]$Kind,
        [Parameter(Mandatory)][string]$Detail
    )
    [pscustomobject]@{ Kind = $Kind; Detail = $Detail }
}

function Invoke-GhAuthStatus {
    # --active restricts the check to the account subsequent gh commands actually use;
    # unscoped `gh auth status` checks EVERY stored account and exits 1 when any of
    # them is stale, so a healthy active account would read as broken. Pre-2.40 gh
    # lacks the flag — fall back to the unscoped form (same probe as
    # connect-github.sh and setup-all.ps1).
    param([Parameter(Mandatory)][string]$GhExe)
    $result = Invoke-Probe -Executable $GhExe -Arguments @('auth', 'status', '--hostname', 'github.com', '--active')
    if ($result.ExitCode -ne 0 -and ((@($result.Output) -join ' ') -match 'unknown flag')) {
        $result = Invoke-Probe -Executable $GhExe -Arguments @('auth', 'status', '--hostname', 'github.com')
    }
    $result
}

# On Windows a bash.exe on PATH is usually WSL's: it cannot resolve Windows repo paths
# handed to .sh scripts, and that failure would mask the native gh fallback below —
# Windows always takes the native login path (same rule as setup-all.ps1).
$bashCommand = if ($IsWindows) { $null } else { Get-CliCommand -Name 'bash' }

# --- Lane spec table ----------------------------------------------------------------
# One [pscustomobject] per login lane. Verify is strictly read-only; Login is the
# interactive device-code/no-browser flow and streams straight to the console so the
# one-time code / URL reaches the human. Interactive=$false lanes never run a Login.
$lanes = @(
    [pscustomobject]@{
        Name        = 'github'
        Interactive = $true
        Covers      = 'gh CLI; GitHub Models provider (GITHUB_MODELS_TOKEN); standalone copilot CLI; Copilot in VS Code / Visual Studio'
        LoginLabel  = 'device-code web login via scripts/bootstrap/connect-github.sh (models:read scope)'
        FixHint     = 'scripts/bootstrap/connect-github.sh   # device-code login + models:read scope; already logged in? export GITHUB_MODELS_TOKEN (see lane detail)'
        Verify      = {
            $gh = Get-CliCommand -Name 'gh'
            if (-not $gh) {
                return New-LaneState -Kind blocked -Detail 'gh (GitHub CLI) is not installed — run scripts/bootstrap/cloud-shell-setup.sh or see https://cli.github.com'
            }
            $status = Invoke-GhAuthStatus -GhExe $gh.Source
            if ($status.ExitCode -eq 0) {
                # gh's keyring login is real, but the hub's GitHub Models provider
                # reads only the GITHUB_MODELS_TOKEN / GITHUB_TOKEN env vars (or Key
                # Vault) — and neither this script nor a child connect script can
                # export a token back into the caller's shell. Presence is checked by
                # NAME only; the value is never read, printed, or exported, and
                # `gh auth token` is never run here — the human runs it.
                if ($env:GITHUB_MODELS_TOKEN -or $env:GITHUB_TOKEN) {
                    New-LaneState -Kind ok -Detail 'gh authenticated against github.com (active account) and GITHUB_MODELS_TOKEN/GITHUB_TOKEN is set (names checked only) — gh CLI, GitHub Models provider, copilot CLI, and Copilot surfaces are covered'
                }
                else {
                    New-LaneState -Kind blocked -Detail ('gh is authenticated, but neither GITHUB_MODELS_TOKEN nor GITHUB_TOKEN is set, and the GitHub Models provider reads only those env vars (or Key Vault) — export one in THIS shell yourself, e.g. pwsh: $env:GITHUB_MODELS_TOKEN = (gh auth token) | bash: export GITHUB_MODELS_TOKEN=$(gh auth token) (a child script cannot export it for you)')
                }
            }
            else {
                New-LaneState -Kind 'needs-login' -Detail 'gh is not authenticated against github.com'
            }
        }
        Login       = {
            $githubConnect = Join-Path $repoRoot 'scripts' 'bootstrap' 'connect-github.sh'
            if ($bashCommand) {
                # connect-github.sh owns the flow: gh auth login --web with the
                # models:read scope (without it the github-models provider 403s), plus
                # the GITHUB_MODELS_TOKEN sourcing tip.
                & $bashCommand.Source ($githubConnect -replace '\\', '/')
            }
            else {
                # Bash-less Windows: the exact login line connect-github.sh runs.
                $gh = Get-CliCommand -Name 'gh'
                & $gh.Source auth login --hostname github.com --git-protocol https --web --scopes 'models:read'
            }
        }
    }
    [pscustomobject]@{
        Name        = 'azure-entra'
        Interactive = $true
        Covers      = 'Azure REST via az; every Azure SDK (AzureCliCredential / DefaultAzureCredential); Azure AI Foundry (AZURE_FOUNDRY_PROJECT_ENDPOINT rides this token)'
        LoginLabel  = 'az login --use-device-code'
        FixHint     = 'az login --use-device-code   # or scripts/bootstrap/connect-azure.sh'
        Verify      = {
            $az = Get-CliCommand -Name 'az'
            if (-not $az) {
                return New-LaneState -Kind blocked -Detail 'az (Azure CLI) is not installed — run scripts/bootstrap/cloud-shell-setup.sh or see https://aka.ms/azure-cli'
            }
            $probe = Invoke-Probe -Executable $az.Source -Arguments @('account', 'show', '--output', 'none')
            if ($probe.ExitCode -eq 0) {
                $suffix = if ($inCloudShell) { ' (Cloud Shell implicit login)' } else { '' }
                New-LaneState -Kind ok -Detail "az authenticated$suffix; the same Entra token backs the SDK credential chain and Azure AI Foundry"
            }
            else {
                $hint = if ($inCloudShell) { ' (Cloud Shell should be pre-authenticated — the shell token may have expired)' } else { '' }
                New-LaneState -Kind 'needs-login' -Detail "az is not authenticated$hint"
            }
        }
        Login       = {
            $az = Get-CliCommand -Name 'az'
            Write-Host '  azure-entra: open the printed URL on any device and enter the one-time code...'
            & $az.Source login --use-device-code --output none
        }
    }
    [pscustomobject]@{
        Name        = 'anthropic-ant'
        Interactive = $true
        Covers      = 'ant CLI profiles under $ANTHROPIC_CONFIG_DIR (anthropic provider rides ANTHROPIC_API_KEY instead when set)'
        LoginLabel  = 'ant auth login --no-browser (authorize URL + pasted code)'
        FixHint     = 'ant auth login --no-browser   # or set ANTHROPIC_API_KEY (Key Vault: anthropic-api-key)'
        Verify      = {
            if ($env:ANTHROPIC_API_KEY) {
                # Presence check by NAME only — the value never enters a variable and
                # is never printed. Per the CLI authentication docs ANTHROPIC_API_KEY
                # overrides every profile, so the lane is configured regardless of
                # any `ant auth` state.
                return New-LaneState -Kind ok -Detail 'ANTHROPIC_API_KEY is set (name checked only) — per the CLI authentication docs it overrides every ant profile'
            }
            $ant = Get-CliCommand -Name 'ant'
            if (-not $ant) {
                return New-LaneState -Kind optional -Detail 'ant CLI not installed (optional) — set ANTHROPIC_API_KEY, or install ant for profile-based auth'
            }
            # Per the CLI authentication docs `ant auth status` prints the selected
            # credential source but its exit status must NOT be scripted against —
            # grep its stdout instead.
            $probe = Invoke-Probe -Executable $ant.Source -Arguments @('auth', 'status')
            $text = $probe.Output -join ' '
            if ($text -match 'Apache Ant|Buildfile') {
                # Name collision: the `ant` on PATH is the Java build tool.
                return New-LaneState -Kind optional -Detail 'the ant on PATH is Apache Ant, not the Anthropic CLI — treated as not installed'
            }
            if ($text -match '(?i)not\s+(logged\s*in|authenticated)|no\s+credential') {
                New-LaneState -Kind 'needs-login' -Detail 'ant auth status reports no active credential'
            }
            elseif ($text -match '(?i)credential|profile|logged\s*in|api\s*key|oauth|workload\s*identity') {
                New-LaneState -Kind ok -Detail 'ant auth status reports an active credential source'
            }
            else {
                New-LaneState -Kind 'needs-login' -Detail 'ant auth status printed no recognizable credential source'
            }
        }
        Login       = {
            $ant = Get-CliCommand -Name 'ant'
            # --no-browser prints the authorize URL and accepts the pasted code — the
            # flow for remote/browserless hosts (Cloud Shell), per the CLI
            # authentication docs; it behaves identically on local machines, so it is
            # the uniform default here. Multi-profile setups can rerun manually with
            # --profile <name> (and --workspace-id <id> to skip the picker).
            & $ant.Source auth login --no-browser
        }
    }
    [pscustomobject]@{
        Name        = 'claude-code'
        Interactive = $false
        Covers      = 'claude cliAgent (`claude -p {prompt}`) and the anthropic provider when ANTHROPIC_API_KEY is set'
        LoginLabel  = ''
        FixHint     = 'set ANTHROPIC_API_KEY (Key Vault: anthropic-api-key), or run `claude` once and let it cache its own login'
        Verify      = {
            if ($env:ANTHROPIC_API_KEY) {
                # Name-only presence check; value never read or echoed.
                return New-LaneState -Kind ok -Detail 'ANTHROPIC_API_KEY is set (name checked only) — claude-code and the anthropic provider are configured'
            }
            # Verify-only lane: probing further would launch an interactive claude
            # session, which this orchestrator never does.
            $claude = Get-CliCommand -Name 'claude'
            if ($claude) {
                New-LaneState -Kind unverified -Detail 'no ANTHROPIC_API_KEY; the claude CLI manages its own cached login (not probed — that would launch an interactive session)'
            }
            else {
                New-LaneState -Kind unverified -Detail 'no ANTHROPIC_API_KEY and no claude binary (pwsh scripts/bootstrap/setup-ai-clis.ps1 installs it; it then manages its own cached login)'
            }
        }
        Login       = $null
    }
    [pscustomobject]@{
        Name        = 'openai-codex'
        Interactive = $true
        Covers      = 'codex CLI agent (codex login or OPENAI_API_KEY); openai / openai-codex API providers (OPENAI_API_KEY or Key Vault openai-api-key ONLY — a codex login does not cover them)'
        LoginLabel  = 'codex login (ChatGPT-plan browser/device flow; covers the CLI only)'
        FixHint     = 'set OPENAI_API_KEY (Key Vault: openai-api-key) for the API providers; codex login   # ChatGPT-plan flow, CLI only'
        Verify      = {
            if ($env:OPENAI_API_KEY) {
                # Name-only presence check; value never read or echoed.
                return New-LaneState -Kind ok -Detail 'OPENAI_API_KEY is set (name checked only) — covers the codex CLI and the openai/openai-codex API providers'
            }
            $codex = Get-CliCommand -Name 'codex'
            if (-not $codex) {
                return New-LaneState -Kind blocked -Detail 'codex CLI not installed — pwsh scripts/bootstrap/setup-ai-clis.ps1 installs @openai/codex'
            }
            $probe = Invoke-Probe -Executable $codex.Source -Arguments @('login', 'status')
            if ($probe.ExitCode -eq 0) {
                # Same honesty rule as the github lane: the codex CLI's keyring login
                # is real, but the hub's ProviderFactory resolves the openai and
                # openai-codex API providers exclusively from OPENAI_API_KEY (or the
                # openai-api-key Key Vault secret) — a CLI login cannot stand in for
                # the key, so reporting ready here would let the script exit 0 while
                # the API providers stay unconfigured. Presence is checked by NAME
                # only; the value is never read, printed, or exported.
                New-LaneState -Kind blocked -Detail ('codex login status: logged in — the codex CLI itself is authenticated — but OPENAI_API_KEY is not set, and the openai/openai-codex API providers read only that env var (or Key Vault) — export OPENAI_API_KEY in THIS shell (pwsh: $env:OPENAI_API_KEY = ''<key>'' | bash: export OPENAI_API_KEY=<key>), or store the key as the openai-api-key Key Vault secret config/aihub.json references')
            }
            elseif (($probe.Output -join ' ') -match '(?i)(unknown|unrecognized|unexpected)\s+(sub)?(command|argument)') {
                # Old builds predate `codex login status`; tolerated — reported, not failed.
                New-LaneState -Kind unverified -Detail 'this codex build has no `login status` subcommand — run `codex login` manually or set OPENAI_API_KEY'
            }
            else {
                New-LaneState -Kind 'needs-login' -Detail 'codex is not logged in'
            }
        }
        Login       = {
            $codex = Get-CliCommand -Name 'codex'
            # ChatGPT-plan sign-in: codex prints a URL (and opens a browser where one
            # exists); on browserless hosts open the URL on any other device.
            & $codex.Source login
        }
    }
    [pscustomobject]@{
        Name        = 'visual-studio'
        Interactive = $false
        Covers      = 'Visual Studio + VS Code account sign-in (their own Entra and GitHub dialogs)'
        LoginLabel  = ''
        FixHint     = ''
        Verify      = {
            # Informational only — there is nothing headless to verify or launch: the
            # IDEs authenticate through their own dialogs, reusing the same Entra
            # identity as azure-entra and the same GitHub account as github.
            New-LaneState -Kind info -Detail 'sign in inside the IDE: File > Account Settings (VS) / Accounts (VS Code) ride the azure-entra and github lanes above'
        }
        Login       = $null
    }
)

# --- Verify, then login only where needed -------------------------------------------
Write-Host ''
Write-Host '-- Login lanes (verify-first; already-authenticated lanes are never re-logged-in) --'
$results = @(foreach ($lane in $lanes) {
    if ($Skip -contains $lane.Name) {
        Write-Host "  $($lane.Name): skipped (-Skip)"
        [pscustomobject]@{ Lane = $lane.Name; Status = 'skipped'; Detail = ''; Covers = $lane.Covers; Fix = '' }
        continue
    }

    $state = & $lane.Verify
    $detail = $state.Detail
    $status = ''
    if ($state.Kind -eq 'ok') { $status = 'ready' }
    elseif ($state.Kind -eq 'info') { $status = 'info' }
    elseif ($state.Kind -eq 'optional') { $status = 'optional' }
    elseif ($state.Kind -eq 'unverified') { $status = 'unverified' }
    elseif ($state.Kind -eq 'blocked') { $status = 'needs-attention' }
    elseif ($VerifyOnly -or -not $lane.Interactive -or -not $lane.Login) { $status = 'needs-login' }
    else {
        Write-Host "  $($lane.Name): $detail"
        Write-Host "  $($lane.Name): starting login — $($lane.LoginLabel)"
        # Login output streams straight to the console: the one-time code / URL must
        # reach the human. The login's exit code is advisory only — the re-verify
        # below is the source of truth (and for ant, per the CLI authentication docs,
        # status exit codes must never be scripted against anyway).
        & $lane.Login
        $state = & $lane.Verify
        if ($state.Kind -eq 'ok') {
            $status = 'logged-in'
            $detail = $state.Detail
        }
        else {
            $status = 'needs-attention'
            $detail = "login did not verify: $($state.Detail)"
        }
    }
    Write-Host "  $($lane.Name): $status — $detail"
    [pscustomobject]@{
        Lane   = $lane.Name
        Status = $status
        Detail = $detail
        Covers = $lane.Covers
        Fix    = if ($status -in 'needs-login', 'needs-attention') { $lane.FixHint } else { '' }
    }
})

# --- Summary table + exit contract (same shape as setup-ai-clis.ps1) -----------------
Write-Host ''
$table = $results |
    Format-Table Lane, Status, @{ n = 'Covers'; e = { $_.Covers } }, Detail, @{ n = 'Next command'; e = { $_.Fix } } -AutoSize |
    Out-String -Width 4096
Write-Host $table.TrimEnd()

Write-Host ''
$checked = @($results | Where-Object { $_.Status -ne 'skipped' })
# Only gate-capable lanes count toward the ratio; info/optional/unverified lanes are
# reported honestly but never fail the run (setup-ai-clis' hermes rule).
$gatingChecked = @($checked | Where-Object { $_.Status -in 'ready', 'logged-in', 'needs-login', 'needs-attention' })
$attention = @($checked | Where-Object { $_.Status -in 'needs-login', 'needs-attention' })
$readyCount = @($gatingChecked | Where-Object { $_.Status -in 'ready', 'logged-in' }).Count
$notes = @($checked | Where-Object { $_.Status -in 'unverified', 'optional', 'info' })
$summary = "Auth lanes: $readyCount/$($gatingChecked.Count) ready"
if ($attention.Count -gt 0) {
    $summary += ' — attention: ' + (@($attention | ForEach-Object Lane) -join ', ')
}
if ($notes.Count -gt 0) {
    $summary += '; informational (never gate): ' + (@($notes | ForEach-Object Lane) -join ', ')
}
if ($Skip.Count -gt 0) { $summary += " (skipped: $($Skip -join ', '))" }
Write-Host $summary

if ($attention.Count -gt 0) { exit 2 }
exit 0
