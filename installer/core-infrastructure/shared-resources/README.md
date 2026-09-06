# HELIOS Shared Infrastructure

Centralized infrastructure layer providing shared functionality for all 7 HELIOS components, eliminating redundancy and ensuring consistency across the platform.

## Overview

The shared infrastructure consists of production-grade utilities and configuration templates that enable:

- **Unified Logging & Diagnostics** - Consistent logging across all components
- **Configuration Management** - Centralized config loading, saving, and validation
- **Event-Driven Communication** - Async event bus for component-to-component messaging
- **API Gateway** - Single entry point for cross-component requests with caching and async support
- **Validation & Prerequisites** - Shared validation utilities for system state
- **File & Database Operations** - Safe, logged file and database operations
- **Error Handling** - Retry logic with exponential backoff

## Architecture

```
┌─────────────────────────────────────────────────────┐
│         HELIOS Components (7 total)                  │
├─────────────────────────────────────────────────────┤
│ Auth │ Code │ Security │ DevOps │ Testing │ Monitor │ KB │
├─────────────────────────────────────────────────────┤
│              API Gateway                             │
│  (Routing, Caching, Async, Monitoring)              │
├─────────────────────────────────────────────────────┤
│              Event Bus                               │
│  (Subscriptions, Emissions, History, Filtering)     │
├─────────────────────────────────────────────────────┤
│         Common Functions Module                      │
│  (Logging, Config, Validation, File/DB Ops)         │
├─────────────────────────────────────────────────────┤
│         Shared Configuration Templates               │
│  (Azure, Security, Models, Optimization, State)     │
└─────────────────────────────────────────────────────┘
```

## Components

### 1. common-functions.psm1 (PowerShell Module)

Shared utilities for all HELIOS components.

#### Logging Functions

- `Log-Message` - Log with color-coded levels (Info, Warning, Error, Success, Debug)
- `Log-Error` - Log errors with exception details and stack traces
- `Log-Success` - Log success messages
- `Initialize-Logging` - Set up logging to file

**Example:**

```powershell
Import-Module "C:\HELIOS\core-infrastructure\shared-resources\common-functions.psm1"

Initialize-Logging -LogPath "C:\HELIOS\logs\app.log"
Log-Message -Message "Component started" -Component "Authentication" -Level "Info"
Log-Error -Message "Failed to connect" -Exception $ex -Component "Authentication"
Log-Success -Message "Authentication successful" -Component "Authentication"
```

#### Configuration Management

- `Load-Config` - Load JSON config with caching support
- `Save-Config` - Save config with automatic backup
- `Get-ConfigValue` - Retrieve config values using dot notation

**Example:**

```powershell
$config = Load-Config -ConfigPath "C:\HELIOS\config\azure-config.json" -UseCache $true
$subscriptionId = Get-ConfigValue -Config $config -Path "azure.subscriptionId"

# Modify and save
$config.azure.subscriptionId = "new-id"
Save-Config -ConfigPath "C:\HELIOS\config\azure-config.json" -Config $config -Backup $true
```

#### Validation Functions

- `Validate-Prerequisites` - Check system requirements
- `Validate-Admin` - Ensure administrator privileges

**Example:**

```powershell
$prereqs = Validate-Prerequisites -Requirements @("PowerShell5.1", "DotNet4.7", "Git")
if (-not $prereqs.AllMet) {
    Write-Host "Missing prerequisites:" -ForegroundColor Red
    $prereqs.Results | Where-Object { -not $_.Met }
}

Validate-Admin  # Throws if not admin
```

#### File Operations

- `Safe-Copy` - Copy files with logging and error handling
- `Safe-Move` - Move files with logging
- `Safe-Delete` - Delete files with optional backup

**Example:**

```powershell
Safe-Copy -Source "C:\source\file.txt" -Destination "C:\dest\file.txt" -Force $true
Safe-Move -Source "C:\old\config.json" -Destination "C:\new\config.json"
Safe-Delete -Path "C:\temp\cache.dat" -Backup $true
```

#### Database Operations

