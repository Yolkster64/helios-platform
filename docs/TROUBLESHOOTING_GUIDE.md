# HELIOS v4.0 - Troubleshooting Guide

## Quick Diagnostics

### System Health Check

```bash
# Run diagnostic
npx helios-cli diagnose

# Output includes:
# - API connectivity
# - Database connection
# - Cache status
# - WebSocket availability
# - Message queue status
# - Service versions
```

---

## Common Issues & Solutions

### Issue 1: High API Latency (>1000ms)

**Symptoms:**

- API responses slow (p95 > 1000ms)
- Dashboard loading takes >5 seconds
- Timeout errors appear in logs

**Root Causes:**

1. Database query performance
2. Network issues
3. Cache misses
4. Upstream service latency

**Diagnostics:**

```bash
# Check database query performance
SELECT query, calls, total_time FROM pg_stat_statements
ORDER BY total_time DESC LIMIT 10;

# Check cache hit rate
redis-cli info stats | grep hit_rate

# Check network latency
ping api.helios.app
mtr -r -c 10 api.helios.app

# Check service latency
curl -w "@curl-format.txt" -o /dev/null -s https://api.helios.app/health
```

**Solutions:**

1. **Add database indexes**

   ```sql
   CREATE INDEX idx_documents_user_id ON documents(user_id);
   CREATE INDEX idx_sync_events_timestamp ON sync_events(timestamp DESC);
   ```

2. **Increase cache size**

   ```javascript
   // In config/cache.js
   maxMemory: '4gb',
   evictionPolicy: 'allkeys-lru'
   ```

3. **Enable query result caching**

   ```javascript
   const cacheResult = await cache.getOrSet(
     `query_${hash(query)}`,
     () => db.query(query),
     { ttl: 300 } // 5 minutes
   );
   ```

4. **Optimize slow queries**

   ```sql
   -- Replace:
   SELECT * FROM documents WHERE content LIKE '%search%';
   
   -- With:
   SELECT * FROM documents_fts WHERE content @@ to_tsquery('search');
   ```

5. **Scale horizontally**

   ```bash
   # Add more API instances
   kubectl scale deployment api-service --replicas=5
   ```

---

### Issue 2: Database Connection Timeouts

**Symptoms:**

- "FATAL: remaining connection slots reserved" error
- Connection pool exhausted
- Database unavailable errors

**Diagnostics:**

```bash
# Check active connections
psql -c "SELECT count(*) FROM pg_stat_activity;"

# Check max connections
psql -c "SHOW max_connections;"

# Check idle connections
psql -c "SELECT * FROM pg_stat_activity WHERE state = 'idle';"
```

**Solutions:**

1. **Increase connection pool size**

   ```javascript
   // config/database.js
   pool: {
     min: 10,
     max: 50, // Increase from 20
     idleTimeoutMillis: 30000,
     connectionTimeoutMillis: 2000,
   }
   ```

2. **Enable connection pooling (PgBouncer)**

   ```
   # pgbouncer.ini
   max_client_conn = 1000
   default_pool_size = 25
   min_pool_size = 10
   reserve_pool_size = 5
   reserve_pool_timeout = 3
   ```

3. **Close idle connections**

   ```javascript
   // Add connection cleanup
   setInterval(() => {
     pool.query(`
       SELECT pg_terminate_backend(pid) 
       FROM pg_stat_activity 
       WHERE state = 'idle' 
       AND query_start < now() - interval '30 minutes'
     `);
   }, 300000); // Every 5 minutes
   ```

4. **Monitor connection usage**

   ```sql
   -- Create alert
   SELECT count(*) as active_connections
   FROM pg_stat_activity
   WHERE state != 'idle';
   -- Alert if > max_connections * 0.8
   ```

---

### Issue 3: Sync Conflicts Not Resolving

**Symptoms:**

- Sync status shows conflicts pending
- Manual resolution required repeatedly
- Data inconsistency between devices

**Diagnostics:**

```javascript
// Check unresolved conflicts
const conflicts = await client.sync.getConflicts({
  resolved: false
});

// Check conflict resolution logs
const logs = await client.sync.getConflictLogs({
  timeRange: '24h'
});
```

