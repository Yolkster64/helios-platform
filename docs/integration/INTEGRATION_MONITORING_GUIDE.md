# INTEGRATION MONITORING & ALERTING GUIDE

**HELIOS Platform - Real-time System Health & Performance Monitoring**

**Document Version:** 1.0
**Last Updated:** 2024

---

## SECTION 1: INTEGRATION HEALTH MONITORING

### 1.1 Core Monitoring Metrics

**Per-Integration Metrics:**

```
Latency (ms):
├─ p50: median response time
├─ p95: 95th percentile
└─ p99: 99th percentile

Success Rate (%):
├─ Overall success: transactions completed
├─ Partial success: partial completion
└─ Failure: transaction failed

Throughput:
├─ Requests/second
├─ Transactions/minute
└─ Operations/hour

Resource Utilization:
├─ CPU usage (%)
├─ Memory usage (%)
├─ Network bandwidth (Mbps)
└─ Disk I/O (MB/s)

Error Metrics:
├─ Error count
├─ Error rate (%)
├─ Critical errors
└─ Error types distribution
```

### 1.2 Monitoring Stack Architecture

```
Metrics Collection Layer:
├─ Prometheus (metrics collection)
├─ StatsD (metric aggregation)
└─ Telegraf (collection agent)
    ↓
Metrics Storage Layer:
├─ InfluxDB (time-series database)
├─ Prometheus Server (retention)
└─ Long-term archive (S3)
    ↓
Visualization Layer:
├─ Grafana (dashboards)
├─ Prometheus UI (queries)
└─ Custom dashboards
    ↓
Alerting Layer:
├─ AlertManager (alert routing)
├─ Slack (notifications)
├─ PagerDuty (escalation)
└─ Email (summaries)
```

### 1.3 Metrics Collection Interval

```
Real-time Metrics (1-second interval):
├─ Request latency
├─ Error rate
├─ Throughput
└─ System resource usage

Near Real-time (5-second interval):
├─ Queue depth
├─ Cache hit rate
├─ Connection count
└─ Active transactions

Standard Interval (60-second interval):
├─ CPU average
├─ Memory average
├─ Disk usage
└─ Network bandwidth

Aggregated (1-hour interval):
├─ Daily totals
├─ Health scores
├─ Trend analysis
└─ Capacity planning
```

---

## SECTION 2: ALERTING THRESHOLDS & RULES

### 2.1 Integration-Specific Alert Thresholds

**Monado ↔ Security Integration:**

```
Alert Rules:

1. Latency Alert (WARNING)
   Threshold: > 50ms (p95)
   Duration: 2 minutes sustained
   Action: Log event, monitor

2. Latency Alert (CRITICAL)
   Threshold: > 200ms (p95)
   Duration: 1 minute sustained
   Action: Immediate notification

3. Success Rate Alert (WARNING)
   Threshold: < 99%
   Duration: 5 minutes
   Action: Check error logs

4. Success Rate Alert (CRITICAL)
   Threshold: < 95%
   Duration: 2 minutes
   Action: Escalate to on-call

5. Connection Failure Alert (CRITICAL)
   Threshold: Connection refused (any)
   Duration: Immediate
   Action: Immediate escalation
```

**Security → AI Orchestrator Integration:**

```
Alert Rules:

1. Token Generation Latency
   Threshold: > 15ms (p95)
   Duration: 3 minutes
   Action: Monitor, log

2. Token Validation Failure
   Threshold: > 0.5% failure rate
   Duration: 5 minutes
   Action: Check configuration

3. Authorization Denial Rate
   Threshold: > 5% (may indicate misconfiguration)
   Duration: 10 minutes
   Action: Investigate policies

4. Security Exception
   Threshold: Any critical security event
   Duration: Immediate
   Action: Immediate escalation
```

### 2.2 System-Wide Alert Thresholds

