# Code Quality Scoring System for Phase 5-6

## Overview

This document defines a comprehensive code quality scoring system for Phase 5-6 agent code generation. The system measures four key dimensions and combines them into an overall quality score with target ranges.

---

## Metric 1: LINQ Adherence (0-100)

### Scoring Rubric

| Score | Level | Description | Key Indicators |
|-------|-------|-------------|-----------------|
| 0-20 | Critical | No LINQ optimization patterns applied | Uses loops, multiple materializations, N+1 queries |
| 21-40 | Poor | Basic LINQ used but poorly optimized | Some Where/Select used; materializes prematurely |
| 41-60 | Good | Solid LINQ patterns with minor issues | Proper projections, some query optimization |
| 61-80 | Excellent | Professional LINQ patterns (TARGET) | AsNoTracking, deferred execution, optimized joins |
| 81-100 | Expert | Advanced optimization patterns | Compiled queries, expression trees, PLINQ |

### Scoring Criteria

**0-20 Points: Critical Issues**

```csharp
// ❌ Examples that score 0-20
var data = context.Orders.ToList();  // Loads everything
foreach (var order in data)  // Loop instead of LINQ
{
    if (order.Amount > 1000)  // Client-side filtering
    {
        // Process
    }
}

var result = data.Where(x => x.Status == "Open").ToList();  // After loading all
```

**21-40 Points: Poor LINQ**

```csharp
// ⚠️ Examples that score 21-40
var orders = context.Orders
    .Where(o => o.Amount > 1000)
    .ToList()  // Materializes early
    .Where(o => o.Status == "Open")  // Client-side second filter
    .ToList();
```

**41-60 Points: Good LINQ**

```csharp
// ✅ Examples that score 41-60
var orders = context.Orders
    .Where(o => o.Amount > 1000)
    .Where(o => o.Status == "Open")  // Good filtering order
    .Select(o => new { o.Id, o.Amount })  // Projects early
    .ToList();
```

**61-80 Points: Excellent LINQ (TARGET)**

```csharp
// ✅✅ Examples that score 61-80 (TARGET)
var orders = context.Orders
    .AsNoTracking()  // No change tracking
    .Where(o => o.Amount > 1000)
    .Where(o => o.Status == "Open")
    .OrderBy(o => o.CreatedAt)  // Indexed column
    .Select(o => new OrderDTO { Id = o.Id, Amount = o.Amount })
    .Take(100)  // Pagination
    .ToListAsync();
```

**81-100 Points: Expert LINQ**

```csharp
// 🎯 Examples that score 81-100 (EXPERT)
private static readonly Func<AppContext, string, Task<List<Order>>>
    GetOrdersByStatusCompiledQuery = EF.CompileAsyncQuery(
        (AppContext ctx, string status) =>
            ctx.Orders
                .AsNoTracking()
                .Where(o => o.Status == status)
                .OrderBy(o => o.CreatedAt)
                .Select(o => new OrderDTO { Id = o.Id, Amount = o.Amount })
                .ToList());

public async Task<List<OrderDTO>> GetOrdersAsync(string status)
{
    return await GetOrdersByStatusCompiledQuery(_context, status);
}
```

### Points Assignment Checklist

For each file/method, check these criteria and add points:

| Criterion | Points | Present? |
|-----------|--------|----------|
| Uses Where before Select | +5 | [ ] |
| Projects early (Select with only needed columns) | +5 | [ ] |
| AsNoTracking for reads | +5 | [ ] |
| No ToList() between filters | +5 | [ ] |
| FirstOrDefault instead of SingleOrDefault where appropriate | +3 | [ ] |
| Skip/Take for pagination | +3 | [ ] |
| OrderBy on indexed columns | +3 | [ ] |
| Deferred execution (returns IEnumerable/IQueryable) | +5 | [ ] |
| Joins optimized (on keys) | +5 | [ ] |
| Aggregates server-side (Sum/Count/Avg) | +5 | [ ] |
| No N+1 queries (Include instead of loops) | +10 | [ ] |
| Compiled queries for repeated use | +5 | [ ] |
| Expression trees used for dynamic queries | +5 | [ ] |
| Parallel LINQ where CPU-intensive | +5 | [ ] |
| No string interpolation in predicates | +3 | [ ] |

