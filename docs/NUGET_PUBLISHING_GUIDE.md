# HELIOS Platform - NuGet Publishing & Distribution Guide

## 🚀 Publishing to NuGet.org

### Prerequisites

1. **NuGet.org Account**
   - Create at https://www.nuget.org/users/account/Register
   - Verify email address
   - Configure profile and API keys

2. **Local Setup**

   ```powershell
   # Install nuget CLI (if not already installed)
   choco install nuget.commandline
   
   # Or download from
   https://www.nuget.org/downloads
   ```

3. **API Key**
   - Go to https://www.nuget.org/account/ApiKeys
   - Click "Create" to generate new API key
   - Save in secure location

### Step 1: Prepare for Publishing

```powershell
cd C:\Users\ADMIN\helios-platform

# Ensure build is clean
Remove-Item -Path dist, obj -Recurse -Force
Remove-Item -Path src/HELIOS.Platform/obj -Recurse -Force
Remove-Item -Path src/HELIOS.Platform/bin -Recurse -Force
```

### Step 2: Build Release Package

```powershell
# Full build with all frameworks
.\build.ps1 -Configuration Release -SkipTests -CreateExe -CreateInstaller

# Or manual build
dotnet clean
dotnet restore
dotnet build -c Release
dotnet pack src/HELIOS.Platform/HELIOS.Platform.csproj -c Release -o ./dist
```

### Step 3: Verify Package

```powershell
# Check package was created
Get-ChildItem dist/*.nupkg | Format-List

# Inspect package contents (optional - install NuGetKeyword)
nuget pack src/HELIOS.Platform/HELIOS.Platform.csproj -OutputDirectory dist -Version 1.0.0

# Or use online package explorer
# https://www.nuget.org/packages/HELIOS.Platform/
```

### Step 4: Configure API Key

**Option A: Configure Globally**

```powershell
nuget setApiKey Your-API-Key-Here
```

**Option B: Configure Per-Command**

```powershell
$apiKey = "Your-API-Key-Here"
```

**Option C: Use NuGet.Config**

```xml
<!-- Create %APPDATA%\NuGet\NuGet.Config -->
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <apiKeys>
    <add key="https://api.nuget.org/v3/index.json" value="Your-API-Key-Here" />
  </apiKeys>
  <packageSources>
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" protocolVersion="3" />
  </packageSources>
</configuration>
```

### Step 5: Publish Package

**Using dotnet CLI (Recommended)**

```powershell
dotnet nuget push dist/HELIOS.Platform.1.0.0.nupkg `
    --api-key $apiKey `
    --source https://api.nuget.org/v3/index.json
```

**Using nuget CLI**

```powershell
nuget push dist/HELIOS.Platform.1.0.0.nupkg `
    -ApiKey $apiKey `
    -Source https://www.nuget.org/api/v2/package
```

**Using PowerShell with Authentication**

```powershell
$headers = @{
    "X-NuGet-ApiKey" = $apiKey
}

Invoke-WebRequest -Uri "https://www.nuget.org/api/v2/package" `
    -Method Post `
    -InFile "dist/HELIOS.Platform.1.0.0.nupkg" `
    -Headers $headers
```

### Step 6: Verify Publication

**Wait for Processing**

- Processing typically takes 1-5 minutes
- Package will appear on NuGet.org dashboard
- Full indexing may take up to 1 hour

**Check Status**

```powershell
# Online
https://www.nuget.org/packages/HELIOS.Platform/

# Via NuGet Search
https://www.nuget.org/api/v2/Search()?$filter=Id%20eq%20'HELIOS.Platform'

# Via PowerShell
Find-Package HELIOS.Platform -Source NuGet
```

**Test Installation**

```powershell
# Create test project
dotnet new console -n TestHelios
cd TestHelios

# Install from NuGet.org
dotnet add package HELIOS.Platform --version 1.0.0