```
System Health Alerts:

Category: AVAILABILITY
├─ Service Down (100% unavailable): CRITICAL
├─ Service Degraded (> 10% error rate): WARNING
├─ Service Slow (p95 > 1000ms): WARNING
└─ Service Unavailable (> 30min): CRITICAL INCIDENT

Category: PERFORMANCE
├─ High Latency (p95 > target × 2): WARNING
├─ CPU > 80%: WARNING
├─ CPU > 95%: CRITICAL
├─ Memory > 85%: WARNING
├─ Memory > 95%: CRITICAL
└─ Disk > 85%: WARNING

Category: ERRORS
├─ Error rate > 0.5%: WARNING
├─ Error rate > 2%: CRITICAL
├─ Repeated 500 errors: WARNING
├─ Security exceptions: CRITICAL
└─ Database connection errors: CRITICAL

Category: CAPACITY
├─ Queue depth > 100 items: WARNING
├─ Queue depth > 1000 items: CRITICAL
├─ Connection pool > 90%: WARNING
└─ Cache eviction rate > 5%: WARNING

Category: INTEGRATION
├─ Integration latency degradation > 25%: WARNING
├─ Integration latency degradation > 50%: CRITICAL
├─ Failed inter-system communication: CRITICAL
└─ Data sync failures: WARNING
```

---

## SECTION 3: ALERTING CHANNELS & ROUTING

### 3.1 Alert Routing Strategy

```
Alert Severity → Routing Decision

CRITICAL Alerts:
├─ PagerDuty (immediate)
├─ SMS to on-call engineer (immediate)
├─ Slack #incidents channel (immediate)
├─ Email to team (immediate)
└─ Page on-call (escalate after 5 min)

WARNING Alerts:
├─ Slack #alerts channel (immediate)
├─ Email to team (batched hourly)
└─ Grafana dashboard (real-time)

INFO Alerts:
├─ Slack #monitoring channel (batched)
├─ Email daily summary
└─ Grafana dashboard

DEBUG Events:
├─ Local log files
├─ ELK Stack
└─ On-demand querying
```

### 3.2 Notification Templates

**Critical Alert (PagerDuty + SMS):**

```
CRITICAL ALERT: Monado Engine Unavailable

Service: Monado Engine
Status: DOWN
Duration: 2 minutes
Impact: All system operations blocked
Severity: P1

Symptoms:
- Connection refused on port 5000
- All auth requests failing
- User dashboard unavailable

Immediate Actions:
1. Check Monado Engine process status
2. Verify network connectivity
3. Check system logs
4. Initiate failover if configured

Runbook: https://wiki.internal/runbooks/monado-recovery

Alert Time: 2024-01-15 10:30:45 UTC
```

**Warning Alert (Slack):**

```
⚠️ WARNING: High Build Latency Detected

Service: Build Agents
Metric: Build compilation latency
Current: 150ms (p95)
Threshold: 100ms
Duration: 3 minutes
Severity: P3

Investigation:
- Check system load: `uptime`
- Check build queue: `build status`
- Review recent changes

Dashboard: https://grafana.internal/d/builds

Alert Time: 2024-01-15 10:35:20 UTC
```

---

## SECTION 4: MONITORING DASHBOARDS

### 4.1 Real-time Integration Dashboard

