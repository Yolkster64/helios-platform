# PHASE 6 QUICK REFERENCE GUIDE

## Using Optimization Services in Phase 1-2 Services

---

## 📚 Overview

Phase 6 introduces four new optimization services to improve performance across all Phase 1-2 services:

1. **L2CacheService** - Advanced caching with TTL and invalidation
2. **ObjectPoolService** - Memory-efficient object reuse
3. **AsyncBatchProcessingService** - Batch I/O operations
4. **PerformanceBenchmarkService** - Performance metrics and benchmarking

---

## 🔧 Usage Examples

### 1. Using L2CacheService

```csharp
using HELIOS.Platform.Core.Performance;

// Initialize cache
var cache = new L2CacheService(
    defaultTtl: TimeSpan.FromHours(1),
    maxMemoryMB: 500
);

// Get or create with cache
var data = await cache.GetOrCreateAsync(
    key: "user:preferences:123",
    factory: async () => await FetchUserPreferences(123),
    ttl: TimeSpan.FromHours(1)
);

// Direct get
var cached = await cache.GetAsync<UserPreferences>("user:preferences:123");

// Set with custom TTL
await cache.SetAsync("temp:key", value, ttl: TimeSpan.FromMinutes(5));

// Invalidate by pattern
await cache.InvalidatePatternAsync("user:*");  // Invalidates all user keys

// Get statistics
var stats = cache.GetStatistics();
Console.WriteLine($"Hit rate: {stats.HitRate:P}");
Console.WriteLine($"Items: {stats.CurrentItemCount}");
Console.WriteLine($"Memory: {stats.MemoryUsageBytes / 1024 / 1024}MB");
```

### 2. Using ObjectPoolService

```csharp
using HELIOS.Platform.Core.Performance;

// Initialize pool
var pool = new ObjectPoolService();

// Rent object from pool
using (var pooledObj = pool.Rent<CommandContext>())
{
    var context = pooledObj.Value;
    context.Command = "deploy";
    context.Parameters = parameters;
    
    // Use context...
    await ExecuteCommand(context);
    
} // Automatically returned to pool

// Get statistics
var stats = pool.GetStatistics();
Console.WriteLine($"Allocations avoided: {stats.TotalAllocationsAvoided}");
Console.WriteLine($"Active pools: {stats.TotalPoolsCreated}");

// Use ArrayPool for temporary buffers
var arrayPool = pool.GetArrayPool<byte>();
var buffer = arrayPool.Rent(4096);
try
{
    // Use buffer...
    ProcessData(buffer);
}
finally
{
    arrayPool.Return(buffer);
}
```

### 3. Using AsyncBatchProcessingService

```csharp
using HELIOS.Platform.Core.Performance;

var batchService = new AsyncBatchProcessingService();

// Batch process items with results
var operations = Enumerable.Range(0, 100)
    .Select(i => (Func<Task<string>>)(() => ProcessItemAsync(i)))
    .ToList();

var results = await batchService.BatchProcessAsync(
    operations,
    batchSize: 20  // Process 20 at a time
);

// Batch execute without results
var tasks = commands.Select(cmd => (Func<Task>)(() => ExecuteCommandAsync(cmd)));
await batchService.BatchExecuteAsync(tasks, batchSize: 10);

// Parallel map with controlled degree
var items = new[] { "a", "b", "c", "d", "e" };
var processed = await batchService.MapAsync(
    source: items,
    mapper: async (item) => await TransformItemAsync(item),
    degreeOfParallelism: 3
);
```

### 4. Using PerformanceBenchmarkService

```csharp
using HELIOS.Platform.Core.Performance;

var benchmark = new PerformanceBenchmarkService();

// Capture baseline
benchmark.StartBaseline();

// Benchmark a service operation
var metrics = await benchmark.BenchmarkServiceAsync(
    serviceName: "CLI",
    operation: async () => await cliService.ExecuteCommandAsync(command),
    iterations: 1000,
    warmupIterations: 100
);

Console.WriteLine($"Throughput: {metrics.ThroughputOpsPerSec:F0} ops/sec");
Console.WriteLine($"Avg Latency: {metrics.AvgLatencyMs}ms");
Console.WriteLine($"p95 Latency: {metrics.P95LatencyMs}ms");
Console.WriteLine($"Memory: {metrics.MemoryDeltaMB}MB");
Console.WriteLine($"GC Gen2: {metrics.GCGen2Collections} collections");

// Generate reports
var allBenchmarks = benchmark.GetAllBenchmarks();
var report = benchmark.GenerateReport(optimizationResults);
Console.WriteLine(report);

var json = benchmark.GenerateJson(optimizationResults);
File.WriteAllText("benchmarks.json", json);
```

---

## 🎯 Integration Patterns

### Pattern 1: Cache + Pool for High-Frequency Operations

```csharp
public class OptimizedUserService
{
    private readonly IL2CacheService _cache;
    private readonly IObjectPoolService _pool;

    public async Task<User> GetUserAsync(int userId)
    {
        // Try cache first
        var user = await _cache.GetAsync<User>($"user:{userId}");
        if (user != null) return user;

        // If not cached, get from database with pooled connection
        using (var conn = _pool.Rent<DatabaseConnection>())
        {
            user = await conn.Value.GetUserAsync(userId);
        }

        // Cache for future requests
        await _cache.SetAsync($"user:{userId}", user);
        return user;
    }
}
```

### Pattern 2: Batch Processing with Caching

