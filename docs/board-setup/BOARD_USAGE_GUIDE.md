# HELIOS Platform - Board Usage Guide for Teams

**Document Version:** 1.0  
**Last Updated:** 2026-04-13  
**Audience:** All Team Members  
**Status:** Production Ready

---

## Getting Started

### First Week Checklist

**Day 1: Access & Orientation**

- [ ] Access GitHub Projects board
- [ ] Review BOARD_SETUP_COMPLETION_SUMMARY.md
- [ ] Explore all 6 views
- [ ] Understand your role

**Day 2: Learn Your Workflow**

- [ ] Review your component's column (By Component view)
- [ ] Understand issue flow (By Status view)
- [ ] Check My Work view
- [ ] Understand priority levels

**Day 3: Create First Issue**

- [ ] Create test issue in your component
- [ ] Apply labels correctly
- [ ] Set custom fields
- [ ] Move through workflow manually
- [ ] Close with PR

**Day 4: Work with Team**

- [ ] Pair with teammate
- [ ] Review their workflow
- [ ] Ask questions
- [ ] Share tips you've learned

**Day 5: Full Participation**

- [ ] Independently manage your issues
- [ ] Help new team members
- [ ] Contribute to board improvements

---

## How-To Guides

### How to Create an Issue on the Board

**Step 1: Create in Repository**

```
1. Go to repository
2. Click Issues tab
3. Click New Issue
4. Fill in title and description
5. Add clear acceptance criteria
```

**Step 2: Add to Project Board**

```
1. Click Projects (top right of issue)
2. Add to "HELIOS Platform" board
3. Project automatically assigns board position
```

**Step 3: Configure Custom Fields**

```
1. In project view, click issue
2. Fill in custom fields on right panel:
   - Priority: [Select level]
   - Component: [Select component]
   - Effort Estimate: [Select points]
   - Status Phase: [Auto-assigned usually]
   - Assigned Team Member: [Your name]
   - Target Completion Date: [Set date]
3. Save automatically
```

**Step 4: Add Labels (Triggers Automation)**

```
1. Back in GitHub issue
2. Click Labels
3. Add relevant labels:
   - component-[name]
   - phase-[number]
   - priority-[level]
4. Automation triggers immediately!
5. Return to board to verify
```

### How to Add Existing Issue to Board

```
Method 1: From Issue Page
1. Open issue in repository
2. Click Projects → Add to project
3. Select "HELIOS Platform"
4. Issue automatically appears on board

Method 2: From Board
1. Open board
2. Click Add item
3. Search for existing issue
4. Click to add
```

### How to Update Issue Fields

**Update Priority:**

```
1. Open issue in project view
2. In right panel, find Priority field
3. Click to open dropdown
4. Select new priority
5. Auto-saves
```

**Update Component:**

```
1. Find Component field
2. Click to open dropdown
3. Select new component
4. Auto-updates automation (Rule 4)
5. Watch for tier auto-assignment
```

**Update Status Phase:**

```
1. Find Status Phase field
2. Click dropdown
3. Select target phase
4. Automation updates related phase checkboxes
5. Issue appears in By Phase view
```

**Update Effort Estimate:**

```
1. Find Effort Estimate field
2. Click dropdown
3. Select points (1, 2, 3, 5, 8, 13)
4. Used for sprint planning and velocity
```

### How to Move Between Columns

**In By Status View (Classic Workflow):**

```
Drag & Drop Method:
1. Find issue card in current column
2. Click and hold
3. Drag to target column
4. Release to drop
5. System updates field automatically

Expected Columns:
Backlog → Todo → In Progress → Review → Done
```

**Automatic Movement (via PR):**

```
1. Create PR linked to issue
2. PR created → Auto moves to In Progress
3. PR ready for review → Auto moves to Review
4. PR merged → Auto moves to Done
5. Less manual work needed!
```

### How to Use Filters

**Filter by Component (Show my component only):**

```
1. Open board
2. Click Filter icon
3. Add filter: Component = [Your Component]
4. View updates to show only your issues
5. Click X to remove filter
```

**Filter by Priority (Focus on critical):**

