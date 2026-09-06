# HELIOS Platform - API Reference

**Complete reference for all public APIs and classes in HELIOS Platform**

---

## 📋 API Overview

HELIOS Platform exposes the following main APIs through its components:

| Component | Primary API | Purpose |
|-----------|-------------|---------|
| **HeliosDeployment** | `DeployAsync()` | Main orchestration entry point |
| **ApiGateway** | `RouteRequestAsync()` | Request routing and management |
| **AuthService** | `GenerateTokenAsync()` | Authentication and JWT tokens |
| **CacheService** | `GetAsync()`, `SetAsync()` | Distributed caching |
| **AnalyticsService** | `TrackMetricAsync()` | Performance tracking |
| **AIIntegration** | `RouteToOptimalServiceAsync()` | AI service orchestration |
| **TaskOrchestrator** | `OrchestrationAsync()` | Workflow management |

---

## 🎯 Main Entry Point: HeliosDeployment

### Class: `HeliosDeployment`

**Location**: `src/HELIOS.Platform/HeliosDeployment.cs`

Main orchestrator for the entire HELIOS Platform deployment process.

### Properties

```csharp
public class HeliosDeployment
{
    /// <summary>Gets the Monado engine component for core processing</summary>
    public MonadoEngine MonadoEngine { get; }
    
    /// <summary>Gets the security system for authentication and authorization</summary>
    public SecuritySystem SecuritySystem { get; }
    
    /// <summary>Gets the software integration component</summary>
    public IncorporatedSoftware IncorporatedSoftware { get; }
    
    /// <summary>Gets the API Gateway for request routing</summary>
    public APIGateway APIGateway { get; }
    
    /// <summary>Gets the analytics service for metrics and monitoring</summary>
    public AnalyticsService AnalyticsService { get; }
    
    /// <summary>Gets the task orchestrator for workflow management</summary>
    public TaskOrchestrator TaskOrchestrator { get; }
}
```

### Key Methods

#### DeployAsync()

```csharp
/// <summary>
/// Executes the complete deployment with all 6 phases.
/// Phases: Preflight → Infrastructure → Security → Services → AI → Monitoring
/// </summary>
/// <returns>DeploymentResult containing success status and details</returns>
public async Task<DeploymentResult> DeployAsync()
```

**Phases**:

1. **Preflight** - Configuration validation and prerequisite checks
2. **Infrastructure** - Azure resource setup and networking
3. **Security** - Authentication, encryption, and security policies
4. **Services** - Deploy backend services and APIs
5. **AI Integration** - Configure AI services and routing
6. **Monitoring** - Enable monitoring, alerting, and health checks

---

## 🔐 Authentication: AuthService

### Class: `AuthService`

**Location**: `src/HELIOS.Platform/BackendServices/AuthService/`

Manages JWT token generation, validation, and refresh.

### Key Methods

#### GenerateTokenAsync()

```csharp
/// <summary>
/// Generates a new JWT token for the specified user.
/// </summary>
/// <param name="userId">Unique user identifier</param>
/// <param name="roles">User roles for claim-based authorization</param>
/// <param name="expirationMinutes">Token validity duration (default: 15)</param>
/// <returns>JWT token string</returns>
public async Task<string> GenerateTokenAsync(string userId, string[] roles, int expirationMinutes = 15)
```

**Example**:

```csharp
var token = await authService.GenerateTokenAsync(
    "user-123",
    new[] { "admin", "developer" },
    15
);
```

#### ValidateTokenAsync()

```csharp
/// <summary>
/// Validates a JWT token and extracts claims.
/// </summary>
/// <param name="token">JWT token string to validate</param>
/// <returns>ClaimsPrincipal if valid, null if invalid</returns>
public async Task<ClaimsPrincipal> ValidateTokenAsync(string token)
```

#### RefreshTokenAsync()

```csharp
/// <summary>
/// Issues a new token using a valid refresh token.
/// </summary>
/// <param name="refreshToken">Previously issued refresh token</param>
/// <returns>New JWT token</returns>
public async Task<string> RefreshTokenAsync(string refreshToken)
```

---

## 🛣️ Request Routing: ApiGateway

