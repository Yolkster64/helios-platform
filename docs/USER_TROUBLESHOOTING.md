# HELIOS Platform - Comprehensive Troubleshooting Guide

**Common issues, diagnostics, and solutions for every situation**

---

## 📋 Table of Contents

1. [Quick Reference](#quick-reference)
2. [Installation Issues](#installation-issues)
3. [Deployment Problems](#deployment-problems)
4. [Performance Issues](#performance-issues)
5. [Database Problems](#database-problems)
6. [Network & Connectivity](#network--connectivity)
7. [AI Service Issues](#ai-service-issues)
8. [Security & Access](#security--access)
9. [Emergency Procedures](#emergency-procedures)

---

## Quick Reference

### Most Common Issues (with solutions)

```
Issue                           Cause                   Solution               Time
═══════════════════════════════════════════════════════════════════════════════
Application Won't Start         Port already in use     Kill process on port   2 min
Service Timeout                 Database unreachable    Check DB connection    5 min
High Memory Usage               Memory leak              Restart service        3 min
Deployment Fails                Invalid configuration   Validate config file   10 min
Can't Connect to Database       Network issue           Check firewall rules   15 min
Slow Response Times             Missing database index  Add index              20 min
Authentication Failed           Token expired           Refresh credentials    3 min
Alerts Not Sending              SMTP misconfigured      Fix email settings     5 min
```

### Emergency Commands

**If things are really broken**:

```powershell
# Quick health check
$status = Get-HELIOSStatus
if ($status.IsHealthy -eq $false) {
    Write-Host "System is unhealthy!"
    Show-HealthDetails
}

# Emergency restart
Restart-HELIOSServices -Force

# Restore from backup
Restore-HELIOSBackup -Date (Get-Date).AddHours(-1)

# Contact support
Get-EmergencyContact | Send-Alert -Severity Critical
```

---

## Installation Issues

### Issue: Installation Hangs During Database Setup

**Symptoms**:

```
Install Progress: 60% (Database initialization)
- Creating tables...
- Initializing data...
[SPINNING INDEFINITELY]
```

**Diagnosis** (2 minutes):

```powershell
# Check if database is responding
$db = Get-SQLDatabase -Name "HELIOS"
if ($db.Status -ne "Online") {
    Write-Error "Database is not online!"
}

# Check for long-running queries
Get-SQLLongRunningQueries

# Check disk space (databases need room!)
Get-Volume -DriveLetter C | Select-Object SizeRemaining
```

**Solution**:

```
Option 1: Cancel & Retry (if hung <5 minutes)
├─ Press Ctrl+C to cancel installation
├─ Wait 30 seconds
├─ Run installer again
└─ Usually succeeds on retry (10% of cases)

Option 2: Pre-allocate Database Storage (if disk full)
├─ Check available disk space
├─ If <50 GB free: Free space or add disk
├─ Retry installation
└─ Time: 10-20 minutes

Option 3: Manual Database Initialization (if truly stuck)
├─ Connect to SQL Server manually
├─ Run initialization script: scripts/initialize-db.sql
├─ Resume installer
└─ Time: 20-30 minutes

Option 4: Full Reset (nuclear option)
├─ Uninstall completely
├─ Delete database files
├─ Clear installation folder
├─ Restart installation from USB
└─ Time: 45 minutes
```

---

## Deployment Problems

### Issue: "Configuration validation failed"

**Error Message**:

```
Error: Deployment configuration validation failed
├─ Issue: ApplicationName is missing
├─ Required Field: applicationName (string)
└─ Example: "payment-api"
```

**Solution**:

```
Step 1: Check Configuration File
┌────────────────────────────────────────┐
│ deployment-config.json                 │
├────────────────────────────────────────┤
│ {                                      │
│   "applicationName": "payment-api",    │
│   "environment": "production",         │
│   "replicas": 3,                       │
│   "resources": {                       │
│     "cpu": "2 cores",                  │
│     "memory": "4 GB"                   │
│   }                                    │
│ }                                      │
└────────────────────────────────────────┘

Step 2: Validate JSON Syntax
$ jsonlint deployment-config.json
✓ Valid JSON

Step 3: Verify Required Fields
Required Fields:
├─ ✓ applicationName: "payment-api"
├─ ✓ environment: "production"
├─ ✓ replicas: 3
├─ ✓ resources: {...}
└─ ✓ All present

Step 4: Retry Deployment
$ Deploy-HELIOSApplication -ConfigFile deployment-config.json
✓ Deployment started
```

### Issue: "Insufficient resources" Error

**Symptom**:

```
Error: Cannot create 5 replicas
├─ Reason: Insufficient memory available
├─ Requested: 20 GB
├─ Available: 8 GB
└─ Action: Need to free up or scale down
```

**Solutions**:

```
Option 1: Scale Down (Quick)
├─ Reduce replicas from 5 to 2
├─ Free up: 12 GB of memory
├─ Time: 5 minutes
└─ Trade-off: Lower capacity

Option 2: Free Up Resources (Medium)
├─ Stop non-essential services
├─ Delete old backups
├─ Compress databases
├─ Free up: 10-15 GB
├─ Time: 20 minutes
└─ Risk: May affect other services

Option 3: Add More Resources (Best)
├─ Add new virtual machine
├─ Add 32 GB memory
├─ Time: 15-20 minutes
└─ Cost: $0.50/hour

Option 4: Manual Allocation (Advanced)
├─ Reduce resource allocation per replica
├─ From: 4 GB per replica
├─ To: 2 GB per replica
├─ Trade-off: May affect performance
└─ Time: 10 minutes
```

### Issue: Deployment Timeout

**Symptom**:

```
Deployment: Application deployment timeout
├─ Time limit: 30 minutes
├─ Time elapsed: 30 minutes
├─ Phase: Service deployment (Phase 3)
└─ Status: Stuck, aborting
```

**Investigation** (5 minutes):

```
Check Docker Build:
├─ Is Docker building successfully?
├─ Building image (150 MB): 5 minutes?
├─ If slow: Check Docker disk space
└─ If error: Check Dockerfile syntax

Check Networking:
├─ Can reach Docker registry?
├─ Can reach deployment target?
├─ Network latency: < 50ms?
└─ Firewall blocking ports?

Check Services:
├─ Service starting up successfully?
├─ Health check passing?
├─ Dependencies ready?
└─ Any errors in logs?
```

**Solution**:

```
Step 1: Increase Timeout
├─ Default timeout: 30 minutes
├─ Increase to: 60 minutes
└─ Command: Deploy-HELIOSApplication ... -Timeout 3600

Step 2: Check Logs
├─ Get deployment logs: Get-DeploymentLogs -DeploymentId abc123
├─ Look for errors or warnings
├─ Identify bottleneck

Step 3: Fix Root Cause
If Docker build slow:
├─ Optimize Dockerfile
├─ Reduce image size
├─ Use layer caching

If services won't start:
├─ Check service logs
├─ Verify dependencies
├─ Test health checks

If network slow:
├─ Check bandwidth
├─ Check latency
├─ Consider faster connection

Step 4: Retry
├─ Deploy-HELIOSApplication -ConfigFile ... -Retry
└─ Should complete faster second time
```

---

## Performance Issues

### Issue: "Response Times Are Degraded"

**Symptom**:

```
Application Performance:
├─ Normal Response: 120 ms (P95)
├─ Current Response: 500 ms (P95)
├─ Degradation: 4.2x slower
├─ Started: 14:30 UTC
└─ Duration: 45 minutes
```

**Diagnosis** (5 minutes):

```
Check 1: CPU Usage
├─ Normal: 30-40%
├─ Current: 85%
├─ Verdict: CPU-bound bottleneck

Check 2: Memory Usage
├─ Normal: 45%
├─ Current: 45%
├─ Verdict: Not memory issue

Check 3: Disk I/O
├─ Normal: 10 MB/s
├─ Current: 250 MB/s
├─ Verdict: Disk I/O spike

Check 4: Network
├─ Normal: 100 Mbps
├─ Current: 105 Mbps
├─ Verdict: Normal network

Check 5: Database
├─ Query time: Normal
├─ Connection pool: 45/100 (normal)
├─ Lock wait time: 0 ms
├─ Verdict: Database is fine
```

**Root Cause**: High disk I/O

```
Why is disk I/O high?
├─ Option 1: Database logs growing fast
├─ Option 2: Large file operations
├─ Option 3: Disk fragmentation
├─ Option 4: Backup running in background
└─ Most likely: Backup running

Verify: Get-Process | Where-Object {$_.Name -like "backup*"}
Result: Backup process running (started 14:30)
```

**Solution**:

```
Option 1: Stop Backup (Immediate)
├─ Command: Stop-BackupProcess
├─ Result: Disk I/O drops to 20 MB/s
├─ Response time: Back to 120 ms (P95)
├─ Downside: Backup not completed
└─ Time: 2 minutes

Option 2: Reschedule Backup (Better)
├─ Move backup from 14:30 to 2 AM (overnight)
├─ Let current backup finish
├─ Response time normalizes in 30 minutes
└─ Time: 5 minutes

Option 3: Parallel Backup (Best)
├─ Use separate backup device
├─ Run backup to different disk
├─ No impact on application
├─ Backup completes normally
└─ Time: 10 minutes

Recommended: Option 2 or 3
└─ This issue won't recur
```

### Issue: "Memory Leak - Memory Usage Growing"

**Symptom**:

```
Memory Over Time (24 hours):

│ 8 GB ├─────────────────────────╮
│ 7 GB │                        ╭╯
│ 6 GB │                    ╭───╯
│ 5 GB │                ╭───╯
│ 4 GB │            ╭───╯
│ 3 GB │        ╭───╯
│ 2 GB │    ╭───╯
│ 1 GB ├────╯
│ 0 GB └─────────────────────────
    0h  6h  12h  18h  24h

Pattern: Steady increase (not normal)
Restart needed: Every 12 hours
Status: CRITICAL
```

**Diagnosis**:

```
Step 1: Identify Process
ps aux | grep dotnet | grep payment-api
Result: dotnet process using 8 GB (expected: 4 GB)

Step 2: Collect Memory Dump
dotnet dump collect -p 1234 -o memory.dump

Step 3: Analyze Dump
dotnet dump analyze memory.dump
> dumpheap -stat
  
Result:
  Size       Count  Class
  2,000 MB   100k   System.String
  1,500 MB   50k    YourApp.CacheEntry
  ...

Finding: Cache growing without bounds!
```

**Root Cause**: Application-level memory leak in caching

```
Culprit Code:
public class CacheManager
{
    private static Dictionary<string, object> _cache 
        = new Dictionary<string, object>(); // Never cleared!
    
    public static void AddToCache(string key, object value)
    {
        _cache[key] = value; // Objects accumulate forever
    }
}
```

**Solution**:

```
Fix 1: Add Cache Expiration (Recommended)
public class CacheManager
{
    private static Dictionary<string, (object Value, DateTime Expiry)> _cache 
        = new Dictionary<string, (object, DateTime)>();
    
    public static void AddToCache(string key, object value, 
        TimeSpan expiry = null)
    {
        var expiryTime = DateTime.UtcNow.Add(expiry ?? TimeSpan.FromMinutes(30));
        _cache[key] = (value, expiryTime);
    }
    
    public static object GetFromCache(string key)
    {
        if (!_cache.TryGetValue(key, out var item))
            return null;
        
        if (DateTime.UtcNow > item.Expiry)
        {
            _cache.Remove(key);
            return null;
        }
        
        return item.Value;
    }
    
    // Cleanup task
    public static void CleanupExpiredEntries()
    {
        var expired = _cache.Where(x => DateTime.UtcNow > x.Value.Expiry)
            .Select(x => x.Key)
            .ToList();
        
        foreach (var key in expired)
            _cache.Remove(key);
    }
}

Fix 2: Use Distributed Cache (Better)
├─ Replace in-process cache with Redis
├─ Redis handles eviction automatically
├─ More scalable (shared across instances)
└─ Implement: See Caching Strategy in Advanced Guide

Verification After Fix:
├─ Deploy updated code
├─ Monitor memory for 24 hours
├─ Expected: Stable at 4 GB
├─ Restart cycle: No longer needed
└─ Status: RESOLVED
```

---

## Database Problems

### Issue: "Database Connection Timeout"

**Symptom**:

```
Error: Timeout expired while waiting for connection
├─ Timeout: 30 seconds
├─ Database: payment-db
├─ User: app_user
└─ Status: Cannot connect
```

**Diagnosis** (3 minutes):

```
Check 1: Database Is Running
$ az sql server list --query "[].{name:name,status:state}"
Result: ✓ Database exists and is online

Check 2: Network Connectivity
$ Test-NetConnection -ComputerName payment-db.database.windows.net -Port 1433
Result: ✓ Can reach database server (TcpTestSucceeded: true)

Check 3: Connection Pool
$ Get-SQLConnectionPoolStatus -Name payment-db
Result: 100/100 connections (FULL!)

Finding: Connection pool is exhausted!
```

**Solution**:

```
Option 1: Increase Connection Pool Size (Quick)
├─ Current: Max pool size 100
├─ New: Max pool size 200
├─ Application restart: Required
├─ Time: 5 minutes

Option 2: Find Connection Leaks (Better)
├─ Which processes are holding connections?
├─ Active queries: Using connections?
├─ Check application logs
├─ Look for exceptions (connections not closed)

Option 3: Restart Service (Immediate Workaround)
├─ Stops current connections
├─ Resets connection pool
├─ Brief downtime: 2-3 seconds
├─ Time: 2 minutes
├─ Trade-off: Temporary fix

Recommended: Option 2
├─ Find root cause
├─ Fix connection leak in code
├─ Add connection.Dispose() in finally blocks
└─ Deploy fix

Quick Fix for Now:
$ Restart-HELIOSService -Name payment-api
✓ Service restarted
✓ Connections reset
✓ Service responding again
```

### Issue: "Database Corruption Detected"

**Symptom**:

```
Database check found errors:
├─ Error: Inconsistent index structure
├─ Table: Payments
├─ Severity: High
└─ Action: Database not safe
```

**Response** (Immediate):

```
Step 1: Alert Team (0 minutes)
├─ Message: "Database corruption detected, investigating"
├─ Channel: Slack #incidents
├─ Status: Investigating

Step 2: Check Backup Integrity (1 minute)
├─ Last backup: 2 AM today (12 hours old)
├─ Backup status: Valid ✓
├─ Can restore: Yes
└─ Data loss: 12 hours

Step 3: Decision (2 minutes)
├─ Option A: Try to repair in-place
│  ├─ Risk: Might fail, data loss unpredictable
│  ├─ Time: 30-60 minutes
│  ├─ Success rate: 40%
│  └─ Decision: Risky
│
├─ Option B: Restore from backup (RECOMMENDED)
│  ├─ Risk: 12 hours of data loss (acceptable)
│  ├─ Time: 15 minutes
│  ├─ Success rate: 99.9%
│  └─ Decision: Safe
│
└─ Option C: Restore from Azure backup
   ├─ Risk: Earlier data (24 hours old)
   ├─ Time: 30 minutes
   ├─ Success rate: 99.9%
   └─ Decision: Bigger data loss

Step 4: Notify Users (3 minutes)
Status Page Update:
"We detected database issues and are restoring from backup.
Brief downtime expected (15 minutes). We apologize for the disruption."

Step 5: Execute Restore (15 minutes)
├─ Initiate restore from backup
├─ Verify data integrity
├─ Bring application online
└─ Verify all systems working

Step 6: Post-Incident (30 minutes later)
├─ Analyze root cause (what caused corruption?)
├─ Implement preventative measures
├─ Review backup strategy
├─ Update runbooks
└─ Post-mortem meeting scheduled

Total Time: 45 minutes (from detection to recovery)
Data Loss: 12 hours (unavoidable)
Customer Impact: 30-minute service interruption
```

---

## Network & Connectivity

### Issue: "Cannot Reach Application Endpoint"

**Symptom**:

```
curl: (7) Failed to connect to payment-api.company.local port 443: Connection refused
```

**Diagnosis** (3 minutes):

```
Check 1: DNS Resolution
$ nslookup payment-api.company.local
Result: 10.1.2.5 (resolves correctly)

Check 2: Network Connectivity
$ ping 10.1.2.5
Result: ✓ Responding (ICMP)

Check 3: Port Connectivity
$ Test-NetConnection -ComputerName 10.1.2.5 -Port 443
Result: TcpTestSucceeded: False (port 443 closed)

Finding: Port 443 is not listening
```

**Investigation**:

```
Is application running?
$ Get-Process -Name dotnet
Result: ✓ Running

Is application listening on port 443?
$ Get-NetTCPConnection -State Listen -LocalPort 443
Result: ✗ No process listening on port 443!

Why not?
$ Get-EventLog -LogName Application -Newest 10 | Where {$_.Source -eq "payment-api"}
Result:
  - Failed to bind to port 443: Permission denied
  - Application running as non-admin user
  - Can't access privileged port 443
```

**Solution**:

```
Option 1: Use Unprivileged Port (Quick)
├─ Change application to port 8443
├─ Configure firewall to forward 443 → 8443
├─ Restart application
└─ Time: 5 minutes

Option 2: Run as Administrator (Risky)
├─ Run application with elevated privileges
├─ Can now bind to port 443
├─ Security risk: More permissions = more exposure
├─ Time: 2 minutes
└─ NOT RECOMMENDED for production

Option 3: Use Reverse Proxy (Recommended)
├─ Keep application on port 8443
├─ Setup nginx/IIS reverse proxy on port 443
├─ Proxy forwards traffic: 443 → 8443
├─ Better security (proxy isolation)
├─ Time: 15 minutes
└─ RECOMMENDED

Implementation:
# nginx reverse proxy config
server {
    listen 443 ssl;
    ssl_certificate /etc/ssl/certs/server.crt;
    ssl_certificate_key /etc/ssl/private/server.key;
    
    location / {
        proxy_pass http://127.0.0.1:8443;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}

Verification:
$ curl https://payment-api.company.local/health
✓ 200 OK
✓ Service responding
```

### Issue: "Firewall Blocking Traffic"

**Symptom**:

```
Application deployed but unreachable from outside network
├─ Internal access: Works (can reach from same subnet)
├─ External access: Fails (cannot reach from internet)
└─ Cause: Firewall rule missing
```

**Investigation**:

```
Check 1: Is firewall enabled?
$ Get-NetFirewallProfile
Result: Domain: Enabled, Private: Enabled, Public: Enabled

Check 2: What rules exist?
$ Get-NetFirewallRule | Where {$_.DisplayName -like "payment*"} | 
    Select DisplayName,Direction,Enabled,Action

Result: (empty - no rules found)

Finding: No firewall rules for payment API
```

**Solution**:

```
Add Inbound Firewall Rule:

PowerShell:
New-NetFirewallRule `
  -DisplayName "HELIOS Payment API HTTPS" `
  -Direction Inbound `
  -Action Allow `
  -Protocol TCP `
  -LocalPort 443 `
  -RemoteAddress Any `
  -Enabled True

Azure Network Security Group:
az network nsg rule create \
  --resource-group helios-prod \
  --nsg-name payment-api-nsg \
  --name AllowHTTPS \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --destination-port-ranges 443 \
  --source-address-prefixes '*'

Verification:
$ curl https://payment-api.company.local/health
✓ 200 OK
✓ Firewall rule working
```

---

## AI Service Issues

### Issue: "AI Service Timeout"

**Symptom**:

```
Error: AI service call timeout
├─ Service: OpenAI
├─ Timeout: 30 seconds
├─ Time taken: 35 seconds
└─ Impact: Request failed
```

**Solution**:

```
Option 1: Increase Timeout (Quick)
├─ Current timeout: 30 seconds
├─ New timeout: 60 seconds
├─ Code change: One line
├─ Time: 5 minutes

Code Example:
var timeout = TimeSpan.FromSeconds(60);
var response = await _aiRouter.CallServiceWithTimeout("openai", 
    input, timeout);

Option 2: Use Fallback Service (Recommended)
├─ Primary: OpenAI (might be slow)
├─ Fallback: Azure Cognitive Services (faster)
├─ Logic: Try primary, if timeout use fallback
├─ Time: 15 minutes

Code Example:
try
{
    var response = await _openAiService.PredictAsync(
        input, 
        timeout: TimeSpan.FromSeconds(30)
    );
    return response;
}
catch (TimeoutException)
{
    // Fallback to faster service
    return await _azureCognitiveService.PredictAsync(input);
}

Option 3: Investigate OpenAI Service
├─ Is OpenAI service up? (check status page)
├─ Is OpenAI experiencing issues?
├─ Is our API key valid?
├─ Is rate limit exceeded?
└─ Time: 5-10 minutes

Status Check:
$ Get-AIServiceStatus -Provider openai
Result:
  Status: ✓ Up and Running
  Latency: 8 seconds (slow)
  Rate Limit: 90/100 used (high)

Verdict: Rate limit approaching, slow latency
```

---

## Security & Access

### Issue: "Access Denied - Authentication Failed"

**Symptom**:

```
Error: 401 Unauthorized
├─ Request: GET /api/payments
├─ Authentication: Bearer token sent
├─ Response: Unauthorized
└─ Likely cause: Invalid or expired token
```

**Diagnosis** (2 minutes):

```
Check 1: Token Format
├─ Is token in correct format? ✓
├─ Bearer prefix present? ✓
└─ Token is not empty? ✓

Check 2: Token Expiry
$ jwt.decode(token)
Result:
  exp: 1702500000 (expires April 17 2024, 3:20 PM)
  iat: 1702413600 (issued April 16 2024, 3:20 PM)
  
Current time: April 17 2024, 5:00 PM
Finding: Token EXPIRED 1 hour 40 minutes ago!
```

**Solution**:

```
Refresh Token:
$ curl -X POST https://auth-service.company.local/token/refresh \
  -H "Authorization: Bearer $EXPIRED_TOKEN" \
  -d '{}'

Result:
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR...",
  "expires_in": 3600,
  "token_type": "Bearer"
}

Use New Token:
$ curl -H "Authorization: Bearer $NEW_TOKEN" \
  https://payment-api.company.local/api/payments

Result: ✓ 200 OK
```

### Issue: "Insufficient Permissions"

**Symptom**:

```
Error: 403 Forbidden
├─ Request: DELETE /api/applications/payment-api
├─ User: sarah@company.com (Developer)
├─ Required Role: Administrator
└─ User Role: Developer
```

**Solution**:

```
Option 1: Request Elevated Access (Proper Way)
├─ Submit access request to admin
├─ Justify why access needed
├─ Wait for approval
└─ Time: 24-48 hours

Option 2: Ask Admin to Perform Action (Immediate)
├─ Contact administrator
├─ Ask them to delete the application
├─ Requires trust/communication
└─ Time: 5 minutes

Option 3: Use Delegated Access (Temporary)
├─ Ask admin to grant temporary admin role
├─ Set expiration: 1 hour
├─ Perform action
├─ Role automatically revoked
└─ Time: 2 minutes

Recommended: Option 1 (security best practice)
└─ Proper audit trail
```

---

## Emergency Procedures

### Nuclear Option: Full System Reset

**Use only when everything is broken**:

```
Warning: ⚠ This will delete everything and start fresh!
├─ All data: GONE
├─ All configurations: GONE
├─ All applications: GONE
├─ Backups: Will be used for restore
└─ Time: 2-3 hours

Procedure:

Step 1: Backup Everything (1 minute)
$ Create-FullBackup -OutputPath "D:\emergency-backup-$(Get-Date -f 'yyyyMMdd-HHmmss')"
Result: 50 GB backup created

Step 2: Notify Customers (1 minute)
├─ Status page: "Performing emergency maintenance"
├─ Email: "Systems temporarily offline"
├─ Estimate: 2 hours downtime
└─ Apology + discount code

Step 3: Stop All Services (2 minutes)
$ Stop-AllHELIOSServices -Force

Step 4: Delete Everything (3 minutes)
$ Remove-Item "C:\HELIOS\*" -Recurse -Force
$ DROP DATABASE HELIOS;

Step 5: Reinstall Fresh (30 minutes)
$ .\Setup-HELIOS.ps1 -Fresh -NoBackup

Step 6: Restore from Backup (60 minutes)
$ Restore-HELIOSBackup -BackupPath "D:\emergency-backup-20240417-173045"
Result: All data restored

Step 7: Verify System (30 minutes)
├─ All services running? ✓
├─ Database integrity? ✓
├─ All data restored? ✓
└─ System responsive? ✓

Step 8: Bring Back Online (5 minutes)
$ Update-StatusPage -Status "Online"
$ Send-AllClear -Channel email

Total Time: 2-3 hours
Data Loss: 0 (restored from backup)
Customer Experience: Poor (2-3 hour outage)
```

---

## Performance Diagnostics Toolkit

### Quick Diagnostics Command

```powershell
function Get-FullDiagnostics {
    Write-Host "HELIOS Platform Full Diagnostics" -ForegroundColor Cyan
    Write-Host "=================================" -ForegroundColor Cyan
    
    # System Health
    Write-Host "`n1. System Health" -ForegroundColor Yellow
    Get-HELIOSStatus | Format-Table
    
    # Service Status
    Write-Host "`n2. Service Status" -ForegroundColor Yellow
    Get-HELIOSServices | Format-Table Name, Status
    
    # Performance Metrics
    Write-Host "`n3. Performance Metrics" -ForegroundColor Yellow
    Get-HELIOSMetrics -Period "Last 5 Minutes" | Format-Table
    
    # Recent Errors
    Write-Host "`n4. Recent Errors (Last Hour)" -ForegroundColor Yellow
    Get-HELIOSErrors -TimeSpan "Last 1 Hour" -Top 10
    
    # Database Health
    Write-Host "`n5. Database Health" -ForegroundColor Yellow
    Get-DatabaseHealth | Format-Table
    
    # Disk Space
    Write-Host "`n6. Disk Space" -ForegroundColor Yellow
    Get-Volume | Select-Object DriveLetter, SizeRemaining, Size
    
    # Network Connectivity
    Write-Host "`n7. Network Connectivity" -ForegroundColor Yellow
    Test-HELIOSConnectivity
    
    # Alert Status
    Write-Host "`n8. Active Alerts" -ForegroundColor Yellow
    Get-ActiveAlerts | Format-Table Severity, Message, TimeTriggered
    
    Write-Host "`nDiagnostics Complete" -ForegroundColor Green
}

# Usage:
Get-FullDiagnostics | Out-File "diagnostics-$(Get-Date -f 'yyyyMMdd-HHmmss').txt"
```

---

## Support Resources

**When self-help isn't enough**:

```
Support Level 1: Documentation
├─ Docs: docs/NAVIGATION.md
├─ Guides: USER_*.md files
└─ Community: forum.helios-platform.com
└─ Time: 15-30 minutes

Support Level 2: Community Forum
├─ Search existing issues
├─ Post question with details
├─ Wait for community response
└─ Time: 30 minutes - 24 hours

Support Level 3: Email Support
├─ Email: support@helios-platform.com
├─ Include: Error details, screenshots, config
├─ SLA: 4-hour response
└─ Time: 4-8 hours

Support Level 4: Priority Support
├─ Contact: premium-support@helios-platform.com
├─ Phone: 1-800-HELIOS-1
├─ SLA: 1-hour response
└─ Cost: Requires Premium plan

Support Level 5: Emergency Support
├─ Contact: emergency@helios-platform.com
├─ 24/7 on-call support team
├─ SLA: 15-minute response
└─ Cost: Requires Enterprise plan + fee
```

---

## Escalation Checklist

**When to escalate to support**:

```
Can you reproduce the issue?
├─ If No: Make detailed notes and skip to step 4
├─ If Yes: Proceed to step 2

Have you checked the logs?
├─ If No: Review logs, often reveals root cause
├─ If Yes: Proceed to step 3

Have you tried a restart?
├─ If No: Try restarting the service
├─ If Yes: Proceed to step 4

Have you searched documentation?
├─ If No: Search docs and forum first
├─ If Yes: Proceed to step 5

Ready to escalate? Gather:
├─ Error message (exact text)
├─ Steps to reproduce
├─ System details (version, OS, etc.)
├─ Recent changes (if any)
├─ Screenshots/logs
├─ Contact support with all details
└─ Include diagnostic report: Get-FullDiagnostics
```

---

**Last Updated: April 2026**  
**Version: 1.0.0**

*Emergency Contact: support@helios-platform.com | Phone: 1-800-HELIOS-1*

*For operational guides, see USER_OPERATIONS_GUIDE.md*  
*For advanced configuration, see USER_ADVANCED_GUIDE.md*