- `Query-Database` - Execute SELECT queries
- `Update-Database` - Execute UPDATE statements
- `Insert-Database` - Execute INSERT statements

**Example:**

```powershell
# Query
$results = Query-Database -ConnectionString $connStr `
                          -Query "SELECT * FROM Users WHERE Status=@status" `
                          -Parameters @{status="Active"}

# Insert
$rowsAffected = Insert-Database -ConnectionString $connStr `
                               -Query "INSERT INTO Logs VALUES (@message, @timestamp)" `
                               -Parameters @{message="Test", timestamp=Get-Date}
```

#### Event Handling

- `Emit-Event` - Send event to all subscribers
- `Subscribe-Event` - Register for events
- `Unsubscribe-Event` - Unregister from events

**Example:**

```powershell
# Subscribe
$subId = Subscribe-Event -EventName "DeploymentComplete" `
                         -Callback { param($event) Write-Host "Deployment done: $($event.Payload)" }

# Emit
Emit-Event -EventName "DeploymentComplete" `
          -Payload @{status="success"; duration=120} `
          -Component "DevOps"

# Unsubscribe
Unsubscribe-Event -EventName "DeploymentComplete" -SubscriptionId $subId
```

#### Error Handling

- `Try-Catch-Retry` - Execute with automatic retry and exponential backoff

**Example:**

```powershell
$result = Try-Catch-Retry -ScriptBlock {
    Invoke-RestMethod -Uri "https://api.example.com/data"
} -MaxAttempts 3 -DelayMs 1000 -BackoffMultiplier 2.0
```

---

### 2. api-gateway.ps1 (API Gateway)

Unified entry point for cross-component communication.

#### Core Functions

- `Register-Component` - Register a component for API calls
- `Invoke-ComponentAPI` - Call component functions with async support
- `Query-Component` - Query a component
- `Trigger-Component` - Trigger an action
- `Get-RequestStatus` - Check async request status

**Example:**

```powershell
. "C:\HELIOS\core-infrastructure\shared-resources\api-gateway.ps1"

# Register component
Register-Component -ComponentName "CodeAnalysis" `
                  -Handler {
                      param($Operation, $Parameters)
                      if ($Operation -eq "Analyze") {
                          return @{result="analysis data"}
                      }
                  } `
                  -Capabilities @("analyze", "suggest")

# Invoke synchronously
$result = Invoke-ComponentAPI -ComponentName "CodeAnalysis" `
                             -Operation "Analyze" `
                             -Parameters @{code=$sourceCode}

# Invoke asynchronously
$asyncResult = Invoke-ComponentAPI -ComponentName "CodeAnalysis" `
                                  -Operation "Analyze" `
                                  -Parameters @{code=$sourceCode} `
                                  -Async $true

# Check status
$status = Get-RequestStatus -RequestId $asyncResult.RequestId
while ($status.Status -ne "COMPLETED") {
    Start-Sleep -Seconds 2
    $status = Get-RequestStatus -RequestId $asyncResult.RequestId
}

# Get component info
$info = Get-ComponentInfo -ComponentName "CodeAnalysis"
Write-Host "Capabilities: $($info.Capabilities -join ', ')"
```

#### Features

- **Request Caching** - Avoid duplicate work with built-in caching (5-minute TTL)
- **Async Operations** - Fire-and-forget or wait-for-completion
- **Request Logging** - Track all requests for monitoring
- **Component Discovery** - List registered components and their capabilities
- **Statistics** - Monitor request counts, error rates, etc.

---

### 3. event-bus.ps1 (Event Bus)

Event-driven communication layer for asynchronous component coordination.

#### Core Functions

- `Register-Event` - Define an event type
- `Subscribe-Event` - Listen for events
- `Emit-Event` - Trigger an event
- `Process-AsyncEvents` - Process queued async events
- `Get-EventHistory` - Query past events

**Example:**

```powershell
. "C:\HELIOS\core-infrastructure\shared-resources\event-bus.ps1"

# Register event types
Register-Event -EventName "CodeAnalysisComplete" `
               -Description "Fired when code analysis completes" `
               -Priority "HIGH" `
               -Schema @{
                   file=[string]
                   issues=[int]
                   duration=[int]
               }

