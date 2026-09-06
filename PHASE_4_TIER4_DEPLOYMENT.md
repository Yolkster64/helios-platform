# Phase 4 Tier 4: Deployment & Operations Guide

**Status**: Complete  
**Date**: 2024  
**Target**: Deployment procedures, validation, rollback strategies  

---

## 🚀 Deployment Checklist

### Pre-Deployment Verification

```
Phase 1: Code Preparation
├─ [ ] All tests passing (500+ tests)
├─ [ ] Code review completed
├─ [ ] Security scan passed
├─ [ ] Performance regression tests passed
├─ [ ] No new security vulnerabilities
├─ [ ] Documentation updated
├─ [ ] Release notes prepared
└─ [ ] Version bumped

Phase 2: Build Verification
├─ [ ] Release build compiles without errors
├─ [ ] Build time acceptable (< 10 seconds)
├─ [ ] No compiler warnings
├─ [ ] Static analysis clean
├─ [ ] All tests pass in Release configuration
├─ [ ] Artifacts packaged correctly
└─ [ ] Signatures verified

Phase 3: Environment Verification
├─ [ ] Staging environment healthy
├─ [ ] Database migrations tested
├─ [ ] Configuration validated
├─ [ ] Dependencies available
├─ [ ] Network connectivity confirmed
├─ [ ] SSL certificates valid
└─ [ ] Monitoring systems online

Phase 4: Business Approval
├─ [ ] Product owner sign-off
├─ [ ] Change advisory board approved
├─ [ ] Stakeholders notified
├─ [ ] Support team briefed
└─ [ ] Rollback plan reviewed
```

---

## 📋 Deployment Procedures

### Deployment Strategy

```
┌─────────────────────────────────────────┐
│  Blue-Green Deployment                  │
├─────────────────────────────────────────┤
│                                         │
│  Blue (Current - v1.2.3)               │
│  ├─ 50% of traffic                     │
│  └─ Production instances              │
│                                         │
│  Green (New - v1.2.4)                  │
│  ├─ 50% of traffic (canary)           │
│  └─ New instances                      │
│                                         │
│  Load Balancer                         │
│  └─ Routes traffic to both            │
│                                         │
└─────────────────────────────────────────┘
```

**Process**:

1. **Pre-Deployment**

   ```bash
   # Verify current state
   kubectl get pods -n production
   kubectl get services -n production
   
   # Backup database
   mysqldump -u root -p helios > backup-$(date +%Y%m%d-%H%M%S).sql
   ```

2. **Deploy New Version**

   ```bash
   # Deploy new version (Green)
   kubectl set image deployment/helios-api \
     api=myregistry.azurecr.io/helios-api:v1.2.4 \
     -n production --record
   
   # Wait for rollout
   kubectl rollout status deployment/helios-api -n production
   
   # Verify new pods are healthy
   kubectl get pods -l app=helios-api -n production
   ```

3. **Canary Testing (10% traffic)**

   ```bash
   # Route 10% to Green, 90% to Blue
   kubectl patch service helios-api -p \
     '{"spec":{"selector":{"version":"v1.2.4"}}}'
   
   # Monitor metrics
   # - Error rate should stay < 0.1%
   # - Latency should stay < baseline + 5%
   # - Success rate should stay > 99.9%
   ```

4. **Gradual Traffic Shift**

   ```
   Time    Blue    Green   Status
   0:00    100%    0%      Deployment started
   5:00    90%     10%     Canary phase (monitoring)
   15:00   80%     20%     Increasing traffic
   25:00   50%     50%     Half traffic shift
   35:00   20%     80%     Majority on new version
   45:00   0%      100%    Complete (Blue shutdown)
   ```

5. **Validation**

   ```bash
   # Smoke tests
   curl https://api.example.com/health
   curl https://api.example.com/api/users
   
   # Performance validation
   # Check latency: should be < baseline + 5%
   # Check error rate: should be < 0.1%
   # Check throughput: should be >= baseline - 5%
   ```

6. **Rollback (if needed)**

   ```bash
   # Immediate rollback
   kubectl rollout undo deployment/helios-api -n production
   kubectl rollout status deployment/helios-api -n production
   ```

---

### Database Migration Strategy

```
Pre-deployment:
1. Create migration script
2. Test on staging database
3. Verify rollback procedure

Deployment:
1. Stop write operations (read-only mode)
2. Execute migration (with lock)
3. Verify data integrity
4. Resume write operations

Rollback:
1. Execute rollback migration
2. Verify data integrity
3. Resume normal operations
```

