# C# Modernization & Best Practices Guide (25+ Patterns)

## Overview

This guide covers 25+ C# modernization patterns and best practices for Phase 5-6 code generation. These patterns leverage modern C# features (C# 10+, .NET 6+) to improve code quality, performance, and maintainability.

---

## Pattern 1: Modern Language Features

### 1.1 Records Instead of Classes

**Pattern:** Use records for immutable data transfer objects and value types.

```csharp
// ❌ Old: Class with boilerplate
public class UserDto
{
    public int Id { get; set; }
    public string Name { get; set; }
    public string Email { get; set; }
    
    public override bool Equals(object obj) { /* boilerplate */ }
    public override int GetHashCode() { /* boilerplate */ }
}

// ✅ Modern: Record (automatic Equals, GetHashCode, ToString)
public record UserDto(int Id, string Name, string Email);

// ✅ Modern: Record with init-only properties
public record UserDto
{
    public int Id { get; init; }
    public string Name { get; init; }
    public string Email { get; init; }
}
```

**Benefit:** 80% less boilerplate, built-in equality

### 1.2 Init-Only Properties

**Pattern:** Use init to enforce immutability at construction.

```csharp
// ❌ Old: Mutable after construction
public class Order
{
    public int Id { get; set; }
    public decimal Amount { get; set; }
}

// ✅ Modern: Immutable after construction
public class Order
{
    public int Id { get; init; }
    public decimal Amount { get; init; }
}

// ✅ Usage
var order = new Order { Id = 1, Amount = 99.99m };
// order.Amount = 100m;  // ❌ Compile error!
```

**Benefit:** Thread-safe, prevents accidental mutation

### 1.3 Nullable Reference Types

**Pattern:** Enable nullable annotations for safer code.

```csharp
// Enable in csproj: <Nullable>enable</Nullable>

// ❌ Ambiguous: Is this allowed to be null?
public string GetUserName(User user)
{
    return user.Name;  // Could be null?
}

// ✅ Clear: Null safety explicit
public string GetUserName(User user)
{
    return user.Name ?? "Unknown";  // Compiler knows it might be null
}

// ✅ Clear: Non-null requirement
public void SetUserName(User user, string name)
{
    // name cannot be null - compiler enforces
    user.Name = name;
}
```

**Benefit:** Eliminates null reference exceptions

### 1.4 Pattern Matching

**Pattern:** Use modern pattern matching for type checking and filtering.

```csharp
// ❌ Old: Type casting
public decimal GetDiscount(Customer customer)
{
    if (customer is VipCustomer)
    {
        var vip = (VipCustomer)customer;
        return vip.YearsActive > 5 ? 0.20m : 0.10m;
    }
    return 0m;
}

// ✅ Modern: Pattern matching
public decimal GetDiscount(Customer customer) =>
    customer switch
    {
        VipCustomer { YearsActive: > 5 } => 0.20m,
        VipCustomer => 0.10m,
        _ => 0m
    };

// ✅ Modern: Property patterns
public bool IsValidOrder(Order order) =>
    order switch
    {
        { Status: "Open", Amount: > 0, Customer: not null } => true,
        _ => false
    };
```

**Benefit:** More expressive, safer code

### 1.5 Target-Typed new()

**Pattern:** Use new() without type specification.

```csharp
// ❌ Old: Redundant type
List<Order> orders = new List<Order>();
Dictionary<string, int> counts = new Dictionary<string, int>();

// ✅ Modern: Target-typed new
List<Order> orders = new();
Dictionary<string, int> counts = new();

// ✅ Modern: In method calls
public void ProcessOrders(List<Order> orders = new()) { }
```

**Benefit:** Less verbose, clearer intent

### 1.6 Global Using Statements

**Pattern:** Use global using for common namespaces.

```csharp
// GlobalUsings.cs
global using System;
global using System.Collections.Generic;
global using System.Linq;
global using System.Threading.Tasks;
global using Microsoft.Extensions.DependencyInjection;

// Other files - no need to repeat
public class OrderService
{
    private readonly IServiceProvider _provider;
    
    public async Task<List<Order>> GetOrdersAsync() { }
}
```

**Benefit:** Cleaner files, shared namespaces

### 1.7 File-Scoped Namespaces

**Pattern:** Use file-scoped namespaces for simpler structure.

```csharp
// ❌ Old: Nested braces
namespace MyApp.Services
{
    public class OrderService
    {
        public void Process() { }
    }
}

// ✅ Modern: File-scoped
namespace MyApp.Services;

public class OrderService
{
    public void Process() { }
}
```

