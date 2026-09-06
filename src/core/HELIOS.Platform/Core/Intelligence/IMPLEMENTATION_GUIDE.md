# Phase 3 Tier 1 - ML Intelligence Services Implementation Guide

## Overview

This document describes the implementation of Phase 3 Tier 1 - ML Intelligence Services for the HELIOS Platform. All 7 ML services have been fully implemented with comprehensive testing, async/await patterns, thread safety, and performance optimization.

## Implemented Services

### 1. DataCollector (`DataCollector.cs`)

- **Purpose**: Aggregates metrics from all services in real-time
- **Key Features**:
  - Register metric sources dynamically
  - Collect metrics from multiple sources concurrently
  - Track collection statistics and performance metrics
  - Thread-safe with SemaphoreSlim(1,1)
  - Comprehensive logging

**Interface**: `IDataCollector`

**Key Methods**:

- `CollectMetricsAsync()` - Collects all registered metrics
- `RegisterMetricSourceAsync()` - Registers a new metric source
- `UnregisterMetricSourceAsync()` - Removes a metric source
- `GetCollectionStatsAsync()` - Returns collection statistics

### 2. DataNormalizer (`DataNormalizer.cs`)

- **Purpose**: Standardizes metrics for ML processing using Z-score normalization
- **Key Features**:
  - Z-score normalization for standardization
  - Metric bounds registration and tracking
  - Historical data management
  - Statistical calculations (mean, stdev, etc.)
  - Automatic history management with max 1000 points per metric

**Interface**: `IDataNormalizer`

**Key Methods**:

- `NormalizeAsync()` - Applies Z-score normalization
- `RegisterMetricBoundsAsync()` - Sets min/max bounds for metrics
- `GetNormalizationStatsAsync()` - Returns normalization statistics
- `ClearHistoryAsync()` - Resets all historical data

### 3. FeatureExtractor (`FeatureExtractor.cs`)

- **Purpose**: Extracts statistical features from time-series data
- **Key Features**:
  - 13+ statistical features (Mean, StdDev, Skewness, Kurtosis, etc.)
  - Moving average calculation
  - Trend slope via linear regression
  - Seasonal component extraction
  - Quartile calculations
  - Performance timing included

**Interface**: `IFeatureExtractor`

**Key Methods**:

- `ExtractFeaturesAsync()` - Extracts comprehensive feature set
- `ExtractMovingAverageAsync()` - Calculates moving averages
- `CalculateTrendSlopeAsync()` - Linear regression slope
- `ExtractSeasonalComponentsAsync()` - Seasonal indices and strength

### 4. InMemoryTimeSeriesDB (`InMemoryTimeSeriesDB.cs`)

- **Purpose**: Fast in-memory time-series database for metric storage and retrieval
- **Key Features**:
  - Thread-safe concurrent storage
  - Time-range queries with efficient filtering
  - Aggregate statistics (min, max, avg, count, stdev)
  - Automatic data purging for old entries
  - Max 10,000 points per series limit
  - Fast query performance (<100ms typical)

**Interface**: `ITimeSeriesDB`

**Key Methods**:

- `StoreAsync()` - Stores a data point with timestamp
- `QueryAsync()` - Retrieves points within a time range
- `GetRecentAsync()` - Gets latest N data points
- `GetAggregateStatsAsync()` - Calculates aggregate statistics
- `PurgeOldDataAsync()` - Removes expired data points

### 5. AnomalyDetector (`AnomalyDetector.cs`)

- **Purpose**: Detects anomalies in data using statistical methods
- **Key Features**:
  - Z-score based anomaly detection with configurable sensitivity
  - Model training on historical data
  - Batch anomaly detection
  - Sigmoid-based probability scoring (0-1)
  - Detection statistics and metrics
  - Supports sensitivity levels 1-10

**Interface**: `IAnomalyDetector`

**Key Methods**:

- `DetectAnomalyAsync()` - Single-value anomaly detection with score
- `DetectBatchAnomaliesAsync()` - Batch processing of multiple values
- `TrainModelAsync()` - Trains detector on historical data
- `GetDetectionStatsAsync()` - Returns detection metrics

### 6. PredictiveAnalytics (`PredictiveAnalytics.cs`)

- **Purpose**: Forecasts trends and predicts future values
- **Key Features**:
  - Linear regression-based trend prediction
  - Confidence interval calculation
  - Peak value forecasting
  - Threshold breach probability prediction
  - Multiple confidence levels (90%, 95%, 99%)
  - Automatic historical data management

