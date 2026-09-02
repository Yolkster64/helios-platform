<#
.SYNOPSIS
Automatic authentication doctor for the HELIOS auth lanes — gh, az, openai-codex,
claude, copilot — plus the verify-only connector lanes: linear, slack, sharepoint,
azure-devops. Report-first: the default run diagnoses every lane, mutates nothing,
and exits 0. -Apply adds automatic NON-INTERACTIVE repair only; whatever cannot be
automated (MFA, device-code) is reported honestly as an exact owner-action command.

.DESCRIPTION
The automatic-repair sibling of `setup-ai-clis.ps1 -ProbeAuth` (which is read-only and
informational). This script stands alone: it probes each lane, attempts the safe
non-interactive repairs when -Apply is given, and emits one result per lane:

  {lane, state (ready|repaired|needs-owner|unavailable), method, detail,
   ownerAction (exact command when needs-owner)}

Lanes:

  gh            env token first (GH_TOKEN / GITHUB_TOKEN — names checked only, gh
                honors env tokens ahead of its keyring), validated by `gh auth status`
                (exit code only; raw output is never echoed — it can name accounts and
                scopes). In GitHub Actions (GITHUB_ACTIONS=true) the workflow-provided
                GITHUB_TOKEN is the auth and the fix is workflow wiring, not a login.
                Otherwise the device-code web login is the owner action.
  az            `az account show` plus a live token refresh
                (`az account get-access-token --output none`, exit code only): the
                show probe alone stays green in the exact broken state
                docs/architecture/ENTERPRISE_AI_CONNECTIONS.md §0 measured on
                2026-08-13 — profile cached but every ARM/Graph call failing
                AADSTS50078 (MFA expired). Repairs under -Apply: service principal
                from AZURE_CLIENT_ID + AZURE_TENANT_ID + (AZURE_CLIENT_SECRET or
                AZURE_CLIENT_CERTIFICATE_PATH), or managed identity when
                IDENTITY_ENDPOINT / MSI_ENDPOINT is present (or -UseManagedIdentity).
                In Actions with ACTIONS_ID_TOKEN_REQUEST_URL present the azure/login
                step owns the OIDC exchange (ci-oidc) and is never fought. The
                interactive fallback is the tenant-scoped re-login from
                ENTERPRISE_AI_CONNECTIONS.md §1 — reported, never run.
  openai-codex  OPENAI_API_KEY presence (name only — it covers both the codex CLI and
                the openai/openai-codex API providers); when the codex CLI is on PATH,
                `codex login status` is probed non-interactively (a CLI login covers
                the CLI only — connect-all.ps1 honesty rule).
  claude        presence of the env var config/aihub.json declares for the anthropic
                provider (providers.anthropic.apiKeyEnv — read from the config at run
                time, not hardcoded). A cached `claude` login cannot be probed
                headlessly (probing would launch an interactive session), so it is
                never counted.
  copilot       presence probe: standalone copilot CLI (@github/copilot — the shape
                config/aihub.json invokes) or the gh-copilot extension. Its auth rides
                the GitHub login, so the lane defers to the gh lane's result.

Connector lanes (verify-only, NEVER gate the exit code — they diagnose wiring, and
their fixes are repository secrets or tenant consent, not logins this doctor can run):

  linear        LINEAR_API_KEY presence (name only — config/connectors.json
                linear.apiKeyEnv). .github/workflows/linear-sync.yml skips green
                without the repository secret of the same name.
  slack         SLACK_WEBHOOK_URL presence (connectors.json slack.webhookUrlEnv);
                notify-slack.yml skips green without the repository secret. Also
                reports SLACK_BOT_TOKEN honestly: declared in connectors.json
                (botTokenEnv) but nothing in the repo consumes it today.
  sharepoint    no headless probe exists: SharePoint/M365 Graph access is owner-gated
                (admin consent for integrations/m365/, MFA-bound tenant session —
                AADSTS50078 per docs/architecture/ENTERPRISE_AI_CONNECTIONS.md §0).
                Always reported as the exact owner runbook.
  azure-devops  informational: az devops extension + AZURE_DEVOPS_EXT_PAT presence.
                No Azure DevOps org is configured in this repo today — nothing
                consumes either; the lane exists so wiring an org later starts from
                a truthful baseline.

Ordering principle — automatic-first, interactive-last:

  CI OIDC -> env token / service principal -> managed identity -> device-code

WHY this order: the automatic methods are deterministic and safe on a headless host —
they either succeed or fail fast with an error code this script can report, so a
doctor may apply them with nobody watching. Device-code/MFA flows are the opposite:
they block on a human with a second device (AADSTS50078 literally means the MFA
session expired, and only the owner can satisfy MFA again), so interactive login is
always the LAST resort and is only ever REPORTED as an ownerAction command. -Apply
never falls back to anything interactive.

Secrets policy (CLAUDE.md rule): environment variables are checked by NAME only —
values never enter a script variable, are never interpolated into a logged string, and
are never printed. The service-principal repair reads credentials from the environment
into an argument ARRAY handed straight to the az process. Raw output of auth probes is
never echoed.

