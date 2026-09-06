# Phase 4 Tier 3: Performance & Best Practices Guide

**Status**: Complete  
**Date**: 2024  
**Target**: Performance optimization best practices, query optimization, caching strategies  

---

## 📖 Table of Contents

1. [Query Optimization Guide](#query-optimization-guide)
2. [Caching Strategies](#caching-strategies)
3. [Memory Management](#memory-management)
4. [Database Best Practices](#database-best-practices)
5. [API Performance](#api-performance)
6. [Common Pitfalls](#common-pitfalls)

---

## Query Optimization Guide

### Principle 1: Use No-Tracking Queries for Read-Only Operations

**Problem**: EF Core tracks all entities by default, using memory for change tracking.

```csharp
// ❌ BAD: Unnecessary tracking
var users = dbContext.Users
    .Where(u => u.IsActive)
    .ToList();  // Memory: 250KB for 1,000 users

// ✅ GOOD: No-tracking for reads
var users = dbContext.Users
    .AsNoTracking()
    .Where(u => u.IsActive)
    .ToList();  // Memory: 120KB for 1,000 users (52% reduction)
```

**Performance Impact**:

- Memory reduction: 40-60%
- CPU reduction: 25-35%
- Recommended for: All read-only queries

**When to Use**:

- Reading data for display
- Reporting and analytics
- API responses (not modifications)

---

### Principle 2: Implement Proper Indexing Strategy

**Problem**: Missing indexes force full table scans.

```csharp
// Database configuration
protected override void OnModelCreating(ModelBuilder modelBuilder)
{
    // ✅ Index on frequently filtered columns
    modelBuilder.Entity<User>()
        .HasIndex(u => u.Email)
        .IsUnique();
    
    modelBuilder.Entity<Order>()
        .HasIndex(o => new { o.UserId, o.CreatedDate })
        .IsDescending(false, true);  // UserId ASC, CreatedDate DESC
    
    modelBuilder.Entity<Product>()
        .HasIndex(p => p.Category)
        .HasFilter("[IsActive] = 1");  // Filtered index
}

// ❌ BAD: Full table scan
SELECT * FROM Users WHERE Email = 'user@example.com';  // ~100ms for 1M rows

// ✅ GOOD: Index lookup
SELECT * FROM Users WHERE Email = 'user@example.com';  // ~1ms with index (100x faster)
```

**Index Planning**:

```
Priority 1 (Critical):
├── Primary keys (automatic)
├── Foreign keys (for joins)
└── High-cardinality filter columns (Email, ID)

Priority 2 (Important):
├── Frequently sorted columns
├── Range query columns
└── Multi-column indexes for common queries

Priority 3 (Optional):
├── Low-cardinality columns (IsActive, Status)
├── Covering indexes (for specific queries)
└── Partial indexes
```

**Maintenance**:

```sql
-- Monitor index fragmentation
SELECT 
    OBJECT_NAME(ps.object_id) AS TableName,
    i.name AS IndexName,
    ps.avg_fragmentation_in_percent AS Fragmentation
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ps
JOIN sys.indexes i ON ps.object_id = i.object_id AND ps.index_id = i.index_id
WHERE ps.avg_fragmentation_in_percent > 10
ORDER BY ps.avg_fragmentation_in_percent DESC;

-- Rebuild fragmented indexes (> 30% fragmentation)
ALTER INDEX [IndexName] ON [TableName] REBUILD;

-- Reorganize moderately fragmented indexes (10-30%)
ALTER INDEX [IndexName] ON [TableName] REORGANIZE;
```

---

### Principle 3: Avoid N+1 Query Problems

**Problem**: Loading parent then querying child for each parent.

```csharp
// ❌ BAD: N+1 queries (1 parent + N child queries = N+1 total)
var users = dbContext.Users.ToList();  // Query 1
foreach (var user in users)
{
    var orders = dbContext.Orders.Where(o => o.UserId == user.Id).ToList();
    // Queries 2..N - one for each user!
}

// ✅ GOOD: Single query with Include
var users = dbContext.Users
    .Include(u => u.Orders)  // Single join query
    .ToList();

// ✅ GOOD: Query projection if you only need some data
var userOrders = dbContext.Users
    .Select(u => new
    {
        User = u,
        OrderCount = u.Orders.Count,
        TotalSpent = u.Orders.Sum(o => o.Total)
    })
    .ToList();
```

**Detection Strategy**:

```csharp
// Enable query logging to detect N+1
var options = new DbContextOptionsBuilder<MyContext>()
    .UseSqlServer(connectionString)
    .LogTo(Console.WriteLine, LogLevel.Information)
    .Build();

// Look for repeated queries with different parameters
// Query Log:
// SELECT * FROM Orders WHERE UserId = 1
// SELECT * FROM Orders WHERE UserId = 2
// SELECT * FROM Orders WHERE UserId = 3
// ^ This is N+1 problem
```

---

### Principle 4: Use Query Splitting for Large Datasets

**Problem**: Large joins create huge result sets.

```csharp
// ❌ BAD: Cartesian product creates bloated result set
var data = dbContext.Users
    .Include(u => u.Orders)
    .Include(u => u.Addresses)
    .ToList();
// User with 10 orders × 5 addresses = 50 rows per user

// ✅ GOOD: Split into separate queries
var data = dbContext.Users
    .Include(u => u.Orders)
    .AsSplitQuery()  // Separate query for each Include
    .Include(u => u.Addresses)
    .ToList();
// User + 10 order rows + 5 address rows = 16 rows total
```

**Performance Comparison**:

```
With 1,000 users, 10 orders each, 5 addresses each:

Join Query: 1,000 × 10 × 5 = 50,000 rows × 200B = ~10MB
Split Query: 1,000 + 10,000 + 5,000 rows = ~3.2MB (68% reduction)

Execution time: 200ms → 45ms (77% faster)
Memory: 150MB → 45MB (70% reduction)
```

---

### Principle 5: Use Compiled Queries for Repeated Queries

**Problem**: Query compilation happens every first execution.

```csharp
// ❌ BAD: Query compiled each time
for (int i = 0; i < 1000; i++)
{
    var user = dbContext.Users.First(u => u.Id == i);
}
// Compilation × 1000 = ~28ms overhead

// ✅ GOOD: Compiled query reused
private static readonly Func<MyContext, int, User> GetUserById =
    EF.CompileQuery((MyContext db, int id) =>
        db.Users.First(u => u.Id == id));

for (int i = 0; i < 1000; i++)
{
    var user = GetUserById(dbContext, i);
}
// Compilation × 1 = no overhead
```

**Compilation Overhead**:

```
First query: 5ms (parsing, translating to SQL)
Subsequent queries: 0.05ms (cached execution plan)

For 1000 queries:
Without compilation: 1000 × 5ms = 5,000ms
With compilation: 5ms + (999 × 0.05ms) = 54.95ms

Speedup: 91x faster with compiled queries
```

---

## Caching Strategies

### Strategy 1: Cache-Aside Pattern (Most Common)

**Implementation**:

```csharp
public class UserRepository : IUserRepository
{
    private readonly IL1CacheService _cache;
    private readonly MyDbContext _dbContext;
    
    public async Task<User> GetUserAsync(int userId)
    {
        // Try cache first
        var cacheKey = $"user-{userId}";
        
        return await _cache.GetAsync(
            cacheKey,
            async () => await _dbContext.Users.FirstOrDefaultAsync(u => u.Id == userId),
            TimeSpan.FromHours(1)  // 1 hour TTL
        );
    }
    
    public async Task UpdateUserAsync(User user)
    {
        // Update database
        _dbContext.Users.Update(user);
        await _dbContext.SaveChangesAsync();
        
        // Invalidate cache
        var cacheKey = $"user-{user.Id}";
        _cache.Invalidate(cacheKey);
    }
}
```

**Performance Impact**:

- Cache hit: 0.8ms (L1) vs 12ms (database) = 15x faster
- Throughput improvement: +25-40%
- Database load reduction: 60-80%

---

### Strategy 2: Write-Through Cache

**Use Case**: Consistency is critical (transactions, financial data)

```csharp
public class TransactionService
{
    public async Task<bool> RecordTransactionAsync(Transaction txn)
    {
        // 1. Write to cache first
        await _cache.SetAsync($"txn-{txn.Id}", txn, TimeSpan.FromMinutes(5));
        
        // 2. Write to database
        _dbContext.Transactions.Add(txn);
        var saved = await _dbContext.SaveChangesAsync() > 0;
        
        // 3. Rollback cache if database fails
        if (!saved)
        {
            _cache.Invalidate($"txn-{txn.Id}");
            return false;
        }
        
        return true;
    }
}
```

**Guarantees**:

- Strong consistency (cache = database)
- Slightly higher write latency (write to both)
- Safety for critical operations

---

### Strategy 3: Multi-Tier Cache Hierarchy

**Architecture**:

```
L1 Cache (Process Memory)
├── Speed: 0.8ms average
├── Size: 34MB
├── Hit Rate Target: 85%
└── TTL: 5-60 minutes

          ↓ (miss)

L2 Cache (Distributed)
├── Speed: 2.1ms average
├── Size: 45MB
├── Hit Rate Target: 75%
└── TTL: 1-24 hours

          ↓ (miss)

Database
├── Speed: 12ms average
├── Size: 100GB+
├── Latency: Network + Query
└── Source of truth
```

**Implementation**:

```csharp
public async Task<Product> GetProductAsync(int productId)
{
    var cacheKey = $"product-{productId}";
    
    // Try L1 cache first
    if (_l1Cache.TryGet(cacheKey, out var product))
        return product;  // 0.8ms hit
    
    // Try L2 cache
    product = await _l2Cache.GetAsync(cacheKey);
    if (product != null)
    {
        // Populate L1 for future hits
        _l1Cache.Set(cacheKey, product, TimeSpan.FromHours(1));
        return product;  // 2.1ms hit
    }
    
    // Fetch from database
    product = await _dbContext.Products.FirstOrDefaultAsync(p => p.Id == productId);
    
    // Populate both caches
    if (product != null)
    {
        await _l2Cache.SetAsync(cacheKey, product, TimeSpan.FromHours(24));
        _l1Cache.Set(cacheKey, product, TimeSpan.FromHours(1));
    }
    
    return product;  // 12ms miss
}
```

**Expected Hit Rates**:

```
100 requests:
├── L1 hits: 85 requests @ 0.8ms = 68ms
├── L2 hits: 10 requests @ 2.1ms = 21ms
└── DB hits: 5 requests @ 12ms = 60ms

Total time: 149ms (vs 1200ms without cache)
Speedup: 8x faster with tiered cache
```

---

### Strategy 4: Cache Warming & Prefetching

**Startup Warming**:

```csharp
public class CacheWarmupService
{
    public async Task WarmupCacheAsync()
    {
        // Preload frequently accessed data on startup
        var hotData = await _dbContext.Users
            .AsNoTracking()
            .Where(u => u.IsActive)
            .OrderByDescending(u => u.LastLogin)
            .Take(100)
            .ToListAsync();
        
        // Populate cache
        foreach (var user in hotData)
        {
            await _cache.SetAsync(
                $"user-{user.Id}",
                user,
                TimeSpan.FromHours(1)
            );
        }
        
        _logger.LogInformation($"Warmed cache with {hotData.Count} hot users");
    }
}

// Call during startup
services.AddScoped<ICacheWarmupService, CacheWarmupService>();
```

**Result**: First 100 user requests hit cache instead of database

---

### Strategy 5: Cache Invalidation Patterns

**Pattern 1: Time-Based Expiration (Simplest)**

```csharp
// Set 1-hour TTL, automatically expires
_cache.Set($"user-{id}", user, TimeSpan.FromHours(1));
```

**Pattern 2: Event-Based Invalidation**

```csharp
public async Task UpdateUserAsync(User user)
{
    _dbContext.Users.Update(user);
    await _dbContext.SaveChangesAsync();
    
    // Explicit invalidation
    _cache.Invalidate($"user-{user.Id}");
    
    // Publish event for other services
    await _mediator.Publish(new UserUpdatedEvent(user.Id));
}
```

**Pattern 3: Pattern-Based Invalidation**

```csharp
public async Task DeleteUserAsync(int userId)
{
    _dbContext.Users.Remove(user);
    await _dbContext.SaveChangesAsync();
    
    // Invalidate all user-related caches
    _cache.InvalidatePattern($"user-{userId}-*");  // user-{id}-profile, user-{id}-orders, etc.
    _cache.InvalidatePattern("user-list-*");       // All user list caches
}
```

**Pattern 4: Distributed Invalidation**

```csharp
public async Task UpdateCategoryAsync(Category category)
{
    _dbContext.Categories.Update(category);
    await _dbContext.SaveChangesAsync();
    
    // Invalidate locally
    _cache.Invalidate($"category-{category.Id}");
    
    // Publish to message bus for other instances
    await _messageBus.PublishAsync(new CacheInvalidationMessage
    {
        Pattern = $"category-{category.Id}-*",
        Timestamp = DateTime.UtcNow
    });
}
```

---

## Memory Management

### Principle 1: Object Pooling for High-Allocation Code Paths

**Problem**: Creating many objects creates GC pressure.

```csharp
// ❌ BAD: Allocations every call
public string FormatData(byte[] data)
{
    var sb = new StringBuilder();  // Allocation
    for (int i = 0; i < data.Length; i++)
    {
        sb.Append(data[i].ToString("X2"));  // String allocations
    }
    return sb.ToString();  // Final string allocation
}

// With 100K calls:
// Allocations: 100K StringBuilder + 200K strings = 300K objects
// GC pressure: High
// Time: 450ms

// ✅ GOOD: Object pooling
private static readonly ArrayPool<char> _charPool = ArrayPool<char>.Shared;
private static readonly StringBuilderPool _sbPool = new StringBuilderPool();

public string FormatData(byte[] data)
{
    var sb = _sbPool.Get();
    try
    {
        for (int i = 0; i < data.Length; i++)
        {
            sb.Append(data[i].ToString("X2"));
        }
        return sb.ToString();
    }
    finally
    {
        _sbPool.Return(sb);
    }
}

// With 100K calls:
// Allocations: 100 StringBuilder reuses = 100 objects
// GC pressure: Minimal
// Time: 120ms (3.75x faster)
```

---

### Principle 2: String Interning for String-Heavy Code

**Problem**: Duplicate strings consume memory.

```csharp
// ❌ BAD: Duplicate strings
var user1 = new User { Status = "active" };     // Allocation for "active"
var user2 = new User { Status = "active" };     // Another allocation for "active"
// Memory: 2 string objects with same value

// ✅ GOOD: String interning
var activeStatus = string.Intern("active");
var user1 = new User { Status = activeStatus };
var user2 = new User { Status = activeStatus };
// Memory: 1 string object, both references point to same object

// Or use constants
public class UserStatus
{
    public const string Active = "active";
    public const string Inactive = "inactive";
}

var user1 = new User { Status = UserStatus.Active };
```

**Memory Impact**:

```
Without interning: 1,000,000 users, 3 status values (active, inactive, pending)
├── 999,999 duplicate strings
├── Memory waste: ~7MB (3 bytes per char × 4 refs × 999,999)
└── Solution: Interning saves 99.9% of duplicate memory

With interning: Only 3 string objects for all 1,000,000 users
```

---

### Principle 3: Use ValueTask to Reduce Allocations

**Problem**: Task allocations in hot paths.

```csharp
// ❌ BAD: Allocates Task object even for synchronous result
public async Task<User> GetUserAsync(int id)
{
    // If user is in cache, still allocates Task
    if (_cache.TryGet(id, out var user))
        return user;  // Still returns Task, allocates Task object
    
    // Database call
    return await _dbContext.Users.FirstAsync(u => u.Id == id);
}

// ✅ GOOD: ValueTask avoids allocation for synchronous path
public async ValueTask<User> GetUserAsync(int id)
{
    // If user is in cache, no Task allocation
    if (_cache.TryGet(id, out var user))
        return user;  // Returns ValueTask without allocation
    
    // Database call still async
    return await _dbContext.Users.FirstAsync(u => u.Id == id);
}

// With 1M cache hits:
// Task allocations: 0 (vs 1M with Task)
// Memory savings: ~8MB per million calls
```

**Guidelines for ValueTask**:

- ✅ Use ValueTask for methods likely to return synchronously (cache hits)
- ✅ Use ValueTask for high-frequency calls (hot paths)
- ❌ Don't use ValueTask for exception cases (exceptions allocate)
- ❌ Don't use ValueTask if caller is already async

---

### Principle 4: LINQ Query Optimization

**Problem**: LINQ allocations in loops.

```csharp
// ❌ BAD: Allocations in loop
var results = new List<OrderSummary>();
foreach (var order in orders)
{
    results.Add(new OrderSummary  // Allocation
    {
        Id = order.Id,
        Total = order.Items.Sum(i => i.Price)  // LINQ allocation
    });
}

// ✅ GOOD: Use collection initializers
var results = orders
    .Select(o => new OrderSummary
    {
        Id = o.Id,
        Total = o.Items.Sum(i => i.Price)
    })
    .ToList();

// Even better: Avoid Sum, aggregate in query
var results = dbContext.Orders
    .AsNoTracking()
    .Select(o => new OrderSummary
    {
        Id = o.Id,
        Total = o.Items.Sum(i => i.Price)  // Executed in SQL, not LINQ
    })
    .ToList();
```

---

## Database Best Practices

### Practice 1: Connection Pool Sizing

**Optimal Pool Sizing**:

```csharp
services.AddDbContext<MyContext>(options =>
    options.UseSqlServer(connectionString, sqlOptions =>
    {
        sqlOptions.CommandTimeout(30);
        sqlOptions.MaxPoolSize(40);  // Default is 100, reduce to needed size
        sqlOptions.MinPoolSize(5);   // Pre-allocate minimum connections
    })
);

// Sizing guidelines:
// Small app (< 100 concurrent users): MinPool=2, MaxPool=20
// Medium app (100-1K concurrent): MinPool=5, MaxPool=40
// Large app (1K+ concurrent): MinPool=10, MaxPool=100
```

---

### Practice 2: Batch Operations

**Problem**: Multiple roundtrips to database.

```csharp
// ❌ BAD: Multiple roundtrips
foreach (var item in items)
{
    dbContext.Items.Add(item);
    await dbContext.SaveChangesAsync();  // 1 roundtrip per item
}
// 1000 items = 1000 roundtrips

// ✅ GOOD: Batch insert
dbContext.Items.AddRange(items);
await dbContext.SaveChangesAsync();  // 1 roundtrip for all
```

**Bulk Operation Library**:

```csharp
// Using BulkOperations NuGet package
await dbContext.BulkInsertAsync(items);      // 100x faster than SaveChanges
await dbContext.BulkUpdateAsync(items);
await dbContext.BulkDeleteAsync(items);

// Performance: 1000 items
// SaveChanges loop: 5000ms
// BulkInsert: 50ms (100x faster)
```

---

### Practice 3: Query Result Paging

**Problem**: Loading entire result set.

```csharp
// ❌ BAD: Loads all users into memory
var users = dbContext.Users.ToList();
var page = users.Skip(100).Take(20).ToList();  // Paging in memory

// ✅ GOOD: Paging in SQL
var page = dbContext.Users
    .Skip((pageNumber - 1) * pageSize)
    .Take(pageSize)
    .ToList();  // SQL handles paging efficiently
```

---

## API Performance

### Optimization 1: Async/Await Throughout

```csharp
// ✅ GOOD: All async
[HttpGet("users/{id}")]
public async Task<ActionResult<UserDto>> GetUserAsync(int id)
{
    var user = await _userService.GetUserAsync(id);  // Async
    var dto = _mapper.Map<UserDto>(user);
    return Ok(dto);
}
```

---

### Optimization 2: Response Compression

```csharp
// Enable gzip compression
services.AddResponseCompression(options =>
{
    options.Providers.Add<GzipCompressionProvider>();
    options.EnableForHttps = true;
});

app.UseResponseCompression();

// Response size: 50KB → 8KB (84% reduction)
```

---

### Optimization 3: ETag Caching

```csharp
[HttpGet("users/{id}")]
public async Task<IActionResult> GetUserAsync(int id)
{
    var user = await _userService.GetUserAsync(id);
    var etag = GenerateETag(user);
    
    if (Request.Headers["If-None-Match"] == etag)
        return NotModified();  // 304 response, no body
    
    Response.Headers["ETag"] = etag;
    return Ok(user);
}
```

---

## Common Pitfalls

### Pitfall 1: Sync-over-Async

```csharp
// ❌ BAD: Deadlock potential
public User GetUser(int id)
{
    return _userService.GetUserAsync(id).Result;  // Blocks thread
}

// ✅ GOOD: Actually async
public async Task<User> GetUserAsync(int id)
{
    return await _userService.GetUserAsync(id);
}
```

---

### Pitfall 2: Lazy<T> in Multithreaded Code

```csharp
// ❌ BAD: Potential race condition
public static Lazy<DataService> _service = new Lazy<DataService>(
    () => new DataService(),
    LazyThreadSafetyMode.None  // NOT thread safe!
);

// ✅ GOOD: Thread-safe
public static Lazy<DataService> _service = new Lazy<DataService>(
    () => new DataService(),
    LazyThreadSafetyMode.ExecutionAndPublication
);
```

---

### Pitfall 3: Not Disposing Resources

```csharp
// ❌ BAD: Resource leak
var stream = File.OpenRead("large-file.bin");
var data = new byte[1000000];
stream.Read(data, 0, 1000000);
// Stream never closed, handle leak

// ✅ GOOD: Using statement
using (var stream = File.OpenRead("large-file.bin"))
{
    var data = new byte[1000000];
    stream.Read(data, 0, 1000000);
}  // Stream automatically closed

// Or using declaration (C# 8+)
using var stream = File.OpenRead("large-file.bin");
var data = new byte[1000000];
stream.Read(data, 0, 1000000);
```

---

### Pitfall 4: Premature Optimization

**Start with**:

1. Write correct code first
2. Measure (profile)
3. Identify bottlenecks
4. Optimize only the bottlenecks

**Don't optimize**: Code paths that are not slow

---

## 📊 Performance Checklist

- [ ] All read queries use AsNoTracking()
- [ ] All relevant columns have indexes
- [ ] No N+1 query patterns
- [ ] Compiled queries used for repeated queries
- [ ] Two-tier caching implemented (L1/L2)
- [ ] Connection pool sized appropriately
- [ ] Object pooling in hot paths
- [ ] ValueTask for cache-hit-likely methods
- [ ] Async/await throughout
- [ ] Response compression enabled
- [ ] Batch operations used where applicable
- [ ] No sync-over-async blocking
- [ ] Resources properly disposed
- [ ] Code profiled and verified

---

**Document Version**: 1.0  
**Last Updated**: Phase 4 Session  
**Status**: Complete - Best Practices Documented