# Subscribe to event
$subId = Subscribe-Event -EventName "CodeAnalysisComplete" `
                        -Component "Security" `
                        -Callback {
                            param($event)
                            Log-Message "Analysis complete: $($event.Payload.file)"
                            if ($event.Payload.issues -gt 0) {
                                Trigger-Component -ComponentName "Security" `
                                                 -Action "ReviewIssues" `
                                                 -Parameters $event.Payload
                            }
                        } `
                        -Filter @{severity="high"} `
                        -Priority 1

# Emit event
Emit-Event -EventName "CodeAnalysisComplete" `
          -Payload @{
              file="Main.cs"
              issues=3
              duration=245
              severity="high"
          } `
          -Component "CodeAnalysis" `
          -Priority "HIGH" `
          -Async $false

# Get event info
$eventInfo = Get-EventInfo -EventName "CodeAnalysisComplete"
Write-Host "Subscribers: $($eventInfo.SubscriberCount)"

# Get history
$history = Get-EventHistory -EventName "CodeAnalysisComplete" -Hours 1
Write-Host "Events in last hour: $($history.Count)"
```

#### Features

- **Event Registration** - Define event types with schema
- **Filtering** - Subscribe to events matching specific criteria
- **Prioritization** - Execute high-priority subscriptions first
- **Async Processing** - Queue events for background processing
- **History Tracking** - Maintain event history for auditing
- **Statistics** - Monitor event emissions and subscriptions

---

## Configuration Templates

### azure-config.template.json

Azure cloud platform configuration.

**Key Sections:**

- `azure` - Subscription, resource group, location
- `copilot` - GitHub Copilot API integration
- `devops` - Azure DevOps organization and pipelines
- `storage` - Azure Storage configuration
- `keyVault` - Secrets management
- `appInsights` - Application monitoring
- `monitoring` - Log Analytics setup

**Usage:**

```powershell
# Copy template and customize
Copy-Item "azure-config.template.json" "azure-config.json"

# Load and use
$azureConfig = Load-Config -ConfigPath "azure-config.json"
$subscriptionId = $azureConfig.azure.subscriptionId

# Set Azure context
az account set --subscription $subscriptionId
```

### security-config.template.json

Security controls and policies configuration.

**Key Sections:**

- `appLocker` - Application whitelisting/blacklisting
- `windowsDefender` - Real-time protection settings
- `bitdefender` - Advanced threat defense (optional)
- `firewall` - Inbound/outbound rules
- `userAccessControl` - UAC settings
- `dataProtection` - Encryption and TLS config
- `auditLogging` - Security event logging
- `mfa` - Multi-factor authentication settings

### agent-profiles.template.json

Definitions for 12 AI agents used by HELIOS components.

**Agents Include:**

1. **Copilot Core** - Code analysis and suggestions
2. **Security Agent** - Vulnerability scanning
3. **DevOps Agent** - Pipeline orchestration
4. **Testing Agent** - Test generation
5. **Documentation Agent** - Doc generation
6. **Monitoring Agent** - Health checks
7. **Optimization Agent** - Performance tuning
8. **Analytics Agent** - Data analysis
9. **Compliance Agent** - Compliance checking
10. **Integration Agent** - API integration
11. **Maintenance Agent** - System maintenance
12. **User Support Agent** - User support

Each agent defines:

- Capabilities
- Supported AI models
- Concurrency limits
- Timeout values

### model-registry.template.json

Registry of 35+ AI models with routing rules.

**Models Include:**

- OpenAI: GPT-4 Turbo, GPT-4, GPT-3.5 Turbo
- Anthropic: Claude 3 Opus, Sonnet, Haiku
- Google: Gemini Pro, PaLM 2
- Meta: Llama 2 70B
- Mistral AI: Mistral 7B
- Cohere, AI21 Labs

**Per-Model Configuration:**

- Provider and version
- Capabilities
- Cost per input/output token
- Latency characteristics
- Accuracy metrics
- Routing rules and use cases

**Routing Strategy:**

- Weighted round-robin load balancing
- Fallback order for failures
- Cost optimization
- Circuit breaker on errors

### optimization-config.template.json

Optimization profiles and resource allocation.

**Profiles:**

1. **Cost-Optimized** - Minimize spending
2. **Speed-Optimized** - Minimize latency
3. **Quality-Optimized** - Maximize accuracy
4. **Balanced** - Default profile
5. **Scale-Optimized** - High-volume processing

**Settings Include:**

- Resource allocation (CPU, memory, storage, network)
- Cost budgets and thresholds
- Performance targets (latency, throughput, availability)
- Horizontal/vertical scaling policies
- Caching strategies
- Batch processing configuration

### component-state.template.json

Tracks state and health of all 7 HELIOS components.

**Per-Component Tracking:**

- Status (initializing, running, degraded, offline)
- Health metrics
- Endpoint status
- Request statistics
- Response times

**System-Level Tracking:**

- Overall health score
- Resource utilization
- Performance metrics
- Dependency connections
- Active events
- Recent activities
- Active alerts

## Usage Patterns

### Pattern 1: Component Setup

```powershell
# 1. Initialize logging
Initialize-Logging -LogPath "C:\HELIOS\logs\component.log"
Log-Message "Component starting..." -Component "MyComponent"

