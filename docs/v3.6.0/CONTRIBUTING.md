# Contributing to HELIOS Platform v3.6.0

**Version**: 3.6.0

We welcome contributions! Here's how to get started.

## Getting Started

### Prerequisites

- Windows 11 Pro or Server 2022+
- Visual Studio 2022 or VS Code
- .NET 8.0 SDK
- Git
- SQL Server LocalDB (for development)

### Setup Development Environment

```powershell
# Clone repository
git clone https://github.com/M0nado/helios-platform.git
cd helios-platform

# Create feature branch
git checkout -b feature/your-feature-name

# Build solution
dotnet build

# Run tests
dotnet test
```

## Types of Contributions

### 1. Plugin Development

Create custom plugins extending HELIOS functionality:

- See docs/v3.6.0/FEATURES_GUIDE.md > Plugin System
- Use IPlugin interface
- Publish to marketplace

### 2. Feature Implementation

Add new features to core platform:

- File an issue first (discuss approach)
- Follow code style guidelines
- Add tests for new functionality
- Update documentation

### 3. Bug Fixes

Fix existing bugs:

- Reference GitHub issue number
- Include regression tests
- Update CHANGELOG.md

### 4. Documentation

Improve documentation:

- Fix typos and clarify instructions
- Add code examples
- Update outdated information
- Translate to other languages

### 5. Testing

Improve test coverage:

- Add unit tests for untested code
- Add integration tests for workflows
- Report test failures

## Code Style Guidelines

- **Language**: C# 12.0
- **Naming**: PascalCase for classes, camelCase for variables
- **Async**: Use async/await for I/O operations
- **Logging**: Use ILogger for all logging
- **Comments**: Document public APIs only
- **Line Length**: Max 120 characters

Example:

```csharp
public class CloudSyncService
{
    private readonly ILogger _logger;

    public async Task<SyncResult> SyncAsync(CancellationToken cancellationToken = default)
    {
        _logger.LogInformation("Starting cloud synchronization");
        // Implementation
        return result;
    }
}
```

## Commit Message Guidelines

```
<type>(<scope>): <subject>

<body>

<footer>
```

Types: feat, fix, docs, style, refactor, perf, test, chore
Example:

```
feat(cloud-sync): Add AWS S3 support

Implemented S3StorageProvider with full sync capabilities including:
- Multi-region support
- Server-side encryption
- Multipart upload for large files

Fixes #234

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```

## Testing Requirements

- All new features must have tests
- Tests should cover both success and failure cases
- Run tests before submitting PR: `dotnet test`
- Aim for >80% code coverage

## Pull Request Process

1. Create feature branch from `main`
2. Make changes and commit with clear messages
3. Push to GitHub: `git push origin feature/your-feature`
4. Open Pull Request with description
5. Respond to review comments
6. Ensure all checks pass
7. Maintainer merges when approved

## Documentation Requirements

- Update README.md for feature additions
- Update CHANGELOG.md with changes
- Add code examples for new APIs
- Update relevant guides in docs/v3.6.0/

## Reporting Issues

When reporting bugs:

1. Check existing issues first
2. Provide clear reproduction steps
3. Include HELIOS version and OS
4. Attach relevant logs
5. (Optional) Submit fix as PR

## Licensing

By contributing, you agree that contributions are licensed under the MIT License.

See LICENSE file for details.

---

Questions? Ask in GitHub Discussions!