**Benefit:** Cleaner files, less indentation

### 1.8 Required Members (C# 11+)

**Pattern:** Use required keyword for mandatory properties.

```csharp
// ✅ Modern: Required properties
public class Order
{
    public required int Id { get; init; }
    public required decimal Amount { get; init; }
    public string? Notes { get; init; }  // Optional
}

// Compiler enforces:
var order = new Order { Amount = 99 };  // ❌ Compile error: Id required
var order = new Order { Id = 1, Amount = 99 };  // ✅ OK
```

**Benefit:** Compile-time safety

### 1.9 Raw String Literals (C# 11+)

**Pattern:** Use raw string literals for multi-line text.

```csharp
// ❌ Old: Escaped quotes
string json = "{\"id\": 1, \"name\": \"John\"}";

// ✅ Modern: Raw strings
string json = """
    {
        "id": 1,
        "name": "John"
    }
    """;

// ✅ Modern: SQL queries
string query = """
    SELECT u.Id, u.Name, u.Email
    FROM Users u
    WHERE u.IsActive = 1
    """;
```

**Benefit:** Readable, no escaping

### 1.10 Top-Level Statements (C# 9+)

**Pattern:** Use top-level statements for simple programs.

```csharp
// ✅ Modern: No Program.cs boilerplate
var builder = WebApplication.CreateBuilder();
builder.Services.AddScoped<IOrderService, OrderService>();

var app = builder.Build();
app.MapGet("/orders", GetOrders);
app.Run();

async Task<IResult> GetOrders(IOrderService service)
{
    var orders = await service.GetOrdersAsync();
    return Results.Ok(orders);
}
```

**Benefit:** Simplified console/ASP.NET apps

---

## Pattern 2: Dependency Injection Excellence

### 2.1 IServiceCollection Registration

**Pattern:** Use DI container for all service registration.

```csharp
// ✅ Good: DI registration
builder.Services.AddScoped<IOrderService, OrderService>();
builder.Services.AddScoped<IOrderRepository, OrderRepository>();
builder.Services.AddSingleton<ICache, MemoryCache>();
builder.Services.AddTransient<IMailService, SmtpMailService>();

// Usage
public class OrderService
{
    private readonly IOrderRepository _repository;
    
    public OrderService(IOrderRepository repository)
    {
        _repository = repository;
    }
}
```

**Benefit:** Loose coupling, testability

### 2.2 AddSingleton for Stateless Services

**Pattern:** Register stateless services as singletons.

```csharp
// ✅ Good: Stateless service as singleton
builder.Services.AddSingleton<IMapper, AutoMapper>();
builder.Services.AddSingleton<IValidator, FluentValidator>();
builder.Services.AddSingleton<ILogger, ConsoleLogger>();
```

**Benefit:** Single instance, lower memory

### 2.3 AddScoped for Request-Scoped Services

**Pattern:** Register request-scoped services for HTTP contexts.

```csharp
// ✅ Good: Scoped to HTTP request
builder.Services.AddScoped<IOrderService, OrderService>();
builder.Services.AddScoped<IOrderRepository, OrderRepository>();
builder.Services.AddScoped<IUnitOfWork, UnitOfWork>();
```

**Benefit:** Fresh instance per request

### 2.4 AddTransient for Stateful Services

**Pattern:** Register stateful services as transient.

```csharp
// ✅ Good: Transient for stateful services
builder.Services.AddTransient<IRequestContext, RequestContext>();
builder.Services.AddTransient<IPasswordHasher, BcryptHasher>();
```

**Benefit:** New instance every time

### 2.5 Factory Pattern with DI

**Pattern:** Use factories for complex object creation.

```csharp
// ✅ Good: Factory registration
builder.Services.AddScoped<IOrderService>(provider =>
{
    var repository = provider.GetRequiredService<IOrderRepository>();
    var cache = provider.GetRequiredService<ICache>();
    var logger = provider.GetRequiredService<ILogger>();
    
    return new OrderService(repository, cache, logger);
});

// ✅ Good: Factory interface
public interface IServiceFactory
{
    T Create<T>() where T : class;
}

public class ServiceFactory : IServiceFactory
{
    private readonly IServiceProvider _provider;
    
    public T Create<T>() where T : class =>
        _provider.GetRequiredService<T>();
}
```

**Benefit:** Complex initialization logic

### 2.6 Keyed Services (C# 11+)

**Pattern:** Register multiple implementations with keys.

