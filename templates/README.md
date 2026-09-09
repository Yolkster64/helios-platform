# Templates

Copy-and-edit starters for the files people author most often and get wrong most
often: a GitHub Actions workflow and the two GitHub manifests the control fabric
reconciles. Nothing in this directory is executed or applied by anything — GitHub
only runs workflows under `.github/workflows/`, and the manifests are read from
`config/github/`. What *is* wired: the two JSON starters are validated in CI against
the same schemas as the live manifests, so they can never rot.

| Template | Copy to | Schema | Applied by |
| --- | --- | --- | --- |
| `workflow.yml` | `.github/workflows/<name>.yml` | SchemaStore `github-workflow` (VS Code, YAML extension) | GitHub Actions |
| `manifest-labels.json` | `config/github/labels.json` | `config/schemas/github-labels.schema.json` | `scripts/github/apply-labels.ps1` |
| `manifest-milestones.json` | `config/github/milestones.json` | `config/schemas/github-milestones.schema.json` | `scripts/github/apply-milestones.ps1` |

## Copy

```bash
cp templates/workflow.yml .github/workflows/my-check.yml
cp templates/manifest-labels.json config/github/labels.json          # or merge entries into the existing file
cp templates/manifest-milestones.json config/github/milestones.json
```

Edit the copies, not the templates. The workflow skeleton keeps every guard the repo
relies on — `permissions: {}` at the top with per-job opt-ins, the `env:` idiom for
`${{ }}` values, pinned action majors, `concurrency`, `paths:` filters, a
`workflow_dispatch` inputs example — each explained in a comment; delete the
comments, keep the guards. The manifest starters carry example entries that must be
replaced before `-Apply`: both apply scripts are dry-run by default and print every
`gh api` command they would run.

## Validate

Three places, one contract (`config/schemas/manifests.json` maps every manifest to
its schema):

- **Editor.** `.vscode/settings.json` binds `config/github/labels.json`,
  `config/github/milestones.json`, the other `config/**` manifests, and these two
  starters to their schemas (`json.schemas`), and `.github/workflows/*.yml` plus
  `templates/workflow.yml` to the SchemaStore workflow schema (`yaml.schemas`; needs
  the recommended `redhat.vscode-yaml` extension). Errors and completions appear as
  you type. The labels/milestones files deliberately carry no `$schema` key: the
  apply scripts also accept a bare array, which cannot hold one, so the binding lives
  in the workspace settings instead.
- **Command line.**

  ```bash
  python3 scripts/validation/validate_config_schemas.py                                  # every mapped manifest
  python3 scripts/validation/validate_config_schemas.py config/github/labels.json        # one mapped manifest
  python3 scripts/validation/validate_config_schemas.py --schema config/schemas/github-labels.schema.json my-draft.json
  python3 .claude/skills/automation-wiring/scripts/validate_all.py                        # JSON/YAML/Bicep/Actions + the schema check
  ```

  Stdlib-only: `python-jsonschema` is used when installed, otherwise the built-in
  validator (the engine CI runs) covers the same keywords. Exit 0 valid, 1 invalid
  (every error listed with its JSON path), 2 unreadable or unmapped.
- **MCP.** Any client on the HELIOS server (`docs/mcp/CLIENT_SETUP.md`) can call
  `helios_config_validate` with a repo-relative path — `config/github/labels.json`,
  or a draft plus `schemaPath` — and gets `{ path, schema, valid, errors }` back.
  Read-only: it applies nothing and never rewrites the file.

## Apply

```bash
pwsh scripts/github/apply-labels.ps1              # dry run: create / update / in-sync per label
pwsh scripts/github/apply-labels.ps1 -Apply       # needs issues:write on the repository
pwsh scripts/github/apply-milestones.ps1
pwsh scripts/github/apply-milestones.ps1 -Apply
```

On `main`, `.github/workflows/governance-apply.yml` runs the same scripts on every
push and daily, so the merged manifest is the applied state. Details per script:
`scripts/github/README.md`; the control-fabric design:
`docs/architecture/GITHUB_ECOSYSTEM_DESIGN.md`.
