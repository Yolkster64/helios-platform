# 🚀 Complete GitHub Setup Guide

## Overview

HELIOS Platform is fully integrated with GitHub. This guide walks you through setting everything up.

---

## Part 1: GitHub Project Board Setup (5-10 minutes)

### Step 1: Create GitHub Project

1. Go to: https://github.com/M0nado/helios-platform
2. Click **Projects** tab
3. Click **New project** button
4. Choose **Table** template
5. Fill in:
   - Name: `HELIOS Platform v2`
   - Description: `Complete modular Windows optimization ecosystem`
6. Click **Create project**

### Step 2: Configure Project Fields

In your new project, add these custom fields:

**Click "+" → "Add field"** and create:

| Field Name | Type | Values |
|-----------|------|--------|
| Phase | Single select | 0, 1, 2, 3 |
| Component | Single select | Installer, Security, Optimization, AI, GUI, Tools, Agents |
| Priority | Single select | Low, Medium, High, Critical |
| Work Track | Single select | Track 1, Track 2, Track 3, Track 4, Track 5 |
| Owner | Single select | [Your team members] |
| Status | Single select | Backlog, In Progress, Review, Done |

### Step 3: Create Project Views

Create different views for different purposes:

**View 1: By Phase**

- Group by: Phase
- Sort by: Priority (desc)

**View 2: By Work Track**

- Group by: Work Track
- Sort by: Priority (desc)

**View 3: By Owner**

- Filter by: Owner = [specific person]

**View 4: By Priority**

- Group by: Priority
- Filter by: Status ≠ Done

---

## Part 2: GitHub Actions Setup (Automatic)

### Status Check

All workflows are already configured! ✅

**Location**: `.github/workflows/`

**Existing workflows**:

1. ✅ `ci-validation.yml` - Runs on push/PR
2. ✅ `phase-build.yml` - Manual trigger
3. ✅ `documentation-update.yml` - Runs on doc changes
4. ✅ `deploy.yml` - Manual deployment

### Verify Workflows

1. Go to: https://github.com/M0nado/helios-platform/actions
2. You should see all workflows listed
3. No setup needed - they run automatically!

### Add Status Badges (Optional)

Update your `README.md` with badges:

```markdown
# HELIOS Platform

[![CI Validation](https://github.com/M0nado/helios-platform/actions/workflows/ci-validation.yml/badge.svg)](https://github.com/M0nado/helios-platform/actions/workflows/ci-validation.yml)
[![Documentation](https://github.com/M0nado/helios-platform/actions/workflows/documentation-update.yml/badge.svg)](https://github.com/M0nado/helios-platform/actions/workflows/documentation-update.yml)
```

---

## Part 3: GitHub Codespaces Setup (5 minutes)

### Launch Codespaces

**Option 1: Via Web** (Easiest)

1. Go to: https://github.com/M0nado/helios-platform
2. Click green **Code** button
3. Click **Codespaces** tab
4. Click **Create codespace on main**
5. Wait 2-3 minutes for environment to build
6. VS Code opens in browser - ready to code!

**Option 2: Via Local VS Code**

1. Install "GitHub Copilot" extension
2. Install "Remote - Codespaces" extension
3. Press Ctrl+Shift+P
4. Type: "Codespaces: Create New Codespace"
5. Select repository and branch

**Option 3: Via GitHub CLI**

```bash
# List existing codespaces
gh codespace list

# Create new codespace
gh codespace create --repo M0nado/helios-platform --branch main

# Open in VS Code
gh codespace code --repo M0nado/helios-platform
```

### Configure Codespaces Settings

1. Go to: https://github.com/settings/codespaces
2. Under "Your codespaces":
   - **Machine type**: Standard (4-core, 8GB RAM)
   - **Idle timeout**: 30 minutes
   - **Enable prebuilds**: Yes (faster startup)

### Dev Container Configuration

Already configured! ✅

**File**: `.devcontainer/devcontainer.json`

**Includes**:

- ✅ PowerShell 7.x
- ✅ GitHub CLI
- ✅ Docker-in-Docker
- ✅ VS Code extensions
- ✅ Custom settings

No additional setup needed!

---

## Part 4: GitHub Issues & Templates

### Issue Templates

Already created! ✅

**Location**: `.github/ISSUE_TEMPLATE/`

**Available templates**:

- `bug_report.md` - Report bugs
- `feature_request.md` - Request features

### Create Issues Manually

1. Go to: https://github.com/M0nado/helios-platform/issues
2. Click **New issue**
3. Choose template (bug or feature)
4. Fill in details
5. Add labels: `phase-0`, `security`, `high-priority`, etc.
6. Assign to project: Select "HELIOS Platform v2"
7. Click **Create issue**

