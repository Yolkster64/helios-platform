# Phase 4 Tier 3: Operations & Monitoring Guide

**Status**: Complete  
**Date**: 2024  
**Target**: Performance monitoring, tuning guidelines, troubleshooting procedures  

---

## 📊 Performance Monitoring Procedures

### Real-Time Monitoring Dashboard

**Key Metrics to Monitor**:

```
┌──────────────────────────────────────────┐
│   HELIOS Platform - Performance Monitor   │
├──────────────────────────────────────────┤
│                                          │
│ Request Metrics                          │
│ ├─ Requests/sec: 2,450 ↑                │
│ ├─ Avg Response: 8.2ms ↓                │
│ ├─ P95 Response: 22ms                   │
│ ├─ P99 Response: 35ms                   │
│ └─ Error Rate: 0.02%                    │
│                                          │
│ Cache Metrics                            │
│ ├─ L1 Hit Rate: 84.2% ↑                │
│ ├─ L2 Hit Rate: 72.5%                  │
│ ├─ L1 Size: 32MB / 34MB                │
│ └─ L2 Size: 43MB / 45MB                │
│                                          │
│ Database Metrics                         │
│ ├─ Connections: 15 / 40                 │
│ ├─ Queries/sec: 890                     │
│ ├─ Avg Query: 12.5ms                    │
│ └─ Slow Queries: 0                      │
│                                          │
│ System Metrics                           │
│ ├─ CPU: 42%                             │
│ ├─ Memory: 185MB / 256MB                │
│ ├─ Disk I/O: 12MB/sec                   │
│ └─ Network: 45Mbps                      │
│                                          │
└──────────────────────────────────────────┘
```

---

### Monitoring Setup

**Application Insights Integration**:

```csharp
services.AddApplicationInsightsTelemetry(configuration);
services.AddApplicationInsightsHttpTelemetry();

// Custom telemetry
var telemetryClient = new TelemetryClient();

// Track custom events
telemetryClient.TrackEvent("CacheHit", properties, metrics);
telemetryClient.TrackException(exception);
telemetryClient.TrackTrace("Slow query detected", SeverityLevel.Warning);
```

**Prometheus Metrics**:

```csharp
services.AddSingleton<IMetricsCollector, PrometheusMetricsCollector>();

// In service code
_metricsCollector.IncrementCounter("cache_hits");
_metricsCollector.RecordHistogram("query_duration", elapsedMs);
_metricsCollector.SetGauge("memory_usage", memoryMB);
```

---

### Log Analysis

**Query Log Analysis**:

```csharp
// Enable query logging in development
var optionsBuilder = new DbContextOptionsBuilder<MyContext>()
    .UseSqlServer(connectionString)
    .LogTo(Console.WriteLine, LogLevel.Information);

// Capture slow queries in production
public class SlowQueryInterceptor : DbCommandInterceptor
{
    public override InterceptionResult<DbDataReader> ReaderExecuting(
        DbCommand command,
        CommandEventData eventData,
        InterceptionResult<DbDataReader> result)
    {
        // Log if query takes > 100ms
        eventData.StopWatch.Start();
        return result;
    }
    
    public override InterceptionResult<DbDataReader> ReaderExecuted(
        DbCommand command,
        CommandEventData eventData,
        InterceptionResult<DbDataReader> result)
    {
        if (eventData.StopWatch.ElapsedMilliseconds > 100)
        {
            _logger.LogWarning(
                $"Slow query ({eventData.StopWatch.ElapsedMilliseconds}ms): {command.CommandText}"
            );
        }
        return result;
    }
}
```

---

## 🎛️ Performance Tuning Guidelines

### Tuning Process

```
1. Establish Baseline
   ├─ Measure current performance
   ├─ Identify metrics
   └─ Set targets

2. Profile & Identify Bottleneck
   ├─ Run profiler
   ├─ Collect traces
   ├─ Analyze flame graphs
   └─ Find top 3 issues

3. Prioritize Optimizations
   ├─ Effort estimation
   ├─ Impact assessment
   ├─ ROI calculation
   └─ Select high-ROI fixes

4. Implement Optimization
   ├─ Code change
   ├─ Test thoroughly
   ├─ Monitor impact
   └─ Document changes

5. Measure Results
   ├─ Compare to baseline
   ├─ Verify improvement
   ├─ Check for regressions
   └─ Update documentation
```

---

### Tuning Scenarios

#### Scenario 1: High CPU Usage

**Symptoms**:

```
- CPU constantly > 80%
- Response times slow
- Throughput plateaued
```

**Diagnosis Steps**:

```csharp
// 1. Use profiler to identify hot code path
dotnet-trace record --output trace.nettrace -- application.exe

// 2. Analyze trace
dotnet-trace convert --format speedscope trace.nettrace

// 3. Look for:
// - Tight loops
// - Inefficient algorithms
// - LINQ allocations
// - Unnecessary conversions
```

