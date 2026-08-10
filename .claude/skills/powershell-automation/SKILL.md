---
name: powershell-automation
description: PowerShell 7 conventions for HELIOS automation scripts — portability, error handling, and the rule that PS wraps the C# CLI rather than reimplementing logic. Use when writing or reviewing .ps1/.psm1 files.
---

# PowerShell — HELIOS Automation Layer

**Role**: PowerShell is the operator-facing wrapper layer. Business logic belongs in C#
(`helios-ai`, MCP server); scripts orchestrate, install, and glue. When a script grows
logic (routing, retries, parsing provider responses), port it into the C# hub instead.

## Hard rules

- **No hardcoded user paths.** `C:\Users\ADMIN\…` (endemic in `scripts/ai-services/`) is
  a defect: derive paths from `$PSScriptRoot` (see `scripts/ai-services/helios-ai.ps1`)
  or accept parameters. Scripts must work from any checkout location and in CI on Linux.
- **Cross-platform by default**: `Join-Path` over string concat, `[Environment]::GetFolderPath`,
  no drive-letter assumptions, no `-WindowStyle` unless guarded by `$IsWindows`.
- `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` at the top of
  every new script; `try/catch` only around the specific external call that can fail.
- Exit codes are the contract: `exit $LASTEXITCODE` after native calls; never swallow.
- Secrets come from environment variables — never parameters with defaults, never files
  in the repo. Validate presence and print the variable *name* (not value) when missing.

## Calling the AI hub from PowerShell

```powershell
# Thin wrapper pattern — logic stays in C#:
& "$PSScriptRoot/helios-ai.ps1" route code_review $diffText
if ($LASTEXITCODE -ne 0) { throw "AI routing failed" }
```

## Which LLM for which PowerShell work

| Work | Route |
|---|---|
| Reviewing scripts for portability/security | `code_review` → Claude |
| Generating a new wrapper/installer script | `code_generation` → Codex/GPT |
| DSC/winget configuration blocks | `code_generation`, verified against microsoft/WindowsDeveloperConfig patterns |

## CI

`ci-validation.yml` syntax-checks every `.ps1` with `shell: pwsh` on ubuntu-latest
(pwsh preinstalled — there is no actions/setup-powershell action). Keep scripts parseable
by `[scriptblock]::Create` and clean under PSScriptAnalyzer Error severity.
