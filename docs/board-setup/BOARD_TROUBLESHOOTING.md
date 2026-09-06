# HELIOS Platform - Board Troubleshooting Guide

**Document Version:** 1.0  
**Last Updated:** 2026-04-13  
**Status:** Production Ready

---

## Quick Troubleshooting Index

| Issue | Cause | Solution | Time |
|-------|-------|----------|------|
| Issue not on board | Not added to project | Add via Projects tab | <1min |
| Status not updating | PR not linked correctly | Link PR in issue comments | <2min |
| Field not populated | Labels not applied | Apply phase/component labels | <1min |
| Automation not triggering | Rule not active/conditions not met | Check rule conditions | <5min |
| View not loading | Too many items or filter issue | Clear filters or refresh | <2min |
| Can't drag issue | Permission or view type issue | Check permissions, use table view | <2min |

---

## Issue Not Appearing on Board

### Symptoms

- Created issue but can't find it on board
- Issue exists in repository but not in projects
- Different views not showing the issue

### Diagnosis Steps

```
Step 1: Verify issue was added to project
  - Go to issue in repository
  - Look for "Projects" tab on right side
  - Should show "HELIOS Platform"
  - If missing: issue never added

Step 2: Check if added but hidden by filters
  - Open board
  - Look for active filters (blue Filter icon)
  - Clear all filters
  - Look for issue again

Step 3: Verify issue meets view criteria
  - Check which view you're using
  - View filters by component, phase, etc.
  - Issue might be in different view
  - Try "By Status" view first
```

### Solutions

**Add Issue to Project:**

```
1. Open issue in repository
2. Right side panel → Projects
3. Click "Add to project"
4. Select "HELIOS Platform"
5. Click "Add"
6. Wait 10 seconds for sync
7. Go back to board and refresh
```

**Clear Filters:**

```
1. Open board
2. Look for Filter icon (funnel shape)
3. If blue: filters active
4. Click to open filter panel
5. Click X next to each filter
6. Issue should appear now
```

**Try Different View:**

```
1. If not in By Component view
2. Try "By Status" view
3. Issue might be in different column
4. Look in all columns
5. By Status is most inclusive
```

### If Still Not Visible

```
1. Try browser refresh (Ctrl+F5)
2. Try different browser
3. Check permission: Repository Collaborator?
4. File issue: @board-admin
   Title: "Issue #XXX not appearing on board"
   Details: Issue number, when created, what you tried
```

---

## Status Not Updating When PR Created

### Symptoms

- Created PR linked to issue
- Issue still in "In Progress" or wrong column
- Manual column move required
- Automation didn't trigger

### Diagnosis Steps

```
Step 1: Verify PR is linked correctly
  - Open issue
  - Scroll down to see PR link
  - Should show "Fixes #XXX" in PR
  - Check exact format in PR description

Step 2: Check PR status
  - Is PR actually merged?
  - Or is it still "open/draft"?
  - Automation moves column based on status
  - Merged = Done (if criteria met)

Step 3: Check automation logs
  - Go to repository Actions tab
  - Look for "Board Automation" workflow
  - Find run for your PR
  - Check if it succeeded or failed
```

### Solutions

**Link PR Correctly:**

```
In your PR Description, include:
  Fixes #456

Not:
  Fixes issue 456
  Related to #456 (doesn't trigger automation)
  See #456

PR auto-detection looks for "Fixes #" pattern
```

**Manual Column Move:**

```
If automation failed:
1. Open issue on board
2. Drag issue to correct column
3. Drag from card to target column
4. Release to drop

Then:
1. Check what went wrong
2. Ensure PR is linked
3. Try again or contact admin
```

**Force Automation Retry:**

```
1. Go to Actions tab
2. Find Board Automation workflow
3. Find failed run for your PR
4. Click "Re-run jobs"
5. Check if succeeds this time
```

### If Still Not Working

```
1. Manually update fields in project
2. Document issue: @board-admin
   Title: "Automation not updating status"
   Details: PR #XXX, issue #YYY, what happened
3. Will investigate and fix
```

---

## Custom Fields Not Auto-Populating

### Symptoms

- Applied label but field not auto-filled
- Component not set automatically
- Priority not assigned
- Tier not calculated

### Diagnosis Steps

