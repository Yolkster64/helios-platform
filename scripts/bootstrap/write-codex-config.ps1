#Requires -Version 7
<#
.SYNOPSIS
Renders the Codex CLI's MCP registration for THIS checkout into ~/.codex/config.toml:
the [mcp_servers.helios] table with the server project path resolved to an absolute
path. Dry-run by default (prints the TOML), -Apply writes, -Force is required before an
existing file is touched.

.DESCRIPTION
docs/mcp/CLIENT_SETUP.md used to ask the operator to hand-edit a "/path/to/helios-platform"
placeholder. This script renders the real path instead, because Codex launches MCP servers
from its own working directory: the repo-relative "src/mcp/HELIOS.Mcp" that works for the
repo-scoped .mcp.json and .vscode/mcp.json does not resolve there.

Rendered TOML (paths are TOML basic strings; backslashes are escaped so a Windows
checkout renders a valid file):

  [mcp_servers.helios]
  command = "dotnet"
  args = ["run", "--project", "<repo>/src/mcp/HELIOS.Mcp", "-c", "Release"]
  env = { HELIOS_REPO_ROOT = "<repo>" }

Write policy. The file belongs to the operator and carries Codex settings this script
knows nothing about, so it is never replaced wholesale:

  no file                 -> created, directory included               (-Apply)
  file, no helios table   -> refused without -Force; -Force APPENDS the table
  file, same helios table -> unchanged (idempotent; exit 0)
  file, other helios table-> refused without -Force; -Force REPLACES only the
                             [mcp_servers.helios] table plus any [mcp_servers.helios.*]
                             sub-table; every other line of the file is preserved

Without -Apply nothing is written: the rendered TOML and the planned action are printed
so the operator can review them first (repo dry-run convention).

.PARAMETER Path
Target file. Defaults to ~/.codex/config.toml, the Codex CLI's user configuration. A
relative or ~-prefixed value is resolved against the current PowerShell location once, up
front, and every message (and the -Json path field) then carries the absolute path.

.PARAMETER RepoRoot
Checkout to register. Defaults to the repository that contains this script.

.PARAMETER Force
Permit modifying an EXISTING file (append or replace the helios table, as above).

.PARAMETER Apply
Write the file. Without it the script is a dry run.

.PARAMETER SkipPlaywright
Render only the helios table. By default the block also carries
[mcp_servers.playwright] (the pinned @playwright/mcp package via npx), the same
browser-automation server .mcp.json and .vscode/mcp.json register for Claude Code and
Copilot, so all three clients drive the same browser tool.

.PARAMETER Json
Emit ONE object and nothing else on stdout:
  {script, generatedUtc, mode, path, repoRoot, mcpProject, playwright, fileExists, action,
   written, message, exitCode}
action is one of create | append-section | replace-section | unchanged | refused |
precondition-failed. playwright is the pinned @playwright/mcp package rendered next to
the helios table, or null when -SkipPlaywright was given.

.EXAMPLE
pwsh scripts/bootstrap/write-codex-config.ps1
# dry run: prints the rendered TOML and what -Apply would do to ~/.codex/config.toml

.EXAMPLE
pwsh scripts/bootstrap/write-codex-config.ps1 -Apply
# creates ~/.codex/config.toml; refuses (exit 1) if it already exists and differs

.EXAMPLE
pwsh scripts/bootstrap/write-codex-config.ps1 -Apply -Force
# updates the helios table inside an existing config, keeping every other setting

.EXAMPLE
pwsh scripts/bootstrap/write-codex-config.ps1 -Path ./codex-config.toml -Apply
# renders to a file of your choosing (useful for review or for a second machine)

