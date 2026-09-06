# AI Orchestration Layer - Quick Reference Card

## 🚀 60-Second Setup

```csharp
// 1. Create services (DI)
services.AddSingleton<IToolOrchestratorEngine, ToolOrchestratorEngine>();

// 2. Initialize
var orchestrator = serviceProvider.GetRequiredService<IToolOrchestratorEngine>();
await orchestrator.InitializeAsync();

// 3. Register tools
await orchestrator.RegisterToolAsync(new ToolInfo { ToolId = "tool-1", ToolName = "My Tool" });

// 4. Start tool
await orchestrator.StartToolAsync("tool-1");

// 5. Switch profile
await orchestrator.SwitchProfileAsync(OrchestrationProfile.Gaming);
```

---

## 📌 Core APIs

### Master Orchestration

```csharp
await orchestrator.InitializeAsync();                    // Start
await orchestrator.RegisterToolAsync(tool);              // Register
await orchestrator.StartToolAsync("toolId");             // Start tool
await orchestrator.SwitchProfileAsync(profile);          // Switch profile
var stats = await orchestrator.GetStatsAsync();           // Get stats
await orchestrator.ShutdownAsync();                       // Stop
```

### Tool Optimization

```csharp
await profiler.ProfileToolAsync("toolId");               // Profile
var metrics = await profiler.GetPerformanceMetricsAsync("toolId");
var recommendations = await profiler.AnalyzeToolAsync("toolId");
await profiler.ApplyOptimizationAsync("toolId", rec);    // Apply
var allocation = await profiler.OptimizeAllocationAsync("toolId", profile);
```

### Health Monitoring

```csharp
var health = await monitor.GetHealthMetricsAsync("toolId");
var isHealthy = await monitor.IsToolHealthyAsync("toolId");
var conflicts = await monitor.DetectConflictsAsync();    // Detect
await monitor.ResolveConflictAsync(conflictId);          // Resolve
var events = await monitor.GetRecentEventsAsync(100);    // Events
```

---

## 🎯 Common Patterns

### Monitor System Health

```csharp
while (true)
{
    var isHealthy = await orchestrator.IsHealthyAsync();
    if (!isHealthy)
    {
        var stats = await orchestrator.GetStatsAsync();
        Console.WriteLine($"Failed: {stats.ToolsFailed}");
    }
    await Task.Delay(5000);
}
```

### Profile-Aware Optimization

```csharp
var profile = OrchestrationProfile.Gaming;
var allocation = await profiler.OptimizeAllocationAsync("toolId", profile);
await profiler.UpdateResourceAllocationAsync("toolId", allocation);
```

### Automatic Conflict Resolution

```csharp
var conflicts = await monitor.DetectConflictsAsync();
foreach (var conflict in conflicts)
{
    await monitor.ResolveConflictAsync(conflict.ConflictId);
}
```

---

## 📊 Profiles

| Profile | CPU | Memory | GPU | Priority | Use Case |
|---------|-----|--------|-----|----------|----------|
| Gaming | 80% | 1024MB | 90% | 10 | Gaming/Performance |
| Development | 60% | 768MB | 50% | 7 | Development |
| Work | 50% | 512MB | 30% | 5 | Productivity |
| Secure | 40% | 256MB | 10% | 8 | Security |

---

## 🔧 Tool Statuses

- `Initializing` → `Running` → `Idle`
- `Running` → `Degraded` (issues detected)
- `Any` → `Failed` (crash/hang)
- `Failed` → `Restarting` (auto-recovery)
- `Any` → `Stopped` (manual stop)

---

## ⚠️ Optimization Categories

1. **CpuUsage** - CPU reduction
2. **MemoryUsage** - Memory optimization
3. **DiskIO** - I/O optimization
4. **GpuUsage** - GPU acceleration
5. **Latency** - Response time
6. **Throughput** - Ops per second
7. **Reliability** - Crash prevention
8. **Security** - Security hardening

---

## 🔴 Conflict Types

| Type | Resolution |
|------|-----------|
| ResourceContention | Throttle to 50% allocation |
| DependencyMissing | Restart dependent tool |
| VersionIncompatibility | Upgrade to compatible version |
| CommunicationFailure | Restart communication channel |
| StateInconsistency | Reset shared state |
| PermissionDenied | Adjust security permissions |

---

## 📈 Performance Targets

| Operation | Target Time |
|-----------|------------|
| Tool Start | ~100ms |
| Tool Stop | ~50ms |
| Profile Switch | ~200ms |
| Conflict Detection | ~500ms |
| Orchestration Cycle | ~5 seconds |

---

## 🧪 Testing Template

```csharp
[Fact]
public async Task MyTest()
{
    // Arrange
    var orchestrator = CreateOrchestratorWithMocks();
    await orchestrator.InitializeAsync();

    // Act
    var result = await orchestrator.StartToolAsync("tool-1");

    // Assert
    Assert.True(result);
}
```