**Total: Add up points, cap at 100**

---

## Metric 2: C# Modernization (0-100)

### Scoring Rubric

| Score | Level | Description | Key Indicators |
|-------|-------|-------------|-----------------|
| 0-20 | Legacy | Old C# patterns (.NET Framework style) | No async, old class patterns |
| 21-40 | Transitional | Some modern features | Some async, some records |
| 41-60 | Good | Solid modernization with gaps | C# 9 features, async/await |
| 61-80 | Excellent | Excellent C# 10+ (TARGET) | Records, init properties, pattern matching |
| 81-100 | Expert | Advanced C# 11+ patterns | Required members, raw strings |

### Scoring Criteria

**0-20 Points: Legacy Code**

```csharp
// ❌ Legacy patterns
public class UserDto
{
    public int Id { get; set; }
    public string Name { get; set; }
    
    public override bool Equals(object obj) { }
    public override int GetHashCode() { }
}

public List<User> GetUsers()  // Sync
{
    return _repository.GetAll();
}

public class Services
{
    public Services() 
    {
        _repo = new Repository();  // Manual instantiation
    }
}
```

**21-40 Points: Some Modern Features**

```csharp
// ⚠️ Mixed old and new
public record UserDto(int Id, string Name);  // Good

public List<User> GetUsers()  // Still sync
{
    return _repository.GetAll();
}
```

**41-60 Points: Good Modernization**

```csharp
// ✅ Good modern code
public record UserDto(int Id, string Name);

public async Task<List<User>> GetUsersAsync()
{
    return await _repository.GetAllAsync();
}

public class UserService
{
    private readonly IUserRepository _repository;
    
    public UserService(IUserRepository repository) // DI
    {
        _repository = repository;
    }
}
```

**61-80 Points: Excellent C# 10+ (TARGET)**

```csharp
// ✅✅ Target modern code
namespace MyApp.Services;

public record UserDto
{
    public required int Id { get; init; }
    public required string Name { get; init; }
}

public class UserService
{
    private readonly IUserRepository _repository;
    
    public UserService(IUserRepository repository)
    {
        _repository = repository;
    }
    
    public async Task<List<UserDto>> GetActiveUsersAsync(
        CancellationToken cancellationToken = default)
    {
        return await _repository
            .GetAsync(u => u.IsActive, cancellationToken)
            .ConfigureAwait(false);
    }
    
    public decimal GetDiscount(User user) =>
        user switch
        {
            { IsVip: true, YearsActive: > 5 } => 0.20m,
            { IsVip: true } => 0.10m,
            _ => 0m
        };
}
```

**81-100 Points: Expert C# 11+**

```csharp
// 🎯 Expert patterns
namespace MyApp.Services;

global using System;
global using System.Collections.Generic;

public record UserDto
{
    public required int Id { get; init; }
    public required string Name { get; init; }
}

public class UserService
{
    private readonly IUserRepository _repository;
    private readonly ILogger<UserService> _logger;
    
    public UserService(
        IUserRepository repository,
        ILogger<UserService> logger)
    {
        _repository = repository;
        _logger = logger;
    }
    
    /// <summary>
    /// Gets active users asynchronously.
    /// </summary>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>List of active users.</returns>
    public async Task<List<UserDto>> GetActiveUsersAsync(
        CancellationToken cancellationToken = default)
    {
        _logger.LogInformation("Retrieving active users");
        
        var users = await _repository
            .GetAsync(u => u.IsActive, cancellationToken)
            .ConfigureAwait(false);
        
        _logger.LogInformation("Retrieved {Count} active users", users.Count);
        return users;
    }
}
```