**Solutions:**

1. **Configure auto-resolution strategy**

   ```javascript
   // config/sync.js
   conflictResolution: {
     strategy: 'lastWrite', // or 'customMerge', 'manual'
     autoResolve: true,
     retryOnConflict: 3
   }
   ```

2. **Implement custom merge logic**

   ```javascript
   syncEngine.onConflict(async (conflict) => {
     const merged = {
       ...conflict.local,
       ...conflict.remote,
       // Custom merge logic
       metadata: {
         ...conflict.local.metadata,
         ...conflict.remote.metadata
       }
     };
     return await syncEngine.resolveConflict(conflict.id, merged);
   });
   ```

3. **Increase conflict timeout**

   ```javascript
   conflictResolution: {
     timeout: 300000, // 5 minutes, was 60 seconds
     maxRetries: 5
   }
   ```

4. **Clear stuck conflicts (careful)**

   ```javascript
   // After investigation
   await syncEngine.clearConflict({
     conflictId: 'conflict_123',
     resolution: 'remote' // or 'local', 'merged'
   });
   ```

---

### Issue 4: Out of Memory Errors

**Symptoms:**

- "JavaScript heap out of memory" error
- Process crashes during heavy operations
- Memory usage steadily increases

**Diagnostics:**

```bash
# Check Node.js process memory
node --max_old_space_size=4096 server.js

# Profile memory usage
node --inspect server.js
# Then use Chrome DevTools to profile

# Check garbage collection
node --trace-gc server.js 2>&1 | grep "Scavenge"
```

**Solutions:**

1. **Increase heap size**

   ```bash
   # In docker-compose.yml or deployment
   environment:
     - NODE_OPTIONS=--max-old-space-size=4096
   ```

2. **Fix memory leaks**

   ```javascript
   // ❌ LEAK: Unbounded event listeners
   client.on('sync:update', listener);
   
   // ✅ FIXED: Remove listeners when done
   client.on('sync:update', listener);
   // Later:
   client.removeListener('sync:update', listener);
   ```

3. **Optimize data structures**

   ```javascript
   // ❌ LEAK: Keeping all results in memory
   const allResults = [];
   for (const item of largeDataset) {
     allResults.push(process(item));
   }
   
   // ✅ FIXED: Stream processing
   for await (const item of streamData()) {
     process(item); // Process and discard
   }
   ```

4. **Enable heap snapshots**

   ```javascript
   const heapdump = require('heapdump');
   
   process.on('SIGABRT', () => {
     heapdump.writeSnapshot(`heap-${Date.now()}.heapsnapshot`);
     process.exit(1);
   });
   ```

---

### Issue 5: Cache Hit Rate Below 80%

**Symptoms:**

- Cache hit rate < 80%
- High database load
- Repeated queries for same data

**Diagnostics:**

```bash
# Check cache hit rate
redis-cli info stats

# Sample output:
# keyspace_hits:1000000
# keyspace_misses:250000
# hit_rate = 1000000 / (1000000 + 250000) = 80%

# Check cache evictions
redis-cli info stats | grep evicted_keys
```

**Solutions:**

1. **Increase cache size**

   ```javascript
   // config/redis.js
   maxMemory: '8gb', // Increase from 4gb
   maxMemoryPolicy: 'allkeys-lru'
   ```

2. **Adjust TTL values**

   ```javascript
   // Longer TTL for stable data
   CACHE_TTL = {
     userProfile: 3600,      // 1 hour
     suggestions: 300,        // 5 minutes
     dashboardMetrics: 60,   // 1 minute
     staticContent: 86400    // 1 day
   }
   ```

3. **Pre-warm cache**

   ```javascript
   async function warmCache() {
     const users = await db.query('SELECT * FROM users LIMIT 10000');
     for (const user of users) {
       await cache.set(`user:${user.id}`, user, 3600);
     }
   }
   
   // Run on startup
   await warmCache();
   ```

4. **Implement cache versioning**

   ```javascript
   const version = process.env.CACHE_VERSION || '1';
   const cacheKey = `${key}:v${version}`;
   ```

