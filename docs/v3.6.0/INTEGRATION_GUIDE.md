# HELIOS Platform v3.6.0 - Integration Guides

**Version**: 3.6.0

## Cloud Provider Integration

### OneDrive Setup

1. Register Azure AD application at portal.azure.com
2. Configure HELIOS with Client ID, Secret, and Tenant ID
3. Enable sync in Settings > Cloud Sync
4. Complete OAuth flow on first sync

### Azure Storage Setup

1. Create Storage Account in Azure
2. Copy Connection String from Access Keys
3. Configure in HELIOS Cloud Sync settings
4. Test connection and enable auto-sync

### AWS S3 Integration

1. Create IAM user with S3 permissions
2. Generate Access Key and Secret Key
3. Configure in HELIOS Cloud Sync settings
4. Select appropriate AWS region
5. Enable encryption (AES-256 recommended)

## Plugin Marketplace Integration

- Browse plugins at plugins.helios-platform.io
- One-click install directly from HELIOS
- View ratings, reviews, and documentation
- Auto-update support

## Telemetry Integration

Track usage and events:

```json
{
  "telemetry": {
    "enabled": true,
    "endpoint": "https://telemetry.helios-platform.io",
    "batchSize": 100
  }
}
```

## Third-Party Services

### Slack Integration

Send alerts to Slack channels:

```csharp
var slack = new SlackNotificationService(webhookUrl);
await slack.SendAlertAsync(alert);
```

### PagerDuty Integration

Create incidents automatically:

```csharp
var pagerDuty = new PagerDutyIncidentService(integrationKey);
await pagerDuty.CreateIncidentAsync(incident);
```

### Email Integration

Configure SMTP for alerts:

```csharp
var email = new EmailService(smtpConfig);
await email.SendAsync(message);
```

## Custom Theme Creation

1. Define ColorScheme (primary, background, text colors)
2. Configure Typography (font, size, line height)
3. Create ThemeDefinition
4. Register with ThemeManager
5. Apply theme in Settings

## ML Model Integration

### Load External Models

```csharp
var mlService = new MLService();
await mlService.RegisterModelAsync(modelMetadata);
```

### Model Serving

Supports TensorFlow SavedModel, ONNX, PyTorch formats.

### Custom Inference Engines

Implement IInferenceEngine for custom model types.

---

See docs/v3.6.0/FEATURES_GUIDE.md for detailed code examples.
