# Real-Time Coaching Recommendations for Phase 5-6 Code

## Overview

This guide provides real-time coaching feedback for Phase 5-6 code generation. Each rule detects specific anti-patterns and provides actionable coaching suggestions.

---

## Section 1: LINQ Query Coaching

### Coaching Rule 1.1: Multiple Materializations

**Detection Pattern:**

```csharp
// ❌ RED FLAG: ToList() called multiple times
var result = data.Where(x => condition).ToList().Where(x => another).ToList();
var result = data.Where(x => x.Active).ToList();
var filtered = result.Where(x => x.Status == "Open").ToList();
```

**Coaching Response:**

```
🎯 COACHING POINT: Multiple Materializations Detected

Pattern: Multiple .ToList() or .ToArray() calls in sequence

Issue:
  - Each ToList() loads data into memory
  - Subsequent filters execute in memory (inefficient)
  - Memory usage multiplies with each materialization

Solution:
  Apply optimization pattern #2.2: Strategic Materialization Points

  // ❌ Before (3 materializations)
  var active = context.Orders.Where(o => o.Status == "Active").ToList();
  var expensive = active.Where(o => o.Amount > 1000).ToList();
  var sorted = expensive.OrderBy(o => o.Date).ToList();

  // ✅ After (1 materialization)
  var sorted = context.Orders
      .Where(o => o.Status == "Active")
      .Where(o => o.Amount > 1000)
      .OrderBy(o => o.Date)
      .ToList();

Expected Impact:
  - 70% reduction in memory usage
  - 3-5x faster execution
  - Single database round-trip

Reference: LINQ_OPTIMIZATION_GUIDE.md - Pattern 2.2
```

---

### Coaching Rule 1.2: AsNoTracking Missing on Reads

**Detection Pattern:**

```csharp
// ❌ RED FLAG: Loading data without AsNoTracking
var reports = context.Reports.Where(r => r.Type == "Summary").ToList();
var userList = context.Users.AsQueryable();  // Change tracking enabled
```

**Coaching Response:**

```
🎯 COACHING POINT: Change Tracking Overhead Detected

Pattern: Read-only query without .AsNoTracking()

Issue:
  - Change tracker monitors entities (unnecessary overhead)
  - Memory usage 30-50% higher than needed
  - CPU overhead detecting changes

Solution:
  Apply optimization pattern #3.3: AsNoTracking for Reads

  // ❌ Before (with tracking)
  var reports = context.Reports
      .Where(r => r.Type == "Summary")
      .ToList();

  // ✅ After (no tracking)
  var reports = context.Reports
      .AsNoTracking()
      .Where(r => r.Type == "Summary")
      .ToList();

When to Use:
  - SELECT queries (reading only)
  - Reports and exports
  - Background jobs
  - Any read-only operation

When NOT to Use:
  - UPDATE/DELETE operations
  - Lazy-loaded navigation properties
  - Operations requiring change detection

Expected Impact:
  - 30-50% faster execution
  - 40% less memory for large result sets

Reference: LINQ_OPTIMIZATION_GUIDE.md - Pattern 3.3
```

---

### Coaching Rule 1.3: Filter Before Projection

**Detection Pattern:**

```csharp
// ❌ RED FLAG: Projects before filtering
var expensive = context.Orders
    .Select(o => new OrderDto { /* many properties */ })
    .Where(o => o.Amount > 1000)
    .ToList();
```

**Coaching Response:**

