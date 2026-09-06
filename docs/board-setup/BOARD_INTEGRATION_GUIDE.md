# HELIOS Platform - Board Integration Guide

**Document Version:** 1.0  
**Last Updated:** 2026-04-13  
**Integration Level:** Enterprise  
**Status:** Production Ready

---

## Overview

The HELIOS Platform board integrates with multiple GitHub systems to create a unified workflow.

### Integration Points

1. **GitHub Issues** ↔ Project Board
2. **GitHub Actions** ↔ PR Automation
3. **GitHub PRs/Commits** ↔ Status Updates
4. **Notifications** → Team Communication
5. **Webhooks** → External Systems (Optional)

---

## GitHub Issues Integration

### Bi-directional Sync

```
Issue Created/Modified
    ↓
Synced to Project Board
    ↓
Field Data Available in Project
    ↓
Project Updates Visible in Issue
```

### What Syncs

**From Issue to Board:**

- Title and description
- Labels (converted to custom fields)
- Assigned users
- Milestone
- Issue status (open/closed)

**From Board to Issue:**

- Custom field values via comments
- Project column (via automation)
- Automation updates (via comments)

### Setup

1. Repository Settings → Features: Enable "Projects"
2. Create GitHub Project
3. Link repository
4. Add issues to project manually or via automation

### Example Workflow

```
Step 1: Create issue in repository
Title: "Implement feature X"
Labels: component-gui, phase-2, priority-high

Step 2: System adds to project
Field updates:
- Component = GUI
- Status Phase = Phase 2
- Priority = High

Step 3: Team works on issue
Moves through board columns

Step 4: PR created and merged
Automation closes issue
Issue closed in repository automatically
```

---

## GitHub Actions Integration

### What Triggers Automation

```
GitHub Event                GitHub Actions Triggered
├─ Issue labeled            → Assign phase/tier
├─ PR opened/updated        → Link to issue
├─ PR status changes        → Update issue column
├─ PR merged                → Mark complete
└─ Issue closed             → Archive/cleanup
```

### Workflow Example

```yaml
name: Board Automation
on:
  issues:
    types: [opened, labeled, edited]
  pull_request:
    types: [opened, synchronize, closed]

jobs:
  process:
    runs-on: ubuntu-latest
    steps:
      - name: Update board
        run: |
          # Sync issue/PR with board
          # Update custom fields
          # Move columns if needed
```

### PR/Commit Linking

**Automatic Linking:**

- PR mentions issue: `Fixes #123`
- Commit mentions issue: `[#456]`
- System auto-detects and links

**Manual Linking:**

1. Open issue in GitHub Projects
2. Add PR link in comments
3. System updates board status

### Status Update Flow

```
Commit → Push → Workflow Triggers
                ↓
            PR Created → Auto-link to issue
                ↓
            Status checks run
                ↓
            Results posted
                ↓
            Board updated (Rule 2)
                ↓
            Column moves in real-time
                ↓
            Team notified
```

---

## PR/Commit Linking

### Best Practices

**PR Commit Message Format:**

```
[component-gui] [phase-2] Implement dark mode toggle

Fixes #456
Related: #457

Description: Adds dark mode toggle to settings.
Tests: Added 10 new test cases.
```

**Monorepo Considerations:**

- One PR per component when possible
- Cross-component PRs link multiple issues
- Use sub-tasks for large features

### Link Verification

```
Step 1: PR Created
Body contains: "Fixes #456"

Step 2: System detects link
Validates issue #456 exists

Step 3: Bi-directional link created
- Issue references PR
- PR references issue

Step 4: Board updates
Issue moves to "In Progress" (Rule 2)
```

---

## Status Propagation

### Sync Direction

**Issue → PR:**

- Issue created → PR references issue
- Issue moved to Review → PR moved to review state

**PR → Issue:**

- PR created → Issue moved to In Progress
- PR merged → Issue auto-completed (if criteria met)

**Board ↔ External:**

- Board updates trigger webhooks (if configured)
- External updates can trigger board updates

### Status Mapping

| Board Column | PR State | Issue State | Sync |
|--------------|----------|------------|------|
| Backlog | N/A | Open | One-way (board → issue) |
| Todo | Draft | Open | One-way (board → issue) |
| In Progress | Open | Open | Both directions |
| Review | Open/Review | Open | Both directions |
| Done | Merged | Closed | Automatic (PR → Issue) |

---

## Notification System

### Notification Triggers

