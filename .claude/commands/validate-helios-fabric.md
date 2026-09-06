Validate the HELIOS Fabric on the current branch without performing external writes.

1. Read `CLAUDE.md`, `AGENTS.md`, `config/claude/helios-claude-policy.v1.json`, and `docs/fabric/HELIOS_FABRIC_SETUP.md`.
2. Run:

```bash
python scripts/validation/validate_yolkster_cutover.py
python scripts/validation/validate_helios_fabric.py
python scripts/validation/validate_model_providers.py
python scripts/validation/validate_fabric_activation.py
```

3. Validate JSON and YAML syntax for the files changed by the branch.
4. Inspect the WinUI 3 boundary: active GUI code must use `Microsoft.UI.Xaml`/`Microsoft.UI.Composition`; WPF/UWP references may exist only in explicitly declared legacy or porting inputs.
5. Inspect Azure DevOps and GitHub workflows for deployment, secret, RBAC, or consent authority. `productionEnabled` and default apply behavior must remain false.
6. Review provider and connector registries for secret values, undeclared tools, missing idempotency, missing approvals, fallback destinations, and broad permissions.
7. Report commands, results, exact files, risks, and required human/admin gates.

Do not merge, rename a repository, deploy, change permissions, write/read back secrets, post collaboration messages, or mutate a workstation.
