<#
.SYNOPSIS
One-command orchestrator for the owner steps in
docs/architecture/ENTERPRISE_AI_CONNECTIONS.md §1-§4 — dry-run by default,
printing every command it would execute; -Apply executes against the owner's
own logged-in az CLI session.

.DESCRIPTION
Verify-first per step, in the runbook's order:

  1. Auth-plane probes (read-only, always executed): `az account show` (cached
     profile) and `az ad signed-in-user show` (live Graph). Detects the
     AADSTS50078 / expired-MFA state measured on 2026-08-13
     (ENTERPRISE_AI_CONNECTIONS.md §0) and prints the exact re-login command
     with the tenant id. This script NEVER runs `az login` itself — the
     remediation is interactive by design. Unhealthy auth -> exit 2.
  2. Azure resource completion (ARM, §2): stack what-if, then the AI Search
     connection what-if. The Search CREATE is additionally gated behind an
     explicit -DeploySearch switch because the new Search service is a
     deliberate recurring cost (§2.3) — without it, what-if only. Deployment
     outputs are mapped to the env-var NAMES the runtime contract uses
     (.env.template): projectEndpoint -> AZURE_FOUNDRY_PROJECT_ENDPOINT,
     keyVaultUri -> AZURE_KEY_VAULT_URI.
  3. Entra (Graph plane, §3): passthrough to register-entra-app.ps1
     (forwarding -Apply), then the helios-m365-connector app pipeline —
     create (guarded against the duplicate-display-name trap), service
     principal, Graph application permissions
     (ExternalConnection.ReadWrite.OwnedBy + ExternalItem.ReadWrite.OwnedBy),
     admin consent (Graph app roles need Privileged Role Administrator or
     Global Administrator — Cloud Application Administrator is NOT enough for
     these two), and client-secret custody straight into Key Vault. The secret
     value lives only in process memory for the handoff, is never echoed, and
     the variable is cleared immediately (§3.3 shape).
  3c. Optional -OpsIdentity lane: the helios-ops-automation workload identity
     (the upgrade path off the owner's CA/MFA-bound user session — see
     .claude/skills/microsoft-ecosystem/references/tenant-administration.md,
     "Access tiers"). Creates app + SP, generates a certificate credential
     INTO Key Vault (az keyvault certificate create with the self-signed
     default policy, attached via az ad app credential reset --cert
     --keyvault --append — no client secret exists), and assigns roles per
     -Tier: read (Reader @ RG), write (Contributor @ RG + Key Vault Secrets
     Officer @ vault), admin (write + User Access Administrator @ RG). All
     tiers also get Azure AI User on the Foundry account (data plane).
     -Apply with -Tier admin additionally requires -AcceptAdminRisk, because
     User Access Administrator lets the identity re-grant roles.
  4. Microsoft 365 admin + Copilot (§4): print-only ordered click-paths —
     these are tenant mutations executed by the owner in the admin center
     (integrations/m365/README.md carries the Graph connection/schema
     runbook); no automation performs them.
  5. Summary table; exit 0 when nothing needs attention, exit 2 otherwise.

Tenant-custody rule (microsoft-ecosystem SKILL.md): tenant mutations are owner
actions. -Apply is therefore for the owner's own session only; agents run this
script in dry-run form exclusively (.claude/agents/m365-admin.md).

No secret is ever printed, persisted, or passed as a parameter default;
environment/Key Vault names only (m365-connector-client-secret,
helios-ops-automation).

Exit codes: 0 = dry-run printed or apply succeeded; 2 = auth plane unhealthy,
a refused input (-Tier admin without -AcceptAdminRisk under -Apply), or one or
more steps need attention.

.PARAMETER Apply
Execute the commands instead of printing them. Requires a healthy, logged-in
az CLI session (step 1 verifies; it never logs in for you).

.PARAMETER DeploySearch
Additionally execute the AI Search connection CREATE in step 2 (recurring-cost
gate; what-if runs either way). Only meaningful together with -Apply.

.PARAMETER OpsIdentity
Include the helios-ops-automation workload-identity lane (step 3c).

.PARAMETER Tier
Access tier for -OpsIdentity role assignments: read, write (default), admin.

.PARAMETER AcceptAdminRisk
Required alongside -Apply -OpsIdentity -Tier admin: acknowledges that User
Access Administrator lets the automation identity re-grant roles within the RG.

.EXAMPLE
pwsh scripts/bootstrap/setup-tenant.ps1
Dry run of §1-§4: probe auth, print every command, execute nothing.

.EXAMPLE
pwsh scripts/bootstrap/setup-tenant.ps1 -OpsIdentity -Tier write
Dry run including the ops workload-identity lane at the default WRITE tier.

.EXAMPLE
pwsh scripts/bootstrap/setup-tenant.ps1 -Apply
Execute §2-§3 (what-if only for AI Search), print §4 click-paths.