---

## 🚨 Error Handling

```csharp
try
{
    await orchestrator.StartToolAsync("tool-1");
}
catch (ArgumentNullException ex)
{
    logger.LogError("Invalid tool ID");
}
catch (Exception ex)
{
    logger.LogError(ex, "Orchestration error");
}
```

---

## 📝 Health Score Interpretation

| Score | Status | Action |
|-------|--------|--------|
| 80-100 | Excellent | Continue monitoring |
| 60-79 | Good | Standard monitoring |
| 40-59 | Fair | Investigate, optimize |
| 20-39 | Poor | Restart tool |
| 0-19 | Critical | Stop & investigate |

---

## 🔐 Security Profile Settings

```json
{
  "maxCpuPercent": 40,
  "enableSandboxing": true,
  "enableSecurityAuditing": true,
  "isolationLevel": "strict"
}
```

---

## 🎮 Gaming Profile Settings

```json
{
  "maxCpuPercent": 80,
  "enableGpuAcceleration": true,
  "threadPoolSize": 16,
  "asyncBufferSize": 65536
}
```

---

## 💼 Work Profile Settings

```json
{
  "maxCpuPercent": 50,
  "enablePowerSaving": true,
  "threadPoolSize": 4,
  "gcFrequency": "conservative"
}
```

---

## 📚 Key Classes

| Class | Purpose |
|-------|---------|
| `ToolOrchestratorEngine` | Master orchestration |
| `ToolOptimizationProfiler` | Tool optimization |
| `ToolHealthMonitorCoordinator` | Health monitoring |
| `ToolInfo` | Tool metadata |
| `ToolConflict` | Conflict info |
| `OptimizationRecommendation` | Optimization suggestion |

---

## 🔗 Dependency Graph

```
ToolOrchestratorEngine
├── IToolHealthMonitorCoordinator
├── IToolOptimizationProfiler
├── IToolConflictResolver
└── IToolCommunicationCoordinator
    └── Various logging/config
```

---

## 📊 Stats Overview

```csharp
var stats = await orchestrator.GetStatsAsync();

// Access properties
stats.TotalToolsManaged           // Total tools
stats.ToolsRunning                // Active tools
stats.ToolsFailed                 // Failed tools
stats.AverageSystemHealth         // Health %
stats.AverageCpuUtilization       // CPU %
stats.AverageMemoryUtilization    // Memory MB
```

---

## ⏱️ Timing Notes

- **Initialization**: ~500ms (includes subfactory init)
- **Orchestration Loop**: Every 5 seconds
- **Health Checks**: Every 3 seconds
- **Profile Switch**: ~200ms (reconfigures tools)
- **Tool Restart**: ~1-2 seconds

---

## 🎓 Integration Checklist

- [ ] Add DI services
- [ ] Create orchestrator instance
- [ ] Call `InitializeAsync()`
- [ ] Register all 45 tools
- [ ] Start tools
- [ ] Monitor health periodically
- [ ] Handle optimization recommendations
- [ ] Respond to profile switches
- [ ] Call `ShutdownAsync()` on exit

---

## 📖 Documentation Files

1. **README.md** - Architecture & detailed docs
2. **INTEGRATION_GUIDE.md** - API reference & examples
3. **IMPLEMENTATION_SUMMARY.md** - Project statistics
4. **QUICK_REFERENCE.md** - This file

---

## 🆘 Common Troubleshooting

**Tool won't start?**

- Check dependencies registered
- Verify resource limits
- Review recent events

**High CPU usage?**

- Switch to Work profile
- Check optimization recommendations
- Reduce thread pool size

**Frequent conflicts?**

- Review dependency graph
- Adjust resource allocation
- Enable debug logging

---

## 💡 Pro Tips

1. **Always initialize before use**
2. **Monitor health regularly**
3. **Apply optimizations for priority >= 8**
4. **Switch profiles based on activity**
5. **Review event logs for issues**
6. **Keep restart attempts under 3**
7. **Use profile-specific settings**
8. **Plan for 45+ tools minimum**

---

## 🔐 Thread Safety

All operations are thread-safe via `SemaphoreSlim(1)`:

- ✅ Concurrent reads allowed
- ✅ Exclusive writes enforced
- ✅ No race conditions
- ✅ Safe for multi-threaded use

---

## 📞 Support Resources

```
Documentation:
- C:\...\AIOrchestration\README.md
- C:\...\AIOrchestration\INTEGRATION_GUIDE.md

Tests:
- C:\...\AIOrchestration\Tests\AIOrchestrationTests.cs

Configuration:
- C:\...\AIOrchestration\Profiles\orchestration-profiles.json
```

---

**Last Updated**: 2024  
**Version**: 1.0  
**Status**: Production Ready

Keep this card handy for quick development reference! 🚀
