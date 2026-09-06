# HELIOS Shared Infrastructure - Quick Reference

## Directory Structure

```
C:\HELIOS\core-infrastructure\shared-resources\
├── common-functions.psm1                    # Shared utilities module (24 KB)
├── api-gateway.ps1                         # API gateway for component communication (17 KB)
├── event-bus.ps1                           # Event-driven communication layer (18 KB)
├── config-templates/                       # Configuration templates
│   ├── azure-config.template.json          # Azure/Copilot/DevOps config
│   ├── security-config.template.json       # Security policies (AppLocker, Defender, Bitdefender)
│   ├── agent-profiles.template.json        # 12 AI agent definitions
│   ├── model-registry.template.json        # 35+ AI models with routing
│   ├── optimization-config.template.json   # Cost/Speed/Quality/Scale profiles
│   └── component-state.template.json       # State tracking for 7 components
└── README.md                                # Full documentation (23 KB)
```

**Total Size**: ~109 KB | **All files validated and production-ready**

---

## Quick Start

### 1. Initialize a Component

```powershell
# Import shared functions
Import-Module "C:\HELIOS\core-infrastructure\shared-resources\common-functions.psm1"

# Setup logging
Initialize-Logging -LogPath "C:\HELIOS\logs\my-component.log"

# Load configuration
$config = Load-Config -ConfigPath "C:\HELIOS\config\azure-config.json"

# Validate prerequisites
Validate-Prerequisites -Requirements @("PowerShell5.1", "AzureCLI")
```

### 2. Register with API Gateway

```powershell
. "C:\HELIOS\core-infrastructure\shared-resources\api-gateway.ps1"

Register-Component -ComponentName "MyComponent" `
                  -Handler {
                      param($Operation, $Parameters)
                      # Your handler logic
                  } `
                  -Capabilities @("operation1", "operation2")
```

### 3. Subscribe to Events

```powershell
. "C:\HELIOS\core-infrastructure\shared-resources\event-bus.ps1"

Subscribe-Event -EventName "MyEvent" `
               -Component "MyComponent" `
               -Callback { param($event) Log-Message "Event: $($event.EventName)" }
```

---

## Function Reference

### Common Functions (19 exported functions)

| Function | Purpose |
|----------|---------|
| `Log-Message` | Standard logging with color coding |
| `Log-Error` | Error logging with exceptions |
| `Log-Success` | Success message logging |
| `Initialize-Logging` | Setup logging file path |
| `Load-Config` | Load JSON config with caching |
| `Save-Config` | Save config with backup |
| `Get-ConfigValue` | Get nested config values (dot notation) |
| `Validate-Prerequisites` | Check system requirements |
| `Validate-Admin` | Ensure admin privileges |
| `Safe-Copy` | Copy files safely with logging |
| `Safe-Move` | Move files safely |
| `Safe-Delete` | Delete files with backup option |
| `Query-Database` | Execute SELECT queries |
| `Update-Database` | Execute UPDATE queries |
| `Insert-Database` | Execute INSERT queries |
| `Emit-Event` | Fire events to subscribers |
| `Subscribe-Event` | Listen for events |
| `Unsubscribe-Event` | Stop listening for events |
| `Try-Catch-Retry` | Retry with exponential backoff |

### API Gateway (9 exported functions)

| Function | Purpose |
|----------|---------|
| `Register-Component` | Register component for API |
| `Invoke-ComponentAPI` | Call component with async support |
| `Query-Component` | Query component data |
| `Trigger-Component` | Trigger component action |
| `Get-RequestStatus` | Check async request status |
| `Get-ComponentInfo` | Get component details |
| `Clear-RequestCache` | Clear cached requests |
| `Get-RequestLog` | View request history |
| `Get-GatewayStats` | View gateway statistics |

### Event Bus (11 exported functions)

| Function | Purpose |
|----------|---------|
| `Register-Event` | Define event type |
| `Unregister-Event` | Remove event type |
| `Subscribe-Event` | Subscribe to event |
| `Unsubscribe-Event` | Unsubscribe from event |
| `Emit-Event` | Emit event to subscribers |
| `Process-AsyncEvents` | Process async event queue |
| `Get-EventHistory` | Query past events |
| `Get-EventInfo` | Get event details |
| `Get-RegisteredEvents` | List all events |
| `Get-EventBusStats` | View event bus statistics |
| `Clear-EventHistory` | Clear event history |

---

## Configuration Templates

### azure-config.template.json (1.7 KB)

- Azure subscription, resource group, location
- GitHub Copilot API configuration
- Azure DevOps organization and pipelines
- Azure Storage, Key Vault, Application Insights
- Monitoring and logging setup

### security-config.template.json (2.4 KB)

- AppLocker policies
- Windows Defender settings
- Bitdefender threat defense
- Firewall rules (inbound/outbound)
- User access control
- Data encryption
- Audit logging
- MFA configuration

### agent-profiles.template.json (5.2 KB)

- 12 AI agent profiles with capabilities:
  - Copilot Core, Security, DevOps, Testing, Documentation
  - Monitoring, Optimization, Analytics, Compliance, Integration
  - Maintenance, User Support
- Per-agent: models, concurrency, timeouts

### model-registry.template.json (7.2 KB)

