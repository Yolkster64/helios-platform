# HELIOS Platform - Development Guide

**For developers who want to understand, extend, or contribute to HELIOS Platform**

---

## 🚀 Getting Started as a Developer

### Prerequisites
- .NET 10.0 SDK or later (`global.json` pins 10.0.400)
- Visual Studio 2022, VS Code, or JetBrains Rider
- Git
- Understanding of C# async/await patterns
- Basic knowledge of Azure services (optional but helpful)

### Quick Setup
```bash
# Clone the repository
git clone https://github.com/M0nado/helios-platform.git
cd helios-platform

# Build the project
dotnet build src/HELIOS.Platform/HELIOS.Platform.csproj

# Run tests
dotnet test tests/HELIOS.Platform.Tests/HELIOS.Platform.Tests.csproj
```

---

## 📚 Understanding the Codebase

### Start Here
1. **Read First**: [docs/ARCHITECTURE_OVERVIEW.md](ARCHITECTURE_OVERVIEW.md)
   - Understand the 6 deployment phases
   - Learn about the 6 core components
   - See the AI service routing

2. **Read Second**: [src/HELIOS.Platform/COMPONENTS_EXPLAINED.md](../src/HELIOS.Platform/COMPONENTS_EXPLAINED.md)
   - Detailed component descriptions
   - Data flow examples
   - Responsibility matrix

3. **Explore Code**: Start with `HeliosDeployment.cs`
   - Entry point for the entire system
   - Shows how all components are initialized
   - Demonstrates the 6-phase deployment

### Project Structure
```
src/HELIOS.Platform/
├── BackendServices/          # Core service implementations
│   ├── Analytics/           # Metrics & performance tracking
│   ├── ApiGateway/          # Rate limiting & routing
│   ├── AuthService/         # JWT token management
│   ├── CacheService/        # Redis distributed cache
│   ├── TaskOrchestrator/    # Workflow automation
│   └── AIIntegration/       # Multi-service AI management
├── ComponentClasses.cs       # Component interface definitions
├── HeliosDeployment.cs      # Main orchestrator (START HERE)
└── SecuritySystem.cs        # Security layer implementation

docs/
├── ARCHITECTURE_OVERVIEW.md # System architecture
├── NAVIGATION.md            # Complete documentation index
└── DEVELOPMENT.md           # This file

tests/
└── HELIOS.Platform.Tests/
    └── HeliosDeploymentTests.cs  # Unit tests
```

---

## 🔧 Key Classes & Components

### HeliosDeployment.cs
**Main orchestrator for the entire deployment process**

```csharp
public class HeliosDeployment
{
    // 6 Core Components
    public MonadoEngine MonadoEngine { get; private set; }
    public SecuritySystem SecuritySystem { get; private set; }
    public IncorporatedSoftware IncorporatedSoftware { get; private set; }
    public APIGateway APIGateway { get; private set; }
    public AnalyticsService AnalyticsService { get; private set; }
    public TaskOrchestrator TaskOrchestrator { get; private set; }
    
    // 6 Deployment Phases
    public async Task<DeploymentResult> DeployAsync()
    {
        // Phase 0: Preflight Checks
        // Phase 1: Infrastructure Setup
        // Phase 2: Security Configuration
        // Phase 3: Service Deployment
        // Phase 4: AI Integration
        // Phase 5: Monitoring & Verification
    }
}
```

**What it does**: Coordinates all deployment phases, initializes components, manages the deployment lifecycle.

### ApiGateway.cs
**Handles request routing, rate limiting, and circuit breaking**

Located: `src/HELIOS.Platform/BackendServices/ApiGateway/`

Key methods:
- `RouteRequestAsync()` - Route incoming requests
- `GetLimitStatusAsync()` - Check rate limits
- `HandleCircuitBreakerAsync()` - Manage failures

### AuthService.cs
**JWT token management and authentication**

Located: `src/HELIOS.Platform/BackendServices/AuthService/`

Key methods:
- `GenerateTokenAsync()` - Create JWT tokens
- `ValidateTokenAsync()` - Verify token validity
- `RefreshTokenAsync()` - Issue new tokens

### AnalyticsService.cs
**Performance metrics and monitoring**

Located: `src/HELIOS.Platform/BackendServices/Analytics/`