### Points Assignment Checklist

| Criterion | Points | Present? |
|-----------|--------|----------|
| Nullable reference types enabled | +5 | [ ] |
| File-scoped namespaces | +3 | [ ] |
| Records for DTOs | +5 | [ ] |
| Init-only properties | +3 | [ ] |
| Target-typed new() | +2 | [ ] |
| Pattern matching used | +5 | [ ] |
| Async/await throughout | +10 | [ ] |
| No .Result or .Wait() | +10 | [ ] |
| ConfigureAwait(false) in libraries | +5 | [ ] |
| CancellationToken support | +5 | [ ] |
| DI container (not manual) | +10 | [ ] |
| No hardcoded strings/magic numbers | +3 | [ ] |
| Global usings | +2 | [ ] |
| XML documentation | +5 | [ ] |
| Method naming conventions | +3 | [ ] |
| SOLID principles | +5 | [ ] |

**Total: Add up points, cap at 100**

---

## Metric 3: Documentation Quality (0-100)

### Scoring Rubric

| Score | Level | Description | Key Indicators |
|-------|-------|-------------|-----------------|
| 0-20 | Missing | No documentation | No XML docs, no comments |
| 21-40 | Minimal | Sparse documentation | Some methods documented |
| 41-60 | Good | Solid documentation with gaps | 60% coverage, some details |
| 61-80 | Excellent | Comprehensive (TARGET) | 90%+ coverage, clear examples |
| 81-100 | Expert | Exceptional documentation | Examples, edge cases explained |

### Documentation Checklist

| Item | Points | Present? |
|------|--------|----------|
| XML docs on public methods | +10 | [ ] |
| Parameters documented | +10 | [ ] |
| Return value documented | +5 | [ ] |
| Exceptions documented | +5 | [ ] |
| Class-level documentation | +5 | [ ] |
| Example code in docs | +5 | [ ] |
| Edge cases explained | +5 | [ ] |
| Performance notes | +5 | [ ] |
| Threading/concurrency notes | +5 | [ ] |
| Configuration instructions | +5 | [ ] |
| README present | +10 | [ ] |
| Architecture documented | +5 | [ ] |
| Usage examples | +5 | [ ] |

**Total: Add up points, cap at 100**

---

## Metric 4: Dependency Health (0-100)

### Scoring Rubric

| Score | Level | Description | Key Indicators |
|-------|-------|-------------|-----------------|
| 0-20 | Critical | Bloated dependencies | Many unused packages |
| 21-40 | Poor | Some unused packages | Transitive bloat |
| 41-60 | Good | Reasonable dependencies | Mostly used, some cleanup |
| 61-80 | Excellent | Optimized (TARGET) | Minimal, necessary only |
| 81-100 | Expert | Highly optimized | Pinned versions, minimal |

### Scoring Criteria

**0-20 Points: Bloated**

```xml
<!-- Many unused packages -->
<PackageReference Include="Unused.Package1" Version="1.0" />
<PackageReference Include="Unused.Package2" Version="2.0" />
<PackageReference Include="Package3" Version="3.0" />
<!-- Only Package3 is used -->
```

**21-40 Points: Poor**

```xml
<!-- Some cleanup needed -->
<PackageReference Include="EntityFramework" Version="6.0" />  <!-- Old -->
<PackageReference Include="Newtonsoft.Json" Version="9.0" />  <!-- Very old -->
<PackageReference Include="UsefulPackage" Version="1.0" />
```

**41-60 Points: Good**

```xml
<!-- Mostly clean -->
<PackageReference Include="EntityFrameworkCore" Version="7.0" />
<PackageReference Include="Microsoft.Extensions.DependencyInjection" Version="7.0" />
<PackageReference Include="Serilog" Version="3.0" />
<!-- Few unused transitive dependencies -->
```

**61-80 Points: Excellent (TARGET)**