---

### Issue 6: Plugin Sandbox Crashes

**Symptoms:**

- "Plugin sandbox terminated unexpectedly"
- Plugin execution timeout
- Resource limit exceeded errors

**Diagnostics:**

```javascript
// Get plugin crash logs
const logs = await client.plugins.getLogs('plugin_id', {
  level: 'error',
  timeRange: '24h'
});

// Check plugin resource usage
const metrics = await client.plugins.getMetrics('plugin_id');
// { cpuUsage: 95%, memoryUsage: 450MB, cpuLimit: 500m, memoryLimit: 512MB }
```

**Solutions:**

1. **Increase resource limits**

   ```javascript
   await client.plugins.updateLimits('plugin_id', {
     cpuLimit: '1000m',      // 1 CPU
     memoryLimit: '1024MB',  // 1 GB
     timeoutSeconds: 30      // 30 seconds
   });
   ```

2. **Fix plugin memory leak**

   ```javascript
   // ❌ MEMORY LEAK in plugin
   const cache = {};
   worker.on('message', (msg) => {
     cache[msg.id] = msg; // Never cleared
   });
   
   // ✅ FIXED: Clear cache periodically
   setInterval(() => {
     if (Object.keys(cache).length > 10000) {
       Object.clear(cache);
     }
   }, 60000);
   ```

3. **Optimize plugin execution**

   ```javascript
   // Reduce processing time
   const optimized = await plugin.process(data, {
     timeout: 5000,
     streaming: true // Process in chunks
   });
   ```

4. **Use different sandbox type**

   ```javascript
   // Switch from VM to Worker for lower overhead
   await client.plugins.updateConfig('plugin_id', {
     sandboxType: 'worker' // Lighter weight
   });
   ```

---

### Issue 7: Authentication Failures

**Symptoms:**

- "Invalid credentials" even with correct password
- JWT token rejected
- MFA authentication failing

**Diagnostics:**

```bash
# Check auth logs
cat logs/auth.log | grep -i "failed\|error" | tail -20

# Verify token validity
curl -H "Authorization: Bearer $TOKEN" https://api.helios.app/v1/users/me

# Check JWT secret configuration
echo $JWT_SECRET | wc -c
```

**Solutions:**

1. **Reset password**

   ```bash
   curl -X POST https://api.helios.app/v1/auth/forgot-password \
     -H "Content-Type: application/json" \
     -d '{"email":"user@example.com"}'
   
   # Click link in email, set new password
   ```

2. **Verify JWT configuration**

   ```javascript
   // Ensure secrets match
   console.log('JWT_SECRET length:', process.env.JWT_SECRET.length);
   
   // Verify token
   try {
     const decoded = jwt.verify(token, process.env.JWT_SECRET);
     console.log('Token valid, expires:', new Date(decoded.exp * 1000));
   } catch (error) {
     console.error('Token error:', error.message);
   }
   ```

3. **MFA troubleshooting**

   ```javascript
   // Verify TOTP synchronization
   const speakeasy = require('speakeasy');
   
   const verified = speakeasy.totp.verify({
     secret: secret,
     encoding: 'base32',
     token: userCode,
     window: 2 // Allow ±2 time windows
   });
   
   if (!verified) {
     console.log('TOTP not verified, check device time sync');
   }
   ```

4. **Refresh expired token**

   ```javascript
   const refreshResponse = await fetch('https://api.helios.app/v1/auth/refresh', {
     method: 'POST',
     headers: { 'Content-Type': 'application/json' },
     body: JSON.stringify({ refreshToken: oldRefreshToken })
   });
   ```

---

### Issue 8: Network Connectivity Issues

**Symptoms:**

- Intermittent connection drops
- WebSocket reconnection loops
- Offline queue never syncs

**Diagnostics:**

```javascript
// Monitor connectivity
client.on('offline', () => console.log('Went offline'));
client.on('online', () => console.log('Came online'));

// Check network quality
navigator.connection?.addEventListener('change', () => {
  const type = navigator.connection.effectiveType;
  console.log('Network type:', type); // 4g, 3g, 2g, slow-2g
});
```

**Solutions:**

