# Quick Start Guide

## Installation

The system is already installed in: `C:\Users\ADMIN\helios-platform\scripts\build-agents`

## Directory Structure

```
build-agents/
├── orchestrator/          # 5 orchestration scripts (48KB)
├── agent-templates/       # 11 autonomous agents (51KB)
├── config/               # Configuration files (13KB)
├── logs/                 # Execution logs
├── temp/                 # Status files
└── README.md            # Full documentation
```

## First Run - DRY RUN (Recommended)

Always test before real execution:

```powershell
cd C:\Users\ADMIN\helios-platform\scripts\build-agents
.\orchestrator\run-all-agents.ps1 -DryRun
```

This will simulate the entire build without making any changes.

## Sequential Execution

Run agents one by one with dependency management:

```powershell
.\orchestrator\run-all-agents.ps1
```

**Typical execution time:** 60-90 minutes
**Best for:** Initial deployments, debugging, conservative approach

## Parallel Execution (Faster)

Run independent agents simultaneously:

```powershell
.\orchestrator\run-agents-parallel.ps1 -MaxParallelJobs 6
```

**Typical execution time:** 30-45 minutes
**Best for:** Faster deployments, production environments

## Monitor Execution

In another PowerShell window:

```powershell
# Overall status
.\orchestrator\check-agent-status.ps1

# Show only failed agents
.\orchestrator\check-agent-status.ps1 -ShowFailed

# Follow specific agent logs
.\orchestrator\check-agent-status.ps1 -FollowLogs -AgentId 3
```

## Emergency Stop

If something goes wrong:

```powershell
# Stop all running agents
.\orchestrator\stop-agents.ps1 -All

# Stop and rollback specific agents
.\orchestrator\stop-agents.ps1 -AgentIds @(3,5) -Rollback
```

## View Results

After execution completes:

```powershell
# List all logs
.\orchestrator\view-agent-logs.ps1 -List

# View specific agent logs
.\orchestrator\view-agent-logs.ps1 -AgentId 5

# Search for errors
.\orchestrator\view-agent-logs.ps1 -Search "ERROR"

# Clean old logs (30+ days)
.\orchestrator\view-agent-logs.ps1 -Clean -CleanDays 30
```

## Agent Execution Order

### Sequential (Single thread):

```
1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 → 11
```

### Parallel (Multiple threads):

```
Batch 1: [1]
Batch 2: [2]
Batch 3: [3]
Batch 4: [4, 5]          # Parallel
Batch 5: [6, 7]          # Parallel
Batch 6: [8]
Batch 7: [9, 10]         # Parallel
Batch 8: [11]
```

## Common Workflows

### 1. Full System Build (Conservative)

```powershell
# Test first
.\orchestrator\run-all-agents.ps1 -DryRun

# Execute
.\orchestrator\run-all-agents.ps1

# Monitor
.\orchestrator\check-agent-status.ps1
```

### 2. Fast Deployment (Production)

```powershell
# Quick dry run
.\orchestrator\run-agents-parallel.ps1 -DryRun

# Execute with parallelization
.\orchestrator\run-agents-parallel.ps1 -MaxParallelJobs 8

# Optional: Monitor in separate window
.\orchestrator\check-agent-status.ps1
```

### 3. Skip Problematic Agent

```powershell
# Skip agent 5 (drivers) if problematic
.\orchestrator\run-all-agents.ps1 -SkipAgents @(5)
```

### 4. Investigate Failure

```powershell
# Show failed agents
.\orchestrator\check-agent-status.ps1 -ShowFailed

# Detailed info for agent 3
.\orchestrator\check-agent-status.ps1 -Details -AgentId 3

# View agent 3 logs
.\orchestrator\view-agent-logs.ps1 -AgentId 3 -Lines 100

# Search for errors in agent 3
.\orchestrator\view-agent-logs.ps1 -AgentId 3 -Search "ERROR"
```

### 5. Recovery from Failure

