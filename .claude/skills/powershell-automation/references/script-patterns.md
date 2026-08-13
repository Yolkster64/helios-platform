# Script patterns — idioms proven in this repo

*Versions and API claims mirror the cited repo files; update this file in the same PR
that changes them.*

All patterns are hoisted from working scripts — `scripts/bootstrap/setup-ai-clis.ps1`
is the exemplar; each section names the file that proves it.

## The $LASTEXITCODE pipeline trap

Piping a native command into anything that can stop the pipeline early
(`Select-Object -First 1`) can halt it before `$LASTEXITCODE` is assigned — and under
`Set-StrictMode -Version Latest`, reading a never-assigned `$LASTEXITCODE` is an
error. Capture everything into an array FIRST, then slice (`setup-ai-clis.ps1`,
`Get-CliVersion`, whose comment cites `verify-readiness.ps1` for the same pattern):

```powershell
$raw = @(& $Command.Source '--version' 2>$null)   # run to completion
if ($LASTEXITCODE -eq 0 -and $raw.Count -gt 0 -and $raw[0]) {
    $version = ([string]$raw[0]).Trim()            # THEN take the first line
}
```

## Get-Command -CommandType Application

When a script verifies a tool that another *process* will launch (AIHub spawns
`claude`, `codex`, ... as OS subprocesses), probe with `-CommandType Application`:

```powershell
Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
```

A PowerShell alias or function shadowing the name would satisfy a bare `Get-Command`,
pass setup, and then fail at first real invocation — an OS subprocess can never
resolve it (`setup-ai-clis.ps1`, `Get-CliCommand`). Invoke via `& $command.Source`
(the resolved path) for the same reason.

## Verify-only exit contract

Setup scripts carry a `-VerifyOnly` switch: report state, mutate nothing, communicate
through the exit code. `setup-ai-clis.ps1` documents its contract in the header
(0 = every non-skipped required CLI present; 2 = something missing), and
`connect-azure.ps1 -VerifyOnly` exits 0 when authenticated / non-zero when not (via
`Write-Error` under `$ErrorActionPreference = 'Stop'`), explicitly skipping
`Set-AzContext` because it mutates persisted state. Rules that fall out:

- verify mode never installs, never logs in, never prompts;
- distinct non-zero codes are part of the documented contract (2 is not a generic 1);
- optional components (the `hermes` spec entry) are reported honestly but never fail
  the run — claiming "4/4 present" while a fifth configured agent is missing would
  make the summary a lie.

## [pscustomobject] spec tables

Drive N-similar-things logic from a declarative table of `[pscustomobject]` entries,
not copy-pasted if-blocks. `setup-ai-clis.ps1` declares `$cliSpecs` — one object per
CLI with `Name`/`Command`/`NpmPackage`/`Optional`/`AgentShape`/`InstallHint`/`Auth` —
and a single loop consumes it. Results are emitted as `[pscustomobject]` rows too, so
the summary is plain pipeline work (`Where-Object` / `Format-Table`), and per-item
rationale lives as a comment on the spec entry it explains (see the `hermes` entry).

## Environment detection

Detect the hosting environment once, from documented env vars, and print what was
found (`setup-ai-clis.ps1`; same Cloud Shell probe in `connect-azure.ps1`):

```powershell
$inCloudShell = [bool]($env:AZUREPS_HOST_ENVIRONMENT -or $env:ACC_CLOUD -or $env:CLOUD_SHELL)
$environment = if ($inCloudShell) { 'Azure Cloud Shell' }
elseif ($env:CODESPACES) { 'GitHub Codespaces' }
else { 'local shell' }
```

Behavior differences (Cloud Shell is pre-authenticated and ships npm) branch off these
flags — never off heuristics like hostname patterns.

## The -f operator precedence trap

PowerShell's `-f` (format) operator binds TIGHTER than `+`. Concatenating a long
format string across lines without parentheses formats only the last fragment and
prints the earlier placeholders literally. This bit the repo; the fix and its warning
comment live in `scripts/fleet/stop-fleet.ps1`:

```powershell
# Parentheses around the concatenation matter: -f binds tighter than
# +, so without them the placeholders would print literally.
Write-Warning (("run {0}: {1} worker(s) could not be identity-verified and were left " +
    '... rerun stop-fleet.ps1 -RunId {0} once resolved.') -f
    $manifestRunId, $counts['pid-unverifiable'])
```

Rule: any `"..." + "..." -f $args` needs the concatenation parenthesized —
`(("a" + "b") -f $args)` — or `-f` grabs only the last string.

## Native-call error handling

Wrap external executables in one thin helper that checks `$LASTEXITCODE` and throws
with the full command line (`azure-oidc-setup.ps1`, `Invoke-Az`). Summarize captured
failure output instead of dumping it — `setup-ai-clis.ps1` keeps the last 5 npm lines
via `Select-Object -Last 5` under a `Write-Warning`. Plain error lines go to stderr
with `[Console]::Error.WriteLine` when `Write-Error`'s record format is unwanted
(same script, npm-missing case).
