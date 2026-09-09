<#
.SYNOPSIS
    Connect everything, in one sitting, from Windows. The twin of connect.sh.

.DESCRIPTION
    Azure Cloud Shell is the intended home surface (bash scripts/bootstrap/connect.sh
    there); this is the Windows path, and it behaves identically: the same lanes in
    the same order, the same .helios/connect-state.json, the same exit contract.

    It is an ORCHESTRATOR. Every lane calls an existing script by path — no
    credential logic is reimplemented here — and every lane is SOFT: its exit code
    is recorded and the run continues, because a lane that needs you is a checklist
    item, not a failure.

    Lanes
      1  github       gh device login in the foreground, so the code is visible
      2  app          connect-github-app.ps1      (App install = admin, once)
      3  oidc         azure-oidc-setup.ps1        (the three repository variables)
      4  secrets      set-provider-secrets.ps1    (masked prompts, into Key Vault)
      5  hub          auto-login.ps1              (pull what the vault already holds)
      6  codex        codex login + write-codex-config.ps1
      7  foundry      Connect-ClaudeFoundry.ps1   (Entra, no key)
      8  connectors   Linear + Slack secret NAMES, and the Linear sync switch
      9  workspace    editor + agent surfaces: MCP servers, devcontainer, workspace
     10  agents       the GitHub agents: Codex cloud, Copilot, Claude on Foundry
     11  fleet        Hermes / XCore locally; the burst pool waits for your word
     12  m365         Microsoft 365 — tenant consent, a decision and not a key
     13  verify       first-run.ps1 -VerifyOnly, read as a report

    Lanes 8-12 are report-only: they never write, they say what is wired and what
    is one click of yours away.

    Secrets: every credential is referenced by the NAME of its environment variable
    or Key Vault secret. No value is printed, logged or stored here.

.PARAMETER Status
    Read-only lane table; runs nothing that changes anything (same as -VerifyOnly).

.PARAMETER VerifyOnly
    Every lane in its verify mode: no login, no write.

.PARAMETER GitHubCode
    Only the GitHub sign-in, in the foreground, then stop.

.PARAMETER Json
    One JSON object on stdout (implies non-interactive).

.PARAMETER Skip
    Lane names to skip: persistence github app oidc secrets hub codex foundry
    connectors workspace agents fleet m365 verify.

.NOTES
    HELIOS_PWSH names the interpreter the .ps1 lanes are run with, for a host that keeps
    PowerShell somewhere the two guesses (.tools/pwsh/pwsh in this checkout, then the
    interpreter running this script) will not find.

.EXAMPLE
    pwsh scripts/bootstrap/connect.ps1
.EXAMPLE
    pwsh scripts/bootstrap/connect.ps1 -Status
#>
[CmdletBinding()]
param(
    [switch]$Status,
    [switch]$VerifyOnly,
    [switch]$GitHubCode,
    [switch]$Json,
    [string[]]$Skip = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$stateDir = Join-Path $repoRoot '.helios'
$stateFile = Join-Path $stateDir 'connect-state.json'
$readOnly = $Status.IsPresent -or $VerifyOnly.IsPresent
$interactive = -not ($Json.IsPresent) -and [Environment]::UserInteractive
$lanes = [System.Collections.Generic.List[object]]::new()

$surface = 'local'
if ($env:AZUREPS_HOST_ENVIRONMENT -or $env:ACC_CLOUD) { $surface = 'cloud-shell' }
elseif ($env:CODESPACES) { $surface = 'codespaces' }

function Write-Line { param([string]$Text = '') if (-not $Json) { Write-Host $Text } }
function Write-Step { param([string]$Text) if (-not $Json) { Write-Host ''; Write-Host "-- $Text --" } }
function Test-Skipped { param([string]$Name) return $Skip -contains $Name }

function Add-Lane {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('ok', 'needs-owner', 'skipped', 'failed')][string]$State,
        [Parameter(Mandatory)][string]$Detail,
        [string]$OwnerAction = ''
    )
    $lanes.Add([pscustomobject]@{ name = $Name; state = $State; detail = $Detail; ownerAction = $OwnerAction })
}