```
🎯 COACHING POINT: Inefficient Filter Ordering

Pattern: Projection (Select) before filtering (Where)

Issue:
  - Projects ALL records into DTOs/objects
  - Filters AFTER projection (client-side)
  - Wastes CPU/memory on records that will be discarded

Solution:
  Apply optimization pattern #3.1: Filter Before Projection

  // ❌ Before (bad order)
  var expensive = context.Orders
      .Select(o => new OrderDto 
      { 
          Id = o.Id, 
          Amount = o.Amount,
          Customer = o.Customer.Name,
          Items = o.OrderItems.ToList()  // Loads all items!
      })
      .Where(o => o.Amount > 1000)  // Client-side filter
      .ToList();

  // ✅ After (good order)
  var expensive = context.Orders
      .Where(o => o.Amount > 1000)  // Server-side filter first
      .Select(o => new OrderDto
      {
          Id = o.Id,
          Amount = o.Amount,
          Customer = o.Customer.Name
      })
      .ToList();

Ordering Rule:
  1. AsNoTracking() - if read-only
  2. Where() - filter rows
  3. Where() - filter rows again if needed
  4. OrderBy() - sort before Take
  5. Skip/Take() - pagination
  6. Select() - project columns
  7. ToList() - materialize

Expected Impact:
  - 70-90% reduction in data processing
  - 10-100x faster for large datasets

Reference: LINQ_OPTIMIZATION_GUIDE.md - Pattern 3.1
```

---

### Coaching Rule 1.4: N+1 Query Pattern

**Detection Pattern:**

```csharp
// ❌ RED FLAG: Loop with query inside
var customers = context.Customers.ToList();
foreach (var customer in customers)
{
    var orders = context.Orders  // QUERY INSIDE LOOP!
        .Where(o => o.CustomerId == customer.Id)
        .ToList();
    
    customer.Orders = orders;
}
```

**Coaching Response:**

```
🎯 COACHING POINT: N+1 Query Problem Detected

Pattern: Query inside loop (1 query + N queries = N+1)

Issue:
  - First query loads N customers
  - Loop executes N additional queries
  - Total: N+1 database round-trips
  - Example: 1000 customers = 1001 queries!

Solution:
  Apply optimization pattern #5.2: Include/Eager Loading

  // ❌ Before (1 + N queries)
  var customers = context.Customers.ToList();
  foreach (var customer in customers)
  {
      var orders = context.Orders
          .Where(o => o.CustomerId == customer.Id)
          .ToList();
      customer.Orders = orders;
  }

  // ✅ After (1 query total)
  var customers = context.Customers
      .Include(c => c.Orders)  // Single join query
      .ToList();

Alternative Using Select:
  var customersWithOrders = context.Customers
      .Select(c => new
      {
          c.Id,
          c.Name,
          Orders = c.Orders.Where(o => o.Status == "Open").ToList()
      })
      .ToList();

Expected Impact:
  - 1000x faster for 1000 records
  - Reduces database load dramatically
  - Reduces network traffic

Reference: LINQ_OPTIMIZATION_GUIDE.md - Pattern 5.1, 5.2
```

---

### Coaching Rule 1.5: FirstOrDefault vs Single

**Detection Pattern:**

```csharp
// ⚠️ CAUTION: Using Single when First is appropriate
var user = context.Users
    .Where(u => u.Id == id)
    .SingleOrDefaultAsync();  // Checks for exactly 1 or 0
```

**Coaching Response:**

```
🎯 COACHING POINT: Inefficient Single Usage

Pattern: Using Single() when First() would be better

Issue:
  - Single() must verify EXACTLY one match
  - Scans entire result set even after finding match
  - Throws if 0 or >1 found (often overkill)
  - FirstOrDefault() stops after first match

Solution:
  Apply optimization pattern #4.11: Single() vs FirstOrDefault()

  Use FirstOrDefault() when:
  - You expect ≤1 match (normal case)
  - Performance is critical
  - Don't need to validate uniqueness

  Use Single() when:
  - You MUST verify exactly 1 exists
  - Data integrity requires it
  - Can accept performance cost

  // ⚠️ Careful: Single scans all rows
  var user = context.Users
      .Where(u => u.Email == email)
      .SingleOrDefaultAsync();  // Scans until end

  // ✅ Better: First stops early
  var user = context.Users
      .Where(u => u.Email == email)
      .FirstOrDefaultAsync();  // Stops at first match

Expected Impact:
  - 100-1000x faster for large datasets
  - Reduced database load

Reference: LINQ_OPTIMIZATION_GUIDE.md - Pattern 4.11
```

