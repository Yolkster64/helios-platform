#Requires -Version 7
<#
.SYNOPSIS
One-command NON-INTERACTIVE auto-login: repair every credential lane that can be
repaired without a human, then export the provider keys the whole stack consumes into
the CURRENT PowerShell session — az, gh, codex (OpenAI), claude (Anthropic),
gh-models, and every SDK/REST consumer that reads the same env names. Zero prompts,
ever: anything that would need a browser or MFA is reported as an owner action, never
started.

.DESCRIPTION
The ACQUIRE-and-EXPORT companion of the report-only diagnostics
(scripts/bootstrap/auth-doctor.ps1 reports; scripts/verify/rest-connect.ps1 probes the
wire). This script deliberately MUTATES, in two well-defined places only:

  1. The az CLI profile — by delegating to `auth-doctor.ps1 -Apply`, whose contract is
     automatic NON-INTERACTIVE repair only (service principal from AZURE_CLIENT_ID/
     AZURE_TENANT_ID + secret/certificate, or managed identity). Nothing interactive
     is ever run; an MFA/device-code fix is only ever printed.
  2. This session's environment variables — Key Vault secrets are exported into the
     exact env names config/aihub.json declares, and a gh-derived token can light the
     gh-models lane. Values land ONLY in process memory ($env:*), never on disk,
     never in output.

DOT-SOURCE IT so the exports outlive the script:

    . scripts/bootstrap/auto-login.ps1

Run normally it still works, but the exports die with the child process — the summary
tells you which invocation you used. The whole implementation runs inside a function
scope, so dot-sourcing does NOT change the caller's StrictMode or
$ErrorActionPreference (review finding); on an internal failure a dot-sourced run
RETHROWS so the caller can detect the partial setup, while a normal run exits 1.
Scope hygiene: the helper symbols are removed from the caller's scope on every
path; the one unavoidable residue is the PARAMETER bindings (-Json and
-UseManagedIdentity), which overwrite (and cleanup then deletes) any caller
variable named $Json/$json or $UseManagedIdentity — do not rely on those names
surviving the call.

Chain (reuse-first — this script orchestrates, it does not reimplement):
  az lane        pwsh scripts/bootstrap/auth-doctor.ps1 -Apply -Json  → repaired/ready
                 or needs-owner (the one-time `az login --tenant ...` MFA +
                 setup-tenant.ps1 -OpsIdentity permanence path is printed verbatim).
                 -UseManagedIdentity is forwarded (review finding): a classic
                 IMDS-only VM exposes no IDENTITY_ENDPOINT / MSI_ENDPOINT, so the
                 doctor tries `az login --identity` there only when told to.
  Key Vault      only when the az lane is usable AND AZURE_KEY_VAULT_URI holds a real
                 value (the vault provisioned by infra/main.bicep): openai-api-key →
                 OPENAI_API_KEY (codex CLI + openai providers/SDKs), anthropic-api-key
                 → ANTHROPIC_API_KEY (claude CLI + anthropic provider),
                 github-models-token → GITHUB_MODELS_TOKEN (gh-models provider).
                 Same secret names as scripts/bootstrap/load-env-from-keyvault.sh
                 (the bash twin). Env vars carrying a NON-EMPTY value are never
                 clobbered; an empty/whitespace value counts as unset (review
                 finding — matching the bash twin's nonempty rule).
  gh-models      for EVERY enabled provider of type github-models on the public
                 endpoint whose configured apiKeyEnv (GITHUB_MODELS_TOKEN when
                 unset) is still effectively unset — a custom-baseUrl provider
                 never receives a GitHub credential: a raw GITHUB_TOKEN satisfies
                 the provider only when the wire PROVES models:read (X-OAuth-Scopes);
                 otherwise `gh auth token` is read env-cleared, probed the same way,
                 and exported to each such target — a proven token retires that
                 target's repairs, an unverifiable one (no scopes header, or an
                 injecting transport) is exported with the scope/vault repair left
                 standing, and a token proven to lack models:read (or rejected) is
                 NOT exported at all. A provider with no apiKeySecretName whose
                 variable is still unset gets a direct-key owner action. A variable
                 shared by a public AND a custom-baseUrl provider is mixed-owned and
                 never receives a GitHub credential either (the durable fix is
                 distinct apiKeyEnv names).
  apiKeyEnv      read exactly as ProviderFactory reads it: the per-type default
                 applies only when the property is absent/null; a declared-blank
                 name means the hub reads NO variable for that entry (it resolves
                 only its apiKeySecretName in-process; github-models then falls back
                 to GITHUB_TOKEN alone), so nothing is exported for it, and a blank
                 entry without any secret path is reported as an owner config fix.
                 A variable that enabled entries map to DIFFERENT Key Vault secrets
                 is a conflict: nothing is pulled into it (declaration order must
                 never choose a credential every sharer then reads) and the owner
                 action names the split — and stands even when the variable is
                 already set, since that value is exactly what every sharer would
                 read (the same rule covers a variable read by consumers of
                 different credential families). A profile with no providers section is a
                 valid CLI-only profile (AIHubOptions.Providers starts empty), not a
                 read failure; an explicitly selected profile the hub cannot load
                 aborts before the az lane runs.
  summary        which env NAMES were set this run, which lanes remain owner-gated.

Secrets policy (CLAUDE.md rule): secret values flow az → local variable → $env:NAME
and die there; no value is ever printed, logged, or written to a file. Names only in
every report line.

.PARAMETER Json
Emit one machine-readable rollup {script, generatedUtc, dotSourced, steps[],
exportedNames[], ownerActions[], exitCode} instead of the human report.

.PARAMETER UseManagedIdentity
Forwarded to auth-doctor.ps1 -Apply as its -UseManagedIdentity opt-in: attempt
`az login --identity` even when no IDENTITY_ENDPOINT / MSI_ENDPOINT is visible (a
classic IMDS-only Azure VM exposes neither). Still non-interactive; without it the az
lane on such a VM can only print the interactive login as an owner action, and the
Key Vault stage stays blocked behind it.

