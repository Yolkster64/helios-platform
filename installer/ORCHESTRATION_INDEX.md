# HELIOS Platform: Orchestration & Deployment System

## Complete Index & Reference Guide

---

## 📋 TABLE OF CONTENTS

### 1. Orchestration Scripts (6 files)

- **master-orchestrator.ps1** - Central coordination and state management
- **cross-component-api.ps1** - Unified API for all components  
- **event-routing.ps1** - Event pub/sub messaging system
- **azure-fabric-bridge.ps1** - Azure/Microsoft Fabric integration
- **decision-engine.ps1** - Interactive deployment configuration wizard
- **monitoring-dashboard.ps1** - Real-time monitoring and alerting

### 2. Deployment Scripts (5 files)

- **phase-1-deploy.ps1** - Foundation deployment (Monado, Aegis, USB Auth)
- **phase-2-deploy.ps1** - Automation deployment (AI Hub, Dev Hub, GUI)
- **phase-3-deploy.ps1** - Professional deployment (Build Agents, Optimization)
- **phase-4-deploy.ps1** - Enterprise deployment (Security, Enterprise Features)
- **rollback.ps1** - Safe atomic rollback to any phase

### 3. Testing Scripts (4 files)

- **integration-tests.ps1** - Cross-component validation
- **phase-validator.ps1** - Phase readiness verification
- **security-scanner.ps1** - Security & compliance scanning
- **performance-baseline.ps1** - Performance baseline establishment

### 4. Configuration Files (2 files)

- **component-definitions.json** - Component specs and dependencies
- **deployment-state.json** - Persistent deployment state

### 5. Documentation (2 files)

- **README.md** - Comprehensive user guide
- **DEPLOYMENT_SUMMARY.md** - Complete system overview

---

## 🎯 ORCHESTRATION SCRIPTS REFERENCE

### master-orchestrator.ps1

**Purpose**: Central orchestration hub for 4-phase deployment

**Usage**:

```powershell
# Deploy Phase 1
.\master-orchestrator.ps1 -Phase 1 -Action Deploy

# View deployment status
.\master-orchestrator.ps1 -Action Status

# Run pre-flight checks for Phase 2
.\master-orchestrator.ps1 -Phase 2 -Action PreFlight

# Deploy all phases (Phase 1 → Phase 4)
.\master-orchestrator.ps1 -Phase All -Action Deploy
```

**Key Parameters**:

- `-Phase`: Phase number (1, 2, 3, 4, or All)
- `-Action`: Deploy, Validate, Status, Rollback, PreFlight
- `-StateFile`: Path to deployment state JSON

**Features**:

- Phase dependency tracking
- Component synergy detection
- State persistence
- Automatic rollback hooks

---

### cross-component-api.ps1

**Purpose**: Unified API gateway for all 7 components

**Usage**:

```powershell
# Check system health
.\cross-component-api.ps1 -Method GET -Route '/system/health'

# Authorize user in Monado
.\cross-component-api.ps1 -Method POST -Route '/monado/authorize' `
  -Body @{ user='admin'; password='secure' }

# Get AI Hub models
.\cross-component-api.ps1 -Method GET -Route '/ai-hub/models'

# Request build job
.\cross-component-api.ps1 -Method POST -Route '/build-agents/deploy' `
  -Body @{ repo='myapp'; branch='main' }
```

**Available Routes**:

- `/system/health` - System health status
- `/system/metrics` - System-wide metrics
- `/system/components` - List all components
- `/monado/*` - Monado component APIs
- `/aegis/*` - Aegis security APIs
- `/ai-hub/*` - AI Hub APIs
- `/dev-hub/*` - Dev Hub APIs
- `/build-agents/*` - Build agent APIs

**Rate Limits** (per minute):

- `/system/health`: 10,000 req/min
- `/ai-hub/predict`: 500 req/min
- `/build-agents/deploy`: 100 req/min

---

### event-routing.ps1

**Purpose**: Pub/sub messaging system for component events

**Usage**:

```powershell
# Publish an event
.\event-routing.ps1 -Action Publish `
  -Source 'ai-hub' `
  -EventType 'training_complete' `
  -Data @{ model='gpt-4'; accuracy=0.95 }

# Subscribe to events
.\event-routing.ps1 -Action Subscribe `
  -Component 'dev-hub' `
  -EventFilter 'training*'

# View event history
.\event-routing.ps1 -Action GetHistory -Limit 100

# Replay events
.\event-routing.ps1 -Action Replay -LastNEvents 10