.EXAMPLE
pwsh scripts/bootstrap/setup-tenant.ps1 -Apply -DeploySearch
As above, plus the cost-gated AI Search connection deployment.
#>
#Requires -Version 7
[CmdletBinding()]
param(
    [switch]$Apply,

    [switch]$DeploySearch,

    [switch]$OpsIdentity,

    [ValidateSet('read', 'write', 'admin')]
    [string]$Tier = 'write',

    [switch]$AcceptAdminRisk,

    [string]$ResourceGroup = 'rg-helios-ai',

    [string]$KeyVaultName = 'kv-helios-jcut',

    [string]$ConnectorDisplayName = 'helios-m365-connector',

    [string]$OpsDisplayName = 'helios-ops-automation'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

# --- Constants (every GUID below is cited in tenant-administration.md) ---------------
# Documented tenant (ENTERPRISE_AI_CONNECTIONS.md §1); replaced by the live value from
# `az account show` whenever the cached profile is readable.
$fallbackTenantId = '349e1399-dccf-45b1-af7e-05d7b0676abf'
$graphResourceAppId = '00000003-0000-0000-c000-000000000000'
# Graph APPLICATION permissions for the connector (learn.microsoft.com/graph/permissions-reference):
$permExternalConnectionRwOwnedBy = 'f431331c-49a6-499f-be1c-62af19c34a9d' # ExternalConnection.ReadWrite.OwnedBy
$permExternalItemRwOwnedBy = '8116ae0f-55c2-452d-9944-d18420f5b2c8'       # ExternalItem.ReadWrite.OwnedBy
$connectorSecretName = 'm365-connector-client-secret'                     # Key Vault secret NAME only
# Azure RBAC built-in role definition IDs (learn.microsoft.com/azure/role-based-access-control/built-in-roles):
$roleReader = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
$roleContributor = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
$roleKvSecretsOfficer = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
$roleUserAccessAdmin = '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9'
$roleAzureAiUser = '53ca6127-db72-4b80-b1b0-d745d6d5456d'                 # infra/modules/ai-foundry-account.bicep

$templateFile = Join-Path $repoRoot 'infra' 'main.bicep'
$parametersFile = Join-Path $repoRoot 'infra' 'main.bicepparam'
$registerScript = Join-Path $PSScriptRoot 'register-entra-app.ps1'

# --- Refused input (before any probe): ADMIN tier needs the explicit risk switch -----
if ($Apply -and $OpsIdentity -and $Tier -eq 'admin' -and -not $AcceptAdminRisk) {
    Write-Host 'Refusing -Apply -OpsIdentity -Tier admin without -AcceptAdminRisk: the ADMIN'
    Write-Host 'tier includes User Access Administrator on the resource group, which lets the'
    Write-Host 'automation identity grant and revoke roles — a compromised credential could'
    Write-Host 're-grant itself access. WRITE is the recommended default; re-run with'
    Write-Host '-AcceptAdminRisk only if the owner accepts that trade'
    Write-Host ('(rationale: .claude/skills/microsoft-ecosystem/references/' +
        'tenant-administration.md, "Access tiers").')
    exit 2
}

$mode = if ($Apply) { 'APPLY' } else { 'DRY RUN' }
Write-Host ('== HELIOS setup-tenant ({0}) — ENTERPRISE_AI_CONNECTIONS.md §1-§4 ==' -f $mode)
if (-not $Apply) {
    Write-Host 'Printing the commands this script would execute (step 1 probes are read-only'
    Write-Host 'and run for real). Re-run with -Apply in the OWNER''s logged-in session to'
    Write-Host 'execute; tenant mutations are owner actions (microsoft-ecosystem SKILL.md).'
}
Write-Host ''

# --- Helpers (patterns: connect-all.ps1 / register-entra-app.ps1 / script-patterns.md)
function Get-CliCommand {
    param([Parameter(Mandatory)][string]$Name)
    # Application only: an alias/function shadowing the name would pass a bare
    # Get-Command and then fail as an OS subprocess (script-patterns.md).
    Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
}

function Invoke-Probe {
    param(
        [Parameter(Mandatory)][string]$Executable,
        [string[]]$Arguments = @()
    )
    # Capture ALL output first, THEN read $LASTEXITCODE — piping into anything that
    # can stop the pipeline early may halt it before $LASTEXITCODE is assigned, an
    # error under StrictMode (script-patterns.md, the $LASTEXITCODE pipeline trap).
    $lines = @(& $Executable @Arguments 2>&1 | ForEach-Object { "$_" })
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $lines }
}

function Format-AzCommand {
    param([Parameter(Mandatory)][string[]]$AzArgs)
    $rendered = foreach ($arg in $AzArgs) {
        if ($arg -match '[\s''"@(){}\[\]<>|&;=]') { '"' + ($arg -replace '"', '\"') + '"' }
        else { $arg }
    }
    'az ' + ($rendered -join ' ')
}

function Show-Planned {
    param(
        [Parameter(Mandatory)][string[]]$AzArgs,
        [string]$Note = ''
    )
    Write-Host ('  ' + (Format-AzCommand -AzArgs $AzArgs))
    if ($Note) { Write-Host ('    # ' + $Note) }
}

$stepResults = [System.Collections.Generic.List[object]]::new()
function Add-StepResult {
    param(
        [Parameter(Mandatory)][string]$Step,
        [Parameter(Mandatory)]
        [ValidateSet('ok', 'planned', 'done', 'skipped', 'print-only', 'blocked', 'needs-attention', 'not-reached')]
        [string]$Status,
        [Parameter(Mandatory)][string]$Detail
    )
    $stepResults.Add([pscustomobject]@{ Step = $Step; Status = $Status; Detail = $Detail })
}

function Write-SummaryAndExit {
    Write-Host ''
    Write-Host '== Summary =='
    $table = $stepResults |
        Format-Table Step, Status, Detail -AutoSize |
        Out-String -Width 4096
    Write-Host $table.TrimEnd()
    $attention = @($stepResults | Where-Object { $_.Status -in 'blocked', 'needs-attention' })
    Write-Host ''
    if ($attention.Count -gt 0) {
        Write-Host ('{0} step(s) need attention: {1}' -f $attention.Count,
            (@($attention | ForEach-Object Step) -join ', '))
        exit 2
    }
    Write-Host ('All steps {0}.' -f ($(if ($Apply) { 'completed' } else { 'planned (dry run)' })))
    exit 0
}

