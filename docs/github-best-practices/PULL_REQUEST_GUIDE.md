# Pull Request Guidelines for HELIOS Platform

Complete guide to creating, reviewing, and merging pull requests effectively.

---

## Table of Contents

1. [PR Title Format](#pr-title-format)
2. [PR Description Template](#pr-description-template)
3. [Testing Requirements](#testing-requirements)
4. [Review Expectations](#review-expectations)
5. [Approval Process](#approval-process)
6. [Merge Strategy](#merge-strategy)
7. [Post-Merge Cleanup](#post-merge-cleanup)

---

## PR Title Format

### Title Structure

Follow this format:

```
<type>(<scope>): <subject> | Fixes #<issue-number>
```

### Title Examples

**✓ Good Titles:**

```
feat(auth): implement JWT token validation | Fixes #234
fix(dashboard): resolve widget overlap on mobile | Fixes #567
docs(api): add webhook documentation | Fixes #890
refactor(database): extract connection pooling | Related to #345
perf(search): optimize query with indexing | Fixes #123
test(components): add Button component tests
ci(workflows): add performance benchmarks
chore(deps): upgrade React to 18.2.0
```

**✗ Bad Titles:**

```
fixes stuff
update file
work in progress
changes
dashboard fix
Implement feature
Updated multiple files
Another hotfix
```

### Title Rules

```markdown
✓ Keep under 72 characters
✓ Use lowercase (except proper nouns)
✓ Start with type: feat, fix, docs, refactor, perf, test, ci, chore
✓ Include scope in parentheses
✓ End with issue reference: | Fixes #123
✓ Use imperative mood
✓ Be specific about what changed

✗ Don't use periods at the end
✗ Don't capitalize first letter
✗ Don't write complete sentences
✗ Don't be vague (e.g., "fix bugs")
```

---

## PR Description Template

### Template Structure

```markdown
## Description
Brief explanation of what this PR does.

## Motivation
Why are these changes needed? What problem does it solve?

## Changes Made
- Specific change 1
- Specific change 2
- Specific change 3

## Testing
- [ ] Test 1 - Verified behavior X
- [ ] Test 2 - Verified behavior Y
- [ ] Added unit tests
- [ ] Added integration tests
- [ ] Manual testing completed

## Checklist
- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Comments added for complex logic
- [ ] Documentation updated
- [ ] No breaking changes (or documented)
- [ ] Tests pass locally
- [ ] No console errors/warnings

## Related Issues
Fixes #234
Relates to #567
Unblocks #890

## Deployment Notes
Any special deployment instructions or concerns.

## Screenshots
If applicable, add before/after screenshots.
```

### Template Example

```markdown
## Description
Implemented JWT token validation for all API endpoints. The validation
checks token signature and expiration time on every request before
processing.

## Motivation
Current implementation skips token validation in some edge cases,
creating security vulnerability. This fix ensures all requests are
properly validated.

## Changes Made
- Added `validateToken()` method to AuthService
- Added `TokenExpiredError` exception class
- Updated API middleware to validate all requests
- Added retry logic for transient validation failures
- Created comprehensive unit tests

## Testing
- [x] Unit tests added (validateToken, error handling)
- [x] Integration tests with mock JWT tokens
- [x] Manual testing on staging environment
- [x] Verified backward compatibility

## Checklist
- [x] Code follows style guidelines
- [x] Self-review completed
- [x] Comments added for token validation logic
- [x] API documentation updated
- [x] No breaking changes
- [x] All tests pass (95% coverage)
- [x] No console errors or warnings

## Related Issues
Fixes #234 (Token validation)
Relates to #567 (Security audit)
Unblocks #890 (Auth feature)

## Deployment Notes
No special deployment steps needed. Can be deployed with existing
database. Token validation enabled by default but can be disabled
via AUTH_VALIDATE_TOKENS environment variable if needed.

## Screenshots
Before: Requests processed without token validation
After: All requests validated before processing
```

---

## Testing Requirements

### Unit Tests

**Required for:**

- New functions/methods
- Modified existing logic
- Bug fixes
- Edge cases

**Example:**

```typescript
describe('AuthService.validateToken', () => {
  it('should validate valid token', () => {
    const token = createValidToken();
    expect(() => authService.validateToken(token)).not.toThrow();
  });

  it('should throw on expired token', () => {
    const token = createExpiredToken();
    expect(() => authService.validateToken(token)).toThrow(TokenExpiredError);
  });

  it('should throw on invalid signature', () => {
    const token = createTokenWithBadSignature();
    expect(() => authService.validateToken(token)).toThrow(InvalidTokenError);
  });

  it('should handle null token', () => {
    expect(() => authService.validateToken(null)).toThrow();
  });
});
```

### Integration Tests

**Required for:**

- Multi-component interactions
- API endpoints
- Database operations
- External service calls

**Example:**

```typescript
describe('API Token Validation', () => {
  it('should reject request without token', async () => {
    const response = await request(app)
      .get('/api/users')
      .expect(401);
  });

  it('should accept request with valid token', async () => {
    const token = createValidToken();
    const response = await request(app)
      .get('/api/users')
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
  });

  it('should reject request with expired token', async () => {
    const token = createExpiredToken();
    const response = await request(app)
      .get('/api/users')
      .set('Authorization', `Bearer ${token}`)
      .expect(401);
  });
});
```

### Test Coverage

**Minimum requirements:**

- New code: 80% coverage
- Modified code: 80% coverage
- Overall: No decrease in project coverage

**Verify coverage:**

```bash
npm test -- --coverage
# Should show 80%+ for new/modified files
```

### Manual Testing Checklist

```markdown
Before submitting PR:
□ Feature works as expected
□ UI responsive on mobile/tablet/desktop
□ No console errors or warnings
□ Error handling works correctly
□ Edge cases handled
□ Backward compatibility verified (if applicable)
□ Performance acceptable
□ Accessibility checked
□ No hardcoded values/debug code left
```

---

## Review Expectations

### Reviewer Response Time

| Priority | Response Time | Must Have |
|----------|---------------|-----------|
| Critical | < 2 hours | 2 reviewers |
| High | < 4 hours | 2 reviewers |
| Normal | < 24 hours | 1 reviewer |
| Low | < 48 hours | 1 reviewer |

### What Reviewers Check

**Functionality:**

```markdown
□ Code does what PR description says
□ Feature works as expected
□ No obvious bugs or logic errors
□ Edge cases handled
□ Error handling appropriate
```

**Code Quality:**

```markdown
□ Code is clean and readable
□ Follows project style guide
□ No unnecessary duplication
□ Comments explain why, not what
□ Functions are focused (single responsibility)
□ Variable/function names are clear
```

**Testing:**

```markdown
□ Tests exist for new code
□ Tests pass locally
□ Test coverage adequate (80%+)
□ Edge cases covered
□ No brittle or flaky tests
```

**Documentation:**

```markdown
□ README/docs updated if needed
□ API documentation current
□ Comments added for complex logic
□ Inline documentation is clear
□ Examples provided if applicable
```

**Security:**

```markdown
□ No hardcoded credentials
□ Input properly validated
□ SQL injection prevention
□ XSS prevention
□ Authentication checks
□ Authorization checks
□ Sensitive data encrypted
```

**Performance:**

```markdown
□ No obvious performance issues
□ Database queries optimized
□ No memory leaks
□ Reasonable algorithm complexity
□ Caching utilized where appropriate
```

### Reviewer Comment Types

**Request Change (Required):**

```markdown
Request change
"This function needs null checking."
→ Author must fix before merge
```

**Suggestion (Nice to Have):**

```markdown
Suggestion
"Consider extracting this to a utility function."
→ Author can accept or decline
```

**Question (Clarification):**

```markdown
Question
"Why did you choose this approach over X?"
→ Author explains decision
```

**Praise (Recognition):**

```markdown
Praise
"Great solution! Very clean implementation."
→ Recognition and feedback
```

---

## Approval Process

### PR Review Workflow

**Step 1: Create and Submit**

```markdown
1. Create PR with complete description
2. Link related issues
3. Request 2 reviewers (or 1 for low-priority)
4. Ensure all checks pass
5. Wait for reviews
```

**Step 2: Initial Review**

```markdown
1. Reviewer(s) read PR description
2. Review code changes
3. Run tests locally (if needed)
4. Request changes or approve
5. Provide constructive feedback
```

**Step 3: Author Responds**

```markdown
1. Read review feedback
2. Discuss any disagreements
3. Make requested changes
4. Commit with clear message
5. Push and request re-review
```

**Step 4: Final Approval**

```markdown
1. Reviewer(s) verify changes
2. Re-approve PR
3. Check all boxes are checked
4. Approve merge (if authorized)
```

**Step 5: Merge**

```markdown
1. Ensure branch is up-to-date
2. Click merge button (squash commits)
3. Delete feature branch
4. Verify deployment
```

### Approval Tiers

**Tier 1: Any Reviewer (Documentation, Comments)**

```markdown
- README updates
- Documentation corrections
- Comment improvements
- Example code
- Non-breaking refactors

Minimum approvals: 1
```

**Tier 2: Core Team (Features, Fixes)**

```markdown
- New features
- Bug fixes
- Code improvements
- Test additions
- Dependency updates

Minimum approvals: 1 (must be core team)
```

**Tier 3: Multiple Reviewers (Critical Changes)**

```markdown
- API changes
- Security changes
- Database schema changes
- Breaking changes
- Performance-critical code

Minimum approvals: 2 (including specialists)
```

**Tier 4: Lead Approval (Major Changes)**

```markdown
- Architecture changes
- Major refactoring
- Version releases
- Critical security fixes

Minimum approvals: 2 (including tech lead)
```

### Dispute Resolution

If reviewer and author disagree:

```markdown
1. Discuss in PR comments
2. Reference design docs/decisions
3. Escalate to @tech-lead if no consensus
4. Tech lead makes final decision
5. Document decision in comment
6. Move forward (no grudges)

Example:
Reviewer: "Use async/await instead of promises"
Author: "Promises work, but async/await is cleaner"
Tech Lead: "Agreed. Use async/await for consistency."
→ Author updates code, gets approved
```

---

## Merge Strategy

### Merge Options

**Option 1: Squash and Merge (RECOMMENDED)**

```
Advantages:
- Clean linear history
- One commit per feature
- Easy to revert if needed
- Clear commit messages

Use for: Most PRs (features, fixes, docs)

Result in main:
- One commit: "feat(auth): add token validation"
- All changes combined
```

**Option 2: Rebase and Merge**

```
Advantages:
- Linear history
- Keeps individual commits
- Clear atomic commits

Use for: Multi-commit PRs with logical separation

Result in main:
- Commit 1: "feat(auth): create TokenValidator class"
- Commit 2: "feat(auth): add validation middleware"
- Commit 3: "test(auth): add unit tests"
```

**Option 3: Create Merge Commit (NOT RECOMMENDED)**

```
Advantages:
- Preserves branch history

Disadvantages:
- Clutters history with merge commits
- Harder to bisect bugs

Use for: Only if explicitly needed

Result in main:
- Merge commit: "Merge pull request #234"
- Plus all original commits
```

### Merge Checklist

Before merging, verify:

```markdown
□ PR title follows format
□ PR description is complete
□ All tests pass
□ All checks pass (CI/CD)
□ Code review approved
□ Branch is up-to-date with base branch
□ No conflicts
□ No console errors/warnings
□ Documentation updated
□ Related issues linked
□ Breaking changes documented
□ Deployment instructions clear
```

### Squash Commit Best Practices

When squashing, the final commit message should be:

```markdown
✓ Clear and descriptive
✓ One logical change
✓ Follows conventional commit format
✓ Includes context for future debugging

Example squashed commit:
"feat(auth): implement JWT token validation with expiration checks"
```

---

## Post-Merge Cleanup

### After Merge Actions

```bash
# 1. Switch back to develop
git checkout develop

# 2. Pull latest changes
git pull origin develop

# 3. Verify merge succeeded
git log --oneline -5

# 4. Delete local feature branch
git branch -d feature/HELIOS-42-new-feature

# 5. Delete remote branch (usually auto-deleted)
git push origin --delete feature/HELIOS-42-new-feature
```

### Verify Deployment

```markdown
After merge:
□ Verify changes in develop
□ Monitor CI/CD pipeline
□ Check deployment logs
□ Verify no errors in staging
□ Run smoke tests
□ Monitor production after deploy
□ Alert team to changes
```

### Close Related Issues

```markdown
If not auto-closed:
1. Go to linked issue
2. Leave comment: "Fixed in PR #456"
3. Click "Close issue"
4. Or use: "Closes #issue-number" in PR description
```

### Update Documentation

```markdown
After merge:
□ Update CHANGELOG.md
□ Update version number if needed
□ Update API documentation
□ Update user-facing docs
□ Create release notes
□ Post announcement to team
```

### Monitor for Issues

```markdown
First 24 hours after merge:
□ Watch error logs
□ Monitor performance metrics
□ Check user reports
□ Be ready to rollback if needed
□ Respond to any issues quickly
```

---

## PR Anti-Patterns to Avoid

### ✗ Too Large PRs

```markdown
Problem: PR with 50+ files changed
- Hard to review thoroughly
- Takes longer to review
- Higher chance of bugs

Solution: Break into smaller PRs
- One feature per PR
- Aim for < 400 lines changed
- Group related changes only
```

### ✗ Missing Description

```markdown
Problem: PR with no description
- Reviewers don't know what changed
- Hard to understand purpose

Solution: Always fill PR template
- Explain what and why
- Link related issues
- Add test notes
```

### ✗ Outdated Branch

```markdown
Problem: Feature branch 10 commits behind develop
- Merge conflicts
- Old base
- Inconsistent behavior

Solution: Keep branch updated
- Rebase weekly
- Before submitting PR
- Merge conflicts addressed
```

### ✗ No Tests

```markdown
Problem: PR with code changes but no tests
- No verification of behavior
- Regressions possible
- Hard to maintain

Solution: Always add tests
- 80% coverage minimum
- Test happy path and edge cases
- Include error handling tests
```

### ✗ Mixing Unrelated Changes

```markdown
Problem: PR mixing feature, refactor, and style fixes
- Hard to review
- Hard to revert specific changes
- Unclear purpose

Solution: One concern per PR
- Feature PR = feature only
- Refactor PR = refactor only
- Style PR = style only
```

---

## PR Best Practices Checklist

```markdown
Before Creating PR:
□ Tested locally (npm test)
□ No console errors/warnings
□ No debug code left
□ Commit messages clear
□ Branch up-to-date
□ No unnecessary files changed

Creating PR:
□ Title follows format
□ Description complete
□ Issues linked
□ Tests included
□ Documentation updated
□ Reviewers requested
□ All checks passing

During Review:
□ Respond within 12 hours
□ Address all feedback
□ Ask for clarification if needed
□ Request re-review when ready
□ Don't dismiss feedback without discussion

After Merge:
□ Delete feature branch
□ Update docs if needed
□ Close related issues
□ Monitor deployment
□ Thank reviewers
```

---

**Last Updated:** April 2026  
**Version:** 1.0

See also: [CODE_REVIEW_STANDARDS.md](CODE_REVIEW_STANDARDS.md), [GITHUB_BEST_PRACTICES.md](GITHUB_BEST_PRACTICES.md)