# View routing status
.\event-routing.ps1 -Action GetStatus
```

**Supported Event Types**:

- Component lifecycle: `component_started`, `component_stopped`, `component_failed`
- Deployment: `deployment_started`, `deployment_completed`, `deployment_failed`
- Processing: `training_complete`, `model_ready`, `build_triggered`, `build_completed`
- Operations: `security_alert`, `policy_updated`, `performance_degradation`

---

### azure-fabric-bridge.ps1

**Purpose**: Bidirectional Azure/Microsoft Fabric integration

**Usage**:

```powershell
# Initialize Azure connection
.\azure-fabric-bridge.ps1 -Action InitializeConnection

# Stream telemetry
.\azure-fabric-bridge.ps1 -Action StreamTelemetry `
  -Component 'ai-hub' `
  -Metrics @{ cpu=45; memory=62; requests_per_sec=250 }

# Stream events
.\azure-fabric-bridge.ps1 -Action StreamEvent `
  -EventType 'deployment_complete' `
  -EventData @{ phase=1; duration_hours=9 }

# Get optimization recommendations
.\azure-fabric-bridge.ps1 -Action GetRecommendations

# Sync configuration from Fabric
.\azure-fabric-bridge.ps1 -Action SyncConfiguration

# Test Azure connection
.\azure-fabric-bridge.ps1 -Action TestConnection

# View bridge status
.\azure-fabric-bridge.ps1 -Action GetStatus
```

**Azure Services Used**:

- Log Analytics - Telemetry ingestion
- Application Insights - Metrics and diagnostics
- Event Hub - Event streaming
- Microsoft Fabric - Recommendations and insights

---

### decision-engine.ps1

**Purpose**: Interactive deployment wizard for configuration generation

**Usage**:

```powershell
# Run interactive wizard
.\decision-engine.ps1 -Action RunWizard

# Get profile details
.\decision-engine.ps1 -Action GetProfile -Profile 'Enterprise'

# Generate config based on responses
.\decision-engine.ps1 -Action GenerateConfig `
  -Responses @{ deploymentType='Enterprise'; users=1000; securityLevel='Enterprise' }

# List available profiles
.\decision-engine.ps1 -Action GetProfiles

# View engine status
.\decision-engine.ps1 -Action GetStatus
```

**Deployment Profiles**:

1. **SMB**: Up to 50 users, cost-optimized
   - 1 AI Hub instance
   - 2 build agents
   - Monthly cost: $500-800

2. **Mid-Market**: 50-500 users, balanced
   - 3 AI Hub instances
   - 5 build agents
   - Monthly cost: $2000-3500

3. **Enterprise**: 500+ users, high-performance
   - 5 AI Hub instances
   - 10 build agents
   - Monthly cost: $8000-15000

---

### monitoring-dashboard.ps1

**Purpose**: Real-time system monitoring with 5-second refresh

**Usage**:

```powershell
# Start real-time dashboard (auto-refresh every 5 seconds)
.\monitoring-dashboard.ps1 -Action StartDashboard

# Get component status snapshot
.\monitoring-dashboard.ps1 -Action GetComponentStatus

# Get metrics for specific component
.\monitoring-dashboard.ps1 -Action GetMetrics -Component 'ai-hub'

# View active alerts
.\monitoring-dashboard.ps1 -Action GetAlerts

# Get system health
.\monitoring-dashboard.ps1 -Action GetSystemHealth
```

**Monitored Metrics**:

- Per-component: CPU%, Memory%, Disk%, Requests/sec, Error rate, Latency
- System-wide: Overall health status, Phase progress, Active alerts
- Performance: P95/P99 latencies, Throughput, Queue depths

**Health Status**:

- 🟢 Green (Healthy): All components operational, <1% errors
- 🟡 Yellow (Warning): Minor issues, 1-5% errors
- 🔴 Red (Critical): Failures, >5% errors or component down

---

## 📦 DEPLOYMENT SCRIPTS REFERENCE

### phase-1-deploy.ps1

**Purpose**: Deploy foundation components (~9 hours)

**Usage**:

```powershell
# Standard deployment with validation
.\phase-1-deploy.ps1

# Skip validation (for re-runs)
.\phase-1-deploy.ps1 -SkipValidation
```

**Deploys**:

1. Monado - Pattern recognition engine
2. Aegis - Security policy management
3. USB Auth - Device authentication

**Produces**: Snapshot `phase-1-YYYYMMDD-HHMMSS` for rollback

---

### phase-2-deploy.ps1

**Purpose**: Deploy automation components (~10 hours)

**Usage**:

```powershell
# Deploy Phase 2 (requires Phase 1 complete)
.\phase-2-deploy.ps1

# Skip Phase 1 validation
.\phase-2-deploy.ps1 -SkipValidation
```

**Deploys**:

1. AI Hub - ML model orchestration (5 instances)
2. Dev Hub - Development environment
3. GUI Dashboard - Web monitoring interface

**Synergies Enabled**:

- AI Hub + Dev Hub: ML automation (+20% efficiency)
- GUI Dashboard linked to all components

---