```csharp
public class OptimizedBulkProcessor
{
    private readonly IAsyncBatchProcessingService _batchService;
    private readonly IL2CacheService _cache;

    public async Task<List<Result>> ProcessBulkAsync(List<Item> items)
    {
        // Check cache for items
        var uncached = new List<Item>();
        var results = new List<Result>();

        foreach (var item in items)
        {
            var cached = await _cache.GetAsync<Result>($"result:{item.Id}");
            if (cached != null)
                results.Add(cached);
            else
                uncached.Add(item);
        }

        // Process uncached items in batch
        if (uncached.Count > 0)
        {
            var ops = uncached.Select(item => 
                (Func<Task<Result>>)(async () => await ProcessItemAsync(item))
            );

            var newResults = await _batchService.BatchProcessAsync(
                ops,
                batchSize: 50
            );

            // Cache results
            foreach (var result in newResults)
            {
                await _cache.SetAsync($"result:{result.Id}", result);
            }

            results.AddRange(newResults);
        }

        return results;
    }
}
```

### Pattern 3: Invalidation on Updates

```csharp
public async Task UpdateConfigurationAsync(string key, object value)
{
    // Update database
    await _database.UpdateAsync(key, value);

    // Invalidate related cache entries
    await _cache.InvalidatePatternAsync($"config:{key}*");
    await _cache.InvalidatePatternAsync($"user:preferences:*");  // If config affects preferences
}
```

---

## 📊 Performance Tips

### 1. Cache TTL Configuration

- **Frequently changing data**: 5-15 minutes
- **User preferences**: 1 hour
- **Configuration**: 1 hour
- **Reference data**: 4-8 hours
- **Read-heavy data**: 24 hours

### 2. Object Pool Sizing

- **Command contexts**: 100 objects
- **Database connections**: 50 connections
- **Buffers**: ArrayPool (automatic sizing)
- **Custom objects**: Scale with concurrency

### 3. Batch Size Guidelines

- **CPU-bound**: (processor count) * 2
- **I/O-bound**: 20-50 items
- **Database operations**: 50-100 items
- **API calls**: 10-20 items

### 4. Memory Optimization

- Cache large objects: Strings >10KB, collections >1MB
- Pool objects: >1KB, frequently allocated
- Use ArrayPool: For temporary buffers >1KB
- Clear collections: When done to enable GC

---

## ⚙️ Configuration

### Production Recommended Settings

```csharp
// Cache configuration
var cache = new L2CacheService(
    defaultTtl: TimeSpan.FromHours(1),
    maxMemoryMB: 500  // Adjust based on server resources
);

// Object pool configuration
var pool = new ObjectPoolService();
// Pools auto-configure based on demand

// Batch service configuration
var batchService = new AsyncBatchProcessingService();
// Batch sizes: 20-50 items, adjust based on operation complexity
```

---

## 🔍 Monitoring

### Metrics to Monitor

```csharp
// Cache metrics
var cacheStats = cache.GetStatistics();
// Alert if: HitRate < 60% or MemoryUsage > 400MB

// Pool metrics
var poolStats = pool.GetStatistics();
// Track: TotalAllocationsAvoided (cost savings)

// Performance metrics
var perfStats = benchmark.GetAllBenchmarks();
// Monitor: Throughput trends, latency increases
```

### Logging Integration

```csharp
_logger.LogInformation(
    "Cache hit rate: {HitRate:P}, Memory: {Memory}MB, Items: {Count}",
    cacheStats.HitRate,
    cacheStats.MemoryUsageBytes / 1024 / 1024,
    cacheStats.CurrentItemCount
);
```

---

## ❓ Troubleshooting

### Issue: Low Cache Hit Rate (<60%)

**Solutions**:

1. Increase TTL for stable data
2. Reduce cache invalidation frequency
3. Add more cache keys (patterns)
4. Monitor data change patterns

### Issue: High Memory Usage (>120MB)

**Solutions**:

1. Reduce cache maxMemoryMB limit
2. Decrease TTL for volatile data
3. Enable object pooling
4. Use ArrayPool for large buffers

### Issue: GC Pause Time >15ms

**Solutions**:

1. Reduce allocation frequency
2. Enable object pooling
3. Clear collections when done
4. Use value types instead of boxing

### Issue: Low Throughput

**Solutions**:

1. Increase batch size (if I/O-bound)
2. Increase parallelism degree
3. Enable caching for hot paths
4. Use connection pooling

---

## 📖 Documentation References

- **Full Report**: PHASE6_OPTIMIZATION_REPORT.md
- **Strategy**: PHASE6_OPTIMIZATION_STRATEGY.md
- **Metrics**: PHASE6_OPTIMIZATION_METRICS.json
- **Tests**: Phase6OptimizationTests.cs

---

## 🚀 Getting Started

1. **Understand**: Read PHASE6_COMPLETION_SUMMARY.md (10 mins)
2. **Review**: Check PHASE6_OPTIMIZATION_METRICS.json (5 mins)
3. **Integrate**: Use patterns above in your service (varies)
4. **Test**: Run Phase6OptimizationTests.cs (2 mins)
5. **Monitor**: Enable performance counters (ongoing)

---

## 📞 Support

For questions:

1. Check this quick reference
2. Review PHASE6_OPTIMIZATION_REPORT.md for detailed info
3. Run test suite for examples
4. Check service-specific documentation

---

**Quick Reference v1.0**  
*Phase 6 Optimization Services*
