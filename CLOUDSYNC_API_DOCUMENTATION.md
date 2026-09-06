# Cloud Sync System - API Documentation

## Overview

The Cloud Sync System provides a comprehensive abstraction layer for synchronizing data between local systems and cloud storage providers. It supports multiple cloud providers (OneDrive, Azure Storage) with advanced conflict resolution and state tracking capabilities.

## Architecture

### Components

1. **ICloudStorageProvider** - Provider abstraction interface
2. **OneDriveProvider** - Microsoft Graph API implementation
3. **AzureStorageProvider** - Azure Blob Storage implementation
4. **ISyncEngine** - Synchronization engine interface
5. **SyncEngine** - Default implementation with SQLite state tracking
6. **ICloudStorageProviderFactory** - Factory for provider instantiation

## Core Interfaces

### ICloudStorageProvider

Defines the contract for cloud storage operations.

```csharp
public interface ICloudStorageProvider
{
    // Authentication
    Task<bool> AuthenticateAsync(CloudProviderCredentials credentials);

    // Upload/Download
    Task<CloudUploadResult> UploadAsync(string localPath, string remotePath);
    Task<CloudDownloadResult> DownloadAsync(string remotePath, string localPath);

    // File Operations
    Task<List<CloudFileInfo>> ListFilesAsync(string remotePath);
    Task<bool> DeleteAsync(string remotePath);

    // Quota Management
    Task<CloudQuotaInfo> GetQuotaAsync();

    // Connection
    Task<bool> VerifyConnectionAsync();
    
    CloudProviderType ProviderType { get; }
}
```

### ISyncEngine

Manages bidirectional synchronization with state tracking and conflict resolution.

```csharp
public interface ISyncEngine
{
    // Initialization
    Task<bool> InitializeAsync(ICloudStorageProvider provider);

    // Sync Operations
    Task<SyncResult> PushAsync(string localPath, string remotePath);
    Task<SyncResult> PullAsync(string remotePath, string localPath);
    Task<SyncResult> SyncAsync(string localPath, string remotePath, 
        ConflictResolutionStrategy strategy);

    // State Management
    Task<FileSyncState?> GetSyncStateAsync(string filePath);
    Task<List<SyncOperation>> GetPendingOperationsAsync();
    Task<SyncResult> RetryFailedAsync();
    Task<bool> ClearStateAsync();
}
```

## Data Models

### CloudProviderCredentials

Credentials for cloud provider authentication.

```csharp
public class CloudProviderCredentials
{
    public string? AccessToken { get; set; }
    public string? RefreshToken { get; set; }
    public string? TenantId { get; set; }
    public string? ClientId { get; set; }
    public string? ClientSecret { get; set; }
    public string? SubscriptionId { get; set; }
    public string? StorageAccountName { get; set; }
    public string? StorageAccountKey { get; set; }
    public DateTime ExpiresAt { get; set; }
}
```

### CloudUploadResult & CloudDownloadResult

Results from upload and download operations.

```csharp
public class CloudUploadResult
{
    public bool Success { get; set; }
    public string? FileId { get; set; }
    public string? RemotePath { get; set; }
    public long? FileSizeBytes { get; set; }
    public DateTime UploadedAt { get; set; }
    public string? ETag { get; set; }
    public string? ErrorMessage { get; set; }
}

public class CloudDownloadResult
{
    public bool Success { get; set; }
    public string? LocalPath { get; set; }
    public long? FileSizeBytes { get; set; }
    public DateTime DownloadedAt { get; set; }
    public string? ErrorMessage { get; set; }
}
```

### SyncResult

Comprehensive sync operation results.

```csharp
public class SyncResult
{
    public bool Success { get; set; }
    public int FilesProcessed { get; set; }
    public int FilesSynced { get; set; }
    public int ConflictCount { get; set; }
    public int ErrorCount { get; set; }
    public List<string> Errors { get; set; }
    public List<ConflictInfo> Conflicts { get; set; }
    public DateTime StartTime { get; set; }
    public DateTime EndTime { get; set; }
    public TimeSpan Duration => EndTime - StartTime;
}
```

### ConflictResolutionStrategy

Enum for handling conflicting changes:

- **LastWriteWins** - Keep the version with the latest modification time
- **KeepLocal** - Always keep the local version
- **KeepRemote** - Always keep the remote version
- **CreateBoth** - Create both versions with timestamp suffixes
- **Abort** - Skip conflicts and report errors

