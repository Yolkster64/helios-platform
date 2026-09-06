# HELIOS Platform - Troubleshooting Guide

Solutions for common issues, error codes, debugging techniques, and performance problems.

---

## 🆘 Common Issues

### Issue 1: Cannot Start HELIOS Service

**Symptom**: Running `helios start` returns an error

**Solutions**:

```powershell
# Check if port 8080 is already in use
netstat -ano | findstr :8080

# If port is in use, use a different port
helios config set platform.port 8081

# Restart the service
helios restart

# Check service status
helios status
```

**Related**: Check [Troubleshooting FAQ](../faq/TECHNICAL.md#service-startup)

---

### Issue 2: Dashboard Not Loading

**Symptom**: Browser shows "Connection refused" or blank page

**Solutions**:

```powershell
# Verify service is running
helios status

# Check service logs
helios logs --service=platform --error-only

# Verify port configuration
helios config get platform.port

# Try accessing with port number
# If port is 8080: http://localhost:8080
# If port is 8081: http://localhost:8081

# Clear browser cache and try again
# In browser: Ctrl+Shift+Delete
```

**Related**: Check [Dashboard Troubleshooting](./TROUBLESHOOTING.md#dashboard)

---

### Issue 3: Deployment Failed

**Symptom**: Deployment shows "Failed" status

**Solutions**:

```powershell
# Get detailed deployment status
helios deployment status <deployment-id> --verbose

# Check deployment logs
helios logs <deployment-id> --error-only

# View recent errors
helios logs <deployment-id> --level=error

# Retry deployment
helios deployment retry <deployment-id>

# Check if component exists
helios component list
```

**Common Causes**:

- Component not available
- Insufficient resources
- Configuration error
- Network connectivity

---

### Issue 4: High Memory Usage

**Symptom**: System consuming excessive memory

**Solutions**:

```powershell
# Check current resource usage
helios metrics system

# View memory breakdown
helios metrics memory --detailed

# Identify memory-heavy components
helios metrics components --sort-by=memory

# Optimize configuration
helios config set platform.cache.enabled false
helios restart

# Clear cache
helios cache clear
```

**Prevention**:

- Monitor regularly with `helios metrics`
- Review [Performance Tuning Guide](../user-guides/PERFORMANCE.md)

---

### Issue 5: API Connection Refused

**Symptom**: Cannot connect to API endpoint

**Solutions**:

```powershell
# Check API service status
helios status --service=api

# Verify API port configuration
helios config get platform.api.port

# Test API connectivity
curl http://localhost:8080/api/health

# Check firewall rules
Get-NetFirewallRule -DisplayName "*HELIOS*" | Format-List

# Restart API service
helios restart --service=api
```

---

## 🔍 Debugging Techniques

### Enable Debug Logging

```powershell
# Set logging level to debug
helios config set logging.level debug

# Restart service to apply
helios restart

# View debug logs
helios logs --level=debug
```

### Capture Service Logs

```powershell
# Export logs to file
helios logs --output=file --path=C:\HELIOS\logs\debug.log

# View specific time range
helios logs --since="2 hours ago" --until="now"

# Follow logs in real-time
helios logs --follow
```

### Monitor System Performance

```powershell
# View real-time metrics
helios metrics --watch --interval=5s

# Export metrics to file
helios metrics --output=csv --path=C:\HELIOS\metrics.csv

# Generate performance report
helios performance-report
```

### Test Connectivity

```powershell
# Test API endpoint
curl -v http://localhost:8080/api/health

# Test with authentication
curl -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/v1/status

# Test WebSocket
wscat -c ws://localhost:8080/ws
```

---

## ⚠️ Error Codes

| Code | Meaning | Solution |
|------|---------|----------|
| **E001** | Service not running | Run `helios start` |
| **E002** | Port already in use | Use different port |
| **E003** | Configuration error | Fix config file |
| **E004** | Component not found | Verify component exists |
| **E005** | Deployment timeout | Check network/resources |
| **E006** | Authentication failed | Verify token/credentials |
| **E007** | Authorization denied | Check user permissions |
| **E008** | Resource exhausted | Free up system resources |
| **E009** | Database connection failed | Check DB connectivity |
| **E010** | Cloud integration error | Verify cloud credentials |

---

## 🛠️ Performance Issues

### Slow API Response

```powershell
# Check API performance metrics
helios metrics api --detailed

# Identify slow endpoints
helios logs api --slow-queries

# Profile API calls
helios profile api --duration=60s

# Optimize database
helios optimize database

# Rebuild search index
helios reindex search
```

### High CPU Usage

```powershell
# Check CPU consumption by component
helios metrics components --sort-by=cpu

# Profile CPU usage
helios profile cpu --duration=60s

# Identify bottlenecks
helios analyze bottlenecks

# Optimize configuration
helios config tune --mode=performance
```

### Database Slow Queries

```powershell
# View slow query log
helios logs database --slow-only

# Analyze query performance
helios query-analyze <query-id>

# Optimize indexes
helios optimize-indexes

# Rebuild database
helios database rebuild
```

---

## 🔄 Recovery Procedures

### Service Recovery

```powershell
# Restart service gracefully
helios restart

# Force restart (if hung)
helios restart --force

# Restart specific service
helios restart --service=api

# Restart all services
helios restart --all
```

### Data Recovery

```powershell
# Check data integrity
helios database verify

# Repair database
helios database repair

# Restore from backup
helios database restore --backup=latest

# View backup history
helios backup list
```

### Configuration Recovery

```powershell
# Reset to defaults
helios config reset

# Restore previous configuration
helios config restore --version=previous

# View configuration history
helios config history
```

---

## 📋 Troubleshooting Checklist

Before contacting support:

- [ ] Service is running (`helios status` shows RUNNING)
- [ ] Port is accessible (verify firewall)
- [ ] Configuration is valid (`helios config validate`)
- [ ] Logs have been checked (`helios logs --error-only`)
- [ ] System resources are available (`helios metrics`)
- [ ] Restarted service (`helios restart`)
- [ ] Tried clearing cache (`helios cache clear`)
- [ ] Checked for updates (`helios update check`)

---

## 📞 Getting Help

### Check Documentation

- **Common Issues**: See above in this guide
- **Configuration**: See [Configuration Guide](../user-guides/CONFIGURATION.md)
- **API**: See [API Reference](../api/README.md)
- **FAQ**: See [FAQ](../faq/README.md)

### Collect Diagnostic Information

```powershell
# Generate diagnostic report
helios diagnose --output=report.zip

# Include in support request
# Contains: logs, metrics, configuration, system info
```

### Contact Support

Include:

1. HELIOS version (`helios --version`)
2. Error message and code
3. Steps to reproduce
4. Diagnostic report (see above)
5. System information (`Get-ComputerInfo`)

---

## 🔗 Related Documentation

- **[Performance Tuning](../user-guides/PERFORMANCE.md)** - Optimize performance
- **[FAQ](../faq/README.md)** - Frequently asked questions
- **[Monitoring Guide](../user-guides/MONITORING.md)** - Monitor your system
- **[Security Guide](../user-guides/SECURITY.md)** - Security best practices

---

**Last Updated:** 2026-04-16 | [Back to Main Documentation](../README.md)