### Class: `ApiGateway`

**Location**: `src/HELIOS.Platform/BackendServices/ApiGateway/`

Routes requests, enforces rate limiting, and manages circuit breaking.

### Key Methods

#### RouteRequestAsync()

```csharp
/// <summary>
/// Routes an incoming request to the appropriate backend service.
/// Considers service availability, load, and request type.
/// </summary>
/// <param name="request">Incoming HTTP request</param>
/// <returns>Routed response from backend service</returns>
public async Task<ApiResponse> RouteRequestAsync(ApiRequest request)
```

**Example**:

```csharp
var response = await apiGateway.RouteRequestAsync(
    new ApiRequest
    {
        Method = "POST",
        Path = "/api/analytics",
        Body = analyticsData,
        Headers = new Dictionary<string, string> { ["Authorization"] = "Bearer token" }
    }
);
```

#### GetLimitStatusAsync()

```csharp
/// <summary>
/// Checks current rate limit status for a client.
/// </summary>
/// <param name="clientId">Client identifier</param>
/// <returns>Rate limit status and remaining quota</returns>
public async Task<RateLimitStatus> GetLimitStatusAsync(string clientId)
```

---

## 💾 Caching: CacheService

### Class: `CacheService`

**Location**: `src/HELIOS.Platform/BackendServices/CacheService/`

Provides distributed Redis-based caching.

### Key Methods

#### GetAsync()

```csharp
/// <summary>
/// Retrieves a value from cache.
/// </summary>
/// <typeparam name="T">Type of cached value</typeparam>
/// <param name="key">Cache key</param>
/// <returns>Cached value or null if not found</returns>
public async Task<T> GetAsync<T>(string key)
```

#### SetAsync()

```csharp
/// <summary>
/// Stores a value in cache with optional expiration.
/// </summary>
/// <typeparam name="T">Type of value to cache</typeparam>
/// <param name="key">Cache key</param>
/// <param name="value">Value to cache</param>
/// <param name="expirationSeconds">TTL in seconds (0 = never expire)</param>
public async Task SetAsync<T>(string key, T value, int expirationSeconds = 0)
```

**Example**:

```csharp
// Cache a user profile for 1 hour
await cacheService.SetAsync("user-profile:123", userProfile, 3600);

// Retrieve from cache
var profile = await cacheService.GetAsync<UserProfile>("user-profile:123");
```

#### RemoveAsync()

```csharp
/// <summary>
/// Removes a value from cache.
/// </summary>
/// <param name="key">Cache key to remove</param>
public async Task RemoveAsync(string key)
```

---

## 📊 Analytics: AnalyticsService

### Class: `AnalyticsService`

**Location**: `src/HELIOS.Platform/BackendServices/Analytics/`

Tracks performance metrics and system analytics.

### Key Methods

#### TrackMetricAsync()

```csharp
/// <summary>
/// Records a performance metric.
/// </summary>
/// <param name="metricName">Name of the metric</param>
/// <param name="value">Numeric value</param>
/// <param name="tags">Optional metadata tags</param>
public async Task TrackMetricAsync(string metricName, double value, Dictionary<string, string> tags = null)
```

**Example**:

```csharp
await analyticsService.TrackMetricAsync(
    "request.latency",
    123.45,  // milliseconds
    new Dictionary<string, string>
    {
        ["endpoint"] = "/api/analytics",
        ["method"] = "POST",
        ["status"] = "200"
    }
);
```

#### GetPerformanceStatsAsync()

```csharp
/// <summary>
/// Retrieves performance statistics for a time period.
/// </summary>
/// <param name="startTime">Time range start</param>
/// <param name="endTime">Time range end</param>
/// <returns>Performance statistics</returns>
public async Task<PerformanceStats> GetPerformanceStatsAsync(DateTime startTime, DateTime endTime)
```

#### QueryMetricsAsync()

```csharp
/// <summary>
/// Advanced metric query with filtering and aggregation.
/// </summary>
/// <param name="query">Metric query specification</param>
/// <returns>Matching metrics</returns>
public async Task<List<Metric>> QueryMetricsAsync(MetricQuery query)
```

