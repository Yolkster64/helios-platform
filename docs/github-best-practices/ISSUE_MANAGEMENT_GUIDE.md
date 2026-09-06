# Issue Management Guide for HELIOS Platform

Best practices for creating, triaging, labeling, and managing issues in GitHub.

---

## Table of Contents

1. [Issue Types](#issue-types)
2. [Issue Template Usage](#issue-template-usage)
3. [Labeling Strategy](#labeling-strategy)
4. [Priority System](#priority-system)
5. [Milestone Assignment](#milestone-assignment)
6. [Issue Linking](#issue-linking)
7. [Automation Rules](#automation-rules)
8. [Closure Criteria](#closure-criteria)

---

## Issue Types

### Feature Request

**When:** New functionality needed

```markdown
Title: "feat: Add two-factor authentication"

Description:
As a [user role], I want to [functionality]
so that [benefit].

Requirements:
- [ ] Support TOTP (Google Authenticator)
- [ ] Support SMS as backup
- [ ] Add recovery codes

Acceptance Criteria:
- [ ] User can enable 2FA in settings
- [ ] 2FA required on login
- [ ] Recovery codes generated and stored securely

Labels: enhancement, security
Milestone: v1.3.0
Assignee: None (open for volunteers)
```

### Bug Report

**When:** Something isn't working correctly

```markdown
Title: "bug: Dashboard widgets overlap on mobile view"

Environment:
- Browser: Chrome 120
- Device: iPhone 13
- OS: iOS 17

Steps to Reproduce:
1. Open dashboard on mobile
2. Scroll to bottom
3. Widget overlaps with footer

Current Behavior:
Widgets are cut off and not clickable

Expected Behavior:
Widgets should be responsive and clickable

Screenshots:
[Attach screenshot showing issue]

Labels: bug, mobile
Priority: High
Milestone: v1.2.1
Assignee: None (needs investigation)
```

### Technical Debt

**When:** Code quality improvement needed

```markdown
Title: "refactor: Extract authentication service from routes"

Description:
Authentication logic is currently embedded in route handlers.
This creates tight coupling and makes testing difficult.

Current Impact:
- Hard to unit test auth logic
- Auth changes require multiple file updates
- Duplicated code across endpoints

Proposed Solution:
Create separate AuthService class with:
- Login/logout methods
- Token validation
- Session management

This refactoring will:
- Improve testability
- Reduce code duplication
- Improve maintainability

Complexity: Medium
Labels: refactor, tech-debt
Milestone: v1.3.0
Priority: Medium
```

### Documentation

**When:** Documentation is missing or outdated

```markdown
Title: "docs: Add API documentation for webhooks"

Description:
Webhook feature exists but lacks documentation.

Missing Documentation:
- [ ] Webhook setup guide
- [ ] Event types and payloads
- [ ] Retry strategy
- [ ] Examples

Labels: documentation
Priority: Medium
Assignee: Documentation Team
```

### Spike/Investigation

**When:** Research or exploration needed

```markdown
Title: "spike: Evaluate authentication libraries"

Description:
Investigate available JWT libraries for Node.js

Objectives:
- Compare popular JWT libraries
- Performance benchmarks
- Security considerations
- Integration complexity

Success Criteria:
- Comparison document created
- Recommendation provided
- Sample integration code

Labels: spike, research
Milestone: v1.3.0
Time Estimate: 8 hours
```

---

## Issue Template Usage

### Create GitHub Issue Templates

Place in `.github/ISSUE_TEMPLATE/`:

**bug-report.md:**

```markdown
---
name: Bug Report
about: Report a bug or issue
title: "[BUG] "
labels: bug
assignees: ''
---

## Describe the Bug
Clear description of what the bug is.

## Steps to Reproduce
1. Go to '...'
2. Click on '...'
3. Scroll down to '...'
4. See error

## Expected Behavior
What should happen instead

## Actual Behavior
What actually happened

## Environment
- Browser: [e.g. Chrome]
- OS: [e.g. Windows 10]
- Version: [e.g. 1.2.0]

## Screenshots
If applicable

## Additional Context
Any other context
```

**feature-request.md:**

```markdown
---
name: Feature Request
about: Suggest a new feature
title: "[FEATURE] "
labels: enhancement
assignees: ''
---

## Is your feature request related to a problem?
Describe the problem. Ex. I'm always frustrated when [...]

## Describe the Solution
Clear description of what you want to happen

## Describe Alternatives
Alternative solutions or features you've considered

## Additional Context
Any other context
```

### Using Templates

1. Click "New issue" on GitHub
2. Select template (Bug Report, Feature Request, etc.)
3. Fill in all sections
4. Click "Submit new issue"

---

## Labeling Strategy

### Core Labels

| Label | Color | When to Use |
|-------|-------|-----------|
| **bug** | 🔴 Red | Something is broken |
| **enhancement** | 🟢 Green | New feature or improvement |
| **documentation** | 🔵 Blue | Docs updates needed |
| **refactor** | 🟣 Purple | Code quality improvement |
| **test** | 🟤 Brown | Testing or coverage |
| **security** | 🟠 Orange | Security-related |
| **performance** | 🟡 Yellow | Performance improvement |
| **accessibility** | 🟢 Green | A11y improvements |
| **chore** | ⚪ Gray | Maintenance tasks |
| **help wanted** | 🔵 Blue | Open for contributors |
| **good first issue** | 🟢 Green | Good for new contributors |

### Priority Labels

| Label | Meaning | Response Time |
|-------|---------|--------------|
| **priority: critical** | Prod down, security issue | Immediate (< 1 hour) |
| **priority: high** | Major functionality broken | ASAP (< 4 hours) |
| **priority: medium** | Important but not blocking | < 24 hours |
| **priority: low** | Nice to have | Within sprint |

### Status Labels

| Label | Meaning |
|-------|---------|
| **status: investigation** | Being investigated |
| **status: in-progress** | Actively being worked on |
| **status: blocked** | Can't proceed (reason in comment) |
| **status: review** | Waiting for code review |
| **status: waiting** | Waiting for external input |
| **status: needs-info** | More information requested |

### Area Labels

| Label | Area |
|-------|------|
| **area: api** | API functionality |
| **area: ui** | User interface |
| **area: database** | Database layer |
| **area: auth** | Authentication |
| **area: performance** | Performance |
| **area: ci-cd** | CI/CD pipeline |
| **area: docs** | Documentation |

### Multi-Line Label Rules

```markdown
✓ Use 2-3 labels per issue (not more)
✓ Always include type label (bug, enhancement, etc.)
✓ Add priority if clear
✓ Add area if known
✗ Don't over-label (causes noise)
✗ Don't use labels instead of descriptions

Example good labeling:
- bug, priority: high, area: api

Example over-labeling:
- bug, priority: high, critical, urgent, needs-fix, please-fix, etc.
```

### Creating Labels

```markdown
## Standard Label Set to Create

Core Types:
- bug (Red)
- enhancement (Green)
- documentation (Blue)
- refactor (Purple)
- test (Brown)

Priority:
- priority: critical (Red)
- priority: high (Orange)
- priority: medium (Yellow)
- priority: low (Gray)

Status:
- status: in-progress (Blue)
- status: blocked (Red)
- status: needs-info (Yellow)
- status: review (Green)

Areas:
- area: api (Light Blue)
- area: ui (Light Green)
- area: auth (Light Orange)
- area: database (Light Gray)

Experience:
- good first issue (Green)
- help wanted (Blue)
- question (Light Blue)
```

---

## Priority System

### Priority Definitions

**Critical (P0)**

- Production is down or severely impaired
- Security vulnerability
- Data loss risk
- Revenue impact
- Response time: Immediate (< 1 hour)
- SLA: Fix within 4 hours

```markdown
Example:
- "Authentication service is down"
- "Database is corrupted"
- "Security breach discovered"
```

**High (P1)**

- Important feature broken
- Major functionality impaired
- Affects multiple users
- Response time: ASAP (< 4 hours)
- SLA: Fix within 24 hours

```markdown
Example:
- "Dashboard doesn't load for logged-in users"
- "Export feature broken"
- "Search results incorrect"
```

**Medium (P2)**

- Normal functionality degraded
- Affects some users
- Workaround exists
- Response time: < 24 hours
- SLA: Fix within sprint

```markdown
Example:
- "Mobile view slightly misaligned"
- "Report generation is slow"
- "Help text could be clearer"
```

**Low (P3)**

- Nice to have
- Doesn't affect core functionality
- No workaround needed
- Response time: Within sprint
- SLA: Fix when time permits

```markdown
Example:
- "Improve button styling"
- "Add dark mode"
- "Update sample code"
```

### Determining Priority Decision Tree

```
Is production down or data at risk?
├─ YES → Priority: Critical (P0)
└─ NO → Does it block users from working?
        ├─ YES → Does it affect all users?
        │       ├─ YES → Priority: High (P1)
        │       └─ NO → Priority: Medium (P2)
        └─ NO → Does it improve experience?
                ├─ YES, significantly → Priority: Medium (P2)
                └─ NO or minor → Priority: Low (P3)
```

---

## Milestone Assignment

### Milestone Naming Convention

```
Version format: v[MAJOR].[MINOR].[PATCH]

Examples:
- v1.0.0 (Major release)
- v1.1.0 (Minor release - new features)
- v1.0.1 (Patch release - bug fixes)
- v1.2.0-beta (Pre-release)
- Future / Backlog (For unscheduled work)
```

### Milestone Strategy

```markdown
## Current Sprint
- v1.3.0 (In Development)
- Target date: Next Friday

## Upcoming Release
- v1.4.0 (Planned)
- Target date: 2 weeks after v1.3.0

## Backlog
- Future / Backlog (Unscheduled)
- For issues without target release

## Past Releases
- v1.2.0 (Released)
- v1.1.0 (Released)
- v1.0.0 (Released)
```

### Assigning Issues to Milestones

1. **New feature** → Assign to next feature release (e.g., v1.3.0)
2. **Bug on production** → Assign to next patch release (e.g., v1.2.1)
3. **Enhancement** → Assign to next minor release (e.g., v1.3.0)
4. **Speculative** → Assign to "Future / Backlog"
5. **Doing now** → Assign to current sprint milestone

---

## Issue Linking

### How to Link Issues

**In Issue Description or Comments:**

```markdown
# Linking to other issues
Relates to #123
Depends on #456
Blocks #789
Fixes #234 (auto-closes when PR merged)
Closes #567 (auto-closes when PR merged)
Partially fixes #890
See also #111, #222, #333
```

### Linking in PR Description

```markdown
# Pull Request Description

## What changed?
Implemented JWT token validation for API endpoints

## Related issues
- Fixes #234 (JWT validation requirement)
- Relates to #567 (Security audit)
- Unblocks #890 (Feature that needed auth)

## Testing
- Unit tests added (95% coverage)
- Manual testing on staging

When this PR is merged, issues #234 will auto-close.
```

### Why Link Issues?

```markdown
✓ Provides context and history
✓ Shows dependencies between work
✓ Auto-closes related issues when PR merged
✓ Makes it easy to find related work
✓ Helps new team members understand connections
✓ Creates audit trail of decisions
```

---

## Automation Rules

### GitHub Automation Setup

Configure in repository Settings → Automation

**Auto-Close on PR Merge:**

```markdown
When issue is linked in PR with "Fixes #123"
→ Issue auto-closes when PR merges
```

**Auto-Add Labels:**

```markdown
When issue created without labels
→ Optionally add "needs-triage" label

When issue has no assignee after 1 day
→ Post reminder: "Please assign owner"
```

**Status Updates:**

```markdown
When issue moved to "In Progress"
→ Change status label automatically

When PR linked to issue
→ Update issue status to "review"
```

### Example Workflow

```markdown
## Issue Lifecycle Automation

Issue Created
├─ Add label: "needs-triage"
└─ Post: "Thanks for reporting! Will review shortly."

Triaged (Priority + Label Added)
├─ Remove label: "needs-triage"
├─ Add status: "ready-for-work"
└─ Post: "Ready for implementation"

Assigned to Developer
├─ Change status: "in-progress"
└─ Notify: "Work has started on this issue"

PR Linked to Issue
├─ Change status: "in-review"
└─ Comment: "PR #456 addresses this issue"

PR Merged
├─ Auto-close issue
├─ Change status: "done"
└─ Close with link to PR
```

### YAML Workflow Example

```yaml
name: Auto-triage
on:
  issues:
    types: [opened, reopened]

jobs:
  triage:
    runs-on: ubuntu-latest
    steps:
      - name: Add needs-triage label
        uses: actions/github-script@v6
        with:
          script: |
            github.rest.issues.addLabels({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              labels: ['needs-triage']
            })
```

---

## Closure Criteria

### Issue Closure Checklist

**Before closing an issue, verify:**

```markdown
## For Bug Fixes
□ Bug is reproduced and understood
□ Root cause identified
□ Fix implemented and tested
□ Fix deployed to staging
□ Fix deployed to production
□ Regression tests added
□ Stakeholders verified fix works
□ Related documentation updated
□ Similar bugs checked for

## For Feature Implementation
□ All acceptance criteria met
□ Code reviewed and approved
□ Test coverage adequate (80%+)
□ Documentation written
□ Feature tested on staging
□ Feature deployed to production
□ User documentation complete
□ Monitoring and alerts in place
□ Team trained on feature

## For Technical Debt
□ Refactoring complete
□ All tests pass
□ Performance benchmarks acceptable
□ Code review approved
□ No new issues introduced
□ Documentation updated
□ Performance impact verified

## For Documentation
□ Documentation written
□ Links verified
□ Examples tested
□ Peer reviewed
□ Published in correct location
□ Indexed in documentation site
```

### Issue Resolution Codes

| Code | Usage | Comment |
|------|-------|---------|
| **Completed** | Issue resolved | Work done, issue complete |
| **Won't Fix** | Decided not to do | Explain why in comment |
| **Duplicate** | Same as another | Link to original issue |
| **Cannot Reproduce** | Can't verify bug | Add debugging steps |
| **Invalid** | Misreported/unclear | Explain why invalid |
| **Wontfix: Obsolete** | Feature no longer needed | Explain why obsolete |

### Closing Issue Steps

1. **Add closing comment** with summary:

```markdown
Fixed in PR #456. Changes:
- Implemented JWT validation
- Added error handling
- Updated documentation
- Added unit tests

Deployed to production on April 15, 2026.
```

2. **Verify linking**: PR has "Fixes #issue-number"
3. **Wait for merge**: PR merges, issue auto-closes
4. Or **manually close** if PR link doesn't auto-close

### Reopening Issues

```markdown
If issue was closed but problem persists:
1. Click "Reopen issue" button
2. Comment: "Issue still present in v1.2.1. [Description]"
3. Assign to developer
4. Set new priority if changed
```

---

## Issue Triage Workflow

### Daily Triage

```markdown
Every morning (15 minutes):

□ Review new issues created since yesterday
□ Add appropriate labels
□ Assign priority
□ Assign to milestone
□ Request more info if needed
□ Assign owner if obvious
□ Post acknowledgment comment

Example comment:
"Thanks for reporting! Assigned to @dev-team for investigation.
Will prioritize based on impact. Any additional details would help."
```

### Weekly Review

```markdown
Every Friday (30 minutes):

□ Review "needs-info" issues (follow up)
□ Review "blocked" issues (resolve blockers)
□ Review unassigned issues (assign owners)
□ Update milestone progress
□ Close outdated or invalid issues
□ Create missing issues from customer feedback
```

### Monthly Metrics

```markdown
Track and review:
- Issues created vs closed
- Average time to close
- Issues by priority distribution
- Backlog size trends
- Time in "needs-info" state
- Team workload balance
```

---

## Best Practices

```markdown
✓ Create issues for any work before starting
✓ Keep descriptions concise but complete
✓ Use templates consistently
✓ Link related issues
✓ Assign to milestone and owner
✓ Update status regularly
✓ Close with summary comment
✓ Use consistent labeling
✓ Triage regularly (daily)
✓ Review metrics weekly

✗ Create issues in comments only
✗ Use issue descriptions for discussion
✗ Leave issues unassigned indefinitely
✗ Ignore "needs-info" requests
✗ Close without explanation
✗ Use inconsistent labels
✗ Accumulate old issues (clean up monthly)
✗ Assign to people without checking
```

---

**Last Updated:** April 2026  
**Version:** 1.0

See also: [PULL_REQUEST_GUIDE.md](PULL_REQUEST_GUIDE.md), [GITHUB_BEST_PRACTICES.md](GITHUB_BEST_PRACTICES.md)
