# HELIOS Shared Infrastructure Architecture

## System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          HELIOS Platform (7 Components)                      │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │Authentication│  │Code Analysis │  │  Security    │  │DevOps        │   │
│  │  Component   │  │  Component   │  │  Component   │  │Orchestration │   │
│  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                     │
│  │    Test      │  │  Monitoring  │  │  Knowledge   │                     │
│  │  Automation  │  │  Component   │  │    Base      │                     │
│  └──────────────┘  └──────────────┘  └──────────────┘                     │
└────────────────┬────────────────────────────────────────────────────────────┘
                 │
                 │ Uses
                 │
        ┌────────▼────────┐
        │   API Gateway   │ ← Single Entry Point
        │  (9 functions)  │
        └────────┬────────┘
                 │
        ┌────────┴────────┐
        │                 │
    ┌───▼──┐         ┌───▼──┐
    │Cache │         │Logs  │ ← Request Monitoring
    │(5min)│         │      │
    └──────┘         └──────┘
                 │
    ┌────────────▼────────────┐
    │     Event Bus           │ ← Event-Driven Communication
    │   (11 functions)        │
    └────────────┬────────────┘
                 │
        ┌────────┴────────────────┐
        │                         │
    ┌───▼──┐  ┌────────┐  ┌─────▼──┐
    │Event │  │History │  │Filtering│ ← Event Processing
    │Queue │  │(5000)  │  │& Routing│
    └──────┘  └────────┘  └────────┘
                 │
                 │ Uses
                 │
    ┌────────────▼──────────────────────┐
    │  Common Functions Module          │ ← Shared Infrastructure
    │         (19 functions)            │
    ├───────────────────────────────────┤
    │ • Logging (5 levels)              │
    │ • Configuration (Load/Save)       │
    │ • Validation (Prerequisites)      │
    │ • File Operations (Safe)          │
    │ • Database Operations             │
    │ • Event Handling                  │
    │ • Error Handling (Retry)          │
    └────────────┬──────────────────────┘
                 │
    ┌────────────▼───────────────────────┐
    │  Configuration Templates (6 files)  │
    ├─────────────────────────────────────┤
    │ • azure-config.template.json       │
    │ • security-config.template.json    │
    │ • agent-profiles.template.json     │
    │ • model-registry.template.json     │
    │ • optimization-config.template.json│
    │ • component-state.template.json    │
    └─────────────────────────────────────┘
```

## Component Communication Flow

### Synchronous Communication

```
Component A                 API Gateway              Component B
    │                          │                        │
    ├──Invoke-ComponentAPI────→├──Register-Component───→│
    │  (Operation, Params)     │                        │
    │                          ├───Check Cache──────→Cache
    │                          │                        │
    │                          ├───Call Handler────────→│
    │                          │                        │
    │                          ├────Request Log────→Logs
    │                          │                        │
    │◄──Result (cached)────────├◄───Result────────────┤
    │                          │                        │
```

### Asynchronous Communication

```
Component A                 API Gateway              Component B
    │                          │                        │
    ├─Invoke-ComponentAPI─────→├─Queue Job─────────────→│
    │  (Async=true)            │                        │
    │                          │                        │
    │◄──Job ID────────────────┤                        ├─Processing...
    │                          │                        │
    ├──Get-RequestStatus──────→├──Check Job Status───────│
    │                          │                        │
    │◄──Status & Result────────┤◄──Job Complete────────┤
```

### Event-Driven Communication

```
Component A                 Event Bus                Component B
    │                          │                        │
    ├──Subscribe-Event────────→├──Register Subscription─│
    │  (EventName, Callback)   │                        │
    │                          │                        │
    │                          │◄──Subscribe-Event─────┤
    │                          │  (EventName, Callback) │
    │                          │                        │
    ├──Emit-Event─────────────→├──Process Subscribers──→│
    │  (Payload, Priority)     │  (Filter, Sort)        │
    │                          ├──Execute Callbacks────→│
    │                          ├──Log & History────────→│
    │                          │                        │
    │                          ├──Async Queue──────────→│ (optional)