```csharp
// ✅ Modern: Keyed services
builder.Services.AddKeyedScoped<INotificationService, EmailService>("email");
builder.Services.AddKeyedScoped<INotificationService, SmsService>("sms");

// Inject specific implementation
public class NotificationHandler
{
    public NotificationHandler(
        [FromKeyedServices("email")] INotificationService emailService,
        [FromKeyedServices("sms")] INotificationService smsService)
    {
        _emailService = emailService;
        _smsService = smsService;
    }
}
```

**Benefit:** Multiple implementations per interface

### 2.7 Service Lifetime Management

**Pattern:** Understand service lifetime implications.

```csharp
// ⚠️ Anti-pattern: Singleton with state
builder.Services.AddSingleton<IUserContext, UserContext>();  // DON'T if stateful!

// ✅ Good: Scoped for request context
builder.Services.AddScoped<IUserContext, UserContext>();

// ✅ Good: Options pattern for configuration
builder.Services.Configure<OrderOptions>(config =>
{
    config.MaxOrderAmount = 10000;
    config.MaxOrdersPerDay = 100;
});
```

**Benefit:** Correct lifetime scoping

### 2.8 Service Provider Best Practices

**Pattern:** Don't use service locator pattern.

```csharp
// ❌ Anti-pattern: Service locator
var service = ServiceLocator.GetService<IOrderService>();

// ✅ Good: Constructor injection
public class OrderController
{
    private readonly IOrderService _service;
    
    public OrderController(IOrderService service)
    {
        _service = service;
    }
}
```

**Benefit:** Explicit dependencies, testability

### 2.9 Named Options

**Pattern:** Use named options for multiple configurations.

```csharp
// ✅ Good: Named options
builder.Services.Configure<CacheOptions>("redis", options =>
{
    options.Host = "redis.local";
    options.Port = 6379;
});

builder.Services.Configure<CacheOptions>("memory", options =>
{
    options.MaxSize = 1000;
});

// Usage
public class CacheService
{
    private readonly IOptionsMonitor<CacheOptions> _options;
    
    public CacheService(IOptionsMonitor<CacheOptions> options)
    {
        var redisConfig = options.Get("redis");
    }
}
```

**Benefit:** Multiple configurations per interface

### 2.10 Validation in DI Configuration

**Pattern:** Validate configuration during startup.

```csharp
// ✅ Good: Validate options
builder.Services.AddOptions<OrderOptions>()
    .Configure(options =>
    {
        options.MaxOrderAmount = 10000;
    })
    .ValidateDataAnnotations()
    .ValidateOnStart();
```

**Benefit:** Fails at startup, not runtime

---

## Pattern 3: Async/Await Best Practices

### 3.1 Async All the Way

**Pattern:** Use async throughout the call chain.

```csharp
// ❌ Bad: Mixed sync/async
public List<Order> GetOrders()
{
    return GetOrdersAsync().Result;  // BLOCKS!
}

// ✅ Good: Async all the way
public async Task<List<Order>> GetOrdersAsync()
{
    var orders = await _repository.GetAllAsync();
    return orders;
}

// ✅ Good: Mark handlers async
public async Task<IActionResult> GetOrders()
{
    var orders = await _service.GetOrdersAsync();
    return Ok(orders);
}
```

**Benefit:** Prevents thread starvation

### 3.2 Never Use .Result or .Wait()

**Pattern:** Never block async code.

```csharp
// ❌ WRONG: Deadlock risk
var result = asyncMethod().Result;

// ❌ WRONG: Blocks thread
asyncMethod().Wait();

// ✅ Correct: Await
var result = await asyncMethod();

// ✅ Correct: Return task
public async Task<T> GetAsync() =>
    await _repository.GetAsync();
```

**Benefit:** Prevents deadlocks

### 3.3 ConfigureAwait(false) for Libraries

**Pattern:** Use ConfigureAwait(false) to not capture context.

```csharp
// ✅ Good: Library code doesn't need context
public async Task<Order> GetOrderAsync(int id)
{
    var order = await _repository.GetAsync(id)
        .ConfigureAwait(false);
    
    return order;
}

// ✅ Good: ASP.NET context not needed in service
public class OrderService
{
    public async Task ProcessAsync(Order order)
    {
        var result = await _processQueue.EnqueueAsync(order)
            .ConfigureAwait(false);
        
        return result;
    }
}
```

**Benefit:** Better thread pool efficiency

### 3.4 Proper Exception Propagation