---

## 🤖 AI Integration: AIIntegration

### Class: `AIIntegration`

**Location**: `src/HELIOS.Platform/BackendServices/AIIntegration/`

Manages multiple AI services and intelligent routing.

### Key Methods

#### RouteToOptimalServiceAsync()

```csharp
/// <summary>
/// Intelligently routes AI requests to the optimal service based on:
/// - Request type and complexity
/// - Service availability and health
/// - Cost optimization (balances accuracy vs cost)
/// </summary>
/// <param name="request">AI request</param>
/// <returns>Response from optimal service</returns>
public async Task<AiResponse> RouteToOptimalServiceAsync(AiRequest request)
```

**Supported AI Services**:

- OpenAI GPT-4 (highest quality)
- Azure OpenAI (enterprise)
- Anthropic Claude (alternative)
- Azure Cognitive Services (specialized)
- Local ML Models (cost-effective)

#### ExecuteAITaskAsync()

```csharp
/// <summary>
/// Executes an AI task with specified service and parameters.
/// </summary>
/// <param name="serviceId">Specific AI service to use</param>
/// <param name="task">AI task specification</param>
/// <returns>Task result</returns>
public async Task<AiTaskResult> ExecuteAITaskAsync(string serviceId, AiTask task)
```

#### GetServiceStatusAsync()

```csharp
/// <summary>
/// Checks health and availability of AI services.
/// </summary>
/// <returns>Status of all configured AI services</returns>
public async Task<Dictionary<string, ServiceStatus>> GetServiceStatusAsync()
```

---

## ⚙️ Task Orchestration: TaskOrchestrator

### Class: `TaskOrchestrator`

**Location**: `src/HELIOS.Platform/BackendServices/TaskOrchestrator/`

Manages workflows and scheduled tasks.

### Key Methods

#### OrchestrationAsync()

```csharp
/// <summary>
/// Orchestrates a multi-step workflow with error handling and retries.
/// </summary>
/// <param name="workflow">Workflow definition</param>
/// <returns>Workflow execution result</returns>
public async Task<WorkflowResult> OrchestrationAsync(Workflow workflow)
```

**Example Workflow**:

```csharp
var workflow = new Workflow
{
    Name = "Data Processing Pipeline",
    Steps = new List<WorkflowStep>
    {
        new WorkflowStep { Action = "validate", Config = validationConfig },
        new WorkflowStep { Action = "transform", Config = transformConfig },
        new WorkflowStep { Action = "store", Config = storageConfig },
        new WorkflowStep { Action = "notify", Config = notificationConfig }
    }
};

var result = await taskOrchestrator.OrchestrationAsync(workflow);
```

#### ScheduleWorkflowAsync()

```csharp
/// <summary>
/// Schedules a workflow to run at specified times.
/// </summary>
/// <param name="workflow">Workflow to schedule</param>
/// <param name="schedule">Cron or time specification</param>
public async Task ScheduleWorkflowAsync(Workflow workflow, string schedule)
```

#### MonitorExecutionAsync()

```csharp
/// <summary>
/// Monitors execution of a running workflow.
/// </summary>
/// <param name="executionId">Workflow execution ID</param>
/// <returns>Current execution status</returns>
public async Task<ExecutionStatus> MonitorExecutionAsync(string executionId)
```

---

## 🔒 Security System: SecuritySystem

### Class: `SecuritySystem`

**Location**: `src/HELIOS.Platform/SecuritySystem.cs`

Manages security policies, encryption, and authorization.

### Key Methods

#### InitializeAsync()

```csharp
/// <summary>
/// Initializes security policies and loads credentials from Key Vault.
/// </summary>
public async Task InitializeAsync()
```

#### VerifyAccessAsync()

```csharp
/// <summary>
/// Verifies user access to a resource based on policies.
/// </summary>
/// <param name="userId">User identifier</param>
/// <param name="resource">Resource name</param>
/// <param name="action">Action to perform</param>
/// <returns>true if access granted</returns>
public async Task<bool> VerifyAccessAsync(string userId, string resource, string action)
```

---

## 📦 Data Types & Models

### DeploymentResult