# 2. Load configuration
$config = Load-Config -ConfigPath "C:\HELIOS\config\azure-config.json"

# 3. Validate prerequisites
$prereqs = Validate-Prerequisites -Requirements @("PowerShell5.1", "AzureCLI")
if (-not $prereqs.AllMet) { throw "Prerequisites not met" }

# 4. Register events
Register-Event -EventName "MyEvent" -Priority "HIGH"

# 5. Subscribe to events
Subscribe-Event -EventName "OtherComponentEvent" -Component "MyComponent" `
               -Callback { param($e) Log-Message "Got event: $($e.EventName)" }

# 6. Register with API gateway
Register-Component -ComponentName "MyComponent" `
                  -Handler $handler `
                  -Capabilities @("capability1", "capability2")

Log-Success "Component initialized successfully"
```

### Pattern 2: Component-to-Component Communication

```powershell
# Synchronous: Wait for result
$result = Invoke-ComponentAPI -ComponentName "CodeAnalysis" `
                             -Operation "Analyze" `
                             -Parameters @{file=$path}
                             -UseCache $true

# Asynchronous: Fire and forget
$asyncJob = Invoke-ComponentAPI -ComponentName "DevOps" `
                               -Operation "Deploy" `
                               -Parameters @{version=$version} `
                               -Async $true

# Check status later
$status = Get-RequestStatus -RequestId $asyncJob.RequestId
if ($status.Status -eq "COMPLETED") {
    $result = $status.Result
}
```

### Pattern 3: Event-Driven Processing

```powershell
# Emit event when work is done
Emit-Event -EventName "AnalysisComplete" `
          -Payload @{
              file=$path
              issues=$count
              severity="high"
          } `
          -Component "CodeAnalysis" `
          -Priority "HIGH"

# Other components react automatically
# (via their subscriptions registered earlier)
```

### Pattern 4: Error Handling with Retry

```powershell
try {
    $result = Try-Catch-Retry -ScriptBlock {
        # Your operation here
        Invoke-RestMethod -Uri $apiUrl -Method Post -Body $payload
    } -MaxAttempts 3 -DelayMs 1000 -BackoffMultiplier 2.0
} catch {
    Log-Error "Operation failed after retries" -Exception $_
    throw
}
```

## Adding New Shared Functionality

### To Add a New Function to common-functions.psm1:

1. **Write the function** with proper error handling
2. **Add documentation** with .SYNOPSIS and parameters
3. **Use existing logging functions** (Log-Message, Log-Error)
4. **Export the function** by adding it to Export-ModuleMember

**Example:**

