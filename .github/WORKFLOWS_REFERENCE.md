# GitHub Actions Workflows Reference

## 📋 Available Workflows

### 1. **CI - Code Validation & Testing** ✅

**File**: `.github/workflows/ci-validation.yml`

**Runs on**:

- Every push to `main` or `develop`
- Every pull request

**What it does**:

- ✅ PowerShell syntax validation
- ✅ Markdown validation
- ✅ Documentation completeness check
- ✅ Run unit tests
- ✅ Security vulnerability scan
- ✅ File structure validation

**Status**: Automatic (no action needed)

---

### 2. **Phase Build & Validation**

**File**: `.github/workflows/phase-build.yml`

**Runs on**: Manual trigger (workflow_dispatch)

**How to trigger**:

1. Go to: https://github.com/Yolkster64/helios-platform/actions
2. Click **"Phase Build & Validation"**
3. Click **"Run workflow"**
4. Select:
   - **Phase**: 0, 1, 2, or 3
   - **Environment**: test, staging, or production
5. Click **"Run workflow"**

**What it does**:

- ✅ Validates phase directory exists
- ✅ Runs phase build script
- ✅ Executes phase tests
- ✅ Reports final status

**Output**: Check under **Actions** → **Phase Build & Validation** → latest run

---

### 3. **Wiki Generator**

**File**: `.github/workflows/wiki-generator.yml`

**Runs on**:

- Every push to `main` with `docs/**` changes
- Manual trigger

**What it does**:

- ✅ Syncs curated `docs/` content to the GitHub wiki
- ✅ Flattens architecture and MCP docs into wiki pages
- ✅ Preserves hand-written wiki pages (like `Home.md`)
- ✅ Commits only when synced content actually changes

**Status**: Automatic (runs on documentation changes)

---

### 4. **HELIOS Deploy**

**File**: `.github/workflows/helios-deploy.yml`

**Runs on**: Manual trigger (workflow_dispatch)

**Requires**: Azure credentials in GitHub Secrets

**How to trigger**:

1. Go to: https://github.com/Yolkster64/helios-platform/actions
2. Click **"HELIOS Deploy"**
3. Click **"Run workflow"**
4. Select:
   - **Environment**: development, staging, or production
   - **Phase**: 0-foundation, 1-security, 2-optimization, or 3-capability
5. Click **"Run workflow"**

**What it does**:

- ✅ Runs guarded Azure what-if/deploy flow
- ✅ Emits deploy custody records for evidence
- ✅ Captures structured deployment diagnostics
- ✅ Supports safe `what_if` mode for validation first

**Output**: Check Actions → HELIOS Deploy → latest run

---

## 🔐 Required GitHub Secrets

For workflows to work fully, add these secrets to your repo:

**Location**: Settings → Secrets and variables → Actions

### Required Secrets:

1. **GITHUB_TOKEN** (automatic - always available)
   - Used by all workflows
   - No setup needed

2. **AZURE_CREDENTIALS** (optional - for Azure deployment)

   ```json
   {
     "clientId": "00000000-0000-0000-0000-000000000000",
     "clientSecret": "00000000-0000-0000-0000-000000000000",
     "subscriptionId": "00000000-0000-0000-0000-000000000000",
     "tenantId": "00000000-0000-0000-0000-000000000000"
   }
   ```

3. **CHATGPT_API_KEY** (optional - for AI integration)
   - Get from: https://platform.openai.com/api-keys

4. **GITHUB_COPILOT_TOKEN** (optional - for Copilot integration)
   - Created automatically for GitHub Apps

## 📊 View Workflow Runs

### Method 1: Via Web Interface

1. Go to: https://github.com/Yolkster64/helios-platform/actions
2. See all workflow runs
3. Click any run to see details
4. Click job to see logs

### Method 2: Via GitHub CLI

```bash
# List all workflow runs
gh run list --repo Yolkster64/helios-platform

# View specific run details
gh run view <run-id> --repo Yolkster64/helios-platform

# View logs
gh run view <run-id> --log --repo Yolkster64/helios-platform
```

## 🎯 Workflow Status Badges

Add to README.md:

```markdown
# HELIOS Platform

![CI Validation](https://github.com/Yolkster64/helios-platform/actions/workflows/ci-validation.yml/badge.svg)
![Wiki Generator](https://github.com/Yolkster64/helios-platform/actions/workflows/wiki-generator.yml/badge.svg)
![Phase Build](https://github.com/Yolkster64/helios-platform/actions/workflows/phase-build.yml/badge.svg)
![HELIOS Deploy](https://github.com/Yolkster64/helios-platform/actions/workflows/helios-deploy.yml/badge.svg)
```

These show real-time status of each workflow.

## ⚙️ Customizing Workflows

### To modify a workflow:

1. Open file in VS Code or GitHub Web
   - Path: `.github/workflows/{workflow-name}.yml`

2. Edit YAML syntax:

   ```yaml
   on:
     push:
       branches: [ main ]    # Add more branches here
       paths:                # Or add path filters
         - '**.md'
         - 'scripts/**'
   ```

3. Commit changes
4. Workflow runs automatically on next trigger

### Common Customizations:

**Run on different branches**:

```yaml
on:
  push:
    branches: [ main, develop, staging ]
```

**Run on schedule (cron)**:

```yaml
on:
  schedule:
    - cron: '0 0 * * 0'  # Weekly Sunday midnight
```

**Skip workflow for certain commits**:

```
git commit -m "Fix typo [skip ci]"
```

## 🔄 Workflow Status Overview

| Workflow | Trigger | Status | Last Run |
|----------|---------|--------|----------|
| CI Validation | Push/PR | Automatic | View in Actions tab |
| Wiki Generator | Doc changes | Automatic | View in Actions tab |
| Phase Build | Manual | On-demand | Trigger in Actions tab |
| HELIOS Deploy | Manual | On-demand | Trigger in Actions tab |

## 💡 Tips & Best Practices

### 1. Monitor Builds

```bash
# Watch workflow progress live
gh run watch <run-id> --repo Yolkster64/helios-platform
```

### 2. Debug Failed Workflows

1. Go to Actions tab
2. Click failed run
3. Click failed job
4. Read error messages
5. Fix issue locally
6. Push fix (triggers workflow again)

### 3. Use Concurrency

Prevent multiple runs of same workflow:

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

### 4. Cache Dependencies

Speed up builds by caching:

```yaml
- uses: actions/cache@v3
  with:
    path: ~/.cache/pip
    key: ${{ runner.os }}-pip-${{ hashFiles('**/requirements.txt') }}
```

## 📞 Troubleshooting

### Workflow not triggering

- Check branch name matches trigger
- Check file paths match filters
- Verify commits aren't marked `[skip ci]`

### Workflow fails immediately

- Check syntax with `yamllint`
- Verify secrets are set correctly
- Check job dependencies

### Long build times

- Add caching
- Run jobs in parallel
- Split into multiple workflows

### Tests failing in CI but passing locally

- Different OS (Linux vs Windows)
- Missing dependencies
- Environment variable differences

---

## 🚀 Next Steps

1. **View Current Runs**: https://github.com/Yolkster64/helios-platform/actions
2. **Add Status Badges**: Update README.md
3. **Setup Secrets** (if using Azure/ChatGPT): Settings → Secrets
4. **Test a Workflow**: Manually trigger "Phase Build"
5. **Monitor**: Check Actions tab regularly

**Everything is set up and ready to use!** ✅