```
1. Click Filter
2. Add: Priority = Critical OR Priority = High
3. See only important items
4. Helps prioritize daily work
```

**Filter by Assignee (See my work):**

```
1. Click Filter
2. Add: Assigned = [Your Name]
3. Or use "My Work" view automatically
```

**Complex Filters:**

```
Show all Phase 2 work assigned to me that's in progress:
Filter: Status Phase = Phase 2
  AND Assigned = Me
  AND Status = In Progress
```

### How to Link PRs to Issues

**In PR Description:**

```
Title: Fix: Dark mode toggle bug

Body:
Fixes #456
Related: #457, #458

This PR implements the dark mode toggle feature.
```

**System Auto-Detects:**

1. Reads "Fixes #456"
2. Finds issue #456
3. Links PR and issue
4. Updates issue: In Progress (Rule 2)

**Manual Linking (if needed):**

```
1. Open issue
2. Scroll to comments
3. Link PR manually
4. Include full URL
5. @mention relevant people
```

### How to Create Sub-Tasks

**For Large Issues:**

```
1. Create parent issue
2. In description, include:

## Sub-tasks
- [ ] Sub-task 1
- [ ] Sub-task 2
- [ ] Sub-task 3

3. Check boxes as you complete each
4. Or create separate issues for each task
5. Link them with "Related" comments
```

### How to Request Review

```
1. Create PR linked to issue
2. Add @mention to reviewers
3. PR automatically moves to Review column
4. Add comment with summary
5. Ask specific questions
6. Tag by expertise needed
```

---

## Best Practices

### Daily Workflow

```
Morning (9:00 AM):
1. Check My Work view
2. Review due today items
3. Check blockers
4. Update status for current work
5. Plan your day

During Day:
1. Move completed items to In Progress
2. Create PR when ready
3. Update issue when PR ready for review
4. Help unblock teammates

End of Day (5:00 PM):
1. Move completed items to Done
2. Update tomorrow's priorities
3. Note any blockers
4. Review team's progress
```

### Estimation Best Practices

**Story Points:**

```
1 point = 1-2 hours of work
2 points = 0.5-1 day of work
3 points = 1-2 days of work
5 points = 2-3 days of work
8 points = 1 week of work
13 points = 2+ weeks of work

Tips:
- Compare to similar past issues
- Account for testing, review, deployment
- Avoid underestimation (causes rushed work)
- Avoid overestimation (seems harder than it is)
```

### Quality Tips

```
Good Issue Descriptions:
✓ Clear problem statement
✓ Context and why it matters
✓ Acceptance criteria with checkboxes
✓ Links to related issues/docs
✓ Expected vs actual behavior (bugs)
✓ Steps to reproduce (bugs)

Bad Issue Descriptions:
✗ "Fix stuff"
✗ No context
✗ Vague criteria
✗ No acceptance criteria
✗ Missing reproduction steps
```

### Communication Tips

```
In Issue Comments:
- Use @mentions to direct to person
- Link related issues with #number
- Post progress updates daily
- Flag blockers immediately
- Ask questions clearly
- Provide context for reviewers

Example:
@john-lead I'm blocked on #456 - need auth design review
See comment on #454 for context.
Can we discuss Thursday?
```

---

## Common Workflows

### Creating a Feature

```
Week 1: Planning
1. Create issue "Design: Feature X"
   - Status: Phase 0
   - Priority: High
   - Component: GUI
   - Effort: TBD
   - Acceptance: [Design complete, reviewed, approved]

2. Design phase work
   - Move to In Progress
   - Link design docs
   - Collaborate with team

3. Design review
   - Move to Review
   - Address feedback
   - Get sign-off

Week 2: Implementation
1. Create issue "Implement: Feature X"
   - Depends on design being done
   - Status: Phase 2
   - Component: GUI
   - Effort: 5 points

2. Development
   - Assign to developer
   - Move to In Progress
   - Create PR when ready

3. Review & Merge
   - PR moves to Review (auto)
   - Address feedback
   - Merge when approved
   - Auto moves to Done
```

### Fixing a Bug

