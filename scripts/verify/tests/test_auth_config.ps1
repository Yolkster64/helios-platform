# Offline regressions for the config-contract and selected-credential rules: functions
# are loaded through the parser, production loops are executed as script blocks with
# inert reporting, and no CLI, network or login entrypoint is ever run.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Read-Ast($Path) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $Path), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "Parse failed: $Path" }
    return $ast
}
function Import-Functions($Ast) {
    foreach ($f in $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        Set-Item "Function:script:$($f.Name)" -Value $f.Body.GetScriptBlock()
    }
}
# A hashtable literal assigned in a script, evaluated from its own source text so the
# test exercises the schema the script really declares.
function Get-AssignedLiteral($Ast, [string]$Left) {
    $node = $Ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq $Left }, $true)
    if (-not $node) { throw "Assignment $Left not found." }
    return (Invoke-Expression $node.Right.Extent.Text)
}
function Assert-True($Value, $Message) { if (-not $Value) { throw $Message }; $script:cases++ }
$script:cases = 0
$rest = Read-Ast 'scripts/verify/rest-connect.ps1'
$doctor = Read-Ast 'scripts/bootstrap/auth-doctor.ps1'
$auto = Read-Ast 'scripts/bootstrap/auto-login.ps1'
$names = @('AZURE_CLIENT_ID','AZURE_TENANT_ID','AZURE_CLIENT_SECRET','AZURE_CLIENT_CERTIFICATE_PATH','AZURE_FEDERATED_TOKEN_FILE',
    'IDENTITY_ENDPOINT','IDENTITY_HEADER','MSI_ENDPOINT','MSI_SECRET','AZURE_OPENAI_ENDPOINT','AZURE_OPENAI_API_KEY','AIHUB_CONFIG','PATH','GH_REPO',
    'ANTHROPIC_FOUNDRY_RESOURCE','ANTHROPIC_FOUNDRY_API_KEY','FOUNDRY_ALT')
