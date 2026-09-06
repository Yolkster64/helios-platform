# {{PROJECT_NAME}} - Contributing Guide

**Template Version:** 1.0  
**Last Updated:** {{LAST_UPDATED}}  
**Maintainer:** {{MAINTAINER_NAME}}

---

## 🤝 Welcome Contributors!

{{PROJECT_NAME}} is an open project and welcomes contributions from the community. Whether you're fixing bugs, adding features, or improving documentation, we appreciate your help!

---

## 🎯 Types of Contributions

### 🐛 Bug Reports

- Found a bug? Create an issue describing:
  - What you were trying to do
  - What happened instead
  - {{ENVIRONMENT_DETAILS}}
  - Steps to reproduce

### ✨ Feature Requests

- Have an idea? Submit a feature request with:
  - Use case and motivation
  - Proposed solution
  - Alternative approaches considered

### 📝 Documentation Improvements

- Spotted unclear docs? Send a PR to improve them
- Add examples or clarify existing content
- Fix typos or formatting

### 💻 Code Contributions

- Implement features or bug fixes
- Performance improvements
- Code refactoring
- Test coverage improvements

### 🧪 Testing

- Report test failures
- Add new test cases
- Improve test coverage
- Test on different environments

---

## 🚀 Getting Started as a Contributor

### Step 1: Fork & Clone

```powershell
# Fork the repository on GitHub
# {{GITHUB_INSTRUCTIONS}}

# Clone your fork
git clone {{YOUR_FORK_URL}}
cd {{PROJECT_DIRECTORY}}

# Add upstream remote
git remote add upstream {{ORIGINAL_REPO_URL}}
```

### Step 2: Set Up Development Environment

```powershell
# Install development dependencies
{{DEV_INSTALL_CMD}}

# Install git hooks
{{GIT_HOOKS_CMD}}

# Verify setup
{{VERIFY_DEV_SETUP_CMD}}
```

### Step 3: Create Feature Branch

```powershell
# Update from upstream
git fetch upstream
git checkout upstream/main

# Create feature branch
git checkout -b feature/{{FEATURE_NAME}}
# or
git checkout -b fix/{{BUG_NAME}}
```

---

## 💻 Development Workflow

### Code Style & Standards

#### Style Guidelines

- **Language**: {{PRIMARY_LANGUAGE}}
- **Formatting**: {{FORMATTER_TOOL}} (automatically applied)
- **Linting**: {{LINTER_TOOL}} (errors must be fixed)
- **Testing**: {{TEST_FRAMEWORK}} (must have tests)

#### PowerShell-Specific

```powershell
# Use explicit parameter names
Get-Service -Name "spooler"  # Good
Get-Service spooler           # Also acceptable

# Avoid aliases in scripts
Get-ChildItem                 # Good
ls                            # Avoid in production code

# Use proper error handling
try {
    {{OPERATION}}
} catch {
    Write-Error $_.Exception.Message
    exit 1
}

# Document complex functions
<#
.SYNOPSIS
Brief description

.DESCRIPTION
Detailed description

.PARAMETER Name
Parameter description

.EXAMPLE
Usage example

.NOTES
Additional notes
#>
```

### Running Tests

```powershell
# Run all tests
{{RUN_ALL_TESTS_CMD}}

# Run specific test file
{{RUN_SPECIFIC_TEST_CMD}}

# Run with coverage
{{RUN_COVERAGE_CMD}}
```

**Coverage Requirements**:

- Minimum {{MIN_COVERAGE}}%
- Must test {{CRITICAL_PATHS}}

### Code Review Checklist

Before submitting PR, verify:

- [ ] Tests added/updated
- [ ] Test coverage {{MIN_COVERAGE}}%+
- [ ] Code formatted with {{FORMATTER}}
- [ ] Linting passes (0 errors)
- [ ] Documentation updated
- [ ] No breaking changes (or documented)
- [ ] Commits are atomic and well-messaged
- [ ] PR description is clear

---

## 📋 Commit Guidelines

### Commit Message Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Type

- **feat**: New feature
- **fix**: Bug fix
- **docs**: Documentation changes
- **style**: Code style (formatting, etc.)
- **refactor**: Code refactoring
- **perf**: Performance improvement
- **test**: Test additions/changes
- **chore**: Tooling, dependencies

### Example Commits

```
feat(api): add support for batch operations

Implement batch endpoint to process multiple items
in a single request. Reduces latency for bulk operations.

Closes #123
```

```
fix(security): prevent SQL injection in filters

Sanitize filter parameters before database query.
Add test case for malicious input.

Fixes #456
```

---

## 🔄 Pull Request Process

### Before Submitting

1. **Update branch from upstream**:

   ```powershell
   git fetch upstream
   git rebase upstream/main
   ```

2. **Run full test suite**:

   ```powershell
   {{FULL_TEST_CMD}}
   ```

3. **Check code quality**:

   ```powershell
   {{LINT_CMD}}
   {{FORMAT_CHECK_CMD}}
   ```

### Submitting PR

1. **Push to your fork**:

   ```powershell
   git push origin feature/{{FEATURE_NAME}}
   ```

2. **Create pull request** with:
   - Clear title: `{{PR_TITLE_FORMAT}}`
   - Detailed description referencing issues
   - Screenshots/examples if applicable
   - Testing instructions if needed