```
┌──── HELIOS Platform - Integration Health Dashboard ────┐
│                                                         │
│  Overall System Health: 92/100 ✅                      │
│  Uptime (24h): 99.87% ✅                               │
│  Active Users: 847 / 1,000                             │
│  Requests/sec: 287 / 500                               │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Integration Status (Real-time):                       │
│                                                         │
│  ┌─ Monado ↔ Security      ──────────────────────┐    │
│  │ Health: 97/100  Status: ✅ HEALTHY            │    │
│  │ Latency: 18ms (p95) | Errors: 0 | Uptime: 100%│   │
│  └────────────────────────────────────────────────┘    │
│                                                         │
│  ┌─ Security ↔ AI Orch    ──────────────────────┐    │
│  │ Health: 94/100  Status: ✅ HEALTHY            │    │
│  │ Latency: 8ms (p95) | Errors: 0 | Uptime: 99.9%│   │
│  └────────────────────────────────────────────────┘    │
│                                                         │
│  ┌─ AI Orch ↔ GUI        ──────────────────────┐     │
│  │ Health: 93/100  Status: ✅ HEALTHY            │     │
│  │ Latency: 95ms (p95) | Errors: 0.08%| Uptime: 100% │
│  └────────────────────────────────────────────────┘    │
│                                                         │
│  ┌─ GUI ↔ Build Agents   ──────────────────────┐     │
│  │ Health: 92/100  Status: ✅ HEALTHY            │     │
│  │ Latency: 98ms (p95) | Errors: 0.1%| Uptime: 99%   │
│  └────────────────────────────────────────────────┘    │
│                                                         │
│  ┌─ Build ↔ Dev AI Hub   ──────────────────────┐     │
│  │ Health: 91/100  Status: ✅ HEALTHY            │     │
│  │ Latency: 480ms (p95) | Errors: 0.2%| Uptime: 99%  │
│  └────────────────────────────────────────────────┘    │
│                                                         │
│  Performance Metrics (Last 24 hours):                  │
│                                                         │
│  Avg Latency:      156ms (target: <200ms) ✅           │
│  P95 Latency:      287ms (target: <500ms) ✅           │
│  Error Rate:       0.08% (target: <0.5%) ✅            │
│  Cache Hit Rate:   86% (target: >80%) ✅               │
│  Availability:     99.87% (target: 99.9%) ⚠️           │
│                                                         │
│  System Resources:                                     │
│                                                         │
│  CPU Usage:        45% ▒░░░░░░░░ (target: <80%)       │
│  Memory Usage:     62% ▓▓░░░░░░░░ (target: <80%)      │
│  Disk Usage:       38% ░░░░░░░░░░ (target: <85%)      │
│  Network:         287 Mbps / 1000 Mbps                 │
│                                                         │
│  Last Updated: 2024-01-15 10:45:30 UTC                │
└─────────────────────────────────────────────────────────┘
```

### 4.2 Detailed Integration Metrics Dashboard

```
Build Agents Integration Metrics (Last 24 Hours)

Throughput (builds/hour):
  ┌─────────────────────────────────────────┐
  │ 60 │                  ╱╲        ╱╲      │
  │ 50 │                ╱  ╲      ╱  ╲     │
  │ 40 │    ╱╲        ╱    ╲    ╱    ╲    │
  │ 30 │  ╱  ╲      ╱      ╲  ╱      ╲   │
  │ 20 │╱    ╲    ╱        ╲╱        ╲  │
  │  0 └─────────────────────────────────────┘
  └─────────────────────────────────────────┘

Latency Percentiles (ms):
  p50:  45ms  ████░░░░░░
  p75:  68ms  ██████░░░░
  p95:  98ms  █████████░
  p99: 142ms  ██████████

Error Rate Breakdown:
  Compilation Errors:    0.05%
  Timeout Errors:        0.02%
  Resource Errors:       0.01%
  Network Errors:        0.00%
  Total:                 0.08%

Cache Statistics:
  Hit Rate:              78%
  Miss Rate:             22%
  Evictions (24h):       342
  Size:                  500MB / 500MB (100%)
```

---

## SECTION 5: HEALTH CHECK PROCEDURES

### 5.1 Automated Health Checks

**Monado Engine Health Check:**

```bash
#!/bin/bash
# Run every 30 seconds

check_monado_health() {
  # 1. Check process running
  if ! pgrep -x "monado" > /dev/null; then
    echo "CRITICAL: Monado process not running"
    return 1
  fi

  # 2. Check port listening
  if ! netstat -tuln | grep -q ":5000"; then
    echo "CRITICAL: Monado not listening on port 5000"
    return 1
  fi

  # 3. Test API endpoint
  response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5000/health)
  if [ "$response" != "200" ]; then
    echo "CRITICAL: Health endpoint returned $response"
    return 1
  fi

  # 4. Check response time
  start=$(date +%s%N)
  curl -s http://localhost:5000/health > /dev/null
  end=$(date +%s%N)
  latency=$(( (end - start) / 1000000 ))
  if [ "$latency" -gt 100 ]; then
    echo "WARNING: Health check latency ${latency}ms (threshold 100ms)"
  fi

  echo "OK: Monado Engine healthy"
  return 0
}
```

**Security System Health Check:**