.NOTES
Exit codes: 0 = success (written, already up to date, or a clean dry run);
1 = refused (existing file without -Force) or the write itself failed;
2 = precondition missing (src/mcp/HELIOS.Mcp is not in the checkout, so there is nothing
to register).
Secrets: none are read, rendered, or printed. The env table carries a directory PATH
only; provider keys stay in the environment or Key Vault (config/aihub.json names them).
#>
[CmdletBinding()]
param(
    [string]$Path,

    [string]$RepoRoot,

    [switch]$Force,

    [switch]$Apply,

    [switch]$Json,

    [switch]$SkipPlaywright
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$mode = if ($Apply) { 'apply' } else { 'dry-run' }
# The Playwright MCP server (browser automation) is rendered in the same managed block,
# right after the helios table, so one re-render keeps both current. Pinned: a floating
# tag would turn someone else's release into a changed tool surface. On Windows Codex
# spawns the command directly, so the npm shim needs its .cmd extension there.
$playwrightPackage = '@playwright/mcp@0.0.80'
$npxCommand = if ($IsWindows) { 'npx.cmd' } else { 'npx' }

# -Json promises one object and nothing else on stdout (auth-doctor convention), so every
# progress line is gated on -not $Json.
function Write-Report {
    param([string]$Message = '')
    if (-not $Json) { Write-Host $Message }
}

# TOML basic-string escaping. A Windows checkout path carries backslashes, and one
# unescaped backslash is a TOML parse error that silently drops the whole server entry
# from Codex's view, which is the exact failure this script exists to prevent.
function ConvertTo-TomlBasicString {
    param([Parameter(Mandatory)][string]$Value)
    '"' + ($Value -replace '\\', '\\' -replace '"', '\"') + '"'
}

# Single exit path so -Json always emits exactly one object, on success and failure alike.
function Complete-Run {
    param(
        [Parameter(Mandatory)][int]$ExitCode,
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][string]$Message,
        [bool]$Written = $false,
        [bool]$FileExists = $false
    )
    if ($Json) {
        [ordered]@{
            script       = 'scripts/bootstrap/write-codex-config.ps1'
            generatedUtc = (Get-Date).ToUniversalTime().ToString('o')
            mode         = $mode
            path         = $Path
            repoRoot     = $RepoRoot
            mcpProject   = 'src/mcp/HELIOS.Mcp'
            playwright   = $(if ($SkipPlaywright) { $null } else { $playwrightPackage })
            fileExists   = $FileExists
            action       = $Action
            written      = $Written
            message      = $Message
            exitCode     = $ExitCode
        } | ConvertTo-Json -Depth 3
    }
    else {
        Write-Report $Message
    }
    exit $ExitCode
}

# The target path is settled BEFORE the preconditions so a -Json precondition report names
# the real file instead of an empty string. It is normalized once, here, because the
# existence guard (Test-Path, provider-relative to $PWD) and the write below
# ([System.IO.File]::WriteAllLines, relative to the .NET process directory, which pwsh does
# not move on Set-Location) would otherwise resolve a relative or ~-prefixed -Path to two
# different files: the guard would clear one path while the write clobbered another.
if (-not $Path) {
    $Path = Join-Path $HOME '.codex' 'config.toml'
}
$Path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

# --- Preconditions: a checkout that actually contains the server project ---------------
if (-not $RepoRoot) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
}
elseif (Test-Path -LiteralPath $RepoRoot -PathType Container) {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}
else {
    Complete-Run -ExitCode 2 -Action 'precondition-failed' -Message "write-codex-config: FAILED PRECONDITION - RepoRoot '$RepoRoot' is not a directory."
}
$mcpProjectDir = Join-Path $RepoRoot 'src' 'mcp' 'HELIOS.Mcp'
if (-not (Test-Path -LiteralPath (Join-Path $mcpProjectDir 'HELIOS.Mcp.csproj') -PathType Leaf)) {
    Complete-Run -ExitCode 2 -Action 'precondition-failed' -Message ("write-codex-config: FAILED PRECONDITION - $mcpProjectDir/HELIOS.Mcp.csproj not found; " +
        'this is not a HELIOS checkout (or src/mcp is missing), so there is no server to register.')
}

Write-Report "write-codex-config: mode=$mode path=$Path repo=$RepoRoot"

