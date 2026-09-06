#Requires -Version 7
<#
.SYNOPSIS
Stores the AIHub provider keys in Azure Key Vault — openai-api-key, anthropic-api-key,
github-models-token — from a masked prompt or from the env var NAME each provider
declares. The printed-never-scripted owner step of the bring-up, made safe to run.

.DESCRIPTION
The secret NAMES and the env-var NAMES come from config/aihub.json (AIHUB_CONFIG
first when set): every provider that declares both apiKeySecretName and apiKeyEnv is
a target, deduplicated by secret name (openai and openai-codex share openai-api-key).
When the config is unreadable or declares none, the three built-in pairs above are
used — the same names infra/main.bicep provisions and load-env-from-keyvault.sh reads.

Dry-run by default: lists every target with its env name, its value source, and
whether the secret already exists in the vault (probed by NAME only). -Apply writes.
Each target is one item of a GET-diff-then-print-then-apply pass: the exact command
is printed BEFORE it runs, a failed item never aborts the pass, and the script exits
1 with a replay list of everything that did not land.

SECURITY — values are never printed, never logged, never on argv:
  - the value is read from the env var (-FromEnv) or from Read-Host -AsSecureString;
    an empty value skips the target;
  - it reaches `az keyvault secret set` through a temp file passed as --file (created
    O_EXCL with mode 0600 on Unix in the same call, written without a trailing
    newline, deleted in finally), never as --value (argv is visible to every process
    on the host);
  - az runs with --output none and its output is captured and discarded;
  - verification reads the NAME back (`az keyvault secret show --query name`), never
    the value.
The plaintext string necessarily exists in this process's memory until garbage
collection; that is the same custody class as the az CLI's own token cache.

.PARAMETER VaultUri
Key Vault URI (https://<vault>.vault.azure.net/). Defaults to AZURE_KEY_VAULT_URI —
the vault infra/main.bicep provisions; scripts/bootstrap/azure-up.sh writes it to
.helios/azure.env.

.PARAMETER Only
Restrict the pass to these secret names (e.g. -Only openai-api-key).

.PARAMETER FromEnv
Read each value from the env var NAME the provider declares (OPENAI_API_KEY,
ANTHROPIC_API_KEY, GITHUB_MODELS_TOKEN) instead of prompting; empty variables skip.

.PARAMETER Apply
Write to the vault. Without it the script only reports (dry run).

.EXAMPLE
pwsh scripts/bootstrap/set-provider-secrets.ps1
# dry run: targets, sources, and whether each secret exists (names only)

.EXAMPLE
pwsh scripts/bootstrap/set-provider-secrets.ps1 -Only openai-api-key -Apply
# masked prompt for one value, stored, then verified by name

.EXAMPLE
pwsh scripts/bootstrap/set-provider-secrets.ps1 -FromEnv -Apply
# non-interactive: every declared env var that holds a value is stored

.NOTES
Exit codes: 0 = success (or clean dry run); 1 = one or more targets failed (replay
list printed) or an unknown -Only name; 2 = -Apply with a precondition missing (no
vault URI, a malformed one, az not on PATH, or az not logged in — the exact fix is
printed). A dry run never exits 2: the target list is useful BEFORE the vault is
wired, so it degrades instead — the vault column reads "unknown (<precondition>)",
the fix line is printed, and the exit is 0 (the scripts/github/apply-*.ps1 sibling
rule: "re-run without -Apply for a dry run that needs neither").
#>
[CmdletBinding()]
param(
    [string]$VaultUri = $env:AZURE_KEY_VAULT_URI,

    [string[]]$Only,

    [switch]$FromEnv,

    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$mode = if ($Apply) { 'apply' } else { 'dry-run' }

# StrictMode-safe property access on parsed JSON (rest-connect.ps1 pattern).
function Get-OptionalProperty {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object -or $Object -isnot [System.Management.Automation.PSObject]) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -ne $prop -and $null -ne $prop.Value) { return $prop.Value }
    return $Default
}

