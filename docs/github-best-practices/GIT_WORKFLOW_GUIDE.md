# Git Workflow Guide for HELIOS Platform

Step-by-step workflows for common development scenarios, troubleshooting, and advanced techniques.

---

## Table of Contents

1. [Initial Setup](#initial-setup)
2. [Feature Development Workflow](#feature-development-workflow)
3. [Code Review and Merge](#code-review-and-merge)
4. [Common Scenarios](#common-scenarios)
5. [Troubleshooting](#troubleshooting)
6. [Advanced Techniques](#advanced-techniques)

---

## Initial Setup

### One-Time Repository Setup

```bash
# Clone the repository
git clone https://github.com/COMPANY/helios-platform.git
cd helios-platform

# Configure git identity (if not already set globally)
git config user.name "Your Name"
git config user.email "your.email@company.com"

# Add upstream remote (if working with fork)
git remote add upstream https://github.com/COMPANY/helios-platform.git

# Verify remotes
git remote -v
# output:
# origin    https://github.com/YOUR-FORK/helios-platform.git (fetch)
# origin    https://github.com/YOUR-FORK/helios-platform.git (push)
# upstream  https://github.com/COMPANY/helios-platform.git (fetch)
# upstream  https://github.com/COMPANY/helios-platform.git (push)

# Install pre-commit hooks (if available)
npm install husky --save-dev
npx husky install
```

### Development Environment Setup

```bash
# Install dependencies
npm install

# Install development dependencies
npm install --save-dev

# Create local environment file
cp .env.template .env

# Run tests to verify setup
npm test

# Verify all systems working
npm run build
```

---

## Feature Development Workflow

### Step 1: Create Feature Branch

```bash
# Ensure you're on develop and up-to-date
git checkout develop
git fetch origin
git pull origin develop

# Create feature branch (always from develop)
git checkout -b feature/HELIOS-42-user-authentication

# Verify branch creation
git branch -v
git status
```

### Step 2: Make Changes

```bash
# Work on feature
# ... make changes to files ...

# Check what changed
git status

# Review changes before staging
git diff
git diff src/auth/LoginService.ts

# Stage changes (ideally in logical chunks)
git add src/auth/LoginService.ts
git add src/auth/TokenValidator.ts
git add tests/auth/LoginService.test.ts

# Review staged changes
git diff --cached

# If you added too much, unstage specific files
git reset HEAD src/utils/UnrelatedFile.ts

# Final check before committing
git status
```

### Step 3: Commit Changes

```bash
# Commit with descriptive message
git commit -m "feat(auth): implement JWT token validation

Implement JWT token validation for all API endpoints.
Validates token signature and expiration time.

- Added validateToken() method to AuthService
- Added TokenExpiredError exception
- Added unit tests with 95% coverage
- Updated API middleware to use validator

Fixes #234"

# View your commit
git log -1

# If commit message wasn't perfect, amend (ONLY before pushing)
git commit --amend
```

### Step 4: Push to Remote

```bash
# Push to remote (creates upstream tracking)
git push -u origin feature/HELIOS-42-user-authentication

# Future pushes on this branch
git push

# Verify on GitHub
# Your branch should now be visible on GitHub
```

### Step 5: Create Pull Request

**On GitHub:**

1. Navigate to the repository
2. Click "Compare & pull request" banner (if visible)
3. Or click "Pull requests" → "New pull request"
4. Ensure:
   - Base: `develop`
   - Compare: `feature/HELIOS-42-user-authentication`
5. Fill in PR template completely
6. Link related issues with `Fixes #234` or `Relates to #456`
7. Request reviewers (at least 2)
8. Click "Create pull request"

### Step 6: Address Review Feedback

```bash
# Review has requested changes
git log --oneline -5

# Make changes locally
# ... edit files to address feedback ...

# Stage and commit changes
git add src/auth/LoginService.ts
git commit -m "fix(auth): handle edge cases in token validation

Address review feedback on error handling for expired tokens.
- Add retry logic for transient failures
- Improve error messages for debugging

As suggested in PR #890"

# Push updated changes
git push origin feature/HELIOS-42-user-authentication

# On GitHub: Comment on PR that changes are ready
# Then request re-review
```

### Step 7: Merge and Cleanup

```bash
# After PR is approved and merged on GitHub

# Switch back to develop
git checkout develop

# Pull latest from remote (includes your merged feature)
git fetch origin
git pull origin develop

# Delete local feature branch
git branch -d feature/HELIOS-42-user-authentication

# Delete remote feature branch (if not auto-deleted)
git push origin --delete feature/HELIOS-42-user-authentication

# Verify branch deleted
git branch -a | grep HELIOS-42

# View your contribution in main branch
git log --oneline -10
```

---

## Code Review and Merge

### For Code Reviewers

```bash
# Get the feature branch locally to test
git fetch origin

# Create local tracking branch
git checkout feature/HELIOS-42-user-authentication

# Review changes
git log develop..HEAD --oneline
git diff develop...HEAD

# Run tests locally
npm test
npm run build

# Check for issues
npm run lint

# Go back to develop when done
git checkout develop
```

### Handling Review Feedback as Author

```bash
# Feedback says: "Handle null case here"
# Make the fix
# ... edit file ...

# Commit the fix
git add src/auth/TokenValidator.ts
git commit -m "fix(auth): add null check for token header

Add defensive null check when extracting token from request header
as suggested in PR review."

# Push the fix
git push origin feature/HELIOS-42-user-authentication

# On GitHub: Go to PR, click "Resolve conversation" after pushing
# Then request re-review from reviewers
```

---

## Common Scenarios

### Scenario 1: Keep Feature Branch Up-to-Date

```bash
# Your feature branch is 5 commits behind develop

# Option A: Rebase (Linear history)
git checkout feature/HELIOS-42-user-authentication
git fetch origin
git rebase origin/develop

# Option B: Merge (Preserve history)
git checkout feature/HELIOS-42-user-authentication
git fetch origin
git merge origin/develop

# If conflicts occur, resolve them
# Then continue
git rebase --continue  # for rebase
# or
git commit -m "Merge develop into feature"  # for merge

# Push updated branch
git push origin feature/HELIOS-42-user-authentication --force-with-lease
```

### Scenario 2: Work on Multiple Features

```bash
# Switch between features easily
git checkout feature/HELIOS-42-user-authentication
git checkout feature/HELIOS-89-dashboard-charts

# See all your branches
git branch -v

# Delete old branch before starting new one
git branch -d feature/HELIOS-40-old-feature
```

### Scenario 3: Fix a Hotfix on Production

```bash
# Create hotfix from main
git fetch origin
git checkout main
git pull origin main

git checkout -b hotfix/HELIOS-999-security-patch

# Make critical fix
# ... edit files ...

git add src/auth/SecurityFix.ts
git commit -m "fix: patch security vulnerability in JWT validation

Critical fix for token validation bypass.
Affects all installations with JWT enabled."

# Push hotfix
git push -u origin hotfix/HELIOS-999-security-patch

# Create PR to main (expedited review)
# After merge to main, also merge to develop
git checkout develop
git pull origin develop
git merge hotfix/HELIOS-999-security-patch
git push origin develop
```

### Scenario 4: Undo Recent Commits

```bash
# Undo last commit (keep changes)
git reset --soft HEAD~1

# Undo last 2 commits (keep changes)
git reset --soft HEAD~2

# Undo last commit (discard changes)
git reset --hard HEAD~1

# Undo on remote (after push)
# ONLY if no one else has pulled
git push origin --force-with-lease

# If already shared, revert instead
git revert HEAD
git push origin feature/branch
```

### Scenario 5: Cherry-pick Commit

```bash
# Copy specific commit to your branch
git log origin/develop --oneline | head -20

# Find commit hash you want
# e.g., abc123def

git checkout feature/your-feature
git cherry-pick abc123def

# If conflicts, resolve and continue
git add .
git cherry-pick --continue

git push origin feature/your-feature
```

### Scenario 6: Stash Work in Progress

```bash
# Need to switch branches but have uncommitted changes
git stash

# Make other changes, come back to feature
git checkout feature/other-work
git checkout feature/HELIOS-42-user-authentication

# Restore stashed changes
git stash pop

# Or keep stash and apply later
git stash apply
```

---

## Troubleshooting

### Issue: Merge Conflicts

**Symptom:** Git says "Conflict" when pulling or merging

```bash
# View conflicting files
git status

# Look at conflicts in file
cat src/auth/LoginService.ts
# Shows both versions: <<<<<<, ======, >>>>>>

# Resolution options:

# Option 1: Manual merge
# Edit file, keep correct version
git add src/auth/LoginService.ts
git commit -m "Merge branch changes"

# Option 2: Abort merge
git merge --abort

# Option 3: Accept ours (current branch)
git checkout --ours src/auth/LoginService.ts
git add src/auth/LoginService.ts

# Option 4: Accept theirs (incoming)
git checkout --theirs src/auth/LoginService.ts
git add src/auth/LoginService.ts

# For rebase
git rebase --continue
```

### Issue: Accidentally Pushed to Main

**Symptom:** You pushed to main instead of feature branch

```bash
# DO NOT PANIC - it's fixable

# Check what you pushed
git log main -5

# If not merged yet, revert
git revert HEAD
git push origin main

# If only you pushed, reset (with caution)
git reset --hard HEAD~1
git push origin main --force-with-lease

# BETTER: Ask a teammate with main access to help revert
```

### Issue: Lost Commits

**Symptom:** Commits disappeared after reset/rebase

```bash
# Don't panic - Git usually keeps them
git reflog

# Shows something like:
# abc123 HEAD@{0}: reset: moving to HEAD~1
# def456 HEAD@{1}: commit: my lost commit

# Recover lost commits
git reset --hard def456

# Or in specific branch
git log --reflog
```

### Issue: Detached HEAD State

**Symptom:** Git says "detached HEAD" and you can't push

```bash
# This happens when you checkout a specific commit
git status

# Fix: Create a branch from current state
git checkout -b feature/save-my-work

# Or go back to a branch
git checkout develop
```

### Issue: Branch Won't Delete

**Symptom:** Can't delete branch locally or remotely

```bash
# Local branch force delete (loses work!)
git branch -D feature/HELIOS-42-user-authentication

# Remote branch force delete
git push origin --delete feature/HELIOS-42-user-authentication --force

# If GitHub web UI has it, use web interface

# BETTER: Check why branch won't delete first
git branch -vv
git branch --merged  # shows merged branches
git branch --no-merged  # shows unmerged branches
```

### Issue: Slow Clone/Pull

**Symptom:** Clone or pull taking forever

```bash
# Shallow clone (faster, only recent history)
git clone --depth 1 https://github.com/COMPANY/helios-platform.git

# Deepen later if needed
git fetch --unshallow

# For existing repo, shallow fetch
git fetch --depth 1 origin

# Show clone progress with verbose
git clone --verbose https://github.com/COMPANY/helios-platform.git
```

---

## Advanced Techniques

### Interactive Rebase

```bash
# Clean up commits before PR
git rebase -i develop

# Shows editor with last N commits
# Options:
#   pick - use commit
#   reword - change commit message
#   squash - combine with previous commit
#   drop - discard commit

# Edit lines:
# pick abc123 feat: add auth
# squash def456 fix: auth typo
# reword ghi789 docs: update readme

# Save and close editor
# Edit commit message if reword selected

git push origin feature/branch --force-with-lease
```

### Create Patch File

```bash
# Export changes as patch
git format-patch develop

# Creates 0001-*.patch files

# Apply patch elsewhere
git apply 0001-*.patch
# or
git am 0001-*.patch  # with commit history
```

### Bisect to Find Bug

```bash
# Find which commit introduced bug
git bisect start
git bisect bad HEAD  # current is bad
git bisect good v1.2.0  # version 1.2.0 was good

# Git checks out middle commit
# Test it
npm test

# Mark as good or bad
git bisect good  # or git bisect bad
# Repeat until found

# Show result
git bisect log

# Clean up
git bisect reset
```

### View Change History

```bash
# See all versions of file
git log --oneline -- src/auth/LoginService.ts

# See who changed each line
git blame src/auth/LoginService.ts

# See what changed at specific time
git log --until="2 weeks ago" --oneline

# See all commits in PR
git log main..feature/HELIOS-42-user-authentication

# Visual graph
git log --graph --oneline --all
```

### Revert Merge

```bash
# Undo a merge (if it was merged to main already)
git revert -m 1 <merge-commit-hash>
git push origin main

# This creates new commit that undoes the merge
# Better than force-push for public branches
```

---

## Best Practices Checklist

### Before Pushing

```markdown
□ All tests pass locally: npm test
□ Code builds without errors: npm run build
□ No console errors or warnings
□ Commit message is clear and follows format
□ Branch name is descriptive
□ No debug code or console.log left
□ No uncommitted changes remain
```

### Before Creating PR

```markdown
□ Branch is up-to-date: git rebase origin/develop
□ PR title is clear and follows format
□ PR description explains why, not what (what is in code)
□ Related issues are linked
□ Tests are included for new code
□ Documentation is updated
□ No merge conflicts
□ Status checks pass (CI/CD)
```

### During Code Review

```markdown
□ Respond to feedback within 12 hours
□ Ask for clarification if feedback unclear
□ Update code or comment on disagreements
□ Don't make breaking changes after approval
□ Rebase if conflicts appear
□ Request re-review after changes
```

### After Merge

```markdown
□ Verify changes in develop/main
□ Delete local and remote feature branch
□ Update any related documentation
□ Close any related GitHub issues
□ Monitor deployment for issues
□ Inform team of changes
```

---

## Quick Reference Commands

```bash
# Daily commands
git status                    # Check status
git pull origin develop       # Get latest
git checkout -b feature/name  # Create branch
git add file.ts               # Stage changes
git commit -m "message"       # Commit
git push origin feature/name  # Push

# Viewing changes
git diff                      # Unstaged changes
git diff --cached             # Staged changes
git log --oneline -10         # Recent commits
git show abc123               # View commit

# Fixing mistakes
git reset --soft HEAD~1       # Undo commit, keep changes
git reset --hard HEAD~1       # Undo commit, lose changes
git revert HEAD               # Create undo commit
git stash                     # Save work temporarily

# Branch management
git branch -v                 # List branches
git branch -d feature/name    # Delete branch
git checkout feature/name     # Switch branch
git fetch origin              # Get latest from remote

# Syncing with upstream
git fetch upstream            # Get upstream changes
git rebase upstream/develop   # Sync develop branch
```

---

## Getting Help

```bash
# Built-in Git help
git help <command>
git help commit
git help merge

# Interactive help
git config --global help.autocorrect 1

# Common issues channel
#general-support on team Slack
```

---

**Last Updated:** April 2026  
**Version:** 1.0

See also: [GITHUB_BEST_PRACTICES.md](GITHUB_BEST_PRACTICES.md), [TROUBLESHOOTING](../../TROUBLESHOOTING.md)