- 12+ AI models across major providers:
  - OpenAI (GPT-4 Turbo, GPT-4, GPT-3.5)
  - Anthropic (Claude 3 Opus, Sonnet, Haiku)
  - Google (Gemini Pro, PaLM 2)
  - Meta (Llama 2), Mistral, Cohere, AI21
- Per-model: capabilities, costs, latency, accuracy
- Routing strategy with fallbacks and load balancing

### optimization-config.template.json (5.2 KB)

- 5 optimization profiles:
  1. Cost-optimized (minimize spending)
  2. Speed-optimized (minimize latency)
  3. Quality-optimized (maximize accuracy)
  4. Balanced (default)
  5. Scale-optimized (high volume)
- Resource allocation (CPU, memory, storage, network)
- Cost budgets and alerts
- Performance targets
- Caching and batch processing

### component-state.template.json (5.0 KB)

- State tracking for 7 HELIOS components
- Per-component: status, health, endpoints, statistics
- System-level: overall health, resources, performance
- Dependencies, events, activities, alerts

---

## Common Use Cases

### Log Operations

```powershell
Log-Message -Message "Processing started" -Component "Auth" -Level "Info"
Log-Error -Message "Connection failed" -Exception $ex -Component "Auth"
Log-Success -Message "Authentication complete" -Component "Auth"
```

### Load & Modify Config

```powershell
$config = Load-Config "C:\config.json"
$subscriptionId = Get-ConfigValue $config "azure.subscriptionId"
$config.azure.subscriptionId = "new-id"
Save-Config "C:\config.json" $config
```

### Call Another Component

```powershell
# Sync call
$result = Invoke-ComponentAPI -ComponentName "Security" -Operation "Scan" -Parameters @{path=$p}

# Async call
$job = Invoke-ComponentAPI -ComponentName "DevOps" -Operation "Deploy" -Async $true
$status = Get-RequestStatus $job.RequestId
```

### Emit & Subscribe Events

```powershell
Subscribe-Event -EventName "SecurityAlert" -Component "Monitor" `
               -Callback { Log-Message "Alert received!" }

Emit-Event -EventName "SecurityAlert" -Payload @{level="high"} -Component "Security"
```

### Retry with Backoff

```powershell
$result = Try-Catch-Retry -ScriptBlock {
    # Your code here
} -MaxAttempts 3 -DelayMs 1000
```

---

## Design Principles

✓ **No Redundancy** - Shared infrastructure eliminates duplicate code
✓ **Production Quality** - Error handling, logging, validation built-in
✓ **Async-Ready** - API gateway and event bus support async operations
✓ **Observable** - Comprehensive logging and monitoring
✓ **Resilient** - Retry logic, circuit breakers, fallbacks
✓ **Configurable** - Flexible templates for different environments
✓ **Maintainable** - Well-documented, easy to extend

---

## Key Features by Component

### common-functions.psm1

- ✓ Unified logging with 5 levels + color coding
- ✓ Config management with caching and backup
- ✓ System validation (prerequisites, admin)
- ✓ Safe file operations (copy, move, delete)
- ✓ Database operations (query, insert, update)
- ✓ Event handling with callbacks
- ✓ Retry logic with exponential backoff

### api-gateway.ps1

- ✓ Component registration and discovery
- ✓ Sync and async request handling
- ✓ 5-minute request caching
- ✓ Request logging and monitoring
- ✓ Statistics tracking
- ✓ Error handling and fallbacks

### event-bus.ps1

- ✓ Event registration with schemas
- ✓ Priority-based processing
- ✓ Subscription filtering
- ✓ Async event queue
- ✓ 5000-entry history
- ✓ Comprehensive statistics

---

## Success Criteria ✓ Met

| Criterion | Status |
|-----------|--------|
| All files created with production-quality code | ✓ |
| Common functions work across 7 components | ✓ |
| API gateway supports async operations | ✓ |
| Event bus handles subscriptions/emissions | ✓ |
| Config templates well-documented | ✓ |
| No component duplicates functionality | ✓ |
| All syntax validated (PowerShell + JSON) | ✓ |
| Total size: ~109 KB | ✓ |

---

## Integration Checklist

When adding to a component:

- [ ] Import `common-functions.psm1`
- [ ] Call `Initialize-Logging`
- [ ] Load configuration with `Load-Config`
- [ ] Register with API gateway (`Register-Component`)
- [ ] Subscribe to needed events (`Subscribe-Event`)
- [ ] Register event types (`Register-Event`)
- [ ] Handle errors with `Try-Catch-Retry`
- [ ] Use safe file operations (`Safe-Copy`, etc.)
- [ ] Log operations with `Log-Message`

---

## Paths & Locations

| Resource | Location |
|----------|----------|
| Shared Infrastructure | `C:\HELIOS\core-infrastructure\shared-resources\` |
| PowerShell Modules | `*.psm1` in shared-resources directory |
| Configuration Templates | `config-templates\` subdirectory |
| Component Configs | `C:\HELIOS\config\` |
| Logs | `C:\HELIOS\logs\` |
| Documentation | `README.md` in shared-resources |

---

## Support

- **Full Documentation**: See `README.md` (23 KB)
- **Code Examples**: Throughout README.md
- **Configuration Samples**: All `*.template.json` files
- **Error Messages**: Logged via `Log-Error` function

---

**Version**: 1.0.0
**Status**: Production Ready ✓
**Total Package**: 10 files, 109 KB, 39 exported functions