Exit codes: 0 = report-only run (the default: diagnose everything, mutate nothing), or
an -Apply run where every lane ended ready/repaired (unavailable lanes — the tool
itself is missing — are reported but never gate; installing tools is
setup-ai-clis.ps1's job); 2 = an -Apply run left at least one lane needs-owner;
1 = internal failure.

.PARAMETER Apply
Enable automatic NON-INTERACTIVE repair (currently: the az lane's service-principal
and managed-identity logins). Never starts a device-code, browser, or MFA flow —
those remain owner actions in the report.

.PARAMETER Json
Emit one machine-readable report object instead of the human report (nothing else on
stdout — same convention as setup-all.ps1 -Json / verify-readiness.ps1 -Json).

.PARAMETER UseManagedIdentity
Treat managed identity as available even when no IDENTITY_ENDPOINT / MSI_ENDPOINT is
visible (some hosts, e.g. classic IMDS-only VMs, expose neither variable). Only acts
together with -Apply.

.EXAMPLE
pwsh scripts/bootstrap/auth-doctor.ps1

.EXAMPLE
pwsh scripts/bootstrap/auth-doctor.ps1 -Json | ConvertFrom-Json

.EXAMPLE
pwsh scripts/bootstrap/auth-doctor.ps1 -Apply

.EXAMPLE
pwsh scripts/bootstrap/auth-doctor.ps1 -Apply -UseManagedIdentity
#>
#Requires -Version 7
[CmdletBinding()]
param(
    [switch]$Apply,

    [switch]$Json,

    [switch]$UseManagedIdentity
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

# Same environment probe as setup-ai-clis.ps1 / connect-all.ps1: documented env vars,
# never heuristics. GitHub Actions is detected first because it changes what the
# right fix even is (workflow wiring / azure-login OIDC, never a login flow).
$inActions = $env:GITHUB_ACTIONS -eq 'true'
$inCloudShell = [bool]($env:AZUREPS_HOST_ENVIRONMENT -or $env:ACC_CLOUD -or $env:CLOUD_SHELL)
$environment = if ($inActions) { 'GitHub Actions' }
elseif ($inCloudShell) { 'Azure Cloud Shell' }
elseif ($env:CODESPACES) { 'GitHub Codespaces' }
else { 'local shell' }
$modeLabel = if ($Apply) { 'apply' } else { 'report-only' }

# -Json promises one object and nothing else on stdout, and from an external caller's
# viewpoint Write-Host lands on stdout too — so all progress printing gates on it
# (setup-all.ps1 convention).
function Write-Report {
    param([string]$Message = '')
    if (-not $Json) { Write-Host $Message }
}

function Get-CliCommand {
    param([Parameter(Mandatory)][string]$Name)
    # Application only: these tools are invoked as OS subprocesses, which can never
    # resolve a PowerShell alias or function shadowing the name (setup-ai-clis.ps1
    # rationale).
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
    # connect-all.ps1 pattern). Callers must never print Output raw: auth status text
    # can embed account names, scopes, or worse.
    $lines = @(& $Executable @Arguments 2>&1 | ForEach-Object { "$_" })
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $lines }
}

function Invoke-GhAuthStatus {
    # --active restricts the check to the account subsequent gh commands actually use;
    # pre-2.40 gh lacks the flag — fall back one flag narrower (connect-all.ps1 /
    # connect-github.sh probe).
    param([Parameter(Mandatory)][string]$GhExe)
    $result = Invoke-Probe -Executable $GhExe -Arguments @('auth', 'status', '--hostname', 'github.com', '--active')
    if ($result.ExitCode -ne 0 -and ((@($result.Output) -join ' ') -match 'unknown flag')) {
        $result = Invoke-Probe -Executable $GhExe -Arguments @('auth', 'status', '--hostname', 'github.com')
    }
    $result
}

function New-LaneResult {
    param(
        [Parameter(Mandatory)][string]$Lane,
        [Parameter(Mandatory)]
        [ValidateSet('ready', 'repaired', 'needs-owner', 'unavailable')]
        [string]$State,
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Detail,
        [string]$OwnerAction = '',
        # Connector lanes are verify-only: they report wiring state but never gate the
        # -Apply exit code (their fixes are repo secrets / tenant consent, not logins).
        [bool]$Gates = $true
    )
    [pscustomobject]@{
        lane        = $Lane
        state       = $State
        method      = $Method
        detail      = $Detail
        ownerAction = $OwnerAction
        gates       = $Gates
    }
}

# --- gh lane -------------------------------------------------------------------------
function Test-GhLane {
    $ghCmd = Get-CliCommand -Name 'gh'
    $envTokenName = @(@('GH_TOKEN', 'GITHUB_TOKEN') | Where-Object { Test-Path "env:$_" }) | Select-Object -First 1

    if (-not $ghCmd) {
        $suffix = if ($envTokenName) { (' ({0} is set — name checked only — but there is no gh to drive)' -f $envTokenName) }
        else { '' }
        return New-LaneResult -Lane 'gh' -State 'unavailable' -Method 'none' `
            -Detail ('gh (GitHub CLI) is not on PATH' + $suffix + ' — install via scripts/bootstrap/cloud-shell-setup.sh or https://cli.github.com')
    }

    # Exit code only; the raw status text is never echoed (it names accounts/scopes).
    $status = Invoke-GhAuthStatus -GhExe $ghCmd.Source

    if ($envTokenName) {
        # gh honors env tokens ahead of its keyring, so a set token IS the auth.
        $actionsNote = if ($inActions) { ' — GitHub Actions: the workflow-provided GITHUB_TOKEN is the auth here' } else { '' }
        if ($status.ExitCode -eq 0) {
            return New-LaneResult -Lane 'gh' -State 'ready' -Method 'env-token' `
                -Detail ("$envTokenName is set (name checked only, value never read) and gh auth status accepts it$actionsNote")
        }
        return New-LaneResult -Lane 'gh' -State 'needs-owner' -Method 'env-token' `
            -Detail ("$envTokenName is set (name checked only) but gh auth status exits $($status.ExitCode) — the gh CLI rejects the session, which does NOT prove the token is bad: REST-level " +
                'connectivity can still exist (a proxy-injected session, or a fine-grained/app token the CLI dislikes). Wire-level ground truth: pwsh scripts/verify/rest-connect.ps1' +
                " (raw status output never echoed)$actionsNote") `
            -OwnerAction 'gh auth login --web   # device-code flow; or rotate the env token — but run scripts/verify/rest-connect.ps1 first: if the transport is already authenticated, nothing may be broken'
    }

    if ($status.ExitCode -eq 0) {
        return New-LaneResult -Lane 'gh' -State 'ready' -Method 'stored-login' `
            -Detail 'gh auth status reports an active github.com login from the keyring (raw output never echoed)'
    }

    if ($inActions) {
        # Inside Actions the fix is workflow wiring, never a login flow (gh's own
        # guidance: add GH_TOKEN: ${{ github.token }} to the job env).
        return New-LaneResult -Lane 'gh' -State 'needs-owner' -Method 'ci-env-token' `
            -Detail 'GitHub Actions job with no GH_TOKEN/GITHUB_TOKEN in the env — the workflow-provided GITHUB_TOKEN is the auth; pass it to the job' `
            -OwnerAction 'add to the workflow job:  env: { GH_TOKEN: ${{ github.token }} }'
    }

    return New-LaneResult -Lane 'gh' -State 'needs-owner' -Method 'device-code' `
        -Detail 'no env token and no stored gh login — the device-code web login needs a human with a browser and is never automated' `
        -OwnerAction 'gh auth login --web   # device-code flow; scripts/bootstrap/connect-github.sh adds the models:read scope'
}

# --- az lane -------------------------------------------------------------------------
function Test-AzLane {
    $azCmd = Get-CliCommand -Name 'az'
    if (-not $azCmd) {
        return New-LaneResult -Lane 'az' -State 'unavailable' -Method 'none' `
            -Detail 'az (Azure CLI) is not on PATH — install via scripts/bootstrap/cloud-shell-setup.sh or https://aka.ms/azure-cli'
    }

    # Two-step health probe. `az account show` only reads the cached profile, so it
    # stays green in the exact broken state ENTERPRISE_AI_CONNECTIONS.md §0 measured
    # (2026-08-13): profile cached, every ARM/Graph call failing AADSTS50078 (MFA
    # expired). The follow-up `az account get-access-token --output none` forces a
    # real token refresh — exit code only, nothing on stdout, and the output captured
    # from a failure is only regex-scanned for an AADSTS code, never echoed.
    $show = Invoke-Probe -Executable $azCmd.Source -Arguments @('account', 'show', '--output', 'none')
    $refreshOk = $false
    $aadCode = ''
    if ($show.ExitCode -eq 0) {
        $refresh = Invoke-Probe -Executable $azCmd.Source -Arguments @('account', 'get-access-token', '--output', 'none')
        if ($refresh.ExitCode -eq 0) { $refreshOk = $true }
        elseif ((@($refresh.Output) -join ' ') -match 'AADSTS\d+') { $aadCode = $Matches[0] }
    }

    if ($show.ExitCode -eq 0 -and $refreshOk) {
        $suffix = if ($inCloudShell) { ' (Cloud Shell implicit login)' } else { '' }
        return New-LaneResult -Lane 'az' -State 'ready' -Method 'cached-login' `
            -Detail ("az account show and a live token refresh both succeed$suffix — this Entra token backs az, the SDK credential chain, and Azure AI Foundry")
    }

    # Diagnosis for every branch below.
    $reason = if ($show.ExitCode -ne 0) { 'az has no cached login' }
    elseif ($aadCode -eq 'AADSTS50078') { 'az profile is cached but the token refresh fails AADSTS50078 — MFA expired (the exact state ENTERPRISE_AI_CONNECTIONS.md §0 measured)' }
    elseif ($aadCode) { "az profile is cached but the token refresh fails $aadCode" }
    else { 'az profile is cached but the token refresh fails (no AADSTS code in the error; raw output never echoed)' }

    # Repair ladder, automatic-first / interactive-last — see the WHY block in
    # .DESCRIPTION. Interactive login is never reached by -Apply; it only ever
    # appears as the reported ownerAction at the bottom.

    # Service-principal availability is computed FIRST because the OIDC rung yields
    # to it (review finding): ACTIONS_ID_TOKEN_REQUEST_URL only proves the exchange
    # is POSSIBLE, not that azure/login ran — a job that skipped azure/login but
    # carries AZURE_CLIENT_* workload credentials has a working non-interactive
    # repair that a short-circuit here would throw away (and every downstream Key
    # Vault pull with it).
    # Non-whitespace values required (review finding): Actions expressions routinely
    # materialize optional secrets as EMPTY variables, and an existence-only check
    # would then suppress the correct CI-OIDC branch and run az login with empty
    # arguments. Values are read only for this emptiness test, never logged.
    $spReady = (-not [string]::IsNullOrWhiteSpace([string]$env:AZURE_CLIENT_ID)) -and
        (-not [string]::IsNullOrWhiteSpace([string]$env:AZURE_TENANT_ID)) -and
        ((-not [string]::IsNullOrWhiteSpace([string]$env:AZURE_CLIENT_SECRET)) -or
         (-not [string]::IsNullOrWhiteSpace([string]$env:AZURE_CLIENT_CERTIFICATE_PATH)))

    # 1. CI OIDC: the azure/login action owns the GitHub-OIDC-to-Entra exchange
    #    (federated credentials from scripts/bootstrap/azure-oidc-setup.ps1). Doing a
    #    login here would fight it, so this is report-only by design — reached only
    #    when no service-principal repair is available.
    if ($inActions -and $env:ACTIONS_ID_TOKEN_REQUEST_URL -and -not $spReady) {
        return New-LaneResult -Lane 'az' -State 'needs-owner' -Method 'ci-oidc' `
            -Detail ("$reason; this Actions job can mint an OIDC token (ACTIONS_ID_TOKEN_REQUEST_URL is present) — the azure/login step owns that exchange and this doctor never fights it") `
            -OwnerAction 'add the azure/login step (client-id/tenant-id/subscription-id from the Actions variables scripts/bootstrap/azure-oidc-setup.ps1 prints) before this script runs'
    }

    # 2. Service principal from the environment — fully non-interactive.
    if ($spReady) {
        # Certificate preferred over a shared secret when both are present
        # (non-whitespace, same rule as $spReady above).
        $credEnvName = if (-not [string]::IsNullOrWhiteSpace([string]$env:AZURE_CLIENT_CERTIFICATE_PATH)) { 'AZURE_CLIENT_CERTIFICATE_PATH' } else { 'AZURE_CLIENT_SECRET' }
        if (-not $Apply) {
            return New-LaneResult -Lane 'az' -State 'needs-owner' -Method 'service-principal' `
                -Detail ("$reason; service-principal credentials are in the environment (AZURE_CLIENT_ID + AZURE_TENANT_ID + $credEnvName — names checked only) — automatic non-interactive repair is available") `
                -OwnerAction 'pwsh scripts/bootstrap/auth-doctor.ps1 -Apply'
        }
        Write-Report ("  az: applying az login --service-principal (credentials read from AZURE_CLIENT_ID / AZURE_TENANT_ID / $credEnvName — values never logged)")
        # Argument ARRAY on purpose: each value flows env var -> process argv and
        # never through an interpolated string that could be logged or echoed.
        $spArgs = @(
            'login', '--service-principal',
            '--username', $env:AZURE_CLIENT_ID,
            '--tenant', $env:AZURE_TENANT_ID,
            '--output', 'none'
        )
        if ($credEnvName -eq 'AZURE_CLIENT_CERTIFICATE_PATH') {
            $spArgs += @('--certificate', $env:AZURE_CLIENT_CERTIFICATE_PATH)
        }
        else {
            $spArgs += @('--password', $env:AZURE_CLIENT_SECRET)
        }
        $login = Invoke-Probe -Executable $azCmd.Source -Arguments $spArgs
        $verify = Invoke-Probe -Executable $azCmd.Source -Arguments @('account', 'get-access-token', '--output', 'none')
        if ($login.ExitCode -eq 0 -and $verify.ExitCode -eq 0) {
            return New-LaneResult -Lane 'az' -State 'repaired' -Method 'service-principal' `
                -Detail ("az login --service-principal succeeded and a live token refresh verifies it (credentials taken from AZURE_CLIENT_ID / AZURE_TENANT_ID / $credEnvName by name; values never logged)")
        }
        $spFailText = (@($login.Output) + @($verify.Output)) -join ' '
        $spAad = if ($spFailText -match 'AADSTS\d+') { (' ({0})' -f $Matches[0]) } else { '' }
        $reason += ("; service-principal repair failed$spAad — exit $($login.ExitCode), raw output never echoed")
        # Fall through: the next automatic rung may still work.
    }

    # 3. Managed identity — also fully non-interactive. IDENTITY_ENDPOINT covers App
    #    Service/Functions/Container Apps; MSI_ENDPOINT is the legacy name; classic
    #    IMDS-only VMs expose neither, which is what -UseManagedIdentity is for.
    $miAvailable = $UseManagedIdentity -or (Test-Path env:IDENTITY_ENDPOINT) -or (Test-Path env:MSI_ENDPOINT)
    if ($miAvailable) {
        if (-not $Apply) {
            return New-LaneResult -Lane 'az' -State 'needs-owner' -Method 'managed-identity' `
                -Detail ("$reason; a managed-identity endpoint is present (IDENTITY_ENDPOINT/MSI_ENDPOINT, or -UseManagedIdentity was given) — automatic non-interactive repair is available") `
                -OwnerAction 'pwsh scripts/bootstrap/auth-doctor.ps1 -Apply'
        }
        Write-Report '  az: applying az login --identity (managed identity; system-assigned/default)'
        # System-assigned/default identity only: selecting a user-assigned identity
        # needs its client id under a flag name that varies across az versions, so it
        # is never guessed here.
        $mi = Invoke-Probe -Executable $azCmd.Source -Arguments @('login', '--identity', '--output', 'none')
        $verify = Invoke-Probe -Executable $azCmd.Source -Arguments @('account', 'get-access-token', '--output', 'none')
        if ($mi.ExitCode -eq 0 -and $verify.ExitCode -eq 0) {
            return New-LaneResult -Lane 'az' -State 'repaired' -Method 'managed-identity' `
                -Detail 'az login --identity succeeded and a live token refresh verifies it'
        }
        $reason += ("; managed-identity repair failed (exit $($mi.ExitCode), raw output never echoed)")
    }

    # 3.5 CI OIDC as the pre-interactive fallback (review finding): when the SP
    #    (or MI) repair FAILED but this Actions job can still mint an OIDC token,
    #    the azure/login step remains a working NON-interactive path — device-code
    #    advice would be both wrong and useless in a headless CI job.
    if ($inActions -and $env:ACTIONS_ID_TOKEN_REQUEST_URL) {
        return New-LaneResult -Lane 'az' -State 'needs-owner' -Method 'ci-oidc' `
            -Detail ("$reason; this Actions job can still mint an OIDC token (ACTIONS_ID_TOKEN_REQUEST_URL is present) — the azure/login step owns that exchange and this doctor never fights it") `
            -OwnerAction 'add the azure/login step (client-id/tenant-id/subscription-id from the Actions variables scripts/bootstrap/azure-oidc-setup.ps1 prints) before this script runs'
    }

    # 4. Interactive last — MFA/device-code needs a human and is NEVER run by this
    #    script, -Apply included. Exact command and tenant id from
    #    docs/architecture/ENTERPRISE_AI_CONNECTIONS.md §1 (Azure re-auth).
    $mfaNote = if ($aadCode -eq 'AADSTS50078') { ' Only the owner can satisfy MFA again.' } else { '' }
    return New-LaneResult -Lane 'az' -State 'needs-owner' -Method 'device-code' `
        -Detail ('{0}.{1} Tenant-scoped re-login per ENTERPRISE_AI_CONNECTIONS.md §1; if az ad calls still fail afterwards, rerun it with --scope "https://graph.microsoft.com//.default"' -f $reason, $mfaNote) `
        -OwnerAction 'az login --tenant "349e1399-dccf-45b1-af7e-05d7b0676abf"'
}

# --- openai-codex lane -----------------------------------------------------------------
function Test-CodexLane {
    if (Test-Path env:OPENAI_API_KEY) {
        # Name-only presence check; the value never enters a variable. One key covers
        # both surfaces: the codex CLI agent and the openai/openai-codex API providers
        # (config/aihub.json apiKeyEnv).
        return New-LaneResult -Lane 'openai-codex' -State 'ready' -Method 'env-token' `
            -Detail 'OPENAI_API_KEY is set (name checked only, value never read) — covers the codex CLI and the openai/openai-codex API providers'
    }

    $codexCmd = Get-CliCommand -Name 'codex'
    if ($codexCmd) {
        $probe = Invoke-Probe -Executable $codexCmd.Source -Arguments @('login', 'status')
        $text = @($probe.Output) -join '; '
        if ($text -match '(?i)unrecognized subcommand|unexpected argument|unknown (sub)?command') {
            # Old builds predate `login status` — reported honestly, never guessed.
            return New-LaneResult -Lane 'openai-codex' -State 'needs-owner' -Method 'cli-login' `
                -Detail 'this codex build has no `login status` subcommand, so the lane cannot be verified headlessly' `
                -OwnerAction 'codex login   # browser/device flow (owner action); or export OPENAI_API_KEY'
        }
        if ($probe.ExitCode -eq 0) {
            return New-LaneResult -Lane 'openai-codex' -State 'ready' -Method 'cli-login' `
                -Detail 'codex login status exits 0 — the codex CLI is authenticated; note the openai/openai-codex API providers still read only OPENAI_API_KEY (or the openai-api-key Key Vault secret), a CLI login does not cover them (connect-all.ps1 honesty rule)'
        }
        return New-LaneResult -Lane 'openai-codex' -State 'needs-owner' -Method 'device-code' `
            -Detail ("codex login status exits $($probe.ExitCode) and OPENAI_API_KEY is not set — the ChatGPT-plan login is a browser/device flow only an owner can complete") `
            -OwnerAction 'codex login   # or: source scripts/bootstrap/load-env-from-keyvault.sh (pulls openai-api-key into OPENAI_API_KEY)'
    }

    return New-LaneResult -Lane 'openai-codex' -State 'needs-owner' -Method 'env-token' `
        -Detail 'OPENAI_API_KEY is not set and no codex CLI is on PATH (pwsh scripts/bootstrap/setup-ai-clis.ps1 installs @openai/codex)' `
        -OwnerAction 'source scripts/bootstrap/load-env-from-keyvault.sh   # after az login; pulls openai-api-key into OPENAI_API_KEY'
}

# --- claude lane -----------------------------------------------------------------------
function Test-ClaudeLane {
    # config/aihub.json is the contract for which env var the anthropic provider reads
    # (CLAUDE.md rule: config carries env-var NAMES only) — so the doctor reads the
    # config instead of hardcoding the name, falling back only if it is unreadable.
    $envName = 'ANTHROPIC_API_KEY'
    $vaultSecretName = 'anthropic-api-key'
    $nameSource = 'fallback defaults; config/aihub.json was unreadable'
    try {
        $aihub = Get-Content (Join-Path $repoRoot 'config' 'aihub.json') -Raw | ConvertFrom-Json
        $declaredEnv = [string]$aihub.providers.anthropic.apiKeyEnv
        $declaredVault = [string]$aihub.providers.anthropic.apiKeySecretName
        if ($declaredEnv) {
            $envName = $declaredEnv
            $nameSource = 'config/aihub.json providers.anthropic.apiKeyEnv'
        }
        if ($declaredVault) { $vaultSecretName = $declaredVault }
    }
    catch {
        Write-Verbose "config/aihub.json read failed: $($_.Exception.Message)"
    }

    if (Test-Path "env:$envName") {
        return New-LaneResult -Lane 'claude' -State 'ready' -Method 'env-token' `
            -Detail ("$envName is set (declared by $nameSource; name checked only, value never read) — covers the claude cliAgent and the anthropic provider")
    }

    $claudeCmd = Get-CliCommand -Name 'claude'
    $cliNote = if ($claudeCmd) {
        'a cached claude login cannot be probed headlessly — probing would launch an interactive session (connect-all.ps1 rule)'
    }
    else {
        'no claude CLI on PATH either (pwsh scripts/bootstrap/setup-ai-clis.ps1 installs it)'
    }
    return New-LaneResult -Lane 'claude' -State 'needs-owner' -Method 'env-token' `
        -Detail ("$envName (declared by $nameSource) is not set; $cliNote. Key Vault secret name: $vaultSecretName") `
        -OwnerAction ("claude setup-token   # mint a long-lived token (owner action); or: source scripts/bootstrap/load-env-from-keyvault.sh to pull $vaultSecretName into $envName")
}

# --- copilot lane ----------------------------------------------------------------------
function Test-CopilotLane {
    param([Parameter(Mandatory)][pscustomobject]$GhResult)

    $copilotCmd = Get-CliCommand -Name 'copilot'
    $presence = ''
    if ($copilotCmd) {
        $presence = 'standalone copilot CLI (@github/copilot) is on PATH'
    }
    else {
        $ghCmd = Get-CliCommand -Name 'gh'
        if ($ghCmd) {
            # `gh extension list` reads local state only — no network call.
            $extensions = Invoke-Probe -Executable $ghCmd.Source -Arguments @('extension', 'list')
            if ((@($extensions.Output) -join ' ') -match 'gh-copilot') {
                $presence = 'gh-copilot extension is installed (gh copilot suggest/explain shape)'
            }
        }
    }

    if (-not $presence) {
        return New-LaneResult -Lane 'copilot' -State 'unavailable' -Method 'none' `
            -Detail 'neither the standalone copilot CLI nor the gh-copilot extension is present — pwsh scripts/bootstrap/setup-ai-clis.ps1 installs @github/copilot (the shape config/aihub.json invokes)'
    }

    # copilot reuses the GitHub login (setup-ai-clis.ps1: GH_TOKEN/GITHUB_TOKEN are
    # honored headlessly), so its auth state IS the gh lane's state.
    if ($GhResult.state -in 'ready', 'repaired') {
        return New-LaneResult -Lane 'copilot' -State 'ready' -Method 'github-login' `
            -Detail ("$presence; copilot reuses the GitHub login and the gh lane is $($GhResult.state) ($($GhResult.method))")
    }
    $fix = if ($GhResult.ownerAction) { $GhResult.ownerAction } else { 'gh auth login --web   # device-code flow' }
    return New-LaneResult -Lane 'copilot' -State 'needs-owner' -Method 'github-login' `
        -Detail ("$presence, but copilot reuses the GitHub login and the gh lane is $($GhResult.state) — one GitHub login fixes both lanes") `
        -OwnerAction $fix
}

# --- linear lane (connector; verify-only, never gates) --------------------------------
function Test-LinearLane {
    # config/connectors.json linear.apiKeyEnv declares the name; the sync workflow
    # (.github/workflows/linear-sync.yml) reads the REPOSITORY SECRET of that name and
    # skips green without it — a local env var covers local tooling only, so the
    # detail says which of the two this shell can actually see.
    if (Test-Path env:LINEAR_API_KEY) {
        return New-LaneResult -Lane 'linear' -State 'ready' -Method 'env-token' -Gates $false `
            -Detail 'LINEAR_API_KEY is set in this shell (name checked only, value never read); the linear-sync.yml workflow separately needs the repository secret of the same name — verify per the CONNECTIONS_SETUP.md owner checklist (label an issue bug)'
    }
    return New-LaneResult -Lane 'linear' -State 'needs-owner' -Method 'repo-secret' -Gates $false `
        -Detail 'LINEAR_API_KEY is not set (declared by config/connectors.json linear.apiKeyEnv); .github/workflows/linear-sync.yml skips green without the repository secret, so GitHub->Linear issue sync runs dark' `
        -OwnerAction 'gh secret set LINEAR_API_KEY   # value from Linear Settings -> Security & access -> API'
}

# --- slack lane (connector; verify-only, never gates) ----------------------------------
function Test-SlackLane {
    # SLACK_BOT_TOKEN honesty: connectors.json declares it (slack.botTokenEnv) but no
    # workflow or service in the repo consumes it today — setting it changes nothing
    # yet, and the report must not imply otherwise.
    $botTokenState = if (Test-Path env:SLACK_BOT_TOKEN) { 'set in this shell' } else { 'not set' }
    $botTokenNote = "SLACK_BOT_TOKEN ($botTokenState) is declared in config/connectors.json but nothing in the repo consumes it today"
    if (Test-Path env:SLACK_WEBHOOK_URL) {
        return New-LaneResult -Lane 'slack' -State 'ready' -Method 'env-token' -Gates $false `
            -Detail ("SLACK_WEBHOOK_URL is set in this shell (name checked only, value never read); notify-slack.yml separately needs the repository secret of the same name. $botTokenNote")
    }
    return New-LaneResult -Lane 'slack' -State 'needs-owner' -Method 'repo-secret' -Gates $false `
        -Detail ("SLACK_WEBHOOK_URL is not set (declared by config/connectors.json slack.webhookUrlEnv); .github/workflows/notify-slack.yml skips green without the repository secret, so workflow notifications run dark. $botTokenNote") `
        -OwnerAction 'gh secret set SLACK_WEBHOOK_URL   # value from the Slack app incoming-webhook config'
}

# --- sharepoint lane (connector; verify-only, never gates) -----------------------------
function Test-SharePointLane {
    # No headless probe exists that would not itself require a live Graph token: the
    # Graph connector + declarative agent under integrations/m365/ need tenant admin
    # consent, and the tenant session is MFA-bound (AADSTS50078 — the state
    # docs/architecture/ENTERPRISE_AI_CONNECTIONS.md §0 measured). Owner runbook only.
    return New-LaneResult -Lane 'sharepoint' -State 'needs-owner' -Method 'admin-consent' -Gates $false `
        -Detail 'SharePoint/M365 Graph access is owner-gated: integrations/m365/ (Graph connector + declarative agent) needs tenant admin consent, and the tenant session is MFA-bound (AADSTS50078 per docs/architecture/ENTERPRISE_AI_CONNECTIONS.md §0) — no headless probe exists' `
        -OwnerAction 'az login --tenant "349e1399-dccf-45b1-af7e-05d7b0676abf"   # then follow the integrations/m365/README.md admin-consent runbook'
}

# --- azure-devops lane (connector; verify-only, never gates) ---------------------------
function Test-AzureDevOpsLane {
    # Honest baseline: NO Azure DevOps org is configured in this repo today — nothing
    # consumes the extension or the PAT. The lane reports raw material presence so
    # wiring an org later starts from a truthful state, and it prefers pointing at the
    # repo's existing GitHub-OIDC federation pattern over PAT-based auth.
    $azCmd = Get-CliCommand -Name 'az'
    $extPresent = $false
    if ($azCmd) {
        $ext = Invoke-Probe -Executable $azCmd.Source -Arguments @('extension', 'list', '--output', 'tsv', '--query', '[].name')
        if ($ext.ExitCode -eq 0 -and ((@($ext.Output) -join ' ') -match '\bazure-devops\b')) { $extPresent = $true }
    }
    $extState = if (-not $azCmd) { 'az not on PATH' } elseif ($extPresent) { 'installed' } else { 'not installed' }
    $patState = if (Test-Path env:AZURE_DEVOPS_EXT_PAT) { 'set in this shell (name checked only)' } else { 'not set' }
    $baseline = "no Azure DevOps org is configured in this repo today — nothing consumes either; az devops extension: $extState; AZURE_DEVOPS_EXT_PAT: $patState"

    if ($extPresent -and (Test-Path env:AZURE_DEVOPS_EXT_PAT)) {
        return New-LaneResult -Lane 'azure-devops' -State 'ready' -Method 'env-token' -Gates $false `
            -Detail ("raw material present, but $baseline. Wiring an org is future owner-initiated work; prefer the GitHub-OIDC federation pattern (scripts/bootstrap/azure-oidc-setup.ps1) over PATs where ADO supports it")
    }
    return New-LaneResult -Lane 'azure-devops' -State 'unavailable' -Method 'not-configured' -Gates $false `
        -Detail ($baseline + '. Informational only: wiring an org is future owner-initiated work (az extension add --name azure-devops; prefer OIDC federation over PATs where supported)')
}

# --- Diagnose (and, with -Apply, repair), then report ---------------------------------
try {
    Write-Report "== HELIOS auth doctor ($environment, $modeLabel) =="
    Write-Report ''
    Write-Report '-- Lanes (automatic-first; interactive fixes are reported owner actions, never run) --'

    $ghResult = Test-GhLane
    $laneResults = @(
        $ghResult
        Test-AzLane
        Test-CodexLane
        Test-ClaudeLane
        Test-CopilotLane -GhResult $ghResult
        Test-LinearLane
        Test-SlackLane
        Test-SharePointLane
        Test-AzureDevOpsLane
    )

    foreach ($result in $laneResults) {
        Write-Report ('  {0,-13} {1,-12} {2,-18} {3}' -f $result.lane, $result.state, $result.method, $result.detail)
    }

    $readyCount = @($laneResults | Where-Object { $_.state -eq 'ready' }).Count
    $repairedCount = @($laneResults | Where-Object { $_.state -eq 'repaired' }).Count
    $needsOwner = @($laneResults | Where-Object { $_.state -eq 'needs-owner' })
    $unavailableCount = @($laneResults | Where-Object { $_.state -eq 'unavailable' }).Count

    # Exit contract (see .DESCRIPTION): report-only always exits 0 — it diagnosed and
    # mutated nothing, which is exactly what it promised. Only -Apply gates on the
    # outcome, and only GATING needs-owner lanes gate: unavailable means the TOOL is
    # missing (setup-ai-clis.ps1's job, not an auth failure), and connector lanes
    # (gates=false) are verify-only wiring reports whose fixes are repository secrets
    # or tenant consent — never logins this doctor could have applied.
    $exitCode = 0
    if ($Apply -and @($needsOwner | Where-Object gates).Count -gt 0) { $exitCode = 2 }

    if ($Json) {
        [ordered]@{
            script       = 'scripts/bootstrap/auth-doctor.ps1'
            generatedUtc = (Get-Date).ToUniversalTime().ToString('o')
            mode         = $modeLabel
            environment  = $environment
            lanes        = @($laneResults)
            summary      = [ordered]@{
                ready       = $readyCount
                repaired    = $repairedCount
                needsOwner  = $needsOwner.Count
                unavailable = $unavailableCount
            }
            exitCode     = $exitCode
        } | ConvertTo-Json -Depth 6
    }
    else {
        Write-Report ''
        $table = $laneResults |
            Format-Table -AutoSize -Property @(
                @{ n = 'Lane'; e = { $_.lane } }
                @{ n = 'State'; e = { $_.state } }
                @{ n = 'Method'; e = { $_.method } }
                @{ n = 'Owner action (exact command)'; e = { $_.ownerAction } }
                @{ n = 'Detail'; e = { $_.detail } }
            ) |
            Out-String -Width 4096
        Write-Report $table.TrimEnd()

        Write-Report ''
        $gating = $laneResults.Count - $unavailableCount
        $summary = "Auth lanes: $($readyCount + $repairedCount)/$gating ready or repaired"
        if ($needsOwner.Count -gt 0) {
            $summary += ' — needs-owner: ' + (@($needsOwner | ForEach-Object lane) -join ', ')
        }
        if ($unavailableCount -gt 0) { $summary += "; unavailable (never gates): $unavailableCount" }
        if (-not $Apply) {
            $summary += ' [report-only: nothing was mutated, exit 0 by contract — rerun with -Apply for automatic non-interactive repair]'
        }
        Write-Report $summary
    }

    exit $exitCode
}
catch {
    # Internal failure — distinct from "a lane needs the owner" (2) so callers can
    # tell a broken doctor from a broken login.
    [Console]::Error.WriteLine("auth-doctor: internal failure — $($_.Exception.Message)")
    exit 1
}