function Test-Application {
    # Application only: an alias or function of the same name would pass a bare
    # Get-Command and then fail as an OS subprocess.
    param([Parameter(Mandatory)][string]$Name)
    return $null -ne (Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue)
}

function Get-OptionalProperty {
    # A property of a parsed report, or $Default when the report does not carry it. Same
    # helper, same name, as scripts/verify/rest-connect.ps1 and the scripts/github/ family.
    # It is not a convenience: under Set-StrictMode -Version Latest a plain $report.thing
    # THROWS when `thing` is absent, so a guard written as `if ($null -ne $report.thing)`
    # terminates the orchestrator on the very report it meant to tolerate.
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -ne $prop -and $null -ne $prop.Value) { return $prop.Value }
    return $Default
}

function Resolve-Pwsh {
    # The interpreter the .ps1 lanes are run with. A bare `pwsh` is a PATH lookup, which can
    # find a DIFFERENT PowerShell than the one running this script - so the interpreter this
    # script is already running under is preferred over the search. HELIOS_PWSH is the explicit
    # override, for a host that keeps PowerShell somewhere the guesses will not find, and it is
    # what the offline suite points at a shim so these contracts can be tested without a network.
    # Every candidate is checked before it is taken, including the override: a HELIOS_PWSH
    # naming something that is not there would otherwise end the run at the first lane.
    $exe = if ($IsWindows) { '.exe' } else { '' }
    # The current process only counts if it IS a pwsh: this script can be dot-sourced into a
    # host that embeds PowerShell, whose executable would run no .ps1 at all.
    $current = [Environment]::ProcessPath
    if ($current -and (Split-Path $current -Leaf) -notin @("pwsh$exe", 'pwsh')) { $current = $null }
    foreach ($candidate in @($env:HELIOS_PWSH, (Join-Path $repoRoot ".tools/pwsh/pwsh$exe"), $current)) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }
    return 'pwsh'
}
$pwshBin = Resolve-Pwsh

function Get-LaneReport {
    # Runs a repo script that speaks -Json and returns @{ Code; Outstanding } where Outstanding
    # is how much the report still wants from the owner, or $null when it cannot be read.
    # An exit code is not the verdict: auto-login.ps1 exits 0 whether or not providers are
    # unconfigured and reserves non-zero for internal failure. The two scripts also report
    # differently - auto-login carries ownerActions[], auth-doctor carries lanes[] with a state.
    param([Parameter(Mandatory)][string]$RelativePath, [string[]]$Arguments = @())
    $full = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $full)) { return @{ Code = 127; Outstanding = $null } }
    $raw = & $pwshBin -NoProfile -File $full @Arguments 2>$null
    $code = $LASTEXITCODE
    try { $report = ($raw | Out-String) | ConvertFrom-Json -ErrorAction Stop }
    catch { return @{ Code = $code; Outstanding = $null } }
    $actions = Get-OptionalProperty $report 'ownerActions'
    if ($null -ne $actions) { return @{ Code = $code; Outstanding = @($actions).Count } }
    $reported = Get-OptionalProperty $report 'lanes'
    if ($null -ne $reported) {
        $laneList = if ($reported -is [System.Collections.IEnumerable] -and $reported -isnot [string]) {
            @($reported)
        } else { @($reported.PSObject.Properties.Value) }
        # A lane with no state of its own is not a resolved lane: it is counted as outstanding
        # rather than read as one, so an unexpected report shape cannot report everything ready.
        return @{ Code = $code
                  Outstanding = @($laneList | Where-Object { (Get-OptionalProperty $_ 'state') -notin @('ready', 'ok') }).Count }
    }
    return @{ Code = $code; Outstanding = $null }
}

function Invoke-Lane {
    # Runs a repo script by path and returns its exit code; output is discarded so
    # a lane cannot leak a value into the transcript.
    param([Parameter(Mandatory)][string]$RelativePath, [string[]]$Arguments = @())
    $full = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $full)) { return 127 }
    & $pwshBin -NoProfile -File $full @Arguments *> $null
    return $LASTEXITCODE
}

