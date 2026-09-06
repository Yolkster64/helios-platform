# Contributing to HELIOS Platform

## Getting Started

### Prerequisites

- Windows 10/11, Linux, or macOS
- .NET 6.0 SDK or later
- Git
- Visual Studio Code or Visual Studio 2022

### Setup

```powershell
git clone https://github.com/M0nado/helios-platform.git
cd helios-platform
dotnet restore
dotnet build
dotnet test
```

## Code Style Guide

### Naming Conventions

**Classes/Types**: `PascalCase`

```csharp
public class ProfileService { }
public interface IAPIGateway { }
```

**Methods/Properties**: `PascalCase`

```csharp
public async Task<bool> CreateProfileAsync() { }
public string ProfileName { get; set; }
```

**Local Variables**: `camelCase`

```csharp
var profileId = "profile-123";
```

**Constants**: `UPPERCASE`

```csharp
private const int MAX_RETRIES = 5;
```

### Code Organization

```csharp
public class ServiceImpl
{
    // 1. Constants
    private const int DEFAULT_TIMEOUT = 5000;
    
    // 2. Private fields
    private readonly ILogger<ServiceImpl> _logger;
    
    // 3. Constructor
    public ServiceImpl(ILogger<ServiceImpl> logger)
    {
        _logger = logger;
    }
    
    // 4. Public methods
    public async Task<bool> ExecuteAsync() { }
    
    // 5. Private methods
    private string FormatResult() { }
}
```

## Making Changes

### Branching Strategy

```powershell
git checkout develop
git pull origin develop
git checkout -b feature/your-feature-name
# Make changes
git commit -m "feat(scope): description"
git push origin feature/your-feature-name
```

**Branch Names**:

- `feature/*` - New features
- `bugfix/*` - Bug fixes
- `docs/*` - Documentation

### Commit Messages

Format: `<type>(<scope>): <subject>`

**Types**: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

**Examples**:

```
feat(api-gateway): add request caching
fix(event-bus): handle concurrent subscriptions
docs(readme): update installation steps
```

## Testing Requirements

### Unit Tests

80%+ code coverage required

```csharp
[TestClass]
public class ServiceTests
{
    [TestMethod]
    public async Task Method_WithCondition_ReturnsExpected()
    {
        // Arrange
        var service = new Service();
        
        // Act
        var result = await service.ExecuteAsync();
        
        // Assert
        Assert.IsTrue(result);
    }
}
```

### Running Tests

```powershell
dotnet test                    # Run all tests
dotnet test --filter "Class"  # Run specific class
dotnet test --watch          # Run on file change
```

## Pull Request Process

1. **Create PR** with clear title and description
2. **Pass all checks**:
   - Build succeeds
   - All tests pass
   - 80%+ code coverage
   - No linting errors
3. **Get code review** (at least 1 approval)
4. **Merge** when approved

## Documentation

### API Changes

Document all public methods:

```csharp
/// <summary>
/// Creates a new profile with the specified name.
/// </summary>
/// <param name="name">The profile name.</param>
/// <returns>true if creation successful; otherwise false.</returns>
public async Task<bool> CreateProfileAsync(string name)
```

### Update Docs

When changing features, update:

- `docs/ARCHITECTURE_COMPLETE.md`
- `docs/API_COMPLETE.md`
- `docs/CONTRIBUTING.md`

## FAQ

**Q: How do I run tests?**
A: `dotnet test`

**Q: How do I format code?**
A: `dotnet format`

**Q: What if tests fail?**
A: Fix locally, commit, push. Checks will run automatically.

**Q: How long for PR review?**
A: Usually 1-2 business days

## Resources

- **[QUICKSTART_PRODUCTION.md](./QUICKSTART_PRODUCTION.md)** - Setup
- **[ARCHITECTURE_COMPLETE.md](./ARCHITECTURE_COMPLETE.md)** - Design
- **[API_COMPLETE.md](./API_COMPLETE.md)** - API reference
- **[TROUBLESHOOTING.md](./TROUBLESHOOTING.md)** - Help

---

**Last Updated**: Phase 7, Stream 8 - Documentation Expansion