**Interface**: `IPredictiveAnalytics`

**Key Methods**:

- `PredictTrendAsync()` - Forecasts future values
- `GetPredictionConfidenceIntervalsAsync()` - Calculates confidence bands
- `ForecastPeakAsync()` - Predicts peak value and time
- `PredictThresholdBreachAsync()` - Calculates breach probability

### 7. MLModelManager (`MLModelManager.cs`)

- **Purpose**: Manages ML model lifecycle including training, evaluation, and auto-retraining
- **Key Features**:
  - Model creation and registration
  - Training and retraining capabilities
  - Performance evaluation with multiple metrics
  - Automatic degradation detection and retraining
  - Model metadata tracking
  - Metrics: Accuracy, Precision, Recall, F1Score, Loss

**Interface**: `IMLModelManager`

**Key Methods**:

- `CreateModelAsync()` - Creates and registers a new model
- `TrainModelAsync()` - Trains/retrains a model
- `EvaluateModelAsync()` - Evaluates model on test data
- `GetModelInfoAsync()` - Retrieves model metadata
- `DeleteModelAsync()` - Removes a model
- `AutoRetrainDegradedModelsAsync()` - Auto-retrains low-accuracy models

## Architecture & Design Patterns

### Thread Safety

All services use `SemaphoreSlim(1,1)` for thread-safe operations:

```csharp
private readonly SemaphoreSlim _semaphore = new(1, 1);

public async Task SomeMethodAsync()
{
    await _semaphore.WaitAsync();
    try
    {
        // Thread-safe operation
    }
    finally
    {
        _semaphore.Release();
    }
}
```

### Async/Await Throughout

All I/O and potentially long-running operations use async/await:

```csharp
public async Task<Dictionary<string, double>> CollectMetricsAsync()
{
    var metrics = new Dictionary<string, double>();
    foreach (var source in _metricSources)
    {
        var value = await source.Value(); // Async metric collection
        metrics[source.Key] = value;
    }
    return metrics;
}
```

### Resource Management

All services implement `IDisposable` with proper cleanup:

```csharp
public class Service : IDisposable
{
    private bool _disposed;
    private readonly SemaphoreSlim _semaphore = new(1, 1);

    public void Dispose()
    {
        if (_disposed) return;
        _semaphore?.Dispose();
        _disposed = true;
    }

    private void ThrowIfDisposed()
    {
        if (_disposed)
            throw new ObjectDisposedException(nameof(Service));
    }
}
```

### Logging Integration

All services use `ILogger<T>` for comprehensive logging:

```csharp
private readonly ILogger<DataCollector> _logger;

public DataCollector(ILogger<DataCollector> logger)
{
    _logger = logger ?? throw new ArgumentNullException(nameof(logger));
    _logger.LogInformation("DataCollector initialized");
}
```

## Dependency Injection Setup

### Service Registration

Register all ML Intelligence services using the extension method:

```csharp
// In your service configuration:
services.AddMLIntelligenceServices();

// Or with custom options:
services.AddMLIntelligenceServices(options =>
{
    options.MaxNormalizationHistorySize = 2000;
    options.MaxTimeSeriesPoints = 20000;
    options.DefaultAnomalySensitivity = 7;
    options.DefaultConfidenceLevel = 0.99;
});
```

### Usage Example

```csharp
public class MyService
{
    private readonly IDataCollector _collector;
    private readonly ITimeSeriesDB _db;
    private readonly IAnomalyDetector _detector;

    public MyService(
        IDataCollector collector,
        ITimeSeriesDB db,
        IAnomalyDetector detector)
    {
        _collector = collector;
        _db = db;
        _detector = detector;
    }

    public async Task MonitorMetricsAsync()
    {
        // Collect metrics
        var metrics = await _collector.CollectMetricsAsync();

        // Store in time-series database
        foreach (var metric in metrics)
        {
            await _db.StoreAsync("metrics", metric.Value);
        }

        // Detect anomalies
        var recent = await _db.GetRecentAsync("metrics", 10);
        var recentValues = recent.Select(r => r.Item2).ToList();
        
        // Train and detect
        await _detector.TrainModelAsync("metrics", recentValues);
        var score = await _detector.DetectAnomalyAsync("metrics", metrics["cpu"]);
        
        if (score > 0.7)
        {
            // Handle anomaly
        }
    }
}
```