```xml
<!-- Optimized -->
<PackageReference Include="EntityFrameworkCore" Version="7.0" />
<PackageReference Include="Microsoft.Extensions.DependencyInjection" Version="7.0" />
<PackageReference Include="Serilog" Version="3.0" />
<!-- Only essential packages, no unused transitive deps -->
```

**81-100 Points: Expert**

```xml
<!-- Highly optimized with pinned versions -->
<PackageReference Include="EntityFrameworkCore" Version="7.0.5" />  <!-- Pinned -->
<PackageReference Include="Microsoft.Extensions.DependencyInjection" Version="7.0.0" />
<PackageReference Include="Serilog" Version="3.0.1" />
<!-- Source-linked for debugging, minimal transitive deps -->
```

### Points Assignment Checklist

| Criterion | Points | Present? |
|-----------|--------|----------|
| No unused NuGet packages | +15 | [ ] |
| All packages up-to-date | +10 | [ ] |
| No deprecated packages | +10 | [ ] |
| Minimal transitive dependencies | +10 | [ ] |
| Version pinning for stability | +10 | [ ] |
| License compatibility checked | +5 | [ ] |
| Security vulnerabilities none | +10 | [ ] |
| Vulnerability scanning enabled | +5 | [ ] |
| Package sizes reasonable | +5 | [ ] |
| No version conflicts | +5 | [ ] |

**Total: Add up points, cap at 100**

---

## Overall Code Quality Score Formula

### Weighted Calculation

```
Overall Score = (LINQ_Score × 0.30) 
              + (Modernization_Score × 0.30) 
              + (Documentation_Score × 0.25) 
              + (Dependencies_Score × 0.15)
```

### Score Interpretation

| Range | Assessment | Action |
|-------|-----------|--------|
| 0-30 | Critical | Complete rewrite needed |
| 31-50 | Poor | Major refactoring required |
| 51-70 | Acceptable | Improvements suggested |
| 71-85 | Good | Minor optimizations |
| 86-95 | Excellent | Production ready |
| 96-100 | Exceptional | Example code |

---

## Phase 5-6 Target Scores

### Minimum Acceptable (Entry Point)

- LINQ Adherence: 60
- Modernization: 65
- Documentation: 70
- Dependencies: 70
- **Overall: 67**

### Target (Standard)

- LINQ Adherence: 75
- Modernization: 78
- Documentation: 80
- Dependencies: 78
- **Overall: 77**

### Excellence (Stretch Goal)

- LINQ Adherence: 85
- Modernization: 88
- Documentation: 90
- Dependencies: 85
- **Overall: 87**

---

## Scoring Workflow for Phase 5-6 Code

### 1. Analyze Single Method

```
For each method in generated code:
1. Count LINQ optimization patterns: ___/100
2. Count modernization patterns: ___/100
3. Check documentation completeness: ___/100
4. Review dependencies used: ___/100
5. Calculate overall: ___/100
6. Record in tracking sheet
```

### 2. File-Level Scoring

```
For each file:
1. Average method scores (if multiple)
2. Add file-level bonuses/penalties
3. Document score in comment
4. Flag areas for improvement
```

### 3. Project-Level Scoring

```
For the entire project:
1. Average all file scores
2. Identify patterns (consistent issues)
3. Report summary statistics
4. Provide improvement roadmap
```

### 4. Feedback Generation

```
Score 0-20:  "Critical issues detected. Major refactoring needed."
Score 21-40: "Poor patterns. Consider complete redesign."
Score 41-60: "Acceptable but needs improvement. See notes."
Score 61-80: "Good code. Minor optimizations available."
Score 81-100:"Excellent code. Production ready."
```

---

## Anti-Patterns & Deductions