```
Step 1: Verify labels applied
  - Open issue in repository
  - Check Labels section
  - Look for phase-*, component-* labels
  - If missing: that's the problem

Step 2: Check label spelling
  - Labels are case-sensitive
  - "Phase-1" ≠ "phase-1" (won't match)
  - Check Against documentation
  - Ensure exact spelling

Step 3: Check automation running
  - Go to Actions tab
  - Search for "Auto-Assign" workflow
  - See if it ran when label added
  - Check if succeeded or errored
```

### Solutions

**Apply Correct Labels:**

```
For Phase 1 assignment:
  Use: phase-1 (lowercase, no quotes)

For Component:
  Use: component-monado
       component-security
       component-ai
       component-gui
       component-agents
       component-hub
       component-stack

Labels must be exact - check label list in repo
```

**Manually Set Fields (temporary):**

```
1. Open issue in project view
2. Find field on right panel
3. Click dropdown
4. Select value manually
5. Auto-saves

This is temporary - labels still recommended
```

**Verify Labels Exist:**

```
1. Go to repository Settings
2. Click Labels
3. Search for your label
4. If missing: create it first
5. Then apply to issue
```

### If Still Having Issues

```
1. Try creating new issue with labels from scratch
2. If new one works: old issue is stuck (contact admin)
3. If new one fails: label doesn't exist or misspelled
4. Report: @board-admin with details
```

---

## Automation Rules Not Triggering

### Symptoms

- Fields not auto-updating
- Columns not auto-moving
- Tier not auto-assigned
- Multiple tries haven't worked

### Common Causes & Fixes

**Rule 1: Phase Assignment Not Triggering**

```
✓ Check: Label applied? (phase-*, component-*)
✓ Check: Spelled correctly? (case-sensitive)
✓ Check: Label exists in repo?

Fix:
1. Apply label with correct spelling
2. If label doesn't exist: create first
3. Apply to issue
4. Wait 10 seconds for sync
5. Refresh page

If still not working:
- Re-apply label (might have cached)
- Try different label first
- Report if persists
```

**Rule 2: PR Status Sync Not Triggering**

```
✓ Check: PR linked in issue? (Fixes #XXX)
✓ Check: Linked correctly? (Not "related to")
✓ Check: PR is merged? (not just approved)

Fix:
1. Ensure PR body has "Fixes #456"
2. PR must be merged (not draft/open)
3. Wait 2-3 minutes for automation
4. Manually move if urgent
5. Report if persistent
```

**Rule 3: Auto-Done Not Triggering**

```
✓ Check: Issue in "Review" column?
✓ Check: All checkboxes checked?
✓ Check: PR merged?
✓ Check: No open conversations?

Fix:
1. Verify issue in Review column
2. Check ALL acceptance criteria
3. Resolve open comments
4. Merge PR
5. Refresh board
6. Manually move if needed
```

**Rule 4: Tier Assignment Not Working**

```
✓ Check: Component set?
✓ Check: Priority set?
✓ Check: Effort estimate if applicable?

Fix:
1. Set Component field first
2. Set Priority if critical
3. Set Effort if >= 5
4. Wait 10 seconds
5. Manually set tier if not auto-assigned
```

### Debug Procedures

**Check Automation Logs:**

```
1. Repository → Actions tab
2. Look for "Board Automation" workflow
3. Click on recent runs
4. Find run for your issue/PR
5. Click to see details
6. Look for error messages
7. Most common: label not found or typo
```

**Manual Trigger:**

```
To manually trigger automation:
1. Remove then re-add label
2. This forces automation to run
3. Wait 10 seconds
4. Check if worked

Or:
1. Go to Actions
2. Find workflow
3. Click "Re-run" button
```

---

## Board View Not Loading or Displaying Correctly

### Symptoms

- View takes too long to load
- Issues not showing in view
- View stuck/frozen
- Drag-and-drop not working

### Solutions

**View Won't Load:**

```
1. Refresh browser (F5)
2. Clear browser cache (Ctrl+Shift+Del)
3. Try incognito mode
4. Try different browser
5. Try mobile app

If still not loading:
1. Go to simpler view (By Status)
2. Try to load that
3. If works: issue is with specific view
4. File report with view name
```

**Issues Not Showing:**

```
1. Check active filters (blue Filter icon)
2. Clear all filters
3. Try different view
4. Issue might be in different column
5. Try "By Status" view first

If specific issue missing:
1. Search for it (Ctrl+F)
2. Check that view includes issue's phase/component
3. Check issue actually added to project
```