Key methods:
- `TrackMetricAsync()` - Record performance data
- `GetPerformanceStatsAsync()` - Retrieve analytics
- `QueryMetricsAsync()` - Advanced metric queries

### AIIntegration.cs
**Multi-service AI management and routing**

Located: `src/HELIOS.Platform/BackendServices/AIIntegration/`

Key methods:
- `RouteToOptimalServiceAsync()` - Intelligent routing
- `ExecuteAITaskAsync()` - Run AI operations
- `GetServiceStatusAsync()` - Service health

### TaskOrchestrator.cs
**Workflow automation and task management**

Located: `src/HELIOS.Platform/BackendServices/TaskOrchestrator/`

Key methods:
- `OrchestrationAsync()` - Coordinate workflows
- `ScheduleWorkflowAsync()` - Schedule tasks
- `MonitorExecutionAsync()` - Track execution

---

## 💡 How to Extend HELIOS

### Adding a New Feature

1. **Create a new service class** in `BackendServices/`
   ```csharp
   public class MyNewService
   {
       private readonly ILogger<MyNewService> _logger;
       
       public MyNewService(ILogger<MyNewService> logger)
       {
           _logger = logger;
       }
       
       /// <summary>
       /// Describes what this method does
       /// </summary>
       public async Task<MyResult> MyFeatureAsync()
       {
           _logger.LogInformation("Starting my feature");
           // Implementation here
       }
   }
   ```

2. **Register it in HeliosDeployment.cs**
   ```csharp
   public class HeliosDeployment
   {
       public MyNewService MyNewService { get; private set; }
       
       public HeliosDeployment()
       {
           MyNewService = new MyNewService(/* dependencies */);
       }
   }
   ```

3. **Use it in the deployment flow**
   ```csharp
   public async Task<DeploymentResult> DeployAsync()
   {
       // ... existing phases ...
       await MyNewService.MyFeatureAsync();
   }
   ```

4. **Add tests** in `tests/HELIOS.Platform.Tests/`

### Adding a New Component Type

1. Add interface to `ComponentClasses.cs`:
   ```csharp
   public interface IMyComponent
   {
       Task InitializeAsync();
       Task<ComponentStatus> GetStatusAsync();
   }
   ```

2. Implement the interface
3. Register in `HeliosDeployment.cs`
4. Add initialization logic to deployment phases

---

## 🧪 Testing

### Running Tests
```bash
# Run all tests
dotnet test tests/HELIOS.Platform.Tests/HELIOS.Platform.Tests.csproj

# Run specific test class
dotnet test --filter "ClassName=HeliosDeploymentTests"

# Run with detailed output
dotnet test --verbosity=detailed
```

### Writing Tests
```csharp
public class MyServiceTests
{
    [Fact]
    public async Task MyMethod_WithValidInput_ReturnsSuccess()
    {
        // Arrange
        var service = new MyService();
        
        // Act
        var result = await service.MyMethod("input");
        
        // Assert
        Assert.NotNull(result);
        Assert.True(result.Success);
    }
    
    [Theory]
    [InlineData("input1")]
    [InlineData("input2")]
    public async Task MyMethod_WithVariousInputs_Succeeds(string input)
    {
        // Test with different inputs
    }
}
```

### Test Patterns to Use
- **Arrange-Act-Assert (AAA)** for structure
- **Xunit** for test framework
- **InlineData** for theory-based tests
- **Async Task** for async operations

---

## 🔐 Security Considerations

### Authentication & Authorization
- All API endpoints require JWT tokens
- Tokens include role-based claims
- Token lifetime: 15 minutes (default)
- Refresh token for extended sessions

### Data Protection
- Secrets stored in Azure Key Vault
- Configuration from secure sources only
- Sensitive data encrypted in transit (HTTPS)
- Database connections use Managed Identity

### Dependency Updates
Keep dependencies current:
```bash
dotnet list package --outdated
dotnet package update                    # Update all packages
```

---

## 🐛 Debugging Tips

### Enable Detailed Logging
```csharp
var builder = new LoggerConfiguration()
    .MinimumLevel.Debug()
    .WriteTo.Console()
    .CreateLogger();
```

### Common Issues & Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| "Task not found" | Missing `using System;` | Add to top of file |
| Azure auth fails | Invalid credentials | Check Key Vault configuration |
| Rate limit errors | Threshold exceeded | Check `RateLimitAndCircuitBreaker.cs` |
| Service not found | Initialization failed | Check component registration in `HeliosDeployment` |