---

## Section 2: C# Async/Await Coaching

### Coaching Rule 2.1: Blocked Async Code

**Detection Pattern:**

```csharp
// ❌ CRITICAL: Using .Result on async method
var result = asyncMethod().Result;

// ❌ CRITICAL: Using .Wait()
asyncMethod().Wait();

// ❌ CRITICAL: Sync wrapper around async
public List<Order> GetOrders()
{
    return GetOrdersAsync().Result;  // DEADLOCK RISK!
}
```

**Coaching Response:**

```
🎯 COACHING POINT: CRITICAL - Blocked Async Code

Pattern: Using .Result or .Wait() on async methods

Issue:
  - DEADLOCK RISK in UI/ASP.NET contexts
  - Blocks thread unnecessarily
  - Wastes thread pool resources
  - Can hang entire application

Solution:
  Apply modernization pattern #3.1 & #3.2: Async All the Way

  // ❌ WRONG: Blocked call (DEADLOCK RISK!)
  public List<Order> GetOrders()
  {
      return GetOrdersAsync().Result;  // ⚠️ CAN DEADLOCK!
  }

  // ✅ CORRECT: Async all the way
  public async Task<List<Order>> GetOrdersAsync()
  {
      return await _repository.GetOrdersAsync();
  }

  // ✅ CORRECT: Make controller async
  public async Task<IActionResult> GetOrders()
  {
      var orders = await _service.GetOrdersAsync();
      return Ok(orders);
  }

Why .Result Deadlocks:
  1. UI thread calls GetOrdersAsync().Result
  2. Result blocks waiting for task completion
  3. Task tries to post back to UI thread
  4. UI thread is blocked, can't run task callback
  5. Deadlock!

Rule: NEVER use .Result or .Wait() in application code

Expected Impact:
  - Prevents deadlocks
  - Better responsiveness
  - Proper async/await semantics

SEVERITY: CRITICAL
Reference: CSHARP_MODERNIZATION_GUIDE.md - Pattern 3.2
```

---

### Coaching Rule 2.2: Missing ConfigureAwait(false)

**Detection Pattern:**

```csharp
// ⚠️ LIBRARY CODE: Missing ConfigureAwait(false)
public class OrderService
{
    public async Task<Order> GetAsync(int id)
    {
        var order = await _repository.GetAsync(id);  // Missing ConfigureAwait(false)
        return order;
    }
}
```

**Coaching Response:**

```
🎯 COACHING POINT: Library Code Optimization

Pattern: Async library code without ConfigureAwait(false)

Issue:
  - Library code captures UI/ASP.NET context
  - Context switching overhead
  - Reduced thread pool efficiency
  - Can cause deadlocks with .Result calls

Solution:
  Apply modernization pattern #3.3: ConfigureAwait(false)

  // ⚠️ Before (captures context)
  public async Task<Order> GetAsync(int id)
  {
      var order = await _repository.GetAsync(id);
      return order;
  }

  // ✅ After (doesn't capture context)
  public async Task<Order> GetAsync(int id)
  {
      var order = await _repository.GetAsync(id)
          .ConfigureAwait(false);  // Don't capture context
      return order;
  }

When to Use ConfigureAwait(false):
  - Library code
  - Service layer code
  - Backend business logic
  - Any code not needing context

When NOT to Use:
  - UI event handlers (need context)
  - Some ASP.NET scenarios (less critical now)

Expected Impact:
  - Reduced context switching
  - Better scalability
  - Proper library patterns

SEVERITY: MEDIUM (Library code)
Reference: CSHARP_MODERNIZATION_GUIDE.md - Pattern 3.3
```

---

### Coaching Rule 2.3: Missing CancellationToken

**Detection Pattern:**

