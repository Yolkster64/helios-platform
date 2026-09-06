# Automation Guide for HELIOS Platform

Best practices for GitHub Actions workflows and automation.

---

## Table of Contents

1. [Workflow Best Practices](#workflow-best-practices)
2. [Job Structure](#job-structure)
3. [Status Check Requirements](#status-check-requirements)
4. [Artifact Management](#artifact-management)
5. [Logging Standards](#logging-standards)
6. [Error Handling](#error-handling)
7. [Performance Optimization](#performance-optimization)

---

## Workflow Best Practices

### Naming Convention

```yaml
# ✓ Good names
name: CI/CD Pipeline
name: Code Quality
name: Deploy to Production

# ✗ Bad names
name: Workflow
name: Test
name: Check
```

### Workflow Structure

```yaml
name: CI/CD Pipeline
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [develop]

env:
  NODE_VERSION: '16'
  NPM_REGISTRY: 'https://registry.npmjs.org'

jobs:
  quality:
    name: Code Quality
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v3
      
      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: ${{ env.NODE_VERSION }}
      
      - name: Install dependencies
        run: npm ci
      
      - name: Run linter
        run: npm run lint
      
      - name: Run tests
        run: npm test
```

### Event Triggers

```yaml
on:
  # Run on push to main/develop
  push:
    branches:
      - main
      - develop
  
  # Run on pull requests
  pull_request:
    branches:
      - main
      - develop
  
  # Run on schedule
  schedule:
    - cron: '0 0 * * 0'  # Weekly
    - cron: '0 */6 * * *' # Every 6 hours
  
  # Manual trigger
  workflow_dispatch:
    inputs:
      environment:
        description: 'Deployment environment'
        required: true
        default: 'staging'
```

---

## Job Structure

### Consistent Job Format

```yaml
jobs:
  build:
    name: Build and Test
    runs-on: ubuntu-latest
    timeout-minutes: 30
    
    # Run job only on main repo (not forks)
    if: github.repository == 'org/repo'
    
    strategy:
      matrix:
        node-version: [16, 18, 20]
        os: [ubuntu-latest, macos-latest]
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v3
      
      - name: Setup Node.js ${{ matrix.node-version }}
        uses: actions/setup-node@v3
        with:
          node-version: ${{ matrix.node-version }}
          cache: 'npm'
      
      - name: Install dependencies
        run: npm ci
      
      - name: Build
        run: npm run build
      
      - name: Upload artifacts
        if: success()
        uses: actions/upload-artifact@v3
        with:
          name: build-${{ matrix.node-version }}
          path: dist/
      
      - name: Report results
        if: always()
        run: echo "Build completed with status: ${{ job.status }}"
```

### Job Dependencies

```yaml
jobs:
  lint:
    name: Lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - run: npm ci && npm run lint
  
  test:
    name: Test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - run: npm ci && npm test
  
  deploy:
    name: Deploy
    runs-on: ubuntu-latest
    needs: [lint, test]  # Wait for lint and test
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v3
      - run: npm ci && npm run deploy
```

---

## Status Check Requirements

### Required Checks for Main Branch

```yaml
# Configure in repository settings
Branch protection rules:
✓ Require the following status checks to pass:
  - CI/CD
  - Test (ubuntu-latest)
  - Test (macos-latest)
  - Lint
  - Security Scan
  - Coverage

✓ Require branches to be up-to-date
✓ Include administrators in restrictions
```

### Status Check Names

```yaml
# Use consistent, descriptive names
jobs:
  lint:
    name: Lint  # Shows as "Lint" in PR
  
  test:
    name: Test (Node ${{ matrix.node-version }})
    # Shows as "Test (Node 16)" etc.
  
  coverage:
    name: Coverage Report
```

### Conditional Status Checks

```yaml
jobs:
  build:
    name: Build
    runs-on: ubuntu-latest
    
    # Only run on pull requests to develop
    if: >
      github.event_name == 'pull_request' &&
      github.base_ref == 'develop'
    
    steps:
      - uses: actions/checkout@v3
      - run: npm ci && npm run build
```

---

## Artifact Management

### Uploading Artifacts

```yaml
steps:
  - name: Build
    run: npm run build
  
  # Upload build artifacts
  - name: Upload build artifacts
    uses: actions/upload-artifact@v3
    if: always()
    with:
      name: build-${{ github.run_id }}
      path: dist/
      retention-days: 30  # Keep for 30 days
```

### Downloading Artifacts

```yaml
jobs:
  build:
    name: Build
    runs-on: ubuntu-latest
    steps:
      - run: npm run build
      - uses: actions/upload-artifact@v3
        with:
          name: build-output
          path: dist/
  
  deploy:
    name: Deploy
    runs-on: ubuntu-latest
    needs: build
    steps:
      - uses: actions/download-artifact@v3
        with:
          name: build-output
          path: dist/
      
      - run: npm run deploy
```

### Artifact Cleanup

```yaml
# Workflow to clean old artifacts
name: Cleanup Artifacts
on:
  schedule:
    - cron: '0 0 * * 0'  # Weekly

jobs:
  cleanup:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/github-script@v6
        with:
          script: |
            const artifacts = await github.rest.actions.listArtifactsForRepo({
              owner: context.repo.owner,
              repo: context.repo.repo,
            });
            
            for (const artifact of artifacts.data.artifacts) {
              if (artifact.expired) {
                github.rest.actions.deleteArtifact({
                  owner: context.repo.owner,
                  repo: context.repo.repo,
                  artifact_id: artifact.id,
                });
              }
            }
```

---

## Logging Standards

### Workflow Logging

```yaml
steps:
  - name: Build
    run: npm run build 2>&1 | tee build.log
    # Capture both stdout and stderr
  
  - name: Show build log
    if: failure()
    run: cat build.log
  
  - name: Debug information
    if: failure()
    run: |
      echo "Node version: $(node --version)"
      echo "NPM version: $(npm --version)"
      echo "Environment: ${{ github.environment }}"
```

### Log Masking

```yaml
steps:
  - name: Log in
    run: |
      # Mask sensitive data
      echo "::add-mask::${{ secrets.API_KEY }}"
      echo "API_KEY=${{ secrets.API_KEY }}" >> $GITHUB_ENV
```

### Step Summaries

```yaml
steps:
  - name: Test Report
    run: |
      echo "## Test Results" >> $GITHUB_STEP_SUMMARY
      echo "" >> $GITHUB_STEP_SUMMARY
      echo "✓ Passed: 95" >> $GITHUB_STEP_SUMMARY
      echo "✗ Failed: 0" >> $GITHUB_STEP_SUMMARY
      echo "⊙ Skipped: 5" >> $GITHUB_STEP_SUMMARY
```

---

## Error Handling

### Handling Failures

```yaml
steps:
  - name: Build
    run: npm run build
    continue-on-error: true
    # Continue even if this fails
  
  - name: Report
    if: failure()
    # Runs if previous step failed
    run: echo "Build failed"
  
  - name: Cleanup
    if: always()
    # Always runs, regardless of status
    run: npm run cleanup
```

### Retry Logic

```yaml
steps:
  - name: Deploy
    uses: some-action@v1
    with:
      timeout_minutes: 5
    retries: 3
    delay_seconds: 60
```

### Error Context

```yaml
steps:
  - name: Run tests
    id: test
    run: npm test || exit 1
  
  - name: Report failure
    if: failure()
    run: |
      echo "Test step failed: ${{ steps.test.outcome }}"
      echo "Step status: ${{ job.status }}"
      echo "Runner: ${{ runner.os }}"
```

---

## Performance Optimization

### Dependency Caching

```yaml
steps:
  - uses: actions/checkout@v3
  
  - uses: actions/setup-node@v3
    with:
      node-version: '18'
      cache: 'npm'
      # Automatically caches node_modules
  
  - run: npm ci  # Use ci instead of install
```

### Parallel Jobs

```yaml
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - run: npm run lint
  
  test:
    runs-on: ubuntu-latest
    steps:
      - run: npm test
  
  build:
    runs-on: ubuntu-latest
    steps:
      - run: npm run build
  
  # All three run in parallel
  # Uses matrix for different configurations
```

### Matrix Strategy

```yaml
jobs:
  test:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        node-version: [16, 18, 20]
        os: [ubuntu-latest, macos-latest, windows-latest]
    
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: ${{ matrix.node-version }}
      - run: npm test
    
    # Creates 9 jobs total (3 versions × 3 OS)
```

### Build Optimization

```yaml
steps:
  - name: Check if build needed
    id: build-check
    run: |
      if git diff --quiet HEAD~1 src/ package.json; then
        echo "no-build=true" >> $GITHUB_OUTPUT
      fi
  
  - name: Build
    if: steps.build-check.outputs.no-build != 'true'
    run: npm run build
```

---

## Common Workflows

### Pull Request Quality Gate

```yaml
name: PR Quality Gate
on:
  pull_request:
    branches: [develop]

jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
      
      - run: npm ci
      - run: npm run lint
      - run: npm run test -- --coverage
      
      - name: Upload coverage
        uses: codecov/codecov-action@v3
        with:
          files: ./coverage/lcov.info
```

### Automated Release

```yaml
name: Release
on:
  push:
    tags:
      - 'v*.*.*'

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
      
      - run: npm ci
      - run: npm run build
      - run: npm run test
      
      - name: Create release
        uses: actions/create-release@v1
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          tag_name: ${{ github.ref }}
          release_name: Release ${{ github.ref }}
```

---

## Troubleshooting Workflows

### Debug Mode

```bash
# Enable debug logging
ACTIONS_STEP_DEBUG=true
```

### Workflow Runs Page

View all runs: Repository → Actions → [Workflow] → All runs

### Checking Logs

```yaml
# View logs in GitHub UI
- Click workflow run
- Click specific job
- View step output

# Or download logs
- Click "Download all logs" in workflow run
```

---

**Last Updated:** April 2026  
**Version:** 1.0

See also: [GITHUB_BEST_PRACTICES.md](GITHUB_BEST_PRACTICES.md)