$ghScopes = 'repo,workflow,project,read:org,models:read'
$ghLoginCommand = "gh auth login --hostname github.com --git-protocol https --web --scopes $ghScopes"

function Invoke-GitHubLane {
    Write-Step '1. GitHub sign-in'
    if (-not (Test-Application 'gh')) {
        Add-Lane github 'needs-owner' 'the gh CLI is not installed on this host' `
            'winget install --id GitHub.cli   # or https://cli.github.com'
        Write-Line '   gh is not installed.'
        return
    }
    & gh auth status --hostname github.com *> $null
    if ($LASTEXITCODE -eq 0) {
        Add-Lane github 'ok' 'gh is signed in on this host'
        Write-Line '   already signed in.'
        return
    }
    if ($readOnly -or -not $interactive) {
        Add-Lane github 'needs-owner' 'gh is not signed in; the device flow needs a terminal' $ghLoginCommand
        Write-Line "   not signed in. Run this where you can read the code it prints:"
        Write-Line "     $ghLoginCommand"
        return
    }
    Write-Line '   gh prints a one-time code and a URL below. Open the URL on any device,'
    Write-Line '   type the code, and this waits for you.'
    Write-Line ''
    & gh auth login --hostname github.com --git-protocol https --web --scopes $ghScopes
    if ($LASTEXITCODE -eq 0) { Add-Lane github 'ok' 'signed in through the device flow' }
    else { Add-Lane github 'needs-owner' 'the device flow did not complete' $ghLoginCommand }
}

if ($GitHubCode) {
    Invoke-GitHubLane
    exit ($(if ($lanes[0].state -eq 'ok') { 0 } else { 2 }))
}

Write-Line 'HELIOS — connect everything'
Write-Line "surface: $surface   repo: $repoRoot"
if ($readOnly) { Write-Line 'mode: read-only (nothing is changed)' }

# The same three cases as the bash twin, in the same order: acted on in Cloud Shell,
# reported as skipped everywhere else, and absent when you asked to skip it. Cloud Shell
# persistence is clouddrive plumbing that cloud-shell-setup.sh owns and this twin does not
# reimplement - but the lane is still REPORTED there, because two twins that describe
# different lanes are two different products.
if (-not (Test-Skipped 'persistence') -and $surface -eq 'cloud-shell') {
    Add-Lane persistence 'needs-owner' 'Cloud Shell persistence is set up by the bash twin' `
        'bash scripts/bootstrap/connect.sh   # in Cloud Shell, where clouddrive persistence lives'
}
elseif ($surface -ne 'cloud-shell') {
    Add-Lane persistence 'skipped' "not Azure Cloud Shell (surface: $surface)"
}

if (-not (Test-Skipped 'github')) { Invoke-GitHubLane }

# 2. GitHub App — one install click buys admin authority for every workflow run.
if (-not (Test-Skipped 'app')) {
    Write-Step '2. GitHub App (admin authority for the workflows)'
    $code = Invoke-Lane 'scripts/bootstrap/connect-github-app.ps1' @('-VerifyOnly')
    switch ($code) {
        0 { Add-Lane app 'ok' 'the App is registered and installed; workflows mint their own token per run' }
        2 { Add-Lane app 'needs-owner' 'the App is not registered yet' `
                'pwsh scripts/bootstrap/connect-github-app.ps1   # opens one page; click Create, then Install' }
        default { Add-Lane app 'failed' "connect-github-app.ps1 exited $code" }
    }
    Write-Line "   exit $code"
}

# 3. Azure OIDC — the three repository variables, no stored cloud password.
if (-not (Test-Skipped 'oidc')) {
    Write-Step '3. Azure OIDC (workflows reach Azure with no stored secret)'
    if (-not (Test-Application 'az')) {
        Add-Lane oidc 'needs-owner' 'the az CLI is not installed on this host' `
            'winget install --id Microsoft.AzureCLI   # or https://aka.ms/azure-cli'
    }
    else {
        & az account show *> $null
        if ($LASTEXITCODE -ne 0) {
            Add-Lane oidc 'needs-owner' 'no Azure session on this host' `
                'az login --use-device-code   # or run this from Azure Cloud Shell, where you are already signed in'
        }
        elseif ($readOnly) {
            Add-Lane oidc 'ok' 'an Azure session exists; the variables are applied on a full run'
        }
        else {
            # azure-oidc-setup.ps1 has no read-only mode: it is idempotent and only runs here.
            $code = Invoke-Lane 'scripts/bootstrap/azure-oidc-setup.ps1'
            switch ($code) {
                0 {
                    # Exit 0 means the identity and its federated credentials exist. It does NOT
                    # mean the repository variables do: azure-oidc-setup PRINTS three
                    # `gh variable set` lines and never runs them, so recording "in place" left
                    # helios-deploy.yml unable to authenticate with nothing on the owner's list.
                    $oidcSet = $false
                    if (Test-Application 'gh') {
                        $slugForVars = (& gh repo view --json nameWithOwner -q .nameWithOwner 2>$null)
                        if ($LASTEXITCODE -eq 0 -and $slugForVars) {
                            $varNames = @(& gh variable list --repo $slugForVars --json name -q '.[].name' 2>$null)
                            $oidcSet = ($LASTEXITCODE -eq 0) -and ($varNames -contains 'AZURE_CLIENT_ID')
                        }
                    }
                    if ($oidcSet) {
                        Add-Lane oidc 'ok' 'the OIDC identity exists and AZURE_CLIENT_ID is set on the repository'
                    }
                    else {
                        Add-Lane oidc 'needs-owner' `
                            'the OIDC identity exists; the three repository variables are printed by that script, not written' `
                            'pwsh scripts/bootstrap/azure-oidc-setup.ps1   # prints the three gh variable set lines to run'
                    }
                }
                2 { Add-Lane oidc 'needs-owner' 'the OIDC lane printed steps for you' `
                        'pwsh scripts/bootstrap/azure-oidc-setup.ps1' }
                default { Add-Lane oidc 'failed' "azure-oidc-setup.ps1 exited $code" }
            }
            Write-Line "   exit $code"
        }
    }
}