$saved = @{}
$temp = Join-Path ([IO.Path]::GetTempPath()) ('helios-auth-config-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }
    foreach ($name in $names | Where-Object { $_ -ne 'PATH' }) { [Environment]::SetEnvironmentVariable($name, $null) }

    # --- 1. An ENABLED cliAgents entry must carry a non-null argsTemplate ----------------
    # CliProcessAgent.BuildArguments calls Contains / Split on it for the first routed
    # request; a disabled entry is never constructed, so its string stays nullable.
    Import-Functions $auto
    $autoSchemas = Get-AssignedLiteral $auto '$memberSchemas'
    $nullTemplate = [pscustomobject]@{ name = 'codex'; command = 'codex'; argsTemplate = $null }
    Assert-True ((Get-JsonMemberProblem -Object $nullTemplate -Schema $autoSchemas.cliAgentEnabled -Path 'cliAgents[0]') -like '*argsTemplate*') 'auto-login accepted a null argsTemplate on an enabled CLI entry.'
    Assert-True ((Get-JsonMemberProblem -Object $nullTemplate -Schema $autoSchemas.cliAgent -Path 'cliAgents[0]') -eq '') 'auto-login rejected a null argsTemplate on a DISABLED CLI entry.'
    Assert-True ((Get-JsonMemberProblem -Object ([pscustomobject]@{ name = 'codex'; command = 'codex'; argsTemplate = 'exec {prompt}' }) -Schema $autoSchemas.cliAgentEnabled -Path 'cliAgents[0]') -eq '') 'auto-login rejected a valid argsTemplate.'
    Import-Functions $rest
    $restSchemas = Get-AssignedLiteral $rest '$script:aihubMemberSchemas'
    Assert-True ((Get-AIHubMemberProblem -Object $nullTemplate -Schema $restSchemas.cliAgentEnabled -Path 'cliAgents[0]') -like '*argsTemplate*') 'rest-connect accepted a null argsTemplate on an enabled CLI entry.'
    Assert-True ((Get-AIHubMemberProblem -Object $nullTemplate -Schema $restSchemas.cliAgent -Path 'cliAgents[0]') -eq '') 'rest-connect rejected a null argsTemplate on a DISABLED CLI entry.'
    Import-Functions $doctor
    $repoRoot = $root
    foreach ($case in @(@{ Enabled = $true; Expect = $true }, @{ Enabled = $false; Expect = $false })) {
        $configPath = Join-Path $temp "aihub-$($case.Enabled).json"
        @{ providers = @{ ollama = @{ type = 'ollama'; model = 'x' } }; cliAgents = @(@{ name = 'codex'; command = 'codex'; argsTemplate = $null; enabled = $case.Enabled }) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $configPath
        $env:AIHUB_CONFIG = $configPath
        $script:aihubConfigState = $null
        $state = Get-AIHubConfigState
        Assert-True ((([string]$state.SectionShape) -like '*argsTemplate*') -eq $case.Expect) "auth-doctor argsTemplate rule wrong for enabled=$($case.Enabled)."
    }
    $env:AIHUB_CONFIG = $null
    $script:aihubConfigState = $null

    # --- 2. A relative command with a separator is refused, bare and absolute resolve ----
    # Process.Start resolves a separator-bearing name against the working directory,
    # IsOnPath joins it onto PATH — only bare names and absolute paths agree.
    $bin = Join-Path $temp 'bin'
    New-Item -ItemType Directory -Path (Join-Path $bin 'tools') | Out-Null
    Set-Content -LiteralPath (Join-Path $bin 'codex') -Value 'inert'
    Set-Content -LiteralPath (Join-Path $bin 'tools/codex') -Value 'inert'
    [Environment]::SetEnvironmentVariable('PATH', $bin)
    function Get-CliCommand { param($Name) $p = Join-Path $bin $Name; if (Test-Path -LiteralPath $p -PathType Leaf) { [pscustomobject]@{ Source = $p } } else { $null } }
    $relative = Resolve-CliAgentExecutable -Configured 'tools/codex' -Fallback 'codex'
    Assert-True ((-not $relative.Found) -and $relative.Shape -eq 'relative-with-separator' -and $relative.Note -like '*working directory*') 'Relative separator command was resolved through PATH.'
    $relativeWin = Resolve-CliAgentExecutable -Configured 'tools\codex' -Fallback 'codex'
    Assert-True ((-not $relativeWin.Found) -and $relativeWin.Shape -eq 'relative-with-separator') 'Backslash-relative command was resolved through PATH.'
    $bare = Resolve-CliAgentExecutable -Configured 'codex' -Fallback 'codex'
    Assert-True ($bare.Found -and $bare.Shape -eq 'bare') 'Bare command on PATH was not found.'
    $rooted = Resolve-CliAgentExecutable -Configured (Join-Path $bin 'tools/codex') -Fallback 'codex'
    Assert-True ($rooted.Found -and $rooted.Shape -eq 'rooted' -and $rooted.Source -eq (Join-Path $bin 'tools/codex')) 'Absolute command was not resolved as written.'
    $missing = Resolve-CliAgentExecutable -Configured (Join-Path $bin 'tools/missing') -Fallback 'codex'
    Assert-True ((-not $missing.Found) -and $missing.Shape -eq 'rooted' -and $missing.Note -like '*does not exist*') 'Missing absolute command was not reported as missing.'
    [Environment]::SetEnvironmentVariable('PATH', $saved['PATH'])

    # --- 3. A selected credential is proven only by rest-connect's azure lane ------------
    Import-Functions $auto
    $RepoRoot = $root
    $azCmd = $null   # Test-HubPrincipalIsAzLogin returns $false without az; the gap must not depend on it
    $hubProbeCache = @{}
    $selectedCredentialProofCache = @{}
    $script:probeCalls = 0
    $script:probeReport = $null
    function Invoke-RestConnectProbe { $script:probeCalls++; return $script:probeReport }
    function Set-Lane([string]$State, [string]$Source, [string]$Action = '') {
        $script:probeReport = [pscustomobject]@{ lanes = @([pscustomobject]@{ lane = 'github'; state = 'ready'; source = 'x' }, [pscustomobject]@{ lane = 'azure'; state = $State; source = $Source; detail = 'inert detail'; ownerAction = $Action }) }
        $selectedCredentialProofCache.Clear()
    }
    Set-Lane 'ready' 'env-service-principal'
    $proof = Get-SelectedCredentialProof -Kind 'environment service principal'
    Assert-True ($proof.Proven -and $proof.State -eq 'ready') 'A token acquired through the selected service principal was not accepted as proof.'
    [void](Get-SelectedCredentialProof -Kind 'environment service principal')
    Assert-True ($script:probeCalls -eq 1) 'rest-connect was run more than once for the same credential kind.'
    Set-Lane 'needs-owner' 'env-service-principal' 'rotate the secret (inert action)'
    $proof = Get-SelectedCredentialProof -Kind 'environment service principal'
    Assert-True ((-not $proof.Proven) -and $proof.OwnerAction -eq 'rotate the secret (inert action)') 'A rejected service principal was credited, or its repair was dropped.'
    Set-Lane 'ready' 'az-cli'
    Assert-True (-not (Get-SelectedCredentialProof -Kind 'environment service principal').Proven) 'A token from a LATER source was credited to the selected service principal.'
    Set-Lane 'ready' 'managed-identity (identity-endpoint)'
    Assert-True ((Get-SelectedCredentialProof -Kind 'managed identity').Proven) 'A proven managed identity was not accepted.'
    Set-Lane 'unavailable' 'workload-identity'
    Assert-True (-not (Get-SelectedCredentialProof -Kind 'workload identity').Proven) 'A transient workload-identity failure was credited.'
    $script:probeReport = $null; $selectedCredentialProofCache.Clear()
    $proof = Get-SelectedCredentialProof -Kind 'environment service principal'
    Assert-True ((-not $proof.Proven) -and $proof.State -eq 'unverifiable') 'A missing rest-connect report was credited.'

    # The gap text and repair derived from that proof; none for the az CLI kind.
    Assert-True ((Get-HubPrincipalGap -Kind 'az-cli').Gap -eq '') 'The az-cli kind reported a principal gap.'
    Set-Lane 'ready' 'env-service-principal'
    Assert-True ((Get-HubPrincipalGap -Kind 'environment service principal').Gap -eq '') 'A proven service principal still reported a gap.'
    Set-Lane 'needs-owner' 'env-service-principal' 'rotate the secret (inert action)'
    $gap = Get-HubPrincipalGap -Kind 'environment service principal'
    Assert-True ($gap.Gap -like '*needs-owner*' -and $gap.Action -eq 'rotate the secret (inert action)') 'A rejected service principal did not surface rest-connect''s verdict and repair.'
    Set-Lane 'needs-owner' 'env-service-principal'
    Assert-True ((Get-HubPrincipalGap -Kind 'environment service principal').Action -like '*rest-connect*') 'A gap without a lane action left the owner without a repair.'
    # A cached az login matching the client and tenant is context, never proof.
    function Fake-Az { $global:LASTEXITCODE = 0; (@{ type = 'servicePrincipal'; name = 'client-a'; tenantId = 'tenant-a' } | ConvertTo-Json -Compress) }
    $azCmd = [pscustomobject]@{ Source = 'Fake-Az' }
    $env:AZURE_CLIENT_ID = 'client-a'; $env:AZURE_TENANT_ID = 'tenant-a'; $env:AZURE_CLIENT_SECRET = 'dummy-secret-must-not-leak'
    Set-Lane 'needs-owner' 'env-service-principal' 'rotate the secret (inert action)'
    $gap = Get-HubPrincipalGap -Kind 'environment service principal'
    Assert-True ($gap.Gap -like '*needs-owner*' -and $gap.Gap -like '*proves the principal exists*') 'A matching cached az identity was taken as proof of the selected credential.'
    Assert-True (($gap | ConvertTo-Json -Depth 3) -notlike '*dummy-secret-must-not-leak*') 'Secret leaked into the gap text.'
    $azCmd = $null
    $env:AZURE_CLIENT_ID = $null; $env:AZURE_TENANT_ID = $null; $env:AZURE_CLIENT_SECRET = $null

    # --- 4. Entra-fallback verdicts ------------------------------------------------------
    $out = Get-EntraFallbackOutcome -Kind 'az-cli' -AzUsable $true -AzState 'ready' -Lights 'p'
    Assert-True ($out.State -eq 'ok' -and $out.Action -eq '') 'az-cli fallback with a usable az lane was not ok.'
    $out = Get-EntraFallbackOutcome -Kind 'az-cli' -AzUsable $false -AzState 'needs-owner' -Lights 'p' -AzLaneHadAction $true
    Assert-True ($out.State -eq 'needs-owner' -and $out.Action -eq '') 'az-cli fallback with a broken az lane reported ok, or duplicated the imported az repair.'
    $out = Get-EntraFallbackOutcome -Kind 'az-cli' -AzUsable $false -AzState 'unavailable' -Lights 'p'
    Assert-True ($out.State -eq 'needs-owner' -and $out.Action -like '*repair the az lane*') 'az-cli fallback without an az action left no repair.'
    Set-Lane 'ready' 'env-service-principal'
    $out = Get-EntraFallbackOutcome -Kind 'environment service principal' -AzUsable $false -AzState 'needs-owner' -Lights 'p'
    Assert-True ($out.State -eq 'ok') 'A proven service principal fallback was not ok (the az lane is irrelevant to it).'
    Set-Lane 'needs-owner' 'env-service-principal' 'rotate the secret (inert action)'
    $out = Get-EntraFallbackOutcome -Kind 'environment service principal' -AzUsable $true -AzState 'ready' -Lights 'p'
    Assert-True ($out.State -eq 'needs-owner' -and $out.Action -eq 'rotate the secret (inert action)') 'An unproven service principal fallback was credited because az is ready.'

    # --- 5. The production secretless azure-openai loop, with inert reporting -------------
    $loop = $auto.Find({ param($n) $n -is [System.Management.Automation.Language.ForEachStatementAst] -and $n.Extent.Text.StartsWith('foreach ($secretless in $secretlessEntraProviders)') }, $true)
    if (-not $loop) { throw 'Secretless Entra-provider loop not found.' }
    $loopBlock = [scriptblock]::Create($loop.Extent.Text)
    $aihubConfigLabel = 'AIHUB_CONFIG'
    $entraProviderTypes = Get-AssignedLiteral $auto '$entraProviderTypes'
    $script:steps = [System.Collections.Generic.List[object]]::new()
    $script:actions = [System.Collections.Generic.List[string]]::new()
    function Add-Step { param([string]$Step, [string]$State, [string]$Detail) $script:steps.Add([pscustomobject]@{ Step = $Step; State = $State; Detail = $Detail }) }
    function Add-OwnerAction { param([string]$Text, [string]$Env = '', [switch]$Imported) $script:actions.Add($Text) }
    function Test-RawImdsManagedIdentity { return $false }
    function Run-Loop([bool]$Usable, [string]$State, [string]$Type = 'azure-openai') {
        $script:steps.Clear(); $script:actions.Clear(); $selectedCredentialProofCache.Clear()
        $secretlessEntraProviders = [System.Collections.Generic.List[object]]::new()
        if ($Type -eq 'azure-openai') { $secretlessEntraProviders.Add([pscustomobject]@{ Name = 'aoai'; Type = 'azure-openai'; Env = 'AZURE_OPENAI_API_KEY'; EndpointEnv = 'AZURE_OPENAI_ENDPOINT'; BaseUrl = '' }) }
        else { $secretlessEntraProviders.Add([pscustomobject]@{ Name = 'claude-foundry'; Type = 'anthropic-foundry'; Env = 'ANTHROPIC_FOUNDRY_API_KEY'; EndpointEnv = 'ANTHROPIC_FOUNDRY_RESOURCE'; BaseUrl = '' }) }
        $azUsable = $Usable; $azState = $State; $azLaneHadAction = $false
        . $loopBlock
        return $script:steps[0]
    }
    $step = Run-Loop $true 'ready'
    Assert-True ($step.State -eq 'needs-owner' -and $step.Detail -like '*AZURE_OPENAI_ENDPOINT is unset*' -and $script:actions.Count -eq 1) 'Secretless azure-openai with no endpoint was not reported.'
    $env:AZURE_OPENAI_ENDPOINT = 'not a url'
    $step = Run-Loop $true 'ready'
    Assert-True ($step.State -eq 'needs-owner' -and $step.Detail -like '*not an absolute http(s) URL*') 'Secretless azure-openai with a malformed endpoint was not reported.'
    $env:AZURE_OPENAI_ENDPOINT = 'https://inert.openai.azure.com/'
    $env:AZURE_OPENAI_API_KEY = 'dummy-key-must-not-leak'
    $step = Run-Loop $false 'needs-owner'
    Assert-True ($step.State -eq 'ok' -and $step.Detail -notlike '*dummy-key-must-not-leak*' -and $script:actions.Count -eq 0) 'Secretless azure-openai with a set key was not ok, or leaked the key.'
    $env:AZURE_OPENAI_API_KEY = $null
    $step = Run-Loop $true 'ready'
    Assert-True ($step.State -eq 'ok' -and $step.Detail -like '*az CLI login*') 'Secretless azure-openai Entra fallback through a usable az lane was not ok.'
    $step = Run-Loop $false 'needs-owner'
    Assert-True ($step.State -eq 'needs-owner' -and $script:actions.Count -eq 1) 'Secretless azure-openai Entra fallback with a broken az lane was credited.'
    $env:AZURE_CLIENT_ID = 'client-a'; $env:AZURE_TENANT_ID = 'tenant-a'; $env:AZURE_CLIENT_SECRET = 'dummy-secret-must-not-leak'
    Set-Lane 'needs-owner' 'env-service-principal' 'rotate the secret (inert action)'
    $step = Run-Loop $true 'ready'
    Assert-True ($step.State -eq 'needs-owner' -and $script:actions[0] -eq 'rotate the secret (inert action)' -and $step.Detail -notlike '*dummy-secret-must-not-leak*') 'Secretless azure-openai credited a rejected service principal because az is ready.'
    Set-Lane 'ready' 'env-service-principal'
    $step = Run-Loop $false 'needs-owner'
    Assert-True ($step.State -eq 'ok' -and $step.Detail -like '*rest-connect*') 'Secretless azure-openai with a proven service principal was not ok.'

    # --- 6. An ENABLED CLI entry's timeoutSeconds is range-checked (1..2147483) ----------
    # CancelAfter throws on a negative TimeSpan after the child was started; zero
    # cancels every request before it answers. Disabled entries keep the plain int rule.
    Import-Functions $auto
    foreach ($case in @(@{ V = -5; Bad = $true }, @{ V = 0; Bad = $true }, @{ V = 2147484; Bad = $true }, @{ V = 1; Bad = $false }, @{ V = 300; Bad = $false }, @{ V = [long]2147483; Bad = $false })) {
        $entry = [pscustomobject]@{ name = 'codex'; command = 'codex'; argsTemplate = 'exec {prompt}'; timeoutSeconds = $case.V }
        $problem = Get-JsonMemberProblem -Object $entry -Schema $autoSchemas.cliAgentEnabled -Path 'cliAgents[0]'
        Assert-True (($problem -like '*timeoutSeconds*') -eq $case.Bad) "auto-login timeoutSeconds rule wrong for $($case.V)."
        $restProblem = Get-AIHubMemberProblem -Object $entry -Schema $restSchemas.cliAgentEnabled -Path 'cliAgents[0]'
        Assert-True (($restProblem -like '*timeoutSeconds*') -eq $case.Bad) "rest-connect timeoutSeconds rule wrong for $($case.V)."
    }
    Assert-True ((Get-JsonMemberProblem -Object ([pscustomobject]@{ name = 'codex'; command = 'codex'; timeoutSeconds = -5 }) -Schema $autoSchemas.cliAgent -Path 'cliAgents[0]') -eq '') 'A DISABLED entry was range-checked.'
    Import-Functions $doctor
    foreach ($case in @(@{ V = -5; Bad = $true }, @{ V = 300; Bad = $false })) {
        $configPath = Join-Path $temp "aihub-timeout-$($case.V).json"
        @{ providers = @{ ollama = @{ type = 'ollama'; model = 'x' } }; cliAgents = @(@{ name = 'codex'; command = 'codex'; argsTemplate = 'exec {prompt}'; timeoutSeconds = $case.V }) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $configPath
        $env:AIHUB_CONFIG = $configPath
        $script:aihubConfigState = $null
        Assert-True (((([string](Get-AIHubConfigState).SectionShape)) -like '*timeoutSeconds*') -eq $case.Bad) "auth-doctor timeoutSeconds rule wrong for $($case.V)."
    }
    $env:AIHUB_CONFIG = $null
    $script:aihubConfigState = $null

    # --- 7. Repository-secret probes are pinned to this checkout's origin remote ------
    # gh's {owner}/{repo} placeholders follow GH_REPO when it is set; the probe must
    # name the checkout's repository explicitly and never consult GH_REPO.
    $script:probeArgs = [System.Collections.Generic.List[string]]::new()
    $script:remoteUrl = 'https://github.com/inert-owner/inert-repo.git'
    function Get-CliCommand { param($Name) [pscustomobject]@{ Source = "Fake-$Name" } }
    function Invoke-Probe { param($Executable, $Arguments)
        if ($Executable -eq 'Fake-git') { return [pscustomobject]@{ ExitCode = 0; Output = @($script:remoteUrl) } }
        $script:probeArgs.Add(($Arguments -join ' '))
        return [pscustomobject]@{ ExitCode = 0; Output = @('HTTP/2.0 200 OK', '{}') } }
    function Get-NonGitHubOwnedTokenNames { @() }
    $savedGhRepo = [Environment]::GetEnvironmentVariable('GH_REPO')
    try {
        [Environment]::SetEnvironmentVariable('GH_REPO', 'other-owner/other-repo')
        $script:checkoutRepositorySlug = $null
        $state = Get-RepositorySecretState -Name 'LINEAR_API_KEY'
        Assert-True ($state.State -eq 'configured') 'A 200 on the pinned repository was not reported as configured.'
        Assert-True (@($script:probeArgs | Where-Object { $_ -like '*repos/inert-owner/inert-repo/actions/secrets*' }).Count -eq 2 -and @($script:probeArgs | Where-Object { $_ -like '*other-owner*' -or $_ -like '*{owner}*' }).Count -eq 0) 'Secret probes were not pinned to the checkout remote.'
        foreach ($url in @('git@github.com:inert-owner/inert-repo.git', 'ssh://git@github.com/inert-owner/inert-repo', 'https://github.com/inert-owner/inert-repo')) {
            $script:remoteUrl = $url; $script:checkoutRepositorySlug = $null
            Assert-True ((Get-CheckoutRepositorySlug) -eq 'inert-owner/inert-repo') "Remote shape not parsed: $url"
        }
        $script:remoteUrl = 'https://dev.azure.com/org/proj/_git/repo'; $script:checkoutRepositorySlug = $null
        $state = Get-RepositorySecretState -Name 'LINEAR_API_KEY'
        Assert-True ($state.State -eq 'unknown' -and $state.Reason -like '*GH_REPO is deliberately not consulted*') 'A non-GitHub remote did not yield unknown.'
    } finally {
        [Environment]::SetEnvironmentVariable('GH_REPO', $savedGhRepo)
        $script:checkoutRepositorySlug = $null
    }

    # --- 8. The vault identity pin compares client id AND tenant -------------------------
    Import-Functions $auto
    function Fake-Az { $global:LASTEXITCODE = 0; $script:accountJson }
    $azCmd = [pscustomobject]@{ Source = 'Fake-Az' }
    $env:AZURE_CLIENT_ID = 'client-a'; $env:AZURE_TENANT_ID = 'tenant-a'
    foreach ($case in @(@{ Name = 'client-a'; Tenant = 'tenant-a'; Mismatch = $false }, @{ Name = 'client-a'; Tenant = 'tenant-b'; Mismatch = $true }, @{ Name = 'client-b'; Tenant = 'tenant-a'; Mismatch = $true }, @{ Name = 'CLIENT-A'; Tenant = 'TENANT-A'; Mismatch = $false })) {
        $script:accountJson = (@{ name = $case.Name; tenantId = $case.Tenant } | ConvertTo-Json -Compress)
        $identity = Get-CachedAzIdentity
        $verdict = Test-AzIdentityMismatch -Name $identity.Name -Tenant $identity.Tenant
        Assert-True (([bool]$verdict) -eq $case.Mismatch) "Identity pin wrong for $($case.Name)/$($case.Tenant)."
    }
    $env:AZURE_TENANT_ID = $null
    $script:accountJson = (@{ name = 'client-a'; tenantId = 'tenant-b' } | ConvertTo-Json -Compress)
    $identity = Get-CachedAzIdentity
    Assert-True (-not (Test-AzIdentityMismatch -Name $identity.Name -Tenant $identity.Tenant)) 'Without AZURE_TENANT_ID the tenant was compared anyway.'
    $env:AZURE_CLIENT_ID = $null
    $azCmd = $null

    # --- 9. A preset key is validated against its endpoint / baseUrl before it counts ---
    # (section 8 re-imported auto-login's real reporting functions; shadow them again)
    function Add-Step { param([string]$Step, [string]$State, [string]$Detail) $script:steps.Add([pscustomobject]@{ Step = $Step; State = $State; Detail = $Detail }) }
    function Add-OwnerAction { param([string]$Text, [string]$Env = '', [switch]$Imported) $script:actions.Add($Text) }
    $script:steps.Clear(); $script:actions.Clear()
    $presetLoop = $auto.Find({ param($n) $n -is [System.Management.Automation.Language.ForEachStatementAst] -and $n.Extent.Text.StartsWith('foreach ($presetPair in @($vaultPairs | Where-Object { Test-EnvValue $_.Env }))') }, $true)
    if (-not $presetLoop) { throw 'Preset-pair loop not found.' }
    $presetBlock = [scriptblock]::Create($presetLoop.Extent.Text)
    $env:AZURE_OPENAI_API_KEY = 'dummy-key-must-not-leak'
    $vaultPairs = @([pscustomobject]@{ SecretName = 'azure-openai-api-key'; Env = 'AZURE_OPENAI_API_KEY'; Lights = 'azure-openai'; Members = @([pscustomobject]@{ Name = 'azure-openai'; Type = 'azure-openai'; EndpointEnv = 'AZURE_OPENAI_ENDPOINT'; BaseUrl = '' }); EntraFallbackOnly = $true; EndpointEnvs = @('AZURE_OPENAI_ENDPOINT') })
    $env:AZURE_OPENAI_ENDPOINT = $null
    . $presetBlock
    Assert-True ($script:steps[0].State -eq 'needs-owner' -and $script:steps[0].Detail -like '*AZURE_OPENAI_ENDPOINT is unset*' -and $script:steps[0].Detail -notlike '*dummy-key-must-not-leak*') 'A preset key with no endpoint was reported as skipped.'
    $script:steps.Clear(); $script:actions.Clear()
    $env:AZURE_OPENAI_ENDPOINT = 'https://inert.openai.azure.com/'
    . $presetBlock
    Assert-True ($script:steps[0].State -eq 'skipped') 'A preset key with a usable endpoint was not skipped.'
    $env:AZURE_OPENAI_ENDPOINT = $null; $env:AZURE_OPENAI_API_KEY = $null

    # --- 10. The doctor exercises a configured deployed credential before crediting the cache
    Import-Functions $doctor
    $repoRoot = $root; $inCloudShell = $false; $inActions = $false; $Apply = $false; $UseManagedIdentity = $false
    function Get-CliCommand { param($Name) if ($Name -eq 'az') { [pscustomobject]@{ Source = 'Fake-Az-Doctor' } } else { $null } }
    function Invoke-Probe { param($Executable, $Arguments) return [pscustomobject]@{ ExitCode = 0; Output = @() } }   # healthy cache: show + get-access-token exit 0
    $script:doctorReport = $null
    function Invoke-RestConnectProbe { return $script:doctorReport }
    function Set-DoctorLane([string]$State, [string]$Source, [string]$Action = '') {
        $script:doctorReport = [pscustomobject]@{ lanes = @([pscustomobject]@{ lane = 'azure'; state = $State; source = $Source; detail = 'inert detail'; ownerAction = $Action }) }
        $script:selectedCredentialLaneCache = @{}
    }
    Assert-True ((Test-AzLane).state -eq 'ready') 'A healthy cache with no deployed credential was not ready.'
    $env:AZURE_CLIENT_ID = 'client-a'; $env:AZURE_TENANT_ID = 'tenant-a'; $env:AZURE_CLIENT_SECRET = 'dummy-secret-must-not-leak'
    Set-DoctorLane 'needs-owner' 'env-service-principal' 'rotate the secret (inert action)'
    $lane = Test-AzLane
    Assert-True ($lane.state -eq 'needs-owner' -and $lane.method -eq 'service-principal' -and $lane.ownerAction -eq 'rotate the secret (inert action)') 'A rejected service principal was masked by the healthy az cache.'
    Assert-True (($lane | ConvertTo-Json -Depth 3) -notlike '*dummy-secret-must-not-leak*') 'Secret leaked into the az lane.'
    Set-DoctorLane 'unavailable' 'env-service-principal'
    Assert-True ((Test-AzLane).state -eq 'unavailable') 'A transient service-principal failure was credited through the cache.'
    Set-DoctorLane 'ready' 'env-service-principal'
    $lane = Test-AzLane
    Assert-True ($lane.state -eq 'ready' -and $lane.method -eq 'service-principal') 'A proven service principal was not reported ready.'
    Set-DoctorLane 'ready' 'az-cli'
    Assert-True ((Test-AzLane).state -eq 'needs-owner') 'A token from the az cache was credited to the selected service principal.'
    $env:AZURE_CLIENT_SECRET = $null
    $env:AZURE_FEDERATED_TOKEN_FILE = (Join-Path $temp 'inert.jwt'); Set-Content -LiteralPath $env:AZURE_FEDERATED_TOKEN_FILE -Value 'inert'
    Set-DoctorLane 'needs-owner' 'workload-identity' 'fix the federated credential (inert action)'
    $lane = Test-AzLane
    Assert-True ($lane.state -eq 'needs-owner' -and $lane.method -eq 'workload-identity') 'A rejected workload identity was masked by the healthy az cache.'
    $env:AZURE_FEDERATED_TOKEN_FILE = $null; $env:AZURE_CLIENT_ID = $null; $env:AZURE_TENANT_ID = $null
    $env:IDENTITY_ENDPOINT = 'http://127.0.0.1:41000/msi/token'
    Set-DoctorLane 'ready' 'managed-identity (identity-endpoint)'
    $lane = Test-AzLane
    Assert-True ($lane.state -eq 'ready' -and $lane.method -eq 'managed-identity') 'A proven managed identity was not reported ready.'
    $env:IDENTITY_ENDPOINT = $null

    # --- 11. Claude in Microsoft Foundry (anthropic-foundry) mirrors ProviderFactory ------
    # CreateAnthropicFoundry: config baseUrl overrides the endpoint variable
    # (ANTHROPIC_FOUNDRY_RESOURCE by default); TryResolveBaseUri accepts a bare resource
    # name or an absolute https URL; the key is optional (Entra ID fallback).
    Import-Functions $auto
    function Add-Step { param([string]$Step, [string]$State, [string]$Detail) $script:steps.Add([pscustomobject]@{ Step = $Step; State = $State; Detail = $Detail }) }
    function Add-OwnerAction { param([string]$Text, [string]$Env = '', [switch]$Imported) $script:actions.Add($Text) }
    function Test-RawImdsManagedIdentity { return $false }
    $azCmd = $null
    $keyedProviderTypes = Get-AssignedLiteral $auto '$keyedProviderTypes'
    Assert-True (('anthropic-foundry' -in $keyedProviderTypes) -and ('anthropic-foundry' -in $entraProviderTypes) -and ('ollama' -notin $keyedProviderTypes)) 'anthropic-foundry is not a keyed, Entra-capable type in auto-login.'
    foreach ($case in @(
        @{ V = 'helios-aijcut'; Ok = $true; Kind = 'resource-name' },
        @{ V = ' helios-aijcut '; Ok = $true; Kind = 'resource-name' },
        @{ V = 'https://helios-aijcut.services.ai.azure.com/anthropic/v1/messages'; Ok = $true; Kind = 'https-url' },
        @{ V = 'HTTPS://helios-aijcut.services.ai.azure.com'; Ok = $true; Kind = 'https-url' },
        @{ V = 'http://helios-aijcut.services.ai.azure.com/anthropic'; Ok = $false; Kind = 'rejected' },
        @{ V = 'helios aijcut'; Ok = $false; Kind = 'rejected' },
        @{ V = 'helios_aijcut'; Ok = $false; Kind = 'rejected' },
        @{ V = '-helios'; Ok = $false; Kind = 'rejected' },
        @{ V = ('a' * 65); Ok = $false; Kind = 'rejected' },
        @{ V = ''; Ok = $false; Kind = 'unset' },
        @{ V = '   '; Ok = $false; Kind = 'unset' })) {
        $verdict = Test-AnthropicFoundryResource -Value $case.V
        Assert-True ($verdict.Ok -eq $case.Ok -and $verdict.Kind -eq $case.Kind) "Foundry resource rule wrong for '$($case.V)'."
    }
    function New-FoundryPair([string]$BaseUrl = '', [string]$EndpointEnv = 'ANTHROPIC_FOUNDRY_RESOURCE') {
        [pscustomobject]@{ SecretName = 'anthropic-foundry-api-key'; Env = 'ANTHROPIC_FOUNDRY_API_KEY'; Lights = 'claude-foundry'; EntraFallbackOnly = $true; EndpointEnvs = @()
            Members = @([pscustomobject]@{ Name = 'claude-foundry'; Type = 'anthropic-foundry'; EndpointEnv = $EndpointEnv; BaseUrl = $BaseUrl }) }
    }
    $script:steps.Clear(); $script:actions.Clear()
    $env:ANTHROPIC_FOUNDRY_RESOURCE = $null
    $problems = @(Get-EntraEndpointProblems -Pair (New-FoundryPair))
    Assert-True ($problems.Count -eq 1 -and $problems[0] -like '*ANTHROPIC_FOUNDRY_RESOURCE is unset*' -and $script:actions.Count -eq 1 -and $script:actions[0] -like 'set ANTHROPIC_FOUNDRY_RESOURCE*') 'An unset Foundry resource was not reported with its set action.'
    $script:actions.Clear(); $env:ANTHROPIC_FOUNDRY_RESOURCE = 'helios aijcut'
    $problems = @(Get-EntraEndpointProblems -Pair (New-FoundryPair))
    Assert-True ($problems.Count -eq 1 -and $problems[0] -notlike '*helios aijcut*' -and $script:actions[0] -like 'fix ANTHROPIC_FOUNDRY_RESOURCE*') 'A malformed Foundry resource was not reported, or its value leaked.'
    $script:actions.Clear(); $env:ANTHROPIC_FOUNDRY_RESOURCE = 'helios-aijcut'
    Assert-True (@(Get-EntraEndpointProblems -Pair (New-FoundryPair)).Count -eq 0 -and $script:actions.Count -eq 0) 'A bare Foundry resource name was rejected.'
    $env:ANTHROPIC_FOUNDRY_RESOURCE = $null
    Assert-True (@(Get-EntraEndpointProblems -Pair (New-FoundryPair -BaseUrl 'https://helios-aijcut.services.ai.azure.com/anthropic')).Count -eq 0) 'A config baseUrl did not override the unset variable.'
    $env:ANTHROPIC_FOUNDRY_RESOURCE = 'helios-aijcut'
    $problems = @(Get-EntraEndpointProblems -Pair (New-FoundryPair -BaseUrl 'ftp://inert'))
    Assert-True ($problems.Count -eq 1 -and $problems[0] -like 'providers.claude-foundry.baseUrl*' -and $script:actions[0] -like 'fix providers.claude-foundry.baseUrl*') 'A rejected config baseUrl was not reported ahead of the valid variable.'
    $script:actions.Clear()
    $problems = @(Get-EntraEndpointProblems -Pair (New-FoundryPair -EndpointEnv ''))
    Assert-True ($problems.Count -eq 1 -and $problems[0] -like '*blank endpointEnv*') 'A blank endpointEnv was not reported.'
    $script:actions.Clear()
    $env:AZURE_OPENAI_ENDPOINT = 'https://inert.openai.azure.com/'
    $aoaiPair = [pscustomobject]@{ SecretName = 'azure-openai-api-key'; Env = 'AZURE_OPENAI_API_KEY'; Lights = 'azure-openai'; Members = @([pscustomobject]@{ Name = 'azure-openai'; Type = 'azure-openai'; EndpointEnv = 'AZURE_OPENAI_ENDPOINT'; BaseUrl = '' }); EntraFallbackOnly = $true; EndpointEnvs = @('AZURE_OPENAI_ENDPOINT') }
    Assert-True (@(Get-EntraEndpointProblems -Pair $aoaiPair).Count -eq 0) 'The Foundry rule broke an azure-openai pair.'
    $fallback = Get-EntraFallbackText -Pair $aoaiPair
    Assert-True ($fallback.Factory -eq 'CreateAzureOpenAi' -and $fallback.Endpoint -like '*AZURE_OPENAI_ENDPOINT*' -and $fallback.Role -like '*Cognitive Services OpenAI User*') 'azure-openai fallback wording changed.'
    $fallback = Get-EntraFallbackText -Pair (New-FoundryPair)
    Assert-True ($fallback.Factory -eq 'CreateAnthropicFoundry' -and $fallback.Endpoint -like '*ANTHROPIC_FOUNDRY_RESOURCE*' -and $fallback.Role -like '*Cognitive Services User*') 'anthropic-foundry fallback wording is wrong.'
    $env:AZURE_OPENAI_ENDPOINT = $null

    # The secretless loop with a Foundry entry: resource first, then key or Entra fallback.
    $env:ANTHROPIC_FOUNDRY_RESOURCE = $null
    $step = Run-Loop $true 'ready' 'anthropic-foundry'
    Assert-True ($step.State -eq 'needs-owner' -and $step.Detail -like '*ANTHROPIC_FOUNDRY_RESOURCE is unset*' -and $step.Detail -like '*CreateAnthropicFoundry*' -and $script:actions.Count -eq 1) 'Secretless anthropic-foundry with no resource was not reported.'
    $env:ANTHROPIC_FOUNDRY_RESOURCE = 'helios-aijcut'
    $env:ANTHROPIC_FOUNDRY_API_KEY = 'dummy-key-must-not-leak'
    $step = Run-Loop $false 'needs-owner' 'anthropic-foundry'
    Assert-True ($step.State -eq 'ok' -and $step.Detail -notlike '*dummy-key-must-not-leak*' -and $script:actions.Count -eq 0) 'Secretless anthropic-foundry with a set key was not ok, or leaked the key.'
    $env:ANTHROPIC_FOUNDRY_API_KEY = $null
    $step = Run-Loop $true 'ready' 'anthropic-foundry'
    Assert-True ($step.State -eq 'ok' -and $step.Detail -like '*az CLI login*' -and $step.Detail -like '*CreateAnthropicFoundry falls back to Entra ID*') 'Secretless anthropic-foundry Entra fallback through a usable az lane was not ok.'
    $step = Run-Loop $false 'needs-owner' 'anthropic-foundry'
    Assert-True ($step.State -eq 'needs-owner' -and $script:actions.Count -eq 1) 'Secretless anthropic-foundry Entra fallback with a broken az lane was credited.'

    # A preset Foundry key counts only with a usable resource (same rule as azure-openai).
    $script:steps.Clear(); $script:actions.Clear()
    $env:ANTHROPIC_FOUNDRY_API_KEY = 'dummy-key-must-not-leak'; $env:ANTHROPIC_FOUNDRY_RESOURCE = $null
    $vaultPairs = @(New-FoundryPair)
    . $presetBlock
    Assert-True ($script:steps[0].State -eq 'needs-owner' -and $script:steps[0].Detail -like '*ANTHROPIC_FOUNDRY_RESOURCE is unset*' -and $script:steps[0].Detail -notlike '*dummy-key-must-not-leak*') 'A preset Foundry key with no resource was reported as skipped.'
    $script:steps.Clear(); $script:actions.Clear()
    $env:ANTHROPIC_FOUNDRY_RESOURCE = 'helios-aijcut'
    . $presetBlock
    Assert-True ($script:steps[0].State -eq 'skipped') 'A preset Foundry key with a usable resource was not skipped.'
    $env:ANTHROPIC_FOUNDRY_RESOURCE = $null; $env:ANTHROPIC_FOUNDRY_API_KEY = $null

    # The provider walk itself, run over an inert providers table: a Foundry entry with
    # a secret becomes an Entra-fallback-only vault pair (no azure-openai EndpointEnvs,
    # a typed member), a secretless one is judged later, a blank one keeps the Foundry
    # default endpoint variable, none is a direct-key provider, and a reader of
    # another family on the Foundry key variable is an incompatible sharing.
    $walk = $auto.Find({ param($n) $n -is [System.Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -eq '$null -ne $aihubProviders' }, $true)
    if (-not $walk) { throw 'Provider walk not found.' }
    $walkBlock = [scriptblock]::Create($walk.Extent.Text)
    $envNameComparer = [StringComparer]::Ordinal
    function Run-Walk($Providers) {
        $script:steps.Clear(); $script:actions.Clear()
        $aihubProviders = $Providers
        $aihubParseOk = $false; $aihubParsed = $null
        $blankEnvProviders = [System.Collections.Generic.List[object]]::new()
        $directKeyProviders = [System.Collections.Generic.List[object]]::new()
        $secretlessEntraProviders = [System.Collections.Generic.List[object]]::new()
        $envReaders = [System.Collections.Generic.Dictionary[string, object]]::new($envNameComparer)
        $conflictingEnvs = @(); $conflictingEnvSet = New-EnvNameSet; $incompatibleEnvSet = New-EnvNameSet
        $vaultPairs = @()
        . $walkBlock
        return [pscustomobject]@{ Pairs = @($vaultPairs); Readers = $envReaders; Blank = @($blankEnvProviders); Direct = @($directKeyProviders); Secretless = @($secretlessEntraProviders) }
    }
    $walkProviders = [pscustomobject]@{
        'claude-foundry'     = [pscustomobject]@{ type = 'anthropic-foundry'; model = 'claude-sonnet-4-6'; apiKeySecretName = 'anthropic-foundry-api-key' }
        'foundry-secretless' = [pscustomobject]@{ type = 'anthropic-foundry'; model = 'x'; endpointEnv = 'FOUNDRY_ALT'; baseUrl = 'https://inert.services.ai.azure.com' }
        'foundry-blank'      = [pscustomobject]@{ type = 'anthropic-foundry'; model = 'x'; apiKeyEnv = '' }
        'openai'             = [pscustomobject]@{ type = 'openai'; model = 'x'; apiKeySecretName = 'openai-api-key' }
    }
    # The blank entry is judged inside the walk: with the resource unset its endpoint
    # step is the one owner step; with a usable resource it is a supported Entra state.
    $env:ANTHROPIC_FOUNDRY_RESOURCE = $null
    $walked = Run-Walk $walkProviders
    Assert-True (@($script:steps | Where-Object { $_.State -eq 'needs-owner' }).Count -eq 1 -and $script:steps[0].Step -eq 'provider:foundry-blank:endpoint' -and $script:steps[0].Detail -like '*ANTHROPIC_FOUNDRY_RESOURCE is unset*') 'A blank-apiKeyEnv Foundry entry with no resource did not raise exactly its endpoint step.'
    $env:ANTHROPIC_FOUNDRY_RESOURCE = 'helios-aijcut'
    $walked = Run-Walk $walkProviders
    Assert-True (@($script:steps | Where-Object { $_.Step -eq 'provider:foundry-blank' -and $_.State -eq 'skipped' -and $_.Detail -like '*CreateAnthropicFoundry uses Entra ID*' }).Count -eq 1) 'A blank-apiKeyEnv Foundry entry with a usable resource was not reported as the supported Entra state.'
    $env:ANTHROPIC_FOUNDRY_RESOURCE = $null
    $foundryPair = @($walked.Pairs | Where-Object { $_.Env -eq 'ANTHROPIC_FOUNDRY_API_KEY' })
    Assert-True ($walked.Pairs.Count -eq 2 -and $foundryPair.Count -eq 1 -and $foundryPair[0].SecretName -eq 'anthropic-foundry-api-key' -and $foundryPair[0].EntraFallbackOnly -and @($foundryPair[0].EndpointEnvs).Count -eq 0) 'A Foundry entry with a secret did not become an Entra-fallback-only vault pair.'
    Assert-True (@($foundryPair[0].Members).Count -eq 1 -and $foundryPair[0].Members[0].Type -eq 'anthropic-foundry' -and $foundryPair[0].Members[0].EndpointEnv -eq 'ANTHROPIC_FOUNDRY_RESOURCE' -and $foundryPair[0].Members[0].BaseUrl -eq '') 'The Foundry pair member does not carry the default endpoint variable.'
    Assert-True ($walked.Readers.ContainsKey('ANTHROPIC_FOUNDRY_API_KEY') -and $walked.Readers['ANTHROPIC_FOUNDRY_API_KEY'][0].Family -eq 'anthropic-foundry') 'The Foundry key variable was not registered under its own family.'
    Assert-True ($walked.Secretless.Count -eq 1 -and $walked.Secretless[0].Name -eq 'foundry-secretless' -and $walked.Secretless[0].EndpointEnv -eq 'FOUNDRY_ALT' -and $walked.Secretless[0].BaseUrl -eq 'https://inert.services.ai.azure.com') 'A secretless Foundry entry lost its endpointEnv or baseUrl.'
    Assert-True ($walked.Blank.Count -eq 1 -and $walked.Blank[0].Name -eq 'foundry-blank' -and $walked.Blank[0].EndpointEnv -eq 'ANTHROPIC_FOUNDRY_RESOURCE') 'A blank-apiKeyEnv Foundry entry lost the Foundry default endpoint variable.'
    Assert-True (@($walked.Direct | Where-Object { $_.Type -eq 'anthropic-foundry' }).Count -eq 0 -and @($script:steps | Where-Object { $_.State -eq 'needs-owner' }).Count -eq 0) 'A Foundry entry was treated as a direct-key provider, or the walk raised a spurious owner step.'
    $walked = Run-Walk ([pscustomobject]@{
        'claude-foundry' = [pscustomobject]@{ type = 'anthropic-foundry'; model = 'x'; apiKeySecretName = 'anthropic-foundry-api-key' }
        'anthropic'      = [pscustomobject]@{ type = 'anthropic'; model = 'x'; apiKeyEnv = 'ANTHROPIC_FOUNDRY_API_KEY'; apiKeySecretName = 'anthropic-api-key' }
    })
    Assert-True ($walked.Pairs.Count -eq 0 -and @($script:steps | Where-Object { $_.Step -eq 'ANTHROPIC_FOUNDRY_API_KEY' -and $_.State -eq 'needs-owner' }).Count -eq 1 -and @($script:actions | Where-Object { $_ -like 'give the consumers sharing ANTHROPIC_FOUNDRY_API_KEY distinct apiKeyEnv names*' }).Count -eq 1) 'An Anthropic API entry sharing the Foundry key variable was not reported incompatible.'

    # --- 12. auth-doctor reads the Foundry key variable as its own credential family ----
    Import-Functions $doctor
    $repoRoot = $root
    $script:EnvNameComparer = [StringComparer]::Ordinal
    $configPath = Join-Path $temp 'aihub-foundry.json'
    @{ providers = @{ 'claude-foundry' = @{ type = 'anthropic-foundry'; model = 'claude-sonnet-4-6' }; 'models-shared' = @{ type = 'github-models'; model = 'x'; apiKeyEnv = 'ANTHROPIC_FOUNDRY_API_KEY' } } } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $configPath
    $env:AIHUB_CONFIG = $configPath
    $script:aihubConfigState = $null; $script:aihubEnvReaders = $null; $script:aihubVariableDefects = $null
    $readers = Get-AIHubEnvReaders
    Assert-True ($readers.ContainsKey('ANTHROPIC_FOUNDRY_API_KEY') -and @($readers['ANTHROPIC_FOUNDRY_API_KEY'] | Where-Object { $_.Type -eq 'anthropic-foundry' -and $_.Family -eq 'anthropic-foundry' }).Count -eq 1) 'auth-doctor did not register the Foundry key variable under its own family.'
    Assert-True (@(Get-AIHubVariableDefects | Where-Object { $_.Kind -eq 'incompatible' -and $_.Env -eq 'ANTHROPIC_FOUNDRY_API_KEY' }).Count -eq 1) 'A Models entry sharing the Foundry key variable was not reported incompatible by auth-doctor.'
    $env:AIHUB_CONFIG = $null
    $script:aihubConfigState = $null; $script:aihubEnvReaders = $null; $script:aihubVariableDefects = $null

    # --- 13. rest-connect never offers the Foundry key variable to api.github.com -------
    Import-Functions $rest
    $script:aihubMemberSchemas = $restSchemas
    $configPath = Join-Path $temp 'aihub-foundry-rest.json'
    @{ providers = @{ 'claude-foundry' = @{ type = 'anthropic-foundry'; model = 'x' }; 'models-shared' = @{ type = 'github-models'; model = 'x'; apiKeyEnv = 'ANTHROPIC_FOUNDRY_API_KEY' }; 'models-public' = @{ type = 'github-models'; model = 'x' } } } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $configPath
    $env:AIHUB_CONFIG = $configPath
    $candidates = @(Get-ConfiguredGitHubModelsEnvs)
    Assert-True (($candidates -contains 'GITHUB_MODELS_TOKEN') -and ($candidates -notcontains 'ANTHROPIC_FOUNDRY_API_KEY') -and $script:nonGitHubReaderEnvs.Contains('ANTHROPIC_FOUNDRY_API_KEY')) 'rest-connect offered the Foundry key variable as a GitHub candidate.'
    $env:AIHUB_CONFIG = $null
} finally {
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output "Passed $script:cases offline auth config-contract cases."
