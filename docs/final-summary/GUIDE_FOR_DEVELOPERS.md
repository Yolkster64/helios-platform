# HELIOS Platform - Guide for Developers

**Document Version:** 1.0  
**Date:** April 13, 2026  
**Audience:** Software Developers, Contributors

## Quick Start (15 minutes)

### Step 1: Clone & Open (5 min)

```bash
git clone https://github.com/your-org/helios-platform.git
cd helios-platform
code .
```

### Step 2: Open in Codespaces (10 min)

1. Click "Code" button in GitHub
2. Select "Codespaces" tab
3. Click "Create codespace on main"
4. Wait 12-16 minutes for environment build
5. Extensions auto-install

### Step 3: Build & Test (5 min)

```powershell
# Build
dotnet build

# Test
dotnet test

# All tests should pass ✅
```

## Development Workflow

### 1. Pick a Feature

**From GitHub Project Board:**

1. Visit: https://github.com/your-org/helios-platform/projects/3
2. Find issue with "Ready" label
3. Assign to yourself
4. Move to "In Progress"

### 2. Create Feature Branch

```bash
git checkout -b feature/your-feature-name
```

**Branch Naming Convention:**

- `feature/description` - New feature
- `fix/issue-number` - Bug fix
- `docs/description` - Documentation
- `refactor/description` - Code cleanup

### 3. Make Changes

```bash
# Write your code
# Make sure to:
# ✅ Follow code style
# ✅ Add unit tests
# ✅ Update documentation
# ✅ Run tests locally
```

### 4. Test Locally

```powershell
# Run all tests
dotnet test

# Check coverage
dotnet test /p:CollectCoverage=true

# Build NuGet package
dotnet pack

# Result should be 85%+ coverage
```

### 5. Commit & Push

```bash
git add .
git commit -m "feat: Add new feature description"
git push origin feature/your-feature-name
```

**Commit Message Format:**

- `feat: Add new feature`
- `fix: Fix issue #123`
- `docs: Update README`
- `test: Add unit tests`
- `refactor: Simplify code`

### 6. Create Pull Request

1. GitHub prompts to create PR
2. Fill in PR description (use template)
3. Link to issue: `Fixes #123`
4. Request code review
5. Wait for CI/CD (tests must pass)

### 7. Code Review

Respond to review comments:

- ✅ Approve and merge
- 💬 Respond to feedback
- 🔄 Push additional commits
- ❌ Reject and restart if needed

### 8. Merge to Main

```bash
# GitHub UI: Click "Squash and merge"
# CI/CD automatically triggers
# NuGet package auto-builds
# Deployment workflow starts
```

## Important Files for Developers

### Source Code

```
src/
├── HELIOS.Platform/
│   ├── Core/                 # Core functionality
│   ├── Services/            # Business logic
│   ├── Configuration/       # Config management
│   └── Extensions/          # Extension points
├── Tests/
│   ├── Unit/               # Unit tests
│   ├── Integration/        # Integration tests
│   └── Performance/        # Performance tests
└── Tools/                  # Developer tools
```

### Documentation

```
docs/
├── API.md                  # API documentation
├── ARCHITECTURE.md         # Architecture guide
├── DEVELOPMENT.md          # Development guide
└── CONTRIBUTING.md         # Contributing guide
```

### Configuration

```
.github/workflows/
├── build.yml              # Build pipeline
├── test.yml               # Test pipeline
├── deploy.yml             # Deployment pipeline
└── publish.yml            # NuGet publishing
```

## Code Standards

### Style Guide

**C# Conventions:**

```csharp
// Use PascalCase for classes, methods, properties
public class HeliosDeployment
{
    // Private fields with underscore
    private string _configPath;
    
    // Properties with auto-implementation
    public string Name { get; set; }
    
    // Methods with XML documentation
    /// <summary>
    /// Validates system prerequisites
    /// </summary>
    public async Task<bool> ValidateAsync()
    {
        // Implementation
    }
}
```

**Comments:**

- Only comment WHY, not WHAT
- Use XML documentation for public APIs
- Keep comments updated with code

### Testing Standards

**Unit Test Structure:**

```csharp
[Fact]
public void ValidationAsync_WithValidConfig_ReturnsTrue()
{
    // Arrange
    var config = new TestConfiguration();
    var validator = new ConfigValidator(config);
    
    // Act
    var result = validator.Validate();
    
    // Assert
    Assert.True(result);
}
```

**Coverage Target:** 85%+

### Security Practices

- No secrets in code (use GitHub Secrets)
- Validate all inputs
- Use parameterized queries
- Sanitize user input
- Follow OWASP guidelines

## Testing Guide

### Running Tests

```powershell
# Run all tests
dotnet test

# Run specific test class
dotnet test --filter "TestClassName"

# Run with coverage
dotnet test /p:CollectCoverage=true /p:CoverageFormat=cobertura

# Run performance tests
dotnet test -c Release
```

### Test Organization

```
Tests/
├── Unit/
│   ├── Core/
│   ├── Services/
│   ├── Configuration/
│   └── Extensions/
├── Integration/
│   ├── CoreIntegration/
│   └── ServiceIntegration/
└── Performance/
    └── BenchmarkTests/
```

## Debugging

### Debug in Codespaces

1. Open debug configuration: `.vscode/launch.json`
2. Press F5 to start debugging
3. Set breakpoints by clicking line number
4. Step through code (F10, F11)
5. Inspect variables in Debug panel

### Debug Locally

```bash
# Build in Debug configuration
dotnet build -c Debug

# Run with debugger
dotnet debug

# Or in Visual Studio Code
F5
```

## Common Issues & Solutions

### Build Fails

```
Solution:
1. Clean build: dotnet clean
2. Restore packages: dotnet restore
3. Rebuild: dotnet build
4. Check .NET version: dotnet --version
```

### Tests Fail

```
Solution:
1. Check test output for details
2. Run single failing test
3. Debug test code
4. Check test data/mocks
```

### Performance Issues

```
Solution:
1. Profile code with performance tools
2. Identify bottlenecks
3. Optimize hot paths
4. Benchmark improvements
```

## Useful Commands

| Command | Purpose |
|---------|---------|
| `dotnet build` | Compile code |
| `dotnet test` | Run tests |
| `dotnet run` | Run application |
| `dotnet pack` | Create NuGet package |
| `git status` | Check uncommitted changes |
| `git log --oneline` | View commit history |
| `git diff` | View file changes |

## Before Creating Pull Request

### Pre-PR Checklist

- [ ] Code builds without errors
- [ ] All tests pass (locally)
- [ ] 85%+ test coverage
- [ ] No security warnings
- [ ] Code follows style guide
- [ ] Documentation updated
- [ ] No console output/warnings
- [ ] Commit message clear
- [ ] Related issue linked

### Expected CI/CD Results

✅ **Build:** ~5 minutes  
✅ **Tests:** ~10 minutes  
✅ **Coverage:** 85%+  
✅ **Security Scan:** No critical issues  
✅ **Code Quality:** Grade A  

## Resources

- **Official Docs:** https://docs.microsoft.com/en-us/dotnet/
- **GitHub Docs:** https://docs.github.com/
- **Codespaces Guide:** https://docs.github.com/en/codespaces

---

**Status: ✅ READY FOR DEVELOPERS**