# 4. Provider keys — masked prompts straight into Key Vault. Skipping a key leaves
#    that provider unconfigured, which is a valid state, not an error.
if (-not (Test-Skipped 'secrets')) {
    Write-Step '4. Provider keys (into Key Vault, never a file)'
    if (-not $env:AZURE_KEY_VAULT_URI) {
        Add-Lane secrets 'needs-owner' 'AZURE_KEY_VAULT_URI is not set, so there is no vault to store keys in' `
            'pwsh scripts/bootstrap/azure-up.ps1   # creates the vault and writes .helios/azure.env'
    }
    elseif ($readOnly -or -not $interactive) {
        Add-Lane secrets 'needs-owner' 'provider keys are entered at a hidden prompt, which needs a terminal' `
            'pwsh scripts/bootstrap/set-provider-secrets.ps1 -Apply   # OPENAI_API_KEY, ANTHROPIC_API_KEY, GITHUB_MODELS_TOKEN; skip any you do not want'
    }
    else {
        # -Apply is what writes; the prompt is masked and the value never reaches a file.
        & $pwshBin -NoProfile -File (Join-Path $repoRoot 'scripts/bootstrap/set-provider-secrets.ps1') -Apply
        $code = $LASTEXITCODE
        switch ($code) {
            0 { Add-Lane secrets 'ok' 'the keys you entered are stored in Key Vault by name' }
            2 { Add-Lane secrets 'needs-owner' 'some keys were left unset' `
                    'pwsh scripts/bootstrap/set-provider-secrets.ps1 -Apply' }
            default { Add-Lane secrets 'failed' "set-provider-secrets.ps1 exited $code" }
        }
        Write-Line "   exit $code"
    }
}

# 5. Hub — pull whatever the vault already holds into this process.
if (-not (Test-Skipped 'hub')) {
    Write-Step '5. Hub (providers resolve their credentials)'
    # auto-login.ps1 delegates to auth-doctor.ps1 -Apply, which may replace the az CLI profile,
    # so a run that promises to change nothing asks auth-doctor directly instead: without -Apply
    # its contract is report-only.
    $hubScript = if ($readOnly) { 'auth-doctor.ps1' } else { 'auto-login.ps1' }
    $hub = Get-LaneReport "scripts/bootstrap/$hubScript" @('-Json')
    $code = $hub.Code
    if ($code -ne 0 -and $code -ne 2) {
        Add-Lane hub 'failed' "$hubScript exited $code"
    }
    elseif ($null -eq $hub.Outstanding) {
        Add-Lane hub 'failed' `
            "$hubScript exited $code but its -Json report could not be read, so no provider's credential state is known" `
            'pwsh scripts/bootstrap/auth-doctor.ps1   # read the report directly'
    }
    elseif ($hub.Outstanding -eq 0) {
        Add-Lane hub 'ok' 'every configured provider resolved a credential'
    }
    else {
        Add-Lane hub 'needs-owner' `
            "$($hub.Outstanding) provider credential(s) still want something from you (a valid state)" `
            'pwsh scripts/bootstrap/auth-doctor.ps1   # names the environment variable or vault secret each lane wants'
    }
    Write-Line "   exit $code; outstanding: $($hub.Outstanding)"
}

# 6. ChatGPT / OpenAI — one lane over four surfaces that are easy to confuse:
#    the cloud reviewer, the CLI, the HELIOS tools registered INTO Codex, and the
#    API providers, which need OPENAI_API_KEY and are NOT covered by a CLI login.
if (-not (Test-Skipped 'codex')) {
    Write-Step '6. ChatGPT / Codex (cloud, CLI, tools, API)'
    # Four surfaces that are easy to confuse, reported as one lane: the cloud
    # reviewer, the CLI, HELIOS's tools registered INTO Codex, and the API
    # providers. A ChatGPT sign-in does NOT produce an API key, so `api` can be
    # missing while the other three are live.
    if (-not (Test-Application 'codex')) {
        Add-Lane codex 'needs-owner' 'the codex CLI is not installed on this host' `
            'npm install -g @openai/codex   # then re-run this script'
    }
    else {
        $parts = @(); $pendingDetail = ''; $pendingAction = ''
        & codex login status *> $null
        if ($LASTEXITCODE -eq 0) { $parts += 'cli ok' }
        elseif ($readOnly -or -not $interactive) {
            $parts += 'cli signed-out'; $pendingDetail = 'the codex CLI is not signed in'; $pendingAction = 'codex login --device-auth'
        }
        else {
            Write-Line '   codex prints a one-time code and a URL below.'
            Write-Line ''
            & codex login --device-auth
            if ($LASTEXITCODE -eq 0) { $parts += 'cli ok' }
            else { $parts += 'cli signed-out'; $pendingDetail = 'the codex device flow did not complete'; $pendingAction = 'codex login --device-auth' }
        }
        if (-not $readOnly) { Invoke-Lane 'scripts/bootstrap/write-codex-config.ps1' @('-Apply') | Out-Null }
        $registered = (& codex mcp list 2>$null) -match '^helios'
        if ($registered) { $parts += 'tools registered' }
        else {
            $parts += 'tools absent'
            if (-not $pendingDetail) {
                $pendingDetail = "HELIOS's tools are not registered in Codex"
                $pendingAction = 'pwsh scripts/bootstrap/write-codex-config.ps1 -Apply   # build first: dotnet build HELIOS.sln -c Release'
            }
        }
        & codex cloud list *> $null
        $parts += $(if ($LASTEXITCODE -eq 0) { 'cloud reachable' } else { 'cloud unverified' })
        $parts += $(if ($env:OPENAI_API_KEY) { 'api key set' } else { 'api unconfigured' })
        $detail = $parts -join ', '
        if ($pendingDetail) { Add-Lane codex 'needs-owner' "$pendingDetail ($detail)" $pendingAction }
        else { Add-Lane codex 'ok' $detail }
        Write-Line "   $detail"
    }
}

# 7. Foundry — Claude and the Azure OpenAI models over Entra, with no key.
if (-not (Test-Skipped 'foundry')) {
    Write-Step '7. Foundry (Claude and Azure OpenAI over Entra)'
    if (-not (Test-Path -LiteralPath (Join-Path $stateDir 'azure.env'))) {
        Add-Lane foundry 'needs-owner' 'the Foundry stack has not been deployed from this checkout' `
            'pwsh scripts/bootstrap/azure-up.ps1   # what-if first; it writes .helios/azure.env'
    }
    else {
        $code = Invoke-Lane 'scripts/ai-integration/Connect-ClaudeFoundry.ps1' @('-VerifyOnly')
        switch ($code) {
            0 { Add-Lane foundry 'ok' 'the Foundry resource resolves and the CLAUDE_AZURE_* identifiers are set' }
            2 { Add-Lane foundry 'needs-owner' 'the Foundry lane printed steps for you' `
                    'pwsh scripts/ai-integration/Connect-ClaudeFoundry.ps1 -VerifyOnly' }
            default { Add-Lane foundry 'failed' "Connect-ClaudeFoundry.ps1 exited $code" }
        }
        Write-Line "   exit $code"
    }
}