**Pattern:** Let exceptions propagate naturally.

```csharp
// ❌ Bad: Swallows exception
public async Task<Order> GetOrderAsync(int id)
{
    try
    {
        return await _repository.GetAsync(id);
    }
    catch
    {
        return null;  // Exception lost!
    }
}

// ✅ Good: Let exception propagate
public async Task<Order> GetOrderAsync(int id) =>
    await _repository.GetAsync(id);

// ✅ Good: Explicit logging
public async Task<Order> GetOrderAsync(int id)
{
    try
    {
        return await _repository.GetAsync(id);
    }
    catch (Exception ex)
    {
        _logger.LogError(ex, "Failed to get order {OrderId}", id);
        throw;
    }
}
```

**Benefit:** Proper error handling

### 3.5 CancellationToken Support

**Pattern:** Accept and honor CancellationToken.

```csharp
// ✅ Good: Accept CancellationToken
public async Task<List<Order>> GetOrdersAsync(
    CancellationToken cancellationToken = default)
{
    var orders = await _repository.GetAllAsync(cancellationToken)
        .ConfigureAwait(false);
    
    return orders;
}

// ✅ Good: Pass through the chain
public class OrderService
{
    public async Task ProcessOrdersAsync(CancellationToken cancellationToken)
    {
        var orders = await _repository.GetAllAsync(cancellationToken)
            .ConfigureAwait(false);
        
        foreach (var order in orders)
        {
            cancellationToken.ThrowIfCancellationRequested();
            await ProcessAsync(order, cancellationToken);
        }
    }
}
```

**Benefit:** Proper cancellation support

### 3.6 Task.Run for Blocking Calls

**Pattern:** Use Task.Run to offload blocking operations.

```csharp
// ✅ Good: Offload expensive sync work
public async Task<Report> GenerateReportAsync()
{
    var report = await Task.Run(() =>
    {
        // Expensive CPU-bound work on thread pool
        return GenerateExpensiveReport();
    }).ConfigureAwait(false);
    
    return report;
}
```

**Benefit:** Doesn't block async context

### 3.7 ValueTask Optimization

**Pattern:** Use ValueTask to avoid allocations.

```csharp
// ✅ Good: ValueTask for likely-synchronous operations
public ValueTask<Order> GetOrderAsync(int id)
{
    if (_cache.TryGetValue(id, out var order))
    {
        return new ValueTask<Order>(order);  // No allocation
    }
    
    return new ValueTask<Order>(_database.GetAsync(id));
}
```

**Benefit:** Reduces allocation pressure

### 3.8 Async Enumerable Patterns

**Pattern:** Use IAsyncEnumerable for streaming async data.

```csharp
// ✅ Good: Async enumerable
public async IAsyncEnumerable<Order> GetOrdersAsync(
    [EnumeratorCancellation] CancellationToken cancellationToken = default)
{
    var orders = _repository.GetAllAsync(cancellationToken);
    
    await foreach (var order in orders.WithCancellation(cancellationToken))
    {
        yield return order;
    }
}

// Usage
await foreach (var order in GetOrdersAsync())
{
    await ProcessAsync(order);
}
```

**Benefit:** Streaming async data

### 3.9 Timeout Handling

**Pattern:** Apply timeouts to async operations.

```csharp
// ✅ Good: Timeout protection
public async Task<Order> GetOrderWithTimeoutAsync(int id)
{
    using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(5));
    
    try
    {
        return await _repository.GetAsync(id, cts.Token)
            .ConfigureAwait(false);
    }
    catch (OperationCanceledException)
    {
        throw new TimeoutException("Order retrieval timed out");
    }
}
```

**Benefit:** Prevents hanging operations

### 3.10 Parallel Async Operations

**Pattern:** Execute multiple async operations in parallel.

```csharp
// ✅ Good: Parallel async
public async Task<(Order, Customer, List<OrderItem>)> GetOrderDetailsAsync(int id)
{
    var orderTask = _orderService.GetAsync(id);
    var customerTask = _customerService.GetAsync(id);
    var itemsTask = _itemService.GetByOrderAsync(id);
    
    await Task.WhenAll(orderTask, customerTask, itemsTask)
        .ConfigureAwait(false);
    
    return (orderTask.Result, customerTask.Result, itemsTask.Result);
}
```

**Benefit:** Parallel I/O operations

---

## Pattern 4: LINQ Excellence

### 4.1 Query vs Method Syntax Consistency

**Pattern:** Choose query or method syntax consistently.

