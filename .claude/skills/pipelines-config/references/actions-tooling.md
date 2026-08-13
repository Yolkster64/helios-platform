# Actions tooling — the HELIOS-specific layer

*Versions and API claims mirror the cited repo files; update this file in the same PR that changes them.*

Generic GitHub Actions knowledge (current action majors, triggers, permissions, OIDC,
injection, caching correctness) lives in
`.claude/skills/automation-wiring/references/github-actions.md` — read that first. This
file carries only what is specific to THIS repo's workflows.

## Pinning lessons learned here

- **`aquasecurity/trivy-action` must be pinned to a release whose composite pins its
  internal `setup-trivy` step by SHA — e.g. `v0.36.0`.** `v0.28.0` is *permanently*
  broken: its composite referenced `aquasecurity/setup-trivy@v0.2.1`, which was deleted
  upstream, so every run fails at action resolution no matter what your workflow says.
  The general lesson: a tag pin protects you from the action's *own* repo, not from
  mutable references inside its composite — audit what a composite action pins before
  trusting the tag.
- The repo's live usage is currently worse than either: `ci-validation.yml` uses
  `aquasecurity/trivy-action@master` (floating). When touching that workflow, pin per the
  rule above and bump the adjacent `github/codeql-action/upload-sarif@v2` — the oldest
  major pin left in the repo — in the same PR.
- `code-checks.yml` still uses `actions/checkout@v3` while every other workflow is on
  `@v4`; it also `choco install`s PowerShell that `windows-latest` already has. Treat it
  as the drift example, not a pattern source.

## actionlint — honest gap

There is **no actionlint job in this repo** and no actionlint config file. Two workflows
shipped with invalid YAML that a linter would have caught before merge
(`publish-to-packagemanagers.yml`, `documentation-update.yml` — embedded-script
indentation defects; see the known-red table in
`docs/architecture/ROADMAP_MULTI_LLM.md`). Until a job exists:

- Run `actionlint` locally (or at minimum `python3 -c "import yaml,sys;
  yaml.safe_load(open(sys.argv[1]))" <file>`) on every workflow you touch — this is the
  verification step the repo's plans already require.
- Adopt an actionlint CI job when workflow churn justifies it; scope its `paths:` to
  `.github/workflows/**` and keep it non-required until it has proven quiet on main
  (a check that can never be green is worse than no check — SKILL.md rule).

## Concurrency patterns (the six workflows that use it)

| Workflow | Group | cancel-in-progress | Why |
|---|---|---|---|
| `helios-deploy.yml` | `helios-deploy` (global) | false | One deploy at a time; queue, never kill a half-applied deployment |
| `wiki-generator.yml` | `wiki-sync` (global) | false | Comment in file: "never interrupt a half-pushed wiki update" |
| `linear-sync.yml` | per `issue.number` | false | Serialize per issue; parallel issues fine |
| `copilot-dispatch.yml` | per event+issue/PR number | false | Same, dual-trigger aware (`\|\|` fallback between event payloads) |
| `absorption-benchmark.yml` | per ref + `inputs.pr_number` | false | Benchmarks must complete to report |
| `docker-validate.yml` | per `github.ref` | **true** | Pure validation — newest push wins, stale runs are waste |

Rule of thumb encoded above: **cancel only pure-validation jobs; queue anything with
side effects** (deploys, pushes, comment posting, benchmarks feeding dashboards).

## NuGet cache keying (dotnet-build.yml)

```yaml
key: nuget-${{ runner.os }}-${{ hashFiles('**/*.csproj', 'nuget.config') }}
restore-keys: nuget-${{ runner.os }}-
```

- Hashing `**/*.csproj` is correct **only because versions live in csproj files**. If
  Central Package Management lands (Copilot PR #95 introduces
  `Directory.Packages.props`), that file must be added to `hashFiles(...)` in the same PR
  or the cache key stops changing when versions do.
- `restore-keys` gives a stale-but-warm fallback; acceptable for restore (NuGet
  revalidates), never use the same trick for build outputs.
- Lockfile-based keying (`RestorePackagesWithLockFile` + `packages.lock.json`) is **not
  in the repo** — adopt only together with CPM, and key on the lockfiles instead.

## Repeated setup — composite-action candidate

Five workflows carry their own checkout → `actions/setup-dotnet@v4` pair, and they have
already drifted on the version spelling: `dotnet-version: 8.0.x` in `dotnet-build.yml`,
`absorption-benchmark.yml`, `create-release.yml`; quoted `'8.0'` plus a matrix in
`nuget.yml`; a multi-line list in `publish-nuget.yml`. Only `dotnet-build.yml` pairs
setup with the NuGet cache. A composite action
(`.github/actions/setup-helios/action.yml`) is the cheap dedup; a reusable workflow
(`workflow_call`) only pays off if whole jobs are shared, which they are not today.
**Not in the repo yet** — adopt when the net10 roadmap bump would otherwise touch five
files with three spellings; that bump is the natural moment to extract.

## Other repo-specific rules worth keeping in view

- Deployment workflows probe configuration and skip gracefully — the
  `steps.creds.outputs.configured` guard-step pattern in `helios-deploy.yml`; forks and
  secretless clones stay green.
- Build the solution (`HELIOS.sln`), never bare `dotnet build` at repo root — the root
  WPF csproj does not compile on Linux runners (SKILL.md rule; `dotnet-build.yml` comment).
- `dotnet-build.yml` builds the native library **before** `dotnet build` and asserts the
  `.so` reached test output — ordering matters because the csproj copy is
  `Condition="Exists(...)"`.
