# Offline contract for the board-setup readiness leg (step f) of scripts/setup/setup-all.ps1.
# Imports the pure Get-BoardSetupReadiness function via the AST (same pattern as the auth
# lanes) and exercises it against temp board-config fixtures. No network, no repo state, no
# login entrypoints -- the function only reads a JSON file and reports ready/not-ready.
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

$setupAll = Read-Ast 'scripts/setup/setup-all.ps1'
Import-Functions $setupAll

$script:cases = 0
function Assert-True($Value, $Message) { if (-not $Value) { throw $Message }; $script:cases++ }

$dir = Join-Path ([IO.Path]::GetTempPath()) ("board-setup-test-" + [Guid]::NewGuid())
New-Item -ItemType Directory -Path $dir -Force | Out-Null
function Write-Fixture($Name, $Content) {
    $path = Join-Path $dir $Name
    Set-Content -LiteralPath $path -Value $Content -NoNewline
    return $path
}

try {
    # 1. Missing file is not-ready and names the artifact, never throws.
    $missing = Join-Path $dir 'does-not-exist.json'
    $r = Get-BoardSetupReadiness -ConfigPath $missing
    Assert-True (-not $r.Ready -and $r.Detail -match 'not found') 'Missing board-config was not reported.'

    # 2. Non-parsing JSON is caught and surfaced, never thrown.
    $bad = Write-Fixture 'bad.json' '{ not valid json'
    $r = Get-BoardSetupReadiness -ConfigPath $bad
    Assert-True (-not $r.Ready -and $r.Detail -match 'does not parse') 'Malformed board-config threw instead of reporting.'

    # 3. Valid JSON without boardConfiguration is not-ready.
    $noBc = Write-Fixture 'nobc.json' '{ "somethingElse": 1 }'
    $r = Get-BoardSetupReadiness -ConfigPath $noBc
    Assert-True (-not $r.Ready -and $r.Detail -match 'no boardConfiguration') 'Board-config without boardConfiguration was accepted.'

    # 4. boardConfiguration missing name or projectNumber is not-ready.
    foreach ($partial in @('{ "boardConfiguration": { "organization": "x" } }',
            '{ "boardConfiguration": { "name": "B" } }',
            '{ "boardConfiguration": { "projectNumber": 3 } }')) {
        $r = Get-BoardSetupReadiness -ConfigPath (Write-Fixture 'partial.json' $partial)
        Assert-True (-not $r.Ready -and $r.Detail -match 'missing a name or projectNumber') 'Incomplete boardConfiguration was accepted.'
    }

    # 5. Complete board with no customFields is ready and counts zero fields; a blank
    #    organization is rendered as (owner unset) rather than an empty owner=.
    $noFields = Write-Fixture 'nofields.json' '{ "boardConfiguration": { "name": "B", "projectNumber": 3 } }'
    $r = Get-BoardSetupReadiness -ConfigPath $noFields
    Assert-True ($r.Ready -and $r.Detail -match "'B'" -and $r.Detail -match '\(owner unset\)' -and $r.Detail -match '0 custom fields') 'Complete-but-empty board was not reported ready.'

    # 6. Custom fields are summed across every tier (2 + 3 = 5) and the owner is shown.
    $withFields = Write-Fixture 'withfields.json' (@{
            boardConfiguration = @{ name = 'HELIOS'; organization = 'helios-org'; projectNumber = 7 }
            customFields       = @{
                tier1 = @{ fields = @('A', 'B') }
                tier2 = @{ fields = @('C', 'D', 'E') }
            }
        } | ConvertTo-Json -Depth 5)
    $r = Get-BoardSetupReadiness -ConfigPath $withFields
    Assert-True ($r.Ready -and $r.Detail -match 'owner=helios-org' -and $r.Detail -match 'project #7' -and $r.Detail -match '5 custom fields') 'Custom fields were not summed across tiers.'

    # 7. The repository's real persisted artifact stays ready -- a guard against the
    #    shipped board-config.json drifting out of the shape this component expects.
    $repoConfig = Join-Path $root 'scripts/config/board-config.json'
    if (Test-Path -LiteralPath $repoConfig) {
        $r = Get-BoardSetupReadiness -ConfigPath $repoConfig
        Assert-True ($r.Ready -and $r.Detail -match 'custom fields persisted') 'Shipped scripts/config/board-config.json is not readiness-ready.'
    }
}
finally {
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output "Passed $script:cases offline board-setup readiness cases."