```csharp
// ✅ Consistent: Method syntax (modern preference)
var activeUsers = context.Users
    .Where(u => u.IsActive)
    .OrderBy(u => u.Name)
    .Select(u => new { u.Id, u.Name })
    .ToList();

// ✅ Consistent: Query syntax (for complex queries)
var expensiveOrders = (from o in context.Orders
                       where o.Amount > 5000
                       orderby o.CreatedAt descending
                       select o).ToList();
```

**Benefit:** Code consistency

### 4.2 Fluent Chaining

**Pattern:** Chain LINQ operators fluidly.

```csharp
// ✅ Good: Fluent chaining
var result = context.Orders
    .Where(o => o.Status == "Open")
    .Where(o => o.Amount > 1000)
    .OrderByDescending(o => o.CreatedAt)
    .Select(o => new OrderDTO { Id = o.Id, Amount = o.Amount })
    .AsNoTracking()
    .ToList();
```

**Benefit:** Readable, chainable operations

### 4.3 Type Inference

**Pattern:** Let LINQ infer types.

```csharp
// ✅ Good: Type inference
var users = context.Users  // Inferred as IQueryable<User>
    .Where(u => u.IsActive)
    .ToList();  // Now List<User>

// ✅ Good: Anonymous types
var summary = context.Orders
    .GroupBy(o => o.Status)
    .Select(g => new { Status = g.Key, Count = g.Count() })
    .ToList();
```

**Benefit:** Less verbose code

### 4.4 Lazy Evaluation

**Pattern:** Leverage lazy evaluation for performance.

```csharp
// ✅ Good: Lazy until enumeration
var query = context.Orders
    .Where(o => o.IsActive);

// Not executed yet
if (query.Any())
{
    var orders = query.ToList();  // Executed here
}
```

**Benefit:** Deferred execution

### 4.5 Stream Processing

**Pattern:** Process streams with yield for memory efficiency.

```csharp
// ✅ Good: Streaming
public IEnumerable<ProcessedOrder> ProcessOrders()
{
    var orders = context.Orders
        .Where(o => o.IsActive)
        .AsEnumerable();
    
    foreach (var order in orders)
    {
        yield return new ProcessedOrder { /* ... */ };
    }
}
```

**Benefit:** Memory efficient

### 4.6 Parallel LINQ Where Appropriate

**Pattern:** Use PLINQ for CPU-intensive operations.

```csharp
// ✅ Good: Parallel processing for expensive computation
var results = data
    .AsParallel()
    .Where(x => ExpensiveValidation(x))
    .Select(x => Transform(x))
    .ToList();
```

**Benefit:** Multi-core utilization

---

## Pattern 5: Code Organization & SOLID

### 5.1 Single Responsibility Principle

**Pattern:** One class, one reason to change.

```csharp
// ❌ Bad: Multiple responsibilities
public class OrderProcessor
{
    public void Process(Order order)
    {
        // Calculate tax - TAX responsibility
        var tax = order.Amount * 0.10m;
        
        // Send email - EMAIL responsibility
        SendEmail($"Order {order.Id} processed");
        
        // Log - LOGGING responsibility
        File.WriteAllText("log.txt", "Processed");
        
        // Save - PERSISTENCE responsibility
        database.SaveOrder(order);
    }
}

// ✅ Good: Single responsibility
public class OrderService
{
    private readonly ITaxCalculator _taxCalculator;
    private readonly IEmailService _emailService;
    private readonly ILogger _logger;
    private readonly IOrderRepository _repository;
    
    public async Task ProcessAsync(Order order)
    {
        var tax = _taxCalculator.Calculate(order);
        await _emailService.SendAsync(order.CustomerId, $"Order {order.Id} processed");
        _logger.LogInformation("Order {OrderId} processed", order.Id);
        await _repository.SaveAsync(order);
    }
}
```

**Benefit:** Maintainability, testability

### 5.2 Open/Closed Principle

**Pattern:** Open for extension, closed for modification.

```csharp
// ✅ Good: Extensible
public interface INotificationService
{
    Task SendAsync(string recipient, string message);
}

public class EmailNotification : INotificationService
{
    public async Task SendAsync(string recipient, string message) { }
}

public class SmsNotification : INotificationService
{
    public async Task SendAsync(string recipient, string message) { }
}

// New notification types added without modifying existing code
```

**Benefit:** Easy to extend

### 5.3 Liskov Substitution Principle

**Pattern:** Subtypes must be substitutable for base types.

