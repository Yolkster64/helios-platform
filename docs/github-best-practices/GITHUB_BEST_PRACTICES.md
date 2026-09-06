# GitHub Best Practices for HELIOS Platform

Complete guide to GitHub workflows, collaboration standards, and repository management for the HELIOS Platform project.

**Table of Contents:**

- [Repository Organization](#repository-organization)
- [Branch Strategy](#branch-strategy)
- [Commit Message Conventions](#commit-message-conventions)
- [Pull Request Review Process](#pull-request-review-process)
- [Release Strategy](#release-strategy)
- [Documentation Standards](#documentation-standards)
- [Security Practices](#security-practices)

---

## Repository Organization

### Directory Structure

```
helios-platform/
├── src/                      # Source code
│   ├── core/                 # Core platform functionality
│   ├── components/           # Reusable components
│   ├── services/             # Service layer
│   └── utils/                # Utility functions
├── tests/                    # Test suites
├── docs/                     # Documentation
│   ├── guides/               # How-to guides
│   ├── api/                  # API documentation
│   └── github-best-practices/# This directory
├── scripts/                  # Build and deployment scripts
├── .github/                  # GitHub-specific files
│   ├── workflows/            # CI/CD workflows
│   ├── ISSUE_TEMPLATE/       # Issue templates
│   └── pull_request_template.md
├── .devcontainer/            # Development container config
└── README.md                 # Project overview
```

### Directory Ownership

| Directory | Owner | Responsibility |
|-----------|-------|-----------------|
| `src/core` | Core Team | Platform core functionality |
| `src/components` | Component Team | Reusable UI/Logic components |
| `tests` | QA Team | Test coverage and automation |
| `docs` | Documentation Team | All documentation |
| `scripts` | DevOps Team | Build and deployment |

### File Organization Rules

1. **Keep files focused**: One primary responsibility per file
2. **Use clear names**: `UserAuthService.ts` not `Service.ts`
3. **Organize by feature**: Group related files in subdirectories
4. **Shared code goes to utils**: Extract utilities to `utils/` directory
5. **Tests mirror structure**: `src/foo/Bar.ts` → `tests/foo/Bar.test.ts`

### Repository Settings

**Enforce in GitHub Repository Settings:**

```
✓ Require pull request reviews before merging (at least 2)
✓ Require status checks to pass
✓ Require branches to be up to date before merging
✓ Include administrators in restrictions
✓ Allow auto-merge (squash only)
✓ Delete head branch on merge (enabled)
✓ Require commit message format checks
✓ Require CODEOWNERS review (for critical files)
```

---

## Branch Strategy

### Branch Types

#### Main (Production)

- **Purpose**: Live, production-ready code
- **Protection**: Requires 2 approvals + all checks passing
- **Tag**: Automatic semantic version tags
- **Deploy**: Automatic to production on merge
- **Access**: Core team only can merge
- **Frequency**: 1-2 releases per week

```bash
# Main branch is ALWAYS production-ready
# Example protection rules:
#   - No direct pushes
#   - Require PR with 2+ approvals
#   - All status checks must pass
#   - Require up-to-date branches
#   - Require conversation resolution
```

#### Develop (Integration)

- **Purpose**: Integration branch for next release
- **Protection**: Requires 1 approval + checks passing
- **Branch from**: Feature branches
- **Merge back to**: Feature branches for updates
- **Release cycle**: Weekly to main

```bash
# Develop branch is release-candidate
# Example protection rules:
#   - Require PR (1 approval minimum)
#   - All checks must pass
#   - Enable auto-deletion
```

#### Feature Branches

- **Naming**: `feature/JIRA-123-brief-description`
- **Branch from**: `develop`
- **Merge back to**: `develop` via PR
- **Lifetime**: Until feature complete
- **Cleanup**: Delete after merge

**Feature Branch Naming Examples:**

```
feature/HELIOS-42-user-authentication
feature/HELIOS-89-dashboard-charts
feature/HELIOS-156-api-optimization
feature/HELIOS-203-security-audit
```

#### Bugfix Branches

- **Naming**: `bugfix/JIRA-123-brief-description`
- **Branch from**: `develop` or `main` (if critical)
- **Protection**: Same as feature branches
- **Priority**: High - review within 24 hours

#### Hotfix Branches

- **Naming**: `hotfix/JIRA-123-brief-description`
- **Branch from**: `main` only
- **Merge to**: Both `main` and `develop`
- **Review**: Expedited (within 4 hours)
- **Deploy**: Immediate to production

**Hotfix Example:**

```bash
# Critical production bug found
git checkout main
git pull origin main
git checkout -b hotfix/HELIOS-999-security-patch

# Fix the bug
git commit -m "fix: patch security vulnerability in auth module"
git push origin hotfix/HELIOS-999-security-patch

# Create PR to BOTH main and develop
# Main PR: 2 approvals required (express review)
# Develop PR: For sync, 1 approval
```

### Creating Feature Branches

```bash
# 1. Ensure you're on develop and up-to-date
git checkout develop
git pull origin develop

# 2. Create feature branch from develop
git checkout -b feature/HELIOS-42-new-feature

# 3. Push to remote (creates upstream)
git push -u origin feature/HELIOS-42-new-feature

# 4. Create PR in GitHub (don't merge to main directly)
```

### Branch Protection Rules Checklist

```markdown
□ Require pull request reviews (min 2 for main, 1 for develop)
□ Require status checks to pass:
  - CI/CD Pipeline
  - Code Coverage
  - Security Scanning
  - Lint Checks
□ Require branches to be up-to-date before merging
□ Include administrators in restrictions
□ Allow auto-merge (squash commits only)
□ Auto-delete head branch on merge
□ Allow force pushes to: No one
□ Allow deletions: No
```

---

## Commit Message Conventions

### Format

Follow **Conventional Commits** specification:

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Types

| Type | Use Case | Example |
|------|----------|---------|
| **feat** | New feature | `feat(auth): add JWT token validation` |
| **fix** | Bug fix | `fix(dashboard): resolve chart rendering issue` |
| **docs** | Documentation | `docs(readme): update installation steps` |
| **style** | Code style (no logic change) | `style(components): reformat button styles` |
| **refactor** | Refactoring (no feature change) | `refactor(api): extract service layer` |
| **perf** | Performance improvement | `perf(search): optimize database query` |
| **test** | Test additions/changes | `test(auth): add token validation tests` |
| **ci** | CI/CD changes | `ci(workflows): add performance benchmark` |
| **chore** | Maintenance (dependencies, etc) | `chore(deps): upgrade React to 18.2.0` |
| **revert** | Revert previous commit | `revert: undo auth changes from PR #123` |

### Scope

Specify what part of the codebase is affected:

- `auth` - Authentication module
- `dashboard` - Dashboard feature
- `api` - API services
- `components` - UI components
- `database` - Database layer
- `config` - Configuration
- `ci` - CI/CD pipeline

### Subject Line Rules

```
✓ Use imperative mood ("add" not "added" or "adds")
✓ Don't capitalize first letter
✓ No period (.) at the end
✓ Keep under 50 characters
✓ Reference issue number if applicable: "close #123"
```

### Body

Use for detailed explanation:

- What changed and why
- Reference related issues: `Fixes #123`, `Relates to #456`
- Mention breaking changes: `BREAKING CHANGE: ...`
- Not needed for trivial commits

**Example:**

```
refactor(api): extract authentication service

Move authentication logic into separate service for better testability
and reusability. Reduces coupling between API routes and auth logic.

- Created AuthService class
- Updated route handlers to use service
- Added unit tests for service
- Maintains backward compatibility

Fixes #234
Related to #567
```

### Commit Message Examples

#### ✓ Good Commits

```
feat(auth): add two-factor authentication support
fix(dashboard): resolve widget overlap on mobile view
docs(api): add webhook endpoint documentation
test(components): add Button component snapshot tests
refactor(database): extract connection pooling logic
perf(search): add caching to reduce query time by 60%
ci(workflows): add automated security scanning
chore(deps): upgrade TypeScript to 4.9.0
```

#### ✗ Bad Commits

```
updates
fixed stuff
work in progress
asdfasdf
WIP: random changes
Updated multiple files
Fixed issues and stuff
Applied changes
```

### Commit Best Practices

```markdown
## Single Responsibility
□ One commit = one logical change
□ Don't mix refactoring with feature work
□ Don't mix formatting with functional changes

## Frequency
□ Commit every 30-60 minutes of work
□ Don't wait until end of day to commit
□ Allows for better history and easier debugging

## Atomic Commits
□ Each commit should be independently useful
□ Should be able to revert one commit without breaking others
□ Makes bisecting bugs easier

## Testing Before Commit
□ All tests pass locally before committing
□ Code runs without errors
□ No console errors or warnings
```

### Commit Workflow

```bash
# Check status
git status

# Stage changes (atomic - related changes only)
git add src/auth/LoginService.ts
git add tests/auth/LoginService.test.ts

# Review staged changes
git diff --cached

# Commit with message
git commit -m "feat(auth): implement JWT token validation

Add JWT token validation to auth service. Validates
signature and expiration time on every request.

- Added validateToken() method
- Added token expiration check
- Added unit tests with 95% coverage

Fixes #234"

# Push to remote
git push origin feature/HELIOS-42-auth-improvements
```

---

## Pull Request Review Process

### PR Purpose

PRs serve to:

1. **Share knowledge**: Distribute code understanding across team
2. **Catch issues**: Identify bugs before production
3. **Maintain standards**: Enforce code quality and style
4. **Create documentation**: PR discussion documents decisions

### Review Timeline

| Stage | Timeline | Responsibility |
|-------|----------|-----------------|
| Initial Review | < 24 hours | Assigned reviewer |
| Author Response | < 12 hours | PR author |
| Final Review | < 24 hours | Reviewer |
| Merge | After approval | Core team |

### Reviewer Responsibilities

**When You're Assigned to Review:**

1. **Within 2 hours**: Acknowledge the review request
2. **Within 24 hours**: Provide initial feedback
3. **Request changes** if issues found
4. **Approve** only when satisfied

**What to Look For:**

- ✓ Code quality and style
- ✓ Test coverage (aim for 80%+)
- ✓ Documentation is updated
- ✓ No security vulnerabilities
- ✓ Performance implications
- ✓ Breaking changes properly documented

### Author Responsibilities

**When You Create a PR:**

1. Fill in PR description template completely
2. Link related issues
3. Ensure all checks pass
4. Respond to comments within 12 hours
5. Request re-review after changes

**Responding to Feedback:**

```markdown
✓ Address feedback promptly
✓ Push new commits (don't force-push)
✓ Comment on each suggestion with status:
  - "Done in commit abc123"
  - "Disagree because..."
  - "Updated as requested"
✓ Request re-review when ready
✓ Don't dismiss feedback without discussion
```

### Review Approval Tiers

| Tier | Approval Type | Requirements |
|------|---------------|--------------|
| **Standard PR** | 1 reviewer | Any reviewer approval |
| **Critical Path** | 2 reviewers | At least 1 core team member |
| **Security Changes** | 2 reviewers | Security team + 1 other |
| **API Changes** | 2 reviewers | API architect + 1 other |
| **Hotfix** | 1 reviewer | Any core team member (expedited) |

### Auto-Merge Policy

**Enabled Only When:**

- All status checks pass
- Required approvals obtained
- Branch is up-to-date with main
- Squash commits enabled
- Only for dependency updates and docs

**Disabled For:**

- Feature PRs (require human verification before merge)
- Security changes
- Breaking API changes

---

## Release Strategy

### Version Numbering (Semantic Versioning)

Format: `MAJOR.MINOR.PATCH`

```
1.2.3
│ │ └─ PATCH: Bug fixes, non-breaking changes (1.2.3 → 1.2.4)
│ └─── MINOR: New features, backward compatible (1.2.0 → 1.3.0)
└───── MAJOR: Breaking changes (1.0.0 → 2.0.0)
```

### Release Schedule

```
Sprint Plan:
├─ Monday-Thursday: Feature development
├─ Friday: Release/QA
└─ Weekend: Monitoring

Cadence:
├─ Patch releases: As needed (hotfixes)
├─ Minor releases: Biweekly (every other Friday)
└─ Major releases: Quarterly (planned)
```

### Release Checklist

Before releasing:

```markdown
□ All tests passing
□ Security scanning complete
□ Performance benchmarks acceptable
□ Documentation updated
□ CHANGELOG.md updated
□ Version number bumped
□ Release notes written
□ Staging deployment tested
□ Monitoring alerts configured
□ Team notification ready
```

### Release Process

```bash
# 1. Create release branch from develop
git checkout develop
git pull origin develop
git checkout -b release/1.3.0

# 2. Update version numbers and CHANGELOG
# Update package.json, version files, etc.
# Update CHANGELOG.md with new features

# 3. Commit version bump
git add package.json CHANGELOG.md
git commit -m "chore(release): bump version to 1.3.0"
git push origin release/1.3.0

# 4. Create PR to main (2 approvals required)
# 5. After merge, GitHub Actions creates tag and releases

# 6. Create PR from main back to develop
git checkout develop
git pull origin main
git commit -m "chore(release): sync develop with main"
git push origin develop
```

---

## Documentation Standards

### What to Document

```markdown
✓ README.md - Project overview, setup
✓ CONTRIBUTING.md - How to contribute
✓ API documentation - Endpoints, parameters, examples
✓ Architecture docs - System design, diagrams
✓ Setup guides - Installation, configuration
✓ Troubleshooting guide - Common issues and fixes
✓ Code comments - Complex logic only (not obvious code)
✓ Commit messages - Why changes were made
✓ PR descriptions - What changed and why
✓ Release notes - What's new in each version
```

### Documentation Location

| Type | Location | Format |
|------|----------|--------|
| Project Overview | `/README.md` | Markdown |
| Contributing Guide | `/CONTRIBUTING.md` | Markdown |
| API Docs | `/docs/API.md` | Markdown + OpenAPI |
| Architecture | `/docs/ARCHITECTURE.md` | Markdown + diagrams |
| Setup Guides | `/docs/guides/` | Markdown |
| Troubleshooting | `/docs/TROUBLESHOOTING.md` | Markdown |

### Quality Guidelines

```markdown
✓ Keep documentation updated with code
✓ Include examples for complex features
✓ Use clear language, avoid jargon
✓ Link to related documentation
✓ Include troubleshooting section
✓ Version documentation with releases
✓ Review docs as part of PR process
```

---

## Security Practices

### Secret Management

**NEVER commit secrets. Period.**

```markdown
✓ Use .env files for local development
✓ Add .env to .gitignore
✓ Use GitHub Secrets for CI/CD
✓ Store credentials in secure vault
✓ Rotate secrets regularly
✓ Audit secret access logs
✗ Don't commit API keys
✗ Don't commit passwords
✗ Don't commit database credentials
```

### Sensitive Data Handling

```bash
# .gitignore must contain:
.env
.env.local
.env.*.local
*.key
*.pem
secrets/
private/
credentials.json
```

### Code Scanning

```markdown
✓ GitHub CodeQL enabled
✓ Dependency scanning enabled
✓ Security vulnerability alerts enabled
✓ Secret scanning enabled
✓ Branch protection requires passing checks
✓ Address alerts within 24 hours
✓ Document any accepted risks
```

### Access Control

**Repository Access Levels:**

| Role | Access | Responsibilities |
|------|--------|------------------|
| Owner | Full | Repo management, settings |
| Maintainer | Full | Merge PRs, manage releases |
| Developer | Write | Create PRs, push branches |
| Contributor | Read | Clone, submit PRs |

### Security Review Checklist

```markdown
□ No hardcoded credentials
□ Input validation on all endpoints
□ SQL injection prevention (parameterized queries)
□ XSS prevention (output escaping)
□ CSRF protection enabled
□ Rate limiting implemented
□ Authentication enforced
□ Authorization checks in place
□ Sensitive data encrypted
□ Error handling doesn't leak info
```

---

## Quick Reference

### Common Git Commands

```bash
# Fetch latest from remote
git fetch origin

# Pull latest changes
git pull origin develop

# Check status
git status

# View commits
git log --oneline -10

# View changes
git diff

# Stage changes
git add file.ts

# Commit changes
git commit -m "type(scope): message"

# Push to remote
git push origin branch-name

# Create branch
git checkout -b feature/new-feature

# Delete local branch
git branch -d feature/old-feature

# Delete remote branch
git push origin --delete feature/old-feature
```

---

## Escalation Path

**For questions about:**

- Code review standards → #code-review channel
- Branch strategy → @core-team on Slack
- Release process → @release-manager
- Security concerns → @security-team (private)
- Documentation standards → #documentation channel

---

**Last Updated:** April 2026  
**Version:** 1.0  
**Maintainer:** Core Platform Team

See also: [GIT_WORKFLOW_GUIDE.md](GIT_WORKFLOW_GUIDE.md), [PULL_REQUEST_GUIDE.md](PULL_REQUEST_GUIDE.md), [CODE_REVIEW_STANDARDS.md](CODE_REVIEW_STANDARDS.md)
