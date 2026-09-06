# GitHub Actions Best Practices & Performance - HELIOS Platform

## Overview

This document outlines best practices for developing, maintaining, and optimizing GitHub Actions workflows for the HELIOS Platform.

**Version**: 1.0  
**Last Updated**: 2024  
**Audience**: DevOps Engineers, Developers, Release Managers

---

## Table of Contents

1. [Security Best Practices](#security-best-practices)
2. [Performance Optimization](#performance-optimization)
3. [Reliability Patterns](#reliability-patterns)
4. [Cost Management](#cost-management)
5. [Monitoring & Logging](#monitoring--logging)
6. [Version Management](#version-management)
7. [Workflow Development](#workflow-development)
8. [Testing Workflows](#testing-workflows)

---

## Security Best Practices

### 1. Secrets Management

✅ **Always use GitHub Secrets**:

```yaml
# ✅ CORRECT
- name: Publish Package
  run: dotnet nuget push "*.nupkg" --api-key "${{ secrets.NUGET_API_KEY }}"

# ❌ WRONG
- name: Publish Package
  run: dotnet nuget push "*.nupkg" --api-key "sk-1234567890"
```

### 2. Secret Masking

GitHub automatically masks:

- Values of secrets in logs
- Environment variables set to secret values
- Passwords in error messages

**But ensure**:

- Secrets are logged only when necessary
- Use `--password-stdin` when possible
- Avoid printing JSON responses containing secrets

### 3. Permissions

```yaml
# Least privilege principle
permissions:
  contents: read              # Only what's needed
  checks: write
  pull-requests: write
  packages: write
  # Not: permissions: write-all (too permissive)
```

### 4. OIDC Token Authentication

```yaml
# Instead of long-lived credentials
- name: Azure Login
  uses: azure/login@v1
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

### 5. Environment Protection

```yaml
# GitHub Settings → Environments → Production
environments:
  production:
    required_reviewers:
      - release-manager
    deployment_branches:
      - main
```

### 6. Third-Party Actions

✅ **Pin action versions**:

```yaml
# ✅ GOOD: Specific version
- uses: actions/checkout@v4

# ⚠️ RISKY: Latest version
- uses: actions/checkout@latest

# ❌ DANGEROUS: Commit SHA not stable
- uses: actions/checkout@abc1234
```

### 7. Audit Workflow Runs

```yaml
# Log all workflow activity
- name: Audit Log
  run: |
    echo "Triggered by: ${{ github.actor }}"
    echo "Event: ${{ github.event_name }}"
    echo "Ref: ${{ github.ref }}"
    echo "Commit: ${{ github.sha }}"
```

---

## Performance Optimization

### 1. Caching Dependencies

```yaml
# NPM caching
- uses: actions/cache@v3
  with:
    path: ~/.npm
    key: ${{ runner.os }}-npm-${{ hashFiles('**/package-lock.json') }}
    restore-keys: |
      ${{ runner.os }}-npm-

# .NET caching
- uses: actions/cache@v3
  with:
    path: ~/.nuget/packages
    key: ${{ runner.os }}-nuget-${{ hashFiles('**/packages.lock.json') }}
    restore-keys: |
      ${{ runner.os }}-nuget-
```

### 2. Parallelization with Matrix

```yaml
# ✅ GOOD: Parallel execution
strategy:
  matrix:
    os: [ubuntu-latest, windows-latest]
    version: ['8.0', '7.0']
  max-parallel: 4  # Limit if needed
  fail-fast: false # Complete all combinations

# ❌ WRONG: Sequential builds
jobs:
  build-windows: ...
  build-linux:
    needs: build-windows
```

### 3. Shallow Clones

```yaml
# ❌ SLOW: Full clone history
- uses: actions/checkout@v4
  with:
    fetch-depth: 0  # Entire history

# ✅ FAST: Shallow clone
- uses: actions/checkout@v4  # Default depth: 1

# ⚠️  USE: Full history when needed
- uses: actions/checkout@v4
  with:
    fetch-depth: 0  # For version detection
```

### 4. Build Artifacts Optimization

```yaml
# ❌ LARGE: Include all files
- uses: actions/upload-artifact@v3
  with:
    path: ./

# ✅ OPTIMIZED: Specific files only
- uses: actions/upload-artifact@v3
  with:
    path: |
      dist/
      build/
      !**/*.tmp
      !**/node_modules/

# ✅ FAST: Quick exclusions
- uses: actions/upload-artifact@v3
  with:
    path: dist/
    if-no-files-found: ignore
```

### 5. Job Timeouts

```yaml
# Set appropriate timeouts
jobs:
  build:
    runs-on: ubuntu-latest
    timeout-minutes: 30  # Default: 360

    steps:
      - name: Long-running task
        timeout-minutes: 5  # Override for step
        run: ./slow-task.sh
```

### 6. Step Skipping

```yaml
# Skip expensive steps when not needed
- name: Run Tests
  if: github.event_name == 'pull_request'
  run: npm test

- name: Build Documentation
  if: contains(github.ref, 'main') || contains(github.ref, 'develop')
  run: npm run build:docs
```

### 7. Concurrency Control

```yaml
# Cancel in-progress workflows
concurrency:
  group: ${{ github.workflow }}-${{ github.head_ref || github.run_id }}
  cancel-in-progress: true

# Prevent duplicate runs
jobs:
  build:
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
```

---

## Reliability Patterns

### 1. Retries

```yaml
# Built-in retries
- name: Download Dependencies
  uses: actions/download-artifact@v3
  with:
    path: ./

# Custom retry logic
- name: Publish Package
  run: |
    for i in {1..3}; do
      dotnet nuget push "*.nupkg" && break || sleep 10
    done
```

### 2. Failure Handling

```yaml
# Continue on error
- name: Optional Step
  continue-on-error: true
  run: npm run optional-check

# Conditional failure
- name: Check Required
  run: |
    result=$(npm run critical-check || true)
    if [ -z "$result" ]; then
      echo "Critical check failed"
      exit 1
    fi
```

### 3. Health Checks

```yaml
# Verify environment
- name: Verify Environment
  run: |
    echo "Node: $(node --version)"
    echo "npm: $(npm --version)"
    echo "Disk: $(df -h | head -2)"
    echo "Memory: $(free -h | head -2)"
```

### 4. Idempotent Operations

```yaml
# ✅ Safe to re-run
- name: Publish Package
  run: dotnet nuget push "*.nupkg" --skip-duplicate

# ❌ Unsafe to re-run (creates duplicate)
- name: Create Release
  run: gh release create v1.0.0
```

### 5. Error Context

```yaml
# Capture detailed errors
- name: Build with Debug
  run: npm run build -- --debug 2>&1 | tee build-debug.log
  if: failure()

- name: Upload Debug Logs
  if: failure()
  uses: actions/upload-artifact@v3
  with:
    name: debug-logs
    path: '**/*.log'
```

---

## Cost Management

### 1. Runner Selection

```yaml
# Cost comparison (per 1000 minutes)
# ubuntu-latest: $0 (included)
# windows-latest: $0 (included)
# macos-latest: $0 (included)

# Larger runners available but cost extra
# Use only when necessary

# ✅ ECONOMICAL
runs-on: ubuntu-latest

# ❌ EXPENSIVE (only if needed)
runs-on: macos-latest-xl
```

### 2. Artifact Retention

```yaml
# ✅ ECONOMICAL: 7 days
- uses: actions/upload-artifact@v3
  with:
    path: dist/
    retention-days: 7  # Default

# ❌ EXPENSIVE: 90 days
- uses: actions/upload-artifact@v3
  with:
    path: dist/
    retention-days: 90
```

### 3. Scheduled Workflow Throttling

```yaml
# ✅ EFFICIENT: Avoid excessive runs
on:
  schedule:
    - cron: '0 2 * * *'  # Once per day

# ❌ EXPENSIVE: Too frequent
on:
  schedule:
    - cron: '*/15 * * * *'  # Every 15 minutes
```

### 4. Matrix Limiting

```yaml
# ✅ CONTROLLED: Limit combinations
strategy:
  matrix:
    os: [ubuntu-latest]  # Only Linux
    version: ['8.0']     # Only latest .NET

# ❌ EXCESSIVE: Too many combinations
strategy:
  matrix:
    os: [ubuntu-latest, windows-latest, macos-latest]
    version: ['6.0', '7.0', '8.0']
    arch: [x86, x64]
```

### 5. Cost Monitoring

```bash
# Check workflow execution minutes
gh api repos/{owner}/{repo}/actions/runs \
  --paginate \
  --jq '.run_data[].run_number, .run_data[].conclusion' \
  | grep -c success
```

---

## Monitoring & Logging

### 1. Debug Logging

```yaml
# Enable debug logging
- name: Debug Workflow
  if: runner.debug == 'true'
  run: |
    echo "Debug mode enabled"
    set -x  # Enable verbose output
    npm run build
    set +x
```

**Enable via**:

```bash
gh secret set ACTIONS_STEP_DEBUG --body true
```

### 2. Workflow Notifications

```yaml
# Slack notification on failure
- name: Slack Notification
  if: failure()
  uses: slackapi/slack-github-action@v1
  with:
    webhook-url: ${{ secrets.SLACK_WEBHOOK }}
    payload: |
      {
        "text": "Workflow failed: ${{ github.run_id }}",
        "blocks": [{
          "type": "section",
          "text": {
            "type": "mrkdwn",
            "text": "❌ Build failed on ${{ github.ref }}"
          }
        }]
      }
```

### 3. Performance Metrics

```yaml
# Track execution time
- name: Report Duration
  run: |
    echo "Workflow started at: ${{ github.run_id }}"
    echo "Job started: ${{ job.started_at }}"
    echo "Job ended: $(date)"
```

### 4. Structured Logging

```yaml
# Use GitHub annotations
- name: Create Annotation
  if: always()
  run: |
    if [ "${{ job.status }}" == "failure" ]; then
      echo "::error::Build failed with errors"
      echo "::notice::See logs for details"
    fi
```

---

## Version Management

### 1. Action Versions

```yaml
# ✅ Pin to major version
- uses: actions/checkout@v4        # Auto-updates to v4.x
- uses: actions/setup-node@v4      # Auto-updates to v4.x

# ⚠️ Dangerous: Always latest
- uses: some-action@latest         # May break

# Safely update
# 1. Test upgrade in branch
# 2. Monitor for issues
# 3. Merge to main
```

### 2. Dependency Versions

```yaml
# Node.js LTS versions
- uses: actions/setup-node@v4
  with:
    node-version: '18'  # LTS

# .NET versions (check EOL)
- uses: actions/setup-dotnet@v4
  with:
    dotnet-version: '8.0'  # LTS until Nov 2026
```

### 3. Tool Updates

```bash
# Check for action updates
# Tools → Update action
# Or manually review and test

# Commit with clear message
git commit -m "Update actions/checkout to v4.1.0"
```

---

## Workflow Development

### 1. Template Structure

```yaml
name: Template Workflow

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch:
    inputs:
      debug:
        description: 'Enable debug'
        required: false
        default: 'false'

permissions:
  contents: read
  checks: write

jobs:
  check:
    name: Check
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup
        uses: actions/setup-node@v4
        with:
          node-version: '18'

      - name: Execute
        run: npm run check

      - name: Report
        if: always()
        uses: actions/upload-artifact@v3
        with:
          name: reports
          path: reports/
```

### 2. Workflow Validation

```yaml
# Validate workflow syntax
- name: Validate Workflow
  run: |
    # Using act (local testing)
    act push --container-architecture linux/amd64 --dry-run
```

### 3. Documentation Comments

```yaml
# Add helpful comments
jobs:
  build:
    runs-on: ubuntu-latest
    # Purpose: Build and test the application
    # Duration: ~10 minutes
    # Dependencies: None
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        # Get latest code including history
```

---

## Testing Workflows

### 1. Local Testing with Act

```bash
# Install act
# https://github.com/nektos/act

# Test workflow locally
act push
act pull_request
act workflow_dispatch -i

# Test specific event
act -l  # List all workflows
```

### 2. Test Branch Workflow

```bash
# Create test branch
git checkout -b workflow-test

# Modify workflow
vim .github/workflows/test.yml

# Push to test
git push origin workflow-test

# Monitor execution
gh run list -b workflow-test --watch
```

### 3. Dry-Run Mode

```yaml
# Disable expensive operations during testing
- name: Publish (Test)
  if: ${{ github.event_name == 'workflow_dispatch' && github.ref != 'refs/heads/main' }}
  run: echo "Would publish: (disabled for test branch)"
```

---

## Common Pitfalls

❌ **Avoid**:

1. **Hardcoding Secrets**

   ```yaml
   # NEVER DO THIS
   env:
     API_KEY: "sk-1234567890"
   ```

2. **Always Using Latest**

   ```yaml
   # RISKY
   - uses: actions/checkout@latest
   ```

3. **Ignoring Failures**

   ```yaml
   # Hides errors
   - run: npm test || true
   ```

4. **Excessive Parallelization**

   ```yaml
   # May fail or timeout
   max-parallel: 100
   ```

5. **Large Artifacts**

   ```yaml
   # Slow uploads
   path: ./  # Everything
   ```

---

## References

- [GitHub Actions Security Best Practices](https://docs.github.com/en/actions/security-guides)
- [Workflow Performance](https://docs.github.com/en/actions/learn-github-actions/workflow-runs)
- [Caching Strategy](https://docs.github.com/en/actions/using-workflows/caching-dependencies-to-speed-up-workflows)
- [Cost Management](https://docs.github.com/en/billing/managing-billing-for-github-actions)

---

**Document Version**: 1.0  
**Last Updated**: 2024  
**Status**: Active ✅