```csharp
// ✅ Good: Proper inheritance
public abstract class Notification
{
    public abstract Task SendAsync(string recipient, string message);
}

public class EmailNotification : Notification
{
    public override async Task SendAsync(string recipient, string message)
    {
        // Can always be used where Notification expected
    }
}

// ✅ Usage
public class NotificationHandler
{
    public async Task SendAsync(Notification notification, string recipient, string msg)
    {
        await notification.SendAsync(recipient, msg);
    }
}
```

**Benefit:** Proper polymorphism

### 5.4 Interface Segregation Principle

**Pattern:** Specific interfaces, not fat ones.

```csharp
// ❌ Bad: Fat interface
public interface IOrderService
{
    Task<Order> GetAsync(int id);
    Task SaveAsync(Order order);
    Task DeleteAsync(int id);
    Task SendEmailAsync(Order order);
    Task GenerateReportAsync(Order order);
}

// ✅ Good: Segregated interfaces
public interface IOrderRepository
{
    Task<Order> GetAsync(int id);
    Task SaveAsync(Order order);
    Task DeleteAsync(int id);
}

public interface IOrderNotification
{
    Task SendEmailAsync(Order order);
}

public interface IOrderReporting
{
    Task GenerateReportAsync(Order order);
}
```

**Benefit:** Flexible composition

### 5.5 Dependency Inversion Principle

**Pattern:** Depend on abstractions, not implementations.

```csharp
// ❌ Bad: Concrete dependency
public class OrderService
{
    private SqlOrderRepository _repository = new();
    
    public Order GetOrder(int id) => _repository.Get(id);
}

// ✅ Good: Abstract dependency
public class OrderService
{
    private readonly IOrderRepository _repository;
    
    public OrderService(IOrderRepository repository)
    {
        _repository = repository;
    }
    
    public async Task<Order> GetOrderAsync(int id) =>
        await _repository.GetAsync(id);
}
```

**Benefit:** Testability, flexibility

### 5.6 DRY (Don't Repeat Yourself)

**Pattern:** Extract common logic.

```csharp
// ❌ Bad: Duplicated logic
public class UserService
{
    public async Task<User> GetByEmailAsync(string email)
    {
        if (string.IsNullOrEmpty(email))
            throw new ArgumentException("Email required");
        
        var user = await _repository.GetByEmailAsync(email);
        if (user == null)
            throw new NotFoundException("User not found");
        
        return user;
    }
    
    public async Task<User> GetByNameAsync(string name)
    {
        if (string.IsNullOrEmpty(name))
            throw new ArgumentException("Name required");
        
        var user = await _repository.GetByNameAsync(name);
        if (user == null)
            throw new NotFoundException("User not found");
        
        return user;
    }
}

// ✅ Good: DRY
private T EnsureFound<T>(T entity, string identifier) =>
    entity ?? throw new NotFoundException($"{typeof(T).Name} '{identifier}' not found");

public async Task<User> GetByEmailAsync(string email) =>
    EnsureFound(await _repository.GetByEmailAsync(email), email);

public async Task<User> GetByNameAsync(string name) =>
    EnsureFound(await _repository.GetByNameAsync(name), name);
```

**Benefit:** Maintainability, consistency

### 5.7 Composition Over Inheritance

**Pattern:** Favor composition for flexibility.

```csharp
// ❌ Bad: Deep inheritance
public class Order { }
public class SpecialOrder : Order { }
public class VipOrder : SpecialOrder { }

// ✅ Good: Composition
public class Order
{
    public required int Id { get; init; }
    public required IOrderStrategy Strategy { get; init; }
    public required IOrderValidator Validator { get; init; }
}

public interface IOrderStrategy { }
public class SpecialOrderStrategy : IOrderStrategy { }

// Mix and match without inheritance
var order = new Order
{
    Id = 1,
    Strategy = new SpecialOrderStrategy(),
    Validator = new StrictValidator()
};
```

**Benefit:** Flexibility, testability

### 5.8 Fail Fast

**Pattern:** Validate early and throw meaningful exceptions.

```csharp
// ❌ Bad: Fail late with poor message
public void ProcessOrder(Order order)
{
    // Later: NullReferenceException
    var total = order.Items.Sum(i => i.Price);
}

// ✅ Good: Fail fast with clear message
public void ProcessOrder(Order order)
{
    if (order == null)
        throw new ArgumentNullException(nameof(order));
    
    if (order.Items == null || !order.Items.Any())
        throw new InvalidOperationException("Order must have items");
    
    var total = order.Items.Sum(i => i.Price);
}
```

