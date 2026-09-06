# Phase 4 Tier 4: Resilience & Reliability Guide

**Status**: Complete  
**Date**: 2024  
**Target**: Resilience patterns, reliability mechanisms, fault tolerance  

---

## 🔁 Resilience Patterns

### Pattern 1: Retry with Exponential Backoff

**Problem**: Transient failures (network hiccup, temporary service outage)

**Solution**:

```csharp
public class RetryPolicy
{
    public async Task<T> ExecuteAsync<T>(
        Func<Task<T>> operation,
        int maxRetries = 3,
        int initialDelayMs = 100)
    {
        int delayMs = initialDelayMs;
        
        for (int attempt = 0; attempt <= maxRetries; attempt++)
        {
            try
            {
                return await operation();
            }
            catch (HttpRequestException) when (attempt < maxRetries)
            {
                await Task.Delay(delayMs);
                delayMs *= 2;  // Exponential backoff: 100ms, 200ms, 400ms
            }
        }
        
        throw new OperationFailedException($"Operation failed after {maxRetries} retries");
    }
}

// Usage
var retryPolicy = new RetryPolicy();
var result = await retryPolicy.ExecuteAsync(() =>
    _httpClient.GetAsync("https://api.example.com/data")
);
```

**Strategy**:

```
Attempt 1: Immediate
Attempt 2: Wait 100ms
Attempt 3: Wait 200ms
Attempt 4: Wait 400ms
Total: < 1 second

Retry for:
✅ Network timeouts
✅ 5xx server errors
✅ 429 rate limiting (backoff)

Don't retry:
❌ 4xx client errors (invalid request)
❌ 401 authentication errors
❌ 403 permission errors
```

---

### Pattern 2: Circuit Breaker

**Problem**: Cascading failures (one failing service brings down others)

**Solution**:

```csharp
public enum CircuitState { Closed, Open, HalfOpen }

public class CircuitBreaker
{
    private CircuitState _state = CircuitState.Closed;
    private DateTime _lastFailureTime;
    private int _failureCount = 0;
    
    private readonly int _failureThreshold = 5;
    private readonly TimeSpan _timeout = TimeSpan.FromMinutes(1);
    
    public async Task<T> ExecuteAsync<T>(Func<Task<T>> operation)
    {
        if (_state == CircuitState.Open)
        {
            if (DateTime.UtcNow - _lastFailureTime > _timeout)
            {
                _state = CircuitState.HalfOpen;  // Try to recover
            }
            else
            {
                throw new ServiceUnavailableException("Circuit breaker is open");
            }
        }
        
        try
        {
            var result = await operation();
            
            if (_state == CircuitState.HalfOpen)
            {
                _state = CircuitState.Closed;  // Recovered!
                _failureCount = 0;
            }
            
            return result;
        }
        catch (Exception ex)
        {
            _failureCount++;
            _lastFailureTime = DateTime.UtcNow;
            
            if (_failureCount >= _failureThreshold)
            {
                _state = CircuitState.Open;
            }
            
            throw;
        }
    }
}

// Circuit Breaker States
```

```
Closed (Normal)
    │
    ├─ Request succeeds → Stay Closed
    │
    └─ Request fails 5 times → Open
        │
        Open (Failing)
        │
        ├─ Wait 1 minute
        │
        └─ Try again → HalfOpen
            │
            HalfOpen (Testing)
            │
            ├─ Request succeeds → Close (recovered!)
            │
            └─ Request fails → Open (still broken)
```

**Usage**:

```csharp
private CircuitBreaker _paymentServiceBreaker = new CircuitBreaker();

public async Task<PaymentResult> ProcessPaymentAsync(Order order)
{
    try
    {
        return await _paymentServiceBreaker.ExecuteAsync(() =>
            _paymentService.ChargeAsync(order.Total)
        );
    }
    catch (ServiceUnavailableException)
    {
        // Payment service down, queue for retry
        await _messageQueue.EnqueueAsync(new PaymentRetryMessage { OrderId = order.Id });
        return new PaymentResult { Status = PaymentStatus.Pending };
    }
}
```

---

### Pattern 3: Timeout

**Problem**: Requests hang indefinitely

**Solution**:

```csharp
public class TimeoutPolicy
{
    public async Task<T> ExecuteAsync<T>(
        Func<Task<T>> operation,
        TimeSpan timeout)
    {
        using (var cts = new CancellationTokenSource(timeout))
        {
            try
            {
                return await operation();
            }
            catch (OperationCanceledException)
            {
                throw new TimeoutException($"Operation timed out after {timeout.TotalSeconds}s");
            }
        }
    }
}

// Usage
var timeoutPolicy = new TimeoutPolicy();
var result = await timeoutPolicy.ExecuteAsync(
    () => _userService.GetUserAsync(userId),
    TimeSpan.FromSeconds(5)  // 5 second timeout
);
```