Exit contract: 0 = ran to completion (owner-gated lanes are reported, not failures);
1 = internal failure. Dot-sourced, exit codes are not asserted (exiting would kill
the caller's shell): completion is silent success and an internal failure RETHROWS.
#>
[CmdletBinding()]
param(
    [switch]$Json,

    [switch]$UseManagedIdentity
)

# Everything lives in this function so StrictMode and ErrorActionPreference are
# FUNCTION-scoped: dot-sourcing the script must never rewrite the caller's shell
# preferences (review finding). Environment exports are process-wide, so they still
# reach the dot-sourcing caller.
function Invoke-HeliosAutoLogin {
    param(
        [switch]$Json,
        [switch]$UseManagedIdentity,
        [bool]$DotSourced,
        [Parameter(Mandatory)][string]$RepoRoot
    )
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $steps = [System.Collections.Generic.List[object]]::new()
    $exportedNames = [System.Collections.Generic.List[string]]::new()
    # Owner actions carry the env var whose satisfaction retires them (review
    # finding): Env = the exact variable for actions this script composes ('' for
    # actions no export can retire), $null for auth-doctor's imported free text,
    # whose variable is recovered by an exact-identifier match at reconcile time.
    $ownerActions = [System.Collections.Generic.List[object]]::new()
    function Add-OwnerAction {
        param([Parameter(Mandatory)][string]$Text, [AllowNull()][AllowEmptyString()][string]$Env = '', [switch]$Imported)
        $ownerActions.Add([pscustomobject]@{ Text = $Text.Trim(); Env = $(if ($Imported) { $null } else { [string]$Env }) })
    }

    function Write-Report {
        param([string]$Line = '')
        if (-not $Json) { Write-Host $Line }
    }

    function Add-Step {
        param(
            [Parameter(Mandatory)][string]$Step,
            [Parameter(Mandatory)][ValidateSet('ok', 'exported', 'skipped', 'needs-owner', 'unavailable')][string]$State,
            [Parameter(Mandatory)][string]$Detail
        )
        $steps.Add([pscustomobject]@{ step = $Step; state = $State; detail = $Detail })
        Write-Report ('  {0,-14} {1,-12} {2}' -f $Step, $State, $Detail)
    }

    # Empty or whitespace counts as unset (review finding): CI shells commonly define
    # variables as '' — the bash twin (load-env-from-keyvault.sh) preserves only
    # nonempty values, and this script matches that rule everywhere.
    function Test-EnvValue {
        param([Parameter(Mandatory)][string]$Name)
        # .NET API, never the env: drive (review finding): a config-derived name such
        # as API_* would be expanded as a wildcard by the provider, while the hub reads
        # the literal name through Environment.GetEnvironmentVariable. Every read,
        # export, and removal of a config-derived name below uses the same API.
        return -not [string]::IsNullOrWhiteSpace([string][Environment]::GetEnvironmentVariable($Name))
    }
    # Environment-variable NAME semantics follow the OS (review finding): on Linux and
    # macOS MODEL_KEY and model_key are two variables and ProviderFactory reads each
    # literally; on Windows they are one. Every name comparison, set, and index below
    # uses this comparer — never PowerShell's case-insensitive -eq / -contains /
    # Group-Object / [ordered] hashtable, which would merge two Unix variables.
    $envNameComparer = if ($IsWindows) { [System.StringComparer]::OrdinalIgnoreCase } else { [System.StringComparer]::Ordinal }
    $envNameRegexOptions = if ($IsWindows) { [System.Text.RegularExpressions.RegexOptions]::IgnoreCase } else { [System.Text.RegularExpressions.RegexOptions]::None }
    function Test-EnvNameEquals { param([string]$A, [string]$B) return $envNameComparer.Equals($A, $B) }
    function New-EnvNameSet { return , [System.Collections.Generic.HashSet[string]]::new($envNameComparer) }
    # Distinct names in first-seen order under the OS comparer (Select-Object -Unique
    # is case-sensitive on every OS and would split one Windows variable in two).
    function Get-UniqueEnvNames {
        param([AllowEmptyCollection()][string[]]$Names = @())
        $seen = New-EnvNameSet
        $ordered = [System.Collections.Generic.List[string]]::new()
        foreach ($n in @($Names)) { if ($seen.Add($n)) { $ordered.Add($n) } }
        return $ordered.ToArray()
    }

    Write-Report '== HELIOS auto-login (non-interactive acquire + export; zero prompts) =='
    if (-not $DotSourced) {
        Write-Report '   NOTE: not dot-sourced — env exports die with this process. For your shell:  . scripts/bootstrap/auto-login.ps1'
    }
    Write-Report ''

    # --- 0. The active hub config, parsed FIRST -------------------------------------
    # AIHUB_CONFIG precedence (review finding): AIHubService.ResolveConfigPath gives
    # the env var precedence over the repo default, so when a custom/cloud profile
    # is selected these exports must follow it — otherwise auto-login configures a
    # hub other than the one that will actually run. Parsed before the az lane
    # (review finding): an explicitly selected profile the hub cannot load must
    # abort before auth-doctor -Apply mutates anything on its behalf.
    $aihubConfigExplicit = Test-EnvValue 'AIHUB_CONFIG'
    $aihubConfigPath = if ($aihubConfigExplicit) { ([string]$env:AIHUB_CONFIG).Trim() }
    else { Join-Path $RepoRoot 'config/aihub.json' }
    # The label auth-doctor uses for the same file, so shared action text dedupes.
    $aihubConfigLabel = if ($aihubConfigExplicit) { 'AIHUB_CONFIG' } else { 'config/aihub.json' }
    # Parse success is tracked apart from the providers table (review finding): a
    # valid CLI-only profile may omit `providers` entirely — AIHubOptions.Providers
    # starts as an empty dictionary, so the hub loads that profile and simply
    # instantiates no API provider from it. An absent (or JSON null) section is
    # therefore an EMPTY table, never a read failure; $aihubProviders stays $null
    # only when the file itself is missing, unparseable, or not a JSON object (the
    # hub binds the document to an object and fails the same way on anything else).
    $aihubParseOk = $false
    $aihubParsed = $null
    $aihubProviders = $null
    $aihubProvidersDeclared = $false
    $aihubProvidersNull = $false
    try {
        $aihubParsed = Get-Content -LiteralPath $aihubConfigPath -Raw | ConvertFrom-Json
        $aihubParseOk = ($aihubParsed -is [System.Management.Automation.PSCustomObject])
    }
    catch { }
    $aihubProvidersShape = ''
    if ($aihubParseOk) {
        $providersProp = $aihubParsed.PSObject.Properties['providers']
        # An EXPLICIT null is not an omitted section (review finding): System.Text.Json
        # assigns null over AIHubOptions.Providers' initializer and CreateAll then fails
        # enumerating it — the hub cannot start on that file, so neither may this run.
        $aihubProvidersNull = [bool]($null -ne $providersProp -and $null -eq $providersProp.Value)
        # Only a JSON OBJECT binds (review finding): AIHubOptions.Load deserializes the
        # section as Dictionary<string, ProviderOptions>, so an array, string, or number
        # there fails the hub exactly like null — and must abort here, before the az
        # lane can mutate anything on behalf of a hub that cannot start.
        if ($null -ne $providersProp -and $null -ne $providersProp.Value -and $providersProp.Value -isnot [System.Management.Automation.PSCustomObject]) {
            $aihubProvidersShape = if ($providersProp.Value -is [System.Array]) { 'an array' } else { "a $($providersProp.Value.GetType().Name)" }
        }
        $aihubProvidersDeclared = [bool]($null -ne $providersProp -and $null -ne $providersProp.Value -and -not $aihubProvidersShape)
        $aihubProviders = if ($aihubProvidersDeclared) { $aihubParsed.providers } else { [pscustomobject]@{} }
    }
    if ($aihubProvidersNull) {
        throw "the active config ($aihubConfigPath) declares `"providers`": null — ProviderFactory.CreateAll cannot enumerate a null providers table and the hub fails to start; omit the section for a CLI-only profile or declare an object; aborting before any lane runs"
    }
    if ($aihubProvidersShape) {
        throw "the active config ($aihubConfigPath) declares `"providers`" as $aihubProvidersShape, not a JSON object — AIHubOptions binds that section as a dictionary of providers and the hub fails to load the file; declare an object (or omit the section for a CLI-only profile); aborting before any lane runs"
    }
    if ($aihubParseOk -and $aihubProvidersDeclared) {
        # Every ENTRY must be an object too (review finding): the table binds as
        # Dictionary<string, ProviderOptions>, a JSON null deserializes as a null
        # entry, and ProviderFactory.CreateAll dereferences provider.Enabled on each —
        # the hub crashes on such a file, so no lane may run (or repair) on its behalf.
        foreach ($entryProp in $aihubProviders.PSObject.Properties) {
            if ($null -eq $entryProp.Value -or $entryProp.Value -isnot [System.Management.Automation.PSCustomObject]) {
                $entryShape = if ($null -eq $entryProp.Value) { 'null' } elseif ($entryProp.Value -is [System.Array]) { 'an array' } else { "a $($entryProp.Value.GetType().Name)" }
                throw "the active config ($aihubConfigPath) declares providers.$($entryProp.Name) as $entryShape, not an object — ProviderFactory.CreateAll dereferences every provider entry and the hub fails to start; remove the entry or declare an object; aborting before any lane runs"
            }
        }
    }
    # An EXPLICITLY selected profile that cannot be read is an internal failure
    # (review finding): the hub itself will fail to load that same file, so
    # silently exporting the built-in default mapping would configure a hub other
    # than the one selected — and report success doing it. The fallback in step 2
    # is reserved for the absent/unreadable REPO DEFAULT only.
    if ($aihubConfigExplicit -and -not $aihubParseOk) {
        throw "AIHUB_CONFIG selects '$aihubConfigPath' but it is missing, unparseable, or not a JSON object — fix the file or unset AIHUB_CONFIG; aborting before any lane runs instead of exporting the default profile's secrets"
    }
    if ($aihubParseOk -and -not $aihubProvidersDeclared) {
        Write-Report "  note: the active config ($aihubConfigPath) declares no providers section — the hub instantiates no API provider from it (CLI-only profile), so there is no credential to acquire for one"
    }

    # --- 1. az lane: delegate repair to auth-doctor -Apply (non-interactive only) ----
    $azUsable = $false
    $azLaneHadAction = $false
    $doctorPath = Join-Path $RepoRoot 'scripts/bootstrap/auth-doctor.ps1'
    if (Test-Path -LiteralPath $doctorPath) {
        # stdout ONLY: the -Json contract puts the report there, and merging stderr
        # (warnings, progress lines) would break the JSON parse (review finding —
        # the same lesson learn-fleet.ps1's capture already encodes).
        # The managed-identity opt-in is forwarded (review finding): on a classic
        # IMDS-only VM neither IDENTITY_ENDPOINT nor MSI_ENDPOINT exists, so the doctor
        # attempts `az login --identity` only when told to — without the switch the
        # vault stage would sit blocked behind an interactive-login action while a
        # non-interactive credential was available all along.
        $doctorArgs = @('-Apply', '-Json')
        if ($UseManagedIdentity) { $doctorArgs += '-UseManagedIdentity' }
        # The PowerShell application, resolved (review finding): an unqualified `pwsh`
        # fails when the host executable's directory is not on PATH and, in a
        # dot-sourcing caller, could resolve to a caller-defined function or alias.
        # setup-everything.ps1 pattern: the PATH application first, else this process.
        $pwshCommand = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        $pwshExe = if ($pwshCommand) { $pwshCommand.Source } else { [Environment]::ProcessPath }
        if (-not $pwshExe) { throw 'cannot locate a PowerShell 7 executable (pwsh not on PATH, host process path unknown) — the az lane cannot be established; aborting instead of reporting success' }
        $doctorLines = @(& $pwshExe -NoProfile -File $doctorPath @doctorArgs 2>$null | ForEach-Object { "$_" })
        $doctorExit = [int]$LASTEXITCODE
        $doctorReport = $null
        try { $doctorReport = ($doctorLines -join "`n") | ConvertFrom-Json } catch { }
        $azLane = $null
        if ($doctorReport -and $doctorReport.PSObject.Properties['lanes']) {
            $azLane = @($doctorReport.lanes | Where-Object { $_.lane -eq 'az' }) | Select-Object -First 1
        }
        if ($null -ne $azLane) {
            $azState = [string]$azLane.state
            $azUsable = $azState -in @('ready', 'repaired')
            # Carry the doctor's own detail through (review finding): 'unavailable'
            # means az is not installed — collapsing that to needs-owner with a bare
            # state name loses the installation guidance for both humans and JSON.
            $azLaneDetail = if ($azLane.PSObject.Properties['detail']) { [string]$azLane.detail } else { '' }
            $azDetail = "auth-doctor -Apply: az lane $azState" +
                $(if ($azLaneDetail) { " — $azLaneDetail" } else { '' })
            $azStepState = if ($azUsable) { 'ok' } elseif ($azState -eq 'unavailable') { 'unavailable' } else { 'needs-owner' }
            if (-not $azUsable -and $azLane.PSObject.Properties['ownerAction'] -and "$($azLane.ownerAction)".Trim()) {
                Add-OwnerAction -Text "$($azLane.ownerAction)" -Imported
                $azLaneHadAction = $true
            }
            Add-Step -Step 'az' -State $azStepState -Detail $azDetail
            # Surface the rest of the doctor's owner actions too — auto-login's summary
            # is meant to be the single list of what still needs a human.
            # A lane the doctor reports as 'disabled' (every consumer off in the active
            # config) never carries an action, and even if one slipped through it must
            # not be imported (review finding): the summary's contract is "only the
            # steps that need a human", and nothing instantiates a disabled lane.
            foreach ($lane in @($doctorReport.lanes)) {
                $laneState = if ($lane.PSObject.Properties['state']) { [string]$lane.state } else { '' }
                if ($lane.lane -ne 'az' -and $laneState -ne 'disabled' -and $lane.PSObject.Properties['ownerAction'] -and "$($lane.ownerAction)".Trim()) {
                    Add-OwnerAction -Text "$($lane.ownerAction)" -Imported
                }
            }
        }
        else {
            # An unparseable/failed auth-doctor is an INTERNAL failure, not a lane
            # state (review finding): converting it into an 'unavailable' step let
            # the run finish with exitCode 0 — a dot-sourced caller then continued
            # after a partial setup with neither the promised rethrow nor a
            # failure status. Throw so the outer handler propagates it.
            throw "auth-doctor -Apply produced no parseable az lane (exit $doctorExit) — az repair state unknown; aborting instead of reporting success"
        }
    }
    else {
        throw 'scripts/bootstrap/auth-doctor.ps1 not found in this checkout — the az lane cannot be established; aborting instead of reporting success'
    }

    # --- 2. Key Vault → env (the pwsh twin of load-env-from-keyvault.sh) ------------
    # SecretName is a Key Vault secret IDENTIFIER (which secret to fetch), never a
    # value — named so the code-checks security scanner's hardcoded-secret pattern
    # (`secret =` followed by a literal) does not false-positive on identifiers.
    # The pairs come from config/aihub.json (review finding): the hub's
    # SecretResolver honors each provider's apiKeyEnv/apiKeySecretName, so this
    # script reads the SAME source of truth — a hardcoded triplet would silently
    # stop configuring a provider the moment an operator renames its mapping.
    # Providers lacking either field are excluded on purpose (azure-openai, for
    # example, declares no vault custody and needs its own endpoint wiring).
    $vaultPairs = @()
    # apiKeyEnv exactly as ProviderFactory reads it (review finding): the per-type
    # default (`ApiKeyEnv ?? <default>`) applies ONLY when the property is absent or
    # JSON null. An explicitly blank/whitespace name is passed through unchanged, and
    # SecretResolver.Resolve reads NO environment variable for a blank name — only the
    # entry's apiKeySecretName, in-process. Normalizing blank to the default would
    # export into a variable the hub never reads and report the provider lit.
    # Returns $null for "absent → default applies", else the trimmed declared name
    # ('' = declared blank).
    function Get-DeclaredApiKeyEnv {
        param([Parameter(Mandatory)]$Provider)
        $prop = $Provider.PSObject.Properties['apiKeyEnv']
        if ($null -eq $prop -or $null -eq $prop.Value) { return $null }
        return ([string]$prop.Value).Trim()
    }
    # The public GitHub Models endpoint is exactly the HTTPS origin of models.github.ai
    # (review finding): the factory rejects a non-http(s) URL outright, and an http://
    # origin would carry the exported credential in cleartext — neither may receive a
    # GitHub token. Returns { Public; Note; Host }.
    function Test-PublicModelsOrigin {
        param([AllowEmptyString()][string]$BaseUrl = '')
        if ([string]::IsNullOrWhiteSpace($BaseUrl)) { return [pscustomobject]@{ Public = $true; Note = ''; Host = 'models.github.ai' } }
        $parsedOrigin = $null
        if (-not [uri]::TryCreate($BaseUrl.Trim(), [System.UriKind]::Absolute, [ref]$parsedOrigin)) {
            return [pscustomobject]@{ Public = $false; Note = 'not an absolute URL — ProviderFactory.CreateGitHubModels reports the provider unconfigured'; Host = '' }
        }
        $hostIsPublic = $parsedOrigin.Host.Equals('models.github.ai', [System.StringComparison]::OrdinalIgnoreCase)
        if ($parsedOrigin.Scheme -eq 'https' -and $hostIsPublic) { return [pscustomobject]@{ Public = $true; Note = ''; Host = $parsedOrigin.Host } }
        if ($parsedOrigin.Scheme -eq 'http' -and $hostIsPublic) { return [pscustomobject]@{ Public = $false; Note = 'cleartext http:// origin of the public host — a GitHub credential must not travel over it'; Host = $parsedOrigin.Host } }
        if ($parsedOrigin.Scheme -notin 'http', 'https') { return [pscustomobject]@{ Public = $false; Note = "'$($parsedOrigin.Scheme)' scheme — ProviderFactory.CreateGitHubModels reports the provider unconfigured (not an absolute http(s) URL)"; Host = $parsedOrigin.Host } }
        return [pscustomobject]@{ Public = $false; Note = ''; Host = $parsedOrigin.Host }
    }
    # Enabled CLI agents that read a FIXED variable (review finding): any enabled
    # cliAgents entry whose command leaf is `codex` reads OPENAI_API_KEY and one running
    # `claude` reads ANTHROPIC_API_KEY (the canonical name counts only for an entry
    # declaring no command) — auth-doctor's discovery rule. Unreadable config → none.
    function Get-CliOwnedEnvReaders {
        $found = [System.Collections.Generic.List[object]]::new()
        if (-not $aihubParseOk -or -not $aihubParsed.PSObject.Properties['cliAgents'] -or $null -eq $aihubParsed.cliAgents) { return $found.ToArray() }
        foreach ($agent in @($aihubParsed.cliAgents)) {
            if ($null -eq $agent) { continue }
            if ($agent.PSObject.Properties['enabled'] -and $agent.enabled -eq $false) { continue }
            $cmd = if ($agent.PSObject.Properties['command'] -and $null -ne $agent.command) { ([string]$agent.command).Trim() } else { '' }
            $leaf = ''
            if ($cmd) { try { $leaf = [System.IO.Path]::GetFileNameWithoutExtension($cmd) } catch { $leaf = $cmd } }
            $agentName = if ($agent.PSObject.Properties['name'] -and $null -ne $agent.name) { ([string]$agent.name).Trim() } else { '' }
            $key = if ($leaf) { $leaf.ToLowerInvariant() } elseif (-not $cmd) { $agentName.ToLowerInvariant() } else { '' }
            if ($key -eq 'codex') { $found.Add([pscustomobject]@{ Name = $agentName; Type = 'codex-cli'; Family = 'openai'; Env = 'OPENAI_API_KEY' }) }
            elseif ($key -in 'claude', 'claude-cli') { $found.Add([pscustomobject]@{ Name = $agentName; Type = 'claude-cli'; Family = 'anthropic'; Env = 'ANTHROPIC_API_KEY' }) }
        }
        return $found.ToArray()
    }
    # Entries whose apiKeyEnv is declared blank: no variable exists to export into,
    # so they are reported (and, without a secret path, handed to the owner as the
    # config defect they are) instead of being silently defaulted.
    $blankEnvProviders = [System.Collections.Generic.List[object]]::new()
    # Providers that read a key but declare NO apiKeySecretName (review finding): no
    # vault path exists for them, so when their variable is still unset after every
    # rung the only repair is to set it directly — and the summary must say so.
    # azure-openai is deliberately not in this list: ProviderFactory falls back to
    # Entra ID (DefaultAzureCredential) when its key is absent, so an unset key is a
    # supported state there, not a defect.
    $directKeyProviders = [System.Collections.Generic.List[object]]::new()
    # Every enabled keyed entry that reads a variable, by variable (review finding):
    # the GitHub-credential rule in step 3 must see readers of OTHER types too — an
    # openai entry sharing a github-models entry's variable would receive the gh
    # export through ProviderFactory.CreateAll exactly like a custom endpoint.
    $envReaders = [System.Collections.Generic.Dictionary[string, object]]::new($envNameComparer)
    # Variables that enabled entries map to DIFFERENT Key Vault secrets (see below).
    $conflictingEnvs = @()
    $conflictingEnvSet = New-EnvNameSet
    # Variables read by consumers of DIFFERENT credential families (see below).
    $incompatibleEnvSet = New-EnvNameSet
    if ($null -ne $aihubProviders) {
        # Keyed "<secret> -> <variable>" under the OS name comparer (review finding);
        # Key Vault secret names are case-insensitive and are folded to lower case.
        $pairIndex = [System.Collections.Generic.Dictionary[string, object]]::new($envNameComparer)
        foreach ($provProp in $aihubProviders.PSObject.Properties) {
            $prov = $provProp.Value
            if ($null -eq $prov) { continue }
            # ProviderFactory.CreateAll excludes disabled providers (review
            # finding): a lane the hub will not instantiate must not have its
            # credential pulled into the process.
            if ($prov.PSObject.Properties['enabled'] -and $prov.enabled -eq $false) { continue }
            $provType = if ($prov.PSObject.Properties['type']) { ([string]$prov.type).Trim().ToLowerInvariant() } else { '' }
            $providerSecretName = ''
            if ($prov.PSObject.Properties['apiKeySecretName']) { $providerSecretName = ([string]$prov.apiKeySecretName).Trim() }
            $declaredEnv = Get-DeclaredApiKeyEnv $prov
            # The factory's per-type default applies when an entry declares no
            # apiKeyEnv (review finding): CreateOpenAi/AnthropicAgent/CreateGitHubModels/
            # CreateAzureOpenAi each resolve `ApiKeyEnv ?? <default>` with the entry's
            # apiKeySecretName, so a secret-only entry is still a live vault pair —
            # but ONLY for an absent/null property, never for a declared-blank one.
            $envName = if ($null -eq $declaredEnv) {
                switch ($provType) {
                    'openai' { 'OPENAI_API_KEY' }
                    'anthropic' { 'ANTHROPIC_API_KEY' }
                    'github-models' { 'GITHUB_MODELS_TOKEN' }
                    'azure-openai' { 'AZURE_OPENAI_API_KEY' }
                    default { '' }
                }
            }
            else { $declaredEnv }
            if ($null -ne $declaredEnv -and $declaredEnv -eq '') {
                # Declared blank (review finding): the keyed types are reported below
                # (github-models in step 3); keyless types read no key either way.
                if ($provType -in 'openai', 'anthropic', 'github-models', 'azure-openai') {
                    $blankEnvProviders.Add([pscustomobject]@{ Name = $provProp.Name; Type = $provType; SecretName = $providerSecretName })
                }
                continue
            }
            if ([string]::IsNullOrWhiteSpace($envName)) { continue }   # keyless types (ollama, azure-foundry-agent)
            # Credential FAMILY (review finding): which service's key this reader expects —
            # one per API type, 'github' for the public Models origin, one per custom host.
            $provBaseUrl = if ($prov.PSObject.Properties['baseUrl'] -and $null -ne $prov.baseUrl) { ([string]$prov.baseUrl).Trim() } else { '' }
            $readerFamily = if ($provType -eq 'github-models') {
                $readerOrigin = Test-PublicModelsOrigin -BaseUrl $provBaseUrl
                if ($readerOrigin.Public) { 'github' } else { "custom-endpoint:$($readerOrigin.Host)" }
            }
            else { $provType }
            if (-not $envReaders.ContainsKey($envName)) { $envReaders[$envName] = [System.Collections.Generic.List[object]]::new() }
            $envReaders[$envName].Add([pscustomobject]@{ Name = $provProp.Name; Type = $provType; Family = $readerFamily })
            if ([string]::IsNullOrWhiteSpace($providerSecretName)) {
                if ($provType -in 'openai', 'anthropic', 'github-models' -and -not @($directKeyProviders | Where-Object { Test-EnvNameEquals $_.Env $envName }).Count) {
                    $directKeyProviders.Add([pscustomobject]@{ Name = $provProp.Name; Type = $provType; Env = $envName })
                }
                continue
            }
            $pairKey = "$($providerSecretName.ToLowerInvariant()) -> $envName"
            if (-not $pairIndex.ContainsKey($pairKey)) {
                $pairIndex[$pairKey] = [pscustomobject]@{
                    SecretName = $providerSecretName
                    Env        = $envName
                    Consumers  = [System.Collections.Generic.List[string]]::new()
                }
            }
            $pairIndex[$pairKey].Consumers.Add($provProp.Name)
        }
        # CLI-owned variables join the reader map (review finding): an enabled codex
        # agent reads the fixed OPENAI_API_KEY and an enabled claude agent reads
        # ANTHROPIC_API_KEY (auth-doctor's CLI-half rule), so a Models entry pointed at
        # either name shares it with a non-GitHub consumer and never gets the gh export.
        foreach ($cliReader in @(Get-CliOwnedEnvReaders)) {
            if (-not $envReaders.ContainsKey($cliReader.Env)) { $envReaders[$cliReader.Env] = [System.Collections.Generic.List[object]]::new() }
            $envReaders[$cliReader.Env].Add([pscustomobject]@{ Name = $cliReader.Name; Type = $cliReader.Type; Family = $cliReader.Family })
        }
        # Incompatible sharing (review finding): a variable read by consumers of
        # DIFFERENT credential families (OpenAI, Anthropic, Azure OpenAI, the public
        # GitHub Models origin, each custom endpoint) can never hold one value valid for
        # all of them — a vault export into it would hand one service's key to another
        # through SecretResolver's environment-first rule, whatever the secret mappings
        # say. Nothing is pulled or exported into such a variable; the repair is
        # distinct names (worded like auth-doctor's action, so the summary dedupes).
        foreach ($sharedEnv in @($envReaders.Keys)) {
            $families = @($envReaders[$sharedEnv] | ForEach-Object { $_.Family } | Select-Object -Unique)
            if ($families.Count -lt 2) { continue }
            [void]$incompatibleEnvSet.Add($sharedEnv)
            $readerText = (@($envReaders[$sharedEnv] | ForEach-Object { "'$($_.Name)' ($($_.Type))" }) -join ', ')
            $readerNames = (@($envReaders[$sharedEnv] | ForEach-Object { $_.Name }) -join ',')
            if (Test-EnvValue $sharedEnv) {
                Add-Step -Step $sharedEnv -State 'skipped' -Detail "already holds a value in this session — never clobbered; note: it is read by consumers of different credential families ($readerText), which cannot all accept one value — ProviderFactory hands this one value to every sharer, so give them distinct apiKeyEnv names"
            }
            else {
                Add-Step -Step $sharedEnv -State 'needs-owner' -Detail "read by consumers of different credential families ($readerText) — no single value is valid for all of them, and an export would hand one service's credential to another through SecretResolver's environment-first rule; nothing is pulled or exported into it"
            }
            # The split action stands whether or not the variable is preset (review
            # finding): a value already in the session is exactly the credential
            # ProviderFactory then supplies to BOTH services, so satisfaction of the
            # variable is not satisfaction of the defect — and the reconcile below
            # never retires an action for an incompatible variable either.
            Add-OwnerAction -Text "give the consumers sharing $sharedEnv distinct apiKeyEnv names in ${aihubConfigLabel} ($readerNames) — they read credentials for different services"
        }
        # Conflicting secret→variable mappings (review finding): two enabled entries
        # naming DIFFERENT Key Vault secrets for the SAME variable would let
        # declaration order choose the credential — the first pull populates the
        # variable, the never-clobber rule skips the rest, and SecretResolver's
        # environment-first rule then hands that one value to every sharer, which
        # may send it to the wrong service. Nothing is pulled into such a variable;
        # the repair is distinct apiKeyEnv names (or one shared secret). A variable
        # already reported as incompatible is not reported twice.
        # Group-Object is case-insensitive unless told otherwise — the OS rule applies
        # to the variable names; secret names are folded (Key Vault ignores case).
        $conflictGroups = @($pairIndex.Values | Group-Object -Property Env -CaseSensitive:(-not $IsWindows) |
            Where-Object { @($_.Group | ForEach-Object { $_.SecretName.ToLowerInvariant() } | Select-Object -Unique).Count -gt 1 })
        foreach ($conflict in $conflictGroups) {
            if ($incompatibleEnvSet.Contains([string]$conflict.Name)) { continue }
            $conflictingEnvs += [string]$conflict.Name
            [void]$conflictingEnvSet.Add([string]$conflict.Name)
            $mapping = (@($conflict.Group | ForEach-Object { "'$($_.SecretName)' <- $(@($_.Consumers) -join ', ')" }) -join ' vs ')
            if (Test-EnvValue $conflict.Name) {
                Add-Step -Step $conflict.Name -State 'skipped' -Detail "already holds a value in this session — never clobbered; note: enabled providers map DIFFERENT Key Vault secrets to it ($mapping), so every sharer reads this one value — give them distinct apiKeyEnv names"
            }
            else {
                Add-Step -Step $conflict.Name -State 'needs-owner' -Detail "enabled providers map DIFFERENT Key Vault secrets to the same variable ($mapping) — SecretResolver prefers the environment, so whichever secret were pulled first would be handed to every sharer and could reach the wrong service; nothing was pulled into it"
            }
            # Same wording as auth-doctor's lane action (the step above carries the
            # mapping), so the summary's unique filter collapses the two into one. Added
            # on both branches (review finding): a preset value is the very credential
            # every sharer then reads, so it never retires the config repair.
            $conflictNames = @($conflict.Group | ForEach-Object { @($_.Consumers) } | Select-Object -Unique) -join ','
            Add-OwnerAction -Text "give providers.{$conflictNames} distinct apiKeyEnv names in ${aihubConfigLabel} (or one shared apiKeySecretName)"
        }
        foreach ($entry in @($pairIndex.Values | Where-Object { -not $conflictingEnvSet.Contains($_.Env) -and -not $incompatibleEnvSet.Contains($_.Env) })) {
            # The agent CLIs read two of these env names directly — that fact is
            # not in config, so it rides along as a fixed hint.
            $cliHint = switch ($entry.Env) {
                'OPENAI_API_KEY' { ' + codex CLI' }
                'ANTHROPIC_API_KEY' { ' + claude CLI' }
                default { '' }
            }
            $vaultPairs += [pscustomobject]@{
                SecretName = $entry.SecretName
                Env        = $entry.Env
                Lights     = (($entry.Consumers -join ', ') + $cliHint + ' — per config/aihub.json')
            }
        }
        # Blank-apiKeyEnv entries of the vault-capable types (review finding). The
        # github-models ones are settled in step 3 (GITHUB_TOKEN is the hub's only
        # fallback for them); the rest are settled here: with an apiKeySecretName the
        # hub resolves that secret itself, in-process, and azure-openai falls back to
        # Entra ID either way — without any secret path the entry can never be
        # configured, which only a config edit fixes, so it is an owner action.
        foreach ($blank in @($blankEnvProviders | Where-Object { $_.Type -ne 'github-models' })) {
            $blankStep = "provider:$($blank.Name)"
            $blankWhy = "declares an explicitly blank apiKeyEnv — ProviderFactory passes it through (the $($blank.Type) default applies only when the property is absent) and SecretResolver reads no environment variable for a blank name, so nothing auto-login exports can light it"
            if ($blank.SecretName) {
                $vaultUriNote = if (Test-EnvValue 'AZURE_KEY_VAULT_URI') { '' } else { ' — AZURE_KEY_VAULT_URI is unset in this session, so that in-process pull cannot happen here' }
                Add-Step -Step $blankStep -State 'skipped' -Detail "$blankWhy; the hub resolves Key Vault secret '$($blank.SecretName)' itself, in-process, under AZURE_KEY_VAULT_URI$vaultUriNote"
            }
            elseif ($blank.Type -eq 'azure-openai') {
                Add-Step -Step $blankStep -State 'skipped' -Detail "$blankWhy; with no apiKeySecretName either, CreateAzureOpenAi uses Entra ID (DefaultAzureCredential) — a supported state, not a defect"
            }
            else {
                Add-Step -Step $blankStep -State 'needs-owner' -Detail "$blankWhy, and it declares no apiKeySecretName either — no credential path exists for it"
                # Same wording and config label as auth-doctor's lane action, so the
                # summary's unique filter collapses the two into one line.
                $blankDefault = switch ($blank.Type) { 'openai' { 'OPENAI_API_KEY' } 'anthropic' { 'ANTHROPIC_API_KEY' } default { 'AZURE_OPENAI_API_KEY' } }
                Add-OwnerAction -Text "fix providers.{$($blank.Name)}.apiKeyEnv in ${aihubConfigLabel}: set a variable name (or remove the property to use $blankDefault) and/or add apiKeySecretName"
            }
        }
    }
    if ($null -eq $aihubProviders -and @($vaultPairs).Count -eq 0) {
        # Stated fallback, never silent — and ONLY for an unreadable REPO DEFAULT
        # config (the explicit AIHUB_CONFIG case threw above). A config that
        # parsed fine but declares zero enabled vault-backed providers is a
        # deliberate profile (review finding): pulling the built-in triplet for it
        # would export credentials for lanes that hub will never instantiate.
        Write-Report '  note: config/aihub.json unreadable — falling back to the built-in secret/env mapping'
        $vaultPairs = @(
            [pscustomobject]@{ SecretName = 'openai-api-key'; Env = 'OPENAI_API_KEY'; Lights = 'codex CLI + openai/openai-codex providers & SDKs (fallback mapping)' }
            [pscustomobject]@{ SecretName = 'anthropic-api-key'; Env = 'ANTHROPIC_API_KEY'; Lights = 'claude CLI + anthropic provider (fallback mapping)' }
            [pscustomobject]@{ SecretName = 'github-models-token'; Env = 'GITHUB_MODELS_TOKEN'; Lights = 'gh-models provider (fallback mapping)' }
        )
    }
    elseif (@($vaultPairs).Count -eq 0) {
        Write-Report '  note: the active config declares no enabled vault-backed providers — nothing to pull from Key Vault'
    }
    # GitHub Models TARGETS (review findings): every enabled provider of TYPE
    # github-models is one — ProviderFactory.CreateAll instantiates each entry,
    # dispatching on provider.type, and CreateGitHubModels reads each entry's
    # CONFIGURED apiKeyEnv (GITHUB_MODELS_TOKEN when unset), so a hardcoded name or a
    # single "chosen" provider would leave a sibling unconfigured. A parsed config
    # with no such provider yields no target (nothing to instantiate); only the
    # unreadable-config fallback keeps the built-in target. A target whose baseUrl
    # is a CUSTOM endpoint is kept for its Key Vault pull but never receives a
    # GitHub credential (GITHUB_TOKEN / the gh keyring) — that would hand a GitHub
    # token to a non-GitHub service. The per-target vault clause in repair guidance
    # follows the entry's apiKeySecretName (a repair naming another secret can never
    # light the lane; no secret name means no vault path and the clause is omitted).
    $ghModelsTargets = [System.Collections.Generic.List[object]]::new()
    if ($null -eq $aihubProviders) {
        $ghModelsTargets.Add([pscustomobject]@{ Name = 'github-models'; Owners = @('github-models'); PublicOwners = @('github-models'); OtherReaders = @(); Env = 'GITHUB_MODELS_TOKEN'; SecretName = 'github-models-token'; Public = $true; Mixed = $false; SkipReason = '' })
    }
    else {
        # Pass 1 — one row per enabled github-models entry that reads a variable (a
        # declared-blank apiKeyEnv has none to export into and is settled in step 3).
        $ghModelsEntries = [System.Collections.Generic.List[object]]::new()
        foreach ($ghProp in $aihubProviders.PSObject.Properties) {
            $ghProv = $ghProp.Value
            if ($null -eq $ghProv -or -not $ghProv.PSObject.Properties['type'] -or
                -not ([string]$ghProv.type).Trim().Equals('github-models', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            if ($ghProv.PSObject.Properties['enabled'] -and $ghProv.enabled -eq $false) { continue }
            $ghDeclared = Get-DeclaredApiKeyEnv $ghProv
            if ($null -ne $ghDeclared -and $ghDeclared -eq '') { continue }
            $ghEnv = if ($null -eq $ghDeclared) { 'GITHUB_MODELS_TOKEN' } else { $ghDeclared }
            $ghSecret = if ($ghProv.PSObject.Properties['apiKeySecretName']) { ([string]$ghProv.apiKeySecretName).Trim() } else { '' }
            $ghBaseUrl = if ($ghProv.PSObject.Properties['baseUrl']) { ([string]$ghProv.baseUrl).Trim() } else { '' }
            # Public means the exact HTTPS origin (review finding) — Test-PublicModelsOrigin.
            $ghOrigin = Test-PublicModelsOrigin -BaseUrl $ghBaseUrl
            $ghModelsEntries.Add([pscustomobject]@{ Name = $ghProp.Name; Env = $ghEnv; SecretName = $ghSecret; Public = $ghOrigin.Public; Note = $ghOrigin.Note })
        }
        # Pass 2 — group by variable only AFTER every entry's endpoint ownership is
        # known (review finding): a public entry listed before a custom-baseUrl entry
        # sharing its apiKeyEnv used to win the dedupe, and the GitHub credential
        # exported for the public one was then handed by ProviderFactory.CreateAll to
        # the custom endpoint as well. A variable with MIXED ownership is one target
        # that never receives a GitHub credential; only its Key Vault pull (or a
        # direct export) applies, and the durable repair is distinct apiKeyEnv names.
        foreach ($ghEnvName in @(Get-UniqueEnvNames -Names @($ghModelsEntries | ForEach-Object { $_.Env }))) {
            $owners = @($ghModelsEntries | Where-Object { Test-EnvNameEquals $_.Env $ghEnvName })
            $ownerNames = @($owners | ForEach-Object { $_.Name })
            $publicOwners = @($owners | Where-Object { $_.Public } | ForEach-Object { $_.Name })
            $customOwners = @($owners | Where-Object { -not $_.Public } | ForEach-Object { $_.Name })
            # Readers of OTHER keyed types (review finding, same class as the custom
            # endpoint): an openai/anthropic/azure-openai entry sharing the variable
            # would receive the GitHub credential too; a variable with conflicting
            # secret mappings is already a reported defect and gets nothing either.
            $foreignReaders = @()
            if ($envReaders.ContainsKey($ghEnvName)) {
                $foreignReaders = @($envReaders[$ghEnvName] | Where-Object { $_.Type -ne 'github-models' } | ForEach-Object { "'$($_.Name)' (type $($_.Type))" })
            }
            $isConflict = $conflictingEnvSet.Contains($ghEnvName)
            $isIncompatible = $incompatibleEnvSet.Contains($ghEnvName)
            # The vault clause follows the first apiKeySecretName declared among the
            # sharers (a repair naming another secret can never light the lane).
            $targetSecret = @($owners | ForEach-Object { $_.SecretName } | Where-Object { $_ }) | Select-Object -First 1
            if (-not $targetSecret) { $targetSecret = '' }
            $quotedPublic = (@($publicOwners | ForEach-Object { "'$_'" }) -join ', ')
            $quotedCustom = (@($customOwners | ForEach-Object { "'$_'" }) -join ', ')
            $customNotes = @($owners | Where-Object { -not $_.Public -and $_.Note } | ForEach-Object { "'$($_.Name)': $($_.Note)" })
            if ($customNotes.Count -gt 0) { $quotedCustom += " ($($customNotes -join '; '))" }
            $otherReaders = @()
            if ($customOwners.Count -gt 0) { $otherReaders += "custom-baseUrl github-models provider(s) $quotedCustom" }
            if ($foreignReaders.Count -gt 0) { $otherReaders += "provider(s) $($foreignReaders -join ', ') of another type" }
            if ($isConflict) { $otherReaders += 'entries with conflicting Key Vault secret mappings (see its step above)' }
            if ($isIncompatible -and $foreignReaders.Count -eq 0 -and $customOwners.Count -eq 0) { $otherReaders += 'consumers of a different credential family (see its step above)' }
            $isMixed = ($publicOwners.Count -gt 0 -and $otherReaders.Count -gt 0)
            $isPublic = ($otherReaders.Count -eq 0)
            $ghSkip = if ($isMixed) {
                "$ghEnvName is read by public github-models provider(s) $quotedPublic and also by $($otherReaders -join '; ') — a GitHub credential exported into it would be handed by ProviderFactory.CreateAll to a non-GitHub endpoint too, so GITHUB_TOKEN and the gh keyring are never exported for it; only its Key Vault pull (or setting $ghEnvName directly) applies, and the durable fix is distinct apiKeyEnv names"
            }
            elseif (-not $isPublic) {
                "provider(s) $quotedCustom (type github-models) point at a custom baseUrl — GITHUB_TOKEN and the gh keyring are GitHub credentials and are never exported for a non-GitHub endpoint; only its Key Vault pull (or setting $ghEnvName directly) applies"
            }
            else { '' }
            $ghModelsTargets.Add([pscustomobject]@{ Name = $ownerNames[0]; Owners = $ownerNames; PublicOwners = $publicOwners; OtherReaders = $otherReaders; Env = $ghEnvName; SecretName = $targetSecret; Public = $isPublic; Mixed = $isMixed; SkipReason = $ghSkip })
        }
    }
    $ghModelsPublicTargets = @($ghModelsTargets | Where-Object { $_.Public })
    $ghModelsPublicEnvs = @($ghModelsPublicTargets | ForEach-Object { $_.Env })
    $ghModelsMixedEnvs = @($ghModelsTargets | Where-Object { $_.Mixed } | ForEach-Object { $_.Env })
    # Membership under the OS name comparer (never -contains).
    $ghModelsPublicEnvSet = New-EnvNameSet
    foreach ($publicEnvName in $ghModelsPublicEnvs) { [void]$ghModelsPublicEnvSet.Add($publicEnvName) }
    $ghModelsMixedEnvSet = New-EnvNameSet
    foreach ($mixedEnvName in $ghModelsMixedEnvs) { [void]$ghModelsMixedEnvSet.Add($mixedEnvName) }
    $vaultUri = if (Test-EnvValue 'AZURE_KEY_VAULT_URI') { ([string]$env:AZURE_KEY_VAULT_URI).Trim() } else { '' }
    # -CommandType Application (review finding): a dot-sourcing caller may carry an
    # `az` alias/function whose .Source is not an invocable path — resolve the real
    # executable only, as the verifier and auth doctor do.
    # First PATH hit only (see the gh lookup below for the duplicate-name failure).
    $azCmd = Get-Command az -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    # Unresolved pairs FIRST (review finding): when every configured provider env
    # already holds a value, or the profile declares no enabled vault-backed
    # providers, the vault stage has nothing to acquire — demanding a vault URI
    # (and adding a human action for it) would leave the "only steps that need
    # a human" list non-empty for an already-satisfied configuration.
    $unresolvedPairs = @($vaultPairs | Where-Object { -not (Test-EnvValue $_.Env) })
    if (@($unresolvedPairs).Count -eq 0) {
        $nothingToPullWhy = if (@($vaultPairs).Count -eq 0) { 'the active config declares no enabled vault-backed providers' }
        else { 'every configured provider env already holds a value in this session (never clobbered)' }
        Add-Step -Step 'keyvault' -State 'skipped' -Detail "$nothingToPullWhy — nothing to pull, vault prerequisite not required"
    }
    elseif (-not $azUsable) {
        # The prerequisite is an owner action in its own right (review finding): the
        # doctor's az lane reports 'unavailable' with NO action when az is absent, so
        # the consolidated list would otherwise omit the one step every pull needs
        # while this step told the reader to look there. When the doctor DID supply
        # an az repair (MFA re-login, service-principal switch), that imported action
        # is the repair and is only referenced, never duplicated.
        $pendingPullsText = (@($unresolvedPairs | ForEach-Object { "'$($_.SecretName)' -> $($_.Env)" }) -join ', ')
        if ($azState -eq 'unavailable') {
            $azInstallAction = "install the Azure CLI (bash scripts/bootstrap/cloud-shell-setup.sh, or https://aka.ms/azure-cli) and re-run auto-login — auth-doctor -Apply then repairs the az lane non-interactively where a service principal or certificate is configured (setup-tenant.ps1 -OpsIdentity), or prints the exact one-time az login command; until then the Key Vault pulls $pendingPullsText cannot run"
            Add-Step -Step 'keyvault' -State 'unavailable' -Detail "az (Azure CLI) is not on PATH — the Key Vault pulls $pendingPullsText need an authenticated az; $azInstallAction"
            Add-OwnerAction -Text $azInstallAction
        }
        else {
            $azRepairRef = if ($azLaneHadAction) { "the imported az-lane owner action is the repair" } else { "repair the az lane first (auth-doctor -Apply reported '$azState')" }
            Add-Step -Step 'keyvault' -State 'needs-owner' -Detail "az lane is $azState — the Key Vault pulls $pendingPullsText need an authenticated az; $azRepairRef, then re-run auto-login"
            if (-not $azLaneHadAction) { Add-OwnerAction -Text "repair the az lane (auth-doctor -Apply reported '$azState': $azLaneDetail), then re-run auto-login so it can pull $pendingPullsText" }
        }
    }
    elseif (-not $vaultUri) {
        Add-Step -Step 'keyvault' -State 'skipped' -Detail ('AZURE_KEY_VAULT_URI is not set (name checked only) — provisioned by infra/main.bicep; ' +
            'azure-up.sh writes .helios/azure.env (bash) and azure-up.ps1 writes .helios/azure.env.ps1 (PowerShell)')
        # Both shells get a working remediation (review finding): this script is
        # dot-sourced from PowerShell, where bash `source`/`export` do nothing.
        Add-OwnerAction -Text 'set AZURE_KEY_VAULT_URI so auto-login can pull provider keys — PowerShell: . .helios/azure.env.ps1 (or $env:AZURE_KEY_VAULT_URI = "https://<vault>.vault.azure.net/"); bash: source .helios/azure.env'
    }
    elseif (-not $azCmd) {
        Add-Step -Step 'keyvault' -State 'unavailable' -Detail 'az CLI not on PATH'
    }
    else {
        # A malformed AZURE_KEY_VAULT_URI is a configuration problem, not an internal
        # failure — the [uri] cast throws on scheme-less/garbage values (review
        # finding), so it is guarded into a skipped step instead of aborting the run.
        # Strict shape too (review finding): any parseable https host used to pass,
        # so a stray value like https://example.com/ derived a vault named 'example',
        # ran az against it, and told the owner to populate the WRONG vault. Only
        # https plus a Key Vault hostname — <vault>.vault.<public or sovereign cloud
        # suffix> — derives a name; anything else is reported as the URI problem it is.
        $vaultName = ''
        $vaultUriParsed = $null
        try { $vaultUriParsed = [uri]$vaultUri } catch { }
        if ($null -ne $vaultUriParsed -and $vaultUriParsed.Scheme -eq 'https' -and
            $vaultUriParsed.Host -match '^(?<vault>[A-Za-z0-9-]{3,24})\.vault\.(azure\.net|azure\.cn|usgovcloudapi\.net|microsoftazure\.de)$') {
            $vaultName = $Matches['vault']
        }
        if (-not $vaultName) {
            Add-Step -Step 'keyvault' -State 'skipped' -Detail 'AZURE_KEY_VAULT_URI is set but is not an https://<vault>.vault.azure.net/ Key Vault URI (sovereign suffixes azure.cn, usgovcloudapi.net, microsoftazure.de also accepted) — fix the value; nothing was pulled and no vault was contacted'
            Add-OwnerAction -Text 'fix AZURE_KEY_VAULT_URI: it is set but is not an https://<vault>.vault.azure.net/ (or sovereign-cloud) Key Vault URI'
        }
        else {
            # Identity pinning (review finding): auth-doctor -Apply returns ready on
            # ANY healthy cached az login before reaching its service-principal
            # repair, so a developer login can mask the configured workload identity —
            # and the developer may lack the vault's RBAC grant that the ops service
            # principal holds. The cached identity is an identifier, never a secret:
            # detect the mismatch up front, and if a pull then fails, report the
            # exact non-interactive switch command instead of a generic RBAC shrug.
            $cachedAzIdentity = ''
            $azIdentityMismatch = $false
            if (Test-EnvValue 'AZURE_CLIENT_ID') {
                $acctLines = @(& $azCmd.Source account show --query user.name --output tsv --only-show-errors 2>$null)
                if ([int]$LASTEXITCODE -eq 0) { $cachedAzIdentity = (@($acctLines) -join '').Trim() }
                if ($cachedAzIdentity -and $cachedAzIdentity -ne ([string]$env:AZURE_CLIENT_ID).Trim()) {
                    $azIdentityMismatch = $true
                    Add-Step -Step 'az-identity' -State 'ok' -Detail ("cached az login is '$cachedAzIdentity', not the configured AZURE_CLIENT_ID workload identity — vault pulls proceed under the cached identity, whose Key Vault RBAC may differ")
                }
            }
            $anyPullFailed = $false
            foreach ($pair in $vaultPairs) {
                if (Test-EnvValue $pair.Env) {
                    Add-Step -Step $pair.Env -State 'skipped' -Detail 'already holds a value in this session — never clobbered'
                    continue
                }
                # Value: az stdout → local → $env:NAME. It is never interpolated anywhere.
                $secretValue = ''
                $secretLines = @(& $azCmd.Source keyvault secret show --vault-name $vaultName --name $pair.SecretName --query value --output tsv --only-show-errors 2>$null)
                $secretExit = [int]$LASTEXITCODE
                if ($secretExit -eq 0) { $secretValue = (@($secretLines) -join '').Trim() }
                if ($secretValue) {
                    [Environment]::SetEnvironmentVariable($pair.Env, $secretValue)   # literal name (review finding)
                    $secretValue = ''
                    $exportedNames.Add($pair.Env)
                    Add-Step -Step $pair.Env -State 'exported' -Detail "from Key Vault secret '$($pair.SecretName)' — lights: $($pair.Lights)"
                }
                else {
                    # A FAILED read is not a 'skipped' (review finding): 'skipped'
                    # is the intentional already-populated no-op, while this is an
                    # unresolved acquisition — JSON consumers must be able to tell
                    # them apart, and the run must leave an actionable remediation.
                    Add-Step -Step $pair.Env -State 'needs-owner' -Detail "Key Vault secret '$($pair.SecretName)' could not be read (missing, empty, no RBAC grant, or transient; az exited $secretExit) — the consumers it lights stay unconfigured"
                    # The action names the env var it lights (review finding): the
                    # post-export reconcile filter recognizes a resolved action only
                    # by that name, so a gh-fallback export can retire this one.
                    Add-OwnerAction -Env $pair.Env -Text "store or authorize Key Vault secret '$($pair.SecretName)' in vault '$vaultName' — az keyvault secret set --vault-name $vaultName --name $($pair.SecretName) (owner supplies the value), or grant the running identity 'Key Vault Secrets User'; then re-run auto-login (lights $($pair.Env))"
                    $anyPullFailed = $true
                }
            }
            if ($anyPullFailed -and $azIdentityMismatch) {
                # The switch is fully non-interactive — the operator (or automation)
                # just has to run it; auto-login itself only mutates the az profile
                # through auth-doctor -Apply, which stops at the first healthy cache.
                Add-OwnerAction -Text 'Key Vault pull failed under the cached az identity while AZURE_CLIENT_ID declares a workload identity — switch non-interactively: az login --service-principal --username $env:AZURE_CLIENT_ID --tenant $env:AZURE_TENANT_ID --password $env:AZURE_CLIENT_SECRET (or --certificate $env:AZURE_CLIENT_CERTIFICATE_PATH), then re-run auto-login'
            }
        }
    }

    # --- 3. gh-models from the gh CLI (connect-github.sh sourcing behavior) ----------
    # Target envs are each public github-models target's CONFIGURED apiKeyEnv
    # (review finding), not a hardcoded name; a disabled provider skips the
    # fallback entirely.

    # models:read PROOF for a raw GITHUB_TOKEN (review finding): non-emptiness is
    # not usability — the github-models provider 403s on every call without
    # models:read (connect-github.sh and setup-all.ps1 both treat it as required).
    # Classic PATs expose their granted scopes in the X-OAuth-Scopes response
    # header; fine-grained/Actions tokens do not, and an injecting transport makes
    # per-token proof impossible (rest-connect.ps1 doctrine) — both read as
    # 'unverifiable', never a false 'proven'. The token value exists only in the
    # request header and is never printed.
    function Get-GitHubTokenModelsScope {
        param([Parameter(Mandatory)][string]$EnvName)
        $ghHeaders = @{ Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }
        try {
            $anon = Invoke-WebRequest -Uri 'https://api.github.com/rate_limit' -Headers $ghHeaders -TimeoutSec 20 -SkipHttpErrorCheck -UserAgent 'helios-auto-login'
            if ([int]$anon.StatusCode -eq 200) {
                $anonParsed = $null
                try { $anonParsed = $anon.Content | ConvertFrom-Json } catch { }
                $anonLimit = 0
                if ($null -ne $anonParsed -and $anonParsed.PSObject.Properties['rate'] -and
                    [int]::TryParse([string]$anonParsed.rate.limit, [ref]$anonLimit) -and $anonLimit -gt 60) {
                    return 'unverifiable'   # injecting transport: any token would look valid
                }
            }
            $authHeaders = $ghHeaders.Clone()
            $authHeaders['Authorization'] = "Bearer $([string][Environment]::GetEnvironmentVariable($EnvName))"
            $resp = Invoke-WebRequest -Uri 'https://api.github.com/rate_limit' -Headers $authHeaders -TimeoutSec 20 -SkipHttpErrorCheck -UserAgent 'helios-auto-login'
            $authHeaders = $null
            # Definitive rejection only on 401 (review finding): 429/5xx/anything else
            # is transient and must not condemn a token — the gh rung would otherwise
            # delete a freshly exported credential and demand a re-login over an outage.
            if ([int]$resp.StatusCode -eq 401) { return 'invalid' }
            if ([int]$resp.StatusCode -ne 200) { return 'unverifiable' }
            $scopeKey = @($resp.Headers.Keys | Where-Object { $_ -ieq 'X-OAuth-Scopes' }) | Select-Object -First 1
            $scopesText = if ($scopeKey) { (@($resp.Headers[$scopeKey]) -join ',') } else { '' }
            if ([string]::IsNullOrWhiteSpace($scopesText)) { return 'unverifiable' }
            if ($scopesText -match '(^|[,\s])models:read([,\s]|$)') { return 'proven' }
            return 'missing-scope'
        }
        catch { return 'unverifiable' }
    }

    # True only when GITHUB_TOKEN's models:read is PROVEN — it satisfies every public
    # target at once (ProviderFactory falls back to it for each of them). The
    # reconcile filter retires the lane's scope/vault actions on proof, never on
    # mere presence.
    $ghModelsScopeProven = $false
    # Per-target tracking for the gh-keyring export (review finding): the SAME stored
    # token goes to every public target still unset, so its one verdict applies to
    # each env it was exported to. A proven export retires that env's repairs; an
    # unverifiable one is the best available credential but must not retire a
    # repair action until a run proves it.
    $ghModelsProvenEnvs = [System.Collections.Generic.List[string]]::new()
    $ghModelsUnprovenExportEnvs = [System.Collections.Generic.List[string]]::new()
    # Held values the wire REJECTED (401 or no models:read) — never satisfied, whatever
    # they contain (review finding); the value itself is left untouched.
    $ghModelsRejectedEnvs = [System.Collections.Generic.List[string]]::new()
    $ghTokenVerdict = $null     # GITHUB_TOKEN is probed at most once per run
    $ghKeyring = $null          # the gh keyring is read (env-cleared) and probed at most once per run
    foreach ($target in $ghModelsTargets) {
        # Entries sharing one variable are one target; the label names them all.
        $targetLabel = if (@($target.Owners).Count -gt 1) { 'providers ' + ((@($target.Owners | ForEach-Object { "'$_'" })) -join ', ') } else { "provider '" + $target.Name + "'" }
        $vaultClause = if ($target.SecretName) { ", or store Key Vault secret '$($target.SecretName)' (the configured apiKeySecretName)" } else { '' }
        $repairAction = "grant models:read to the GitHub credential feeding $($target.Env) — gh auth refresh -h github.com --scopes models:read, or a PAT that includes models:read$vaultClause"
        if (-not $target.Public) {
            Add-Step -Step $target.Env -State 'skipped' -Detail "$($target.SkipReason) — no GitHub token fetched or exported for it"
            continue
        }
        if (Test-EnvValue $target.Env) {
            # A preset or vault-pulled value is probed exactly like GITHUB_TOKEN and the
            # gh keyring (review finding): non-emptiness is not usability, and the
            # reconcile filter must never retire a repair on the strength of a revoked
            # or scope-less token. The value is never clobbered — only judged.
            $heldVerdict = Get-GitHubTokenModelsScope -EnvName $target.Env
            $heldSource = 'already holds a value in this session (preset or pulled from Key Vault)'
            switch ($heldVerdict) {
                'proven' {
                    $ghModelsProvenEnvs.Add($target.Env)
                    Add-Step -Step $target.Env -State 'ok' -Detail "$heldSource and X-OAuth-Scopes carries models:read — $targetLabel is satisfied; no GitHub-credential fallback needed"
                }
                'unverifiable' {
                    $ghModelsUnprovenExportEnvs.Add($target.Env)
                    Add-Step -Step $target.Env -State 'ok' -Detail "$heldSource; its models:read permission is NOT verifiable here (no X-OAuth-Scopes header, or an injecting transport) — kept as-is and no fallback attempted, but any scope/vault repair stays listed until a run proves it"
                }
                'missing-scope' {
                    $ghModelsRejectedEnvs.Add($target.Env)
                    Add-Step -Step $target.Env -State 'needs-owner' -Detail "$heldSource but its X-OAuth-Scopes lack models:read — $targetLabel would 403 on every call; the value is left untouched (never clobbered)"
                    Add-OwnerAction -Env $target.Env -Text $repairAction
                }
                default {
                    $ghModelsRejectedEnvs.Add($target.Env)
                    Add-Step -Step $target.Env -State 'needs-owner' -Detail "$heldSource but api.github.com rejects it (401) — $targetLabel cannot use it; the value is left untouched (never clobbered)"
                    Add-OwnerAction -Env $target.Env -Text "rotate the value held by $($target.Env) — api.github.com rejects it: replace it in the shell$vaultClause, or unset it so the GITHUB_TOKEN / gh-keyring fallback can apply on the next run (lights $($target.Env))"
                }
            }
            continue
        }
        $needFallback = $true
        if (Test-EnvValue 'GITHUB_TOKEN') {
            # ProviderFactory.CreateGitHubModels falls back to GITHUB_TOKEN when the
            # configured env is unset (review finding) — the documented CI path — but
            # only a token that actually carries models:read satisfies the provider.
            if ($null -eq $ghTokenVerdict) { $ghTokenVerdict = Get-GitHubTokenModelsScope -EnvName 'GITHUB_TOKEN' }
            switch ($ghTokenVerdict) {
                'proven' {
                    $ghModelsScopeProven = $true
                    $needFallback = $false
                    Add-Step -Step $target.Env -State 'ok' -Detail ("GITHUB_TOKEN carries models:read (X-OAuth-Scopes) and ProviderFactory.CreateGitHubModels falls back to it — $targetLabel is satisfied without an export")
                }
                'unverifiable' {
                    $needFallback = $false
                    Add-Step -Step $target.Env -State 'ok' -Detail ("GITHUB_TOKEN holds a value and ProviderFactory.CreateGitHubModels falls back to it for $targetLabel, but its models:read " +
                        'permission is NOT verifiable here (fine-grained/Actions token exposes no scopes, or an injecting transport) — any vault ' +
                        'or direct-key repair stays listed as the deterministic path; if model calls 403, grant models: read')
                }
                'missing-scope' {
                    Add-Step -Step $target.Env -State 'needs-owner' -Detail "GITHUB_TOKEN is REST-valid but its X-OAuth-Scopes lack models:read — $targetLabel would 403 on every call; trying the gh keyring next"
                    Add-OwnerAction -Env $target.Env -Text $repairAction
                }
                default {
                    Add-Step -Step $target.Env -State 'needs-owner' -Detail "GITHUB_TOKEN was rejected by api.github.com — it cannot satisfy $targetLabel; trying the gh keyring next"
                }
            }
        }
        if (-not $needFallback) { continue }
        if ($null -eq $ghKeyring) {
            # First PATH hit only: Get-Command returns EVERY matching application when
            # the name resolves more than once (a shim or a second install ahead of the
            # real binary), and an array .Source would then be invoked as one bogus
            # command name — measured as an internal failure, not a lane result.
            $ghKeyring = [pscustomobject]@{ Cmd = (Get-Command gh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1); Token = ''; Exit = -1; Verdict = $null }
            if ($ghKeyring.Cmd) {
                # --hostname github.com (review finding): never export a GitHub
                # Enterprise credential (GH_HOST context) into the github.com models lane.
                # Env-cleared (review finding): gh gives GH_TOKEN/GITHUB_TOKEN precedence
                # over its keyring, so with a stale env token set this would export that
                # dead value instead of the STORED login. The shadowing variables are
                # removed for this one call and restored immediately (values move only
                # between env slots in-process; rest-connect.ps1 does the same).
                $savedGhToken = $env:GH_TOKEN
                $savedGithubToken = $env:GITHUB_TOKEN
                try {
                    Remove-Item env:GH_TOKEN -ErrorAction SilentlyContinue
                    Remove-Item env:GITHUB_TOKEN -ErrorAction SilentlyContinue
                    $ghLines = @(& $ghKeyring.Cmd.Source auth token --hostname github.com 2>$null)
                    $ghKeyring.Exit = [int]$LASTEXITCODE
                }
                finally {
                    if ($null -ne $savedGhToken) { $env:GH_TOKEN = $savedGhToken }
                    if ($null -ne $savedGithubToken) { $env:GITHUB_TOKEN = $savedGithubToken }
                    $savedGhToken = ''
                    $savedGithubToken = ''
                }
                $ghKeyring.Token = (@($ghLines) -join '').Trim()
                $ghLines = $null
            }
        }
        if (-not $ghKeyring.Cmd) {
            # Record the lane even when gh is absent — an unevaluated-looking steps
            # list is ambiguous (review finding).
            Add-Step -Step $target.Env -State 'unavailable' -Detail "gh CLI not on PATH and Key Vault did not provide the token for $targetLabel"
            continue
        }
        if ($ghKeyring.Exit -ne 0 -or -not $ghKeyring.Token) {
            Add-Step -Step $target.Env -State 'skipped' -Detail "gh CLI yielded no token (logged out or unavailable) and Key Vault did not provide one for $targetLabel"
            continue
        }
        # Scope PROOF before the export counts (review finding): the stored gh login
        # is probed exactly like GITHUB_TOKEN above, once — the verdict is the same
        # for every target the same token reaches. A token the wire proves to lack
        # models:read is not exported at all (the provider would 403 on every call)
        # and the repair action stands; an unverifiable one is exported as the best
        # available credential but leaves every scope/vault repair listed until a
        # run proves it.
        [Environment]::SetEnvironmentVariable($target.Env, $ghKeyring.Token)   # literal name (review finding)
        if ($null -eq $ghKeyring.Verdict) { $ghKeyring.Verdict = Get-GitHubTokenModelsScope -EnvName $target.Env }
        switch ($ghKeyring.Verdict) {
            'proven' {
                $ghModelsProvenEnvs.Add($target.Env)
                $exportedNames.Add($target.Env)
                Add-Step -Step $target.Env -State 'exported' -Detail "from `gh auth token` — X-OAuth-Scopes carries models:read; lights: $targetLabel"
            }
            'unverifiable' {
                $ghModelsUnprovenExportEnvs.Add($target.Env)
                $exportedNames.Add($target.Env)
                Add-Step -Step $target.Env -State 'exported' `
                    -Detail ("from `gh auth token` — exported as the best available credential for $targetLabel, but its models:read permission is NOT " +
                        'verifiable here (no X-OAuth-Scopes header, or an injecting transport); any scope/vault repair stays listed ' +
                        'until a run proves it; if model calls 403: gh auth refresh -h github.com --scopes models:read')
            }
            'missing-scope' {
                [Environment]::SetEnvironmentVariable($target.Env, $null)   # literal removal (review finding)
                Add-Step -Step $target.Env -State 'needs-owner' -Detail "the stored gh login is REST-valid but its X-OAuth-Scopes lack models:read — NOT exported ($targetLabel would 403 on every call)"
                Add-OwnerAction -Env $target.Env -Text $repairAction
            }
            default {
                [Environment]::SetEnvironmentVariable($target.Env, $null)   # literal removal (review finding)
                Add-Step -Step $target.Env -State 'needs-owner' -Detail "the stored gh login was rejected by api.github.com — NOT exported for $targetLabel"
                Add-OwnerAction -Env $target.Env -Text "re-login gh with models:read — gh auth login --hostname github.com --web --scopes models:read$vaultClause (lights $($target.Env))"
            }
        }
    }
    if ($null -ne $ghKeyring) { $ghKeyring.Token = '' }

    # Blank-apiKeyEnv github-models entries (review finding): the hub reads no
    # variable for them, so there is nothing to export — CreateGitHubModels resolves
    # the entry's apiKeySecretName in-process and otherwise falls back only to
    # GITHUB_TOKEN, which is therefore the one credential this run can vouch for —
    # unless the vault already holds that secret (review finding): presence is proven
    # metadata-only (`az keyvault secret list` returns names, never values) under the
    # az lane this run established, exactly as auth-doctor's Get-BlankVaultChecks does,
    # and a listed, enabled secret makes the provider usable in-process with no export
    # and no owner action.
    $blankGhModels = @($blankEnvProviders | Where-Object { $_.Type -eq 'github-models' })
    $blankSecretNames = @()
    $blankSecretBlocker = ''
    $blankSecretVault = ''
    if (@($blankGhModels | Where-Object { $_.SecretName }).Count -gt 0) {
        $presenceUri = $null
        if ($vaultUri) { try { $presenceUri = [uri]$vaultUri } catch { } }
        if ($null -ne $presenceUri -and $presenceUri.Scheme -eq 'https' -and $presenceUri.Host -match '^(?<vault>[A-Za-z0-9-]{3,24})\.vault\.(azure\.net|azure\.cn|usgovcloudapi\.net|microsoftazure\.de)$') { $blankSecretVault = $Matches['vault'] }
        if (-not $vaultUri) { $blankSecretBlocker = 'AZURE_KEY_VAULT_URI is unset, so the hub cannot reach any vault' }
        elseif (-not $blankSecretVault) { $blankSecretBlocker = 'AZURE_KEY_VAULT_URI is not an https Key Vault URI, so the hub cannot reach the vault' }
        elseif (-not $azUsable) { $blankSecretBlocker = "the az lane is $azState, so the vault could not be inspected" }
        elseif (-not $azCmd) { $blankSecretBlocker = 'az is not on PATH, so the vault could not be inspected' }
        else {
            $listLines = @(& $azCmd.Source keyvault secret list --vault-name $blankSecretVault --query '[?attributes.enabled].name' --output json --only-show-errors 2>$null | ForEach-Object { "$_" })
            $listExit = [int]$LASTEXITCODE
            $listed = $null
            if ($listExit -eq 0) { try { $listed = @(($listLines -join "`n") | ConvertFrom-Json) } catch { $listed = $null } }
            if ($listExit -ne 0 -or $null -eq $listed) { $blankSecretBlocker = "az keyvault secret list against vault '$blankSecretVault' failed (exit ${listExit}: no RBAC grant, network, or wrong vault; output never echoed)" }
            else { $blankSecretNames = @($listed | ForEach-Object { ([string]$_).ToLowerInvariant() }) }
        }
    }
    # The principal that LISTED is not necessarily the principal that READS (review
    # finding): SecretResolver builds its client on DefaultAzureCredential, which
    # prefers the environment service principal (AZURE_CLIENT_ID + secret /
    # certificate), then a workload identity, then a managed identity, and only
    # then the az CLI cache this listing ran under. When the hub would authenticate
    # as one of those and az is not logged in as that same principal, a listed name
    # proves nothing about the hub's access, so presence is reported unverifiable.
    $blankSecretPrincipalGap = ''
    if (-not $blankSecretBlocker -and $blankSecretNames.Count -gt 0) {
        $hubCredential = if ((Test-EnvValue 'AZURE_CLIENT_ID') -and (Test-EnvValue 'AZURE_TENANT_ID') -and ((Test-EnvValue 'AZURE_CLIENT_SECRET') -or (Test-EnvValue 'AZURE_CLIENT_CERTIFICATE_PATH'))) { 'environment service principal' }
        elseif ((Test-EnvValue 'AZURE_FEDERATED_TOKEN_FILE') -and (Test-EnvValue 'AZURE_CLIENT_ID')) { 'workload identity' }
        elseif ((Test-EnvValue 'IDENTITY_ENDPOINT') -or (Test-EnvValue 'MSI_ENDPOINT')) { 'managed identity' }
        else { 'az-cli' }
        if ($hubCredential -ne 'az-cli') {
            $accountLines = @(& $azCmd.Source account show --query '{type:user.type,name:user.name}' --output json --only-show-errors 2>$null | ForEach-Object { "$_" })
            $accountExit = [int]$LASTEXITCODE
            $account = $null
            if ($accountExit -eq 0) { try { $account = ($accountLines -join '') | ConvertFrom-Json } catch { $account = $null } }
            $accountType = if ($null -ne $account -and $account.PSObject.Properties['type'] -and $null -ne $account.type) { [string]$account.type } else { '' }
            $accountName = if ($null -ne $account -and $account.PSObject.Properties['name'] -and $null -ne $account.name) { [string]$account.name } else { '' }
            $samePrincipal = ($hubCredential -ne 'managed identity') -and ($accountType -eq 'servicePrincipal') -and $accountName.Equals(([string][Environment]::GetEnvironmentVariable('AZURE_CLIENT_ID')).Trim(), [System.StringComparison]::OrdinalIgnoreCase)
            if (-not $samePrincipal) {
                $blankSecretPrincipalGap = "listed for the cached az identity, but the hub's DefaultAzureCredential authenticates as the $hubCredential" + $(if ($hubCredential -eq 'managed identity') { ' (IDENTITY_ENDPOINT / MSI_ENDPOINT)' } else { ' (AZURE_CLIENT_ID)' }) + ' — access for that principal is not proven from here'
            }
        }
    }
    foreach ($blank in $blankGhModels) {
        $blankStep = "provider:$($blank.Name)"
        $blankWhy = 'declares an explicitly blank apiKeyEnv — ProviderFactory passes it through (GITHUB_MODELS_TOKEN applies only when the property is absent) and SecretResolver reads no environment variable for a blank name, so nothing auto-login exports can light it'
        $blankPresence = ''
        if ($blank.SecretName) {
            $blankPresence = if ($blankSecretBlocker) { 'unverifiable' }
            elseif ($blankSecretNames -contains $blank.SecretName.ToLowerInvariant()) { if ($blankSecretPrincipalGap) { 'unverifiable' } else { 'present' } }
            else { 'absent' }
        }
        $blankPresenceText = switch ($blankPresence) {
            'present' { " (listed as enabled in vault '$blankSecretVault')" }
            'absent' { " (NOT present, or disabled, in vault '$blankSecretVault')" }
            'unverifiable' { " ($(if ($blankSecretBlocker) { $blankSecretBlocker } else { $blankSecretPrincipalGap }))" }
            default { '' }
        }
        $blankVaultNote = if ($blank.SecretName) { "; the hub resolves Key Vault secret '$($blank.SecretName)' itself, in-process, under AZURE_KEY_VAULT_URI$blankPresenceText" } else { '' }
        $blankSatisfied = $false
        if ($blankPresence -eq 'present') {
            $blankSatisfied = $true
            Add-Step -Step $blankStep -State 'ok' -Detail "$blankWhy$blankVaultNote — CreateGitHubModels reads that secret in-process, so the provider is satisfied without an export"
        }
        elseif (Test-EnvValue 'GITHUB_TOKEN') {
            if ($null -eq $ghTokenVerdict) { $ghTokenVerdict = Get-GitHubTokenModelsScope -EnvName 'GITHUB_TOKEN' }
            switch ($ghTokenVerdict) {
                'proven' {
                    $ghModelsScopeProven = $true
                    $blankSatisfied = $true
                    Add-Step -Step $blankStep -State 'ok' -Detail "$blankWhy$blankVaultNote; GITHUB_TOKEN carries models:read (X-OAuth-Scopes) and CreateGitHubModels falls back to it — satisfied without an export"
                }
                'unverifiable' {
                    $blankSatisfied = $true
                    Add-Step -Step $blankStep -State 'ok' -Detail "$blankWhy$blankVaultNote; GITHUB_TOKEN holds a value and CreateGitHubModels falls back to it, but its models:read permission is NOT verifiable here — if model calls 403, grant models:read"
                }
                'missing-scope' { Add-Step -Step $blankStep -State 'needs-owner' -Detail "$blankWhy$blankVaultNote; GITHUB_TOKEN, the hub's only fallback for it, is REST-valid but its X-OAuth-Scopes lack models:read" }
                default { Add-Step -Step $blankStep -State 'needs-owner' -Detail "$blankWhy$blankVaultNote; GITHUB_TOKEN, the hub's only fallback for it, was rejected by api.github.com" }
            }
        }
        else {
            Add-Step -Step $blankStep -State 'needs-owner' -Detail "$blankWhy$blankVaultNote; GITHUB_TOKEN, the hub's only fallback for it, is unset"
        }
        if (-not $blankSatisfied) {
            if ($blankPresence -eq 'absent') {
                # The configured vault path is the primary repair (review finding): the
                # secret's absence, not the config, is what leaves the provider unlit.
                Add-OwnerAction -Text "store Key Vault secret '$($blank.SecretName)' in vault '$blankSecretVault' for provider '$($blank.Name)' (type github-models) — az keyvault secret set --vault-name $blankSecretVault --name $($blank.SecretName)   # owner supplies the value; the hub then resolves it in-process (its apiKeyEnv is explicitly blank, so no variable applies); or provide a GITHUB_TOKEN that carries models:read"
            }
            else {
                Add-OwnerAction -Text "fix provider '$($blank.Name)' (type github-models) in ${aihubConfigPath}: its apiKeyEnv is explicitly blank, so the hub reads no variable for it$blankVaultNote — set apiKeyEnv to a variable name (or remove the property to use GITHUB_MODELS_TOKEN), or provide a GITHUB_TOKEN that carries models:read"
            }
        }
    }

    # Mixed-ownership variables (review finding): still unset after every rung, the
    # repair is the config split or a direct export — stated once here, in place of
    # the generic direct-key action for the same variable.
    foreach ($mixedTarget in @($ghModelsTargets | Where-Object { $_.Mixed })) {
        if (Test-EnvValue $mixedTarget.Env) { continue }
        if ($conflictingEnvSet.Contains($mixedTarget.Env) -or $incompatibleEnvSet.Contains($mixedTarget.Env)) { continue }   # the conflict / incompatible action above already names the split
        $mixedVaultClause = if ($mixedTarget.SecretName) { ", or store Key Vault secret '$($mixedTarget.SecretName)' (the configured apiKeySecretName) for the next run" } else { '' }
        $mixedPublic = (@($mixedTarget.PublicOwners | ForEach-Object { "'$_'" }) -join ', ')
        Add-OwnerAction -Env $mixedTarget.Env -Text "give the providers sharing $($mixedTarget.Env) distinct apiKeyEnv names in ${aihubConfigLabel} (public github-models: $mixedPublic; also read by: $($mixedTarget.OtherReaders -join '; ')) — no GitHub credential is exported into a variable a non-GitHub endpoint also reads, so until then set $($mixedTarget.Env) directly$mixedVaultClause (lights $($mixedTarget.Env))"
    }

    # Direct-key repairs (review finding): a provider that reads a key but declares
    # no apiKeySecretName has no vault path, and a custom-endpoint github-models
    # provider gets no GitHub credential either — when its variable is still unset
    # after every rung, setting it directly is the only repair, and the summary must
    # carry it instead of listing nothing. A public github-models target proven (or
    # exported) through the GitHub credential is already served.
    foreach ($direct in $directKeyProviders) {
        if (Test-EnvValue $direct.Env) { continue }
        if ($ghModelsMixedEnvSet.Contains($direct.Env) -or $incompatibleEnvSet.Contains($direct.Env)) { continue }   # the mixed-ownership / incompatible action above carries this variable's repair
        if ($direct.Type -eq 'github-models' -and $ghModelsPublicEnvSet.Contains($direct.Env) -and ($ghModelsScopeProven -or $ghModelsProvenEnvs.Contains($direct.Env))) { continue }
        Add-OwnerAction -Env $direct.Env -Text "set $($direct.Env) directly for provider '$($direct.Name)' (type $($direct.Type)) — the active config declares no apiKeySecretName for it, so no Key Vault pull exists: export it in the shell, or add apiKeySecretName to that provider and store the secret (lights $($direct.Env))"
    }

    # Owner actions were collected BEFORE the export steps ran (review finding): the
    # auth-doctor's provider-lane actions say things like "pull openai-api-key into
    # OPENAI_API_KEY" — and when the Key Vault or gh rung supplies that exact env var
    # later in this same run, the pre-export action is already satisfied. The
    # summary's contract is "the only steps that need a human", so any action naming
    # a provider env var that NOW holds a value is dropped, with the drop reported.
    # Derived from the config-driven pairs, the public github-models targets, and the
    # direct-key providers, so the reconcile filter tracks config/aihub.json the same
    # way the pulls do.
    $exportResolvableEnvNames = @(Get-UniqueEnvNames -Names @(@($vaultPairs | ForEach-Object { $_.Env }) + $ghModelsPublicEnvs + @($directKeyProviders | ForEach-Object { $_.Env })))
    # A public github-models env counts as satisfied via the provider's documented
    # GITHUB_TOKEN fallback too (review finding) — a run that ends with a working
    # github-models lane must not still demand a vault repair — but never on the
    # strength of an unproven gh-rung export (review finding): a stored token that
    # also lacks models:read would otherwise retire the very repair it needs. A
    # vault-pulled or pre-set value is the deterministic path and counts as before.
    function Test-EnvSatisfied {
        param([Parameter(Mandatory)][string]$Name)
        # A conflicting or incompatible variable is never satisfied (review finding):
        # a value in it — preset or pulled — is exactly what ProviderFactory hands to
        # every sharer, so the split action (this script's, and the doctor's imported
        # copy, which the direct-key list would otherwise match) must survive.
        if ($incompatibleEnvSet.Contains($Name) -or $conflictingEnvSet.Contains($Name)) { return $false }
        if ($ghModelsPublicEnvSet.Contains($Name)) {
            if ($ghModelsRejectedEnvs.Contains($Name)) { return $false }
            return ($ghModelsScopeProven -or $ghModelsProvenEnvs.Contains($Name) -or
                ((Test-EnvValue $Name) -and -not $ghModelsUnprovenExportEnvs.Contains($Name)))
        }
        return (Test-EnvValue $Name)
    }
    $resolvedActionCount = 0
    $remainingOwnerActions = [System.Collections.Generic.List[string]]::new()
    foreach ($action in $ownerActions) {
        # Structural match (review finding): every action this script composes carries
        # the exact env var it retires on. A substring test let a satisfied 'API_KEY'
        # retire the unrelated OPENAI_API_KEY repair under a custom profile. The
        # auth-doctor's imported free-text actions carry no env, so the variables they
        # name are recovered by an exact-identifier match (bounded by the [A-Za-z0-9_]
        # class) — never a substring.
        # Outer @() on purpose: an if-expression unrolls its output, so a single name
        # would otherwise land as a scalar string and .Count would not exist.
        $candidateEnvNames = @(if ($null -ne $action.Env) { @($action.Env | Where-Object { $_ }) }
            else {
                @($exportResolvableEnvNames | Where-Object {
                    [regex]::IsMatch($action.Text, ('(^|[^A-Za-z0-9_])' + [regex]::Escape($_) + '([^A-Za-z0-9_]|$)'), $envNameRegexOptions) })
            })
        # ALL-variable semantics (review finding): an action is retired only when
        # EVERY variable it names is satisfied — a compound doctor action covering
        # KEY_A and KEY_B must survive the export of KEY_A alone, because KEY_B's
        # provider stays unconfigured and that text is its only remaining repair.
        $unsatisfied = @($candidateEnvNames | Where-Object { -not (Test-EnvSatisfied $_) })
        $resolvedByExport = ($candidateEnvNames.Count -gt 0) -and ($unsatisfied.Count -eq 0)
        if ($resolvedByExport) { $resolvedActionCount++ } else { $remainingOwnerActions.Add($action.Text) }
    }
    $uniqueOwnerActions = @($remainingOwnerActions | Select-Object -Unique)

    Write-Report ''
    if ($resolvedActionCount -gt 0) {
        Write-Report ("{0} pre-export owner action(s) dropped — the provider env var each referenced was satisfied later in this run" -f $resolvedActionCount)
    }
    if ($exportedNames.Count -gt 0) {
        Write-Report ('Exported this run (names only): ' + (@($exportedNames) -join ', '))
        if (-not $DotSourced) { Write-Report 'These exports died with this process — dot-source the script to keep them.' }
    }
    else {
        Write-Report 'Nothing newly exported this run.'
    }
    if ($uniqueOwnerActions.Count -gt 0) {
        Write-Report ''
        Write-Report '== OWNER ACTIONS (the only steps that need a human) =='
        $i = 0
        foreach ($action in $uniqueOwnerActions) { $i++; Write-Report ('  {0}. {1}' -f $i, $action) }
    }

    if ($Json) {
        [ordered]@{
            script        = 'scripts/bootstrap/auto-login.ps1'
            generatedUtc  = (Get-Date).ToUniversalTime().ToString('o')
            dotSourced    = $DotSourced
            steps         = @($steps)
            exportedNames = @($exportedNames)
            ownerActions  = @($uniqueOwnerActions)
            exitCode      = 0
        } | ConvertTo-Json -Depth 4
    }
}

# Dot-source hygiene (review finding): the documented contract mutates exactly
# two surfaces (the az profile via auth-doctor -Apply, and process env vars), so
# every helper symbol this file necessarily creates in a dot-sourcing caller's
# scope is removed again on every path below. ONE class of residue is not
# removable: PowerShell binds the -Json and -UseManagedIdentity parameters into
# the calling scope BEFORE any code runs, so a caller variable named $Json/$json
# or $UseManagedIdentity (names are case-insensitive) is overwritten by the
# binding itself — cleanup deletes the symbols rather than restoring prior values.
# Do not rely on those names surviving this call.
function Remove-HeliosAutoLoginScopeResidue {
    Remove-Item -Path function:Invoke-HeliosAutoLogin -ErrorAction SilentlyContinue
    Remove-Item -Path variable:Json -ErrorAction SilentlyContinue
    # Every PARAMETER binding is a residue, not only -Json (review finding): the
    # -UseManagedIdentity switch lands in the caller's scope the same way.
    Remove-Item -Path variable:UseManagedIdentity -ErrorAction SilentlyContinue
    Remove-Item -Path variable:autoLoginDotSourced -ErrorAction SilentlyContinue
    # Self-removal last: the already-loaded body keeps executing to completion.
    Remove-Item -Path function:Remove-HeliosAutoLoginScopeResidue -ErrorAction SilentlyContinue
}

$autoLoginDotSourced = $MyInvocation.InvocationName -eq '.'
try {
    Invoke-HeliosAutoLogin -Json:$Json -UseManagedIdentity:$UseManagedIdentity -DotSourced $autoLoginDotSourced -RepoRoot (Resolve-Path (Join-Path $PSScriptRoot '..' '..'))
    if (-not $autoLoginDotSourced) { exit 0 }
    Remove-HeliosAutoLoginScopeResidue
}
catch {
    [Console]::Error.WriteLine("auto-login: internal failure: $($_.Exception.Message)")
    # Dot-sourced: rethrow so the caller can DETECT the partial setup (review
    # finding) — exiting would kill their shell, and swallowing would fake
    # success. Scope residue is removed first; `throw` rethrows $_ regardless.
    if ($autoLoginDotSourced) {
        Remove-HeliosAutoLoginScopeResidue
        throw
    }
    exit 1
}