```

## Data Flow Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Configuration Management                                    │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  JSON Config Files     Load-Config    Memory Cache            │
│       ↓                   (load)           ↓                  │
│  • azure-config    ──────────────→  • ConfigCache    ────┐   │
│  • security-config ──────────────→    (5min TTL)         │   │
│  • agent-profiles  ──────────────→                       │   │
│  • model-registry  ──────────────→                       │   │
│  • optimization    ──────────────→  Get-ConfigValue      │   │
│  • component-state ──────────────→    (dot notation)     │   │
│                                       ↓                   │   │
│  Save-Config       ◄──────────────  [Use in Components]  │   │
│    (backup)                                              │   │
│       ↓                                                   │   │
│  Updated Config (*.backup file) ◄─────────────────────┘   │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  Logging & Diagnostics                                      │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  Log-Message     ┐                                            │
│  Log-Error       ├──→ Format with timestamp      ───────┐   │
│  Log-Success     ┘     & component name              │   │   │
│                                                       │   │   │
│                    Color Console Output              │   │   │
│                    (Info, Warning, Error,         ←─┘   │   │
│                     Success, Debug)                      │   │
│                                                       │   │   │
│                    Write to Log File            ←───────┘   │
│                    (C:\HELIOS\logs\*.log)                    │
│                                                               │
│  [Structured for easy parsing & analysis]                    │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  Error Handling & Retry                                      │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  Try-Catch-Retry                                             │
│       ↓                                                      │
│  Attempt 1 ─ Failure ─→ Wait (1000ms) ─→ Attempt 2          │
│                           ↓                                  │
│                   (Exponential Backoff)                      │
│                           ↓                                  │
│  Attempt 2 ─ Failure ─→ Wait (2000ms) ─→ Attempt 3          │
│                                                               │
│  Attempt 3 ─ Success ─→ Return Result                        │
│            or Failure ─→ Throw Exception (& Log)            │
│                                                               │
│  Backoff Multiplier: 2.0 (configurable)                      │
│  Max Attempts: 3 (configurable)                              │
└─────────────────────────────────────────────────────────────┘
```

## Request Processing Pipeline

```
┌─ Incoming Request ─┐
                      ├─→ Log-RequestDetails (INITIATED)
                      │
                      ├─→ Check RequestCache
                      │   ├─ HIT  → Return cached result
                      │   └─ MISS → Continue
                      │
                      ├─→ Get Component from Registry
                      │   ├─ FOUND → Continue
                      │   └─ NOT FOUND → Error & Log
                      │
                      ├─→ Execute Component Handler
                      │   ├─ Sync Path  → Direct execution
                      │   └─ Async Path → Queue as job
                      │
                      ├─→ Cache Result (if cacheable)
                      │
                      ├─→ Log-RequestDetails (COMPLETED/FAILED)
                      │
                      └─→ Return Result/Status
```

## Event Processing Pipeline

```
┌─ Event Registered ─┐
                      ├─→ Register-Event
                      │   ├─ EventName
                      │   ├─ Schema
                      │   └─ Priority
                      │
┌─ Event Emitted ──┐  │
                    ├─→├─→ Get Subscribers
                    │   ├─ Filter by criteria
                    │   └─ Sort by priority
                    │
                    ├─→ Process Subscriptions
                    │   ├─ For each subscriber:
                    │   │  ├─ Test filter
                    │   │  ├─ Execute callback
                    │   │  └─ Handle errors
                    │   │
                    │   └─ Update statistics
                    │
                    ├─→ Log Event History
                    │   └─ Maintain 5000 entries
                    │
                    └─→ Optional: Queue for async
                        └─ Process-AsyncEvents
```

## Caching Architecture

```
┌─────────────────────────────────────────────────┐
│           Request Cache (5-minute TTL)           │
├─────────────────────────────────────────────────┤
│                                                  │
│  Cache Key: ComponentName/Operation/Params      │
│              (hashed)                           │
│                                                  │
│  Cache Entry:                                    │
│    {                                             │
│      Result: <cached response>,                  │
│      Timestamp: <creation time>,                 │
│      TTL: 300 seconds                            │
│    }                                             │
│                                                  │
│  On Request:                                     │
│    1. Generate cache key                         │
│    2. Check if exists & not expired             │
│    3. If valid → Return immediately            │
│    4. If expired → Remove & execute             │
│    5. On completion → Update cache              │
│                                                  │
│  Benefits:                                       │
│    ✓ Reduce redundant API calls                 │
│    ✓ Faster responses                            │
│    ✓ Lower resource usage                        │
│    ✓ Better system performance                   │
└─────────────────────────────────────────────────┘
```

## Statistics & Monitoring Architecture

```
┌─ API Gateway Stats ────────┐
│  • Total components        │
│  • Total requests          │
│  • Total errors            │
│  • Cached items            │
│  • Pending async jobs      │
└─────────────────────────────┘
        │
        ├─ Per Component:
        │   • Request count
        │   • Error count
        │   • Registration time
        │
        └─ Request Log (1000 entries):
            • RequestId
            • Component & Operation
            • Status (INITIATED/COMPLETED/FAILED)
            • Timestamp
            • Error message (if failed)

┌─ Event Bus Stats ──────────┐
│  • Registered events       │
│  • Total subscriptions     │
│  • Total emissions         │
│  • Async queue size        │
│  • History size            │
└─────────────────────────────┘
        │
        ├─ Per Event:
        │   • Emission count
        │   • Subscriber count
        │   • Recent emissions
        │   • Registered date
        │
        └─ Per Subscription:
            • Call count
            • Last execution time
            • Last error (if any)
```

## Database Operation Flow

