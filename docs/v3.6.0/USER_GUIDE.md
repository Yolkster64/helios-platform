# HELIOS Platform v3.6.0 - User Guide

**Version**: 3.6.0

## Getting Started with v3.6.0

### System Requirements

- Windows 11 Pro or Server 2022+
- 4GB RAM minimum (8GB recommended)
- 10GB disk space
- .NET 8.0 or later
- Stable internet connection

### Installation

1. Download HELIOS-Platform-v3.6.0-Setup.exe
2. Run as administrator
3. Follow setup wizard
4. Accept default paths or customize
5. HELIOS launches automatically

## Cloud Sync Setup Wizard

1. Navigate to Settings > Cloud Synchronization
2. Click "Setup New Provider"
3. Choose provider (OneDrive/Azure/AWS S3)
4. Authenticate with your account
5. Configure sync paths and exclusions
6. Review settings and start sync

## Installing & Managing Plugins

1. Go to Extensions > Plugin Marketplace
2. Browse or search for plugins
3. Click "Install" to add plugin
4. Review permissions and confirm
5. Plugin loads automatically

**Manage Installed Plugins:**

- View list in Extensions > Installed Plugins
- Enable/disable with checkbox
- Update when available
- Uninstall if needed
- Configure settings per plugin

## Using the Developer Dashboard

1. Open https://localhost:8080
2. Enter administrator credentials
3. Dashboard shows system overview
4. Navigate tabs for details:
   - Overview: System metrics
   - Performance: Historical data
   - Logs: Real-time log viewing
   - Plugins: Installed plugins
   - Analytics: Usage trends

## Customizing Dark Mode

1. Go to Settings > Appearance > Theme
2. Choose:
   - **Auto**: Follow system setting
   - **Dark**: Always dark mode
   - **Light**: Always light mode
3. For custom colors, click Create Theme
4. Adjust primary/secondary/accent colors
5. Save and apply theme

## Troubleshooting Guide

**Cloud sync not working:**

- Check internet connectivity
- Verify cloud credentials in Settings
- Check file permissions
- Review sync logs in Dashboard

**Plugin issues:**

- Check compatibility with v3.6.0
- Review plugin logs
- Try reinstalling from marketplace
- Check plugin configuration

**Dashboard access problems:**

- Verify HELIOS service running
- Check port 8080 not blocked by firewall
- Clear browser cache
- Try different browser

**Dark mode not applying:**

- Clear browser cache
- Hard refresh (Ctrl+Shift+R)
- Restart dashboard service

---

For detailed troubleshooting, see docs/v3.6.0/DEPLOYMENT.md.
