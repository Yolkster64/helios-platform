# Workflow Troubleshooting Guide - HELIOS Platform

## Overview

This guide provides solutions for common workflow issues, debugging procedures, and recovery steps.

**Version**: 1.0  
**Last Updated**: 2024  
**Scope**: All HELIOS Platform workflows

---

## Table of Contents

1. [Common Issues & Solutions](#common-issues--solutions)
2. [Debug Procedures](#debug-procedures)
3. [Recovery Steps](#recovery-steps)
4. [FAQ](#faq)
5. [Getting Help](#getting-help)

---

## Common Issues & Solutions

### Issue: Workflow Timeout

**Symptoms**:

- Job runs longer than expected
- Eventually times out (360 minutes default)
- Shows: "The operation was canceled"

**Root Causes**:

- Dependency download taking too long
- Tests running slowly
- Resource contention
- Network issues

**Solutions**:

```yaml
# 1. Increase timeout
jobs:
  build:
    timeout-minutes: 60  # Default: 360

# 2. Skip cache (clear cache first)
- name: Setup with fresh cache
  uses: actions/cache@v3
  with:
    path: ~/.npm
    key: ${{ runner.os }}-npm-${{ github.run_id }}

# 3. Increase parallelization
strategy:
  matrix:
    os: [ubuntu-latest]  # Remove slow runners

# 4. Add health check
- name: Check Performance
  run: |
    free -h
    df -h
    ps aux --sort=-%mem | head -10
```

**Recovery**:

```bash
# Rerun failed job
gh run rerun <RUN_ID> --failed

# Clear cache and retry
# GitHub UI → Actions → Caches → Delete
```

---

### Issue: Out of Disk Space

**Symptoms**:

```
No space left on device
Failed to write to file
Disk full
```

**Root Causes**:

- Large artifacts not cleaned up
- Build outputs not removed
- Test data accumulation

**Solutions**:

```yaml
# 1. Clean workspace
- name: Clean Workspace
  run: |
    rm -rf node_modules/
    rm -rf dist/
    rm -rf build/
    rm -rf .npm/

# 2. Reduce artifact size
- name: Upload Artifact
  uses: actions/upload-artifact@v3
  with:
    path: dist/
    if-no-files-found: ignore
    # Reduce retention
    retention-days: 3

# 3. Use compression
- name: Compress Artifacts
  run: tar -czf artifact.tar.gz dist/
  
- name: Upload Compressed
  uses: actions/upload-artifact@v3
  with:
    path: artifact.tar.gz
```

---

### Issue: Cache Not Being Restored

**Symptoms**:

```
Restoring cache failed
Cache miss - reinstalling dependencies
No matching cache found
```

**Root Causes**:

- `package-lock.json` not committed
- Cache key mismatch
- Cache expired (5 day default)
- Different runner type

**Solutions**:

```yaml
# 1. Verify lock file committed
git status | grep package-lock.json
git add package-lock.json
git commit -m "Add lock file"

# 2. Clear cache
# GitHub UI → Actions → Caches → Delete all

# 3. Fix cache key
- uses: actions/cache@v3
  with:
    path: ~/.npm
    # Ensure this hash changes when dependencies change
    key: ${{ runner.os }}-npm-${{ hashFiles('**/package-lock.json') }}
    restore-keys: |
      ${{ runner.os }}-npm-

# 4. Force fresh cache
key: ${{ runner.os }}-npm-${{ github.run_id }}  # Always unique
```

---

### Issue: Permission Denied Errors

**Symptoms**:

```
Permission denied: ./script.sh
Cannot access file
chmod: operation not permitted
```

**Root Causes**:

- File lacks execute permission
- Running as wrong user
- Windows-Linux path issues

**Solutions**:

```yaml
# 1. Add execute permission
- name: Make Script Executable
  run: chmod +x ./script.sh

# 2. Or run with explicit shell
- name: Run PowerShell Script
  run: pwsh -File ./script.ps1
  shell: bash

# 3. Use /usr/bin/env
- name: Run Python Script
  run: /usr/bin/env python script.py

# 4. Check permissions
- name: Debug Permissions
  run: |
    ls -la ./script.sh
    whoami
    pwd
```

---

### Issue: Network Connectivity

**Symptoms**:

```
Error: getaddrinfo ENOTFOUND npmjs.com
Connection timeout
Failed to download package
```

**Root Causes**:

- Network issues
- Firewall blocking
- Package registry down
- Rate limiting

**Solutions**:

```yaml
# 1. Verify connectivity
- name: Check Network
  run: |
    ping -c 1 8.8.8.8
    curl -I https://registry.npmjs.org
    nslookup npmjs.com

# 2. Use mirror/cache
- name: Setup npm Cache
  run: |
    npm config set registry https://registry.npmjs.org/
    npm ci --prefer-offline

# 3. Add retry logic
- name: Download with Retry
  run: |
    npm ci --prefer-offline || sleep 10 && npm ci

# 4. Use different registry
- name: Configure Alternate Registry
  run: |
    npm config set registry https://mirror.example.com/
```

---

### Issue: Test Failures

**Symptoms**:

```
FAIL tests/app.test.ts
Expected: true, Got: false
AssertionError: expected value to be 5
```

**Root Causes**:

- Code changes broken tests
- Environment-specific issues
- Missing test data
- Timing issues

**Solutions**:

```yaml
# 1. Run tests locally
npm test -- --verbose

# 2. Enable debug output
npm test -- --debug

# 3. Run specific test
npm test -- --testNamePattern="specific test"

# 4. Check test output artifact
# GitHub UI → Artifacts → test-results.trx

# 5. Increase test timeout
# jest.config.js
module.exports = {
  testTimeout: 10000,  // Default: 5000
};

# 6. Disable parallelization (for debugging)
npm test -- --runInBand
```

---

### Issue: NuGet Publish Fails

**Symptoms**:

```
401 Unauthorized
409 Conflict (version already exists)
400 Bad Request
```

**Root Causes**:

- Invalid API key
- Version already published
- Invalid package format

**Solutions**:

```yaml
# 1. Verify API key
- name: Test NuGet Connection
  run: |
    dotnet nuget add source \
      --username __token__ \
      --password "${{ secrets.NUGET_API_KEY }}" \
      --store-password-in-clear-text \
      --name nuget \
      https://api.nuget.org/v3/index.json

# 2. Use --skip-duplicate
- name: Publish Package
  run: |
    dotnet nuget push "*.nupkg" \
      --api-key "${{ secrets.NUGET_API_KEY }}" \
      --source https://api.nuget.org/v3/index.json \
      --skip-duplicate

# 3. Verify package format
- name: Check Package
  run: |
    unzip -t *.nupkg
    # Verify .nuspec is valid XML

# 4. Update version
- name: Get Version
  run: |
    [xml]$csproj = Get-Content "*.csproj"
    $version = $csproj.Project.PropertyGroup.Version
    echo "Current version: $version"
    # Increment for next release
```

---

### Issue: Azure Deployment Fails

**Symptoms**:

```
401 Unauthorized (Azure)
ResourceNotFound
DeploymentFailed
```

**Root Causes**:

- Invalid Azure credentials
- Insufficient permissions
- Resource already exists
- Quota exceeded

**Solutions**:

```yaml
# 1. Verify credentials
- name: Test Azure Connection
  run: |
    az login --service-principal \
      -u ${{ secrets.AZURE_CLIENT_ID }} \
      -p ${{ secrets.AZURE_CLIENT_SECRET }} \
      --tenant ${{ secrets.AZURE_TENANT_ID }}
    az account list

# 2. Check permissions
- name: Verify Permissions
  run: |
    az role assignment list --assignee $CLIENT_ID

# 3. Check resource exists
- name: Check Resources
  run: |
    az resource list --resource-group helios-dev

# 4. Check quotas
- name: Check Quotas
  run: |
    az vm list-usage --location eastus
```

---

## Debug Procedures

### Enable Debug Logging

```bash
# Set environment variable
gh secret set ACTIONS_STEP_DEBUG --body true

# Workflow will now output debug info
# Check workflow logs for detailed output
```

### Capture Workflow Context

```yaml
- name: Debug Context
  run: |
    echo "=== Context Info ==="
    echo "Event: ${{ github.event_name }}"
    echo "Ref: ${{ github.ref }}"
    echo "Actor: ${{ github.actor }}"
    echo "Commit: ${{ github.sha }}"
    echo "Run ID: ${{ github.run_id }}"
    echo "Run Number: ${{ github.run_number }}"
    
    echo "=== Environment ==="
    echo "OS: $(uname -a)"
    echo "Shell: $SHELL"
    echo "PWD: $PWD"
    
    echo "=== Disk Space ==="
    df -h
    
    echo "=== Memory ==="
    free -h
```

### Run Tests Locally

```bash
# Using act
act push --container-architecture linux/amd64
act pull_request

# With debug
act push --verbose
```

### Inspect Workflow File

```bash
# Validate syntax
gh workflow list
gh workflow view build-all-modules.yml

# Check for errors
yamllint .github/workflows/build-all-modules.yml
```

---

## Recovery Steps

### For Failed Workflow

```bash
# 1. View run details
gh run view <RUN_ID>

# 2. View job logs
gh run view <RUN_ID> -j <JOB_ID>

# 3. Rerun failed job
gh run rerun <RUN_ID> --failed

# 4. Rerun entire workflow
gh run rerun <RUN_ID>

# 5. Download artifacts
gh run download <RUN_ID>
```

### For Failed Build

```bash
# 1. Identify which module failed
# View "Upload Build Artifacts" step

# 2. Build locally
cd <module>
npm install
npm run lint
npm run build
npm test

# 3. Fix issues locally
# Make necessary code changes

# 4. Push changes
git add .
git commit -m "Fix build issues"
git push
```

### For Failed Deployment

```bash
# 1. Check deployment status
az deployment group show \
  --resource-group helios-staging \
  --name <deployment-name>

# 2. View error details
az deployment group show \
  --resource-group helios-staging \
  --name <deployment-name> \
  --query "properties.error"

# 3. Rollback
az deployment group create \
  --resource-group helios-staging \
  --template-file template-v1.0.0.json

# 4. Verify resources
az resource list --resource-group helios-staging
```

---

## FAQ

### Q: How do I re-run a workflow?

**A**:

```bash
# Using GitHub CLI
gh run rerun <RUN_ID>

# Or GitHub UI
# Go to workflow run → "Re-run jobs" → "Re-run all jobs"
```

### Q: Can I test workflows locally?

**A**:

```bash
# Use act - GitHub Actions local runner
# https://github.com/nektos/act
act push
act pull_request
```

### Q: How long do workflow runs keep?

**A**:

- Workflow history: 400 runs (oldest auto-deleted)
- Artifacts: 7 days default (configurable up to 90)
- Logs: 90 days (not deletable)

### Q: Can I skip a workflow for specific files?

**A**:

```yaml
on:
  push:
    paths-ignore:
      - 'docs/**'
      - '**.md'
```

### Q: How do I debug secrets?

**A**:

```yaml
# Secrets are masked in logs
- name: Debug (No secrets printed)
  run: echo "API Key: ${{ secrets.API_KEY }}"
  # Output: API Key: ***

# To debug without printing
- name: Debug Safely
  run: |
    if [ -z "${{ secrets.API_KEY }}" ]; then
      echo "ERROR: API_KEY not set"
    else
      echo "API_KEY is set"
    fi
```

### Q: Why is my workflow slow?

**A**:

- Check for large downloads
- Verify caching is working
- Look for sequential jobs (use parallelization)
- Check network connectivity
- Monitor resource usage

### Q: How do I handle flaky tests?

**A**:

```yaml
- name: Run Tests with Retry
  run: |
    for i in {1..3}; do
      npm test && break || echo "Attempt $i failed"
    done

# Or configure in test framework
# jest.config.js
testTimeout: 10000,  # Increase timeout
```

---

## Getting Help

### Internal Resources

1. **Documentation**:
   - `/docs/workflows/` - All workflow docs
   - `.github/workflows/` - Workflow files
   - `README.md` - Setup instructions

2. **Team**:
   - DevOps channel on Slack
   - Team email: devops@helios.local
   - Stand-up meetings: Daily 10 AM

3. **External**:
   - [GitHub Actions Docs](https://docs.github.com/en/actions)
   - [GitHub Community](https://github.community)
   - Stack Overflow: `github-actions` tag

### Creating Issues

When reporting workflow issues:

```markdown
## Issue Description
Brief description of the problem

## Steps to Reproduce
1. ...
2. ...
3. ...

## Expected Behavior
What should happen

## Actual Behavior
What actually happened

## Environment
- Workflow: `build-all-modules.yml`
- Run ID: #12345
- OS: ubuntu-latest
- Version: Node 18

## Logs
[Paste relevant logs]

## Artifacts
[Attach artifacts if applicable]
```

---

**Document Version**: 1.0  
**Last Updated**: 2024  
**Status**: Active ✅
