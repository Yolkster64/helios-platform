# Project Board Management for HELIOS Platform

Guide for managing GitHub Project Boards and workflow automation.

---

## Table of Contents

1. [Column Definitions](#column-definitions)
2. [Card Flow](#card-flow)
3. [Automation Triggers](#automation-triggers)
4. [Status Updates](#status-updates)
5. [Burndown Tracking](#burndown-tracking)
6. [Impediment Handling](#impediment-handling)
7. [Review Cadence](#review-cadence)

---

## Column Definitions

### Standard Project Board Columns

**Backlog**

- Items identified but not committed to sprint
- Can move to Ready when prioritized
- No time commitment
- May be re-prioritized

**Ready**

- Items for current sprint
- Meeting acceptance criteria
- Have been estimated
- Can start immediately

**In Progress**

- Currently being worked on
- Someone actively coding
- Progress visible
- Not blocked

**In Review**

- PR created and under review
- Waiting for approval
- Tests passing
- Ready to merge

**Done**

- Merged to main/develop
- In production or staging
- Working as expected
- Closed and archived

**Blocked**

- Can't proceed without dependency
- Clear blocker identified
- Waiting for external issue
- Should be unblocked soon

### Optional Advanced Columns

```
Backlog → Ready → Estimated → In Progress → Testing → Review → Done

Or for complex projects:

Backlog → Planning → Design → Dev → QA → Staging → Release → Done
```

### Column Rules

```markdown
Backlog:
□ Items from GitHub issues
□ Not yet estimated
□ May not have owner
□ Can be reprioritized

Ready:
□ Estimated (story points)
□ Have owner assigned
□ Clear acceptance criteria
□ Can start immediately

In Progress:
□ One person assigned
□ PR created or in progress
□ Moving toward done
□ Update daily

In Review:
□ PR open on GitHub
□ Awaiting approval
□ Tests passing
□ No blockers

Done:
□ Merged to develop/main
□ Tests all passing
□ Deployed to staging
□ Ready for production
```

---

## Card Flow

### Moving Cards Through Board

**Backlog → Ready**

```markdown
When: During sprint planning
Owner: Product Manager
Criteria:
□ Issue is well-defined
□ Requirements clear
□ Acceptance criteria written
□ Story points estimated
□ Priority determined
```

**Ready → In Progress**

```markdown
When: Developer starts work
Owner: Developer
Criteria:
□ Create feature branch
□ Create draft PR
□ Link issue to PR
□ Update PR description
□ Move card to In Progress
```

**In Progress → In Review**

```markdown
When: PR ready for review
Owner: Developer
Criteria:
□ PR description complete
□ Tests written
□ Code reviewed locally
□ All status checks pass
□ Ready for peer review
```

**In Review → Done**

```markdown
When: PR approved and merged
Owner: Reviewer/Developer
Criteria:
□ 2+ approvals
□ All checks passing
□ No conflicts
□ Merged to develop
□ Branch deleted
```

**To Blocked**

```markdown
When: Work is blocked
Owner: Developer
Criteria:
□ Clear reason documented
□ Blocker issue linked
□ Expected unblock date
□ Assigned to unblock owner
```

**From Blocked**

```markdown
When: Blocker resolved
Owner: Developer
Criteria:
□ Blocker issue resolved
□ Work can resume
□ Move back to In Progress
□ Update team in Slack
```

### Example Card Lifecycle

```
Monday:
Backlog → Issue: "Add user authentication"
         Ready → (Sprint planning)
         
Tuesday:
Ready → Issue assigned to Developer A
In Progress → (Branch created, PR drafted)

Wednesday:
In Progress → (Implementation 50% complete)

Thursday:
In Progress → In Review (PR complete, awaiting review)
Reviewer checks PR, requests changes

Friday:
In Review → (Changes made and re-submitted)
           → (Approved after review)
           → Done (Merged!)

Next Sprint:
Monitor production for issues
User feedback: "Works great!"
```

---

## Automation Triggers

### GitHub Project Automation Setup

Configure in project settings:

**Automation Rules:**

```yaml
Rule 1: Auto-add to project
Trigger: New issue created
Action: Add to Backlog column

Rule 2: Move to In Progress
Trigger: PR opened
Action: Move linked issue to In Progress

Rule 3: Move to In Review
Trigger: PR review requested
Action: Move linked issue to In Review

Rule 4: Move to Done
Trigger: PR merged
Action: Move linked issue to Done

Rule 5: Archive old cards
Trigger: Card in Done for 2 weeks
Action: Archive card
```

### Manual Automation with GitHub Actions

Create `.github/workflows/project-automation.yml`:

```yaml
name: Project Automation
on:
  issues:
    types: [opened, labeled, assigned]
  pull_request:
    types: [opened, converted_to_draft, ready_for_review]

jobs:
  add-to-project:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/add-to-project@v0.5.0
        with:
          project-url: https://github.com/your-org/your-repo/projects/1
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

### Webhook-Based Automation

```javascript
// Trigger when issue labeled as "high-priority"
if (event.action === 'labeled' && event.label.name === 'high-priority') {
  moveCardToColumn(event.issue.id, 'Ready');
  notifySlack('High priority issue added!');
}

// Trigger when PR opened
if (event.action === 'opened') {
  linkIssueToPR(event.pull_request.id, event.issue_id);
  moveCardToColumn(event.issue_id, 'In Progress');
}

// Trigger when PR merged
if (event.action === 'closed' && event.pull_request.merged) {
  moveCardToColumn(event.issue_id, 'Done');
  closeIssue(event.issue_id);
}
```

---

## Status Updates

### Daily Status Updates

**During Daily Stand-up:**

```markdown
For each in-progress card:
1. What's your status? (0-100%)
2. Any blockers?
3. Will it be done today?
4. Need help?

Example:
Card: "Add user authentication"
Status: 60% complete
Blocker: Waiting for design approval
Timeline: Should finish Thursday
Need: @designer review ASAP
```

### Weekly Status Report

**Every Friday (15 minutes):**

```markdown
Completed this week:
- Card 1: User authentication (✓ Done)
- Card 2: Email notifications (✓ Done)

In progress:
- Card 3: Password reset (80%)
- Card 4: 2FA setup (50%)

Blocked:
- Card 5: OAuth integration (Waiting on vendor)

Next week:
- Continue password reset
- Start 2FA testing
- Resolve OAuth blocker
```

### Monthly Review

```markdown
Metrics:
- Issues completed: 24
- Average cycle time: 3.2 days
- On-time completion: 95%
- Blocked items: 2 (resolved)
- Velocity: 84 story points

Trends:
- Faster PR reviews this month
- Better issue descriptions
- Fewer blocked items

Improvements:
- Continue current practices
- More pair programming
- Better early blockers
```

---

## Burndown Tracking

### Sprint Metrics

Track for each sprint:

```markdown
Total Story Points: 100

Daily Tracking:
Monday:    100 → 90 (10 completed)
Tuesday:   90 → 85 (5 completed)
Wednesday: 85 → 65 (20 completed)
Thursday:  65 → 50 (15 completed)
Friday:    50 → 30 (20 completed)

Ideal Line:
└─ Should decrease steadily
└─ Should reach 0 by Friday
└─ Dips show completed work

Actual vs Ideal:
If below ideal: On track or ahead
If above ideal: Behind schedule
```

### Burndown Chart

```
100 │ ╱─── Ideal
    │╱  ╱── Actual
 75 │  ╱
    │ ╱
 50 │╱
    │
 25 │
    │
  0 └────────────────
    Mon Tue Wed Thu Fri
```

### Tracking Tool

Use GitHub Issues Insights or:

```bash
# Create burndown script
npm install @actions/github

# Calculate daily points
issues_done = count(issues where closed_at == today)
total_points = sum(all story points)
burndown = total_points - completed_points
```

---

## Impediment Handling

### Identifying Impediments

```markdown
An impediment is something blocking progress:

✓ Waiting for external team
✓ Dependency not met
✓ Blocker in another system
✓ Missing information
✓ Resource not available
✓ Infrastructure issue

NOT impediments:
✗ "Code is hard" (work to do)
✗ "Need to learn" (learning is part of work)
✗ "Wish we had tool" (use what's available)
```

### Impediment Process

**Identify:**

```markdown
1. Name the impediment clearly
2. Explain why it's blocking
3. Estimate impact (1-10)
4. Identify what's needed to unblock
```

**Example:**

```markdown
Impediment: Waiting for API documentation from backend team
Impact: 9/10 (blocking all frontend work)
Blocker: Backend team hasn't published API docs
Needed to unblock: API specification document
Timeline: Needed by tomorrow
Owner: @backend-lead
```

**Resolve:**

```markdown
1. Escalate if needed
2. Find workaround if possible
3. Update blocker status daily
4. Celebrate when resolved
5. Prevent in future
```

**Prevention:**

```markdown
1. Communicate dependencies early
2. Get commitments upfront
3. Build dependency buffers
4. Have backup plans
5. Document lessons learned
```

---

## Review Cadence

### Sprint Planning (Every 2 weeks)

**Preparation (Day Before):**

```markdown
□ Review backlog
□ Prioritize items
□ Refine issue descriptions
□ Estimate story points
□ Identify dependencies
```

**Planning Meeting (1 hour):**

```markdown
1. Review last sprint results (5 min)
2. Discuss roadmap (5 min)
3. Review backlog (10 min)
4. Team selects items (20 min)
5. Finalize sprint goal (10 min)
6. Team commits (10 min)
```

### Sprint Review (Every 2 weeks)

**Demo Meeting (1 hour):**

```markdown
1. Welcome & intro (5 min)
2. Demo completed items (30 min)
3. Discuss feedback (15 min)
4. Next steps (10 min)
```

### Sprint Retrospective (Every 2 weeks)

**Retro Meeting (1 hour):**

```markdown
1. What went well? (15 min)
2. What could improve? (15 min)
3. What will we try? (15 min)
4. Action items (15 min)
```

### Board Grooming (Weekly)

**Every Thursday (30 minutes):**

```markdown
□ Review Done items (can archive)
□ Review In Review items (any stuck?)
□ Review In Progress items (blockers?)
□ Review Ready items (order correct?)
□ Clean up labels
□ Add new issues
□ Update estimates if needed
```

### Quarterly Board Review

**Every 3 months (1 hour):**

```markdown
□ Review project structure
□ Are columns still appropriate?
□ Automation working well?
□ Team feedback on process
□ Any improvements needed?
□ Update board configuration
□ Document new standards
```

---

## Board Best Practices

```markdown
✓ Move cards to correct column immediately
✓ Update card descriptions when status changes
✓ Link PRs to issues in card
✓ Archive old/closed cards
✓ Keep Ready column prioritized
✓ Limit In Progress items (max 3 per person)
✓ Communicate blockers ASAP
✓ Celebrate Done items
✓ Review board in daily standup

✗ Don't leave cards in wrong column
✗ Don't ignore blocked cards
✗ Don't overload In Progress
✗ Don't archive cards before Done
✗ Don't change priorities constantly
✗ Don't neglect board maintenance
✗ Don't hide impediments
✗ Don't let cards stale
```

---

## Troubleshooting

### Cards Stuck in In Review

```markdown
If PR in review for > 3 days:
1. Check if reviewer has capacity
2. Request review reminder
3. Offer to pair on review
4. Escalate if critical
5. Consider breaking down
```

### Too Many Blocked Items

```markdown
If > 2 blocked items:
1. What are the common blockers?
2. Can we remove dependencies?
3. Can we unblock faster?
4. Do we need policy change?
5. Review planning process
```

### Sprint Goals Not Met

```markdown
If sprint fails 2 times:
1. Estimate too optimistic?
2. Unexpected issues appeared?
3. Team interrupted too much?
4. Complex issues need breaking down?
5. Consider retrospective focus
```

---

**Last Updated:** April 2026  
**Version:** 1.0

See also: [GITHUB_BEST_PRACTICES.md](GITHUB_BEST_PRACTICES.md), [ISSUE_MANAGEMENT_GUIDE.md](ISSUE_MANAGEMENT_GUIDE.md)
