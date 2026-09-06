# Studio Dashboard - Quick Reference Guide

## 🚀 Getting Started (5 minutes)

### Basic Usage

```csharp
using HELIOS.Platform.Presentation.Studio.Services;
using HELIOS.Platform.Presentation.Studio.Models;

// 1. Initialize dashboard
var dashboard = new StudioDashboardService();
await dashboard.InitializeAsync();

// 2. Collect metrics
var metrics = dashboard.CollectMetrics();
Console.WriteLine($"CPU: {metrics.CpuUsagePercent}%");

// 3. Get system status
var status = dashboard.GetStatus();
Console.WriteLine($"Health: {status.OverallHealth}");
```

## 📊 Service Reference

### Core Services (Task 2.1)

```csharp
// Dashboard Service
var dashboard = new StudioDashboardService();
await dashboard.InitializeAsync();
var metrics = dashboard.CollectMetrics();
var status = dashboard.GetStatus();
dashboard.Shutdown();

// Alerts
var alert = dashboard.CreateAlert(AlertSeverity.Warning, "Title", "Message");
dashboard.ResolveAlert(alert.Id);
var alerts = dashboard.GetAlerts(activeOnly: true);

// Users
var user = dashboard.CreateOrUpdateUser("user1", "User One", "user@example.com");
dashboard.DeleteUser("user1");
var users = dashboard.GetUsers();

// Settings
var settings = dashboard.GetSettings();
dashboard.UpdateSettings(new DashboardSettings { RefreshIntervalSeconds = 10 });
```

### Advanced Services (Task 2.2)

```csharp
// Performance Graphs
var graph = new PerformanceGraphService();
graph.RecordMetric("CPU", 45.5);
graph.RecordMetricsSnapshot(metrics);
var hourly = graph.GetHourlyGraph("CPU");
var daily = graph.GetDailyGraph("Memory");
var weekly = graph.GetWeeklyGraph("Disk");
var stats = graph.GetMetricStatistics("CPU", TimeSpan.FromHours(24));

// Alert Management
var alerts = new AlertManagementService();
var config = alerts.CreateAlertConfig("High CPU", 
    new AlertCondition { MetricType = "CPU", Operator = "GreaterThan", Threshold = 80 },
    new AlertAction { ActionType = "Notification" }
);
await alerts.ExecuteAlertActionAsync(config);

// Reports
var reports = new ReportGenerator(graph);
var report = reports.GenerateDailyReport();
var html = reports.ExportToHtml(report);
var csv = reports.ExportToCSV(report);

// Customization
var customizer = new DashboardCustomizer();
var layout = customizer.CreateLayout("My Dashboard");
customizer.SetTheme("Dark");
customizer.AddWidgetToLayout(layout.Id, new DashboardWidget { Type = "CPU" });
```

### Analytics Services (Task 2.3)

```csharp
// Analytics Engine
var analytics = new AnalyticsEngine();
analytics.RecordMetric("CPU", 50);
analytics.RecordSnapshot(metrics);
var result = analytics.GetAnalytics("CPU", TimeSpan.FromHours(1));
var peaks = analytics.GetPeakUsage("Memory", topN: 5);
var correlation = analytics.AnalyzeCorrelation("CPU", "Memory", TimeSpan.FromHours(1));

// Predictions
var predictor = new PredictiveAnalytics(analytics);
var prediction = predictor.PredictMetric("CPU", TimeSpan.FromHours(1));
var exhaustion = predictor.PredictResourceExhaustion("Memory", threshold: 90);

// Capacity Forecasting
var forecaster = new CapacityForecaster(analytics);
var forecast = forecaster.GenerateCapacityForecast("Disk", daysAhead: 30);
var risk = forecaster.AnalyzeCapacityRisk("Memory");

// Anomaly Detection
var detector = new AnomalyDetector(analytics);
var anomalies = detector.DetectAnomalies("CPU", TimeSpan.FromHours(1));
```

### Cloud Services (Task 2.4)

```csharp
// Cloud Integration
var cloud = new CloudIntegrationService();
var provider = cloud.RegisterProvider(CloudProviderType.Azure, "My Azure",
    new Dictionary<string, string> { { "clientId", "..." } });
await cloud.ConnectToProviderAsync(provider.Id);
bool connected = await cloud.TestConnectionAsync(provider.Id);

// API Client
var apiClient = new ThirdPartyApiClient();
var endpoint = apiClient.RegisterEndpoint("MyAPI", "https://api.example.com", ApiProtocol.REST);
var response = await apiClient.MakeRequestAsync(endpoint.Id, 
    new ApiRequest { Path = "/data", Method = "GET" });

// Webhooks
var webhooks = new WebhookService();
var webhook = webhooks.RegisterWebhook("Alert Webhook", "https://example.com/alerts",
    new List<string> { "alert.triggered" });
await webhooks.TriggerWebhookAsync("alert.triggered", new { severity = "high" });

// Extensions
var extensions = new ExtensionFramework();
var ext = await extensions.LoadExtensionAsync("my-extension.dll");
await extensions.ExecuteHookAsync("OnDashboardLoad");
```

## 📋 Common Tasks

### Monitor CPU Usage

```csharp
var dashboard = new StudioDashboardService();
var metrics = dashboard.CollectMetrics();
if (metrics.CpuUsagePercent > 80)
{
    var alert = dashboard.CreateAlert(
        AlertSeverity.Critical,
        "High CPU",
        $"CPU at {metrics.CpuUsagePercent}%"
    );
}
```

