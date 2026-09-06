# Build Agent Orchestration System

A comprehensive PowerShell-based orchestration system for managing complex system build tasks through autonomous agents with dependency management, parallel execution, and rollback capabilities.

## System Architecture

### Directory Structure

```
build-agents/
├── orchestrator/              # Main orchestration scripts (400+ lines)
│   ├── run-all-agents.ps1    # Sequential execution
│   ├── run-agents-parallel.ps1 # Parallel execution with optimization
│   ├── check-agent-status.ps1  # Status monitoring and diagnostics
│   ├── stop-agents.ps1         # Stop and rollback agents
│   └── view-agent-logs.ps1     # Log management and viewing
├── agent-templates/           # 11 autonomous build agents (250+ lines each)
│   ├── agent-1-storage.ps1     # Drive management
│   ├── agent-2-security.ps1    # Security setup
│   ├── agent-3-software.ps1    # Software installation
│   ├── agent-4-users.ps1       # User accounts
│   ├── agent-5-drivers.ps1     # Driver installation
│   ├── agent-6-gui.ps1         # GUI dashboard
│   ├── agent-7-optimization.ps1 # System optimization
│   ├── agent-8-configuration.ps1 # Configuration management
│   ├── agent-9-testing.ps1     # Testing and validation
│   ├── agent-10-monitoring.ps1 # Monitoring and alerting
│   └── agent-11-reporting.ps1  # Reporting and documentation
├── config/                    # Configuration files
│   ├── agents-config.json     # Agent definitions
│   ├── agent-dependencies.json # Dependency chain and rollback
│   └── rollback-procedures.json # Detailed rollback steps
├── logs/                      # Execution logs
└── temp/                      # Temporary files and status
```

## Core Features

### 1. Sequential Execution (`run-all-agents.ps1`)

Execute agents in dependency order with full error handling and rollback support.

```powershell
# Standard execution
.\orchestrator\run-all-agents.ps1

# Skip specific agents
.\orchestrator\run-all-agents.ps1 -SkipAgents @(5,6)

# Dry run mode (simulate without changes)
.\orchestrator\run-all-agents.ps1 -DryRun

# Skip rollback on failure
.\orchestrator\run-all-agents.ps1 -SkipRollback
```

**Features:**

- Dependency graph validation
- Graceful error handling
- Automatic rollback on critical failure
- Comprehensive logging to JSON
- Status tracking and monitoring

### 2. Parallel Execution (`run-agents-parallel.ps1`)

Optimize orchestration speed by running independent agents simultaneously.

```powershell
# Standard parallel (max 4 jobs)
.\orchestrator\run-agents-parallel.ps1

# Configure parallel jobs and timeout
.\orchestrator\run-agents-parallel.ps1 -MaxParallelJobs 8 -TimeoutSeconds 7200

# Dry run
.\orchestrator\run-agents-parallel.ps1 -DryRun
```

**Features:**

- Dependency-aware batch scheduling
- Configurable parallelization levels
- Job monitoring and timeout handling
- Optimal execution time

### 3. Status Monitoring (`check-agent-status.ps1`)

Real-time visibility into agent execution status and logs.

```powershell
# Show overall status
.\orchestrator\check-agent-status.ps1

# Show only failed agents
.\orchestrator\check-agent-status.ps1 -ShowFailed

# Show only running agents
.\orchestrator\check-agent-status.ps1 -ShowRunning

# Show details for specific agent
.\orchestrator\check-agent-status.ps1 -Details -AgentId 5

# Follow live logs for an agent
.\orchestrator\check-agent-status.ps1 -FollowLogs -AgentId 3
```

**Features:**

- Visual status dashboard with color coding
- Execution summary statistics
- Detailed agent information
- Live log following
- Error tracking

### 4. Agent Control (`stop-agents.ps1`)

Stop running agents and execute rollback procedures.

```powershell
# Stop all running agents
.\orchestrator\stop-agents.ps1 -All

# Stop specific agents with rollback
.\orchestrator\stop-agents.ps1 -AgentIds @(3,5) -Rollback

# Force immediate shutdown
.\orchestrator\stop-agents.ps1 -All -Force
```

**Features:**

- Graceful shutdown with timeout
- Force kill capability
- Automatic rollback execution
- Status synchronization

### 5. Log Management (`view-agent-logs.ps1`)

Comprehensive log viewing, searching, and management.