**Drag-and-Drop Not Working:**

```
1. Try table view instead of board view
2. Click issue to open details
3. Manually update column field
4. Or try different view
5. Refresh browser if persists
```

**View Performance:**

```
If view is slow:
1. Clear filters to reduce items
2. Group by component to organize
3. Try table view (faster than board)
4. Archive completed items (>30 days)
5. Contact admin if persistent
```

---

## Permission & Access Issues

### Symptoms

- Can't see board
- Can't edit issue
- Can't add label
- Can't assign people

### Solutions

**Can't See Board:**

```
1. Check: Are you a collaborator on repo?
   Settings → Collaborators
   If not: Ask repo admin to add you

2. Check: Have you accepted invitation?
   GitHub → Settings → Invitations
   If pending: Accept invitation

3. Check: Is repo public?
   If private: Must be collaborator

4. Try: GitHub Settings → Authorizations
   Re-authorize if needed
```

**Can't Edit Issue:**

```
1. Check: Are you collaborator? (see above)
2. Check: Is issue locked?
   Issues can be locked (shows lock icon)
   If locked: Only can comment
3. Check: Do you have write permission?
   Should be default for collaborators
4. Ask repo admin to grant write access
```

**Can't Assign People:**

```
1. Check: Are they collaborators?
   If not: Add them to repository first
2. Check: Have they accepted invitation?
3. Check: Can you assign yourself?
   If not: Permission issue
4. Contact repo admin
```

---

## Automation Failure Recovery

### When Automation Fails

```
Step 1: Identify failure
  - Go to Actions tab
  - Find failing workflow run
  - Click to see error details
  - Note the error message

Step 2: Understand the cause
  - Common: Label not found
  - Common: Permission denied
  - Common: Field not exists
  - See error details

Step 3: Fix the issue
  - Correct the label spelling
  - Re-apply the label
  - Wait for retry
  - Or manually set field

Step 4: Report if needed
  - If recurring issue
  - If different error
  - Include error message
  - Report to @board-admin
```

### Manual Workarounds

```
If automation stuck:

For field not updating:
1. Open issue in project
2. Click field on right panel
3. Manually select value
4. Auto-saves

For status not moving:
1. Click issue on board
2. Drag to correct column
3. Released to drop
4. Field updates manually

For PR link not working:
1. Find PR URL
2. Add comment to issue:
   "Related: [PR URL]"
3. Manual reference until fixed
```

---

## Getting Additional Help

### Reporting an Issue

**Template for Board Admin:**

```
Title: [Issue Type] - Brief description

Type: Bug / Performance / Enhancement / Question

Description:
[What were you trying to do?]

Steps to Reproduce:
1. [First step]
2. [Second step]
3. [Third step]

Expected Result:
[What should happen]

Actual Result:
[What actually happened]

Attachments:
[Screenshots if helpful]
[Error messages]

Contact: [Your Slack handle]
```

### Where to Get Help

**Slack:** #project-board channel

- Quick questions
- General usage help
- Tips and tricks

**GitHub Issues:** DevOps repo

- Technical issues
- Bug reports
- Feature requests

**Email:** board-admin@company.com

- Urgent issues
- Access problems
- Formal complaints

**Wiki:** Team's GitHub Wiki

- Documented workflows
- Team-specific guides
- Best practices

---

## Prevention Tips

### Avoid Common Problems

**When Creating Issues:**

- ✓ Apply labels immediately (phase-*, component-*)
- ✓ Set priority to enable automation
- ✓ Use clear titles and descriptions
- ✓ Add acceptance criteria

**When Creating PRs:**

- ✓ Include "Fixes #XXX" in description
- ✓ Link to main issue
- ✓ Request specific reviewers
- ✓ Describe changes clearly

**When Working on Board:**

- ✓ Keep status updated
- ✓ Move issues through workflow
- ✓ Flag blockers immediately
- ✓ Don't let issues stall

**For Team:**

- ✓ Regular check-ins on blocked items
- ✓ Review metrics weekly
- ✓ Provide feedback on process
- ✓ Suggest improvements

---

**Document Control:**

- Version: 1.0
- Last Updated: 2026-04-13
- Common Issues Covered: 10+
- Status: Production Ready

For issues not covered here, ask in #project-board or contact @board-admin.