# Presence = a NON-WHITESPACE value (auth-doctor.ps1 rule): dotenv loaders and Actions
# expressions materialize optional secrets as EMPTY variables. Read only for this
# emptiness test here; never logged.
function Test-EnvValue {
    param([Parameter(Mandatory)][string]$Name)
    -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($Name))
}

# --- Targets: config first, built-in fallback ---------------------------------------
$configPath = if ($env:AIHUB_CONFIG -and (Test-Path -LiteralPath $env:AIHUB_CONFIG)) { $env:AIHUB_CONFIG } else { Join-Path $repoRoot 'config' 'aihub.json' }
$targets = [ordered]@{}
$targetSource = "config ($configPath)"
try {
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $providers = Get-OptionalProperty $config 'providers'
    if ($providers -is [System.Management.Automation.PSObject]) {
        foreach ($prop in $providers.PSObject.Properties) {
            $entry = $prop.Value
            $secretName = [string](Get-OptionalProperty $entry 'apiKeySecretName' '')
            $envName = [string](Get-OptionalProperty $entry 'apiKeyEnv' '')
            # A provider without BOTH names has no vault path the hub reads, so it is
            # not a target (azure-openai, ollama, azure-foundry today).
            if ([string]::IsNullOrWhiteSpace($secretName) -or [string]::IsNullOrWhiteSpace($envName)) { continue }
            if ($targets.Contains($secretName)) { $targets[$secretName].Providers.Add($prop.Name) }
            else {
                $targets[$secretName] = [pscustomobject]@{
                    SecretName = $secretName
                    EnvName    = $envName
                    Providers  = [System.Collections.Generic.List[string]]::new([string[]]@($prop.Name))
                }
            }
        }
    }
}
catch { Write-Verbose "config unreadable ($($_.Exception.Message)); using the built-in targets" }
if ($targets.Count -eq 0) {
    $targetSource = 'built-in fallback (config declared no apiKeySecretName/apiKeyEnv pairs)'
    foreach ($pair in @(
            @{ SecretName = 'openai-api-key'; EnvName = 'OPENAI_API_KEY'; Providers = @('openai', 'openai-codex') }
            @{ SecretName = 'anthropic-api-key'; EnvName = 'ANTHROPIC_API_KEY'; Providers = @('anthropic') }
            @{ SecretName = 'github-models-token'; EnvName = 'GITHUB_MODELS_TOKEN'; Providers = @('github-models') }
        )) {
        $targets[$pair.SecretName] = [pscustomobject]@{
            SecretName = $pair.SecretName; EnvName = $pair.EnvName
            Providers  = [System.Collections.Generic.List[string]]::new([string[]]$pair.Providers)
        }
    }
}

Write-Host "set-provider-secrets: mode=$mode targets=$($targets.Count) source=$targetSource"

if ($Only) {
    $unknown = @($Only | Where-Object { -not $targets.Contains($_) })
    if ($unknown.Count -gt 0) {
        Write-Host ('set-provider-secrets: unknown -Only name(s): {0}. Known: {1}' -f ($unknown -join ', '), (@($targets.Keys) -join ', '))
        exit 1
    }
}
$selected = @($targets.Values | Where-Object { -not $Only -or $Only -contains $_.SecretName })