```csharp
// ❌ Missing CancellationToken parameter
public async Task<List<Order>> GetOrdersAsync()
{
    return await _repository.GetAllAsync();
}

// ❌ Not passing through token
public async Task ProcessAsync()
{
    var orders = await GetOrdersAsync();  // Token not passed
}
```

**Coaching Response:**

```
🎯 COACHING POINT: Cancellation Support Missing

Pattern: Async methods without CancellationToken

Issue:
  - No graceful cancellation support
  - Can't stop long-running operations
  - Resource waste if operation cancelled elsewhere
  - Bad for responsive UIs and timeouts

Solution:
  Apply modernization pattern #3.5: CancellationToken Support

  // ❌ Before (no cancellation)
  public async Task<List<Order>> GetOrdersAsync()
  {
      return await _repository.GetAllAsync();
  }

  // ✅ After (supports cancellation)
  public async Task<List<Order>> GetOrdersAsync(
      CancellationToken cancellationToken = default)
  {
      return await _repository.GetAllAsync(cancellationToken);
  }

  // ✅ Proper usage
  using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(5));
  
  try
  {
      var orders = await GetOrdersAsync(cts.Token);
  }
  catch (OperationCanceledException)
  {
      Console.WriteLine("Operation timed out");
  }

Pattern:
  1. Add CancellationToken parameter with default
  2. Pass through call chain
  3. Check ThrowIfCancellationRequested in loops
  4. Use with TimeSpan for timeouts

Expected Impact:
  - Graceful timeouts
  - Better resource management
  - Responsive cancellation

SEVERITY: MEDIUM
Reference: CSHARP_MODERNIZATION_GUIDE.md - Pattern 3.5
```

---

## Section 3: C# Modernization Coaching

### Coaching Rule 3.1: Old Class Patterns

**Detection Pattern:**

```csharp
// ❌ OLD: Manual DTO with boilerplate
public class UserDto
{
    public int Id { get; set; }
    public string Name { get; set; }
    public string Email { get; set; }
    
    public override bool Equals(object obj) { /* boilerplate */ }
    public override int GetHashCode() { /* boilerplate */ }
    public override string ToString() { /* boilerplate */ }
}
```

**Coaching Response:**

```
🎯 COACHING POINT: Legacy DTO Pattern

Pattern: Manual class with property boilerplate

Issue:
  - 80% boilerplate code
  - Error-prone equality implementation
  - Hard to maintain
  - Verbose and unnecessary

Solution:
  Apply modernization pattern #1.1: Records

  // ❌ Before (legacy pattern - lots of boilerplate)
  public class UserDto
  {
      public int Id { get; set; }
      public string Name { get; set; }
      public override bool Equals(object obj) { }
      public override int GetHashCode() { }
      public override string ToString() { }
  }

  // ✅ After (modern record - clean!)
  public record UserDto(int Id, string Name, string Email);

  // ✅ Alternative: Record with init properties
  public record UserDto
  {
      public required int Id { get; init; }
      public required string Name { get; init; }
      public string? Email { get; init; }
  }

Benefits:
  - Auto-generated Equals/GetHashCode
  - Auto-generated ToString
  - Immutable by default
  - 80% less code

Expected Impact:
  - 50% reduction in file size
  - Fewer bugs
  - Better readability

Reference: CSHARP_MODERNIZATION_GUIDE.md - Pattern 1.1
```

---

### Coaching Rule 3.2: No Dependency Injection

**Detection Pattern:**

```csharp
// ❌ Manual instantiation
public class OrderService
{
    private OrderRepository _repository = new();
    
    public Order GetOrder(int id) => _repository.Get(id);
}

// ❌ Static access
public class Cache
{
    public static Cache Instance = new();
}
```

**Coaching Response:**

