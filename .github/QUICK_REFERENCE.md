# Quick Reference: Workflow Triggers & Usage

## Automatic Triggers

| Workflow | Schedule | Event Trigger |
|----------|----------|---------------|
| multi-repo-sync | Daily @ 2 AM UTC | — |
| component-version-check | — | PR on `COMPONENT_MATRIX.md`, `src/` |
| build-all-modules | — | Push to main/develop, PR |
| build-variant-test | — | Push to main/develop, PR |
| code-registry-update | Monday @ 3 AM UTC | — |
| wiki-generator | — | Push to main (docs change) |
| status-dashboard | Every 4 hours | Push to main |

## Manual Triggers

All workflows support `workflow_dispatch`:

```bash
# Trigger via GitHub CLI
gh workflow run multi-repo-sync.yml --ref main
gh workflow run component-version-check.yml --ref main
gh workflow run build-all-modules.yml --ref main
```

### With Input Parameters

```bash
# Dry-run mode for multi-repo-sync
gh workflow run multi-repo-sync.yml -f dry_run=true

# Strict mode for version check
gh workflow run component-version-check.yml -f strict_mode=true

# Include diagrams for wiki
gh workflow run wiki-generator.yml -f include_diagrams=true

# Include metrics for dashboard
gh workflow run status-dashboard.yml -f include_metrics=true
```

## Output Artifacts

### multi-repo-sync.yml

- `sync-artifacts/` → Submodule and version data

### component-version-check.yml

- `compatibility-reports/` → Validation and dependency data

### build-all-modules.yml

- `*-build/` → Module builds
- `test-results-*/` → Test reports
- `build-metrics-*/` → Performance data

### build-variant-test.yml

- `variant-*-build/` → Variant builds
- `variant-reports/` → Test results

### code-registry-update.yml

- `compression-data/` → Registry and analysis

### wiki-generator.yml

- `wiki-html/` → Complete HTML wiki

### status-dashboard.yml

- `status-dashboard/` → Reports and dashboard

## Performance Characteristics

| Workflow | Est. Duration | Parallel Jobs |
|----------|---------------|---------------|
| multi-repo-sync | 5-10 min | Sequential |
| component-version-check | 3-5 min | Sequential |
| build-all-modules | 15-30 min | 14 parallel |
| build-variant-test | 20-40 min | 7 parallel |
| code-registry-update | 10-15 min | Sequential |
| wiki-generator | 5-10 min | Sequential |
| status-dashboard | 3-5 min | Sequential |

## Monitoring Workflows

### View Workflow Status

```bash
# List recent runs
gh workflow view multi-repo-sync.yml --json updatedAt,status

# View specific run details
gh run view <RUN_ID>

# Stream logs
gh run view <RUN_ID> --log
```

### Check for Failures

```bash
# Get failed runs
gh run list --status failure --limit 10

# View failure logs
gh run view <FAILED_RUN_ID> --log-failed
```

## Common Issues

**"Push rejected"**

- Use `git pull` before manual changes
- Workflows use `force-with-lease` for safety

**"Artifact not found"**

- Check retention period (default 30 days)
- Verify workflow completed successfully
- Check artifact name in workflow step

**"Build failed"**

- Review build logs in workflow run
- Check dependencies are installed
- Verify all required tools available

**"Incompatible versions detected"**

- Review `COMPATIBILITY_REPORT.md`
- Check `breaking_changes.json`
- May need manual intervention

## Repository Setup

### Required Branch Protection Rules

```
Branch: main
- Require status checks to pass before merging
- Require branches to be up to date
- Dismiss stale PR approvals
- Require at least 1 approval
```

### Recommended Secrets

None required (uses GITHUB_TOKEN)

### File Permissions

Workflows need write access to:

- Root README.md
- COMPONENT_MATRIX.md
- BUILD_VARIANTS.md
- .github/workflows/

## GitHub Actions Permissions

All workflows use minimal required permissions:

```yaml
permissions:
  contents: write          # For commits/PRs
  pull-requests: write     # For reviews/comments
  pages: write             # For GitHub Pages (wiki)
```

## Scheduling Coordination

- **2 AM UTC:** multi-repo-sync (daily)
- **3 AM UTC:** code-registry-update (Monday)
- **Every 4 hours:** status-dashboard

Staggered to avoid concurrent heavy operations.

## Artifact Access

### Via GitHub UI

1. Click "Actions" tab
2. Select workflow
3. Click run
4. Scroll to "Artifacts" section
5. Download desired artifact

### Via GitHub CLI

```bash
gh run download <RUN_ID> -n artifact-name
```

### Via Download Button

All artifacts automatically download with run completion.

## Cost Considerations

GitHub Actions provides:

- **Public repos:** Unlimited minutes
- **Private repos:** 2,000 minutes/month free

Estimated monthly usage for Helios:

- ~1,500 build minutes
- Cost: $0 (within free tier)

## Troubleshooting

### Enable Debug Logging

```bash
# Set repository secrets
gh secret set ACTIONS_STEP_DEBUG --body true
```

### Manual Retry

```bash
gh run rerun <RUN_ID>
```

### Force Workflow

```bash
# Push empty commit to trigger
git commit --allow-empty -m "trigger workflows"
git push
```

## Best Practices

✅ **DO:**

- Run in dry-run mode first for major changes
- Review artifacts before committing
- Monitor workflow status regularly
- Keep workflows updated with code changes

❌ **DON'T:**

- Manually edit generated files (they'll be overwritten)
- Disable workflows without reason
- Ignore workflow failures
- Commit secrets to repository

---

**Last Updated:** 2024 | For full documentation see WORKFLOWS.md