```powershell
<#
.SYNOPSIS
    My new shared function

.PARAMETER Param1
    Description of param1
#>
function My-Function {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Param1
    )
    
    try {
        Log-Message -Message "Starting operation..." -Level "Debug"
        # Implementation here
        Log-Success -Message "Operation completed"
        return $result
    }
    catch {
        Log-Error -Message "Operation failed" -Exception $_
        throw
    }
}

# Add to Export-ModuleMember list
Export-ModuleMember -Function @('My-Function', 'OtherFunction')
```

### To Add a New Event Type:

```powershell
. "C:\HELIOS\core-infrastructure\shared-resources\event-bus.ps1"

Register-Event -EventName "MyNewEvent" `
               -Description "Fired when X happens" `
               -Priority "HIGH" `
               -Schema @{
                   status=[string]
                   duration=[int]
               }
```

### To Add a New Configuration Template:

1. Create JSON file in `config-templates/`
2. Use meaningful property names
3. Include version, defaults, and descriptions
4. Document all properties in README
5. Add example usage

## Best Practices

### Logging

- Use appropriate log levels (Debug for detailed, Info for standard, Warning for issues, Error for failures)
- Include component name for easy filtering
- Log at start and end of operations
- Include context/details in error messages

### Configuration

- Always load config at component startup
- Use dot notation for nested values
- Validate required config before proceeding
- Create backups before modifying

### Events

- Use consistent event naming (PascalCase, descriptive)
- Define schemas to document event payloads
- Set appropriate priority levels
- Filter subscriptions to avoid unnecessary processing

### API Calls

- Use component names consistently
- Leverage caching for repeated queries
- Consider async for long-running operations
- Monitor request statistics for performance

### Error Handling

- Always use Try-Catch-Retry for external API calls
- Provide specific error messages
- Clean up resources in finally blocks
- Log stack traces for debugging

## Performance Considerations

- **Caching**: API gateway caches results for 5 minutes by default
- **Async**: Use async for long operations (>5 seconds)
- **Batch Size**: Process events in batches of 10 by default
- **Log Rotation**: Keep request logs to 1000 entries
- **Memory**: Event history limited to 5000 entries

## Troubleshooting

### Logging not working

- Check log file path is writable
- Verify logging initialized: `Initialize-Logging -LogPath "..."`

### Configuration not loading

- Verify file exists and is valid JSON
- Check path is correct and readable
- Use `-UseCache $false` to reload fresh

### Events not firing

- Confirm event is registered
- Check subscription filter matches
- Verify callback script block is valid

### API Gateway timeouts

- Check component handler returns quickly
- Use async for long operations
- Increase timeout if needed

## Architecture Documentation

### Component Interactions

```
Component A → API Gateway → Component B
              ↓
           Cache/Logging

Event emitted → Event Bus → All Subscribers
                ↓
           History/Filtering
```

### Data Flow

```
Configuration File → Load-Config → Cache → Component
                                      ↓
                                   Save-Config
```

### Error Recovery

```
API Call → Try-Catch-Retry → Exponential Backoff → Circuit Breaker
            ↓ Retry Attempt
         Failure Logged
```

## Security Notes

- All database operations use parameterized queries to prevent SQL injection
- Sensitive config (secrets, tokens) loaded from environment variables
- Firewall rules restrict outbound connections
- All file operations logged and backed up
- Admin validation ensures proper permissions

## Support & Maintenance

### File Locations

- **Shared Infrastructure**: `C:\HELIOS\core-infrastructure\shared-resources\`
- **Config Templates**: `C:\HELIOS\core-infrastructure\shared-resources\config-templates\`
- **Logs**: `C:\HELIOS\logs\`
- **Config Files**: `C:\HELIOS\config\`

### Update Process

1. Update relevant .psm1 or .ps1 file
2. Test changes with dependent components
3. Update this README if behavior changes
4. Document breaking changes
5. Notify component teams of updates

## Version History

- **1.0.0** (Current) - Initial release
  - Common functions module with 18 functions
  - API Gateway with async support and caching
  - Event Bus with filtering and history
  - 6 comprehensive configuration templates

---

**Last Updated**: 2024
**Maintained By**: HELIOS Infrastructure Team