### Create 45+ Submodule Issues

Use this PowerShell script to create issues via API:

```powershell
# Set your GitHub token
$token = $env:GITHUB_TOKEN

$issues = @(
    # Track 1: Foundation (Phase 0)
    @{ 
        title = "USB Creator Script"
        body = "Create bootable USB with Windows 11 installer and HELIOS Phase 0 scripts"
        labels = @("phase-0", "installer", "critical")
    },
    @{ 
        title = "Windows Installation Automation"
        body = "Automate Windows 11 Pro installation with custom partitioning"
        labels = @("phase-0", "installer", "high")
    },
    @{ 
        title = "Partition Manager Script"
        body = "Create, manage, and validate disk partitions"
        labels = @("phase-0", "storage", "high")
    },
    
    # Track 2: Security (Phase 1)
    @{ 
        title = "AppLocker Baseline Rules"
        body = "Implement basic AppLocker rules for security foundation"
        labels = @("phase-1", "security", "high")
    },
    @{ 
        title = "Windows Firewall Configuration"
        body = "Configure Windows Firewall with baseline rules"
        labels = @("phase-1", "security", "high")
    },
    @{ 
        title = "Vault Encryption Setup"
        body = "Setup encrypted vault for sensitive data"
        labels = @("phase-1", "security", "high")
    },
    
    # Add more issues as needed...
)

foreach ($issue in $issues) {
    $body = @{
        title = $issue.title
        body = $issue.body
        labels = $issue.labels
    } | ConvertTo-Json

    $response = Invoke-RestMethod -Uri "https://api.github.com/repos/M0nado/helios-platform/issues" `
        -Method POST `
        -Headers @{
            Authorization = "token $token"
            Accept = "application/vnd.github.v3+json"
        } `
        -Body $body
    
    Write-Host "✅ Created: $($issue.title)"
}
```

Save as `scripts/utilities/create-github-issues.ps1` and run once.

---

## Part 5: GitHub Collaborators & Permissions

### Add Team Members

1. Go to: https://github.com/M0nado/helios-platform/settings/access
2. Click **Invite a collaborator**
3. Enter GitHub username
4. Select role:
   - **Maintain**: Can push, review PRs, manage issues
   - **Write**: Can push and review PRs
   - **Read**: Can view and comment only

### Branch Protection Rules

1. Go to: https://github.com/M0nado/helios-platform/settings/branches
2. Click **Add rule**
3. Apply to branch: `main`
4. Enable:
   - ✅ Require pull request reviews before merging (1 reviewer)
   - ✅ Dismiss stale PR approvals
   - ✅ Require status checks to pass (CI validation)
   - ✅ Require branches to be up to date before merging

### Team Structure

Suggested roles:

| Role | What They Do | GitHub Role |
|------|-------------|-------------|
| **Project Lead** | Overall direction, merge PRs | Admin |
| **Developers** | Write code, submit PRs | Maintain |
| **Contributors** | Small features, documentation | Write |
| **Reviewers** | Code review, quality gates | Maintain |

---

## Part 6: GitHub Wiki Setup

### Enable Wiki

1. Go to: https://github.com/M0nado/helios-platform/settings
2. Scroll to **Features**
3. Check **Wikis** if not already checked
4. Click **Save**

### Add Wiki Pages

GitHub Wikis are separate from the main repo.

**Access Wiki**: https://github.com/M0nado/helios-platform/wiki

### Auto-Sync Documentation to Wiki

A workflow already does this! ✅

**Workflow**: `documentation-update.yml`

**What it does**:

- Monitors `.md` files in main repo
- Auto-syncs to GitHub Wiki
- Updates wiki indexes
- Validates all links

No action needed - it's automatic!

---

## Part 7: GitHub Discussions (Optional)

### Enable Discussions

1. Go to: https://github.com/M0nado/helios-platform/settings
2. Scroll to **Features**
3. Check **Discussions** if not already checked

### Create Categories

1. Go to: https://github.com/M0nado/helios-platform/discussions
2. Click **New discussion**
3. Create categories:
   - **General** - General discussion
   - **Ideas** - Feature ideas
   - **Q&A** - Questions
   - **Show & Tell** - Share work

---

## Part 8: GitHub Insights & Analytics

### View Repository Statistics

1. Go to: https://github.com/M0nado/helios-platform/graphs/contributors
2. See contributor activity

### View Pulse

1. Go to: https://github.com/M0nado/helios-platform/pulse
2. See recent activity summary

### View Network

1. Go to: https://github.com/M0nado/helios-platform/network
2. See branch and commit history

---

## 📋 GitHub Setup Checklist

### Before Launch

- [ ] Repository created
- [ ] README.md exists
- [ ] Initial commit pushed
- [ ] Documentation files in place

### Project Board

- [ ] Project board created
- [ ] Custom fields added
- [ ] Views configured
- [ ] Issues created (45+)
- [ ] Issues assigned to project

### GitHub Actions

- [ ] Workflows exist in `.github/workflows/`
- [ ] Status badges added to README
- [ ] Workflows triggered successfully
- [ ] No failed checks

### Codespaces

- [ ] `.devcontainer/` configured
- [ ] Codespace created and tested
- [ ] Extensions installed
- [ ] PowerShell working

### Collaborators

- [ ] Team members invited
- [ ] Appropriate roles assigned
- [ ] Branch protection rules set
- [ ] Merge requirements configured

### Documentation

- [ ] Wiki enabled
- [ ] Auto-sync workflow running
- [ ] Pages appear in wiki
- [ ] Links validated

### Discussions

- [ ] Discussions enabled
- [ ] Categories created
- [ ] Community guidelines posted

---

## 🎯 Quick Commands

### GitHub CLI Essentials

```bash
# Setup GitHub CLI
gh auth login

