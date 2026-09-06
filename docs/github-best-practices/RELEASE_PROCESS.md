# Release Process for HELIOS Platform

Complete guide to versioning, releasing, and announcing new versions.

---

## Table of Contents

1. [Version Numbering](#version-numbering)
2. [Release Checklist](#release-checklist)
3. [Changelog Management](#changelog-management)
4. [Tag Strategy](#tag-strategy)
5. [GitHub Releases](#github-releases)
6. [Announcement Process](#announcement-process)
7. [Post-Release Verification](#post-release-verification)

---

## Version Numbering

### Semantic Versioning (SemVer)

Format: `MAJOR.MINOR.PATCH`

```
1.2.3
│ │ └─ PATCH (0.0.x): Bug fixes, no new features
│ └─── MINOR (0.x.0): New features, backward compatible
└───── MAJOR (x.0.0): Breaking changes
```

### Version Examples

```
0.1.0 → 0.2.0  # Minor: New features added
0.2.0 → 0.2.1  # Patch: Bug fix
0.2.1 → 1.0.0  # Major: Breaking changes
1.0.0 → 1.1.0  # Minor: New features
1.1.0 → 1.1.1  # Patch: Bug fix
```

### When to Increment

**PATCH Release (x.x.+1):**

- Bug fixes
- Security patches
- Documentation fixes
- No new features
- Backward compatible

**MINOR Release (x.+1.0):**

- New features
- Non-breaking enhancements
- API additions (backward compatible)
- Backward compatible

**MAJOR Release (+1.0.0):**

- Breaking API changes
- Major feature overhauls
- Incompatible changes
- Migration required

### Pre-Release Versions

```
1.0.0-alpha.1   # Alpha (unstable)
1.0.0-beta.1    # Beta (testing)
1.0.0-rc.1      # Release Candidate
1.0.0           # Final release
```

---

## Release Checklist

### Pre-Release (1 week before)

```markdown
□ Create release branch: git checkout -b release/1.3.0
□ Update version in package.json
□ Update version in version file (if separate)
□ Run full test suite: npm test
□ Run security audit: npm audit
□ Build for production: npm run build
□ Test on staging environment
□ Performance benchmarks acceptable
□ All dependencies up-to-date
□ Security scanning complete (CodeQL, SAST)
```

### Release Day (Friday)

```markdown
□ Final testing on staging
□ Create PR for release branch to main
□ Get 2 approvals on release PR
□ Update CHANGELOG.md
□ Update documentation if needed
□ Prepare release notes
□ Create deployment plan
□ Notify team (Slack announcement)
```

### Merge to Main

```markdown
□ Ensure branch is up-to-date
□ All status checks passing
□ All approvals obtained
□ Create tag: git tag -a v1.3.0
□ Merge PR to main
□ Push tag: git push origin v1.3.0
□ Tag triggers GitHub Actions
□ Verify build in CI/CD
```

### Post-Release (Merge to Develop)

```markdown
□ Create PR from main back to develop
□ Comment: "Sync develop with released v1.3.0"
□ Get approval
□ Merge PR
□ Verify develop has latest changes
```

### Monitoring & Support (First 24 hours)

```markdown
□ Monitor error logs
□ Monitor performance metrics
□ Check user reports
□ Be ready to hotfix if needed
□ Keep team informed
□ Document any issues
□ Verify no regressions
```

---

## Changelog Management

### Format

Create/Update `CHANGELOG.md`:

```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- New feature descriptions

### Changed
- Modified feature descriptions

### Fixed
- Bug fix descriptions

### Removed
- Removed feature descriptions

### Deprecated
- Deprecated feature descriptions

### Security
- Security fix descriptions

## [1.2.0] - 2026-04-01

### Added
- JWT token validation for all API endpoints
- Webhook support for events
- Database connection pooling

### Changed
- Updated authentication middleware
- Refactored database layer

### Fixed
- Fixed dashboard widget overlap on mobile
- Fixed memory leak in WebSocket handler

### Deprecated
- Legacy authentication endpoint (use OAuth2 instead)

### Security
- Fixed SQL injection vulnerability in search
- Added rate limiting to API endpoints

## [1.1.0] - 2026-03-15

### Added
- New API endpoints for reporting
- User dashboard redesign

### Fixed
- Fixed API timeout issues
- Fixed incorrect filtering in search

## [1.0.0] - 2026-03-01

### Added
- Initial release
- Core platform features
- Basic API
- Authentication system

[Unreleased]: https://github.com/your-org/your-repo/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/your-org/your-repo/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/your-org/your-repo/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/your-org/your-repo/releases/tag/v1.0.0
```

### Changelog Entry Guidelines

```markdown
✓ Group changes by type (Added, Changed, Fixed, etc.)
✓ Start with action verb: "Added", "Fixed", "Updated"
✓ Be specific and descriptive
✓ Include issue/PR numbers: "Fixes #234, PR #567"
✓ Mention breaking changes prominently
✓ Include migration steps if breaking

✗ Don't be vague: "Fixed stuff"
✗ Don't mix multiple changes: "Added feature and fixed bug"
✗ Don't forget breaking changes
✗ Don't omit migration steps
```

---

## Tag Strategy

### Creating Tags

```bash
# Annotated tag (recommended)
git tag -a v1.3.0 -m "Release version 1.3.0

New features:
- JWT token validation
- Webhook support

Bug fixes:
- Mobile widget overlap
- WebSocket memory leak

Breaking changes:
- Legacy API endpoint deprecated"

# Push tag to remote
git push origin v1.3.0

# Create tag from current commit
git tag v1.3.0
git push origin v1.3.0

# Verify tag
git show v1.3.0
```

### Tag Naming

```
v1.2.3          # Standard semantic version
v1.2.3-beta     # Pre-release version
v1.2.3-rc.1     # Release candidate

NOT:
1.2.3           # Missing 'v' prefix
release-1.2.3   # Wrong format
v1.2.3.4        # Too many numbers
```

### Tag Protection

Configure in GitHub repository settings:

```markdown
Manage access → Tags
✓ Create new tag rule
  - Pattern: v*
  - Required status checks: All passing
  - Require admin review: Yes
  - Include administrators: Yes
```

---

## GitHub Releases

### Creating Release

```markdown
1. Go to repository on GitHub
2. Click "Releases" → "Create a new release"
3. Enter:
   - Tag: v1.3.0
   - Release title: Version 1.3.0
   - Release notes: Copy from CHANGELOG
4. Check "Pre-release" if beta/alpha
5. Click "Publish release"
```

### Release Template

```markdown
# HELIOS Platform v1.3.0

## Overview
Brief description of this release.

## 🎉 New Features

### JWT Token Validation (Issue #234)
- Validates JWT tokens on all API endpoints
- Supports custom token expiration
- Automatic token refresh

### Webhook Support (Issue #567)
- Send webhooks for user events
- Retry logic for failed webhooks
- Event filtering

## 🐛 Bug Fixes

- Fixed dashboard widget overlap on mobile devices
- Fixed memory leak in WebSocket handler
- Fixed incorrect user filtering in search API

## ⚙️ Changes

- Updated authentication middleware
- Refactored database layer for performance
- Upgraded dependencies (see below)

## ⚠️ Breaking Changes

The legacy authentication endpoint `/api/auth/legacy` has been removed.
**Action required:** Switch to OAuth2 endpoint `/api/auth/oauth2`

Migration guide: [Link to migration docs]

## 🔒 Security

- Fixed SQL injection vulnerability in search endpoint
- Added rate limiting (1000 req/hour per API key)
- Security audit completed - no critical issues

## 📦 Dependency Updates

- React: 17.0.0 → 18.2.0
- Express: 4.17.0 → 4.18.2
- PostgreSQL driver: 8.0.0 → 8.7.0

## 📈 Performance

- 40% improvement in search query performance
- 30% reduction in API response time
- 50% improvement in database query efficiency

## 🙏 Contributors

- @developer1
- @developer2
- @designer1

---

**Release Date:** April 14, 2026  
**Download:** [GitHub Release Assets]
```

### Release Template in Repository

Create `.github/release-template.md`:

```markdown
## Overview
Brief description of this release.

## 🎉 New Features
- Feature 1
- Feature 2

## 🐛 Bug Fixes
- Fix 1
- Fix 2

## ⚙️ Changes
- Change 1
- Change 2

## ⚠️ Breaking Changes
None

## 🔒 Security
- Security fix 1

## 📈 Performance
- Performance improvement 1

## 📦 Dependencies
- Updated package X to Y

## 🙏 Contributors
Thank you to contributors!
```

---

## Announcement Process

### Internal Announcement (Slack)

```markdown
🚀 HELIOS Platform v1.3.0 Released!

New features:
✓ JWT token validation
✓ Webhook support

Bug fixes:
✓ Mobile widget overlap
✓ WebSocket memory leak

Breaking changes:
⚠️ Legacy auth endpoint removed (see migration guide)

Download: [GitHub Release Link]
Docs: [Release notes link]
Migration guide: [Link if needed]

Questions? Post in #helios-platform
```

### External Announcement (Blog/Email)

```markdown
Subject: HELIOS Platform v1.3.0 - Enhanced Security & Reliability

We're excited to announce HELIOS Platform v1.3.0!

This release includes:

✨ Enhanced Security
- JWT token validation on all API endpoints
- Automatic token refresh support
- Rate limiting to prevent abuse

🔧 New Capabilities
- Webhook support for real-time integrations
- Event filtering and routing
- Advanced configuration options

🐛 Stability Improvements
- Fixed dashboard performance issues
- Resolved WebSocket memory leaks
- Improved search reliability

📖 Documentation
- New webhook integration guide
- Migration guide for auth changes
- Security best practices

🚀 Get Started
- Download v1.3.0: [Link]
- Read the full release notes: [Link]
- Check the migration guide: [Link]

As always, we appreciate your feedback!
```

### Customer Notification (for breaking changes)

```markdown
IMPORTANT: HELIOS Platform v1.3.0 - Action Required

Dear HELIOS Platform Users,

Version 1.3.0 includes a breaking change to the authentication system.

What's changing:
- Legacy authentication endpoint is deprecated
- OAuth2 is now the recommended authentication method
- Support for legacy auth ends June 1, 2026

What you need to do:
1. Review the migration guide [Link]
2. Update your integrations to use OAuth2
3. Test changes in staging environment
4. Deploy updates before June 1, 2026

Need help?
- Migration guide: [Link]
- Support: support@helios.com
- FAQ: [Link]

Questions? Reply to this email or contact support.
```

---

## Post-Release Verification

### Deployment Verification (30 minutes after)

```markdown
□ Production deployment successful
□ Health check endpoints responding
□ No critical errors in logs
□ Performance metrics normal
□ Database queries performing well
□ API response times acceptable
□ No increase in error rate
□ User traffic normal
```

### Functional Verification (1 hour after)

```markdown
□ New features working correctly
□ Existing features not broken
□ API endpoints responding
□ Database queries successful
□ Webhooks triggering (if applicable)
□ Authentication working
□ No configuration issues
```

### Monitoring (24 hours after)

```markdown
□ Error rates stable
□ Performance metrics acceptable
□ User engagement normal
□ No unusual API patterns
□ No security alerts
□ Customer support tickets normal
□ No rollback needed

If issues appear:
1. Assess severity
2. Determine rollback need
3. Create hotfix branch
4. Deploy hotfix
5. Document incident
```

### Rollback Plan

```bash
# If critical issue discovered:

# 1. Assess impact
# 2. Decide if rollback needed

# If rollback needed:
git checkout main
git log --oneline -5
# Find previous tag

git revert v1.3.0
git tag v1.3.1-rollback
git push origin main --force-with-lease
git push origin v1.3.1-rollback

# Verify previous version running
# Monitor for issues
```

---

## Release Metrics

Track for each release:

```markdown
- Time to release (from planning to deployment)
- Number of hotfixes needed
- Customer issues reported
- Performance impact
- Adoption rate
- User feedback score
- Support ticket increase
```

---

**Last Updated:** April 2026  
**Version:** 1.0

See also: [GITHUB_BEST_PRACTICES.md](GITHUB_BEST_PRACTICES.md), [CHANGELOG.md](../../CHANGELOG.md)
