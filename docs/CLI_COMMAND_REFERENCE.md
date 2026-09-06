# HELIOS Platform - CLI Command Reference

## Overview

The HELIOS Platform Command-Line Interface (CLI) provides powerful tools for system management, deployment, and monitoring.

## Table of Contents

1. [Basic Commands](#basic-commands)
2. [Deployment Commands](#deployment-commands)
3. [Configuration Commands](#configuration-commands)
4. [Monitoring Commands](#monitoring-commands)
5. [System Commands](#system-commands)
6. [Help & Support](#help--support)

---

## Basic Commands

### `helios help`

Display general help information and command listing.

```bash
helios help
```

**Output:**

```
═══════════════════════════════════════════════════════════
  HELIOS Platform v1.0.0
═══════════════════════════════════════════════════════════

Usage: helios [command] [options]

Commands:
  help           Show this help message
  version        Display application version
  status         Check system status
  deploy         Deploy HELIOS to cloud provider
  config         Manage configuration
  monitor        Monitor system metrics
  logs           View system logs
```

### `helios version`

Display application version and build information.

```bash
helios version
```

**Output:**

```
✓ HELIOS Platform v1.0.0
  Build: 20260417
  Release: Stable
  Copyright © 2026 HELIOS. All rights reserved.
```

### `helios status`

Check the current status of all system components.

```bash
helios status
```

**Output:**

```
═══════════════════════════════════════════════════════════
  System Status
═══════════════════════════════════════════════════════════

Component              Status       Version    Last Check
────────────────────────────────────────────────────────────
Core Engine            ✓ OK         1.0.0      1m ago
Cloud Sync             ✓ OK         1.0.0      2m ago
Database              ✓ OK         latest     1m ago
Security Module       ✓ OK         1.0.0      45s ago
```

---

## Deployment Commands

### `helios deploy [provider] [options]`

Deploy HELIOS Platform to specified cloud provider.

**Supported Providers:**

- `azure` - Microsoft Azure
- `aws` - Amazon Web Services
- `gcp` - Google Cloud Platform
- `local` - Local deployment

**Options:**

```
--config PATH         Path to deployment configuration file
--region REGION       Target deployment region
--env ENVIRONMENT     Environment (dev, staging, prod)
--force              Skip confirmation prompts
--verbose            Enable verbose output
```

**Examples:**

```bash
# Deploy to Azure with interactive prompts
helios deploy azure --env prod

# Deploy to AWS with specific configuration
helios deploy aws --config production.yaml --region us-east-1

# Local development deployment
helios deploy local --env dev --verbose
```

**Output Example:**

```
ℹ Preparing deployment to Azure...
✓ Configuration validated
ℹ Provisioning resources...
[████████████████░░░░░░░░░░░░░░░░░░] 50% (5/10)
✓ Cloud services provisioned
ℹ Deploying application...
[██████████████████████████████████] 100% (10/10)
✓ Deployment completed successfully
```

---

## Configuration Commands

### `helios config set [key] [value]`

Set a configuration parameter.

```bash
# Set API endpoint
helios config set api.endpoint "https://api.helios.cloud"

# Set cache TTL (in seconds)
helios config set cache.ttl 3600

# Enable debug mode
helios config set debug.enabled true
```

### `helios config get [key]`

Retrieve a configuration value.

```bash
# Get current API endpoint
helios config get api.endpoint

# Get all security settings
helios config get security.*
```

### `helios config list`

List all current configuration settings.

```bash
helios config list
```

**Output Example:**

```
ℹ Current Configuration
────────────────────────────────────────────────────────────
api.endpoint          https://api.helios.cloud
api.timeout           30000 ms
cache.enabled         true
cache.ttl             3600 s
debug.enabled         false
security.tls          1.3
logging.level         INFO
```

### `helios config validate`

Validate current configuration for errors.

```bash
helios config validate
```

**Output Examples:**

Success:

```
✓ Configuration is valid
✓ All required parameters present
✓ No conflicts detected
```

With Warnings:

```
⚠ Configuration validation completed with warnings
⚠ WARNING: SSL certificate will expire in 30 days
⚠ WARNING: Cache TTL below recommended minimum
✓ No errors found
```

---

## Monitoring Commands

### `helios monitor [interval]`

Monitor real-time system metrics.

```bash
# Monitor with 2-second refresh interval
helios monitor 2

# Monitor with default 5-second interval
helios monitor
```

**Output Example:**

```
═══════════════════════════════════════════════════════════
  System Metrics (Refresh: 2s)  [14:30:45]
═══════════════════════════════════════════════════════════

CPU Usage:        42%  ████████░░░░░░░░░░░░
Memory Usage:     65%  █████████████░░░░░░░░
Network I/O:      120 MB/s  ↓  95 MB/s  ↑
Active Services:  8/10
Request Queue:    234
Average Latency:  42ms
```

### `helios logs [filter] [options]`

View system logs with filtering and search capabilities.

**Options:**

```
--level LEVEL        Filter by log level (error, warning, info, debug)
--component COMP     Filter by component name
--since TIME         Show logs since specified time (1h, 30m, etc.)
--follow, -f         Follow log output in real-time
--lines N            Show last N lines (default: 50)
```

**Examples:**

```bash
# Show last 100 log lines
helios logs --lines 100

# Show error logs from last hour
helios logs --level error --since 1h

# Follow API Gateway logs in real-time
helios logs --component ApiGateway --follow

# Show all warnings from last 30 minutes
helios logs --level warning --since 30m
```

**Output Example:**

```
═══════════════════════════════════════════════════════════
  System Logs (Level: info)
═══════════════════════════════════════════════════════════

[14:30:45] ✓ Core Engine     - System initialized
[14:30:46] ℹ Cloud Sync      - Connecting to provider...
[14:30:47] ✓ Cloud Sync      - Connected (latency: 45ms)
[14:30:48] ℹ Database        - Running migration 001
[14:30:50] ✓ Database        - Migration completed
[14:30:51] ✓ Security Module - All checks passed
```

---

## System Commands

### `helios health-check`

Run comprehensive system health check.

```bash
helios health-check
```

**Output Example:**

```
═══════════════════════════════════════════════════════════
  System Health Check
═══════════════════════════════════════════════════════════

Database Connectivity        ✓ OK
API Endpoints                ✓ OK
Cloud Credentials            ✓ OK
SSL Certificates             ✓ OK (expires: 2027-04-15)
Disk Space                   ✓ OK (85% used)
Memory Availability          ✓ OK (4.2 GB available)
Network Connectivity         ✓ OK (latency: 15ms)

Overall Status:              ✓ HEALTHY
```

### `helios update`

Check for and install updates.

```bash
# Check for updates
helios update --check

# Install latest updates
helios update

# Install specific version
helios update --version 1.0.1
```

### `helios info`

Display detailed system information.

```bash
helios info
```

**Output Example:**

```
═══════════════════════════════════════════════════════════
  HELIOS Platform - System Information
═══════════════════════════════════════════════════════════

Application:
  Name               HELIOS Platform
  Version            1.0.0
  Build              20260417
  Install Path       C:\Program Files\HELIOS

System:
  OS                 Windows Server 2022
  Architecture       x64
  Processor          Intel Xeon Platinum 8280
  Total Memory       32 GB
  Available Memory   8.4 GB

Configuration:
  Config Path        %APPDATA%\HELIOS\config.yaml
  Logs Path          %APPDATA%\HELIOS\logs
  Cache Enabled      true
  Debug Mode         false

Network:
  Primary Endpoint   https://api.helios.cloud
  Latency            45ms
  Status             Connected
```

---

## Help & Support

### `helios help [command]`

Show detailed help for a specific command.

```bash
# Get help for deploy command
helios help deploy

# Get help for config command
helios help config
```

### Keyboard Shortcuts (Interactive Mode)

| Shortcut | Action |
|----------|--------|
| `Ctrl+C` | Cancel current operation |
| `Ctrl+L` | Clear screen |
| `↑ / ↓` | Command history navigation |
| `Tab` | Auto-complete command |
| `?` | Show help |
| `Q` | Quit application |

### Common Troubleshooting

**"Connection refused" error:**

```bash
# Check service status
helios status

# Verify configuration
helios config validate

# Check network connectivity
helios health-check
```

**"Permission denied" error:**

```bash
# Run as administrator
helios --admin [command]

# Or on Linux/Mac:
sudo helios [command]
```

**Performance issues:**

```bash
# Monitor system metrics
helios monitor

# Check logs for errors
helios logs --level error --follow

# Run health check
helios health-check
```