---

### Pattern 4: Fallback

**Problem**: Service returns error, need graceful degradation

**Solution**:

```csharp
public class FallbackPolicy<T>
{
    public async Task<T> ExecuteAsync(
        Func<Task<T>> operation,
        Func<Task<T>> fallback)
    {
        try
        {
            return await operation();
        }
        catch (Exception ex)
        {
            _logger.LogWarning($"Operation failed, using fallback: {ex.Message}");
            return await fallback();
        }
    }
}

// Usage
var result = await _fallbackPolicy.ExecuteAsync(
    async () => await _premiumDataService.GetAnalyticsAsync(userId),
    async () => await _cachedDataService.GetAnalyticsAsync(userId)
);
// Try premium service first, fall back to cached data if it fails
```

---

### Pattern 5: Bulkhead (Isolation)

**Problem**: One failing endpoint consumes all threads, starving others

**Solution**:

```csharp
public class BulkheadPolicy
{
    private readonly SemaphoreSlim _semaphore;
    private readonly string _name;
    
    public BulkheadPolicy(string name, int maxConcurrent)
    {
        _name = name;
        _semaphore = new SemaphoreSlim(maxConcurrent);
    }
    
    public async Task<T> ExecuteAsync<T>(Func<Task<T>> operation)
    {
        if (!_semaphore.Wait(0))  // Non-blocking check
        {
            throw new BulkheadFailedException($"Bulkhead {_name} at capacity");
        }
        
        try
        {
            return await operation();
        }
        finally
        {
            _semaphore.Release();
        }
    }
}

// Usage
private BulkheadPolicy _reportServiceBulkhead = new BulkheadPolicy("ReportService", maxConcurrent: 5);

public async Task<Report> GenerateReportAsync(ReportRequest request)
{
    // Only allow 5 concurrent report generations
    // Additional requests fail fast with error
    return await _reportServiceBulkhead.ExecuteAsync(() =>
        _reportService.GenerateAsync(request)
    );
}
```

---

## 🏥 Health Checks

### Implement Health Checks

```csharp
// Register health checks
services.AddHealthChecks()
    .AddDbContextCheck<MyContext>()
    .AddCheck<CacheHealthCheck>("cache")
    .AddCheck<ExternalServiceHealthCheck>("payment-service")
    .AddUrlCheck("https://api.example.com/health", name: "external-api");

// Use in middleware
app.UseHealthChecks("/health", new HealthCheckOptions
{
    ResponseWriter = WriteResponse
});

// Custom health check
public class CacheHealthCheck : IHealthCheck
{
    private readonly IL1CacheService _cache;
    
    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        try
        {
            // Test cache operation
            var testKey = "health-check-test";
            _cache.Set(testKey, "test", TimeSpan.FromSeconds(30));
            
            if (!_cache.TryGet(testKey, out _))
                return HealthCheckResult.Unhealthy("Cache read failed");
            
            return HealthCheckResult.Healthy("Cache operational");
        }
        catch (Exception ex)
        {
            return HealthCheckResult.Unhealthy("Cache check failed", ex);
        }
    }
}

// Health check response
public static Task WriteResponse(HttpContext context, HealthReport report)
{
    context.Response.ContentType = "application/json";
    
    var response = new
    {
        status = report.Status.ToString(),
        checks = report.Entries.Select(kvp => new
        {
            name = kvp.Key,
            status = kvp.Value.Status.ToString(),
            description = kvp.Value.Description,
            duration = kvp.Value.Duration.TotalMilliseconds
        })
    };
    
    return context.Response.WriteAsJsonAsync(response);
}
```

---

## 📊 Error Handling

### Structured Error Handling

```csharp
public class ErrorHandlingMiddleware
{
    private readonly RequestDelegate _next;
    
    public async Task InvokeAsync(HttpContext context)
    {
        try
        {
            await _next(context);
        }
        catch (Exception ex)
        {
            await HandleExceptionAsync(context, ex);
        }
    }
    
    private static Task HandleExceptionAsync(HttpContext context, Exception ex)
    {
        context.Response.ContentType = "application/json";
        
        var response = new ErrorResponse
        {
            Message = ex.Message,
            TraceId = context.TraceIdentifier
        };
        
        context.Response.StatusCode = ex switch
        {
            ValidationException => StatusCodes.Status400BadRequest,
            UnauthorizedAccessException => StatusCodes.Status401Unauthorized,
            ForbiddenException => StatusCodes.Status403Forbidden,
            NotFoundException => StatusCodes.Status404NotFound,
            ServiceUnavailableException => StatusCodes.Status503ServiceUnavailable,
            _ => StatusCodes.Status500InternalServerError
        };
        
        return context.Response.WriteAsJsonAsync(response);
    }
}

public class ErrorResponse
{
    public string Message { get; set; }
    public string TraceId { get; set; }
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;
}

// Register middleware
app.UseMiddleware<ErrorHandlingMiddleware>();
```