# 8. Linear and Slack — two repository secrets, by NAME. Both workflows skip green
#    without their secret, so nothing here can break a build.
if (-not (Test-Skipped 'connectors')) {
    Write-Step '8. Linear and Slack'
    $slug = ''
    if (Test-Application 'git') {
        $origin = (& git -C $repoRoot remote get-url origin 2>$null)
        if ($LASTEXITCODE -eq 0 -and $origin) {
            $slug = ($origin -replace '^(git@github\.com:|https://github\.com/)', '') -replace '\.git$', ''
        }
    }
    # Test-Application FIRST: with ErrorActionPreference = 'Stop' a missing gh turns
    # command-not-found into a terminating error that ends the whole orchestrator, instead of
    # this lane recording needs-owner and the run continuing as promised.
    $ghReady = $false
    if (Test-Application 'gh') {
        & gh auth status --hostname github.com *> $null
        $ghReady = $LASTEXITCODE -eq 0
    }
    if (-not $ghReady) {
        Add-Lane connectors 'needs-owner' 'the two connector secrets cannot be listed until gh is signed in' $ghLoginCommand
        Write-Line '   gh is not signed in; skipping the secret listing.'
    }
    else {
        $names = @(& gh secret list --repo $slug --json name -q '.[].name' 2>$null)
        $missing = @('LINEAR_API_KEY', 'SLACK_WEBHOOK_URL') | Where-Object { $names -notcontains $_ }
        if ($missing.Count -eq 0) {
            Add-Lane connectors 'ok' 'LINEAR_API_KEY and SLACK_WEBHOOK_URL are set; routing lives in config/connectors.json'
            Write-Line '   both secrets present.'
        }
        else {
            Add-Lane connectors 'needs-owner' "these connector secrets are not set: $($missing -join ' ')" `
                "gh secret set $($missing[0])   # value pasted at the prompt, never stored in the repo. Also: Linear -> Settings -> Integrations -> GitHub -> turn issue sync OFF for team JOH"
            Write-Line "   missing: $($missing -join ' ')"
        }
    }
}

# 9. Workspace — what an editor or an assistant picks up when it opens this checkout.
if (-not (Test-Skipped 'workspace')) {
    Write-Step '9. Workspace and MCP servers'
    $expected = @('.mcp.json', '.vscode/mcp.json', 'workspace.code-workspace', '.devcontainer/devcontainer.json')
    $absent = $expected | Where-Object { -not (Test-Path -LiteralPath (Join-Path $repoRoot $_)) }
    $toolServer = Join-Path $repoRoot 'src/mcp/HELIOS.Mcp/bin/Release/net10.0/HELIOS.Mcp.dll'
    if ($absent) { Add-Lane workspace 'failed' "missing from this checkout: $($absent -join ' ')" }
    elseif (Test-Path -LiteralPath $toolServer) {
        Add-Lane workspace 'ok' 'helios + playwright MCP servers registered for Claude Code, VS Code / Copilot and Codex; the tool server is built'
    }
    else {
        Add-Lane workspace 'needs-owner' 'the MCP tool server is registered but not built, so an assistant starting it waits on a build' `
            'dotnet build HELIOS.sln -c Release   # then any client starts the 24 helios_* tools instantly'
    }
    Write-Line "   $($expected -join ' ')"
}

# 10. GitHub agents — none of the three can be switched on from here.
if (-not (Test-Skipped 'agents')) {
    Write-Step '10. GitHub agents (Codex, Copilot, Claude on Foundry)'
    $wired = @()
    if (Test-Path -LiteralPath (Join-Path $repoRoot '.github/workflows/copilot-dispatch.yml')) { $wired += 'copilot dispatch by label + review request' }
    if (Test-Path -LiteralPath (Join-Path $repoRoot '.github/workflows/claude-foundry.yml')) { $wired += 'claude on foundry (owner-dispatched)' }
    if (Test-Path -LiteralPath (Join-Path $repoRoot 'AGENTS.md')) { $wired += 'codex instructions' }
    $detail = if ($wired) { $wired -join ', ' } else { 'none' }
    Add-Lane agents 'needs-owner' "wired: $detail. Codex cloud reviews depend on the repo being connected in your ChatGPT settings" `
        'confirm the repository is listed at https://chatgpt.com/codex/cloud/settings/general   # one click, once; Copilot reviews resume when the monthly quota resets'
    Write-Line "   $detail"
}

# 11. Fleet — Hermes and XCore run locally with no cloud at all.
if (-not (Test-Skipped 'fleet')) {
    Write-Step '11. Fleet (Hermes / XCore)'
    $code = Invoke-Lane 'scripts/fleet/fleet-status.ps1' @('-Json')
    if ($code -eq 0) {
        Add-Lane fleet 'ok' 'the local fleet is ready: pwsh scripts/fleet/start-fleet.ps1 brings the pools up from config/fleet/fleet-topology.json'
    }
    else {
        Add-Lane fleet 'needs-owner' 'the fleet has never been started in this checkout' `
            'pwsh scripts/fleet/start-fleet.ps1        # local pools, no cloud. Burst capacity is a separate, paid deploy you ask for'
    }
    Write-Line "   fleet-status exit $code"
}