### phase-3-deploy.ps1

**Purpose**: Deploy professional features (~30 hours)

**Usage**:

```powershell
# Deploy Phase 3 (requires Phase 1 & 2 complete)
.\phase-3-deploy.ps1
```

**Deploys**:

1. Build Agents - CI/CD automation (10 instances)
2. Advanced Optimization - ML performance tuning

**Synergies Enabled**:

- AI Hub + Build Agents: Intelligent build optimization (+25% efficiency)
- Advanced Optimization + AI Hub: ML-driven tuning (+30% efficiency)

---

### phase-4-deploy.ps1

**Purpose**: Deploy enterprise features (~40 hours)

**Usage**:

```powershell
# Deploy Phase 4 - System becomes enterprise-ready
.\phase-4-deploy.ps1
```

**Deploys**:

1. Advanced Security - Enterprise compliance (HIPAA, SOC2, ISO27001, GDPR)
2. Enterprise Features - Multi-tenancy, SLA management

**Compliance Enabled**:

- ✓ HIPAA - Healthcare data protection
- ✓ SOC2 - Security audit logging
- ✓ ISO27001 - Information security
- ✓ GDPR - Data protection & privacy

---

### rollback.ps1

**Purpose**: Safe atomic rollback to any checkpoint

**Usage**:

```powershell
# Rollback Phase 2
.\rollback.ps1 -Phase 2

# Rollback specific component
.\rollback.ps1 -Phase 3 -Component 'ai-hub'

# Rollback to specific snapshot
.\rollback.ps1 -ToSnapshot 'phase-3-20240115-001'

# Full system rollback
.\rollback.ps1 -Full -Confirm

# List available snapshots
.\rollback.ps1
```

**Rollback Process**:

1. Pre-rollback validation
2. Stop all services
3. Restore from snapshot
4. Verify data consistency
5. Restart services
6. Post-rollback health checks

---

## 🧪 TESTING SCRIPTS REFERENCE

### integration-tests.ps1

**Purpose**: Validate cross-component integration

**Usage**:

```powershell
# Run all tests
.\integration-tests.ps1

# Run only critical tests
.\integration-tests.ps1 -Suite 'critical'

# Run performance tests
.\integration-tests.ps1 -Suite 'performance'

# Run resilience tests
.\integration-tests.ps1 -Suite 'resilience'

# Test specific component
.\integration-tests.ps1 -Component 'ai-hub'
```

**Test Coverage**:

- 15+ integration tests
- Component interoperability
- API contracts
- Data flow integrity
- Event routing
- Error handling
- Performance under load
- Security isolation

**Pass Criteria**: ≥95% tests must pass

---

### phase-validator.ps1

**Purpose**: Verify phase readiness before advancement

**Usage**:

```powershell
# Validate Phase 1
.\phase-validator.ps1 -Phase 1

# Validate Phase 3 with details
.\phase-validator.ps1 -Phase 3 -Verbose
```

**Validations**:

- Component deployment confirmation
- Dependency completion
- Configuration correctness
- Phase-specific requirements
- Next phase prerequisites

**Exit Codes**:

- 0 = Phase ready for advancement
- 1 = Phase not ready, review errors

---

### security-scanner.ps1

**Purpose**: Comprehensive security and compliance validation

**Usage**:

```powershell
# Scan Phase 1 security
.\security-scanner.ps1 -Phase 1

# Scan Phase 4 with enterprise compliance
.\security-scanner.ps1 -Phase 4 -Verbose

# Fix security issues (if supported)
.\security-scanner.ps1 -Phase 2 -FixIssues
```

**Security Checks** (Phase 1):

- SSH key authentication
- Default credentials removed
- Firewall rules
- Logging enabled

**Security Checks** (Phase 4):

- End-to-end encryption
- HIPAA compliance
- SOC2 audit logging
- ISO27001 controls
- GDPR data protection

**Exit Codes**:

- 0 = All security checks passed
- 1 = Security issues found

---

### performance-baseline.ps1

**Purpose**: Establish performance baseline for regression testing

**Usage**:

```powershell
# Quick baseline (5 seconds)
.\performance-baseline.ps1 -LoadProfile 'quick'

# Standard baseline (15 seconds)
.\performance-baseline.ps1 -LoadProfile 'standard'

# Sustained load baseline (30 seconds)
.\performance-baseline.ps1 -LoadProfile 'sustained'

# Custom duration
.\performance-baseline.ps1 -LoadProfile 'standard' -Duration 20
```

**Baseline Metrics**:

- API latency: min, max, avg, p50, p95, p99
- Throughput: requests/second
- Resource usage: CPU%, memory%, disk%
- Error rate and queue depths

**Acceptance Criteria**:

- P95 latency < 500ms
- P99 latency < 1000ms
- Throughput ≥ 100 RPS
- Error rate < 1%