**Benefit:** Clear error messages

### 5.9 Abstraction Levels

**Pattern:** Keep abstraction levels consistent.

```csharp
// ✅ Good: Consistent abstraction
public async Task<IResult> CreateOrderAsync(CreateOrderRequest request)
{
    // High level
    var order = await _service.CreateAsync(request);
    return Results.Created($"/orders/{order.Id}", order);
}

public class OrderService
{
    // Mid level
    public async Task<Order> CreateAsync(CreateOrderRequest request)
    {
        ValidateRequest(request);
        var order = MapToEntity(request);
        return await _repository.SaveAsync(order);
    }
    
    // Low level
    private void ValidateRequest(CreateOrderRequest request)
    {
        if (request.Amount <= 0)
            throw new InvalidOperationException("Amount must be positive");
    }
}
```

**Benefit:** Readability, maintainability

### 5.10 Clear Naming Conventions

**Pattern:** Use clear, intention-revealing names.

```csharp
// ❌ Bad: Unclear names
public class Proc
{
    public async Task Do(Obj o)
    {
        var x = o.Amt * 0.1m;
        var y = o.C?.Get();
        // ...
    }
}

// ✅ Good: Clear names
public class OrderProcessor
{
    public async Task ProcessAsync(Order order)
    {
        var taxAmount = order.Amount * 0.10m;
        var customer = order.Customer?.Get();
        // ...
    }
}
```

**Benefit:** Code readability

---

## Pattern 6: Documentation Best Practices

### 6.1 XML Documentation Comments

**Pattern:** Document public APIs with XML comments.

```csharp
/// <summary>
/// Gets an order by its unique identifier.
/// </summary>
/// <param name="id">The unique order identifier.</param>
/// <returns>The order if found; otherwise null.</returns>
/// <exception cref="ArgumentException">Thrown when id is less than 1.</exception>
public async Task<Order> GetOrderAsync(int id)
{
    if (id < 1)
        throw new ArgumentException("Order ID must be greater than 0", nameof(id));
    
    return await _repository.GetAsync(id);
}
```

**Benefit:** IntelliSense support, documentation generation

### 6.2 Method Documentation

**Pattern:** Document parameters, return values, and exceptions.

```csharp
/// <summary>
/// Calculates the total price including tax for an order.
/// </summary>
/// <param name="order">The order to calculate for.</param>
/// <param name="taxRate">The tax rate as a decimal (e.g., 0.10 for 10%).</param>
/// <returns>The total price including tax.</returns>
/// <exception cref="ArgumentNullException">Thrown when order is null.</exception>
/// <exception cref="ArgumentOutOfRangeException">Thrown when taxRate is negative.</exception>
public decimal CalculateTotalWithTax(Order order, decimal taxRate)
{
    if (order == null)
        throw new ArgumentNullException(nameof(order));
    
    if (taxRate < 0)
        throw new ArgumentOutOfRangeException(nameof(taxRate), "Tax rate cannot be negative");
    
    return order.Amount * (1 + taxRate);
}
```

**Benefit:** Clear API contracts

### 6.3 Complex Logic Comments

**Pattern:** Comment why, not what.

```csharp
// ❌ Bad: Comments describe the obvious
public decimal CalculateDiscount(Order order)
{
    // If order amount is greater than 1000
    if (order.Amount > 1000)
    {
        // Return 0.10 (10% discount)
        return 0.10m;
    }
    
    // Return 0 (no discount)
    return 0m;
}

// ✅ Good: Comments explain why
public decimal CalculateDiscount(Order order)
{
    // VIP customers get 10% discount on orders over $1000
    // to incentivize bulk purchases and improve retention
    return order.Amount > 1000 ? 0.10m : 0m;
}
```

**Benefit:** Understanding design intent

---

## Pattern 7: Error Handling & Logging

### 7.1 Structured Logging

**Pattern:** Use structured logging with parameters.

```csharp
// ❌ Bad: String interpolation
_logger.LogInformation($"Processing order {order.Id} for customer {customer.Name}");

// ✅ Good: Structured logging
_logger.LogInformation("Processing order {OrderId} for customer {CustomerName}",
    order.Id, customer.Name);

// ✅ Good: With levels
_logger.LogInformation("Order processed successfully. OrderId: {OrderId}", order.Id);
_logger.LogWarning("Order {OrderId} has unusual amount {Amount}", order.Id, order.Amount);
_logger.LogError(ex, "Failed to process order {OrderId}", order.Id);
```

