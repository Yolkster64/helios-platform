# Workflow Integration Matrix - HELIOS Platform

## Overview

This document describes how all GitHub Actions workflows interact, their dependencies, trigger chains, and status propagation mechanisms.

**Version**: 1.0  
**Last Updated**: 2024  
**Scope**: Complete CI/CD pipeline

---

## Table of Contents

1. [Integration Overview](#integration-overview)
2. [Workflow Dependency Graph](#workflow-dependency-graph)
3. [Trigger Chains](#trigger-chains)
4. [Status Propagation](#status-propagation)
5. [Data Flow](#data-flow)
6. [Parallel Execution](#parallel-execution)
7. [Error Handling](#error-handling)
8. [Performance Implications](#performance-implications)

---

## Integration Overview

### All Workflows

```
Workflows (14 total):
├─ code-checks.yml           (Linting)
├─ code-registry-update.yml  (Registry)
├─ ci-validation.yml         (Validation)
├─ build-all-modules.yml     (Build)
├─ build-variant-test.yml    (Variant)
├─ phase-build.yml           (Phase)
├─ nuget.yml                 (Publishing)
├─ deploy.yml                (Deployment)
├─ documentation-update.yml  (Docs)
├─ ai-code-review.yml        (Review)
├─ component-version-check.yml (Versioning)
├─ multi-repo-sync.yml       (Sync)
├─ status-dashboard.yml      (Dashboard)
└─ wiki-generator.yml        (Wiki)
```

---

## Workflow Dependency Graph

### Critical Path (PR/Push)

```
┌──────────────┐
│ PR/Push      │
│ main/develop │
└──────┬───────┘
       │
       ├─────────────────────────────┐
       │                             │
    (3s)                           (3s)
       │                             │
       ▼                             ▼
┌──────────────────┐      ┌────────────────────┐
│ code-checks.yml  │      │ ci-validation.yml  │
│ Lint & Security  │      │ Validation         │
│ 3-5 min          │      │ 5 min              │
└────────┬─────────┘      └───────┬────────────┘
         │                        │
         └────────────┬───────────┘
                      │
              (Both must pass)
                      │
                      ▼
        ┌──────────────────────────┐
        │ build-all-modules.yml    │
        │ Multi-module build       │
        │ 10-15 min (parallel)     │
        └────────────┬─────────────┘
                     │
       ┌─────────────┴──────────────────┐
       │                                │
       ▼                                ▼
┌─────────────────┐       ┌──────────────────────┐
│ Test Phase      │       │ documentation-update │
│ Coverage Checks │       │ Build docs           │
│ 8-12 min        │       │ 5 min                │
└────────┬────────┘       └──────────────────────┘
         │
         └─────────┬──────────┘
                   │
              (Optional)
                   │
              [On Tags only]
                   │
                   ▼
        ┌────────────────────┐
        │ nuget.yml          │
        │ Package & Publish  │
        │ 8-12 min           │
        └────────────────────┘
```

### Tag Trigger Chain

```
Push Tag (v*.*.*)
       │
       ├─ code-checks ✓
       │
       ├─ build-all-modules ✓
       │
       └─ nuget.yml
          ├─ Build (multi-framework)
          ├─ Package
          ├─ Publish to NuGet.org
          └─ Publish to GitHub Packages
```

### Manual Deployments

```
workflow_dispatch
       │
       ├─ deploy.yml (Manual only)
       │  ├─ Deploy Phase to Environment
       │  ├─ Test Deployment
       │  └─ Notify Status
       │
       └─ status-dashboard.yml (Update status)
```

### Scheduled Tasks

```
cron: 0 2 * * *  (Daily)
       │
       ├─ component-version-check.yml
       ├─ multi-repo-sync.yml
       ├─ wiki-generator.yml
       └─ status-dashboard.yml (Update)
```

---

## Trigger Chains

### Chain 1: Standard Push/PR Flow

```
Trigger: Push to main/develop
Timing:  Immediate

Step 1: code-checks (0 min)
  - Syntax validation
  - Security scan
  - Documentation check
  └─ Pass required for next step

Step 2: build-all-modules (5 min delay from T0)
  - Parallel module builds
  - Test execution
  - Coverage reports
  └─ Pass required for status checks

Step 3: ci-validation (concurrent)
  - Framework compatibility
  - Integration tests
  └─ Informational (doesn't block)

Step 4: documentation-update (optional)
  - Auto-update README
  - Update API docs
  └─ Concurrent with builds

Total time: 15-20 minutes
Critical path: code-checks + build-all-modules + tests
```

### Chain 2: Release/Tag Flow

```
Trigger: Push tag v*.*.* to main
Timing:  Immediate

Step 1: code-checks (from push)
Step 2: build-all-modules (from push)
Step 3: [Trigger only if steps 1-2 pass]
        nuget.yml
  - Build multi-framework
  - Create NuGet package
  - Publish to NuGet.org
  - Publish to GitHub Packages
  - Create GitHub Release
  └─ Creates release assets

Total time: 30-45 minutes
New workflows: nuget job only
```

### Chain 3: Manual Deployment

```
Trigger: workflow_dispatch (manual)
Timing:  When user clicks "Run workflow"

User selects:
  - Environment: development/staging/production
  - Phase: 0-foundation/1-security/2-optimization/3-capability

Step 1: deploy.yml
  - Azure login
  - Validate phase configuration
  - Deploy to environment
  - Run post-deployment tests
  - Notify status

Total time: 10-35 minutes (environment-dependent)
Parallel workflows: None (sequential)
```

### Chain 4: Scheduled Tasks

```
Daily (0 2 * * *):
  └─ component-version-check.yml

Weekly (0 3 * * 0):
  └─ multi-repo-sync.yml

Monthly (0 4 1 * *):
  └─ wiki-generator.yml
```

---

## Status Propagation

### Branch Protection Status

```
GitHub Branch Protection Rules:
├─ Required: code-checks ✓
├─ Required: build-all-modules ✓
├─ Optional: ci-validation
├─ Optional: documentation-update
└─ Optional: component-version-check

Merge blocked if any Required status is:
  - ✗ Failed
  - ⏳ Pending
  - ⚪ Skipped (if set as required)
```

### Status Check Flow

```
Workflow Step → Workflow Status → Commit Status → PR Status

Example:
  code-checks syntax-check → code-checks → ✓ Passing → ✅ Mergeable
  build-all-modules (5 failures) → build-all-modules → ✗ Failing → ❌ Blocked
```

### PR Comment Reporting

```yaml
# After build completion
if: github.event_name == 'pull_request'
  - Comment posted with:
    - Build status (✓/✗)
    - Module results
    - Coverage summary
    - Artifacts links
```

### Commit Status Badges

```markdown
[![Build Status](url)](url)
[![Code Checks](url)](url)
[![Deploy Status](url)](url)
```

---

## Data Flow

### Artifact Flow

```
                              Workflow Artifacts
                              (7 day retention)
                                    │
                ┌───────────────────┼───────────────────┐
                │                   │                   │
                ▼                   ▼                   ▼
         Build Artifacts      Test Results        Coverage Reports
         (dist/, build/)      (.trx files)        (coverage/ dir)
                │                  │                   │
         ├─ core/dist       ├─ test-core         ├─ coverage-core
         ├─ modules/dist    ├─ test-modules      ├─ coverage-modules
         ├─ registry/dist   ├─ test-registry     ├─ coverage-registry
         ├─ cli/dist        ├─ test-cli          ├─ coverage-cli
         └─ ui/dist         └─ test-ui           └─ coverage-ui
                │                  │                   │
                │         (30 day retention)          │
                │                  │                   │
                └──────────────┬───┴───────────────────┘
                               │
                               ▼
                         nuget.yml (on tags)
                               │
                    ┌──────────┼──────────┐
                    │          │          │
                    ▼          ▼          ▼
            NuGet Package  GitHub Release  GitHub Packages
            (.nupkg)       (Release notes)  (Private registry)
                    │
                    ▼ (Published)
                NuGet.org (Public)
```

### Secret Flow

```
GitHub Secrets
├─ NUGET_API_KEY      ──→ nuget.yml (publish)
├─ AZURE_CREDENTIALS  ──→ deploy.yml (authentication)
├─ GITHUB_TOKEN       ──→ PR comments, releases
└─ API_KEYS           ──→ Various workflows

Secure flow:
  1. Stored in GitHub Secrets vault
  2. Not printed in logs
  3. Available as ${{ secrets.NAME }}
  4. Masked in workflow output
  5. Not available in PR forks (security)
```

### Environment Variables Flow

```
GitHub Environment Variables
├─ NODE_VERSION: 18        ──→ build-all-modules
├─ DOTNET_VERSION: 8.0     ──→ nuget.yml
├─ AZURE_REGION: eastus    ──→ deploy.yml
└─ TEST_TIMEOUT: 30000     ──→ ci-validation

Matrix Variables
├─ matrix.module            ──→ build-all-modules
├─ matrix.os                ──→ nuget.yml
└─ matrix.dotnet-version    ──→ nuget.yml
```

---

## Parallel Execution

### Concurrent Workflows (Same Trigger)

```
PR Created:
  │
  ├─ code-checks (parallel)
  ├─ ci-validation (parallel)
  └─ build-all-modules (waits for code-checks)
       └─ 5 module builds (parallel)
```

### Matrix Parallelization

```
build-all-modules:
  matrix:
    module: [core, modules, registry, cli, ui]
    
Execution:
  Time 0:    [core] [modules] [registry] [cli] [ui]  ← 5 jobs
             └─────────────────────────────────────┘
                    3-5 minutes total

Sequential execution would take: 15-25 minutes
**Speedup: 4-5x**
```

### Job Concurrency Limits

```
GitHub-hosted runners available:
  - linux: Unlimited (usually)
  - windows: 1 (limited)
  - macos: 5

HELIOS Platform typically uses:
  - 5 × ubuntu-latest (build-all-modules matrix)
  - 1 × ubuntu-latest (other workflows)
  - 1 × windows-latest (code-checks, nuget)

No concurrency issues expected
```

---

## Error Handling

### Failure Propagation

```
Failure Chain:

code-checks fails
  └─ build-all-modules SKIPPED
       └─ testing SKIPPED
            └─ PR cannot merge
                 └─ Author notified via PR comment

Mitigation:
  - Fix code-checks issues
  - Re-push to retry
```

### Continue on Error

```yaml
# Some steps can continue despite failures
- name: Run Tests
  continue-on-error: true
  run: npm test

# Workflow continues but marks as failed overall
```

### Retry Strategy

```
Transient failures (network, timeouts):
  - Auto-retry: No built-in retry
  - Manual retry: Rerun failed job in GitHub UI
  - Re-push: Force re-run by pushing to branch

Persistent failures (code, config):
  - Fix issue in code
  - Re-push to trigger workflow
```

### Status Reporting

```
Failures reported via:
  1. GitHub commit status (✗ Failed)
  2. PR comment (automated)
  3. Email notification (if enabled)
  4. Slack (if configured)
  5. GitHub issues (can auto-create)
```

---

## Performance Implications

### Execution Timeline

```
Standard PR Flow:
  T+ 0 min:  PR created → code-checks starts
  T+ 3 min:  code-checks complete
  T+ 5 min:  build-all-modules starts (5 modules parallel)
  T+ 18 min: build complete
  T+ 20 min: All status checks pass → Mergeable ✓

Total CI time: ~20 minutes
```

### Concurrency Costs

```
Each concurrent job costs:
  - Runner time (seconds)
  - GitHub Actions compute (minutes × rate)
  - Network bandwidth

build-all-modules (5 parallel jobs):
  - Sequential: 5 modules × 3 min = 15 min
  - Parallel: max(3, 3, 3, 2, 3) = 3 min
  - Time saved: 12 min per build
  - Cost: Minimal (same runner time)
```

### Resource Utilization

```
Typical monthly usage:
  - 50 PRs × 20 min = 1,000 minutes
  - 4 releases × 30 min = 120 minutes
  - Scheduled tasks × 20 min = 400 minutes
  - Total: ~1,520 minutes

Free tier: 2,000 minutes/month
Usage: 76% of free tier ✓
```

---

## Dependency Resolution

### Critical Dependencies

```
✓ MUST PASS for merge:
  - code-checks
  - build-all-modules (core)

⚠ Should pass:
  - ci-validation
  - test suite

ℹ Informational only:
  - documentation-update
  - component-version-check
```

### Conditional Dependencies

```
nuget.yml depends on:
  ├─ Tag created (github.ref starts with refs/tags/v)
  ├─ build passed (from same push)
  └─ Previous release status

deploy.yml depends on:
  ├─ Manual trigger
  ├─ Environment selection
  └─ Phase selection
```

---

## Best Practices

✅ **Do**:

- Monitor workflow execution times
- Optimize critical path
- Use parallelization effectively
- Implement proper error handling
- Document dependencies
- Test workflow locally (act)

❌ **Don't**:

- Create circular dependencies
- Over-parallelize (resource limits)
- Ignore workflow status
- Skip status checks
- Leave workflows in error state

---

## References

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Workflow Syntax](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)
- [Contexts and Expressions](https://docs.github.com/en/actions/learn-github-actions/contexts)
- [Workflow Performance](https://docs.github.com/en/actions/learn-github-actions/workflow-runs)

---

**Document Version**: 1.0  
**Last Updated**: 2024  
**Status**: Active ✅