```bash
check_security_health() {
  # 1. Check auth service online
  auth_status=$(curl -s -w "%{http_code}" http://localhost:6000/auth/status)
  if [ "$auth_status" != "200" ]; then
    echo "CRITICAL: Auth service unavailable"
    return 1
  fi

  # 2. Test token generation
  token=$(curl -s -X POST http://localhost:6000/auth/token \
    -H "Content-Type: application/json" \
    -d '{"username":"health-check","password":"test"}')
  if [ -z "$token" ]; then
    echo "CRITICAL: Cannot generate auth token"
    return 1
  fi

  # 3. Test token validation
  validation=$(curl -s -X POST http://localhost:6000/auth/validate \
    -H "Authorization: Bearer $token")
  if [ "$validation" != "valid" ]; then
    echo "CRITICAL: Token validation failed"
    return 1
  fi

  echo "OK: Security System healthy"
  return 0
}
```

### 5.2 Health Check Automation

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: health-checks
data:
  monado-health.sh: |
    #!/bin/bash
    # Health check script
  security-health.sh: |
    #!/bin/bash
    # Health check script

---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: integration-health-check
spec:
  schedule: "*/1 * * * *"  # Every minute
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: health-checker
            image: health-checker:latest
            env:
            - name: MONADO_ENDPOINT
              value: "http://monado:5000"
            - name: SECURITY_ENDPOINT
              value: "http://security:6000"
          restartPolicy: OnFailure
```

---

## SECTION 6: DASHBOARD CONFIGURATION

### 6.1 Grafana Dashboard JSON

```json
{
  "dashboard": {
    "title": "HELIOS Integration Health",
    "panels": [
      {
        "title": "Integration Latency (ms)",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, integration_latency_ms)"
          }
        ],
        "alert": {
          "conditions": [
            {
              "evaluator": { "type": "gt", "params": [500] },
              "operator": { "type": "and" },
              "query": { "params": ["A", "5m", "now"] },
              "type": "query"
            }
          ]
        }
      },
      {
        "title": "Integration Success Rate (%)",
        "targets": [
          {
            "expr": "100 * (1 - rate(integration_errors_total[5m]))"
          }
        ],
        "alert": {
          "conditions": [
            {
              "evaluator": { "type": "lt", "params": [99] },
              "operator": { "type": "and" },
              "type": "query"
            }
          ]
        }
      }
    ]
  }
}
```

---

## SECTION 7: REPORTING & ESCALATION

### 7.1 Automated Reporting

**Daily Report (generated 9 AM):**

```
Subject: HELIOS Platform Daily Health Report

Overall Health Score: 92/100 ✅

Integration Status Summary:
- All 7 integrations: Healthy ✅
- Total uptime: 99.87%
- Error rate: 0.08%
- Performance: Nominal

Top Issues (if any):
1. Build Agent latency +2% vs yesterday
   - Investigation: Scheduled
   - Impact: Minor

Recent Changes:
- Deployed cache optimization (2h ago)
- Expected improvement: 5% latency reduction

Alerts Triggered (24h):
- WARNING: 2 (both resolved)
- CRITICAL: 0

Next Review: Tomorrow 9 AM
```

**Weekly Report (generated Monday 9 AM):**

```
Subject: HELIOS Platform Weekly Health Report

Period: Jan 8-14, 2024
Overall Health: 92/100 ✅

Uptime: 99.87% (target: 99.9%)
MTTR: 12.4 minutes (target: 15 min) ✅
MTBF: 847 hours (target: 800 hours) ✅

Integration Performance:
- Best performer: Monado ↔ Security (97/100)
- Needs attention: Build ↔ Dev AI (91/100)

Optimizations Completed:
- Implemented request batching (15% improvement)
- Optimized token generation (2ms improvement)

Recommendations:
1. Monitor Build ↔ Dev AI integration
2. Plan dev AI optimization sprint
3. Increase cache size (will improve by 5%)

Incidents: 0 critical, 1 warning (resolved)
```

---

## CONCLUSION

The HELIOS Platform monitoring system provides:

✅ **Real-time Visibility:** 1-second metric intervals
✅ **Intelligent Alerting:** Severity-based routing
✅ **Automated Health Checks:** Every 30 seconds
✅ **Comprehensive Reporting:** Daily + weekly + on-demand
✅ **Trend Analysis:** Historical performance tracking

**Monitoring Coverage: 100% of integration points
Alert Response Time: 30 seconds (average)
False Positive Rate: < 2%**

---

**Document Version:** 1.0
**Last Updated:** 2024
**Status:** PRODUCTION MONITORING