# --- Render -------------------------------------------------------------------------------
# The explanatory comment lives INSIDE the table (after the header line) on purpose: the
# replace path swaps the whole table, header to next header, so comments placed above the
# header would survive every re-render and pile up.
$rendered = @(
    '[mcp_servers.helios]',
    '# Rendered by scripts/bootstrap/write-codex-config.ps1 (HELIOS). Re-run it after moving',
    '# the checkout: the project path is absolute because Codex starts MCP servers from its',
    '# own working directory, where a repo-relative path would not resolve.',
    'command = "dotnet"',
    ('args = ["run", "--project", {0}, "-c", "Release"]' -f (ConvertTo-TomlBasicString $mcpProjectDir)),
    ('env = {{ HELIOS_REPO_ROOT = {0} }}' -f (ConvertTo-TomlBasicString $RepoRoot))
)
if (-not $SkipPlaywright) {
    $rendered += @(
        '',
        '[mcp_servers.playwright]',
        '# Rendered by scripts/bootstrap/write-codex-config.ps1 (HELIOS): the same Playwright MCP',
        '# server Claude Code (.mcp.json) and Copilot (.vscode/mcp.json) use. Headed by default;',
        '# add "--headless" for a display-less host. Its browser profile is persistent, so a',
        '# site you log into stays logged in for the next session - use --isolated to avoid that.',
        ('command = "{0}"' -f $npxCommand),
        ('args = ["-y", {0}]' -f (ConvertTo-TomlBasicString $playwrightPackage))
    )
}

# --- Inspect the existing file ------------------------------------------------------------
$fileExists = Test-Path -LiteralPath $Path -PathType Leaf
$existing = @()
if ($fileExists) { $existing = @(Get-Content -LiteralPath $Path) }

# Locate our table: the header line, then everything up to (excluding) the next table
# header that is not one of our own sub-tables. Trailing blank lines are left outside the
# range so they keep separating us from whatever follows after a replace.
$start = -1
$end = $existing.Count
for ($i = 0; $i -lt $existing.Count; $i++) {
    if ($existing[$i] -match '^\s*\[mcp_servers\.helios\]\s*(#.*)?$') { $start = $i; break }
}
if ($start -ge 0) {
    for ($i = $start + 1; $i -lt $existing.Count; $i++) {
        # Our block is the helios table, its sub-tables, and the playwright table that this
        # script renders right after it; the next foreign header ends the block.
        if ($existing[$i] -match '^\s*\[' -and $existing[$i] -notmatch '^\s*\[mcp_servers\.(helios\.|playwright(\]|\.))') { $end = $i; break }
    }
    while ($end - 1 -gt $start -and [string]::IsNullOrWhiteSpace($existing[$end - 1])) { $end-- }
}

$sectionMatches = $false
if ($start -ge 0) {
    $current = @($existing[$start..($end - 1)] | ForEach-Object { $_.TrimEnd() })
    # Ordinal, case-sensitive comparison: a path that differs only by case is a different
    # path on Linux, and "unchanged" must never hide that.
    $sectionMatches = ($current.Count -eq $rendered.Count) -and
    (@(0..($rendered.Count - 1) | Where-Object { -not [string]::Equals($current[$_], $rendered[$_], [System.StringComparison]::Ordinal) }).Count -eq 0)
}

$action = if (-not $fileExists) { 'create' }
elseif ($start -lt 0) { if ($Force) { 'append-section' } else { 'refused' } }
elseif ($sectionMatches) { 'unchanged' }
elseif ($Force) { 'replace-section' }
else { 'refused' }

$why = switch ($action) {
    'create' { 'the file does not exist; it will be created with the table below' }
    'append-section' { 'the file exists without a [mcp_servers.helios] table; -Force appends it, other lines untouched' }
    'unchanged' { 'the file already carries exactly this table; nothing to do' }
    'replace-section' { "the file's [mcp_servers.helios] table differs (lines $($start + 1)-$end); -Force replaces just that table" }
    'refused' {
        if ($start -lt 0) { 'the file exists and has no [mcp_servers.helios] table; modifying an existing file needs -Force' }
        else { "the file's [mcp_servers.helios] table differs (lines $($start + 1)-$end); replacing it needs -Force" }
    }
}

