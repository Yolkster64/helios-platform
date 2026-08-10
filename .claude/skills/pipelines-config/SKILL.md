---
name: pipelines-config
description: GitHub Actions YAML, JSON, and XML configuration hygiene for HELIOS — workflow health rules, action version policy, and config-file conventions. Use when editing .github/workflows/, config/*.json, or csproj/XML files.
---

# Pipelines & Config — HELIOS

## GitHub Actions rules

- **Actions must exist and be current**: `actions/checkout@v4`, `setup-dotnet@v4`,
  `cache@v4`, `upload/download-artifact@v4` (v3 is disabled by GitHub and fails).
  There is **no** `actions/setup-powershell` — pwsh is preinstalled; use `shell: pwsh`.
- Every workflow needs an explicit `permissions:` block (least privilege; `contents: read`
  unless it writes) and `paths:` filters so unrelated PRs don't trigger it.
- Build the **solution** (`HELIOS.sln`), never bare `dotnet restore` at repo root (the
  root WPF csproj fails on Linux runners).
- A check that can never be green is worse than no check: gate flaky/known-broken steps
  with `continue-on-error: true` plus a comment naming the roadmap item that removes it.
- Deployment workflows must skip gracefully when secrets are absent (guard step pattern
  in `helios-deploy.yml`) so forks stay green.
- Workflows live only in `.github/workflows/` — anywhere else they silently never run
  (this repo had two such strays).

## JSON config conventions

- `config/aihub.json` is the exemplar: no secrets (env-var name indirection), `$comment`
  for humans, bound 1:1 to a C# `*Options` class, covered by a CI test that loads the
  real file (`ConfigBindingTests`) so drift fails the build.
- New config = new options class + binding test in the same PR.

## XML / csproj

- SDK-style projects only; `TargetFramework` net8.0 (see csharp-orchestrator skill for
  version policy); `Nullable` + `ImplicitUsings` enabled; pin package versions exactly
  (no floating `*`).
- Remember the root-csproj glob rule before adding any C# directory.

## Which LLM

| Work | Route |
|---|---|
| Reviewing workflow security (injection via `${{ }}`, pull_request_target) | `security_analysis` → Claude |
| Generating a workflow from a description | `code_generation` → Codex/GPT |
| Debugging a red check from logs | `debugging` → Claude CLI/Codex |