```csharp
public class DeploymentResult
{
    /// <summary>True if deployment succeeded</summary>
    public bool Success { get; set; }
    
    /// <summary>Overall deployment status</summary>
    public DeploymentStatus Status { get; set; }
    
    /// <summary>Deployment duration</summary>
    public TimeSpan Duration { get; set; }
    
    /// <summary>Created resources (ARNs/IDs)</summary>
    public List<string> CreatedResources { get; set; }
    
    /// <summary>Any deployment errors</summary>
    public List<string> Errors { get; set; }
}
```

### ComponentStatus

```csharp
public class ComponentStatus
{
    /// <summary>Component name</summary>
    public string ComponentName { get; set; }
    
    /// <summary>Health status</summary>
    public bool IsHealthy { get; set; }
    
    /// <summary>Component version</summary>
    public string Version { get; set; }
    
    /// <summary>Last health check time</summary>
    public DateTime LastChecked { get; set; }
}
```

### ApiRequest

```csharp
public class ApiRequest
{
    public string Method { get; set; }          // GET, POST, PUT, DELETE, etc.
    public string Path { get; set; }            // API endpoint path
    public object Body { get; set; }            // Request payload
    public Dictionary<string, string> Headers { get; set; }
}
```

### ApiResponse

```csharp
public class ApiResponse
{
    public int StatusCode { get; set; }         // HTTP status code
    public object Data { get; set; }            // Response data
    public string Message { get; set; }         // Status message
    public List<string> Errors { get; set; }    // Any errors
}
```

---

## 🔗 Common Usage Patterns

### Pattern 1: Complete Deployment

```csharp
var deployment = new HeliosDeployment();
var result = await deployment.DeployAsync();

if (result.Success)
{
    Console.WriteLine($"Deployment succeeded in {result.Duration}");
}
else
{
    foreach (var error in result.Errors)
    {
        Console.WriteLine($"Error: {error}");
    }
}
```

### Pattern 2: Authenticated API Request

```csharp
// Get auth token
var token = await deployment.SecuritySystem.AuthService.GenerateTokenAsync(
    userId: "user-123",
    roles: new[] { "api-client" }
);

// Make authenticated request
var response = await deployment.APIGateway.RouteRequestAsync(
    new ApiRequest
    {
        Method = "POST",
        Path = "/api/data",
        Body = data,
        Headers = new Dictionary<string, string>
        {
            ["Authorization"] = $"Bearer {token}"
        }
    }
);
```

### Pattern 3: AI-Powered Processing

```csharp
var aiRequest = new AiRequest
{
    Task = "analyze-sentiment",
    Input = userText,
    Parameters = new { language = "en" }
};

var response = await deployment.AIOrchestrator.RouteToOptimalServiceAsync(aiRequest);
```

### Pattern 4: Performance Monitoring

```csharp
// Track metric
await deployment.AnalyticsService.TrackMetricAsync(
    "processing.time",
    stopwatch.ElapsedMilliseconds,
    new Dictionary<string, string>
    {
        ["operation"] = "data-analysis",
        ["success"] = "true"
    }
);

// Query metrics
var stats = await deployment.AnalyticsService.GetPerformanceStatsAsync(
    startTime: DateTime.UtcNow.AddHours(-1),
    endTime: DateTime.UtcNow
);
```

---

## ⚠️ Error Handling

All methods follow consistent error handling patterns:

```csharp
try
{
    var result = await deployment.DeployAsync();
}
catch (ValidationException ex)
{
    // Invalid configuration or parameters
}
catch (AuthenticationException ex)
{
    // Auth failure
}
catch (ServiceUnavailableException ex)
{
    // Service temporarily down
}
catch (Exception ex)
{
    // Generic error
}
```

---

## 📚 Additional Resources

- [Component Details](../src/HELIOS.Platform/COMPONENTS_EXPLAINED.md)
- [Architecture Overview](ARCHITECTURE_OVERVIEW.md)
- [Development Guide](DEVELOPMENT.md)
- [Navigation & Index](NAVIGATION.md)

---

**Last Updated**: April 2026  
**Version**: 1.0.0  
**API Stability**: Stable (backward compatible)