**Benefit:** Searchable logs, better analytics

### 7.2 Exception Specificity

**Pattern:** Throw specific, meaningful exceptions.

```csharp
// ❌ Bad: Generic exceptions
throw new Exception("Failed");

// ✅ Good: Specific exceptions
throw new OrderNotFoundException($"Order {id} not found");
throw new InvalidOperationException($"Cannot process order with status {order.Status}");
throw new ArgumentException($"Email format invalid: {email}", nameof(email));
```

**Benefit:** Better error handling

### 7.3 Custom Exception Classes

**Pattern:** Create domain-specific exceptions.

```csharp
// ✅ Good: Custom exceptions
public class OrderNotFoundException : Exception
{
    public int OrderId { get; }
    
    public OrderNotFoundException(int orderId)
        : base($"Order {orderId} not found")
    {
        OrderId = orderId;
    }
}

public class InsufficientInventoryException : Exception
{
    public string ItemCode { get; }
    public int Requested { get; }
    public int Available { get; }
    
    public InsufficientInventoryException(string itemCode, int requested, int available)
        : base($"Item {itemCode}: requested {requested}, available {available}")
    {
        ItemCode = itemCode;
        Requested = requested;
        Available = available;
    }
}
```

**Benefit:** Rich error context

---

## Pattern 8: Testing Best Practices

### 8.1 Arrange-Act-Assert Pattern

**Pattern:** Structure tests with AAA pattern.

```csharp
[Fact]
public async Task CreateOrder_WithValidData_ReturnsCreatedOrder()
{
    // Arrange
    var request = new CreateOrderRequest { CustomerId = 1, Amount = 99.99m };
    var service = new OrderService(_repository.Object);
    
    // Act
    var result = await service.CreateAsync(request);
    
    // Assert
    Assert.NotNull(result);
    Assert.Equal(request.Amount, result.Amount);
}
```

**Benefit:** Clear test structure

### 8.2 Descriptive Test Names

**Pattern:** Name tests clearly about what they test.

```csharp
[Fact]
public async Task GetOrder_WhenOrderExists_ReturnsOrder() { }

[Fact]
public async Task GetOrder_WhenOrderDoesNotExist_ThrowsNotFoundException() { }

[Theory]
[InlineData(0)]
[InlineData(-1)]
public async Task GetOrder_WhenIdIsInvalid_ThrowsArgumentException(int invalidId) { }
```

**Benefit:** Self-documenting tests

### 8.3 Mock Dependencies

**Pattern:** Use mocks to isolate units.

```csharp
[Fact]
public async Task ProcessOrder_CallsRepository_WithCorrectOrder()
{
    // Arrange
    var mockRepository = new Mock<IOrderRepository>();
    var order = new Order { Id = 1, Amount = 99.99m };
    var service = new OrderService(mockRepository.Object);
    
    // Act
    await service.ProcessAsync(order);
    
    // Assert
    mockRepository.Verify(
        x => x.SaveAsync(It.IsAny<Order>()),
        Times.Once);
}
```

**Benefit:** Isolated testing

---

## Performance Targets

| Metric | Target | Notes |
|--------|--------|-------|
| Compilation | <5s | Incremental builds |
| Runtime | Baseline + 5% | No regressions |
| Memory | Minimize allocations | <100MB baseline |
| GC | <2% pause time | Smooth performance |
| Test Coverage | >80% | Critical paths |

---

## Summary Checklist

When modernizing C# code, verify:

- [ ] Using records for DTOs
- [ ] Init-only properties for immutability
- [ ] Nullable reference types enabled
- [ ] Pattern matching for type checks
- [ ] File-scoped namespaces
- [ ] Global usings for common imports
- [ ] Async/await throughout
- [ ] No .Result or .Wait()
- [ ] ConfigureAwait(false) in libraries
- [ ] CancellationToken support
- [ ] DI container for all services
- [ ] LINQ for queries, not loops
- [ ] SOLID principles applied
- [ ] XML documentation on public APIs
- [ ] Structured logging
- [ ] Custom exceptions
- [ ] Proper unit tests
- [ ] No string interpolation in logs

---

## Tools & Resources

- **Code Analysis:** Roslyn Analyzers, StyleCop
- **Testing:** xUnit, Moq, NSubstitute
- **Performance:** BenchmarkDotNet, dotTrace
- **Documentation:** DocFX, Doxygen
- **Logging:** Serilog, NLog
- **DI:** Microsoft.Extensions.DependencyInjection