# 12. Microsoft 365 — a tenant administrator decision, not a credential.
if (-not (Test-Skipped 'm365')) {
    Write-Step '12. Microsoft 365'
    Add-Lane m365 'needs-owner' 'the Graph connector and the declarative agent are built; enabling them writes to your tenant, which only you can do' `
        'pwsh scripts/bootstrap/setup-tenant.ps1            # preview first (no -Apply); the runbook is integrations/m365/README.md'
    Write-Line '   decision-gated; nothing was contacted.'
}

# 13. Verify — one read-only pass, read as a report rather than as an exit code.
if (-not (Test-Skipped 'verify')) {
    Write-Step '13. Verify'
    # A temporary file, not a record: read-only runs put it where the OS reclaims it rather
    # than leaving a new file in the checkout's .helios/ directory - and the directory itself
    # is only created on the path that writes into it, because creating an empty .helios/ is
    # still a change to a checkout that had none.
    # New-TemporaryFile, not a name built from $PID: a predictable path in a world-writable
    # directory can be pre-created as a symlink, and the write below would follow it.
    # first-run writes its own durable state under .helios/ whether or not -VerifyOnly was
    # passed, so a read-only run of THIS script would create a directory in the checkout by
    # way of its child. HELIOS_STATE_DIR sends that state to a temporary directory instead,
    # removed below with the report.
    $verifyState = $null
    $savedStateDirEnv = $env:HELIOS_STATE_DIR
    if ($readOnly) {
        $reportPath = (New-TemporaryFile).FullName
        $verifyState = Join-Path ([IO.Path]::GetTempPath()) ('helios-firstrun-state-' + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $verifyState -Force | Out-Null
        $env:HELIOS_STATE_DIR = $verifyState
    }
    else {
        New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
        $reportPath = Join-Path $stateDir 'connect-firstrun.json'
    }
    & $pwshBin -NoProfile -File (Join-Path $repoRoot 'scripts/bootstrap/first-run.ps1') -VerifyOnly -Json 2>$null |
        Set-Content -LiteralPath $reportPath -Encoding utf8
    $code = $LASTEXITCODE
    $outstanding = @()
    # $null, not @(): an empty list means "the report named no outstanding lane", and a report
    # nobody could read must not be able to say that. The bash twin draws the same line.
    $readReport = $null
    try {
        $report = Get-Content -LiteralPath $reportPath -Raw -ErrorAction Stop | ConvertFrom-Json
        $readReport = Get-OptionalProperty $report 'lanes'
        if ($null -ne $readReport) {
            foreach ($lane in $readReport.PSObject.Properties) {
                if ((Get-OptionalProperty $lane.Value 'state') -notin @('ready', 'ok')) { $outstanding += $lane.Name }
            }
        }
    }
    catch { $readReport = $null }
    # The report has been read, so the temporary copy has done its job: a run that promises to
    # change nothing leaves nothing behind, in the temp directory either. The bash twin does
    # the same with its mktemp file.
    if ($readOnly) {
        Remove-Item -LiteralPath $reportPath -Force -ErrorAction SilentlyContinue
        if ($verifyState) { Remove-Item -LiteralPath $verifyState -Recurse -Force -ErrorAction SilentlyContinue }
        $env:HELIOS_STATE_DIR = $savedStateDirEnv
    }
    if ($code -ne 0 -and $code -ne 2) { Add-Lane verify 'failed' "first-run.ps1 -VerifyOnly exited $code" }
    elseif ($null -eq $readReport) {
        Add-Lane verify 'failed' `
            "first-run.ps1 exited $code but its -Json report could not be read, so no lane state is known" `
            'pwsh scripts/bootstrap/first-run.ps1 -VerifyOnly   # read the report directly'
    }
    elseif ($outstanding.Count -eq 0) { Add-Lane verify 'ok' 'first-run reports every lane ready' }
    else {
        Add-Lane verify 'needs-owner' "first-run still lists: $(($outstanding | Sort-Object) -join ' ')" `
            'pwsh scripts/bootstrap/first-run.ps1 -VerifyOnly   # the full report, one command per lane'
    }
    Write-Line "   exit $code; outstanding: $(if ($outstanding) { ($outstanding | Sort-Object) -join ' ' } else { 'none' })"
}