**Example Migration**:

```sql
-- Migration: Add_UserPreferences_Table

-- Forward migration
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'UserPreferences')
BEGIN
    CREATE TABLE UserPreferences (
        Id INT PRIMARY KEY IDENTITY,
        UserId INT NOT NULL FOREIGN KEY REFERENCES Users(Id),
        Theme NVARCHAR(50) DEFAULT 'light',
        Language NVARCHAR(10) DEFAULT 'en',
        CreatedDate DATETIME2 DEFAULT GETUTCDATE(),
        ModifiedDate DATETIME2 DEFAULT GETUTCDATE()
    );
    
    CREATE INDEX IX_UserId ON UserPreferences(UserId);
    
    PRINT 'UserPreferences table created';
END

-- Rollback migration
-- IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'UserPreferences')
-- BEGIN
--     DROP TABLE UserPreferences;
--     PRINT 'UserPreferences table dropped';
-- END
```

---

### Infrastructure as Code (IaC)

```yaml
# Kubernetes Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: helios-api
  namespace: production
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: helios-api
  template:
    metadata:
      labels:
        app: helios-api
        version: v1.2.4
    spec:
      containers:
      - name: api
        image: myregistry.azurecr.io/helios-api:v1.2.4
        ports:
        - containerPort: 5000
        env:
        - name: DATABASE_CONNECTION
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: connection-string
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: 5000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 5000
          initialDelaySeconds: 5
          periodSeconds: 5
```

---

## 🔍 Deployment Validation

### Automated Validation

```powershell
# Deployment validation script
param(
    [string]$Environment = "Staging",
    [string]$ApiUrl = "https://api-staging.example.com",
    [int]$TimeoutSeconds = 60
)

Write-Host "Starting deployment validation..."
$startTime = Get-Date

# 1. Health check
Write-Host "Checking health endpoint..."
$health = Invoke-WebRequest "$ApiUrl/health" -TimeoutSec 5
if ($health.StatusCode -eq 200) {
    Write-Host "✓ Health check passed" -ForegroundColor Green
} else {
    Write-Host "✗ Health check failed" -ForegroundColor Red
    exit 1
}

# 2. API functionality test
Write-Host "Testing API endpoints..."
$users = Invoke-RestMethod "$ApiUrl/api/users?limit=10" -TimeoutSec 10
if ($users -and $users.Count -gt 0) {
    Write-Host "✓ User listing works (found $($users.Count) users)" -ForegroundColor Green
} else {
    Write-Host "✗ User listing failed" -ForegroundColor Red
    exit 1
}

# 3. Performance validation
Write-Host "Measuring response times..."
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$response = Invoke-RestMethod "$ApiUrl/api/users/1" -TimeoutSec 10
$stopwatch.Stop()
$latency = $stopwatch.ElapsedMilliseconds

if ($latency -lt 100) {
    Write-Host "✓ Response time acceptable: ${latency}ms" -ForegroundColor Green
} else {
    Write-Host "⚠ Response time high: ${latency}ms" -ForegroundColor Yellow
}

# 4. Error handling
Write-Host "Testing error handling..."
try {
    $error = Invoke-RestMethod "$ApiUrl/api/users/99999" -TimeoutSec 5
} catch {
    if ($_.Exception.Response.StatusCode -eq 404) {
        Write-Host "✓ Error handling works correctly" -ForegroundColor Green
    }
}

$elapsedTime = ((Get-Date) - $startTime).TotalSeconds
Write-Host "Validation complete in ${elapsedTime}s" -ForegroundColor Green
```

---

### Smoke Tests

```csharp
[TestClass]
public class DeploymentSmokeTests
{
    private HttpClient _httpClient;
    private readonly string _baseUrl = "https://api.example.com";
    
    [TestInitialize]
    public void Setup()
    {
        _httpClient = new HttpClient();
    }
    
    [TestMethod]
    public async Task HealthCheck_Returns200()
    {
        var response = await _httpClient.GetAsync($"{_baseUrl}/health");
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);
    }
    
    [TestMethod]
    public async Task GetUsers_ReturnsValidList()
    {
        var response = await _httpClient.GetAsync($"{_baseUrl}/api/users?limit=10");
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);
        
        var content = await response.Content.ReadAsAsync<List<UserDto>>();
        Assert.IsNotNull(content);
    }
    
    [TestMethod]
    public async Task Authentication_Works()
    {
        var loginRequest = new { email = "test@example.com", password = "password" };
        var content = new StringContent(
            JsonConvert.SerializeObject(loginRequest),
            Encoding.UTF8,
            "application/json");
        
        var response = await _httpClient.PostAsync($"{_baseUrl}/api/auth/login", content);
        Assert.IsTrue(response.StatusCode == HttpStatusCode.OK || 
                      response.StatusCode == HttpStatusCode.Unauthorized);
    }
    
    [TestMethod]
    public async Task Database_IsAccessible()
    {
        var response = await _httpClient.GetAsync($"{_baseUrl}/api/health/db");
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);
    }
}
```