# ======================================================================================
# Step 1 — auth-plane probes (§1). Read-only; runs in every mode; never logs in.
# ======================================================================================
Write-Host '== 1. Auth-plane probes (read-only; §0/§1) =='
$azCommand = Get-CliCommand -Name 'az'
if (-not $azCommand) {
    Write-Host 'The Azure CLI (az) is not installed — nothing below can be verified or run.'
    Write-Host 'Install it (https://aka.ms/azure-cli), log in, then re-run this script.'
    Add-StepResult -Step '1 auth' -Status blocked -Detail 'az CLI not on PATH'
    foreach ($s in '2 arm', '3a ingress-app', '3b connector-app', '3c ops-identity', '4 m365-admin') {
        Add-StepResult -Step $s -Status 'not-reached' -Detail 'blocked by step 1'
    }
    Write-SummaryAndExit
}

$accountProbe = Invoke-Probe -Executable $azCommand.Source -Arguments @('account', 'show', '--output', 'json')
$graphProbe = Invoke-Probe -Executable $azCommand.Source -Arguments @('ad', 'signed-in-user', 'show', '--output', 'none')

$tenantId = $fallbackTenantId
$subscriptionId = ''
$accountDetail = 'no readable az profile'
if ($accountProbe.ExitCode -eq 0) {
    try {
        $account = ($accountProbe.Output -join "`n") | ConvertFrom-Json
        $tenantId = [string]$account.tenantId
        $subscriptionId = [string]$account.id
        $accountDetail = ('profile cached: tenant {0}, subscription "{1}"' -f $tenantId, $account.name)
    }
    catch {
        $accountDetail = 'az account show succeeded but its JSON was unparseable'
    }
}
Write-Host ('  az account show          : {0} ({1})' -f
    $(if ($accountProbe.ExitCode -eq 0) { 'ok' } else { 'FAILED' }), $accountDetail)
Write-Host ('  az ad signed-in-user show: {0}' -f
    $(if ($graphProbe.ExitCode -eq 0) { 'ok (Graph plane live)' } else { 'FAILED (Graph plane blocked)' }))

if ($accountProbe.ExitCode -ne 0 -or $graphProbe.ExitCode -ne 0) {
    $failureText = (@($accountProbe.Output) + @($graphProbe.Output)) -join ' '
    $diagnosis = 'az is not logged in'
    $tlsBlocked = $false
    if ($failureText -match 'AADSTS50078|multi-?factor authentication has expired') {
        $diagnosis = ('AADSTS50078 (UserStrongAuthExpired): the session''s MFA claim expired under ' +
            'Conditional Access sign-in frequency — the exact state measured on 2026-08-13 ' +
            '(ENTERPRISE_AI_CONNECTIONS.md §0)')
    }
    elseif ($failureText -match '(AADSTS\d+)') {
        $diagnosis = ('Entra rejected the token ({0}) — see ' -f $Matches[1]) +
            'https://learn.microsoft.com/entra/identity-platform/reference-error-codes'
    }
    elseif ($failureText -match 'CERTIFICATE_VERIFY_FAILED|Certificate verification failed|SSLError') {
        $tlsBlocked = $true
        $diagnosis = ('TLS to login.microsoftonline.com failed — an intercepting proxy''s CA is not ' +
            'trusted by az. This is a network problem, not an auth problem; re-login cannot fix it')
    }
    Write-Host ''
    Write-Host ('  Diagnosis: {0}.' -f $diagnosis)
    if ($tlsBlocked) {
        Write-Host '  Remediation: point az at the proxy''s CA bundle (REQUESTS_CA_BUNDLE) per'
        Write-Host '  https://learn.microsoft.com/cli/azure/use-cli-effectively#work-behind-a-proxy'
        Write-Host '  — never disable TLS verification. Then re-run this script.'
    }
    else {
        Write-Host '  Remediation (interactive by design; this script never runs az login):'
        Write-Host '    az logout'
        Write-Host ('    az login --tenant "{0}"' -f $tenantId)
        Write-Host '    # if az ad ... still 401s afterwards, refresh the Graph scope explicitly:'
        Write-Host ('    az login --tenant "{0}" --scope "https://graph.microsoft.com//.default"' -f $tenantId)
        Write-Host '    az account show   # expect subscription "main"'
    }
    Add-StepResult -Step '1 auth' -Status blocked -Detail $diagnosis
    foreach ($s in '2 arm', '3a ingress-app', '3b connector-app', '3c ops-identity', '4 m365-admin') {
        Add-StepResult -Step $s -Status 'not-reached' -Detail 'blocked by step 1 — re-login first'
    }
    Write-SummaryAndExit
}
Add-StepResult -Step '1 auth' -Status ok -Detail ('both planes live; tenant {0}' -f $tenantId)
$stepStatusDefault = if ($Apply) { 'done' } else { 'planned' }

# ======================================================================================
# Step 2 — Azure resource completion (ARM plane, §2)
# ======================================================================================
Write-Host ''
Write-Host '== 2. Azure resource completion (ARM; §2) =='
$whatIfArgs = @('deployment', 'group', 'what-if', '-g', $ResourceGroup,
    '--template-file', $templateFile, '--parameters', $parametersFile)
$searchWhatIfArgs = $whatIfArgs + @('--parameters', 'deployAiSearchConnection=true')
$searchCreateArgs = @('deployment', 'group', 'create', '-g', $ResourceGroup,
    '--template-file', $templateFile, '--parameters', $parametersFile,
    '--parameters', 'deployAiSearchConnection=true')