```
1. Create issue "Bug: X not working in Y"
   - Priority: High
   - Component: [Affected component]
   - Add reproduction steps
   - Acceptance: [Bug fixed + test added]

2. Investigation
   - Move to In Progress
   - Add diagnosis details as comments
   - Link related issues

3. Fix & Test
   - Create PR with fix
   - Auto moves to Review
   - Include test case
   - Document fix

4. Deploy
   - Merge when approved
   - Auto moves to Done
   - Mark deployment status
```

### Cross-Component Work

```
Scenario: Feature needs UI + Backend

1. Create parent issue "Feature X"
2. Create sub-issues:
   - "Backend: Implement API" (Hub/Stack)
   - "Frontend: Build UI" (GUI)
   - Link them as related
   - Coordinate timelines
   - Don't start frontend until API designed

3. Backend team:
   - Works on API issue
   - Creates design PR
   - Frontend reviews to understand API

4. Frontend team:
   - Uses API design
   - Builds UI
   - Both move through workflow
   - Integrate when both ready

5. Integration:
   - Create integration issue if needed
   - Test together
   - Deploy together
```

---

## Troubleshooting

### Issue Not Appearing on Board

**Check:**

1. Is issue added to project? (Check Projects tab on issue)
2. Is view filtering it out? (Check active filters)
3. Is view showing correct columns? (Check view settings)

**Fix:**

1. Click issue → Projects → Add to HELIOS Platform
2. Remove or modify filters
3. Reset view or try different view

### Status Not Updating

**Check:**

1. Is PR linked correctly? (Check issue comments)
2. Is PR merged? (Check PR status)
3. Are automation rules active? (Check Actions logs)

**Fix:**

1. Link PR manually in issue comments
2. Verify PR is merged (not just approved)
3. Manually move if automation failed

### Custom Fields Not Populating

**Check:**

1. Did you apply labels? (phase-*, component-*)
2. Are labels spelled correctly? (case-sensitive)
3. Is automation rule running?

**Fix:**

1. Apply labels (triggers Rule 1)
2. Check label spelling
3. Manually fill fields if needed
4. Report if persists

### Can't Assign to Team Member

**Check:**

1. Is person a collaborator? (Check repo settings)
2. Have they accepted invitation?
3. Is field accepting this value?

**Fix:**

1. Add person as collaborator first
2. Have them accept invitation
3. Try again

---

## Tips & Tricks

### Keyboard Shortcuts

```
In GitHub Project Board:
- j/k: Move up/down
- Enter: Open issue
- Esc: Close issue
- c: Create issue
- l: Add label
- a: Assign
- m: Set milestone
```

### Quick Views to Bookmark

```
By Status: dailystandup.com/status
By Priority: focus-board/priority
By Component: [Your team component]
My Work: personal-tasks
By Phase: high-level-view
```

### Productivity Hacks

```
1. Use labels to trigger automation
2. Keep descriptions short but clear
3. Check My Work first thing each day
4. Update status at end of day
5. Batch similar work together
6. Keep work in progress limited (2-3 tasks)
7. Ask for help early, not late
8. Document blockers immediately
```

---

## Support & Resources

### Getting Help

**For Board Questions:**

- Check this guide first
- Search GitHub Discussions
- Ask in #project-board Slack channel
- Tag @board-admin in issue

**For Technical Issues:**

- Check GitHub status page
- File issue in DevOps repo
- Contact @devops-team

**For Process Questions:**

- Ask @project-manager
- Check team wikis
- Consult component lead

### Resources

- **Main Docs:** BOARD_SETUP_COMPLETION_SUMMARY.md
- **Custom Fields:** BOARD_CUSTOM_FIELDS_COMPLETE.md
- **Automation:** BOARD_AUTOMATION_RULES.md
- **Views:** BOARD_VIEWS_GUIDE.md
- **Metrics:** BOARD_MONITORING_GUIDE.md

---

**Document Control:**

- Version: 1.0
- Last Updated: 2026-04-13
- Audience: All Team Members
- Status: Production Ready

Welcome to the HELIOS Platform board! Happy organizing! 🚀