# --- Preconditions ---------------------------------------------------------------------
# One precondition is evaluated at a time (each later one needs the earlier). -Apply
# exits 2 with the exact fix; a dry run only NOTES it and continues, because the
# target list (names, env names, providers) is exactly what a user wants to see
# before the vault is wired - gating the listing on the vault would hide it.
$precondition = ''
$preconditionFix = @()
$vaultName = ''
$az = $null
if ([string]::IsNullOrWhiteSpace($VaultUri)) {
    $precondition = 'no Key Vault URI'
    $preconditionFix = @(
        'Pass -VaultUri https://<vault>.vault.azure.net/ or set AZURE_KEY_VAULT_URI (the vault',
        'infra/main.bicep provisions; scripts/bootstrap/azure-up.sh writes it to .helios/azure.env,',
        'the .ps1 twin to .helios/azure.env.ps1 - dot-source it).')
}
elseif ($VaultUri -notmatch '^https?://([^./]+)') {
    $precondition = "'$VaultUri' is not a Key Vault URI"
    $preconditionFix = @('Expected https://<vault>.vault.azure.net/ (pass -VaultUri or fix AZURE_KEY_VAULT_URI).')
}
else {
    $vaultName = $Matches[1]
    $az = Get-Command az -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $az) {
        $precondition = 'the Azure CLI (az) is not on PATH'
        $preconditionFix = @('Install it (https://aka.ms/azure-cli; pre-installed in Cloud Shell).')
    }
    else {
        # Capture-then-$LASTEXITCODE; the captured output is discarded (it names the account).
        $null = @(& $az.Source account show --output none 2>&1)
        if ($LASTEXITCODE -ne 0) {
            $precondition = 'az is not logged in (az account show failed)'
            $preconditionFix = @(
                'Log in first: scripts/bootstrap/connect-azure.sh (device code; az login --use-device-code),',
                'or in Cloud Shell simply open a new session.')
        }
    }
}
if ($precondition) {
    if ($Apply) {
        Write-Host "set-provider-secrets: FAILED PRECONDITION - $precondition."
        foreach ($line in $preconditionFix) { Write-Host $line }
        Write-Host 'Nothing was changed. Re-run without -Apply for a dry run that needs neither.'
        exit 2
    }
    Write-Host "set-provider-secrets: precondition missing - $precondition; the vault column below reads unknown (dry run continues, -Apply would exit 2)."
    foreach ($line in $preconditionFix) { Write-Host "  fix: $line" }
}
$vaultLabel = if ($vaultName) { "'$vaultName'" } else { '<not set>' }
$vaultArg = if ($vaultName) { $vaultName } else { '<vault>' }

# --- Existence probe by NAME ----------------------------------------------------------
# `secret show --query name` returns the name and nothing else; stderr is classified,
# never echoed (az error text is verbose but value-free; classification is enough).
# With a precondition missing there is nothing to probe, and the state says which.
function Get-SecretState {
    param([Parameter(Mandatory)][string]$Name)
    if ($precondition) { return "unknown ($precondition)" }
    $raw = @(& $az.Source keyvault secret show --vault-name $vaultName --name $Name --query name --output tsv 2>&1 | ForEach-Object { "$_" })
    $exit = $LASTEXITCODE
    $joined = $raw -join "`n"
    if ($exit -eq 0 -and $joined.Trim() -eq $Name) { return 'exists' }
    if ($joined -match 'SecretNotFound|was not found') { return 'absent' }
    if ($joined -match 'Forbidden|AuthorizationFailed|does not have secrets') { return 'forbidden (grant Key Vault Secrets Officer on the vault)' }
    return "unknown (az exited $exit; rerun the show command with --debug)"
}

$failures = [System.Collections.Generic.List[string]]::new()
$stored = 0
$skipped = 0