# Clone repo
gh repo clone M0nado/helios-platform

# View issues
gh issue list --repo M0nado/helios-platform

# Create issue
gh issue create --repo M0nado/helios-platform --title "My Issue"

# View project
gh project view 1 --repo M0nado/helios-platform

# Create PR
gh pr create --repo M0nado/helios-platform --title "My PR" --body "Description"

# View workflow runs
gh run list --repo M0nado/helios-platform

# Watch workflow
gh run watch <run-id> --repo M0nado/helios-platform
```

### Git Workflow (Local)

```bash
# Clone repo locally
git clone https://github.com/M0nado/helios-platform.git
cd helios-platform

# Create feature branch
git checkout -b feature/my-feature

# Make changes
# ... edit files ...

# Commit changes
git add .
git commit -m "Add feature description"

# Push to GitHub
git push -u origin feature/my-feature

# Create PR (GitHub will prompt, or use: gh pr create)

# After approval, merge and delete branch
git checkout main
git pull
git branch -d feature/my-feature
```

---

## 🚀 First Day Workflow

### Morning: Setup (30 min)

1. [ ] Create GitHub Project board
2. [ ] Create first batch of issues (10)
3. [ ] Setup Codespaces
4. [ ] Test a workflow run

### Midday: Configure Team (20 min)

1. [ ] Invite first team members
2. [ ] Set branch protection rules
3. [ ] Create team roles
4. [ ] Setup wiki

### Afternoon: Start Development (30 min)

1. [ ] Create first feature branch
2. [ ] Make sample change
3. [ ] Submit first PR
4. [ ] Test CI/CD validation
5. [ ] Merge PR

### End of Day: Verify

1. [ ] All systems working
2. [ ] Team can access everything
3. [ ] Workflows running
4. [ ] Documentation in place

---

## 📚 Reference Links

### Project Management

- **Project Board**: https://github.com/M0nado/helios-platform/projects
- **Issues**: https://github.com/M0nado/helios-platform/issues
- **Pull Requests**: https://github.com/M0nado/helios-platform/pulls
- **Milestones**: https://github.com/M0nado/helios-platform/milestones

### Development

- **Code**: https://github.com/M0nado/helios-platform
- **Actions**: https://github.com/M0nado/helios-platform/actions
- **Codespaces**: https://github.com/codespaces
- **Wiki**: https://github.com/M0nado/helios-platform/wiki

### Configuration

- **Settings**: https://github.com/M0nado/helios-platform/settings
- **Branches**: https://github.com/M0nado/helios-platform/settings/branches
- **Secrets**: https://github.com/M0nado/helios-platform/settings/secrets/actions
- **Access**: https://github.com/M0nado/helios-platform/settings/access

### Community

- **Discussions**: https://github.com/M0nado/helios-platform/discussions
- **Insights**: https://github.com/M0nado/helios-platform/insights
- **Pulse**: https://github.com/M0nado/helios-platform/pulse

---

## ✅ Everything is Ready!

GitHub infrastructure is fully set up:

- ✅ Project board configured
- ✅ Actions workflows deployed
- ✅ Codespaces ready
- ✅ Documentation synced
- ✅ Team structure ready

**Next step: Start using it!**

1. Create first issue
2. Launch Codespaces
3. Make your first PR
4. See CI/CD in action

🚀 **Welcome to GitHub-first development!**