1. **Implement exponential backoff**

   ```javascript
   const reconnectDelays = [1000, 2000, 4000, 8000, 16000, 30000];
   let reconnectAttempt = 0;
   
   client.on('disconnect', () => {
     const delay = reconnectDelays[Math.min(reconnectAttempt, 5)];
     console.log(`Reconnecting in ${delay}ms`);
     setTimeout(() => client.connect(), delay);
     reconnectAttempt++;
   });
   
   client.on('connect', () => {
     reconnectAttempt = 0;
   });
   ```

2. **Increase timeout values**

   ```javascript
   // Adjust for poor network
   const config = {
     connectionTimeout: 10000, // 10s, was 5s
     requestTimeout: 30000,    // 30s, was 15s
     syncInterval: 60000       // 60s, was 30s
   };
   ```

3. **Enable socket.io fallback**

   ```javascript
   const socket = io(url, {
     transports: ['websocket', 'polling'],
     reconnectionDelay: 1000,
     reconnection: true,
     reconnectionAttempts: Infinity
   });
   ```

4. **Monitor offline queue**

   ```javascript
   setInterval(async () => {
     const queue = await client.sync.getOfflineQueue();
     if (queue.pending > 0 && navigator.onLine) {
       console.log(`Syncing ${queue.pending} pending operations`);
       await client.sync.syncData();
     }
   }, 30000);
   ```

---

## Performance Tuning

### Database Optimization

```sql
-- Enable query statistics
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Find slow queries
SELECT query, calls, mean_time
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 20;

-- Add indexes for slow queries
CREATE INDEX idx_sync_events_user_timestamp 
ON sync_events(user_id, timestamp DESC);
```

### Cache Optimization

```javascript
// Implement cache compression
const compress = require('compression');

// Compress large cache values
const compressedValue = compress(JSON.stringify(largeObject));
await redis.set(key, compressedValue);

// Decompress on retrieval
const decompressed = JSON.parse(decompress(cached));
```

### API Response Optimization

```javascript
// Use pagination
app.get('/api/documents', (req, res) => {
  const limit = Math.min(req.query.limit || 50, 1000);
  const offset = (req.query.page || 0) * limit;
  
  // Only fetch needed data
  return db.query('SELECT id, title FROM documents LIMIT $1 OFFSET $2', 
    [limit, offset]);
});

// Compress responses
app.use(compression({ threshold: 1000 }));
```

---

## Monitoring & Alerting

### Key Metrics to Monitor

```
- API latency (p50, p95, p99)
- Error rate (%)
- Database connection pool usage (%)
- Cache hit rate (%)
- Memory usage (%)
- Disk I/O (%)
- WebSocket connections (count)
- Message queue depth (count)
```

### Alert Thresholds

```
- API p99 latency > 1000ms    → Warning
- Error rate > 1%              → Critical
- DB connections > 80%         → Warning
- Cache hit rate < 80%         → Warning
- Memory usage > 90%           → Critical
- Disk usage > 85%             → Warning
```

---

## Debugging Tools

### 1. Using Node Inspector

```bash
node --inspect=9229 server.js
# Open chrome://inspect in Chrome
```

### 2. Log Analysis

```bash
# Find error patterns
grep ERROR logs/*.log | cut -d: -f3 | sort | uniq -c | sort -rn

# Real-time log monitoring
tail -f logs/*.log | grep -E "(ERROR|WARN)"
```

### 3. Database Query Profiling

```sql
EXPLAIN ANALYZE SELECT * FROM documents WHERE user_id = $1;
```

### 4. WebSocket Debugging

```javascript
// Log all WebSocket events
socket.on('connect', () => console.log('WS connected'));
socket.on('disconnect', () => console.log('WS disconnected'));
socket.on('error', (err) => console.error('WS error:', err));
socket.onAny((event, data) => console.log('WS event:', event, data));
```

---

## Contact & Support

**Documentation:** https://docs.helios.app
**Status Page:** https://status.helios.app
**Support Email:** support@helios.app
**Slack Community:** #helios-support

---

**Document Version:** 4.0.0
**Last Updated:** 2026-04-13