```
🎯 COACHING POINT: Dependency Injection Missing

Pattern: Manual instantiation instead of DI

Issue:
  - Hard to test (can't mock)
  - Tight coupling
  - Hard to change implementations
  - Not following modern patterns

Solution:
  Apply modernization pattern #2.1: DI Registration

  // ❌ Before (manual, not testable)
  public class OrderService
  {
      private OrderRepository _repository = new();
  }

  // ✅ After (injected, testable)
  public class OrderService
  {
      private readonly IOrderRepository _repository;
      
      public OrderService(IOrderRepository repository)
      {
          _repository = repository;
      }
  }

  // ✅ Registration
  builder.Services.AddScoped<IOrderRepository, OrderRepository>();
  builder.Services.AddScoped<IOrderService, OrderService>();

Benefits:
  - Easy to test with mocks
  - Easy to swap implementations
  - Clear dependencies
  - Follows SOLID principles

Expected Impact:
  - 100% improvement in testability
  - Easier to refactor
  - Better architecture

Reference: CSHARP_MODERNIZATION_GUIDE.md - Pattern 2
```

---

### Coaching Rule 3.3: Nullable Warnings

**Detection Pattern:**

```csharp
// ⚠️ With Nullable enabled, this warns
public string GetUserName(User user)
{
    return user.Name;  // ⚠️ Name could be null!
}

// ⚠️ Using potentially null value
public void ProcessOrder(Order? order)
{
    decimal total = order.Amount;  // ⚠️ order could be null!
}
```

**Coaching Response:**

```
🎯 COACHING POINT: Nullable Reference Type Warnings

Pattern: Potentially null values without checks

Issue:
  - NullReferenceException risk
  - Compiler warnings if Nullable enabled
  - Unsafe code paths

Solution:
  Apply modernization pattern #1.3: Nullable Reference Types

  // ⚠️ Before (nullable warning)
  public string GetUserName(User user)
  {
      return user.Name;  // Warning: Name might be null
  }

  // ✅ After (clear contract)
  public string GetUserName(User user)
  {
      return user.Name ?? "Unknown";  // Safe
  }

  // ✅ Or enforce non-null input
  public string GetUserName(User user)
  {
      if (user == null)
          throw new ArgumentNullException(nameof(user));
      
      return user.Name;  // Now guaranteed non-null
  }

Pattern:
  - Properties: Use Type? for nullable, Type for non-null
  - Methods: Use ?? to provide defaults
  - Validation: Check before use
  - Document: XML docs should mention null behavior

Enable in Project:
  <PropertyGroup>
      <Nullable>enable</Nullable>
  </PropertyGroup>

Expected Impact:
  - Eliminates null reference exceptions
  - Compiler catches unsafe code
  - Better code quality

Reference: CSHARP_MODERNIZATION_GUIDE.md - Pattern 1.3
```

---

## Section 4: Code Organization Coaching

### Coaching Rule 4.1: Duplicate Code

**Detection Pattern:**

```csharp
// ❌ Duplicated validation logic
public User GetByEmail(string email)
{
    if (string.IsNullOrEmpty(email))
        throw new ArgumentException("Email required");
    return _repository.GetByEmail(email);
}

public User GetByName(string name)
{
    if (string.IsNullOrEmpty(name))
        throw new ArgumentException("Name required");
    return _repository.GetByName(name);
}
```

**Coaching Response:**

```
🎯 COACHING POINT: Code Duplication Detected

Pattern: Same logic repeated multiple times

Issue:
  - Maintenance nightmare (fix in multiple places)
  - Inconsistency risk
  - Violates DRY principle
  - Bloats codebase

Solution:
  Apply SOLID principle #6: DRY (Don't Repeat Yourself)

  // ❌ Before (duplication)
  public User GetByEmail(string email)
  {
      if (string.IsNullOrEmpty(email))
          throw new ArgumentException("Email required");
      return _repository.GetByEmail(email);
  }

  public User GetByName(string name)
  {
      if (string.IsNullOrEmpty(name))
          throw new ArgumentException("Name required");
      return _repository.GetByName(name);
  }

  // ✅ After (extracted)
  private void ValidateNotEmpty(string value, string paramName)
  {
      if (string.IsNullOrEmpty(value))
          throw new ArgumentException($"{paramName} required", paramName);
  }

  public User GetByEmail(string email)
  {
      ValidateNotEmpty(email, nameof(email));
      return _repository.GetByEmail(email);
  }

  public User GetByName(string name)
  {
      ValidateNotEmpty(name, nameof(name));
      return _repository.GetByName(name);
  }

Expected Impact:
  - 30-50% code reduction
  - Easier maintenance
  - Consistency

Reference: CSHARP_MODERNIZATION_GUIDE.md - Pattern 5.6
```

