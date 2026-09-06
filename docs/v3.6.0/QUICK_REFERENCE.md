# HELIOS Platform v3.6.0 - Quick Reference Card

**Version**: 3.6.0 | **Updated**: 2026-05-15

## Common Tasks

### Cloud Synchronization

```
Enable sync:    Settings > Cloud Sync > Provider > Enable
Configure:      Settings > Cloud Sync > [Provider] > Options
Manual sync:    Dashboard > Cloud Sync > "Sync Now" button
View status:    Dashboard > Cloud Sync > Status & Statistics
Resolve conflicts: Dashboard > Cloud Sync > Conflicts > Resolve
```

### Plugin Management

```
Browse plugins:     Extensions > Plugin Marketplace
Install plugin:     Marketplace > [Plugin] > Install
View installed:     Extensions > Installed Plugins
Enable/disable:     Installed Plugins > [Toggle]
Configure:          Installed Plugins > [Plugin] > Configure
Uninstall:          Installed Plugins > [Plugin] > Uninstall
Update plugin:      Installed Plugins > [Update Available] > Update
View logs:          Installed Plugins > [Plugin] > Logs
```

### Dashboard

```
Access:           https://localhost:8080
Overview:         Dashboard > Overview (system metrics)
Performance:      Dashboard > Performance (CPU, Memory, Disk, Network)
Logs:             Dashboard > Logs (real-time log stream)
Plugins:          Dashboard > Plugins (installed plugins)
Custom views:     Dashboard > + Add View (create custom)
```

### Theme & Appearance

```
Switch theme:     Settings > Appearance > Theme > Light/Dark/Auto
Create custom:    Settings > Appearance > Custom Theme > Create
Edit theme:       Settings > Appearance > Themes > [Theme] > Edit
Apply theme:      Settings > Appearance > Themes > [Theme] > Apply
Color picker:     Click [#] button next to color field
```

### Health & Monitoring

```
Check health:     Dashboard > Health Status
View metrics:     Dashboard > Metrics > [Metric Type]
Alerts:           Dashboard > Alerts > Active Alerts
Health checks:    API: /api/health/status
Performance:      Dashboard > Performance > Analysis
```

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Dashboard refresh | F5 |
| Dark mode toggle | Ctrl+Shift+D |
| Clear logs | Ctrl+L |
| Export metrics | Ctrl+E |
| Settings | Ctrl+, |
| Help | F1 |

## Configuration Files

| File | Location | Purpose |
|------|----------|---------|
| appsettings.json | C:\ProgramData\HELIOS\config | Core settings |
| plugins.config | C:\ProgramData\HELIOS\config | Plugin configuration |
| cloud-sync.json | C:\ProgramData\HELIOS\config | Cloud sync settings |
| theme.json | C:\Users\[User]\AppData\Local\HELIOS | User theme preferences |

## Important Ports

| Service | Port | Protocol |
|---------|------|----------|
| Dashboard | 8080 | HTTPS |
| Core API | 8081 | HTTPS |
| Plugin IPC | 8082 | Named pipes |

## Troubleshooting Quick Guide

| Issue | Solution |
|-------|----------|
| Can't access dashboard | Verify HELIOS service running: `Get-Service HELIOS` |
| Cloud sync failing | Check credentials, internet, verify provider auth |
| Plugin won't load | Check compatibility, verify permissions, restart service |
| Dark mode not working | Clear browser cache (Ctrl+Shift+Delete), hard refresh |
| High CPU usage | Check plugin logs, disable problematic plugin |
| Dashboard slow | Reduce log retention, clear cache, check disk space |

## API Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| /api/health/status | GET | System health status |
| /api/metrics/current | GET | Current system metrics |
| /api/cloud/sync | POST | Start synchronization |
| /api/plugins/list | GET | List installed plugins |
| /api/plugins/{id}/execute | POST | Execute plugin command |

## Version Information

- **Current Version**: 3.6.0
- **Release Date**: 2026-05-15
- **.NET Runtime**: 8.0+
- **Windows**: 11 Pro / Server 2022+
- **Disk Space**: 2GB app + 5GB+ cache
- **RAM**: 4GB minimum, 8GB recommended

## Contact & Support

- **Documentation**: docs/v3.6.0/
- **GitHub Issues**: github.com/M0nado/helios-platform/issues
- **Discussions**: discussions.github.com/M0nado/helios-platform
- **Email**: support@helios-platform.io
- **Status**: https://status.helios-platform.io

---

**Print this card for quick reference!**