## Usage Examples

### OneDrive Integration

```csharp
// Create provider
var factory = new CloudStorageProviderFactory(logger);
var oneDriveProvider = factory.CreateProvider(CloudProviderType.OneDrive);

// Authenticate
var credentials = new CloudProviderCredentials
{
    AccessToken = "eyJ0eXAiOiJKV1QiLCJhbGc...",
    RefreshToken = "M.R3_BAY...",
    TenantId = "common"
};

var authenticated = await oneDriveProvider.AuthenticateAsync(credentials);

// Upload file
var uploadResult = await oneDriveProvider.UploadAsync(
    @"C:\Documents\report.pdf",
    "/Work/2024/report.pdf"
);

if (uploadResult.Success)
{
    Console.WriteLine($"Uploaded: {uploadResult.FileId}");
}

// Get quota
var quota = await oneDriveProvider.GetQuotaAsync();
Console.WriteLine($"Used: {quota.UsagePercent}%");
```

### Azure Storage Integration

```csharp
// Create provider
var azureProvider = factory.CreateProvider(CloudProviderType.AzureBlob);

// Authenticate
var credentials = new CloudProviderCredentials
{
    StorageAccountName = "mystorageaccount",
    StorageAccountKey = "DefaultEndpointsProtocol=https;..."
};

await azureProvider.AuthenticateAsync(credentials);

// List files
var files = await azureProvider.ListFilesAsync("/projects/2024");
foreach (var file in files)
{
    Console.WriteLine($"{file.Name}: {file.SizeBytes} bytes");
}
```

### Bidirectional Sync with Conflict Resolution

```csharp
// Initialize sync engine
var syncEngine = new SyncEngine(logger);
await syncEngine.InitializeAsync(oneDriveProvider);

// Perform bidirectional sync
var syncResult = await syncEngine.SyncAsync(
    @"C:\Users\John\Documents",
    "/OneDrive/Documents",
    ConflictResolutionStrategy.LastWriteWins
);

Console.WriteLine($"Synced: {syncResult.FilesSynced} files");
Console.WriteLine($"Conflicts: {syncResult.ConflictCount}");

foreach (var conflict in syncResult.Conflicts)
{
    Console.WriteLine($"Conflict: {conflict.FilePath}");
    Console.WriteLine($"  Local: {conflict.LocalModified}");
    Console.WriteLine($"  Remote: {conflict.RemoteModified}");
}
```

### Push/Pull Operations

```csharp
// Push local changes to cloud
var pushResult = await syncEngine.PushAsync(
    @"C:\Documents\ProjectA",
    "/cloud/projects/ProjectA"
);

Console.WriteLine($"Pushed: {pushResult.FilesSynced} files");

// Pull remote changes to local
var pullResult = await syncEngine.PullAsync(
    "/cloud/projects/ProjectA",
    @"C:\Documents\ProjectA"
);

Console.WriteLine($"Pulled: {pullResult.FilesSynced} files");
```

### Handling Failed Operations

```csharp
// Check pending operations
var pending = await syncEngine.GetPendingOperationsAsync();
Console.WriteLine($"Pending operations: {pending.Count}");

foreach (var op in pending)
{
    Console.WriteLine($"  {op.Type}: {op.FilePath} (Retry: {op.RetryCount})");
}

// Retry failed operations
var retryResult = await syncEngine.RetryFailedAsync();
if (retryResult.Success)
{
    Console.WriteLine("Retry completed successfully");
}
```

## Cloud Provider Details

### OneDrive Provider

**Authentication:**

- Uses OAuth2 with Microsoft Graph API
- Requires access token (with optional refresh token for token renewal)
- Supports delegated and application permissions

**Key Features:**

- Full file upload/download support
- File listing with metadata
- Quota information (total, used, remaining)
- Large file resumable upload support
- Proper error handling and retry logic

**API Endpoints:**

- `GET /me/drive` - Get quota information
- `GET /me/drive/root:/{path}:/children` - List files
- `PUT /me/drive/root:/{path}:/content` - Upload file
- `GET /me/drive/root:/{path}:/content` - Download file
- `DELETE /me/drive/root:/{path}` - Delete file

### Azure Storage Provider

**Authentication:**

- Uses storage account name and key
- Supports connection strings
- Connection pooling for performance

**Key Features:**

