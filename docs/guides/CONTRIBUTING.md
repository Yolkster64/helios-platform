# Contributing to HELIOS Platform

First off, thanks for taking the time to contribute! 🎉

## Code of Conduct

This project and everyone participating in it is governed by our Code of Conduct. By participating, you are expected to uphold this code.

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check the issue list as you might find out that you don't need to create one. When you are creating a bug report, please include as many details as possible:

* **Use a clear and descriptive title**
* **Describe the exact steps which reproduce the problem**
* **Provide specific examples to demonstrate the steps**
* **Describe the behavior you observed after following the steps**
* **Explain which behavior you expected to see instead and why**
* **Include screenshots and animated GIFs if possible**
* **Include your environment details** (OS, PowerShell version, Docker version, etc.)

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When creating an enhancement suggestion, please include:

* **Use a clear and descriptive title**
* **Provide a step-by-step description of the suggested enhancement**
* **Provide specific examples to demonstrate the steps**
* **Describe the current behavior and the proposed behavior**
* **Explain why this enhancement would be useful**

### Pull Requests

* Fill in the required template
* Follow the code style guidelines
* Include appropriate test cases
* End all files with a newline
* Avoid platform-dependent code

## Development Setup

1. **Fork and clone the repository**

   ```bash
   git clone https://github.com/your-username/helios-platform.git
   cd helios-platform
   ```

2. **Create a branch for your changes**

   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make your changes and commit**

   ```bash
   git commit -am 'Add your feature'
   ```

4. **Push to your fork**

   ```bash
   git push origin feature/your-feature-name
   ```

5. **Create a Pull Request** against the `develop` branch

## Code Style Guidelines

### PowerShell

* Use PascalCase for functions and variables (except script-scoped)
* Use camelCase for local variables
* Add comment blocks explaining complex logic
* Use proper error handling with try-catch
* Include verbose narration in deployment scripts

### C\#

* Follow Microsoft C# coding conventions
* Use meaningful variable and function names
* Add XML documentation comments
* Use async/await patterns where appropriate
* Write unit tests for new functionality

### Documentation

* Use clear, concise language
* Include code examples where appropriate
* Keep documentation up-to-date with code changes
* Use markdown for formatting

## Commit Messages

* Use the present tense ("Add feature" not "Added feature")
* Use the imperative mood ("Move cursor to..." not "Moves cursor to...")
* Limit the first line to 72 characters or less
* Reference issues and pull requests liberally after the first line
* Include Co-authored-by for pair programming

Example:

```
Add Azure resource group creation in Phase 1

- Implements resource group deployment
- Includes error handling for existing groups
- Adds detailed narration for operator visibility

Fixes #123
Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```

## Testing

* Add tests for new functionality
* Ensure all tests pass before submitting PR
* Maintain or improve code coverage
* Test on multiple platforms if possible

## Documentation

* Update README.md if your changes introduce new functionality
* Update the relevant documentation files
* Add/update inline code comments
* Consider adding examples

## Review Process

1. At least one maintainer review required
2. All tests must pass
3. No merge conflicts
4. Code style guidelines followed
5. Documentation updated

## Questions?

Feel free to open a discussion or contact us:

* GitHub Discussions: https://github.com/M0nado/helios-platform/discussions
* Email: support@helios-platform.dev

Thank you for contributing! 🚀