$outputsArgs = @('deployment', 'group', 'show', '-g', $ResourceGroup, '-n', 'main',
    '--query', 'properties.outputs.{projectEndpoint:projectEndpoint.value, keyVaultUri:keyVaultUri.value}',
    '--output', 'json')

$step2Detail = 'what-if verified; AI Search create withheld (no -DeploySearch)'
if (-not $Apply) {
    Write-Host '  2.1 Re-verify the stack unchanged (read-only plan):'
    Show-Planned -AzArgs $whatIfArgs
    Write-Host '  2.2 AI Search connection plan (opt-in module):'
    Show-Planned -AzArgs $searchWhatIfArgs
    Write-Host '  2.3 AI Search connection CREATE — cost gate: printed only; -Apply -DeploySearch executes'
    Write-Host '      (new Search service is a deliberate recurring cost, §2.3):'
    Show-Planned -AzArgs $searchCreateArgs
    Write-Host '  2.4 Outputs -> runtime env-var NAMES (.env.template; values are URIs, not credentials):'
    Show-Planned -AzArgs $outputsArgs
    Write-Host '        projectEndpoint -> AZURE_FOUNDRY_PROJECT_ENDPOINT'
    Write-Host '        keyVaultUri     -> AZURE_KEY_VAULT_URI'
    Add-StepResult -Step '2 arm' -Status planned -Detail 'what-if x2 + gated create + outputs mapping printed'
}
else {
    Write-Host '  2.1 Stack what-if (read-only plan):'
    Show-Planned -AzArgs $whatIfArgs
    $wi = Invoke-Probe -Executable $azCommand.Source -Arguments $whatIfArgs
    $wi.Output | ForEach-Object { Write-Host ('    ' + $_) }
    if ($wi.ExitCode -ne 0) {
        Add-StepResult -Step '2 arm' -Status 'needs-attention' -Detail ('stack what-if failed (exit {0})' -f $wi.ExitCode)
    }
    else {
        Write-Host '  2.2 AI Search connection what-if:'
        Show-Planned -AzArgs $searchWhatIfArgs
        $swi = Invoke-Probe -Executable $azCommand.Source -Arguments $searchWhatIfArgs
        $swi.Output | ForEach-Object { Write-Host ('    ' + $_) }
        if ($swi.ExitCode -ne 0) {
            Add-StepResult -Step '2 arm' -Status 'needs-attention' -Detail ('AI Search what-if failed (exit {0})' -f $swi.ExitCode)
        }
        elseif ($DeploySearch) {
            Write-Host '  2.3 AI Search connection create (-DeploySearch passed — cost accepted):'
            Show-Planned -AzArgs $searchCreateArgs
            $create = Invoke-Probe -Executable $azCommand.Source -Arguments ($searchCreateArgs + @('--output', 'none'))
            if ($create.ExitCode -ne 0) {
                $create.Output | Select-Object -Last 10 | ForEach-Object { Write-Host ('    ' + $_) }
                Add-StepResult -Step '2 arm' -Status 'needs-attention' -Detail ('AI Search create failed (exit {0})' -f $create.ExitCode)
            }
            else {
                $step2Detail = 'what-if verified; AI Search connection deployed'
                Add-StepResult -Step '2 arm' -Status done -Detail $step2Detail
            }
        }
        else {
            Write-Host '  2.3 AI Search create WITHHELD: pass -DeploySearch with -Apply to accept the'
            Write-Host '      recurring Search-service cost (§2.3); what-if above is the full preview.'
            Add-StepResult -Step '2 arm' -Status done -Detail $step2Detail
        }
        Write-Host '  2.4 Outputs -> env-var names:'
        $outs = Invoke-Probe -Executable $azCommand.Source -Arguments $outputsArgs
        if ($outs.ExitCode -eq 0) {
            try {
                $outJson = ($outs.Output -join "`n") | ConvertFrom-Json
                # Endpoints/URIs are identifiers, not credentials (IDENTITY_ARCHITECTURE.md §2).
                Write-Host ('        AZURE_FOUNDRY_PROJECT_ENDPOINT = {0}' -f $outJson.projectEndpoint)
                Write-Host ('        AZURE_KEY_VAULT_URI            = {0}' -f $outJson.keyVaultUri)
            }
            catch {
                Write-Host '        (deployment outputs unparseable — inspect with the command above)'
            }
        }
        else {
            Write-Host '        (no deployment named "main" to read outputs from yet)'
        }
    }
}

# ======================================================================================
# Step 3a — Entra ingress app (§3.1): passthrough to register-entra-app.ps1
# ======================================================================================
Write-Host ''
Write-Host '== 3a. helios-ai-api ingress app — register-entra-app.ps1 passthrough (§3.1) =='
$registerArgs = @()
if ($Apply) { $registerArgs += '-Apply' }
& $registerScript @registerArgs
$registerExit = $LASTEXITCODE
if ($registerExit -ne 0) {
    Add-StepResult -Step '3a ingress-app' -Status 'needs-attention' -Detail ('register-entra-app.ps1 exited {0}' -f $registerExit)
}
else {
    Add-StepResult -Step '3a ingress-app' -Status $stepStatusDefault -Detail 'register-entra-app.ps1 exited 0'
}