# --- state + the one list ---------------------------------------------------
# The directory is created by the branch that writes into it, below, and nowhere else: an
# empty .helios/ appearing in a checkout that had none is a change like any other.
$state = [pscustomobject]@{ surface = $surface; verifyOnly = [bool]$readOnly; lanes = $lanes }
# -Status / -VerifyOnly say "runs nothing that changes anything", so they must not write the
# durable record either. The report is still printed; only the side effect is withheld.
$stateJson = $state | ConvertTo-Json -Depth 5
if (-not $readOnly) {
    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    $stateJson | Set-Content -LiteralPath $stateFile -Encoding utf8
}

$failed = @($lanes | Where-Object { $_.state -eq 'failed' }).Count -gt 0
$pending = @($lanes | Where-Object { $_.state -eq 'needs-owner' }).Count -gt 0

if ($Json) {
    # $stateJson, not the file: a read-only run deliberately does not write $stateFile, so
    # reading it terminated on a clean checkout and returned stale lanes after a mutable run.
    $stateJson
}
else {
    Write-Host ''
    Write-Host '== lanes =='
    foreach ($lane in $lanes) { Write-Host ('  {0,-12} {1,-12} {2}' -f $lane.name, $lane.state, $lane.detail) }
    if ($pending) {
        Write-Host ''
        Write-Host '== what is left for you =='
        $n = 0
        foreach ($lane in $lanes) {
            if ($lane.state -eq 'needs-owner' -and $lane.ownerAction) {
                $n++
                Write-Host ("  {0}. {1}" -f $n, $lane.detail)
                Write-Host ("     {0}" -f $lane.ownerAction)
            }
        }
        Write-Host ''
        Write-Host '  State saved to .helios/connect-state.json — re-run this script and the list gets shorter.'
    }
    else {
        Write-Host ''
        Write-Host '  Nothing left for you. Everything this checkout can connect is connected.'
    }
    Write-Host '  One page: docs/CONNECT.md'
}

if ($failed) { exit 1 }
if ($pending) { exit 2 }
exit 0