---

### Coaching Rule 4.2: Missing XML Documentation

**Detection Pattern:**

```csharp
// ❌ No documentation
public async Task<Order> GetOrderAsync(int id)
{
    return await _repository.GetAsync(id);
}

// ❌ No parameter docs
public void ProcessOrders(List<Order> orders, bool includeArchived)
{
}
```

**Coaching Response:**

```
🎯 COACHING POINT: Missing Documentation

Pattern: Public method without XML documentation

Issue:
  - No IntelliSense help
  - Unclear parameters/return values
  - Hard to understand intent
  - Poor API documentation

Solution:
  Apply documentation pattern: XML Documentation Comments

  // ❌ Before (no docs)
  public async Task<Order> GetOrderAsync(int id)
  {
      return await _repository.GetAsync(id);
  }

  // ✅ After (complete docs)
  /// <summary>
  /// Gets an order by its unique identifier.
  /// </summary>
  /// <param name="id">The order ID. Must be greater than 0.</param>
  /// <returns>The order if found; otherwise null.</returns>
  /// <exception cref="ArgumentException">Thrown when id is less than 1.</exception>
  public async Task<Order> GetOrderAsync(int id)
  {
      if (id < 1)
          throw new ArgumentException("Order ID must be greater than 0", nameof(id));
      
      return await _repository.GetAsync(id);
  }

Documentation Template:
  /// <summary>[What does this do?]</summary>
  /// <param name="[name]">[What is this for?]</param>
  /// <returns>[What does it return?]</returns>
  /// <exception cref="[Exception]">[When is it thrown?]</exception>

Expected Impact:
  - Better IDE support
  - Self-documenting code
  - Easier onboarding

Reference: CSHARP_MODERNIZATION_GUIDE.md - Pattern 6
```

---

### Coaching Rule 4.3: Magic Numbers/Strings

**Detection Pattern:**

```csharp
// ❌ Magic numbers
if (order.Amount > 1000)  // What's 1000?
{
    discount = 0.10m;  // What's 0.10?
}

// ❌ Magic strings
if (customer.Status == "ACTIVE")  // Hardcoded
{
    // ...
}
```

**Coaching Response:**

```
🎯 COACHING POINT: Magic Values

Pattern: Hardcoded numbers and strings without explanation

Issue:
  - Unclear intent
  - Hard to maintain
  - Error-prone (typos)
  - Difficult to change

Solution:
  Apply SOLID principle #5.9: Use Named Constants

  // ❌ Before (magic values)
  if (order.Amount > 1000)
  {
      discount = 0.10m;
  }
  
  if (customer.Status == "ACTIVE")
  {
      // Process
  }

  // ✅ After (named constants)
  private const decimal MinAmountForDiscount = 1000m;
  private const decimal DiscountRate = 0.10m;
  
  public enum CustomerStatus
  {
      Active = "ACTIVE",
      Inactive = "INACTIVE",
      Pending = "PENDING"
  }
  
  if (order.Amount > MinAmountForDiscount)
  {
      discount = DiscountRate;
  }
  
  if (customer.Status == CustomerStatus.Active)
  {
      // Process
  }

Benefits:
  - Self-documenting
  - Easy to change
  - Prevents typos
  - Clear intent

Expected Impact:
  - 40% improvement in readability
  - Fewer bugs
  - Easier maintenance

Reference: CSHARP_MODERNIZATION_GUIDE.md - Pattern 5.9
```

