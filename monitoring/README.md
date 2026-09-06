# HELIOS Platform - Comprehensive Monitoring & Alerting System

## 🎯 Overview

Complete enterprise-grade monitoring and alerting system for the HELIOS Platform with real-time dashboards, health checks, performance metrics, alerting, SLA tracking, capacity planning, anomaly detection, and incident management.

## 📊 System Components

### Core Monitoring (7 Components)

1. **HELIOS.Platform** - Main API and orchestration (Port 5000)
2. **AI-Dashboard** - Analytics and visualization (Port 5001)
3. **Analytics-Core** - Data processing and analysis (Port 5002)
4. **Cloud-Bridge** - Cloud integration layer (Port 5003)
5. **Performance-AI** - Performance optimization (Port 5004)
6. **Security-Engine** - Security and compliance (Port 5005)
7. **Vault-Dynamics** - Secrets and encryption (Port 5006)

## 🚀 Quick Start

### 1. Start Monitoring System

```powershell
cd C:\Users\ADMIN\helios-platform\monitoring\scripts
.\start-monitoring.ps1 -Mode Continuous -Port 8080
```

### 2. Access Dashboard

Open browser and navigate to: `http://localhost:8080`

### 3. View Real-time Data

- Health Checks: `data/latest_health_check.json`
- Performance Metrics: `data/latest_performance_metrics.json`
- Alerts: `data/alert_status.json`
- Incidents: `data/incidents_status.json`
- Anomalies: `data/anomalies.json`

## 📁 Directory Structure

```
monitoring/
├── dashboards/          # Web-based dashboard
│   └── index.html       # Main dashboard UI
├── scripts/             # PowerShell collection scripts
│   ├── 00-init-database.ps1
│   ├── 01-health-check.ps1
│   ├── 02-performance-metrics.ps1
│   ├── 03-alert-evaluator.ps1
│   ├── 04-sla-calculator.ps1
│   ├── 05-anomaly-detector.ps1
│   ├── 06-incident-manager.ps1
│   └── start-monitoring.ps1
├── config/              # Configuration files
│   ├── alert-rules.json
│   ├── components.json
│   └── notifications.json
├── data/                # Runtime data and exports
│   ├── helios_monitoring.db  # SQLite database
│   ├── latest_health_check.json
│   ├── latest_performance_metrics.json
│   ├── alert_status.json
│   ├── incidents_status.json
│   └── anomalies.json
├── logs/                # Application logs
└── alerts/              # Alert definitions
```

## ✨ Features

### 1. Real-Time Dashboards

- Component health status with live indicators
- Performance metrics (throughput, latency, errors)
- Alert summary and incident tracking
- SLA compliance tracking
- Resource utilization graphs
- 24-hour trending

### 2. Health Checks (01-health-check.ps1)

- HTTP endpoint availability
- Port responsiveness
- Service readiness
- Response time monitoring
- Runs every 30 seconds

**Sample Output:**

```
✓ HELIOS.Platform - Healthy (Status: 200, Response: 45ms)
⚠ Analytics-Core - Warning (Status: 200, Response: 1250ms)
✗ Cloud-Bridge - Critical (Port not responding)
```

### 3. Performance Metrics (02-performance-metrics.ps1)

Tracks per component:

- **Throughput**: Requests per second
- **Latency**: P50, P95, P99 percentiles
- **Errors**: 4xx and 5xx error rates
- **Resources**: CPU %, Memory %, Disk I/O, Network

**Sample Output:**

```
HELIOS.Platform:
  ├─ Throughput: 150 req/s
  ├─ Latency P99: 300ms
  ├─ Errors 5xx: 0.1%
  ├─ CPU: 45% | Memory: 60%
  └─ Network: 100 MB/s
```

### 4. Alert Evaluator (03-alert-evaluator.ps1)

Predefined alert rules:

- High Error Rate (5xx > 1%)
- High Latency (P99 > 1000ms)
- High CPU (> 85%)
- High Memory (> 90%)
- Service Unavailability

**Notification Channels:**

- Email (SMTP)
- Microsoft Teams
- Webhooks
- PagerDuty

### 5. SLA Tracking (04-sla-calculator.ps1)

Monitors:

- Monthly uptime % vs targets (99.9%, 99.95%, 99.99%)
- Mean Time To Respond (MTTR)
- Mean Time Between Failures (MTBF)
- Downtime incidents
- Compliance scoring

**Sample Output:**

```
HELIOS.Platform:
  ├─ SLA Target: 99.95%
  ├─ Actual Uptime: 99.96% ✓
  ├─ Downtime: 5.76m / 43.2m allowed
  └─ MTTR: 15m (Target: 30m)
```

### 6. Anomaly Detection (05-anomaly-detector.ps1)

Detects:

- Statistical deviations (Z-score > 2.5σ)
- Sudden spikes (>150% baseline)
- Sudden drops (<50% baseline)
- Rate of change anomalies
- Confidence scoring

**Anomaly Types:**

- STATISTICAL_DEVIATION
- SPIKE
- DROP
- TREND_CHANGE

### 7. Incident Management (06-incident-manager.ps1)

Lifecycle management:

- Automatic creation from critical alerts
- Status tracking (NEW → ASSIGNED → INVESTIGATING → RESOLVED)
- Root cause documentation
- Resolution notes
- MTTR/MTBF calculations

**Sample Incident:**

```
INC-20240413-54821
├─ Title: Analytics-Core Memory Spike
├─ Component: Analytics-Core
├─ Severity: CRITICAL
├─ Status: INVESTIGATING
├─ Assigned To: alice@helios.local
└─ MTTR: 15 minutes
```

### 8. SLA Compliance Calculations

Monthly tracking:

- Individual component SLA compliance
- Overall platform compliance
- Trend analysis (Quarterly/Annual)
- Breach documentation

### 9. Capacity Planning

Forecasts (30/90/180 days):

- CPU utilization trends
- Memory usage growth
- Disk space consumption
- Days to resource exhaustion
- Growth rate analysis

### 10. Correlative Analysis

Identifies:

- Components that fail together
- Dependency relationships
- Root cause propagation
- Common failure scenarios
- Incident frequency patterns

## 🔧 Configuration

### Alert Rules (config/alert-rules.json)

```json
{
  "name": "High Error Rate 5xx",
  "metric": "error_rate_5xx",
  "threshold": 1.0,
  "duration_seconds": 300,
  "severity": "CRITICAL",
  "notification_channels": ["email", "teams"]
}
```

### Components (config/components.json)

Define all monitored components with:

- Health endpoints
- Port numbers
- SLA targets
- Owner teams

### Notifications (config/notifications.json)

Configure:

- Email SMTP settings
- Teams webhook URLs
- Slack integration
- PagerDuty integration
- SMS providers

## 📈 Data Collection

### Collection Intervals

- Health Checks: Every 30 seconds
- Performance Metrics: Every 60 seconds
- System Metrics: Every 5 minutes
- Anomaly Detection: Every 15 minutes
- SLA Calculations: Every 1 hour
- Capacity Planning: Every 24 hours

### Data Retention

- Raw metrics: 30 days
- Aggregated metrics: 1 year
- Incidents: 2 years
- SLA records: 7 years (compliance)

## 🗄️ Database Schema

SQLite database with tables:

- `components` - Component registry
- `metrics` - Time-series metrics
- `health_checks` - Health check history
- `alerts` - Alert definitions and history
- `incidents` - Incident tracking
- `sla_tracking` - Monthly SLA records
- `anomalies` - Detected anomalies
- `correlations` - Component correlations
- `capacity_planning` - Forecasts

## 🎛️ Control Commands

### View Job Status

```powershell
Get-Job
Get-Job -Name "HealthCheck" | Format-List
```

### Stop Individual Component

```powershell
Stop-Job -Name "HealthCheck"
```

### View Job Output

```powershell
Get-Job -Name "HealthCheck" | Receive-Job
```

### View Recent Errors

```powershell
Get-Job -Name "AlertEvaluator" | Select-Object -Last 1 | Receive-Job
```

### Clean Up Jobs

```powershell
Get-Job | Stop-Job
Get-Job | Remove-Job
```

## 📊 Dashboard Sections

1. **Health Status** - Component availability
2. **Performance Metrics** - Real-time throughput/latency
3. **Active Alerts** - Current triggered alerts
4. **Open Incidents** - Active incident list
5. **SLA Compliance** - Compliance tracking
6. **Capacity Planning** - Resource forecasts
7. **Anomaly Detection** - Unusual patterns
8. **24h Trending** - Historical graphs
9. **Correlation Analysis** - Component relationships

## 🔐 Security

- HTTPS/TLS encryption for all communications
- API key authentication for endpoints
- Role-based access control (RBAC)
- Audit logging of all actions
- Secrets managed via Vault-Dynamics
- Encrypted incident data at rest

## 📋 Compliance Support

- **GDPR** - Data retention and privacy controls
- **HIPAA** - Audit logging and access control
- **SOC 2** - Monitoring evidence
- **PCI-DSS** - Security monitoring
- **ISO 27001** - Information security
- **FedRAMP** - Compliance tracking

## 🐛 Troubleshooting

### Dashboard Not Loading

```powershell
# Check if server is running
Get-Job -Name "DashboardServer"

# Check port availability
netstat -ano | findstr :8080

# Try different port
.\start-monitoring.ps1 -Port 8081
```

### Missing Metrics

```powershell
# Verify collection scripts are running
Get-Job -Name "PerformanceMetrics" | Receive-Job

# Check data files
Get-Content data\latest_performance_metrics.json
```

### Alert Not Triggering

```powershell
# Check alert evaluator
Get-Job -Name "AlertEvaluator" | Receive-Job

# Review alert configuration
Get-Content config\alert-rules.json
```

## 📞 Support & Help

For issues:

1. Check logs: `logs/monitoring.log`
2. Review component health: `data/latest_health_check.json`
3. View alert history: `data/alert_status.json`
4. Check incident status: `data/incidents_status.json`

## 📝 API Reference

### Health Endpoint

```
GET http://localhost:5000/health
Returns: { status: "healthy", timestamp: "...", components: [...] }
```

### Metrics Endpoint

```
GET http://localhost:5000/metrics
Returns: { throughput_rps, latency_p99, error_rate_5xx, cpu_percent, ... }
```

### Dashboard API

- `GET /api/health` - Overall health
- `GET /api/components` - Component list
- `GET /api/metrics/:component` - Component metrics
- `GET /api/alerts` - Current alerts
- `GET /api/incidents` - Incident list
- `GET /api/sla` - SLA tracking
- `POST /api/incidents` - Create incident

## 🎯 Next Steps

1. ✅ **Deploy System**: Run `start-monitoring.ps1`
2. ✅ **Configure Alerts**: Edit `config/alert-rules.json`
3. ✅ **Setup Notifications**: Configure channels in `config/notifications.json`
4. ✅ **Monitor Dashboard**: Access at `http://localhost:8080`
5. ✅ **Tune Thresholds**: Adjust baselines based on metrics
6. ✅ **Setup Escalation**: Configure on-call policies
7. ✅ **Enable Integrations**: PagerDuty, Slack, custom webhooks
8. ✅ **Archive Metrics**: Setup data retention policies

## 📄 License

HELIOS Platform Monitoring System © 2024