**Possible Solutions**:

- Replace LINQ with for loops (hot path)
- Use object pooling for allocations
- Cache computation results
- Parallel processing for CPU-bound work

---

#### Scenario 2: High Memory Usage

**Symptoms**:

```
- Memory grows over time
- GC pauses increasing
- "Memory pressure" warnings
```

**Diagnosis Steps**:

```csharp
// 1. Check for memory leaks
var gcMemory = GC.GetTotalMemory(true);
var processMemory = Process.GetCurrentProcess().WorkingSet64;
// If growing over time → potential leak

// 2. Profile memory allocations
dotnet-trace record --provider GCHeapSnapshot -- application.exe

// 3. Analyze heap dump
// Look for:
// - Retained objects
// - Circular references
// - Event handler leaks
// - Resource leaks
```

**Possible Solutions**:

- Implement object pooling
- Use object disposal patterns
- Reduce cache sizes
- Implement streaming for large data

---

#### Scenario 3: Slow Database Queries

**Symptoms**:

```
- Query times > 100ms
- CPU at database server high
- Lock escalation occurring
```

**Diagnosis Steps**:

```sql
-- 1. Find slow queries
SELECT 
    TOP 10 
    stat.execution_count,
    stat.total_elapsed_time / stat.execution_count AS avg_time,
    SUBSTRING(text, 1, 100) AS query
FROM sys.dm_exec_query_stats stat
CROSS APPLY sys.dm_exec_sql_text(sql_handle) text
ORDER BY stat.total_elapsed_time DESC;

-- 2. Get execution plan
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
-- [Run slow query]
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

-- 3. Check for missing indexes
SELECT * FROM sys.dm_db_missing_index_details;
```

**Possible Solutions**:

- Create missing indexes
- Remove N+1 queries
- Use query splitting
- Implement caching
- Add connection pooling

---

#### Scenario 4: High Cache Churn (Low Hit Rate)

**Symptoms**:

```
- L1 Cache hit rate < 70%
- Database queries not decreasing
- Cache size near limit
```

**Diagnosis Steps**:

```csharp
// 1. Analyze cache statistics
var stats = _cache.GetStatistics();
Console.WriteLine($"Hit Rate: {stats.HitRate}%");
Console.WriteLine($"Eviction Rate: {stats.EvictionRate}%");
Console.WriteLine($"Average TTL: {stats.AverageTTL}");

// 2. Check cache key patterns
foreach (var key in _cache.GetAllKeys())
{
    Console.WriteLine(key);  // Look for similar patterns
}

// 3. Profile cache access patterns
// Log every cache operation for analysis
```

**Possible Solutions**:

- Increase TTL for stable data
- Implement cache warming
- Use different cache key strategy
- Pre-cache frequently accessed items
- Implement predictive prefetching

---

## 🔧 Common Tuning Adjustments

### Configuration Tuning

**Connection Pool**:

```csharp
// Current: MinPool=5, MaxPool=40
// For high concurrency (1000+ users):
services.AddDbContext<MyContext>(options =>
    options.UseSqlServer(connectionString, sqlOptions =>
    {
        sqlOptions.MinPoolSize(10);   // Pre-allocate more connections
        sqlOptions.MaxPoolSize(100);  // Allow more concurrent queries
        sqlOptions.CommandTimeout(30);
    })
);
```

**Thread Pool**:

```csharp
// Ensure sufficient threads for async workloads
ThreadPool.GetMinThreads(out var workerThreads, out var ioThreads);
ThreadPool.SetMinThreads(Math.Max(workerThreads, Environment.ProcessorCount * 2), ioThreads);
```

**Cache Sizes**:

```csharp
// L1 Cache (in-memory)
// Current: 34MB
// For 10x throughput: increase to 100MB
// Trade-off: Memory vs Hit Rate

// L2 Cache (distributed)
// Current: 45MB
// Scale with user base: 50MB per 10K concurrent users
```

**TTL Strategy**:

```csharp
// Current: 1 hour for user data
// Adjust based on data freshness requirements:
// - User profile: 1 hour (changes infrequently)
// - Product inventory: 5 minutes (changes frequently)
// - Session data: 30 minutes (expires at timeout)
// - Config: 24 hours (cached separately)
```

---

## 🚨 Troubleshooting Guide

### Issue 1: Intermittent Slowness

**Symptoms**:

```
- Most requests fast (10ms)
- Occasional slow requests (500ms+)
- Pattern: periodic spikes
```

**Troubleshooting Steps**:

1. **Check for GC Pauses**:

```csharp
var initialGen0 = GC.CollectionCount(0);
// [do work]
var finalGen0 = GC.CollectionCount(0);
if (finalGen0 > initialGen0)
    Console.WriteLine("Gen0 collection during operation");
```

2. **Check for Lock Contention**:

```csharp
// Monitor lock wait times
var diagnostics = System.Diagnostics.LockMetrics.GetLockDetails();
foreach (var lockWait in diagnostics.Where(d => d.WaitTime > 10))
{
    Console.WriteLine($"Long lock wait: {lockWait.WaitTime}ms at {lockWait.Location}");
}
```

3. **Check for Database Connection Issues**:

```sql
-- Check for blocking queries
SELECT * FROM sys.dm_exec_requests WHERE wait_type IS NOT NULL;

-- Check connection count
SELECT COUNT(*) FROM sys.dm_exec_sessions;
```

---

### Issue 2: Out of Memory Exception

**Symptoms**:

```
- OutOfMemoryException thrown
- Service crashes
- Not caught by try-catch
```

**Troubleshooting Steps**:

1. **Identify Allocation Site**:

```csharp
// Enable memory diagnostics
using var heapSnapshot = new HeapSnapshot();
// [do work that crashes]
heapSnapshot.Analyze();
```

2. **Check for Large Collections**:

```csharp
// Look for suspicious large allocations
var largeObjects = _cache.GetAllKeys()
    .Select(k => (k, size: _cache.GetSize(k)))
    .OrderByDescending(x => x.size)
    .Take(10);

foreach (var (key, size) in largeObjects)
{
    Console.WriteLine($"{key}: {size}MB");
}
```

3. **Implement Limits**:

```csharp
if (GC.GetTotalMemory(false) > _memoryLimit)
{
    _logger.LogWarning("Approaching memory limit, clearing caches");
    _cache.Clear();
}
```

---

### Issue 3: Database Deadlock

**Symptoms**:

```
- Sporadic deadlock errors
- "Deadlock detected" exception
- Transaction timeout
```

**Troubleshooting Steps**:

1. **Enable Deadlock Tracing**:

```sql
-- Enable trace flag for deadlock detection
DBCC TRACEON(1222);

-- Check deadlock graph
SELECT * FROM sys.dm_exec_requests WHERE wait_type = 'DW_LATCH_EX';
```

2. **Identify Lock Order Issue**:

```csharp
// Ensure consistent lock order in code
// BAD:
// Transaction 1: Lock(A) → Lock(B)
// Transaction 2: Lock(B) → Lock(A)  [DEADLOCK!]

// GOOD: Always lock in same order
// Transaction 1: Lock(A) → Lock(B)
// Transaction 2: Lock(A) → Lock(B)
```

3. **Implement Retry Logic**:

```csharp
public async Task<T> ExecuteWithRetryAsync<T>(Func<Task<T>> operation)
{
    for (int i = 0; i < 3; i++)
    {
        try
        {
            return await operation();
        }
        catch (SqlException ex) when (ex.Number == -2 && i < 2)  // -2 = Timeout
        {
            await Task.Delay(100 * (i + 1));  // Exponential backoff
        }
    }
    throw;
}
```

---

## 📈 Performance Tuning Roadmap

### Phase 1: Quick Wins (1-2 hours, 15% improvement)

- [ ] Enable query result caching
- [ ] Increase connection pool size
- [ ] Add missing database indexes
- [ ] Enable compression

**Expected**: Startup 2,847ms → 2,400ms, Throughput 8,945 → 10,200 req/sec

---

### Phase 2: Medium Optimizations (4-6 hours, 20% improvement)

- [ ] Implement query batching
- [ ] Add cache warming
- [ ] Optimize hot paths
- [ ] Implement lazy loading

**Expected**: Startup → 1,900ms, Throughput → 11,500 req/sec

---

### Phase 3: Deep Optimization (8-10 hours, 15% improvement)

- [ ] Implement object pooling
- [ ] Optimize memory allocations
- [ ] Profile and micro-optimize
- [ ] Implement async throughout

**Expected**: Startup → 1,600ms, Throughput → 13,000+ req/sec

---

## ✅ Performance Tuning Checklist

- [ ] Baseline metrics established and documented
- [ ] Profiler integrated and tested
- [ ] Real-time monitoring dashboard deployed
- [ ] Slow query logging enabled
- [ ] Alert thresholds configured
- [ ] Connection pool sized appropriately
- [ ] Cache TTL tuned for data type
- [ ] Cache warming implemented
- [ ] Query optimization patterns verified
- [ ] No N+1 queries detected
- [ ] Memory leaks checked and eliminated
- [ ] GC pause times within target
- [ ] Load test completed successfully
- [ ] Performance regression tests in place
- [ ] Documentation updated

---

## 📞 Support & Escalation

**Performance Issue Escalation**:

1. **Level 1**: Cache clear & service restart
2. **Level 2**: Database index rebuild & query optimization
3. **Level 3**: Connection pool adjustment & TTL tuning
4. **Level 4**: Infrastructure scaling (more resources)
5. **Level 5**: Architecture changes (redesign)

---

**Document Version**: 1.0  
**Last Updated**: Phase 4 Session  
**Status**: Operations Guide Complete
