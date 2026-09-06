# GitHub Project Setup Guide

## Creating the GitHub Project (Manual Steps via Web)

### Step 1: Create Project Board

1. Go to: https://github.com/M0nado/helios-platform
2. Click **"Projects"** tab
3. Click **"New project"**
4. Select **"Table"** template
5. Name: **"HELIOS Platform v2"**
6. Description: **"Complete modular Windows optimization ecosystem with 4 phases and 45+ submodules"**

### Step 2: Add Project Columns

Create these statuses:

- **Backlog** - All items to do
- **Structure** - Architecture/folder setup
- **In Progress** - Active work
- **Review** - Code review phase
- **Done** - Complete items

### Step 3: Add Project Fields

Add custom fields:

- **Phase** (Single select: 0, 1, 2, 3)
- **Component** (Text: which component)
- **Priority** (Single select: Low, Medium, High, Critical)
- **Work Track** (Single select: Track 1-5)
- **Owner** (Single select: team members)

### Step 4: Create Issues

Create 45+ issues for submodules:

#### Track 1: Foundation (Phase 0)

```
Issue: USB Creator Script
- Phase: 0
- Component: Installer
- Priority: Critical
- Work Track: 1
- Description: Create bootable USB with Windows 11 and HELIOS phase 0 scripts
```

#### Track 2: Security (Phase 1)

```
Issue: AppLocker Baseline Rules
- Phase: 1
- Component: Security System
- Priority: High
- Work Track: 2

Issue: Windows Firewall Configuration
- Phase: 1
- Component: Security System
- Priority: High
- Work Track: 2

Issue: Vault Encryption Setup
- Phase: 1
- Component: Security System
- Priority: High
- Work Track: 2
```

#### Track 3: Optimization (Phase 2)

```
Issue: Service Optimization Level 1
- Phase: 2
- Component: Optimization
- Priority: High
- Work Track: 3

Issue: Service Optimization Level 2
- Phase: 2
- Component: Optimization
- Priority: Medium
- Work Track: 3
```

#### Track 4: Capability (Phase 3)

```
Issue: AI Dashboard Core
- Phase: 3
- Component: GUI Dashboard
- Priority: High
- Work Track: 4

Issue: Learning Engine Integration
- Phase: 3
- Component: Monado Engine
- Priority: High
- Work Track: 4
```

#### Track 5: Integration

```
Issue: ChatGPT Pro Integration
- Phase: 3
- Component: AI Integration
- Priority: Medium
- Work Track: 5

Issue: Azure Deployment Scripts
- Phase: 3
- Component: Microsoft Ecosystem
- Priority: Medium
- Work Track: 5
```

### Step 5: Create Milestones

1. Click **"Milestones"** tab
2. Create these milestones:

```
Milestone: Phase 0 - Foundation
Due Date: [2 weeks from start]
Issues: All Phase 0 tasks

Milestone: Phase 1 - Security
Due Date: [4 weeks from start]
Issues: All Phase 1 tasks

Milestone: Phase 2 - Optimization
Due Date: [8 weeks from start]
Issues: All Phase 2 tasks

Milestone: Phase 3 - Capability
Due Date: [12 weeks from start]
Issues: All Phase 3 tasks

Milestone: Documentation Complete
Due Date: [1 week from start]
Issues: All doc tasks

Milestone: Testing & Validation
Due Date: [Ongoing]
Issues: All test tasks
```

### Step 6: Add Issue Templates

Create `.github/ISSUE_TEMPLATE/` with:

**bug_report.md**

```markdown
---
name: Bug Report
about: Report a bug in HELIOS
title: "[BUG] "
labels: bug
assignees: ''
---

## Description
[Describe the bug]

## Affected Phase/Component
- Phase: 
- Component: 

## Steps to Reproduce
1. ...

## Expected Behavior
[What should happen]

## Actual Behavior
[What actually happens]

## Screenshots
[If applicable]

## Environment
- Phase: 
- Windows Version: 
```