```powershell
# List all available logs
.\orchestrator\view-agent-logs.ps1 -List

# View specific agent logs (last 50 lines)
.\orchestrator\view-agent-logs.ps1 -AgentId 3

# Follow logs in real-time
.\orchestrator\view-agent-logs.ps1 -AgentId 5 -Follow

# Search logs with filtering
.\orchestrator\view-agent-logs.ps1 -Search "error" -Level ERROR

# Show logs since a specific time
.\orchestrator\view-agent-logs.ps1 -AgentId 2 -Since "30 minutes ago"

# Clean old logs (older than 30 days)
.\orchestrator\view-agent-logs.ps1 -Clean -CleanDays 30
```

**Features:**

- Multiple filtering options
- Real-time log following
- Log search with level filtering
- Automatic log cleanup
- Color-coded output

## Agents Overview

### Agent 1: Drive Management

**Scope:** Storage configuration and management
**Tasks:** Drive inventory, disk health checks, storage policies, optimization, VSS setup
**Dependencies:** None
**Critical:** No

### Agent 2: Security Setup

**Scope:** Security configuration and hardening
**Tasks:** Windows Defender, Firewall, audit policies, UAC, BitLocker, Windows Update
**Dependencies:** agent-1
**Critical:** Yes

### Agent 3: Software Installation

**Scope:** Software packages and runtimes
**Tasks:** .NET runtime, VC++ redistributables, dev tools, utilities
**Dependencies:** agent-2
**Critical:** No

### Agent 4: User Accounts Setup

**Scope:** User and group management
**Tasks:** Groups, service accounts, permissions, policies, audit logging
**Dependencies:** agent-2, agent-3
**Critical:** No

### Agent 5: Driver Installation

**Scope:** Hardware and driver management
**Tasks:** Chipset, GPU, network, storage, audio drivers
**Dependencies:** agent-1, agent-2
**Critical:** No

### Agent 6: GUI Dashboard

**Scope:** Monitoring dashboard deployment
**Tasks:** Framework, web server, widgets, authentication, API, SSL/TLS
**Dependencies:** agent-3, agent-4
**Critical:** No

### Agent 7: System Optimization

**Scope:** Performance optimization
**Tasks:** Baselines, service optimization, defrag, memory tuning, network, CPU, power
**Dependencies:** agent-1, agent-5
**Critical:** No

### Agent 8: Configuration Management

**Scope:** System policies and settings
**Tasks:** Group policies, registry, environment, Windows settings, scheduled tasks
**Dependencies:** agent-2, agent-4
**Critical:** No

### Agent 9: Testing and Validation

**Scope:** System validation and testing
**Tasks:** System integrity, network, firewall, security, storage, applications
**Dependencies:** agent-6, agent-7, agent-8
**Critical:** No

### Agent 10: Monitoring and Alerting

**Scope:** Observability and monitoring
**Tasks:** Monitoring agents, counters, event forwarding, log aggregation, alerts, health checks
**Dependencies:** agent-3, agent-4, agent-6
**Critical:** No

### Agent 11: Reporting and Documentation

**Scope:** Final documentation and reporting
**Tasks:** System reports, configuration summary, software inventory, procedures, guides
**Dependencies:** agent-9, agent-10
**Critical:** No

## Dependency Graph

```
agent-1 (Storage)
├── agent-2 (Security) [CRITICAL]
│   ├── agent-3 (Software)
│   │   ├── agent-4 (Users)
│   │   │   └── agent-6 (GUI)
│   │   └── agent-10 (Monitoring)
│   └── agent-8 (Configuration)
└── agent-5 (Drivers)
    └── agent-7 (Optimization)
        └── agent-9 (Testing)
            └── agent-11 (Reporting)
```

## Parallel Execution Batches

```
Batch 1: agent-1 (foundation)
Batch 2: agent-2 (security baseline)
Batch 3: agent-3 (software)
Batch 4: agent-4 + agent-5 (users & drivers in parallel)
Batch 5: agent-6 + agent-7 (GUI & optimization in parallel)
Batch 6: agent-8 (configuration)
Batch 7: agent-9 + agent-10 (testing & monitoring in parallel)
Batch 8: agent-11 (reporting)
```

## Configuration Files

### agents-config.json

Defines all 11 agents with metadata, tasks, outputs, and rollback procedures.

```json
{
  "agents": [
    {
      "id": 1,
      "name": "Drive Management",
      "description": "...",
      "scope": "Storage configuration",
      "critical": false,
      "estimatedDuration": 300,
      "tasks": [...],
      "outputs": [...],
      "rollback": "..."
    }
  ]
}
```

### agent-dependencies.json

Defines dependency relationships, rollback procedures, and failure strategies.