```powershell
# Emergency stop
.\orchestrator\stop-agents.ps1 -All

# Execute rollback on key agents
.\orchestrator\stop-agents.ps1 -AgentIds @(2,4,6) -Rollback

# Review logs
.\orchestrator\view-agent-logs.ps1 -Search "ROLLBACK"

# Investigate root cause
.\orchestrator\check-agent-status.ps1 -Details -AgentId 3

# Retry individual agent
C:\Users\ADMIN\helios-platform\scripts\build-agents\agent-templates\agent-3-software.ps1
```

## Output Files

Each execution generates outputs in `logs/`:

- `orchestrator_[timestamp].log` - Main orchestration log
- `agent-X-[name]_[timestamp].log` - Individual agent logs
- Configuration backups as JSON files

## Configuration

### agents-config.json

Defines all 11 agents:

- Name and description
- Tasks and scope
- Critical flag
- Estimated duration
- Dependencies

### agent-dependencies.json

Defines:

- Agent dependencies
- Rollback procedures
- Parallel batches
- Failure strategies

## Customization

### Skip Specific Agents

```powershell
# Skip agents 5 and 6
.\orchestrator\run-all-agents.ps1 -SkipAgents @(5,6)
```

### Adjust Parallel Jobs

```powershell
# Use more parallel jobs for faster execution
.\orchestrator\run-agents-parallel.ps1 -MaxParallelJobs 12

# Use fewer for resource-constrained systems
.\orchestrator\run-agents-parallel.ps1 -MaxParallelJobs 2
```

### Disable Rollback

```powershell
# Don't rollback on failure (not recommended)
.\orchestrator\run-all-agents.ps1 -SkipRollback
```

## Troubleshooting

### Script Not Found Error

```powershell
# Make sure you're in the correct directory
cd C:\Users\ADMIN\helios-platform\scripts\build-agents

# Check scripts exist
ls orchestrator/*.ps1
ls agent-templates/*.ps1
```

### Permission Denied

```powershell
# May need to allow script execution
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Agent Timeout (Parallel Only)

```powershell
# Increase timeout to 2 hours
.\orchestrator\run-agents-parallel.ps1 -TimeoutSeconds 7200
```

### Need Admin Privileges

Some agents require admin privileges:

```powershell
# Run PowerShell as Administrator first
Start-Process powershell -Verb RunAs
```

## Performance Tips

1. **Use Parallel for Speed:**

   ```powershell
   .\orchestrator\run-agents-parallel.ps1
   ```

2. **Reduce Max Parallel Jobs if Resource Constrained:**

   ```powershell
   .\orchestrator\run-agents-parallel.ps1 -MaxParallelJobs 4
   ```

3. **Increase Timeout for Slow Systems:**

   ```powershell
   .\orchestrator\run-agents-parallel.ps1 -TimeoutSeconds 7200
   ```

4. **Monitor System Resources:**
   Use Task Manager or Resource Monitor while running parallel builds

## Key Files Location

- **Orchestrator:** `orchestrator/`
- **Agents:** `agent-templates/`
- **Config:** `config/agents-config.json` & `agent-dependencies.json`
- **Logs:** `logs/` (after first run)
- **Status:** `temp/orchestrator_status.json` (during execution)

## Next Steps

1. **Review the system:** Check `README.md` for full documentation
2. **Test execution:** Run `.\orchestrator\run-all-agents.ps1 -DryRun`
3. **Execute full build:** Run `.\orchestrator\run-agents-parallel.ps1`
4. **Monitor progress:** Use `check-agent-status.ps1` in another window
5. **Review results:** Check logs in `view-agent-logs.ps1`

## Support Resources

- **Full README:** `README.md` - Comprehensive documentation
- **Agent Details:** Each agent has `-Description` and comments
- **Configuration:** `config/agents-config.json` - Agent definitions
- **Logs:** `logs/` directory - All execution details
- **Status:** `temp/orchestrator_status.json` - Current execution state

---

**Version:** 1.0  
**Last Updated:** 2024-01-01  
**Platform:** Windows Server 2016+  
**PowerShell:** 5.1+