### Create Daily Report

```csharp
var graph = new PerformanceGraphService();
var generator = new ReportGenerator(graph);
var report = generator.GenerateDailyReport("Daily Performance");
string html = generator.ExportToHtml(report);
File.WriteAllText("report.html", html);
```

### Analyze Trends

```csharp
var analytics = new AnalyticsEngine();
for (int i = 0; i < 100; i++)
{
    analytics.RecordMetric("Memory", 40 + i * 0.5);
}
var stats = analytics.GetAnalytics("Memory", TimeSpan.FromHours(24));
Console.WriteLine($"Average: {stats.Mean:F2}%");
Console.WriteLine($"Peak: {stats.Max:F2}%");
```

### Detect Anomalies

```csharp
var analytics = new AnalyticsEngine();
var detector = new AnomalyDetector(analytics);
var anomalies = detector.DetectAnomalies("CPU", TimeSpan.FromHours(1));
foreach (var anomaly in anomalies)
{
    Console.WriteLine($"Anomaly: {anomaly.Description}");
}
```

### Forecast Capacity

```csharp
var analytics = new AnalyticsEngine();
var forecaster = new CapacityForecaster(analytics);
var forecast = forecaster.GenerateCapacityForecast("Disk", 30);
var risk = forecaster.AnalyzeCapacityRisk("Disk");
Console.WriteLine($"Risk: {risk.CurrentRiskLevel}");
Console.WriteLine($"Recommendation: {risk.RecommendedAction}");
```

## 🔧 Configuration

### Settings

```csharp
var dashboard = new StudioDashboardService();
var settings = new DashboardSettings
{
    RefreshIntervalSeconds = 5,
    EnableNotifications = true,
    EnableDarkMode = false,
    CpuAlertThreshold = 80,
    MemoryAlertThreshold = 85,
    DiskAlertThreshold = 90,
    MaxHistoryDays = 30,
    Theme = "Light"
};
dashboard.UpdateSettings(settings);
```

### Alert Configuration

```csharp
var alertService = new AlertManagementService();
var config = new AlertConfiguration
{
    Name = "High Memory",
    Condition = new AlertCondition
    {
        MetricType = "Memory",
        Operator = "GreaterThan",
        Threshold = 85
    },
    Action = new AlertAction
    {
        ActionType = "Email",
        Email = "admin@example.com",
        Title = "High Memory Alert"
    },
    IsEnabled = true
};
```

## 📈 Metrics Reference

### Available Metrics

- `CPU` - Processor utilization (%)
- `Memory` - RAM usage (%)
- `Disk` - Storage usage (%)
- `Network` - Bytes per second
- `GPU` - Graphics processor usage (%)

### Operators

- `GreaterThan` (>)
- `LessThan` (<)
- `GreaterOrEqual` (>=)
- `LessOrEqual` (<=)
- `Equal` (=)

### Severity Levels

- `Info` - Informational
- `Warning` - Needs attention
- `Critical` - Urgent
- `Error` - System error

## 🔌 Events

```csharp
var dashboard = new StudioDashboardService();

// Metrics Updated
dashboard.MetricsUpdated += (s, metrics) => 
    Console.WriteLine($"CPU: {metrics.CpuUsagePercent}%");

// Alert Raised
dashboard.AlertRaised += (s, alert) => 
    Console.WriteLine($"Alert: {alert.Title}");

// Status Changed
dashboard.StatusChanged += (s, status) => 
    Console.WriteLine($"Health: {status.OverallHealth}");
```

## 🧪 Testing

```csharp
[Fact]
public void MetricsCollection_Should_Return_Valid_Data()
{
    var dashboard = new StudioDashboardService();
    var metrics = dashboard.CollectMetrics();
    
    Assert.NotNull(metrics);
    Assert.True(metrics.CpuUsagePercent >= 0 && metrics.CpuUsagePercent <= 100);
}
```

## 📚 Resources

- **README**: `src/HELIOS.Platform/Presentation/Studio/README.md`
- **Tests**: `tests/HELIOS.Platform.Tests/Presentation/Studio/StudioTests.cs`
- **Phase 2 Report**: `PHASE_2_COMPLETION_REPORT.md`

## 💡 Tips & Tricks

1. **Record metrics continuously** for better trend analysis
2. **Use alerts with email** for critical thresholds
3. **Export reports regularly** for auditing
4. **Clear old data** periodically to save memory
5. **Enable dark mode** for late-night monitoring
6. **Create custom layouts** for different roles
7. **Use webhooks** for external integrations
8. **Extend with plugins** for custom functionality

## ⚡ Performance Tips

- Collect metrics in background task
- Use async/await for non-blocking operations
- Cache frequently accessed data
- Clean up old alerts and reports regularly
- Load extensions selectively
- Configure refresh intervals appropriately

## 🆘 Troubleshooting

**High Memory Usage**

- Clear old alerts: `dashboard.ClearOldAlerts(7)`
- Clear old data: `analytics.ClearOldData(7)`

**Slow Dashboard**

- Increase refresh interval
- Reduce number of active widgets
- Review extension count

**Metrics Not Updating**

- Verify service initialization
- Check system permissions
- Review event subscribers

---

**Quick Ref Version**: 1.0
**Last Updated**: April 16, 2026
**For Phase 2 Studio Subsystem**
