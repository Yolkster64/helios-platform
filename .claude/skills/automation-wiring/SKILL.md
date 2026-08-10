---
name: automation-wiring
description: Builds end-to-end automation where several config formats have to agree with each other — GitHub Actions workflows, Bicep/ARM templates, Terraform, JSON/YAML config, .env and plain-text manifests, and curl/REST calls. Use this whenever the user asks for a pipeline, workflow, deployment, provisioning, CI/CD, IaC, or "wire X to Y" task, or hands you more than one of these file types at once — even if they only name one of them, because the wiring between them (outputs to inputs, secrets to consumers, names to references) is where these tasks actually break.
---

# Automation Wiring

Most automation failures are not syntax errors in one file. They are **contract breaks
between files**: a workflow references a secret nobody creates, a Bicep output the deploy
step never reads, a Terraform variable whose name drifted from the JSON config that feeds
it. Single files are easy; the seams are the work.

So the organizing idea here is: **identify the contracts first, then write the files that
satisfy them, then prove the contracts hold.** Everything below serves that.

## Workflow

### 1. Map the contracts before writing anything

Write down (in your head or as a scratch note) every value that crosses a file boundary:

| Contract kind | Producer | Consumer | Fails as |
|---|---|---|---|
| Resource identity | Bicep/TF resource name | app config, workflow env | 404 at runtime |
| Deployment output | `output x string` | `az deployment ... --query` → workflow env | empty string, silent misconfig |
| Secret | Key Vault / GitHub secret | workflow `secrets.X`, app env var | 403, or a skipped job |
| Identity/RBAC | role assignment in IaC | OIDC login in workflow | "not authorized" at deploy |
| Schema | JSON/YAML config | code that binds it | crash on first read |
| Trigger | workflow `on:` + path filter | the change that should fire it | silence — the worst failure |

When you deliver, state these contracts explicitly. A reader should be able to trace one
value end to end without opening every file.

### 2. Pick the tool per layer — don't blend them

- **Azure resources**: Bicep. ARM JSON only for reading legacy or when a tool demands it
  (`bicep decompile` to move off it; `bicep build` to produce ARM when required).
- **Multi-cloud, or where the org already runs it**: Terraform. Never define the same
  resource in both Terraform and Bicep — pick one owner per resource and let the other
  read outputs.
- **Orchestration/CI**: GitHub Actions YAML.
- **App/tool config**: JSON (schema-bound) or YAML (human-edited). Plain text (`.env`,
  manifests, `requirements.txt`) only where a tool mandates the format.
- **Ad-hoc API calls and smoke tests**: curl, kept in a script with the same auth pattern
  the real code uses.

### 3. Delegate the specialist layers

For anything beyond a single small file, hand each layer to the matching subagent so each
gets full attention and the formats are authored by a specialist rather than sketched:

| Layer | Agent |
|---|---|
| GitHub Actions, reusable workflows, runners | `workflow-author` |
| Bicep + ARM, parameters, RBAC, what-if | `bicep-arm-author` |
| Terraform modules, state, providers | `terraform-author` |
| JSON/YAML/.env schemas and their binding code | `config-schema-author` |
| REST/curl calls, auth flows, smoke tests | `rest-api-wirer` |

Launch independent layers **in parallel in one message**. Give every agent the contract
table from step 1 — that shared context is what keeps their outputs compatible. Serialize
only where one layer genuinely needs another's output shape.

### 4. Validate everything before claiming it works

Run `scripts/validate_all.py` (bundled) from the repo root. It parses every JSON/YAML file,
compiles Bicep, checks Terraform formatting/validity, and lints Actions workflows for the
failure modes that actually bite: nonexistent actions, deprecated versions, missing
`permissions`, and shell-injection through `${{ }}` interpolation.

```bash
python .claude/skills/automation-wiring/scripts/validate_all.py            # whole repo
python .claude/skills/automation-wiring/scripts/validate_all.py infra .github/workflows
```

Anything the script can't check — does the workflow actually trigger on the change you
expect? does the deploy read the output the template produces? — verify by tracing it
yourself and say in your summary that you did.

## Non-negotiables

These come from real breakage, so they're worth holding even under time pressure:

- **Secrets never land in a file.** Config holds the *name* of an env var or secret;
  values come from the environment, GitHub secrets, or a vault at runtime. IaC takes them
  as secure parameters and never emits them as outputs. If you catch yourself writing a
  placeholder like `"api_key": "sk-..."`, switch to `"apiKeyEnv": "OPENAI_API_KEY"`.
- **Prefer OIDC/federated identity over stored cloud credentials** (`azure/login@v2` with
  `id-token: write`). A long-lived cloud secret in a repo is a standing incident.
- **A pipeline that can't be green is worse than no pipeline.** If a step depends on
  credentials a fork or contributor won't have, guard it so it skips cleanly rather than
  failing. Deployment gates on secrets; validation must run offline.
- **Idempotency.** Re-running provisioning must converge, not duplicate. Watch for
  timestamps in resource names (`utcNow()` in a Bicep name creates new resources every
  deploy), random suffixes without stable seeds, and non-`-f` copies.
- **Destructive operations are opt-in.** `terraform destroy`, `az group delete`, force
  pushes, and DB migrations get an explicit input or environment approval — never a
  default branch trigger.
- **Pin versions.** Actions at a major tag they still publish, Terraform providers with
  `~>`, Bicep `apiVersion` explicit, packages exact. Floating versions turn someone else's
  release into your outage.

## Deliverable format

Give the user, in this order:

1. **The wiring map** — a short table or list of the contracts from step 1, showing what
   flows where. This is the part they can't easily reconstruct themselves.
2. **The files**, each with a one-line purpose.
3. **Validation results** — what you ran, what passed, what you couldn't check mechanically.
4. **How to run it** — the exact commands, including a dry-run/what-if first.
5. **What's deliberately not wired yet**, if anything, so nobody assumes coverage that
   isn't there.

## Reference material

Read the file for the layer you're working in — they carry the version-specific details
and the traps that generic knowledge gets wrong:

- `references/github-actions.md` — triggers, permissions, OIDC, matrices, reusable
  workflows, self-hosted runners, injection safety, current action versions
- `references/bicep-arm.md` — modern Azure patterns, parameter files, secure params,
  RBAC, what-if, ARM interop, AI Foundry specifics
- `references/terraform.md` — module layout, state/backends, providers, `for_each` vs
  `count`, importing existing resources, Azure specifics
- `references/config-schemas.md` — JSON/YAML/.env design, schema binding, drift tests,
  the env-name indirection pattern for secrets
- `references/rest-curl.md` — auth flows (OIDC, PAT, managed identity), retry/backoff,
  GitHub and Azure REST specifics, turning curl into a committed smoke test