---

## 🔧 CONFIGURATION REFERENCE

### component-definitions.json

**Schema**:

```json
{
  "components": [
    {
      "id": "component-name",
      "phase": 1,
      "name": "Display Name",
      "dependencies": ["dep1", "dep2"],
      "critical": true,
      "estimated_deployment_hours": 3,
      "api_endpoint": "/component"
    }
  ],
  "synergies": [
    {
      "components": ["comp1", "comp2"],
      "benefit": "Description",
      "efficiency_improvement_percent": 20
    }
  ]
}
```

### deployment-state.json

**Schema**:

```json
{
  "deployment_id": "helios-YYYYMMDD-HHMMSS",
  "started_at": "2024-01-15T10:00:00Z",
  "phases": {
    "Phase 1": {
      "status": "completed|in_progress|pending|failed",
      "components": {
        "component": {
          "status": "deployed|pending",
          "completed_at": "2024-01-15T11:00:00Z"
        }
      }
    }
  }
}
```

---

## 📊 COMPONENT DEPENDENCIES

```
Phase 1 (Foundation):
  Monado
    ↓
  Aegis ← (depends on Monado)
    ↓
  USB Auth ← (depends on Aegis)

Phase 2 (Automation):
  AI Hub ← (depends on Monado, Aegis)
  Dev Hub ← (depends on Monado, AI Hub)
  GUI Dashboard ← (depends on Monado, Aegis)
  
Phase 3 (Professional):
  Build Agents ← (depends on Dev Hub)
  Advanced Optimization ← (depends on AI Hub, Build Agents)
  
Phase 4 (Enterprise):
  Advanced Security ← (depends on Aegis, GUI Dashboard)
  Enterprise Features ← (depends on Advanced Security)
```

---

## 🎯 TYPICAL DEPLOYMENT WORKFLOW

### Day 1: Phase 1 Deployment

```powershell
# 1. Check prerequisites
.\orchestration\master-orchestrator.ps1 -Phase 1 -Action PreFlight

# 2. Deploy Phase 1
.\deployment\phase-1-deploy.ps1

# 3. Validate
.\testing\phase-validator.ps1 -Phase 1 -Verbose

# 4. Test
.\testing\integration-tests.ps1 -Suite 'critical'

# 5. Security scan
.\testing\security-scanner.ps1 -Phase 1
```

### Day 2: Phase 2 Deployment

```powershell
# 1. Start monitoring
.\orchestration\monitoring-dashboard.ps1 -Action StartDashboard

# 2. Deploy Phase 2
.\deployment\phase-2-deploy.ps1

# 3. Validate
.\testing\phase-validator.ps1 -Phase 2

# 4. Test
.\testing\integration-tests.ps1

# 5. Security scan
.\testing\security-scanner.ps1 -Phase 2
```

### Optional: Phase 3 & 4

```powershell
# Phase 3 (professional features)
.\deployment\phase-3-deploy.ps1
.\testing\phase-validator.ps1 -Phase 3
.\testing\integration-tests.ps1
.\testing\security-scanner.ps1 -Phase 3

# Phase 4 (enterprise-ready)
.\deployment\phase-4-deploy.ps1
.\testing\phase-validator.ps1 -Phase 4
.\testing\integration-tests.ps1
.\testing\security-scanner.ps1 -Phase 4
.\testing\performance-baseline.ps1
```

---

## 📞 SUPPORT & TROUBLESHOOTING

### Common Issues

**"Deployment failed - prerequisites not met"**

```powershell
# Check prerequisites
.\orchestration\master-orchestrator.ps1 -Phase 1 -Action PreFlight
```

**"Component unhealthy"**

```powershell
# Check component metrics
.\orchestration\monitoring-dashboard.ps1 -Action GetMetrics -Component 'component-name'

# Check alerts
.\orchestration\monitoring-dashboard.ps1 -Action GetAlerts
```

**"Need to rollback Phase 2"**

```powershell
# Rollback Phase 2
.\deployment\rollback.ps1 -Phase 2

# Verify rollback
.\orchestration\monitoring-dashboard.ps1 -Action GetSystemHealth
```

### Getting Help

1. **Check system status**:

   ```powershell
   .\orchestration\monitoring-dashboard.ps1
   ```

2. **Review event history**:

   ```powershell
   .\orchestration\event-routing.ps1 -Action GetHistory -Limit 50
   ```

3. **Run full test suite**:

   ```powershell
   .\testing\integration-tests.ps1
   ```

4. **Check Azure diagnostics**:

   ```powershell
   .\orchestration\azure-fabric-bridge.ps1 -Action GetRecommendations
   ```

---

**Last Updated**: January 15, 2024  
**System Status**: ✅ Production Ready  
**Total Scripts**: 17  
**Total Size**: 155 KB