# Build and run
dotnet build
dotnet run
```

---

## 📋 Publishing Checklist

### Pre-Publication

- [ ] Version number correct (1.0.0)
- [ ] CHANGELOG.md updated
- [ ] README.md reviewed
- [ ] License file included
- [ ] Package metadata complete
- [ ] All dependencies resolved
- [ ] Tests passing
- [ ] Build succeeds for all frameworks (net6.0, net7.0, net8.0)
- [ ] No compiler warnings
- [ ] Security review completed

### Publication

- [ ] .nupkg file created
- [ ] Package size verified (~100MB)
- [ ] API key configured
- [ ] Internet connection stable
- [ ] Publish command executed successfully
- [ ] No error messages

### Post-Publication

- [ ] Package appears on NuGet.org
- [ ] Package searchable (search for "HELIOS.Platform")
- [ ] Installation works: `dotnet add package HELIOS.Platform`
- [ ] Documentation accessible
- [ ] License displays correctly
- [ ] Download count tracking
- [ ] GitHub repository linked

---

## 🔄 Update & Version Management

### Version Numbering (Semantic Versioning)

```
MAJOR.MINOR.PATCH
1.0.0
│ │ │
│ │ └─ Patch (bug fixes)
│ └─── Minor (new features, backward compatible)
└───── Major (breaking changes)

Examples:
v1.0.0 → Initial release
v1.0.1 → Bug fix
v1.1.0 → New feature
v2.0.0 → Breaking changes
```

### Publishing Updates

**Update Version Number**

```xml
<!-- In HELIOS.Platform.csproj -->
<PropertyGroup>
  <Version>1.0.1</Version>
</PropertyGroup>
```

**Update CHANGELOG**

```markdown
# Changelog

## [1.0.1] - 2024-01-15
### Fixed
- Fixed component initialization race condition
- Corrected Azure authentication timeout

### Added
- Performance metrics logging

### Security
- Updated dependency versions
```

**Build and Publish**

```powershell
.\build.ps1 -All
dotnet nuget push dist/HELIOS.Platform.1.0.1.nupkg --api-key $apiKey
```

---

## 🏢 Private/Corporate NuGet Feeds

### Setup Internal Feed (Azure Artifacts)

**Create Feed in Azure DevOps**

```
1. Go to Azure DevOps Organization
2. Click "Artifacts"
3. Click "Create Feed"
4. Name: "HELIOS"
5. Visibility: "People in your organization"
6. Upstream sources: "Include packages from NuGet.org"
```

**Get Connection String**

```powershell
# In Azure DevOps Artifacts
# Click "Connect to feed" → .NET Core
# Copy the source URL

$internalFeed = "https://pkgs.dev.azure.com/YOUR-ORG/_packaging/HELIOS/nuget/v3/index.json"
```

**Publish to Internal Feed**

```powershell
dotnet nuget push dist/HELIOS.Platform.1.0.0.nupkg `
    --api-key AzureArtifacts `
    --source $internalFeed
```

### Setup Internal Feed (ProGet)

**Install ProGet**

```powershell
# Download from https://inedo.com/proget/download
# Or use Docker
docker run -p 8080:80 inedo/proget
```

**Configure Feed**

```
1. Go to http://localhost:8080
2. Create new feed named "HELIOS"
3. Set type to "NuGet"
4. Copy feed URL
```

**Publish to ProGet Feed**

```powershell
$progetFeed = "http://proget.internal/nuget/HELIOS"

dotnet nuget push dist/HELIOS.Platform.1.0.0.nupkg `
    --source $progetFeed `
    --api-key "proget-api-key"
```

---

## 🔐 Security Best Practices

### API Key Management

```powershell
# ✓ Good: Use environment variable
$apiKey = $env:NUGET_API_KEY

# ✓ Good: Store in secure location
$apiKey = Read-Host -AsSecureString "Enter NuGet API Key"

# ✗ Bad: Hardcode in script
$apiKey = "sk_live_12345..."  # NEVER DO THIS!

# ✗ Bad: Commit to repository
# .git/config with API key
```

### Package Security

```powershell
# Sign package (optional, for enterprise)
nuget sign dist/HELIOS.Platform.1.0.0.nupkg `
    -CertificatePath "C:\certs\code-signing.pfx" `
    -CertificatePassword "password"

# Verify signature
nuget verify -signature dist/HELIOS.Platform.1.0.0.nupkg
```

### Dependency Security

```powershell
# Check for vulnerable dependencies
dotnet package audit

# Update dependencies to latest stable
dotnet outdated

# View dependency graph
dotnet package tree

# Lock file for reproducible builds
dotnet restore --use-lock-file
```

---

## 📊 Monitoring Package Distribution

### Track Downloads

**Via NuGet.org Dashboard**

```
https://www.nuget.org/packages/HELIOS.Platform/
Dashboard shows:
- Total downloads
- Downloads per version
- Download trends
```

**Via API**

```powershell
# Get package statistics
$statsUri = "https://api.nuget.org/v3/stats/packages/download"
$result = Invoke-RestMethod -Uri "$statsUri/HELIOS.Platform/download.json"
$result | ConvertTo-Json
```

**Via PowerShell**

```powershell
# Check latest version
Find-Package HELIOS.Platform -Source NuGet