## Performance Characteristics

### Target Performance

- Data Collection: <100ms for 50+ metrics
- Time-Series Query: <100ms for 1000+ points
- Feature Extraction: <100ms for 1000+ data points
- Anomaly Detection: <50ms per value
- Prediction: <100ms for trend calculation

### Resource Usage

- Memory: ~1MB per 10,000 time-series data points
- CPU: Minimal overhead with async patterns
- Lock Contention: Minimal with SemaphoreSlim

## Testing

### Test Coverage

- 25+ comprehensive unit tests
- Integration tests for end-to-end workflows
- Performance benchmarks
- All services tested with mock loggers

### Test Location

`Tests/HELIOS.Platform.Tests/Intelligence/MLIntelligenceServicesTests.cs`

### Running Tests

```bash
dotnet test Tests/HELIOS.Platform.Tests/HELIOS.Platform.Tests.csproj --filter "MLIntelligence"
```

## Caching Integration (Phase 4)

Services are designed to support Phase 4 caching:

- L1 Cache: 5-minute TTL for normalized data
- L2 Cache: 1-hour TTL for predictions and models
- Easy integration with ICacheService interface

### Planned Cache Integration

```csharp
public class CachedDataCollector : IDataCollector
{
    private readonly IDataCollector _inner;
    private readonly ICacheService _cache;

    public async Task<Dictionary<string, double>> CollectMetricsAsync()
    {
        var cacheKey = "metrics:collected";
        var cached = await _cache.GetAsync<Dictionary<string, double>>(cacheKey);
        if (cached != null) return cached;

        var result = await _inner.CollectMetricsAsync();
        await _cache.SetAsync(cacheKey, result, TimeSpan.FromMinutes(5));
        return result;
    }
}
```

## Error Handling & Graceful Degradation

All services include:

- Exception handling for individual metric collection failures
- Null argument validation
- Disposed object detection
- Graceful fallbacks (e.g., zero anomaly score if model not trained)
- Comprehensive error logging

## Future Enhancements

1. **Real-time Streaming**: WebSocket support for streaming metrics
2. **Model Persistence**: Save/load trained models from disk
3. **Distributed Caching**: Redis integration for multi-instance deployments
4. **Advanced ML**: Integration with ML.NET for more sophisticated models
5. **Visualization**: Time-series charting and dashboards
6. **Custom Features**: Plugin system for domain-specific feature extraction

## File Structure

```
src/HELIOS.Platform/Core/Intelligence/
├── Interfaces/
│   ├── IDataCollector.cs
│   ├── IDataNormalizer.cs
│   ├── IFeatureExtractor.cs
│   ├── ITimeSeriesDB.cs
│   ├── IAnomalyDetector.cs
│   ├── IPredictiveAnalytics.cs
│   └── IMLModelManager.cs
├── DataCollector.cs
├── DataNormalizer.cs
├── FeatureExtractor.cs
├── InMemoryTimeSeriesDB.cs
├── AnomalyDetector.cs
├── PredictiveAnalytics.cs
├── MLModelManager.cs
└── IntelligenceServiceExtensions.cs

Tests/HELIOS.Platform.Tests/Intelligence/
└── MLIntelligenceServicesTests.cs
```

## Configuration Example

```csharp
// Startup configuration
public void ConfigureServices(IServiceCollection services)
{
    services.AddLogging();
    
    services.AddMLIntelligenceServices(options =>
    {
        options.MaxNormalizationHistorySize = 1000;
        options.MaxTimeSeriesPoints = 10000;
        options.DefaultAnomalySensitivity = 5;
        options.DefaultConfidenceLevel = 0.95;
        options.EnablePredictionCaching = true;
        options.PredictionCacheTtlSeconds = 300;
    });
}
```

## Troubleshooting

### High Memory Usage

- Reduce `MaxTimeSeriesPoints` option
- Implement more aggressive `PurgeOldDataAsync` schedules
- Monitor with performance counters

### Detection Accuracy Issues

- Train models with more representative historical data
- Adjust `DefaultAnomalySensitivity` (1-10)
- Verify data normalization is appropriate

### Performance Degradation

- Monitor lock contention with diagnostic logging
- Scale with additional service instances
- Consider caching predictions

## License & Attribution

Part of HELIOS Platform - Phase 3 Tier 1 ML Intelligence Services
Implemented with comprehensive async/await patterns, thread safety, and full integration support.
