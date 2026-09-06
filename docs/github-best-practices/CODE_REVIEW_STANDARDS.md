# Code Review Standards for HELIOS Platform

Standards and best practices for conducting and receiving code reviews.

---

## Table of Contents

1. [Review Checklist](#review-checklist)
2. [Comment Types](#comment-types)
3. [Approval Criteria](#approval-criteria)
4. [Response Timeframes](#response-timeframes)
5. [Conflict Resolution](#conflict-resolution)
6. [Approval Process](#approval-process)
7. [Anti-Patterns](#anti-patterns-to-avoid)

---

## Review Checklist

### Functionality Review

**Does the code do what it's supposed to do?**

```markdown
□ Feature implements requirements as described in PR
□ All acceptance criteria are met
□ Behavior matches PR description
□ No obvious bugs or logic errors
□ Error cases are handled properly
□ Edge cases are handled
□ Backward compatibility maintained (or documented)
□ No side effects or unintended consequences

Reviewer questions to ask:
- What does this code do?
- Does it match the description?
- Are there any edge cases I'm missing?
- What happens when inputs are invalid?
- Could this break existing functionality?
```

### Code Quality Review

**Is the code maintainable and readable?**

```markdown
□ Code is clean and readable
□ Follows project coding standards
□ No unnecessary duplication
□ Functions are focused (single responsibility)
□ Classes have clear purpose
□ Variable/function names are descriptive
□ Comments explain WHY, not WHAT (code explains what)
□ Complex logic is commented
□ Magic numbers explained or extracted
□ No dead code or commented-out code
□ Proper error handling

Code smell checklist:
□ Function not too long (< 50 lines)
□ Function not too many parameters (< 4)
□ No deeply nested conditionals
□ No duplicate code blocks
□ No overly complex logic
□ Names are self-documenting
```

### Testing Review

**Are the changes properly tested?**

```markdown
□ Tests exist for new functionality
□ Tests pass locally
□ Test coverage adequate (80%+)
□ Tests cover happy path
□ Tests cover error cases
□ Tests cover edge cases
□ No brittle or flaky tests
□ Tests are maintainable
□ Mocking is appropriate
□ No redundant tests

Testing questions:
- What are all the ways this code could fail?
- Are those cases tested?
- Are tests verifying behavior or implementation?
- Could these tests be more focused?
```

### Documentation Review

**Is the code properly documented?**

```markdown
□ README/docs updated if applicable
□ API documentation current
□ Functions have JSDoc comments (for public APIs)
□ Complex algorithms explained
□ Non-obvious decisions documented
□ Examples provided if needed
□ Configuration options documented
□ Breaking changes clearly marked
□ Migration guide provided (if breaking)

Documentation questions:
- Would a new team member understand this?
- Are assumptions documented?
- Are there examples?
- Is API behavior clear?
```

### Security Review

**Are there security vulnerabilities?**

```markdown
□ No hardcoded secrets or credentials
□ Input validation present and correct
□ Output properly escaped (XSS prevention)
□ SQL queries parameterized (SQL injection prevention)
□ Authentication required where needed
□ Authorization checks in place
□ Sensitive data encrypted
□ Error handling doesn't leak information
□ Rate limiting implemented (if needed)
□ CSRF protection enabled (if needed)
□ Dependency versions secure

Security questions:
- Could this be exploited?
- Are inputs validated?
- Are outputs sanitized?
- Is sensitive data exposed?
- Are authentication/authorization correct?
```

### Performance Review

**Does the code perform acceptably?**

```markdown
□ No obvious performance issues
□ Database queries optimized
□ Appropriate algorithms used (O(n) complexity acceptable)
□ Caching utilized where appropriate
□ No memory leaks
□ No infinite loops
□ No unnecessary iterations
□ Asynchronous operations where needed
□ No blocking operations in hot paths

Performance questions:
- How does this scale?
- Any potential bottlenecks?
- Could this be optimized?
- Is caching appropriate here?
```

---

## Comment Types

### Request Change (🔴 Required Fix)

**When:** There's a problem that must be fixed before merge

```markdown
# Comment format
**Request change**: [Brief description]

[Detailed explanation]

Example code:
```

**Example:**

```markdown
Request change: Add null check for token parameter

The validateToken function doesn't check if token is null,
which will cause a crash if called without argument.

Should be:
```typescript
function validateToken(token) {
  if (!token) {
    throw new Error('Token required');
  }
  // ... rest of validation
}
```

Current code will fail if token is null or undefined.

```

**Author must:**
- [ ] Fix the issue
- [ ] Commit with clear message
- [ ] Request re-review
- [ ] Not merge without addressing

---

### Suggestion (💡 Nice to Have)

**When:** Improvement or alternative approach (not required)

```markdown
# Comment format
**Suggestion**: [Brief description]

[Alternative approach or improvement]
```

**Example:**

```markdown
Suggestion: Consider extracting this to a separate function

This block of code handles email validation. Since it's
reusable, consider moving it to a utility:

```typescript
// src/utils/validators.ts
export function validateEmail(email: string): boolean {
  const pattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return pattern.test(email);
}
```

Would improve reusability and testability.

```

**Author can:**
- [ ] Accept and implement
- [ ] Decline and explain why
- [ ] Ask for more details

---

### Question (❓ Clarification)

**When:** Something is unclear or needs explanation

```markdown
# Comment format
**Question**: [What you're confused about]

[Context of confusion]
```

**Example:**

```markdown
Question: Why use async/await here instead of promises?

I see you're using async/await for the database query.
The old code used .then(). What's the advantage?
Is it just style preference or is there a functional difference?
```

**Author should:**

- [ ] Explain the decision
- [ ] Reference documentation if relevant
- [ ] Clarify any confusion

---

### Praise (⭐ Recognition)

**When:** Acknowledging good code or clever solution

```markdown
# Comment format
**Great work**: [What you appreciate]

[Why it's good]
```

**Example:**

```markdown
Great work: Really clean error handling approach

The way you're handling token expiration with exponential
backoff is very elegant. Makes the code more resilient and
the error handling is very readable.
```

**Purpose:**

- Motivate team members
- Reinforce good practices
- Create positive code review culture

---

## Approval Criteria

### ✓ Approve When

```markdown
Functionality:
✓ Code implements requirements correctly
✓ All acceptance criteria met
✓ No obvious bugs or issues

Quality:
✓ Code follows style guidelines
✓ Properly structured and organized
✓ Names are clear and descriptive
✓ No unnecessary duplication
✓ Comments explain complex logic

Testing:
✓ Tests exist for changes
✓ Tests pass locally
✓ Coverage adequate (80%+)
✓ Edge cases covered

Documentation:
✓ Docs updated as needed
✓ API documentation current
✓ Comments sufficient

Security:
✓ No security vulnerabilities
✓ No secrets hardcoded
✓ Input validation present
✓ Authorization checks in place

Performance:
✓ No obvious performance issues
✓ Algorithms appropriate
✓ Database queries optimized

ALSO: All automated checks pass (CI/CD)
```

### ✗ Request Changes When

```markdown
Never approve if:
✗ Code doesn't implement requirements
✗ Tests are missing
✗ Security vulnerabilities present
✗ Hardcoded credentials found
✗ Code style violated
✗ Documentation missing
✗ Performance concerns
✗ Merge conflicts exist
✗ Branch not up-to-date
✗ Automated checks failing

Examples requiring changes:
✗ "Add null check for this parameter"
✗ "Remove hardcoded API key"
✗ "Add tests for error case"
✗ "Update documentation"
✗ "Rebase to resolve conflicts"
```

### Approval Levels

**Tier 1: Standard Approval**

```
Criteria:
- No critical issues
- Code quality acceptable
- Tests adequate
- No security concerns

Result: Ready to merge
```

**Tier 2: Conditional Approval**

```
Criteria:
- Approved with minor notes
- Author should address suggestions
- Don't block merge, but encourage fixes

Comment:
"Approved with suggestions. See comments above."
```

**Tier 3: Request Changes**

```
Criteria:
- Issues that must be fixed
- Author must address before merge
- Re-review required

Result: DO NOT MERGE until addressed
```

---

## Response Timeframes

### Reviewer Responsibilities

| Task | Timeline | Severity |
|------|----------|----------|
| Acknowledge review request | < 2 hours | All |
| Initial feedback | < 24 hours | All |
| Re-review after changes | < 12 hours | All |
| Final approval/decision | < 24 hours | All |

**Acknowledgment:**

```markdown
Within 2 hours of being assigned to review:
"Reviewing this now" or "Will review by [time]"
```

**Initial Feedback:**

```markdown
Within 24 hours:
Post initial thoughts, even if not complete
"Initial review done, a few more questions"
```

**Response to Changes:**

```markdown
Within 12 hours of author pushing changes:
Re-review and provide feedback or approve
```

### Author Responsibilities

| Task | Timeline | Severity |
|------|----------|----------|
| Read feedback | < 4 hours | Critical |
| Read feedback | < 8 hours | High |
| Read feedback | < 24 hours | Normal |
| Respond to feedback | < 12 hours | All |
| Make requested changes | < 24 hours | All |
| Request re-review | Immediately after changes | All |

**Reading Feedback:**

```markdown
✓ Read review comments promptly
✓ Ask for clarification if needed
✓ Don't dismiss feedback without discussion
```

**Responding to Feedback:**

```markdown
✓ Comment on each suggestion:
  "Done in commit abc123"
  "Disagree because... [reason]"
  "Updated as requested"
  "Good point, implemented"
```

**Requesting Re-review:**

```markdown
✓ After addressing feedback
✓ Click "Request review" button
✓ Leave comment: "Addressed feedback, ready for re-review"
```

---

## Conflict Resolution

### When Author and Reviewer Disagree

**Scenario 1: Different Approach**

```markdown
Reviewer: "Use Map instead of object for performance"
Author: "Object is simpler and performance is fine here"

Resolution:
1. Author explains use case
2. Reviewer provides benchmark data
3. Discuss in comment thread
4. Reference architecture guidelines
5. Tech lead decides if deadlocked
6. Document decision for future reference

Example resolution:
"After discussion, agreed to use Map for consistency
with rest of codebase, even though object performs fine
for this use case."
```

**Scenario 2: Style Difference**

```markdown
Reviewer: "Function too long, break into smaller pieces"
Author: "Function is clear as-is, breaking it up won't help"

Resolution:
1. Check project style guide
2. Point to similar code in project
3. Accept if already follows standard
4. Request if violates standard
5. Escalate if no precedent

Example resolution:
"Checked similar functions - they average 40 lines.
This is 85 lines. Can we break into 2-3 functions?"
```

**Scenario 3: Architecture Decision**

```markdown
Reviewer: "This should use service pattern"
Author: "Simpler to put logic directly in controller"

Resolution:
1. Document both approaches
2. Reference architecture docs
3. Discuss trade-offs
4. Tech lead makes decision
5. Follow decision for consistency

Example resolution:
"Agreed to use service pattern per architecture
guidelines. This keeps controllers thin and improves
testability."
```

### Escalation Path

```markdown
If disagreement can't be resolved:

Level 1: Discussion in PR comments
- Discuss approach
- Reference guidelines
- Provide evidence
- Remain respectful

Level 2: Call for third opinion
- Tag @tech-lead or relevant expert
- Provide context
- Let third party decide

Level 3: Tech Lead decides
- Tech lead makes final call
- Decision is final
- Document decision

Then: Move forward without grudges
```

### Disagreement Guidelines

```markdown
✓ Discuss respectfully and professionally
✓ Provide evidence and reasoning
✓ Reference project standards
✓ Ask questions instead of demands
✓ Accept when you're wrong
✓ Thank person for catching issues
✓ Move on after decision is made

✗ Don't dismiss concerns
✗ Don't insist without reason
✗ Don't be defensive
✗ Don't hold grudges
✗ Don't make it personal
✗ Don't override decisions
```

---

## Approval Process

### Standard PR Approval Flow

```
1. PR Created
   ↓
2. Reviewers Assigned
   ↓
3. Initial Review (24h)
   ├─ Approved → Go to 5
   └─ Changes Requested → Go to 4
   ↓
4. Author Responds & Updates
   ├─ Commit changes
   ├─ Push updates
   └─ Request re-review
   ↓
5. Re-review (12h)
   ├─ Approved → Go to 6
   └─ More changes → Go to 4
   ↓
6. Final Approval
   ├─ All checks pass → Merge ready
   └─ Issues remain → Hold
   ↓
7. Merge
   ├─ Squash commits
   ├─ Delete branch
   └─ Close related issues
```

### Multi-Reviewer Approval

**For PRs requiring 2 approvals:**

```markdown
Status: WAITING FOR APPROVALS (0/2)
├─ ✓ Reviewer 1: Approved
├─ ⏳ Reviewer 2: Reviewing
└─ ⏳ Reviewer 3: Awaiting assignment

After both approve:
Status: READY TO MERGE (2/2)
├─ ✓ Reviewer 1: Approved
├─ ✓ Reviewer 2: Approved
└─ Can merge when ready
```

### Handling Review Timeouts

```markdown
If no review after 24 hours (normal priority):
1. Leave comment: "Ping @reviewer1, ready for review"
2. After 48 hours, reach out in Slack
3. If critical (P1/P0): Escalate immediately
4. Assign backup reviewer

If author doesn't respond to feedback:
1. Leave comment: "Waiting on author response"
2. After 48 hours: "This PR will be closed if no response"
3. Close PR if still unresponsive (can reopen)
```

---

## Anti-Patterns to Avoid

### ✗ Rubber Stamping

```markdown
Problem: Approving without real review

Signs:
- "LGTM" (Looks Good To Me) with no comments
- Approval without reading changes
- Same reviewer always approves everything

Impact:
- Bugs slip through
- Code quality degrades
- False sense of safety

Solution:
- Read code carefully
- Actually run tests
- Provide constructive feedback
- Challenge assumptions
```

### ✗ Nitpicking Everything

```markdown
Problem: Commenting on trivial style issues

Signs:
- "Add space before brace"
- "Use different variable name"
- Dozens of minor comments

Impact:
- Demoralizes authors
- Slows down development
- Creates negative culture

Solution:
- Focus on substance
- Let linters handle style
- Distinguish style from logic
- Be selective with comments
```

### ✗ Dismissing Feedback

```markdown
Problem: Author ignores valid concerns

Signs:
- Comments ignored without response
- Code merged despite objections
- "I don't think this is important"

Impact:
- Bugs in production
- Reduced review effectiveness
- Loss of knowledge sharing

Solution:
- Address all feedback
- Ask for clarification
- Explain disagreements
- Don't merge over objections
```

### ✗ Incomplete Reviews

```markdown
Problem: Only looking at some of the code

Signs:
- "Didn't check tests"
- "Haven't looked at documentation"
- Only reviewed first few commits

Impact:
- Issues in untested code
- Incomplete implementation
- Missing documentation

Solution:
- Review all changes
- Check tests and docs
- Ask questions about unclear areas
- Don't approve incomplete reviews
```

### ✗ Personal Attacks

```markdown
Problem: Making feedback personal

Bad:
"You obviously don't understand this"
"Why would you write it this way?"
"This is so wrong"

Good:
"I think this could be clearer by..."
"Have you considered...?"
"This approach might have issues because..."

Solution:
- Focus on code, not person
- Assume good intent
- Be respectful always
- Help, don't criticize
```

---

## Review Etiquette

### As a Reviewer

```markdown
DO:
✓ Be respectful and constructive
✓ Ask questions, don't accuse
✓ Provide alternatives and suggestions
✓ Praise good code and solutions
✓ Explain your reasoning
✓ Respond promptly
✓ Think about author's perspective
✓ Share knowledge and best practices

DON'T:
✗ Be dismissive or harsh
✗ Make it personal
✗ Assume bad intent
✗ Block on style preferences
✗ Comment without reading code
✗ Ignore author's responses
✗ Demand changes without explaining
✗ Use review as teaching opportunity for basics
```

### As an Author

```markdown
DO:
✓ Read feedback carefully
✓ Ask for clarification if confused
✓ Respond to all comments
✓ Thank reviewers for their time
✓ Accept feedback gracefully
✓ Update code promptly
✓ Learn from feedback
✓ Request re-review when ready

DON'T:
✗ Dismiss feedback without discussion
✗ Get defensive
✗ Ignore comments
✗ Merge over reviewer objections
✗ Be sarcastic or dismissive
✗ Leave feedback unaddressed
✗ Argue without substance
✗ Rush to merge
```

---

## Review Best Practices Checklist

### Before Starting Review

```markdown
□ Have 20+ minutes uninterrupted time
□ Calm and focused (not rushed)
□ Have necessary context (issue, PR description)
□ Have development environment ready
□ Have linter and tests available
```

### During Review

```markdown
□ Read PR description
□ Check for breaking changes
□ Review all changed files
□ Think about edge cases
□ Consider security implications
□ Test locally if possible
□ Run tests locally
□ Provide constructive feedback
□ Ask clarifying questions
```

### After Review

```markdown
□ Submit all feedback at once (not piece by piece)
□ Be available for questions
□ Re-review after changes
□ Approve or provide feedback
□ Don't approve hastily
```

---

**Last Updated:** April 2026  
**Version:** 1.0

See also: [PULL_REQUEST_GUIDE.md](PULL_REQUEST_GUIDE.md), [GITHUB_BEST_PRACTICES.md](GITHUB_BEST_PRACTICES.md)