# ======================================================================================
# Step 3b — M365 connector app (§3.2-§3.3)
# ======================================================================================
Write-Host ''
Write-Host ('== 3b. {0}: app + SP + Graph app permissions + consent + secret custody (§3.2-§3.3) ==' -f $ConnectorDisplayName)
$permissionPair = @(
    ('{0}=Role' -f $permExternalConnectionRwOwnedBy),
    ('{0}=Role' -f $permExternalItemRwOwnedBy)
)
if (-not $Apply) {
    Show-Planned -AzArgs @('ad', 'app', 'list', '--display-name', $ConnectorDisplayName,
        '--query', '[0].appId', '--output', 'tsv') `
        -Note 'guard first: display names are NOT unique — create only when this returns nothing'
    Show-Planned -AzArgs @('ad', 'app', 'create', '--display-name', $ConnectorDisplayName,
        '--sign-in-audience', 'AzureADMyOrg')
    Show-Planned -AzArgs @('ad', 'sp', 'create', '--id', '<appId>')
    Show-Planned -AzArgs (@('ad', 'app', 'permission', 'add', '--id', '<appId>',
            '--api', $graphResourceAppId, '--api-permissions') + $permissionPair) `
        -Note 'ExternalConnection.ReadWrite.OwnedBy + ExternalItem.ReadWrite.OwnedBy (application)'
    Show-Planned -AzArgs @('ad', 'app', 'permission', 'admin-consent', '--id', '<appId>') `
        -Note 'Graph APP roles: needs Privileged Role Administrator / Global Administrator'
    Show-Planned -AzArgs @('ad', 'app', 'credential', 'reset', '--id', '<appId>',
        '--display-name', 'kv-custody', '--query', 'password', '--output', 'tsv') `
        -Note 'value captured in memory only — never echoed, never written to a file'
    Show-Planned -AzArgs @('keyvault', 'secret', 'set', '--vault-name', $KeyVaultName,
        '--name', $connectorSecretName, '--value', '<in-memory only>', '--output', 'none') `
        -Note 'then the variable is cleared; Key Vault is the only durable copy (§3.3)'
    Add-StepResult -Step '3b connector-app' -Status planned -Detail 'create/sp/permissions/consent/secret-to-KV pipeline printed'
}
else {
    $connectorAttention = @()
    # Duplicate-display-name guard (tenant-administration.md, "duplicate-display-name trap").
    $appList = Invoke-Probe -Executable $azCommand.Source -Arguments @('ad', 'app', 'list',
        '--display-name', $ConnectorDisplayName, '--query', '[0].appId', '--output', 'tsv')
    $connectorAppId = (@($appList.Output) | Where-Object { $_ } | Select-Object -First 1)
    if ($connectorAppId) {
        Write-Host ('  App exists (appId {0}) — skipping create.' -f $connectorAppId)
    }
    else {
        $createApp = Invoke-Probe -Executable $azCommand.Source -Arguments @('ad', 'app', 'create',
            '--display-name', $ConnectorDisplayName, '--sign-in-audience', 'AzureADMyOrg',
            '--query', 'appId', '--output', 'tsv')
        if ($createApp.ExitCode -ne 0) { $connectorAttention += 'app create failed' }
        else {
            $connectorAppId = (@($createApp.Output) | Where-Object { $_ } | Select-Object -First 1)
            Write-Host ('  Created app (appId {0}).' -f $connectorAppId)
        }
    }
    if ($connectorAppId) {
        $spList = Invoke-Probe -Executable $azCommand.Source -Arguments @('ad', 'sp', 'list',
            '--filter', ("appId eq '{0}'" -f $connectorAppId), '--query', '[0].id', '--output', 'tsv')
        $connectorSpId = (@($spList.Output) | Where-Object { $_ } | Select-Object -First 1)
        if (-not $connectorSpId) {
            $spCreate = Invoke-Probe -Executable $azCommand.Source -Arguments @('ad', 'sp', 'create', '--id', $connectorAppId)
            if ($spCreate.ExitCode -ne 0) { $connectorAttention += 'sp create failed' }
            else { Write-Host '  Service principal created.' }
        }
        else { Write-Host ('  Service principal exists (objectId {0}).' -f $connectorSpId) }

        # Verify-first on permissions: adding a duplicate errors on current az builds.
        $permProbe = Invoke-Probe -Executable $azCommand.Source -Arguments @('ad', 'app', 'show',
            '--id', $connectorAppId,
            '--query', ("requiredResourceAccess[?resourceAppId=='{0}'].resourceAccess[].id" -f $graphResourceAppId),
            '--output', 'json')
        $permText = $permProbe.Output -join ' '
        if ($permText -match $permExternalConnectionRwOwnedBy -and $permText -match $permExternalItemRwOwnedBy) {
            Write-Host '  Graph application permissions already present — skipping permission add.'
        }
        else {
            $permAdd = Invoke-Probe -Executable $azCommand.Source -Arguments (@('ad', 'app', 'permission', 'add',
                    '--id', $connectorAppId, '--api', $graphResourceAppId, '--api-permissions') + $permissionPair)
            if ($permAdd.ExitCode -ne 0) { $connectorAttention += 'permission add failed' }
            else { Write-Host '  Graph application permissions added.' }
        }

        $consent = Invoke-Probe -Executable $azCommand.Source -Arguments @('ad', 'app', 'permission',
            'admin-consent', '--id', $connectorAppId)
        if ($consent.ExitCode -ne 0) {
            Write-Host '  Admin consent FAILED — Graph application permissions need Privileged Role'
            Write-Host '  Administrator or Global Administrator (Cloud Application Administrator is not'
            Write-Host '  enough for Graph app roles). Have the owner grant consent and re-run.'
            $connectorAttention += 'admin consent refused (role too low?)'
        }
        else { Write-Host '  Admin consent granted.' }

        # Secret custody (§3.3): verify-first so a healthy credential is never rotated
        # by accident; the value exists only in this process's memory for the handoff.
        $kvProbe = Invoke-Probe -Executable $azCommand.Source -Arguments @('keyvault', 'secret', 'show',
            '--vault-name', $KeyVaultName, '--name', $connectorSecretName, '--query', 'name', '--output', 'tsv')
        if ($kvProbe.ExitCode -eq 0) {
            Write-Host ('  Key Vault secret {0} already exists — not rotating (reset + set manually to rotate).' -f $connectorSecretName)
        }
        else {
            # stderr is dropped (warnings only); stdout is the secret — captured, never printed.
            $resetArgs = @('ad', 'app', 'credential', 'reset', '--id', $connectorAppId,
                '--display-name', 'kv-custody', '--query', 'password', '--output', 'tsv')
            $secretRaw = @(& $azCommand.Source @resetArgs 2>$null)
            if ($LASTEXITCODE -ne 0) {
                $connectorAttention += 'credential reset failed'
            }
            else {
                $secretValue = ($secretRaw | Where-Object { $_ } | Select-Object -First 1)
                # The value crosses to az as an argument in the owner's own session — the
                # §3.3 runbook shape; it is never echoed and never touches a file.
                $setArgs = @('keyvault', 'secret', 'set', '--vault-name', $KeyVaultName,
                    '--name', $connectorSecretName, '--value', $secretValue, '--output', 'none')
                $setOut = @(& $azCommand.Source @setArgs 2>&1 | ForEach-Object { "$_" })
                if ($LASTEXITCODE -ne 0) {
                    $setOut | Select-Object -Last 5 | ForEach-Object { Write-Host ('    ' + $_) }
                    $connectorAttention += ('secret set into {0} failed' -f $KeyVaultName)
                }
                else {
                    Write-Host ('  Secret stored as Key Vault secret "{0}" (value never echoed).' -f $connectorSecretName)
                }
                # Clear every in-memory copy of the value (the args array holds one too).
                $secretValue = $null
                $setArgs = $null
                Remove-Variable -Name secretValue, setArgs
                Write-Host '  In-memory secret variable cleared.'
            }
        }
    }
    if ($connectorAttention.Count -gt 0) {
        Add-StepResult -Step '3b connector-app' -Status 'needs-attention' -Detail ($connectorAttention -join '; ')
    }
    else {
        Add-StepResult -Step '3b connector-app' -Status done -Detail 'app/sp/permissions/consent/secret verified or applied'
    }
}

# ======================================================================================
# Step 3c — ops workload identity (-OpsIdentity; tenant-administration.md "Access tiers")
# ======================================================================================
Write-Host ''
if (-not $OpsIdentity) {
    Write-Host '== 3c. Ops workload identity: SKIPPED (pass -OpsIdentity to include this lane) =='
    Add-StepResult -Step '3c ops-identity' -Status skipped -Detail 'not requested (-OpsIdentity absent)'
}
else {
    Write-Host ('== 3c. {0}: workload identity, cert-in-Key-Vault credential, tier "{1}" ==' -f $OpsDisplayName, $Tier)
    # Tier -> grants (role IDs are constants above; scopes resolved under -Apply).
    $tierGrants = switch ($Tier) {
        'read' {
            @([pscustomobject]@{ Role = 'Reader'; RoleId = $roleReader; ScopeKind = 'rg' })
        }
        'write' {
            @(
                [pscustomobject]@{ Role = 'Contributor'; RoleId = $roleContributor; ScopeKind = 'rg' },
                [pscustomobject]@{ Role = 'Key Vault Secrets Officer'; RoleId = $roleKvSecretsOfficer; ScopeKind = 'vault' }
            )
        }
        'admin' {
            @(
                [pscustomobject]@{ Role = 'Contributor'; RoleId = $roleContributor; ScopeKind = 'rg' },
                [pscustomobject]@{ Role = 'Key Vault Secrets Officer'; RoleId = $roleKvSecretsOfficer; ScopeKind = 'vault' },
                [pscustomobject]@{ Role = 'User Access Administrator'; RoleId = $roleUserAccessAdmin; ScopeKind = 'rg' }
            )
        }
    }
    # Every tier gets the Foundry data-plane role, same as the interactive operator
    # (infra/modules/ai-foundry-account.bicep — Azure AI User).
    $tierGrants = @($tierGrants) + @([pscustomobject]@{ Role = 'Azure AI User'; RoleId = $roleAzureAiUser; ScopeKind = 'foundry' })
    if ($Tier -eq 'admin') {
        Write-Host '  RISK (admin tier): User Access Administrator lets this identity re-grant roles'
        Write-Host '  within the RG. WRITE is the recommended default; -Apply requires -AcceptAdminRisk.'
    }
    Write-Host ('  Planned grants for tier "{0}":' -f $Tier)
    foreach ($g in $tierGrants) {
        Write-Host ('    {0} ({1}) @ {2}' -f $g.Role, $g.RoleId, $g.ScopeKind)
    }

    if (-not $Apply) {
        Show-Planned -AzArgs @('ad', 'app', 'list', '--display-name', $OpsDisplayName,
            '--query', '[0].appId', '--output', 'tsv') `
            -Note 'duplicate-display-name guard, same as step 3b'
        Show-Planned -AzArgs @('ad', 'app', 'create', '--display-name', $OpsDisplayName,
            '--sign-in-audience', 'AzureADMyOrg')
        Show-Planned -AzArgs @('ad', 'sp', 'create', '--id', '<appId>')
        Show-Planned -AzArgs @('keyvault', 'certificate', 'get-default-policy') `
            -Note 'self-signed policy JSON, saved to a temp file for the next command'
        Show-Planned -AzArgs @('keyvault', 'certificate', 'create', '--vault-name', $KeyVaultName,
            '--name', $OpsDisplayName, '--policy', '@default-policy.json') `
            -Note 'private key is generated INTO Key Vault — no secret ever exists in env or files'
        Show-Planned -AzArgs @('ad', 'app', 'credential', 'reset', '--id', '<appId>',
            '--cert', $OpsDisplayName, '--keyvault', $KeyVaultName, '--append') `
            -Note 'attaches the KV certificate as the app credential (append: never wipes others)'
        foreach ($g in $tierGrants) {
            Show-Planned -AzArgs @('role', 'assignment', 'create',
                '--assignee-object-id', '<spObjectId>', '--assignee-principal-type', 'ServicePrincipal',
                '--role', $g.RoleId, '--scope', ('<{0}-scope>' -f $g.ScopeKind)) `
                -Note ('{0} @ {1}' -f $g.Role, $g.ScopeKind)
        }
        Add-StepResult -Step '3c ops-identity' -Status planned -Detail ('app/sp/cert/grants printed for tier "{0}"' -f $Tier)
    }
    else {
        $opsAttention = @()
        $opsList = Invoke-Probe -Executable $azCommand.Source -Arguments @('ad', 'app', 'list',
            '--display-name', $OpsDisplayName, '--query', '[0].appId', '--output', 'tsv')
        $opsAppId = (@($opsList.Output) | Where-Object { $_ } | Select-Object -First 1)
        if ($opsAppId) { Write-Host ('  App exists (appId {0}) — skipping create.' -f $opsAppId) }
        else {
            $opsCreate = Invoke-Probe -Executable $azCommand.Source -Arguments @('ad', 'app', 'create',
                '--display-name', $OpsDisplayName, '--sign-in-audience', 'AzureADMyOrg',
                '--query', 'appId', '--output', 'tsv')
            if ($opsCreate.ExitCode -ne 0) { $opsAttention += 'app create failed' }
            else {
                $opsAppId = (@($opsCreate.Output) | Where-Object { $_ } | Select-Object -First 1)
                Write-Host ('  Created app (appId {0}).' -f $opsAppId)
            }
        }
        $opsSpId = ''
        if ($opsAppId) {
            $opsSpList = Invoke-Probe -Executable $azCommand.Source -Arguments @('ad', 'sp', 'list',
                '--filter', ("appId eq '{0}'" -f $opsAppId), '--query', '[0].id', '--output', 'tsv')
            $opsSpId = (@($opsSpList.Output) | Where-Object { $_ } | Select-Object -First 1)
            if (-not $opsSpId) {
                $opsSpCreate = Invoke-Probe -Executable $azCommand.Source -Arguments @('ad', 'sp', 'create',
                    '--id', $opsAppId, '--query', 'id', '--output', 'tsv')
                if ($opsSpCreate.ExitCode -ne 0) { $opsAttention += 'sp create failed' }
                else { $opsSpId = (@($opsSpCreate.Output) | Where-Object { $_ } | Select-Object -First 1) }
            }

            # Certificate credential, generated into Key Vault (verify-first).
            $certProbe = Invoke-Probe -Executable $azCommand.Source -Arguments @('keyvault', 'certificate', 'show',
                '--vault-name', $KeyVaultName, '--name', $OpsDisplayName, '--query', 'name', '--output', 'tsv')
            if ($certProbe.ExitCode -eq 0) {
                Write-Host ('  Key Vault certificate {0} already exists — reusing.' -f $OpsDisplayName)
            }
            else {
                $policy = Invoke-Probe -Executable $azCommand.Source -Arguments @('keyvault', 'certificate', 'get-default-policy')
                if ($policy.ExitCode -ne 0) { $opsAttention += 'get-default-policy failed' }
                else {
                    $policyFile = New-TemporaryFile
                    try {
                        Set-Content -Path $policyFile -Value ($policy.Output -join "`n")
                        $certCreate = Invoke-Probe -Executable $azCommand.Source -Arguments @('keyvault', 'certificate', 'create',
                            '--vault-name', $KeyVaultName, '--name', $OpsDisplayName,
                            '--policy', ('@{0}' -f $policyFile.FullName), '--output', 'none')
                        if ($certCreate.ExitCode -ne 0) {
                            $certCreate.Output | Select-Object -Last 5 | ForEach-Object { Write-Host ('    ' + $_) }
                            $opsAttention += 'certificate create failed'
                        }
                        else { Write-Host ('  Self-signed certificate created in Key Vault as "{0}".' -f $OpsDisplayName) }
                    }
                    finally {
                        Remove-Item $policyFile -Force -ErrorAction SilentlyContinue
                    }
                }
            }
            $keyCredCount = Invoke-Probe -Executable $azCommand.Source -Arguments @('ad', 'app', 'show',
                '--id', $opsAppId, '--query', 'length(keyCredentials)', '--output', 'tsv')
            $attached = ($keyCredCount.ExitCode -eq 0 -and
                ((@($keyCredCount.Output) | Where-Object { $_ } | Select-Object -First 1) -match '^[1-9]'))
            if ($attached) {
                Write-Host '  App already carries a certificate credential — skipping attach.'
            }
            else {
                $attach = Invoke-Probe -Executable $azCommand.Source -Arguments @('ad', 'app', 'credential', 'reset',
                    '--id', $opsAppId, '--cert', $OpsDisplayName, '--keyvault', $KeyVaultName, '--append', '--output', 'none')
                if ($attach.ExitCode -ne 0) { $opsAttention += 'certificate attach failed' }
                else { Write-Host '  Certificate attached as the app credential (no client secret exists).' }
            }
        }

        # Role assignments (RBAC is eventually consistent: bounded retry on the
        # PrincipalNotFound replication race — azure-oidc-setup.ps1 ensure_role pattern).
        if ($opsAppId -and $opsSpId) {
            $rgScope = ''
            if ($subscriptionId) {
                $rgScope = ('/subscriptions/{0}/resourceGroups/{1}' -f $subscriptionId, $ResourceGroup)
            }
            $vaultProbe = Invoke-Probe -Executable $azCommand.Source -Arguments @('keyvault', 'show',
                '--name', $KeyVaultName, '--query', 'id', '--output', 'tsv')
            $vaultScope = (@($vaultProbe.Output) | Where-Object { $_ } | Select-Object -First 1)
            $foundryProbe = Invoke-Probe -Executable $azCommand.Source -Arguments @('resource', 'list',
                '-g', $ResourceGroup, '--resource-type', 'Microsoft.CognitiveServices/accounts',
                '--query', '[0].id', '--output', 'tsv')
            $foundryScope = (@($foundryProbe.Output) | Where-Object { $_ } | Select-Object -First 1)
            foreach ($g in $tierGrants) {
                $scope = switch ($g.ScopeKind) {
                    'rg' { $rgScope }
                    'vault' { $vaultScope }
                    'foundry' { $foundryScope }
                }
                if (-not $scope) {
                    Write-Host ('  {0}: SKIPPED — {1} scope not resolvable yet (deploy step 2 first?).' -f $g.Role, $g.ScopeKind)
                    $opsAttention += ('{0} grant skipped ({1} scope missing)' -f $g.Role, $g.ScopeKind)
                    continue
                }
                $assignArgs = @('role', 'assignment', 'create',
                    '--assignee-object-id', $opsSpId, '--assignee-principal-type', 'ServicePrincipal',
                    '--role', $g.RoleId, '--scope', $scope, '--output', 'none')
                $granted = $false
                for ($attempt = 1; $attempt -le 5 -and -not $granted; $attempt++) {
                    $assign = Invoke-Probe -Executable $azCommand.Source -Arguments $assignArgs
                    if ($assign.ExitCode -eq 0) {
                        $granted = $true
                        Write-Host ('  Granted {0} @ {1}.' -f $g.Role, $g.ScopeKind)
                    }
                    elseif (($assign.Output -join ' ') -match 'PrincipalNotFound|does not exist in the directory' -and $attempt -lt 5) {
                        # New SP not yet replicated through Entra — the one retryable case.
                        Start-Sleep -Seconds (5 * $attempt)
                    }
                    else {
                        $assign.Output | Select-Object -Last 3 | ForEach-Object { Write-Host ('    ' + $_) }
                        $opsAttention += ('{0} grant failed' -f $g.Role)
                        break
                    }
                }
            }
            Write-Host ''
            Write-Host '  Container login (owner retrieves once; both files are a materialized'
            Write-Host '  credential while they exist — delete them after login):'
            Write-Host ('    az keyvault secret download --file ops-cert.pfx --vault-name {0} --name {1} --encoding base64' -f $KeyVaultName, $OpsDisplayName)
            Write-Host '    openssl pkcs12 -in ops-cert.pfx -passin pass: -passout pass: -out ops-cert.pem -nodes'
            Write-Host ('    az login --service-principal --username {0} --certificate ops-cert.pem --tenant {1}' -f $opsAppId, $tenantId)
            Write-Host '    rm ops-cert.pfx ops-cert.pem'
        }
        if ($opsAttention.Count -gt 0) {
            Add-StepResult -Step '3c ops-identity' -Status 'needs-attention' -Detail ($opsAttention -join '; ')
        }
        else {
            Add-StepResult -Step '3c ops-identity' -Status done -Detail ('identity + cert + tier "{0}" grants applied' -f $Tier)
        }
    }
}