3. **PR Description Template**:

   ```markdown
   ## Description
   {{DESCRIPTION}}

   ## Type of Change
   - [ ] Bug fix
   - [ ] New feature
   - [ ] Breaking change
   - [ ] Documentation update

   ## Related Issues
   Fixes #{{ISSUE_NUMBER}}

   ## Testing Instructions
   {{TESTING_STEPS}}

   ## Checklist
   - [ ] Tests added
   - [ ] Documentation updated
   - [ ] No new warnings
   - [ ] Tested locally
   ```

### Review Process

- **Automated Checks**: Must pass CI/CD pipeline
- **Code Review**: Reviewed by {{REVIEWER_COUNT}}+ maintainers
- **Approval**: All reviewers must approve
- **Merge**: Squashed commit to main branch

---

## 🧩 Adding New Features

### Feature Development Checklist

1. **Discuss First** (for major features)
   - Open an issue to discuss approach
   - Get feedback before investing time
   - Align with project direction

2. **Implementation**
   - Implement on feature branch
   - Follow code style guidelines
   - Add comprehensive tests
   - Update documentation

3. **Testing**
   - Unit tests for all functions
   - Integration tests for workflows
   - Test edge cases and errors
   - Verify {{COVERAGE_THRESHOLD}}%+ coverage

4. **Documentation**
   - Update relevant docs
   - Add examples
   - Document breaking changes
   - Update CHANGELOG

5. **Review**
   - Submit PR with clear description
   - Respond to review feedback
   - Make requested changes
   - Ensure CI/CD passes

---

## 🐛 Reporting Bugs

### Creating Bug Report

**Title**: Concise summary

**Description**:

- What you were doing
- What you expected
- What actually happened
- {{ENVIRONMENT_INFO}}

**To Reproduce**:

```powershell
# Steps to reproduce
{{REPRO_STEP_1}}
{{REPRO_STEP_2}}
```

**Expected Behavior**:

```
{{EXPECTED_BEHAVIOR}}
```

**Actual Behavior**:

```
{{ACTUAL_BEHAVIOR}}
```

**Environment**:

- OS: {{OS_VERSION}}
- {{PROJECT_NAME}} Version: {{VERSION}}
- {{RUNTIME}}: {{RUNTIME_VERSION}}

**Screenshots/Logs**:

```
{{ERROR_LOG}}
```

---

## 📚 Documentation Standards

### Markdown Guidelines

- Use clear, concise language
- Headings hierarchy: # → ## → ###
- Code blocks with language: ` ```powershell `
- Link format: `[Text](./file.md#section)`
- Update table of contents when adding sections

### Documentation PR Requirements

- [ ] Grammar check passed
- [ ] Links verified
- [ ] Examples tested
- [ ] Formatting consistent
- [ ] TOC updated

---

## 🎓 Development Resources

### Essential Documentation

- [Architecture](./ARCHITECTURE.md) - System design
- [API Reference](./API.md) - Function signatures
- [Style Guide](./CONTRIBUTING.md#code-style--standards) - Code standards
- [Testing Guide](./TESTING.md) - Test conventions

### Development Tools

```powershell
# {{TOOL_1}}: {{TOOL_1_PURPOSE}}
# {{TOOL_2}}: {{TOOL_2_PURPOSE}}
# {{TOOL_3}}: {{TOOL_3_PURPOSE}}
```

### Useful Commands

```powershell
# Format code
{{FORMAT_CMD}}

# Check code quality
{{LINT_CMD}}

# Run tests
{{TEST_CMD}}

# Build documentation
{{BUILD_DOCS_CMD}}

# Check dependencies
{{CHECK_DEPS_CMD}}
```

---

## 🏆 Recognition

### Contributors

All contributors are recognized in:

- [CONTRIBUTORS.md](./CONTRIBUTORS.md)
- GitHub repository contributors
- Release notes

### Support Levels

- **{{SUPPORT_LEVEL_1}}**: {{SUPPORT_LEVEL_1_DESC}}
- **{{SUPPORT_LEVEL_2}}**: {{SUPPORT_LEVEL_2_DESC}}
- **{{SUPPORT_LEVEL_3}}**: {{SUPPORT_LEVEL_3_DESC}}

---

## ⚖️ Code of Conduct

### Our Commitment

We are committed to providing a welcoming and inclusive environment.

### Expected Behavior

- Be respectful and inclusive
- Assume good intent
- Focus on what is best for the community
- Show empathy toward other community members

### Unacceptable Behavior

- Harassment or discrimination
- Insulting language
- Unwelcome sexual attention
- Other conduct inappropriate for a professional setting

### Enforcement

Violations will be reviewed and addressed appropriately, potentially including removal from the project.

---

## ❓ Questions?

- **PR Questions**: Comment on the PR
- **Development Help**: Create a discussion
- **General Questions**: Check [FAQ.md](./FAQ.md)
- **Contact**: {{CONTACT_EMAIL}}

---

## 📝 License

By contributing, you agree that your contributions will be licensed under the {{PROJECT_LICENSE}} License.

---

## 🎉 Thank You!

Thank you for contributing to {{PROJECT_NAME}}! Your efforts make this project better for everyone.

---

**Generated from template version 1.0 on {{GENERATION_DATE}}**