```
┌─ Query-Database ──┐
                     ├─→ Create connection
                     ├─→ Open connection
                     ├─→ Create command
                     ├─→ Add parameterized parameters
                     │   └─ Prevents SQL injection
                     ├─→ Execute query
                     ├─→ Return DataTable
                     ├─→ Close connection
                     ├─→ Log success
                     └─→ Return result

┌─ Update-Database ─┐
                     ├─→ Create connection
                     ├─→ Open connection
                     ├─→ Create command
                     ├─→ Add parameterized parameters
                     ├─→ Execute update
                     ├─→ Get rows affected
                     ├─→ Close connection
                     ├─→ Log success
                     └─→ Return row count

┌─ Insert-Database ─┐
                     ├─→ Create connection
                     ├─→ Open connection
                     ├─→ Create command
                     ├─→ Add parameterized parameters
                     ├─→ Execute insert
                     ├─→ Get rows affected
                     ├─→ Close connection
                     ├─→ Log success
                     └─→ Return row count
```

## Component Registration & Discovery

```
┌─────────────────────────────────┐
│     Component Registry          │
│  (In-memory dictionary)         │
├─────────────────────────────────┤
│                                 │
│  Key: ComponentName             │
│  Value:                         │
│    {                            │
│      Handler: <script block>,   │
│      Capabilities: [array],     │
│      RequestCount: <number>,    │
│      ErrorCount: <number>,      │
│      Registered: <timestamp>    │
│    }                            │
│                                 │
│  Operations:                    │
│    • Register-Component         │
│      Add entry to registry      │
│    • Get-ComponentInfo          │
│      Return component details   │
│    • Invoke-ComponentAPI        │
│      Look up & execute handler  │
│                                 │
└─────────────────────────────────┘
```

## Async Job Management

```
┌─────────────────────────────────┐
│      Async Job Tracker          │
│  (Job ID → PowerShell Job Map)  │
├─────────────────────────────────┤
│                                 │
│  When Async Request Comes In:   │
│    1. Create PowerShell Job     │
│    2. Store in tracker          │
│    3. Return Job ID             │
│    4. Client polls status       │
│                                 │
│  When Polling Status:           │
│    1. Get Job from tracker      │
│    2. Return current state      │
│    3. If complete:              │
│       • Get results             │
│       • Remove from tracker     │
│       • Return to client        │
│                                 │
│  Job States:                    │
│    • Running → IN_PROGRESS      │
│    • Completed → COMPLETED      │
│    • Failed → FAILED            │
│    • Stopped → CANCELLED        │
│                                 │
└─────────────────────────────────┘
```

## Deployment Layers

```
┌──────────────────────────────────────────────────┐
│  Layer 0: Physical Infrastructure                │
│  (Windows Server, Azure VMs, Network)            │
└──────────────────────────────────────────────────┘
                    ↓
┌──────────────────────────────────────────────────┐
│  Layer 1: Operating System                       │
│  (Windows PowerShell 5.1+, .NET Framework)       │
└──────────────────────────────────────────────────┘
                    ↓
┌──────────────────────────────────────────────────┐
│  Layer 2: Shared Infrastructure                  │
│  (Common Functions, API Gateway, Event Bus)      │
└──────────────────────────────────────────────────┘
                    ↓
┌──────────────────────────────────────────────────┐
│  Layer 3: Configuration Templates                │
│  (Azure, Security, Agents, Models, Optimization) │
└──────────────────────────────────────────────────┘
                    ↓
┌──────────────────────────────────────────────────┐
│  Layer 4: HELIOS Components                      │
│  (7 components using shared infrastructure)      │
└──────────────────────────────────────────────────┘
                    ↓
┌──────────────────────────────────────────────────┐
│  Layer 5: Applications & Users                   │
│  (End-user applications using HELIOS)            │
└──────────────────────────────────────────────────┘
```

## Redundancy Elimination

### Before (Without Shared Infrastructure)

```
Component A          Component B          Component C
├─ Logging           ├─ Logging           ├─ Logging
├─ Config Mgmt       ├─ Config Mgmt       ├─ Config Mgmt
├─ Error Handling    ├─ Error Handling    ├─ Error Handling
├─ File Ops          ├─ File Ops          ├─ File Ops
├─ DB Ops            ├─ DB Ops            ├─ DB Ops
└─ ...repeated...    └─ ...repeated...    └─ ...repeated...
```

❌ Code Duplication | Maintenance Burden | Inconsistency

### After (With Shared Infrastructure)

```
Component A      Component B      Component C
├─ Core Logic    ├─ Core Logic    ├─ Core Logic
└─ Shared Infra  └─ Shared Infra  └─ Shared Infra
       ↓              ↓                 ↓
       └──────────────┴─────────────────┘
            ↓
    [Common Infrastructure]
    ├─ Logging (1 copy)
    ├─ Config Mgmt (1 copy)
    ├─ Error Handling (1 copy)
    ├─ File Ops (1 copy)
    ├─ DB Ops (1 copy)
    └─ ...unified...
```

✅ Single Source of Truth | Easy Maintenance | Consistency

---

**Architecture Version**: 1.0.0
**Design Pattern**: Shared Infrastructure with Microservices
**Communication**: Hybrid (Sync API Gateway + Async Event Bus)
**Status**: Production Ready ✓