# ======================================================================================
# Step 4 — Microsoft 365 admin + Copilot (§4): print-only, always
# ======================================================================================
Write-Host ''
Write-Host '== 4. Microsoft 365 admin + Copilot (owner click-paths; PRINT-ONLY in every mode) =='
Write-Host '  Ordered runbook (details + payloads: integrations/m365/README.md):'
Write-Host ('  1. Client-credentials token for Graph as {0} — secret read from Key Vault' -f $ConnectorDisplayName)
Write-Host ('     secret "{0}", never echoed, never a file.' -f $connectorSecretName)
Write-Host '  2. POST /external/connections with graph-connector/connection.json, then'
Write-Host '     PATCH /external/connections/heliosplatform/schema with schema.json and poll'
Write-Host '     the operation to "completed" (takes minutes; items PUT earlier are rejected).'
Write-Host '  3. M365 admin center -> Settings -> Search & intelligence -> Data sources ->'
Write-Host '     enable the heliosplatform connection for Copilot.'
Write-Host '  4. Package declarative-agent/declarativeAgent.json with the M365 Agents Toolkit;'
Write-Host '     upload via Integrated apps -> Upload custom app; assign to the operators group.'
Write-Host '  5. Ingestion automation rides GitHub OIDC -> Entra federation'
Write-Host '     (IDENTITY_ARCHITECTURE.md §3) — no stored client secret in CI, ever.'
Add-StepResult -Step '4 m365-admin' -Status 'print-only' -Detail 'owner click-paths printed (integrations/m365/README.md)'

# ======================================================================================
# Step 5 — summary + exit contract
# ======================================================================================
Write-SummaryAndExit
