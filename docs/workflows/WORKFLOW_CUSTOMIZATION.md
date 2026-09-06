# Workflow Customization Guide - HELIOS Platform

## Overview

This guide explains how to customize, extend, and maintain GitHub Actions workflows for the HELIOS Platform.

**Version**: 1.0  
**Last Updated**: 2024  
**Audience**: DevOps Engineers, Technical Leads

---

## Table of Contents

1. [Modifying Existing Workflows](#modifying-existing-workflows)
2. [Adding New Workflows](#adding-new-workflows)
3. [Custom Actions](#custom-actions)
4. [Matrix Configuration](#matrix-configuration)
5. [Conditional Execution](#conditional-execution)
6. [Environment Variables](#environment-variables)
7. [Workflow Templates](#workflow-templates)

---

## Modifying Existing Workflows

### Safe Modification Process

```
1. Create feature branch
2. Modify workflow
3. Push to branch (triggers test run)
4. Monitor execution
5. Verify no side effects
6. Merge to main
7. Verify production run
```

### Step 1: Create Feature Branch

```bash
git checkout -b feature/update-build-workflow
```

### Step 2: Modify Workflow

```yaml
# .github/workflows/build-all-modules.yml

# Add new step
- name: New Step
  run: echo "New functionality"

# Modify existing step
- name: Install Dependencies
  run: npm ci --prefer-offline --no-audit
  # Added: --prefer-offline flag

# Remove step (comment out)
# - name: Old Step
#   run: deprecated-command
```

### Step 3: Test on Feature Branch

```bash
# Push changes
git add .
git commit -m "Add new build step"
git push origin feature/update-build-workflow

# Monitor execution
gh run list -b feature/update-build-workflow --watch

# Check for issues
gh run view <RUN_ID>
```

### Step 4: Merge to Production

```bash
# Create pull request
gh pr create --base main

# Review and merge
gh pr merge <PR_NUMBER> --merge

# Monitor main branch runs
gh run list -b main --watch
```

---

## Adding New Workflows

### Workflow Structure

```yaml
name: New Workflow Description

on:
  # Triggers
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  checks: write

concurrency:
  group: ${{ github.workflow }}-${{ github.head_ref || github.run_id }}
  cancel-in-progress: true

jobs:
  job-name:
    name: Job Display Name
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4
      
      - name: Execute Task
        run: echo "Task execution"
      
      - name: Upload Results
        if: always()
        uses: actions/upload-artifact@v3
        with:
          name: results
          path: results/
```

### Example: Custom Validation Workflow

```yaml
name: Custom Validation

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

permissions:
  contents: read

jobs:
  validate:
    name: Custom Validation
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      
      - name: Setup Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      
      - name: Install Dependencies
        run: |
          python -m pip install --upgrade pip
          pip install custom-validator
      
      - name: Run Validation
        run: python scripts/validate.py
      
      - name: Upload Report
        if: always()
        uses: actions/upload-artifact@v3
        with:
          name: validation-report
          path: validation-report.json
      
      - name: Comment on PR
        if: github.event_name == 'pull_request'
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const report = JSON.parse(fs.readFileSync('validation-report.json'));
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: `## Validation Results\n\n${report.summary}`
            });
```

---

## Custom Actions

### Using Custom Actions

```yaml
# Use local custom action
- name: Use Custom Action
  uses: ./.github/actions/my-custom-action
  with:
    param1: value1
    param2: value2

# Use action from another repository
- name: Use External Action
  uses: owner/repo/path/to/action@v1
  with:
    param: value
```

### Creating Custom Actions

**Structure**:

```
.github/
└── actions/
    └── my-custom-action/
        ├── action.yml
        ├── index.js
        └── lib/
            └── helpers.js
```

**action.yml**:

```yaml
name: 'My Custom Action'
description: 'Description of what the action does'

inputs:
  param1:
    description: 'First parameter'
    required: true
  param2:
    description: 'Second parameter'
    required: false
    default: 'default-value'

outputs:
  result:
    description: 'Output result'
    value: ${{ steps.main.outputs.result }}

runs:
  using: 'node16'
  main: 'index.js'
```

**index.js**:

```javascript
const core = require('@actions/core');
const exec = require('@actions/exec');

async function run() {
  try {
    const param1 = core.getInput('param1');
    const param2 = core.getInput('param2');
    
    // Perform action
    const result = await exec.exec('echo', [param1]);
    
    // Set output
    core.setOutput('result', result);
  } catch (error) {
    core.setFailed(error.message);
  }
}

run();
```

---

## Matrix Configuration

### Basic Matrix

```yaml
strategy:
  matrix:
    version: ['6.0', '7.0', '8.0']
    os: [ubuntu-latest, windows-latest]
```

**Creates**: 3 × 2 = 6 combinations

### Advanced Matrix

```yaml
strategy:
  matrix:
    include:
      - os: ubuntu-latest
        node: 18
        npm: 9
      - os: windows-latest
        node: 18
        npm: 9
      - os: macos-latest
        node: 18
        npm: 9
    exclude:
      - os: macos-latest
        node: 16  # Don't test old version on macOS
```

### Matrix with Conditions

```yaml
jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-latest, windows-latest]
        framework: [jest, mocha]
    runs-on: ${{ matrix.os }}
    
    steps:
      - name: Use Framework
        run: |
          case "${{ matrix.framework }}" in
            jest)
              npm install jest
              npm test
              ;;
            mocha)
              npm install mocha
              npm test
              ;;
          esac
```

---

## Conditional Execution

### Branch-Based Conditions

```yaml
# Only on main branch
- name: Deploy
  if: github.ref == 'refs/heads/main'
  run: npm run deploy

# Only on PRs
- name: Review Changes
  if: github.event_name == 'pull_request'
  run: npm run review

# Only on tags
- name: Create Release
  if: startsWith(github.ref, 'refs/tags/v')
  run: npm run create-release
```

### Environment-Based Conditions

```yaml
# Windows only
- name: Windows Task
  if: runner.os == 'Windows'
  run: powershell -Command "Get-ChildItem"

# Linux only
- name: Linux Task
  if: runner.os == 'Linux'
  run: ls -la

# Not macOS
- name: Skip macOS
  if: runner.os != 'macOS'
  run: echo "Running on non-macOS"
```

### Status-Based Conditions

```yaml
# Only if previous step succeeded
- name: Next Step
  if: success()
  run: npm run next

# Run even if previous failed
- name: Cleanup
  if: always()
  run: npm run cleanup

# Only if previous failed
- name: Rollback
  if: failure()
  run: npm run rollback

# Only if cancelled
- name: Notify Cancellation
  if: cancelled()
  run: echo "Workflow was cancelled"
```

### File-Based Conditions

```yaml
# Check if file exists
- name: Run if Config Exists
  if: hashFiles('config.json') != ''
  run: npm run with-config

# Check multiple files
- name: Complex Check
  if: |
    hashFiles('package.json') != '' &&
    hashFiles('src/**/*.ts') != ''
  run: npm run build
```

---

## Environment Variables

### Workflow-Level Variables

```yaml
name: Workflow with Variables

env:
  NODE_ENV: production
  API_ENDPOINT: https://api.example.com
  LOG_LEVEL: info

on: [push]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: echo "NODE_ENV=$NODE_ENV"
```

### Job-Level Variables

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    env:
      BUILD_DIR: ./dist
      CACHE_DIR: ./cache
    
    steps:
      - run: mkdir -p $BUILD_DIR $CACHE_DIR
```

### Step-Level Variables

```yaml
steps:
  - name: Build with Variables
    env:
      CUSTOM_VAR: custom_value
    run: |
      echo "CUSTOM_VAR=$CUSTOM_VAR"
      echo "BUILD_DIR=$BUILD_DIR"  # From job level
      echo "NODE_ENV=$NODE_ENV"    # From workflow level
```

### Setting Variables During Execution

```yaml
- name: Set Dynamic Variables
  run: |
    echo "BUILD_NUMBER=${{ github.run_number }}" >> $GITHUB_ENV
    echo "TIMESTAMP=$(date +%s)" >> $GITHUB_ENV

- name: Use Dynamic Variables
  run: |
    echo "Build: $BUILD_NUMBER"
    echo "Time: $TIMESTAMP"
```

### GitHub Default Variables

```yaml
- name: Show Defaults
  run: |
    echo "Repository: ${{ github.repository }}"
    echo "Actor: ${{ github.actor }}"
    echo "Ref: ${{ github.ref }}"
    echo "SHA: ${{ github.sha }}"
    echo "Run ID: ${{ github.run_id }}"
    echo "Job: ${{ github.job }}"
    echo "Runner: ${{ runner.os }}"
```

---

## Workflow Templates

### Template 1: Build & Test

```yaml
name: Build & Test Template

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

permissions:
  contents: read
  checks: write

jobs:
  build:
    runs-on: ubuntu-latest
    
    strategy:
      matrix:
        version: ['16', '18']
    
    steps:
      - uses: actions/checkout@v4
      
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.version }}
          cache: npm
      
      - run: npm ci
      - run: npm run lint
      - run: npm run build
      - run: npm test
      
      - uses: actions/upload-artifact@v3
        if: always()
        with:
          name: coverage-node-${{ matrix.version }}
          path: coverage/
```

### Template 2: Publish Package

```yaml
name: Publish Package Template

on:
  push:
    tags: ['v*.*.*']

permissions:
  contents: write
  packages: write

jobs:
  publish:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v4
      
      - uses: actions/setup-node@v4
        with:
          node-version: 18
          registry-url: 'https://registry.npmjs.org'
      
      - run: npm ci
      - run: npm test
      
      - name: Publish
        run: npm publish
        env:
          NODE_AUTH_TOKEN: ${{ secrets.NPM_TOKEN }}
      
      - name: Create Release
        uses: actions/create-release@v1
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          tag_name: ${{ github.ref }}
          release_name: Release ${{ github.ref_name }}
```

### Template 3: Deployment

```yaml
name: Deploy Template

on:
  workflow_dispatch:
    inputs:
      environment:
        type: choice
        options: [dev, staging, prod]
      version:
        description: 'Version to deploy'
        required: true

permissions:
  contents: read
  id-token: write

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: ${{ github.event.inputs.environment }}
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Deploy
        run: |
          echo "Deploying v${{ github.event.inputs.version }} to ${{ github.event.inputs.environment }}"
          # Deploy commands here
      
      - name: Verify
        run: |
          echo "Verifying deployment..."
          # Verification commands here
```

---

## Workflow Maintenance

### Regular Reviews

- **Monthly**: Check for action updates
- **Quarterly**: Review performance metrics
- **Yearly**: Audit security practices

### Documentation

Always document:

- Purpose of workflow
- Trigger conditions
- Expected duration
- Dependencies
- Change history

### Version Control

```bash
# Track workflow changes
git log --oneline -- .github/workflows/

# View specific workflow history
git log -p -- .github/workflows/build.yml
```

---

## Best Practices for Customization

✅ **Do**:

- Test in branch before merging
- Document changes clearly
- Update related documentation
- Monitor for side effects
- Version workflows appropriately

❌ **Don't**:

- Modify workflows in production without testing
- Make breaking changes to shared workflows
- Remove security checks
- Disable error handling
- Hardcode environment-specific values

---

## References

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Workflow Syntax](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)
- [Creating Actions](https://docs.github.com/en/actions/creating-actions)
- [Matrix Builds](https://docs.github.com/en/actions/using-jobs/using-a-build-matrix-for-your-jobs)

---

**Document Version**: 1.0  
**Last Updated**: 2024  
**Status**: Active ✅
