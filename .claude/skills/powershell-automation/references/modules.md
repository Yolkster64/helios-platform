# PowerShell module landscape — what CI actually runs

*Versions and API claims mirror the cited repo files; update this file in the same PR
that changes them.*

## Pester — pinned 5.4.0, and the v4-syntax trap

`.github/workflows/code-checks.yml` installs Pester with an exact pin on its
windows-latest job:

```yaml
Install-Module -Name Pester -RequiredVersion 5.4.0 -Force -SkipPublisherCheck
```

and later runs `Invoke-Pester -Path $TestFile.FullName -PassThru` over every
`test-*-unit.ps1` in the tree (that step is `continue-on-error: true`, so failures are
visible but non-gating today). Write all Pester code as v5:

- **Two-phase model.** Pester 5 splits Discovery from Run: code sitting directly in a
  `Describe`/`Context` body or at file top level executes during *Discovery*, not with
  your tests. Setup goes in `BeforeAll`/`BeforeEach`; discovery-time data (for
  `-ForEach` generation) goes in `BeforeDiscovery` (Pester docs, migrations v4→v5).
- **Legacy assertion syntax is gone.** `10 | Should Be 10` (no dash) worked in v4 but
  is not supported by the pinned 5.4.0 — only `Should -Be`. `Assert-VerifiableMocks`
  is likewise removed (→ `Should -Invoke`) (Pester docs, breaking-changes-in-v5).
  The repo templates already model the v5 style: `tests/TEST_TEMPLATES.md` uses
  `BeforeAll` + `Should -Be` throughout — copy from there.
- The v4-style `Invoke-Pester` parameter set survives in v5 only as a deprecated
  legacy shim with warnings and gaps; use the simple `-Path`/`-PassThru` form the
  workflow itself uses, or `New-PesterConfiguration` for anything advanced.

## PSScriptAnalyzer — the honest gap

Two workflows look like "the linter"; neither PSSA run gates anything:

- `.github/workflows/quality.yml` (`powershell-lint`) installs PSScriptAnalyzer
  (unpinned) and runs `Invoke-ScriptAnalyzer -Path './src', './scripts' -Recurse
  -Severity Error, Warning` — but the step is `continue-on-error: true` and results
  only upload as the `powershell-analysis` artifact. **PSSA is advisory-only in CI.**
- The *enforced* PowerShell gate is `.github/workflows/ci-validation.yml`
  (`syntax-check`): the real parser,
  `[System.Management.Automation.Language.Parser]::ParseFile`, over every `.ps1`,
  checked against the legacy baseline `.github/ps1-parse-baseline.txt`. A parse error
  in any file NOT in that baseline fails the job; repairing a baselined file means
  deleting its line (the job prints "repaired" reminders). Adding new broken files is
  not allowed — the baseline's own header says so.
- `code-checks.yml` additionally tokenizes with the older `PSParser::Tokenize` plus
  regex-based security/registry/path checks — shallower than `Parser::ParseFile`;
  treat ci-validation as the source of parse truth.

Practical rule: run `Invoke-ScriptAnalyzer` locally before pushing (CI will not force
you to), but always confirm `Parser::ParseFile` reports zero errors — that one gates.

## PSResourceGet vs Install-Module

The workflows use PowerShellGet v2 (`Install-Module` — the Pester pin above,
quality.yml's PSSA install). `Microsoft.PowerShell.PSResourceGet` ships with
PowerShell 7.4+ as the preferred package manager, and `Install-PSResource` combines
PowerShellGet v2's `Install-Module` + `Install-Script` (Microsoft Learn:
about_Modules; Install-PSResource). For new scripts — the repo's bootstrap scripts
already declare `#Requires -Version 7` (`scripts/bootstrap/setup-ai-clis.ps1`):

- `Install-PSResource Pester -Version '5.4.0' -TrustRepository` is the modern
  equivalent of the pinned install; `-TrustRepository` replaces the
  `-Force`-to-skip-the-prompt dance.
- Caveats (Install-PSResource docs): it does NOT import the module into the current
  session, and it does not resolve dependencies from NuGet-v3 repositories.
- Do not churn the existing pinned workflow lines to PSResourceGet for style points —
  change them only with a reason, and keep the exact version pin either way.

## Az module discipline

Two repo scripts define the pattern; copy them rather than inventing:

- **Az PowerShell path** — `scripts/bootstrap/connect-azure.ps1` uses `Az.Accounts`
  only (`Connect-AzAccount -UseDeviceAuthentication`, `Get-AzContext`,
  `Set-AzContext`). Its precondition check is a capability probe whose error names
  the *narrow* module — `Install-Module Az.Accounts -Scope CurrentUser` — not the
  giant `Az` meta-module:

  ```powershell
  if (-not (Get-Command Connect-AzAccount -ErrorAction SilentlyContinue)) { ... }
  ```

  Its `-VerifyOnly` mode deliberately never calls `Set-AzContext`, because that
  mutates the persisted context (the script's own comment). Cloud Shell is detected
  via `$env:AZUREPS_HOST_ENVIRONMENT -or $env:ACC_CLOUD` and treated as
  pre-authenticated rather than re-logged-in.
- **az CLI path** — `scripts/bootstrap/azure-oidc-setup.ps1` wraps the `az` CLI behind
  one `Invoke-Az` helper that throws on non-zero `$LASTEXITCODE` and returns trimmed
  stdout. It never touches the Az module.

The discipline: one script commits to ONE tool (Az module or az CLI) and states it in
its header. Mixing them doubles the auth-state surface — `Get-AzContext` and
`az account show` can disagree — and doubles the failure modes.
