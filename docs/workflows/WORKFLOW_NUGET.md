# NuGet Build & Publish Workflow - nuget.yml

## Overview

The `nuget.yml` workflow handles .NET package creation, versioning, and publishing to NuGet.org and GitHub Packages. It supports multi-framework builds and semantic versioning.

**File**: `.github/workflows/nuget.yml`  
**Trigger**: Push to main, tags (v*.*.*), PRs, manual dispatch  
**Duration**: 8-12 minutes  
**Runners**: Windows + Ubuntu  
**Frameworks**: .NET 6.0, 7.0, 8.0

---

## Table of Contents

1. [Workflow Purpose](#workflow-purpose)
2. [Multi-Framework Strategy](#multi-framework-strategy)
3. [Job Details](#job-details)
4. [Version Management](#version-management)
5. [Package Creation](#package-creation)
6. [Publishing Process](#publishing-process)
7. [GitHub Packages](#github-packages)
8. [Release Management](#release-management)
9. [Troubleshooting](#troubleshooting)

---

## Workflow Purpose

**Goals**:

- ✅ Build across multiple .NET versions (6.0, 7.0, 8.0)
- ✅ Build across multiple platforms (Windows, Linux)
- ✅ Run tests on each configuration
- ✅ Create NuGet package
- ✅ Publish to NuGet.org
- ✅ Publish to GitHub Packages
- ✅ Create GitHub Release
- ✅ Handle version management

**Scope**: .NET packages for HELIOS Platform

---

## Multi-Framework Strategy

### Build Matrix

```yaml
strategy:
  matrix:
    os: [ubuntu-latest, windows-latest]
    dotnet-version: ['8.0', '7.0', '6.0']
  fail-fast: false
```

**Total Combinations**: 2 OS × 3 versions = 6 concurrent build jobs

### Platform Specifics

| OS | Runner | Use Case |
|---|---|---|
| Windows | windows-latest | Native Windows development, signing |
| Linux | ubuntu-latest | CI validation, cross-platform |

### .NET Version Support

| Version | EOL | Support Level | Recommendation |
|---------|-----|---|---|
| .NET 8.0 | Nov 2026 | LTS | ✅ Recommended |
| .NET 7.0 | May 2024 | STS | 🟡 Support |
| .NET 6.0 | Nov 2024 | LTS | 🟡 Maintenance |

---

## Job Details

### Job 1: Build (Matrix)

```yaml
jobs:
  build:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, windows-latest]
        dotnet-version: ['8.0', '7.0', '6.0']
      fail-fast: false
    steps:
      - Checkout code
      - Setup .NET
      - Restore dependencies
      - Build solution
      - Run tests
      - Upload test results
```

**Steps breakdown**:

1. **Checkout**

   ```yaml
   - uses: actions/checkout@v4
     with:
       fetch-depth: 0
   ```

2. **Setup .NET**

   ```yaml
   - uses: actions/setup-dotnet@v4
     with:
       dotnet-version: ${{ matrix.dotnet-version }}
   ```

3. **Restore Dependencies**

   ```bash
   dotnet restore
   ```

   Restores NuGet packages from `packages.config` or `.csproj`

4. **Build Solution**

   ```bash
   dotnet build src/HELIOS.Platform/HELIOS.Platform.csproj \
     -c Release \
     -f net${{ matrix.dotnet-version }} \
     --no-restore \
     -v minimal
   ```

   **Build flags**:
   - `-c Release` - Release configuration
   - `-f net8.0` - Target framework
   - `--no-restore` - Skip restore (already done)
   - `-v minimal` - Minimal logging

5. **Run Tests**

   ```bash
   dotnet test tests/ \
     -c Release \
     --no-build \
     --logger "trx;LogFileName=test-results.trx" \
     --verbosity minimal
   ```

6. **Upload Results**

   ```yaml
   - uses: actions/upload-artifact@v3
     with:
       name: test-results-${{ matrix.os }}-${{ matrix.dotnet-version }}
       path: '**/test-results.trx'
   ```

---

## Version Management

### Version Sources

```yaml
- name: Get version
  id: version
  run: |
    [xml]$csproj = Get-Content "src/HELIOS.Platform/HELIOS.Platform.csproj"
    $version = $csproj.Project.PropertyGroup.Version
    echo "VERSION=$version" >> $env:GITHUB_OUTPUT
```

### Version Format

Follow semantic versioning:

```
Major.Minor.Patch[-Prerelease]

Examples:
1.0.0           # Stable release
1.0.1           # Patch release
1.1.0           # Minor release
2.0.0           # Major release
1.0.0-alpha.1   # Pre-release
1.0.0-beta.2    # Beta release
1.0.0-rc.1      # Release candidate
```

### .csproj Version Configuration

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFrameworks>net8.0;net7.0;net6.0</TargetFrameworks>
    <Version>1.0.0</Version>
    <AssemblyVersion>1.0.0</AssemblyVersion>
    <FileVersion>1.0.0</FileVersion>
    <PackageVersion>1.0.0</PackageVersion>
    <InformationalVersion>1.0.0</InformationalVersion>
  </PropertyGroup>
</Project>
```

---

## Package Creation

### Job 2: Package

```yaml
jobs:
  package:
    needs: build
    runs-on: windows-latest
    if: always()
    steps:
      - Checkout
      - Setup .NET
      - Get version
      - Restore and Build
      - Verify package
      - Upload artifact
```

### Package Generation

```bash
dotnet restore
dotnet pack src/HELIOS.Platform/HELIOS.Platform.csproj \
  -c Release \
  -o artifacts/
```

**Output**:

```
artifacts/
└── HELIOS.Platform.1.0.0.nupkg
```

### Package Contents

```
HELIOS.Platform.1.0.0.nupkg
├── _rels/
├── package/
│   ├── HELIOS.Platform.1.0.0.nuspec
│   └── services/
├── HELIOS.Platform/
│   ├── net8.0/
│   │   ├── HELIOS.Platform.dll
│   │   ├── HELIOS.Platform.pdb
│   │   └── HELIOS.Platform.xml
│   ├── net7.0/
│   │   └── ...
│   └── net6.0/
│       └── ...
├── [Content_Types].xml
└── .nuspec
```

### Verification

```powershell
Get-ChildItem artifacts/*.nupkg | ForEach-Object {
    Write-Host "Package: $($_.Name)"
    Write-Host "Size: $(($_.Length / 1MB).ToString('F2')) MB"
}
```

---

## Publishing Process

### Job 3: Publish to NuGet.org

```yaml
jobs:
  publish-nuget:
    needs: package
    runs-on: windows-latest
    if: startsWith(github.ref, 'refs/tags/v')
    steps:
      - Download package
      - Setup .NET
      - Publish to NuGet.org
      - Create GitHub Release
```

**Trigger Condition**: Only on version tags (v*.*.*)

### Publishing Steps

1. **Download Package**

   ```yaml
   - uses: actions/download-artifact@v3
     with:
       path: download/
   ```

2. **Push to NuGet.org**

   ```powershell
   $nupkgs = Get-ChildItem download -Recurse -Filter "*.nupkg"
   foreach ($nupkg in $nupkgs) {
       dotnet nuget push "$($nupkg.FullName)" `
         --api-key "${{ secrets.NUGET_API_KEY }}" `
         --source https://api.nuget.org/v3/index.json `
         --skip-duplicate
   }
   ```

   **Flags**:
   - `--api-key` - NuGet.org API key (from GitHub Secrets)
   - `--source` - NuGet.org feed URL
   - `--skip-duplicate` - Don't fail if version exists

3. **Create GitHub Release**

   ```yaml
   - uses: actions/create-release@v1
     env:
       GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
     with:
       tag_name: ${{ github.ref }}
       release_name: Release ${{ github.ref_name }}
       body: |
         # HELIOS.Platform ${{ github.ref_name }}
         See [CHANGELOG.md](CHANGELOG.md) for release details.
       draft: false
       prerelease: ${{ contains(github.ref_name, 'alpha') || 
                      contains(github.ref_name, 'beta') || 
                      contains(github.ref_name, 'rc') }}
   ```

### NuGet.org Setup

1. **Create Account**: https://www.nuget.org
2. **Get API Key**: Profile → API Keys
3. **Create Secret**: GitHub → Settings → Secrets → `NUGET_API_KEY`

---

## GitHub Packages

### Job 4: Publish to GitHub Packages

```yaml
jobs:
  publish-github:
    needs: package
    runs-on: windows-latest
    if: always()
    steps:
      - Download package
      - Setup .NET
      - Configure source
      - Publish to GitHub
```

**Always runs** (regardless of NuGet publication)

### GitHub Package Configuration

```powershell
dotnet nuget add source `
  --username github-actions `
  --password ${{ secrets.GITHUB_TOKEN }} `
  --store-password-in-clear-text `
  --name github `
  https://nuget.pkg.github.com/M0nado/index.json
```

**Replace `M0nado`** with your GitHub username/organization

### Publishing to GitHub

```powershell
$nupkgs = Get-ChildItem download -Recurse -Filter "*.nupkg"
foreach ($nupkg in $nupkgs) {
    dotnet nuget push "$($nupkg.FullName)" `
      --source github `
      --skip-duplicate
}
```

---

## Release Management

### Creating a Release

**Method 1: Git tag**

```bash
git tag -a v1.0.0 -m "Release version 1.0.0"
git push origin v1.0.0
```

**Method 2: GitHub UI**

1. Go to Releases
2. Draft new release
3. Set tag name: `v1.0.0`
4. Publish release

### Release Naming

```
v1.0.0                 # Stable release
v1.0.0-alpha.1        # Alpha release
v1.0.0-beta.2         # Beta release
v1.0.0-rc.1           # Release candidate
```

### Release Notes Template

```markdown
# HELIOS.Platform v1.0.0

## ✨ New Features
- Feature 1 description
- Feature 2 description

## 🐛 Bug Fixes
- Bug 1 description
- Bug 2 description

## 📚 Documentation
- Updated README
- API documentation

## 🔄 Dependencies Updated
- Dependency 1 → v1.5.0
- Dependency 2 → v2.0.0

## 📊 Test Coverage
- Unit tests: 85%
- Integration tests: 90%

**Download**: [HELIOS.Platform.1.0.0.nupkg](https://www.nuget.org/packages/HELIOS.Platform/1.0.0)
```

---

## Troubleshooting

### Build Failures

| Error | Cause | Solution |
|---|---|---|
| `dotnet: not found` | .NET not installed | Check actions/setup-dotnet@v4 |
| `Project file not found` | Wrong path | Verify .csproj path |
| `Restore failed` | Network issue | Retry workflow |
| `Test failure` | Code issue | Fix failing test |

### Publishing Issues

| Error | Cause | Solution |
|---|---|---|
| `401 Unauthorized` | Invalid API key | Regenerate/update secret |
| `409 Conflict` | Version exists | Increment version |
| `400 Bad Request` | Invalid package | Verify package format |

### Package Issues

| Error | Cause | Solution |
|---|---|---|
| `NuSpec error` | Invalid metadata | Check .nuspec file |
| `File not found` | Missing dependency | Verify assembly output |
| `Large package` | Unnecessary files | Exclude from package |

---

## Best Practices

✅ **Do**:

- Use semantic versioning
- Keep version in .csproj
- Test on all frameworks
- Use `--skip-duplicate`
- Sign packages (for production)
- Document releases

❌ **Don't**:

- Hardcode versions
- Publish duplicate versions
- Skip testing
- Publish unsigned packages (production)
- Remove old versions carelessly

---

## Advanced Configuration

### Package Metadata

```xml
<PropertyGroup>
  <PackageId>HELIOS.Platform</PackageId>
  <Title>HELIOS Platform</Title>
  <Description>Platform for HELIOS system</Description>
  <Authors>Your Name</Authors>
  <PackageProjectUrl>https://github.com/yourorg/helios</PackageProjectUrl>
  <PackageLicenseExpression>MIT</PackageLicenseExpression>
  <RepositoryUrl>https://github.com/yourorg/helios</RepositoryUrl>
  <RepositoryType>git</RepositoryType>
  <PackageTags>helios;platform;dotnet</PackageTags>
</PropertyGroup>
```

### Build Conditionals

```xml
<Target Name="PreBuild">
  <Message Text="Building $(Version)" Importance="high"/>
</Target>

<Target Name="PostBuild">
  <Message Text="Build complete" Importance="high"/>
</Target>
```

---

## References

- [NuGet Documentation](https://docs.microsoft.com/en-us/nuget/)
- [Semantic Versioning](https://semver.org/)
- [.NET Documentation](https://docs.microsoft.com/en-us/dotnet/)
- [dotnet pack command](https://docs.microsoft.com/en-us/dotnet/core/tools/dotnet-pack)
- [GitHub Packages](https://docs.github.com/en/packages)

---

**Document Version**: 1.0  
**Last Updated**: 2024  
**Status**: Active ✅