| Anti-Pattern | Deduction | Example |
|--------------|-----------|---------|
| N+1 queries | -20 | Loop with query inside |
| Premature materialization | -15 | Multiple ToList() calls |
| No async/await | -20 | Sync all the way |
| Missing null checks | -10 | Potential NullRefException |
| No documentation | -15 | Zero XML docs |
| Unused packages | -5 per package | Bloated dependencies |
| Magic strings/numbers | -5 | Hardcoded values |
| Poor naming | -5 | Unclear variable names |
| Wrong exception types | -5 | Generic Exception |
| Missing ConfigureAwait | -3 | Library async code |

---

## Scoring Examples

### Example 1: Method Scoring

```csharp
public async Task<List<Order>> GetActiveOrdersAsync()
{
    var orders = context.Orders  // ✓ Uses context
        .AsNoTracking()  // ✓+5 LINQ
        .Where(o => o.IsActive)  // ✓+5 LINQ
        .OrderBy(o => o.CreatedAt)  // ✓+3 LINQ (indexed)
        .Select(o => new { o.Id, o.Amount })  // ✓+5 LINQ (early projection)
        .ToListAsync();  // ✓+5 async
    
    return orders;
}
```

**Score Breakdown:**

- LINQ: 5+5+3+5 = 18 (capped at reasonable amount) = 60-70 range
- Modernization: async/await = 70+ range
- Documentation: MISSING = 0
- Dependencies: Standard = 75+
- **Overall: ~50-55 (below target due to missing docs)**

### Example 2: Project Scoring

**10 files analyzed:**

- 3 files score 85+ (excellent)
- 5 files score 75-84 (good)
- 2 files score 60-74 (acceptable)

**Average Scores:**

- LINQ: (90+88+87+78+75+72+71+70+68+65)/10 = 76.4
- Modernization: (92+90+88+80+76+73+70+68+65+62)/10 = 76.4
- Documentation: (85+82+80+78+76+75+74+72+70+68)/10 = 76.0
- Dependencies: (88+85+82+78+75+72+70+68+65+60)/10 = 74.3

**Overall Score:**
= (76.4 × 0.30) + (76.4 × 0.30) + (76.0 × 0.25) + (74.3 × 0.15)
= 22.9 + 22.9 + 19.0 + 11.1
= **75.9** (Good - close to target)

---

## Continuous Improvement Tracking

### Score Trend Analysis

Track scores over time to show improvement:

| Iteration | LINQ | Modern | Docs | Deps | Overall | Improvement |
|-----------|------|--------|------|------|---------|------------|
| Phase 5.1 | 65   | 68     | 65   | 70   | 67.0    | Baseline   |
| Phase 5.2 | 72   | 75     | 72   | 75   | 73.1    | +6.1       |
| Phase 5.3 | 78   | 82     | 80   | 80   | 80.0    | +13.0      |
| Phase 6.0 | 85   | 88     | 88   | 85   | 86.4    | +19.4      |

### Improvement Focus Areas

Based on lagging metrics, prioritize improvements:

```
If LINQ is lagging:
→ Review LINQ_OPTIMIZATION_GUIDE.md
→ Apply patterns: Where before Select, AsNoTracking, etc.

If Modernization is lagging:
→ Review CSHARP_MODERNIZATION_GUIDE.md
→ Upgrade: records, init properties, async/await, etc.

If Documentation is lagging:
→ Add XML documentation comments
→ Document parameters, returns, exceptions

If Dependencies is lagging:
→ Run: dotnet list package --outdated
→ Remove unused packages
→ Update to latest versions
```

---

## Tools for Automation

### Roslyn Analyzer Configuration

```xml
<!-- .editorconfig -->
[*.cs]
dotnet_diagnostic.CA1802.severity = warning
dotnet_diagnostic.CA1806.severity = warning
dotnet_diagnostic.CA1810.severity = warning
dotnet_diagnostic.CA1815.severity = warning
```

### Code Quality Tools

- **StyleCop Analyzers**: Enforces consistent style
- **Roslynator**: Syntax/LINQ analysis
- **Sonarqube**: Comprehensive analysis
- **CodeMetrics**: Complexity measurement
- **Prolint**: Dependency analysis