### Debug Breakpoints
Key places to set breakpoints:
- `HeliosDeployment.DeployAsync()` - Phase transitions
- `ApiGateway.RouteRequestAsync()` - Request routing
- `AIIntegration.RouteToOptimalServiceAsync()` - Service selection

---

## 📝 Code Standards

### Naming Conventions
- **Classes**: PascalCase (`MyService`, `ApiGateway`)
- **Methods**: PascalCase (`GetAsync()`, `ValidateToken()`)
- **Variables**: camelCase (`_logger`, `result`)
- **Constants**: UPPER_CASE (`MAX_TIMEOUT`)

### Async/Await
- Always use `async Task` or `async Task<T>` for async operations
- Avoid `Task.Result` or `Task.Wait()`
- Use `await` to call async methods
- Example:
  ```csharp
  public async Task<Result> MyAsync()
  {
      var data = await GetDataAsync();  // ✅ Correct
      return data;
  }
  ```

### Comments & Documentation
- Use XML doc comments for public methods
- Explain the **why**, not just the **what**
- Keep comments up-to-date
- Example:
  ```csharp
  /// <summary>
  /// Processes incoming requests and routes them to appropriate services.
  /// Uses intelligent routing based on request type and service availability.
  /// </summary>
  /// <param name="request">The incoming request to process</param>
  /// <returns>The routed response</returns>
  public async Task<Response> RouteRequestAsync(Request request)
  {
      // Implementation
  }
  ```

---

## 🚀 Performance Optimization

### Key Areas to Optimize
1. **Caching**: Use `CacheService` for frequently accessed data
2. **Async Operations**: All I/O should be async (not blocking)
3. **Rate Limiting**: Circuit breaker prevents cascading failures
4. **Metrics**: `AnalyticsService` tracks performance

### Profile Your Code
```bash
# Build in Release configuration for accurate measurements
dotnet build -c Release

# Run with performance analyzer
dotnet build -c Release /p:EnableAotAnalyzer=true
```

---

## 📖 Additional Resources

### Within This Repository
- [ARCHITECTURE_OVERVIEW.md](ARCHITECTURE_OVERVIEW.md) - System design
- [COMPONENTS_EXPLAINED.md](../src/HELIOS.Platform/COMPONENTS_EXPLAINED.md) - Component details
- [NAVIGATION.md](NAVIGATION.md) - Documentation index

### External Resources
- [.NET Documentation](https://docs.microsoft.com/en-us/dotnet/)
- [Azure Services](https://docs.microsoft.com/en-us/azure/)
- [JWT Authentication](https://jwt.io/)
- [Redis Documentation](https://redis.io/documentation)

---

## ❓ Getting Help

### Questions About:
- **Architecture**: See [ARCHITECTURE_OVERVIEW.md](ARCHITECTURE_OVERVIEW.md)
- **Components**: See [COMPONENTS_EXPLAINED.md](../src/HELIOS.Platform/COMPONENTS_EXPLAINED.md)
- **Deployment**: See docs/DEPLOYMENT_PLAYBOOK.md (if exists)
- **Troubleshooting**: See docs/TROUBLESHOOTING.md (if exists)

### Contributing
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

---

## 🎯 Development Workflow

### Local Development
```bash
# 1. Build the project
dotnet build src/HELIOS.Platform/HELIOS.Platform.csproj

# 2. Run tests
dotnet test tests/HELIOS.Platform.Tests/HELIOS.Platform.Tests.csproj

# 3. Make your changes
# ... edit code ...

# 4. Verify builds
dotnet build -c Release

# 5. Commit changes
git add .
git commit -m "Your meaningful commit message"

# 6. Push to your fork
git push origin feature-branch
```

### Before Submitting PR
- ✅ Code builds successfully
- ✅ All tests pass
- ✅ No compiler warnings (or justified)
- ✅ Changes are well-documented
- ✅ Commit messages are clear

---

## 📞 Contact & Support

For questions or issues:
1. Check [NAVIGATION.md](NAVIGATION.md) for documentation
2. Review existing [GitHub Issues](https://github.com/M0nado/helios-platform/issues)
3. Create a new issue with clear description

---

**Happy developing! 🚀**

*Last Updated: April 2026*
*For updates, check [START_HERE.md](../START_HERE.md)*