---

## Section 5: Coaching Workflow

### Phase 5-6 Monitoring Process

```
For each generated code file:

1. LINT CHECK (Automatic)
   ├─ Syntax errors? → Fix immediately
   ├─ Compilation errors? → Fix immediately
   └─ Analysis warnings? → Check coaching rules

2. LINQ CHECK (Patterns 1.1-1.5)
   ├─ Multiple materializations? → Rule 1.1
   ├─ Missing AsNoTracking? → Rule 1.2
   ├─ Project before filter? → Rule 1.3
   ├─ N+1 queries? → Rule 1.4
   └─ Single vs First? → Rule 1.5

3. ASYNC CHECK (Patterns 2.1-2.3)
   ├─ .Result usage? → Rule 2.1 (CRITICAL)
   ├─ .Wait() usage? → Rule 2.1 (CRITICAL)
   ├─ Missing ConfigureAwait? → Rule 2.2
   └─ Missing CancellationToken? → Rule 2.3

4. MODERNIZATION CHECK (Patterns 3.1-3.3)
   ├─ Old class patterns? → Rule 3.1
   ├─ Manual instantiation? → Rule 3.2
   └─ Nullable warnings? → Rule 3.3

5. ORGANIZATION CHECK (Patterns 4.1-4.3)
   ├─ Duplicate code? → Rule 4.1
   ├─ Missing docs? → Rule 4.2
   └─ Magic values? → Rule 4.3

6. SCORE CALCULATION
   ├─ Count violations by category
   ├─ Calculate quality score
   ├─ Generate report
   └─ Track improvements

7. FEEDBACK GENERATION
   ├─ List violations with coaching
   ├─ Provide examples
   ├─ Link to guides
   └─ Suggest improvements

8. TRACK METRICS
   ├─ Record score
   ├─ Compare to target
   ├─ Identify trends
   └─ Report progress
```

---

## Scoring Impact of Violations

| Rule | Severity | Points Lost | Category |
|------|----------|-------------|----------|
| 1.1 Multiple ToList() | High | -10 | LINQ |
| 1.2 Missing AsNoTracking | High | -10 | LINQ |
| 1.3 Project before filter | High | -10 | LINQ |
| 1.4 N+1 queries | Critical | -20 | LINQ |
| 1.5 Single vs First | Medium | -5 | LINQ |
| 2.1 Blocked async (.Result) | Critical | -25 | Async |
| 2.2 Missing ConfigureAwait | Medium | -5 | Async |
| 2.3 Missing CancellationToken | Medium | -5 | Async |
| 3.1 Old patterns | Medium | -10 | Modern |
| 3.2 No DI | High | -15 | Modern |
| 3.3 Nullable warnings | Medium | -8 | Modern |
| 4.1 Duplicate code | Medium | -5 | Org |
| 4.2 Missing XML docs | Low | -3 | Org |
| 4.3 Magic values | Low | -2 | Org |

---

## Quick Reference: Common Issues

**If score is 0-30:**

- Check for CRITICAL patterns (Rule 2.1, 1.4)
- Likely has .Result or N+1 queries
- Review entire approach

**If score is 31-50:**

- Check for HIGH patterns (Rule 1.1, 1.2, 3.2)
- Multiple materialization or DI issues
- Significant refactoring needed

**If score is 51-70:**

- Check for MEDIUM patterns (Rule 1.5, 2.2, 3.1)
- Mostly good, needs polish
- Target improvements: docs, nullability

**If score is 71-85:**

- Check for LOW patterns (Rule 4.2, 4.3)
- Good code, minor optimizations
- Focus on documentation

**If score is 86-100:**

- Excellent code
- Look for edge cases
- Production ready

---

## End of Coaching Guide

Use this framework to provide real-time feedback during Phase 5-6 code generation. Update scores continuously and track improvements toward target scores.