Write-Report ''
Write-Report ('-- rendered [mcp_servers.helios]{0} --' -f $(if ($SkipPlaywright) { '' } else { ' + [mcp_servers.playwright]' }))
foreach ($line in $rendered) { Write-Report "  $line" }
Write-Report ''
Write-Report '-- plan --'
Write-Report "  file exists: $(if ($fileExists) { 'yes' } else { 'no' })"
Write-Report "  action: $action ($why)"

# --- Dry run ends here ----------------------------------------------------------------------
if (-not $Apply) {
    $applyCommand = 'pwsh scripts/bootstrap/write-codex-config.ps1 -Apply'
    if ($action -eq 'refused') { $applyCommand += ' -Force' }
    if ($PSBoundParameters.ContainsKey('Path')) { $applyCommand += " -Path `"$Path`"" }
    # -RepoRoot travels with the replay too: without it the replayed command would register
    # the script's own checkout instead of the one this dry run just previewed.
    if ($PSBoundParameters.ContainsKey('RepoRoot')) { $applyCommand += " -RepoRoot `"$RepoRoot`"" }
    Write-Report "  to apply: $applyCommand"
    Complete-Run -ExitCode 0 -Action $action -FileExists $fileExists -Message 'Dry run complete - nothing was written. Re-run with -Apply to write the file.'
}

# --- Apply -----------------------------------------------------------------------------------
if ($action -eq 'refused') {
    Complete-Run -ExitCode 1 -Action $action -FileExists $fileExists -Message ("write-codex-config: REFUSED - $why. Nothing was written. " +
        'Re-run with -Force to modify the existing file, or -Path <file> to render elsewhere.')
}
if ($action -eq 'unchanged') {
    Complete-Run -ExitCode 0 -Action $action -FileExists $fileExists -Message "write-codex-config: already up to date - $Path carries this table. Nothing was written."
}

$newLines = switch ($action) {
    'create' { $rendered }
    'append-section' {
        # One blank line between the operator's last line and our header keeps TOML
        # readable; none when the file already ends blank or is empty.
        $separator = @(if ($existing.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($existing[-1])) { '' })
        @($existing) + $separator + $rendered
    }
    'replace-section' {
        $before = @(if ($start -gt 0) { $existing[0..($start - 1)] })
        $after = @(if ($end -lt $existing.Count) { $existing[$end..($existing.Count - 1)] })
        $before + $rendered + $after
    }
}

# The exact mutation is printed BEFORE it runs (apply-repo-settings.ps1 convention): if the
# write dies half-way the operator still knows what was being attempted. The replay line
# for that case is built here, before the attempt, and carries -Path (now absolute) and,
# when given, -RepoRoot, so replaying it targets the same file and the same checkout.
$replayCommand = "pwsh scripts/bootstrap/write-codex-config.ps1 -Apply$(if ($Force) { ' -Force' }) -Path `"$Path`""
if ($PSBoundParameters.ContainsKey('RepoRoot')) { $replayCommand += " -RepoRoot `"$RepoRoot`"" }
Write-Report "  [apply] $action -> $Path"
try {
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $parent -Force
    }
    # UTF-8 without BOM: a BOM is not valid at the start of a TOML document.
    [System.IO.File]::WriteAllLines($Path, [string[]]$newLines, [System.Text.UTF8Encoding]::new($false))
}
catch {
    Complete-Run -ExitCode 1 -Action $action -FileExists $fileExists -Message "write-codex-config: FAILED - could not write $Path ($($_.Exception.Message)). Replay: $replayCommand"
}

Complete-Run -ExitCode 0 -Action $action -Written $true -FileExists $true -Message ("write-codex-config: $action complete - $Path now registers the helios MCP server$(if ($SkipPlaywright) { '' } else { ' and the playwright MCP server' }). " +
    'Verify from Codex with: codex mcp list   (or open a codex session and check the tool list).')