foreach ($target in $selected) {
    $secretName = $target.SecretName
    $envName = $target.EnvName
    Write-Host ''
    Write-Host ('-- {0} (env {1}; providers: {2}) --' -f $secretName, $envName, ($target.Providers -join ', '))
    $current = Get-SecretState -Name $secretName
    Write-Host "  vault ${vaultLabel}: $current"
    $envPresent = Test-EnvValue -Name $envName
    $sourceText = if ($FromEnv) { "env $envName (" + $(if ($envPresent) { 'present' } else { 'EMPTY - would skip' }) + ')' } else { 'masked prompt (Read-Host -AsSecureString)' }
    Write-Host "  source: $sourceText"
    $setCommand = "az keyvault secret set --vault-name $vaultArg --name $secretName --file <temp file holding the value; mode 600; deleted afterwards> --output none"
    $verifyCommand = "az keyvault secret show --vault-name $vaultArg --name $secretName --query name --output tsv"

    if (-not $Apply) {
        Write-Host "  [dry-run] would run: $setCommand"
        Write-Host "  [dry-run] then verify by name: $verifyCommand"
        continue
    }

    # --- acquire the value (memory only) ---
    $value = $null
    if ($FromEnv) {
        if (-not $envPresent) {
            Write-Host "  skipped: env $envName is empty (name checked only)"
            $skipped++
            continue
        }
        $value = [Environment]::GetEnvironmentVariable($envName)
    }
    else {
        if ([Console]::IsInputRedirected) {
            Write-Host '  skipped: no terminal for a masked prompt - use -FromEnv on a headless host'
            $skipped++
            continue
        }
        $secure = Read-Host -AsSecureString -Prompt "  value for $secretName (input hidden; Enter to skip)"
        $value = [System.Net.NetworkCredential]::new('', $secure).Password
        if ([string]::IsNullOrWhiteSpace($value)) {
            Write-Host '  skipped: empty input'
            $skipped++
            $value = $null
            continue
        }
    }

    # --- write through a 0600 temp file, never argv ---
    $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) ('helios-kv-' + [guid]::NewGuid().ToString('N'))
    try {
        # Created O_CREAT|O_EXCL with mode 0600 in ONE call (FileStreamOptions.UnixCreateMode,
        # .NET 7+, the same baseline SetUnixFileMode already needs): a create-then-chmod pair
        # leaves a umask-default (0644) window in the shared temp dir during which another
        # local user can open() the file and keep that descriptor across the chmod, then read
        # the value once it lands. CreateNew also refuses a pre-planted path of the same name.
        $fileOptions = [System.IO.FileStreamOptions]::new()
        $fileOptions.Mode = [System.IO.FileMode]::CreateNew
        $fileOptions.Access = [System.IO.FileAccess]::Write
        $fileOptions.Share = [System.IO.FileShare]::None
        if (-not $IsWindows) {
            $fileOptions.UnixCreateMode = [System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::UserWrite
        }
        $stream = [System.IO.File]::Open($tempPath, $fileOptions)
        try {
            # No BOM and no trailing newline: az --file stores the file content verbatim.
            $writer = [System.IO.StreamWriter]::new($stream, [System.Text.UTF8Encoding]::new($false))
            $writer.Write($value)
            $writer.Flush()
        }
        finally { $stream.Dispose() }
        Write-Host "  [apply] $setCommand"
        $null = @(& $az.Source keyvault secret set --vault-name $vaultName --name $secretName --file $tempPath --output none 2>&1)
        $setExit = $LASTEXITCODE
        if ($setExit -ne 0) {
            Write-Host "  [apply] FAILED (az exited $setExit; output withheld - it could carry the value)"
            $failures.Add("[$secretName] $setCommand")
            continue
        }
        $verified = Get-SecretState -Name $secretName
        if ($verified -eq 'exists') {
            Write-Host "  [apply] stored and verified by name: $secretName"
            $stored++
        }
        else {
            Write-Host "  [apply] stored, but the read-back by name reported '$verified' - replay recorded"
            $failures.Add("[$secretName] $verifyCommand")
        }
    }
    finally {
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force }
        $value = $null
    }
}

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "set-provider-secrets: $($failures.Count) target(s) FAILED - replay list (value comes from your masked prompt or env var, never from this output):"
    foreach ($f in $failures) { Write-Host "  $f" }
    exit 1
}
if ($Apply) {
    Write-Host "set-provider-secrets: complete - $stored stored and verified by name, $skipped skipped. Load them with: source scripts/bootstrap/load-env-from-keyvault.sh (bash) or . scripts/bootstrap/auto-login.ps1 (pwsh)."
}
elseif ($precondition) {
    Write-Host "set-provider-secrets: dry run complete - $($selected.Count) target(s) listed above; nothing was changed. Meet the precondition ($precondition) first, then re-run with -Apply (add -FromEnv on a headless host)."
}
else {
    Write-Host "set-provider-secrets: dry run complete - $($selected.Count) target(s) listed above; nothing was changed. Re-run with -Apply (add -FromEnv on a headless host)."
}
exit 0