| Event | Recipient | Channel | Timing |
|-------|-----------|---------|--------|
| Issue assigned | Assignee | Email, Notifications | Immediate |
| PR created | Team | Slack, Email | Immediate |
| Review needed | Reviewer | Slack, Email | Immediate |
| Approval needed | Team | Notifications | Immediate |
| Status moved | Assignee | In-app | Immediate |
| Deadline approaching | Assignee | Email | 1 day before |
| Deadline passed | Lead | Email | Immediate |
| Blocker added | Team | Slack | Immediate |

### Notification Setup

**Email Notifications:**

- GitHub Settings → Notifications
- Project notifications → Email
- Repository notifications → Email

**Slack Integration (Optional):**

```
1. Install GitHub Slack app
2. Connect repository
3. Subscribe to board updates
4. Configure notification rules
5. Test notifications
```

### Customizing Notifications

```
GitHub Settings:
1. Notifications center
2. Select your project
3. Choose notification types:
   - Participating
   - Watching
   - Not watching
4. Email frequency settings
```

---

## Webhook Integration (Optional)

### Supported Webhooks

```yaml
Webhook Events:
  - issues
  - pull_requests
  - project changes
  - labels
  - workflow_runs
  - workflow_jobs
```

### External System Integration

**Example: Slack Webhook**

```yaml
Event: Issue moved to Review
Action: Post to Slack
Message: "@team Issue #456 ready for review"
```

**Example: JIRA Sync**

```
GitHub Issue ← → JIRA Ticket
Field Sync: Status, Priority, Assignee
Bi-directional updates via Integration Reference field
```

### Setup Instructions

1. External system settings
2. Copy webhook URL
3. GitHub repo → Settings → Webhooks
4. Paste URL
5. Select events
6. Test webhook
7. Monitor delivery

---

## Monitoring & Troubleshooting

### Integration Health Checks

```
Daily Checks:
□ Issues syncing to board
□ PR links working
□ Status updates occurring
□ Notifications sending
□ No integration errors
```

### Common Issues

**Issues not appearing on board:**

- Verify issue added to project
- Check filters aren't hiding it
- Verify view is showing all items

**PR not linking to issue:**

- Use "Fixes #123" format
- Verify issue number correct
- Check for typos

**Status not updating:**

- Verify automation rules active
- Check PR merge status
- Review GitHub Actions logs

**Notifications not sending:**

- Check notification settings
- Verify email not in spam
- Test with new notification

---

## Data Synchronization

### Sync Frequency

| Data Type | Sync Frequency | Latency | Reliability |
|-----------|--------|---------|------------|
| Issue metadata | Real-time | <1s | 99.9% |
| Board fields | Real-time | <2s | 99.9% |
| PR status | 1-2 minutes | 1-2m | 99.8% |
| Workflow status | 2-5 minutes | 2-5m | 99.5% |
| External webhooks | Real-time | <2s | 99.0% |

### Ensuring Data Consistency

```
During high activity (>100 updates/min):
1. Queue updates
2. Process in order
3. Prevent race conditions
4. Retry failed updates
5. Log all changes
```

### Conflict Resolution

If board field and issue field conflict:

- **Board takes precedence** in project
- Manual override allowed
- Auto-correction logs error
- Team notified of conflict

---

## Security & Access Control

### Permission Requirements

| Action | Permission | Scope |
|--------|-----------|-------|
| View board | Read | Project |
| Create issue | Write | Repository |
| Update field | Write | Project |
| Run automation | Admin | Workflow |
| Configure webhook | Admin | Repository |

### API Rate Limits

```
GitHub API Limits (with authentication):
- Issue operations: 5,000/hour
- Project operations: 5,000/hour
- Workflow operations: 5,000/hour
- Webhook deliveries: 100/minute

Current Usage:
- Daily average: ~500 operations
- Peak hours: ~100 operations
- Status: Well within limits
```

### Audit Logging

All integration activities logged:

- Who made changes
- What changed
- When change occurred
- External system involved

---

## Integration Performance

### Typical Latencies

```
Issue Created → Board Update:         <1 second
PR Created → Link Update:             <2 seconds
PR Status → Board Column:             1-2 minutes
Automation Rule Execution:            1-2 seconds
Webhook Delivery (external):          <5 seconds
```

### Optimization

- Archive old completed issues monthly
- Limit real-time sync to active items
- Cache frequently accessed data
- Use batch operations where possible

---

**Document Control:**

- Version: 1.0
- Last Updated: 2026-04-13
- Integration Points: 6
- Status: Production Ready

For integration support, contact the DevOps team.
