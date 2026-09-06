# Cloud Provider Integration Guide

## Overview

This guide provides step-by-step instructions for integrating OneDrive and Azure Storage providers into your application.

## OneDrive Integration

### Prerequisites

- Microsoft 365 account
- Azure AD application registration
- Client ID and Client Secret

### Step 1: Register Azure AD Application

1. Go to [Azure Portal](https://portal.azure.com)
2. Navigate to **Azure Active Directory** > **App registrations**
3. Click **New registration**
4. Enter application name: `HELIOS Cloud Sync`
5. Select **Accounts in any organizational directory (Multi-tenant)**
6. Click **Register**

### Step 2: Configure API Permissions

1. In app registration, go to **API permissions**
2. Click **Add a permission**
3. Select **Microsoft Graph**
4. Choose **Delegated permissions**
5. Search and select:
   - `Files.Read`
   - `Files.ReadWrite`
   - `Files.Read.All`
   - `Files.ReadWrite.All`
   - `offline_access` (for refresh token)
6. Click **Add permissions**
7. Click **Grant admin consent**

### Step 3: Create Client Secret

1. Go to **Certificates & secrets**
2. Click **New client secret**
3. Enter description: `HELIOS Cloud Sync Secret`
4. Set expiry to 24 months
5. Copy the secret value (use immediately, won't be shown again)

### Step 4: Obtain Access Token

#### Using Authorization Code Flow (Recommended for Users)

```csharp
using Microsoft.Identity.Client;

var app = PublicClientApplicationBuilder
    .Create("YOUR_CLIENT_ID")
    .WithDefaultRedirectUri()
    .WithAuthority(AadAuthorityAudience.AzureAdMultipleOrgs)
    .Build();

var scopes = new[] { "https://graph.microsoft.com/.default" };

try
{
    var result = await app.AcquireTokenInteractive(scopes).ExecuteAsync();
    
    var credentials = new CloudProviderCredentials
    {
        AccessToken = result.AccessToken,
        RefreshToken = result.RefreshToken,
        TenantId = result.TenantId,
        ClientId = "YOUR_CLIENT_ID",
        ExpiresAt = result.ExpiresOn.UtcDateTime
    };
}
catch (MsalException ex)
{
    Console.WriteLine($"Authentication failed: {ex.Message}");
}
```

#### Using Service Principal (For Applications)

```csharp
using Azure.Identity;
using Azure.Core;

var credential = new ClientSecretCredential(
    tenantId: "YOUR_TENANT_ID",
    clientId: "YOUR_CLIENT_ID",
    clientSecret: "YOUR_CLIENT_SECRET"
);

var tokenRequestContext = new TokenRequestContext(
    scopes: new[] { "https://graph.microsoft.com/.default" }
);

var token = await credential.GetTokenAsync(tokenRequestContext);

var credentials = new CloudProviderCredentials
{
    AccessToken = token.Token,
    TenantId = "YOUR_TENANT_ID",
    ClientId = "YOUR_CLIENT_ID",
    ClientSecret = "YOUR_CLIENT_SECRET"
};
```

### Step 5: Initialize OneDrive Provider

```csharp
var logger = new ConsoleLogger(); // Your logger implementation
var factory = new CloudStorageProviderFactory(logger);
var oneDriveProvider = factory.CreateProvider(CloudProviderType.OneDrive);

// Authenticate
bool authenticated = await oneDriveProvider.AuthenticateAsync(credentials);

if (authenticated)
{
    // Use provider
    var files = await oneDriveProvider.ListFilesAsync("/Documents");
    var quota = await oneDriveProvider.GetQuotaAsync();
    
    Console.WriteLine($"OneDrive connected!");
    Console.WriteLine($"Used: {quota.UsagePercent:F1}%");
}
```

### OneDrive Permissions Model

| Scope | Description | Use Case |
|-------|-------------|----------|
| `Files.Read` | Read files | Reading documents |
| `Files.ReadWrite` | Read/write files | Full sync capability |
| `Files.Read.All` | Read all files | Admin access |
| `Files.ReadWrite.All` | Read/write all files | Full admin capability |
| `offline_access` | Refresh token | Long-lived sessions |

## Azure Storage Integration

### Prerequisites

- Azure subscription
- Storage account
- Account key or connection string

### Step 1: Create Storage Account

1. Go to [Azure Portal](https://portal.azure.com)
2. Click **Create a resource** > **Storage account**
3. Select resource group or create new
4. Enter storage account name (must be unique, lowercase)
5. Select region
6. Choose performance tier: **Standard**
7. Choose replication: **Locally redundant storage (LRS)** for cost
8. Click **Review + create** > **Create**

### Step 2: Get Access Keys

1. Navigate to created storage account
2. Go to **Access keys** in left menu
3. Copy **Storage account name** (e.g., `mystorageaccount`)
4. Copy **Key1** (account key)

### Step 3: Create Blob Container

1. In storage account, go to **Containers**
2. Click **+ Container**
3. Enter name: `helios-sync`
4. Set public access level: **Private**
5. Click **Create**

### Step 4: Initialize Azure Provider

```csharp
var logger = new ConsoleLogger();
var factory = new CloudStorageProviderFactory(logger);
var azureProvider = factory.CreateProvider(CloudProviderType.AzureBlob);

// Authenticate
var credentials = new CloudProviderCredentials
{
    StorageAccountName = "mystorageaccount",
    StorageAccountKey = "DefaultEndpointsProtocol=https;AccountName=..."
};

bool authenticated = await azureProvider.AuthenticateAsync(credentials);

if (authenticated)
{
    // Use provider
    var uploadResult = await azureProvider.UploadAsync(
        @"C:\data\file.txt",
        "/documents/file.txt"
    );
    
    Console.WriteLine($"Uploaded: {uploadResult.FileId}");
}
```

### Connection String Format

```
DefaultEndpointsProtocol=https;
AccountName=mystorageaccount;
AccountKey=DefaultEndpointsProtocol=https;[...];
EndpointSuffix=core.windows.net
```

## Application Configuration

### Dependency Injection Setup

```csharp
// In Startup.cs or Program.cs
services.AddCloudStorageProvider();
services.AddSingleton<ISyncEngine>(sp => 
    new SyncEngine(sp.GetRequiredService<ILogger>()));

// Register cloud provider credentials (from secure config)
services.Configure<CloudProviderOptions>(
    configuration.GetSection("CloudProviders"));
```

### appsettings.json Configuration

```json
{
  "CloudProviders": {
    "OneDrive": {
      "ClientId": "your-client-id",
      "TenantId": "common",
      "Enabled": true
    },
    "AzureStorage": {
      "AccountName": "mystorageaccount",
      "Enabled": true
    }
  },
  "CloudSync": {
    "SyncInterval": 300,
    "MaxConcurrentOperations": 5,
    "ConflictResolution": "LastWriteWins"
  }
}
```

### Secure Credential Storage

**DO NOT** store credentials in configuration files. Use:

#### Azure Key Vault (Recommended)

```csharp
var credential = new DefaultAzureCredential();
var client = new SecretClient(
    new Uri("https://keyvaultname.vault.azure.net/"),
    credential
);

var secret = await client.GetSecretAsync("OneDrive--AccessToken");
var accessToken = secret.Value.Value;
```

#### Windows Credential Manager

```csharp
var credentialManager = new CredentialManager();
var credentials = credentialManager.GetCredentials("HELIOS.OneDrive");
```

#### Secure Configuration

```csharp
services.AddOptions<CloudProviderCredentials>()
    .Configure<IConfiguration>((options, config) =>
    {
        options.AccessToken = config["Secrets:OneDrive:AccessToken"];
        options.StorageAccountKey = config["Secrets:Azure:AccountKey"];
    });
```

## Testing Integration

### Unit Testing with Mock Providers

```csharp
[Fact]
public async Task CloudSync_WithMockProvider_SyncsSuccessfully()
{
    // Arrange
    var loggerMock = new Mock<ILogger>();
    var providerMock = new Mock<ICloudStorageProvider>();
    
    providerMock
        .Setup(p => p.UploadAsync(It.IsAny<string>(), It.IsAny<string>()))
        .ReturnsAsync(new CloudUploadResult { Success = true });
    
    var syncEngine = new SyncEngine(loggerMock.Object);
    await syncEngine.InitializeAsync(providerMock.Object);
    
    // Act
    var tempFile = Path.GetTempFileName();
    File.WriteAllText(tempFile, "test");
    var result = await syncEngine.PushAsync(tempFile, "/remote");
    
    // Assert
    Assert.True(result.Success);
    File.Delete(tempFile);
}
```

### Integration Testing with Real Providers

```csharp
[Fact]
[Trait("Integration", "OneDrive")]
public async Task OneDrive_UploadAndDownload_Succeeds()
{
    // Requires valid credentials in test environment
    var credentials = new CloudProviderCredentials
    {
        AccessToken = Environment.GetEnvironmentVariable("ONEDRIVE_TOKEN")
    };
    
    var logger = new TestLogger();
    var provider = new OneDriveProvider(logger);
    await provider.AuthenticateAsync(credentials);
    
    // Test upload/download cycle
    var tempFile = Path.GetTempFileName();
    File.WriteAllText(tempFile, "integration test");
    
    var uploadResult = await provider.UploadAsync(tempFile, "/test/file.txt");
    Assert.True(uploadResult.Success);
    
    // Cleanup
    await provider.DeleteAsync("/test/file.txt");
    File.Delete(tempFile);
}
```

## Troubleshooting

### OneDrive Issues

**Problem:** "AADSTS65001: User or admin has not consented to use the application"

**Solution:**

```csharp
// Use interactive browser for first-time authentication
var app = PublicClientApplicationBuilder.Create(clientId)
    .WithDefaultRedirectUri()
    .Build();

var result = await app.AcquireTokenInteractive(scopes)
    .WithPrompt(Prompt.ForceLogin)
    .ExecuteAsync();
```

**Problem:** "401 Unauthorized"

**Solution:** Token may be expired. Refresh it:

```csharp
var result = await app.AcquireTokenSilent(scopes, account)
    .ExecuteAsync();

if (!string.IsNullOrEmpty(result.RefreshToken))
{
    credentials.RefreshToken = result.RefreshToken;
    credentials.ExpiresAt = result.ExpiresOn.UtcDateTime;
}
```

### Azure Storage Issues

**Problem:** "StorageException: The specified container does not exist"

**Solution:**

```csharp
// Ensure container is created
await containerClient.CreateIfNotExistsAsync();
```

**Problem:** "AuthenticationFailedException: Invalid storage account key"

**Solution:** Verify:

1. Storage account name matches exactly
2. Account key is correct (not truncated)
3. Endpoint suffix is correct (usually `core.windows.net`)

## Compliance & Security

### Data Encryption

Ensure data is encrypted in transit and at rest:

**OneDrive:**

- Uses HTTPS (TLS 1.2+)
- Files encrypted in OneDrive with AES-256
- In-transit encryption with TLS

**Azure Storage:**

- Enable TLS 1.2 minimum
- Storage Service Encryption (SSE) by default
- Optional client-side encryption

### Audit Logging

```csharp
// Log all sync operations
var logger = LoggerFactory.Create(builder =>
    builder
        .AddConsole()
        .AddFile($"logs/cloudsync-{DateTime.Now:yyyy-MM-dd}.log")
        .SetMinimumLevel(LogLevel.Information)
).CreateLogger("CloudSync");

var syncEngine = new SyncEngine(logger);
```

### Compliance Considerations

- **GDPR:** Document data processing agreements with cloud providers
- **HIPAA:** Use Azure Government or OneDrive for Business with compliance controls
- **SOC2:** Verify provider compliance certifications
- **Data Residency:** Choose appropriate regions for storage

## Performance Tuning

### Optimization Tips

1. **Batch Operations:** Group multiple small files into larger batches
2. **Parallel Operations:** Use concurrent uploads/downloads
3. **Compression:** Consider compressing large files before upload
4. **Caching:** Enable sync state caching for large file sets
5. **Scheduling:** Schedule syncs during off-peak hours

### Monitoring

```csharp
var result = await syncEngine.SyncAsync(localPath, remotePath, strategy);

Console.WriteLine($"Files Synced: {result.FilesSynced}/{result.FilesProcessed}");
Console.WriteLine($"Duration: {result.Duration.TotalSeconds:F2}s");
Console.WriteLine($"Throughput: {result.FilesSynced / result.Duration.TotalSeconds:F2} files/sec");
Console.WriteLine($"Conflicts: {result.ConflictCount}");
```

## Next Steps

1. Choose your primary cloud provider
2. Complete authentication setup
3. Test sync operations with sample data
4. Implement error handling and retry logic
5. Configure logging and monitoring
6. Deploy to production with secure credential management