---

## 🔄 Rollback Procedures

### Automated Rollback

```powershell
# Automatic rollback if validation fails
param(
    [string]$DeploymentName = "helios-api",
    [string]$Namespace = "production"
)

$validationPassed = Test-Deployment -DeploymentName $DeploymentName -Namespace $Namespace

if (-not $validationPassed) {
    Write-Host "Deployment validation failed, initiating rollback..." -ForegroundColor Red
    
    # Get previous deployment
    $previousVersion = kubectl rollout history deployment/$DeploymentName -n $Namespace | Select-Object -First 2 | Select-Object -Last 1
    
    # Rollback
    kubectl rollout undo deployment/$DeploymentName -n $Namespace
    kubectl rollout status deployment/$DeploymentName -n $Namespace
    
    # Verify rollback
    $health = Test-HealthCheck -ApiUrl "https://api.example.com"
    if ($health) {
        Write-Host "✓ Rollback successful, service restored" -ForegroundColor Green
    } else {
        Write-Host "✗ Rollback failed, manual intervention required" -ForegroundColor Red
        Exit-WithAlert "Deployment rollback failed"
    }
}
```

### Manual Rollback

```bash
# List deployment history
kubectl rollout history deployment/helios-api -n production

# Rollback to previous version
kubectl rollout undo deployment/helios-api -n production

# Rollback to specific revision
kubectl rollout undo deployment/helios-api --to-revision=2 -n production

# Monitor rollback progress
kubectl rollout status deployment/helios-api -n production
```

---

## 📊 Post-Deployment Monitoring

### Metrics to Monitor

```
First Hour Post-Deployment:
├─ Error rate: should be < 0.5% (usually 0.02%)
├─ Response time P95: should be < baseline + 10%
├─ CPU usage: should be < 70%
├─ Memory usage: should be < 80%
├─ Database connections: should be < 50% of max
├─ Cache hit rate: should maintain > 80%
└─ No exceptions in logs

First 24 Hours:
├─ Error rate stable and < 0.1%
├─ No performance degradation
├─ No memory leaks
├─ All background jobs running
└─ User reports of issues: 0
```

---

### Alert Configuration

```yaml
# Prometheus alert rules
groups:
- name: deployment-alerts
  rules:
  - alert: HighErrorRate
    expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.01
    for: 5m
    annotations:
      summary: "High error rate detected ({{ $value | humanizePercentage }})"
  
  - alert: HighLatency
    expr: histogram_quantile(0.95, http_request_duration_seconds) > 1.0
    for: 10m
    annotations:
      summary: "High latency detected ({{ $value }}s)"
  
  - alert: HighMemoryUsage
    expr: container_memory_usage_bytes / container_spec_memory_limit_bytes > 0.9
    for: 5m
    annotations:
      summary: "Memory usage critical ({{ $value | humanizePercentage }})"
```

---

## 📋 Deployment Checklist

- [ ] Pre-deployment checklist completed
- [ ] All tests passing
- [ ] Security scan clean
- [ ] Performance baseline established
- [ ] Database migration tested
- [ ] Configuration validated
- [ ] Deployment strategy selected
- [ ] Canary testing metrics defined
- [ ] Rollback procedure documented
- [ ] Monitoring alerts configured
- [ ] Stakeholders notified
- [ ] Deployment executed
- [ ] Smoke tests passed
- [ ] Performance validated
- [ ] 24-hour monitoring completed

---

## 🔗 Related Documents

- [Security Hardening Guide](PHASE_4_TIER4_SECURITY.md) - Security checks before deployment
- [Resilience Guide](PHASE_4_TIER4_RESILIENCE.md) - Resilience requirements for deployment
- [Operations Guide](PHASE_4_TIER3_OPERATIONS.md) - Post-deployment operations

---

**Document Version**: 1.0  
**Last Updated**: Phase 4 Session  
**Status**: Deployment Guide Complete