---

## 🔄 Data Consistency

### Eventual Consistency with Message Queue

```csharp
// Publish event on successful operation
public async Task<Order> CreateOrderAsync(Order order)
{
    // 1. Create order in database
    dbContext.Orders.Add(order);
    await dbContext.SaveChangesAsync();
    
    // 2. Publish event (may succeed even if service fails)
    await _eventBus.PublishAsync(new OrderCreatedEvent
    {
        OrderId = order.Id,
        UserId = order.UserId,
        Total = order.Total
    });
    
    return order;
}

// Handle event with retry
public class OrderCreatedEventHandler : IEventHandler<OrderCreatedEvent>
{
    public async Task HandleAsync(OrderCreatedEvent @event)
    {
        try
        {
            // Update inventory
            await _inventoryService.DecrementStockAsync(@event.OrderId);
            
            // Send confirmation email
            await _emailService.SendOrderConfirmationAsync(@event.UserId, @event.OrderId);
        }
        catch (Exception ex)
        {
            // Event will be retried automatically
            _logger.LogError(ex, "Failed to handle order created event");
            throw;  // Re-throw to trigger retry
        }
    }
}
```

---

## 🚀 Graceful Shutdown

### Implement Graceful Shutdown

```csharp
// Add hosted service for graceful shutdown
public class GracefulShutdownService : BackgroundService
{
    private readonly IHostApplicationLifetime _applicationLifetime;
    
    public override Task StartAsync(CancellationToken cancellationToken)
    {
        _applicationLifetime.ApplicationStopping.Register(OnStopping);
        return base.StartAsync(cancellationToken);
    }
    
    private void OnStopping()
    {
        _logger.LogInformation("Application stopping, waiting for pending requests...");
        
        // Stop accepting new requests
        // Wait for in-flight requests to complete (timeout: 30 seconds)
    }
    
    protected override Task ExecuteAsync(CancellationToken stoppingToken)
    {
        return Task.CompletedTask;
    }
}

// Register in Startup
services.AddHostedService<GracefulShutdownService>();

// Configure shutdown timeout
var host = Host.CreateDefaultBuilder()
    .ConfigureWebHostDefaults(webBuilder =>
    {
        webBuilder.UseShutdownTimeout(TimeSpan.FromSeconds(30));
    })
    .Build();
```

---

## 📋 Reliability Checklist

- [ ] Retry logic implemented for transient failures
- [ ] Circuit breaker for failing services
- [ ] Timeouts configured for all external calls
- [ ] Fallback mechanisms for critical services
- [ ] Bulkhead isolation for resource-intensive operations
- [ ] Health checks implemented for all services
- [ ] Error handling middleware in place
- [ ] Structured error responses
- [ ] Message queue for async operations
- [ ] Graceful shutdown handling
- [ ] Monitoring and alerting configured
- [ ] Disaster recovery plan documented
- [ ] Backup strategies in place
- [ ] Redundancy for critical components
- [ ] Load balancing configured

---

## 🔧 Resilience Testing

### Chaos Engineering

```csharp
// Simulate failures in testing
public class ChaosMonkey
{
    private Random _random = new Random();
    private readonly double _failureRate;
    
    public async Task<T> MayFailAsync<T>(Func<Task<T>> operation)
    {
        if (_random.NextDouble() < _failureRate)
        {
            throw new SimulatedException("Chaos injection: Simulated failure");
        }
        
        return await operation();
    }
}

// Test with chaos
[TestMethod]
public async Task Service_WithChaosMonkey_EventuallySucceeds()
{
    var chaos = new ChaosMonkey(failureRate: 0.3);  // 30% failure rate
    var retryPolicy = new RetryPolicy();
    
    var result = await retryPolicy.ExecuteAsync(() =>
        chaos.MayFailAsync(() => _service.GetDataAsync())
    );
    
    Assert.IsNotNull(result);
}
```

---

**Document Version**: 1.0  
**Last Updated**: Phase 4 Session  
**Status**: Resilience Guide Complete
