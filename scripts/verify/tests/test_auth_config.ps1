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
    'IDENTITY_ENDPOINT','IDENTITY_HEADER','MSI_ENDPOINT','MSI_SECRET','AZURE_OPENAI_ENDPOINT','AZURE_OPENAI_API_KEY','AIHUB_CONFIG','PATH')
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
    $loop = $auto.Find({ param($n) $n -is [System.Management.Automation.Language.ForEachStatementAst] -and $n.Extent.Text.StartsWith('foreach ($secretless in $secretlessAzureOpenAi)') }, $true)
    if (-not $loop) { throw 'Secretless azure-openai loop not found.' }
    $loopBlock = [scriptblock]::Create($loop.Extent.Text)
    $aihubConfigLabel = 'AIHUB_CONFIG'
    $script:steps = [System.Collections.Generic.List[object]]::new()
    $script:actions = [System.Collections.Generic.List[string]]::new()
    function Add-Step { param([string]$Step, [string]$State, [string]$Detail) $script:steps.Add([pscustomobject]@{ Step = $Step; State = $State; Detail = $Detail }) }
    function Add-OwnerAction { param([string]$Text, [string]$Env = '', [switch]$Imported) $script:actions.Add($Text) }
    function Test-RawImdsManagedIdentity { return $false }
    function Run-Loop([bool]$Usable, [string]$State) {
        $script:steps.Clear(); $script:actions.Clear(); $selectedCredentialProofCache.Clear()
        $secretlessAzureOpenAi = [System.Collections.Generic.List[object]]::new()
        $secretlessAzureOpenAi.Add([pscustomobject]@{ Name = 'aoai'; Env = 'AZURE_OPENAI_API_KEY'; EndpointEnv = 'AZURE_OPENAI_ENDPOINT' })
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
} finally {
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output "Passed $script:cases offline auth config-contract cases."