```json
{
  "dependencies": [...],
  "parallelizationGroups": [...],
  "rollbackProcedures": [...],
  "failureStrategies": {
    "criticalAgentFailure": "STOP",
    "nonCriticalAgentFailure": "CONTINUE",
    "maxRetries": 3,
    "rollbackOnCriticalFailure": true
  }
}
```

## Usage Examples

### Basic Full Build (Sequential)

```powershell
CD C:\Users\ADMIN\helios-platform\scripts\build-agents
.\orchestrator\run-all-agents.ps1
```

### Fast Build (Parallel)

```powershell
CD C:\Users\ADMIN\helios-platform\scripts\build-agents
.\orchestrator\run-agents-parallel.ps1 -MaxParallelJobs 6
```

### Monitor During Execution

```powershell
# In another terminal
.\orchestrator\check-agent-status.ps1 -ShowRunning

# Or follow specific agent
.\orchestrator\check-agent-status.ps1 -FollowLogs -AgentId 3
```

### Handle Failure

```powershell
# Check failed agents
.\orchestrator\check-agent-status.ps1 -ShowFailed

# View failure details
.\orchestrator\view-agent-logs.ps1 -AgentId 5 -Search "ERROR"

# Stop all agents and rollback
.\orchestrator\stop-agents.ps1 -All -Rollback
```

### Dry Run Before Production

```powershell
# Simulate the full build
.\orchestrator\run-all-agents.ps1 -DryRun

# Or parallel dry run
.\orchestrator\run-agents-parallel.ps1 -DryRun
```

## Logging

All actions are comprehensively logged:

- **Orchestrator logs:** `logs/orchestrator_[timestamp].log`
- **Agent logs:** `logs/agent-X-[name]_[timestamp].log`
- **Status file:** `temp/orchestrator_status.json`

Logs include:

- Timestamps for all operations
- Level indicators (INFO, WARN, ERROR, SUCCESS)
- Detailed error messages
- Configuration backups
- Test results

## Rollback Procedures

Rollback is automatic when:

1. A critical agent fails
2. Agent dependencies cannot be satisfied
3. Fatal errors occur during execution

Manual rollback:

```powershell
.\orchestrator\stop-agents.ps1 -All -Rollback
```

Each agent defines rollback steps that restore the system to its pre-execution state.

## Best Practices

1. **Always do a dry run first:**

   ```powershell
   .\orchestrator\run-all-agents.ps1 -DryRun
   ```

2. **Monitor execution:**

   ```powershell
   .\orchestrator\check-agent-status.ps1
   ```

3. **Review logs on failure:**

   ```powershell
   .\orchestrator\view-agent-logs.ps1 -ShowFailed
   ```

4. **Use parallel execution for speed:**

   ```powershell
   .\orchestrator\run-agents-parallel.ps1
   ```

5. **Document configuration:**
   All outputs are saved to JSON files for audit trail

6. **Test critical components:**
   - Run individual agents if needed
   - Use test environments first

## Troubleshooting

### Agent Timeout

- Increase timeout: `run-agents-parallel.ps1 -TimeoutSeconds 7200`
- Check logs for hanging tasks

### Dependency Issues

- View dependency graph in `agent-dependencies.json`
- Skip problematic dependencies: `run-all-agents.ps1 -SkipAgents @(5)`

### Partial Failures

- Review failed agent logs: `view-agent-logs.ps1 -ShowFailed`
- Execute rollback: `stop-agents.ps1 -All -Rollback`
- Fix issue and retry

### Performance Issues

- Use parallel execution with fewer jobs: `run-agents-parallel.ps1 -MaxParallelJobs 4`
- Check system resources during execution

## Security Considerations

- All sensitive operations logged (without passwords)
- Service account credentials managed externally
- Audit trail for all configuration changes
- Rollback capability for all changes
- Permission-based access control

## Version Information

- **Version:** 1.0
- **Created:** 2024-01-01
- **PowerShell:** 5.1+
- **Platform:** Windows Server 2016+

## Support and Maintenance

### Updating Agents

1. Edit agent script in `agent-templates/`
2. Update configuration in `config/agents-config.json`
3. Test with dry run
4. Deploy

### Adding New Agents

1. Create `agent-N-name.ps1` in `agent-templates/`
2. Add to `agents-config.json`
3. Define dependencies in `agent-dependencies.json`
4. Update parallelization groups

### Monitoring

- Real-time status: `check-agent-status.ps1`
- Historical logs: `view-agent-logs.ps1`
- JSON outputs for integration with monitoring systems