**feature_request.md**

```markdown
---
name: Feature Request
about: Suggest a new feature
title: "[FEATURE] "
labels: enhancement
assignees: ''
---

## Feature Description
[Describe the feature]

## Why This Feature
[Explain the benefit]

## Affected Phase/Component
- Phase: 
- Component: 

## Suggested Implementation
[Optional: how to implement]
```

## Automating Project Management

### GitHub Actions Workflow to Auto-Add Issues to Project

Create `.github/workflows/project-automation.yml`:

```yaml
name: Auto-add to Project

on:
  issues:
    types: [opened]

jobs:
  add-to-project:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/add-to-project@v0.5.0
        with:
          project-url: https://github.com/M0nado/helios-platform/projects/1
          github-token: ${{ secrets.GITHUB_TOKEN }}
          labeled: ready
```

## Using the GitHub Project

### For Users/Contributors

1. **View Project**: https://github.com/M0nado/helios-platform/projects/1
2. **Pick a Task**: Find unassigned task in Backlog
3. **Self-Assign**: Click "Assignees" and select yourself
4. **Move to In Progress**: Drag issue to "In Progress" column
5. **Create Branch**: Use GitHub Desktop or CLI
6. **Submit PR**: When ready for review

### For Team Leads

1. **Monitor Progress**: View project board regularly
2. **Unblock Issues**: Check "In Progress" for blocked items
3. **Move to Review**: When PR created, move to "Review"
4. **Merge**: Move to "Done" when PR merged
5. **Track Metrics**: Count cards in each column for velocity

## GitHub Codespaces Launch

### Pre-configured Commands

In Codespaces terminal:

```bash
# List all phases
ls phases/

# View current phase docs
cat phases/0-foundation/README.md

# Run a script
pwsh ./phases/0-foundation/build.ps1

# Push changes
git add .
git commit -m "Work on feature X"
git push origin feature-branch
```

### Codespaces Settings

1. Go to https://github.com/M0nado/helios-platform/settings/codespaces
2. Set **Default Machine Type**: Standard (4-core, 8GB RAM)
3. Enable **Prebuild configurations** for faster startup
4. Set **Idle timeout**: 30 minutes

## View Project Status

### Via GitHub Actions Status Page

- https://github.com/M0nado/helios-platform/actions

### View Workflow Runs

- All CI/CD validation runs are visible
- Click run to see logs
- Status badges can be added to README

## Next Steps

1. **Create Project Board** - Use web interface (5 min)
2. **Add 45+ Issues** - Use issue templates (30 min)
3. **Assign to Milestones** - Group by phase (15 min)
4. **Setup Automation** - Deploy GitHub Actions (10 min)
5. **Enable Codespaces** - Configure prebuild (5 min)
6. **Test Everything** - Create first branch and PR (20 min)

**Total Setup Time: ~85 minutes**

## PowerShell Script to Create Issues via API

```powershell
# Note: Requires GitHub CLI or REST API token

$token = $env:GITHUB_TOKEN
$owner = "M0nado"
$repo = "helios-platform"

$issues = @(
    @{ title = "USB Creator Script"; phase = 0; component = "Installer"; priority = "Critical" },
    @{ title = "AppLocker Baseline"; phase = 1; component = "Security"; priority = "High" },
    # ... more issues
)

foreach ($issue in $issues) {
    $body = @{
        title = $issue.title
        body = "Phase: $($issue.phase)`nComponent: $($issue.component)`nPriority: $($issue.priority)"
        labels = @("phase-$($issue.phase)", $issue.component)
    } | ConvertTo-Json

    Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo/issues" `
        -Method POST `
        -Headers @{ Authorization = "token $token"; Accept = "application/vnd.github.v3+json" } `
        -Body $body
}
```

Save as `scripts/utilities/create-github-issues.ps1` and run once to populate project.