# Check available versions
Find-Package HELIOS.Platform -AllVersions -Source NuGet
```

---

## ❌ Troubleshooting Publishing

### Issue: "403 Forbidden - API key invalid"

```powershell
# Verify API key is correct
# Go to https://www.nuget.org/account/ApiKeys
# Make sure API key hasn't expired

# Test API key
dotnet nuget push --dry-run dist/*.nupkg `
    --api-key "your-api-key" `
    --source https://api.nuget.org/v3/index.json
```

### Issue: "Conflict: The feed already contains 'HELIOS.Platform 1.0.0'"

```powershell
# Package version already published
# Increment version number and republish

# Edit HELIOS.Platform.csproj
# Change <Version>1.0.0</Version> to <Version>1.0.1</Version>

# Rebuild
.\build.ps1

# Republish
dotnet nuget push dist/HELIOS.Platform.1.0.1.nupkg ...
```

### Issue: "Package size exceeds limit"

```powershell
# NuGet.org limit is 500MB
# Check package size
(Get-Item "dist/HELIOS.Platform.1.0.0.nupkg").Length / 1MB

# Reduce size by excluding unnecessary files
# Edit HELIOS.Platform.csproj:
<PropertyGroup>
    <GenerateDocumentationFile>true</GenerateDocumentationFile>
    <TreatWarningsAsErrors>false</TreatWarningsAsErrors>
</PropertyGroup>
```

### Issue: "Cannot connect to NuGet.org"

```powershell
# Check internet connection
Test-NetConnection -ComputerName api.nuget.org -Port 443

# Check firewall/proxy
$proxy = [System.Net.HttpWebRequest]::DefaultWebProxy
Write-Host "Proxy: $proxy"

# Try with explicit proxy
dotnet nuget push dist/*.nupkg `
    --api-key $apiKey `
    --source https://api.nuget.org/v3/index.json `
    --skip-duplicate
```

---

## 📚 Additional Resources

### NuGet Documentation

- **Creating Packages:** https://learn.microsoft.com/en-us/nuget/create-packages/creating-a-package
- **Publishing:** https://learn.microsoft.com/en-us/nuget/nuget-org/publish-a-package
- **Versioning:** https://learn.microsoft.com/en-us/nuget/concepts/package-versioning
- **Metadata:** https://learn.microsoft.com/en-us/nuget/reference/nuspec

### Best Practices

- **Package Naming:** https://docs.microsoft.com/en-us/nuget/create-packages/package-naming-conventions
- **Semantic Versioning:** https://semver.org/
- **nuspec Reference:** https://learn.microsoft.com/en-us/nuget/reference/nuspec

### Tools

- **NuGet Package Explorer:** https://github.com/NuGetPackageExplorer/NuGetPackageExplorer
- **Package Search:** https://www.nuget.org/packages/
- **API Explorer:** https://api.nuget.org/v3/index.json

---

## 🎯 Multi-Platform Publishing Strategy

### Phase 1: NuGet.org (Public)

```
✓ Publish to NuGet.org for public consumption
✓ Enable community feedback and contributions
✓ Track downloads and usage
✓ Establish presence in .NET ecosystem
```

### Phase 2: Internal Feed (Corporate)

```
✓ Mirror on internal NuGet feed
✓ Ensure availability for enterprise deployments
✓ Maintain control over versions
✓ Enable offline access in restricted networks
```

### Phase 3: GitHub Releases (Artifacts)

```
✓ Publish executable as GitHub Release
✓ Include release notes and changelog
✓ Enable direct download for CI/CD
✓ Maintain executable distribution channel
```

### Phase 4: Docker Registry (Optional)

```
✓ Publish containerized version
✓ Enable Kubernetes deployments
✓ Support microservices architecture
✓ Enable cloud-native deployments
```

---

## 📋 Post-Publication Tasks

### Documentation Updates

- [ ] Update website with new version
- [ ] Post release announcement
- [ ] Update GitHub releases page
- [ ] Announce on community channels

### Support Readiness

- [ ] Monitor GitHub issues
- [ ] Track bug reports
- [ ] Prepare hotfix if needed
- [ ] Update support documentation

### Analytics

- [ ] Track download statistics
- [ ] Analyze usage patterns
- [ ] Collect user feedback
- [ ] Plan next version

---

**Publication Guide Version:** 1.0  
**Last Updated:** 2024  
**Maintained By:** HELIOS Team