- Blob container operations
- File listing with filtering
- Size and quota tracking
- Automatic container creation
- Optimized batch operations

**Container:**

- Default container: `helios-sync`
- Auto-created on initialization
- Supports hierarchical path structure with `/`

## Conflict Resolution

### Last Write Wins (Recommended)

The engine compares modification timestamps and keeps the newer version:

```
Local:  2024-01-15 14:30:00 UTC (newer) ✓ Kept
Remote: 2024-01-15 14:00:00 UTC         Downloaded

Decision: Keep local version
```

### Keep Local

Always preserves the local file and prevents cloud overwrites:

```
Local:  2024-01-15 14:00:00 UTC ✓ Kept
Remote: 2024-01-15 14:30:00 UTC

Decision: Upload local, overwrite remote
```

### Keep Remote

Always preserves the remote file and prevents local overwrites:

```
Local:  2024-01-15 14:00:00 UTC
Remote: 2024-01-15 14:30:00 UTC ✓ Kept

Decision: Download remote, overwrite local
```

### Create Both

Creates both versions with unique identifiers:

```
Local:  file.txt (2024-01-15 14:00:00)
Remote: file.txt (2024-01-15 14:30:00)

Result: 
  file_local_2024-01-15-140000.txt
  file_remote_2024-01-15-143000.txt
```

## State Management

### SQLite Database

The sync engine maintains state in a local SQLite database:

**Location:** `%APPDATA%\HELIOS\Cloud\helios-sync-state.db`

**Tables:**

```sql
FileSyncStates
  - FilePath (PK)
  - LocalModifiedAt
  - RemoteModifiedAt
  - LocalHash
  - RemoteHash
  - RemoteFileId
  - Status (Synced, Pending, Conflict, Failed)
  - LastSyncAt

SyncOperations
  - FileId (PK)
  - FilePath
  - Type (Upload, Download, Delete, Merge)
  - Status (Pending, Failed)
  - CreatedAt
  - RetryCount
```

### State Cache

The engine maintains an in-memory cache of file sync states for performance. Cache is loaded on initialization and synchronized with the database.

## Error Handling

### Retry Logic

Failed operations are automatically queued with exponential backoff:

- Max retries: 3
- Retry intervals: 1s, 2s, 4s

### Error Categories

1. **Authentication Errors** - Invalid credentials or expired tokens
2. **Network Errors** - Connection timeouts or failures
3. **File I/O Errors** - Missing files or permission issues
4. **Quota Errors** - Insufficient storage space
5. **Conflict Errors** - File version conflicts

### Error Recovery

```csharp
var result = await syncEngine.RetryFailedAsync();

if (!result.Success)
{
    foreach (var error in result.Errors)
    {
        logger.Error($"Retry failed: {error}");
    }
}
```

## Performance Optimization

### Batch Operations

- Processes multiple files in single sync operation
- Leverages provider's batch API where available
- Efficient state database queries with indexing

### Caching

- In-memory cache for sync states
- Database indexing on status and operation type
- Lazy-loaded provider instances

### Concurrency

- Uses async/await throughout
- Non-blocking I/O operations
- Thread-safe concurrent collections

## Telemetry

Each sync operation provides:

- Files processed count
- Successful syncs count
- Conflict count and details
- Error count and messages
- Duration and performance metrics

```csharp
var result = await syncEngine.SyncAsync(...);

Console.WriteLine($"Duration: {result.Duration.TotalSeconds}s");
Console.WriteLine($"Success Rate: {result.FilesSynced}/{result.FilesProcessed}");
Console.WriteLine($"Throughput: {result.FilesProcessed / result.Duration.TotalSeconds:F2} files/sec");
```

## Best Practices

1. **Always verify connection before sync** - Use `VerifyConnectionAsync()` first
2. **Handle conflicts explicitly** - Choose appropriate strategy for your use case
3. **Monitor pending operations** - Check for stuck or failed syncs
4. **Use appropriate conflict strategy** - Different strategies for different data types
5. **Batch large operations** - Sync folders instead of individual files
6. **Implement retry logic** - Handle transient failures gracefully
7. **Log all operations** - Enable detailed logging for troubleshooting
8. **Test with mock providers** - Use Moq for unit testing

## Future Enhancements

- Support for Google Drive and Dropbox
- Delta sync capabilities
- Bidirectional watch/monitor mode
- Advanced merge strategies
- Encryption support
- Bandwidth throttling
- Selective sync patterns
