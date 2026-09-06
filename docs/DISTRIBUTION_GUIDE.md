# HELIOS Platform - Distribution Guide

## Overview

This guide covers the complete distribution process for HELIOS Platform v1.0.0 across all channels including NuGet.org, GitHub Releases, Chocolatey, Winget, and direct downloads.

## Distribution Channels

### 1. NuGet.org (Primary Channel)

- **Package Name**: `HELIOS.Platform`
- **Installation**: `nuget install HELIOS.Platform -Version 1.0.0`
- **URL**: https://www.nuget.org/packages/HELIOS.Platform/
- **Multi-Framework Support**:
  - .NET Framework 4.7.2
  - .NET Core 3.1
  - .NET 5.0+
  - .NET 6.0+

### 2. GitHub Releases

- **URL**: https://github.com/HELIOS-Platform/helios-platform/releases
- **Tag Format**: `v1.0.0`
- **Artifacts**:
  - HELIOS.Platform.exe
  - HELIOS-Setup.exe
  - HELIOS.Platform.1.0.0.nupkg
  - Demo applications
  - Documentation

### 3. Chocolatey Package Manager

- **Package**: `helios-platform`
- **Installation**: `choco install helios-platform`
- **Repository**: https://community.chocolatey.org/packages/helios-platform
- **Support**: Windows 7 SP1+

### 4. Windows Package Manager (Winget)

- **Package**: `HELIOS.Platform`
- **Installation**: `winget install HELIOS.Platform`
- **Repository**: Microsoft Store
- **Support**: Windows 10 Build 1809+

### 5. Direct Download

- **Location**: https://github.com/HELIOS-Platform/helios-platform/releases
- **File**: HELIOS-Setup.exe
- **Size**: Typically 50-100 MB
- **Format**: Windows Installer (.exe)

## Deployment Process

### Phase 1: Preparation (Before Release)

1. **Version Management**

   ```powershell
   # Tag the release
   git tag -a v1.0.0 -m "HELIOS Platform v1.0.0 Release"
   git push origin v1.0.0
   ```

2. **Build Verification**

   ```powershell
   dotnet build -c Release
   dotnet test -c Release
   ```

3. **Documentation Updates**
   - Update CHANGELOG.md with v1.0.0 changes
   - Create RELEASE_NOTES.md with release information
   - Update installation guides

### Phase 2: Automated Publishing (GitHub Actions)

1. **NuGet Publishing Workflow**
   - Triggered by: Git tag push (v1.0.0)
   - Actions:
     - Builds all projects
     - Runs test suite
     - Creates distribution package
     - Verifies all files
     - Publishes to NuGet.org
   - Duration: ~10-15 minutes

2. **GitHub Release Workflow**
   - Triggered by: Git tag push
   - Actions:
     - Prepares all artifacts
     - Creates GitHub Release
     - Uploads all files
     - Posts release notes
   - Duration: ~5-10 minutes

3. **Package Manager Workflow**
   - Triggered by: Release published
   - Actions:
     - Creates Chocolatey package
     - Creates Winget manifest
     - Prepares submission files
   - Duration: ~2-5 minutes

### Phase 3: Manual Submission (Package Managers)

1. **Chocolatey Submission**

   ```powershell
   cd choco-package
   choco pack
   choco push helios-platform.1.0.0.nupkg --key=$env:CHOCO_API_KEY
   ```

2. **Winget Submission**
   - Submit PR to: https://github.com/microsoft/winget-pkgs
   - Include: manifests/h/HELIOS/Platform/1.0.0/*

## Distribution Checklist

### Pre-Release

- [ ] All tests passing
- [ ] Code review completed
- [ ] Documentation updated
- [ ] Version number updated in all files
- [ ] CHANGELOG.md updated
- [ ] RELEASE_NOTES.md created
- [ ] Git tag created locally

### During Release

- [ ] Verify NuGet publishing workflow
- [ ] Check GitHub Release creation
- [ ] Verify artifact uploads
- [ ] Test installations from each channel
- [ ] Monitor for errors in workflows

### Post-Release

- [ ] Verify NuGet.org package
- [ ] Verify GitHub Release
- [ ] Test Chocolatey installation
- [ ] Test Winget installation
- [ ] Verify direct downloads
- [ ] Update website with release info
- [ ] Announce in community channels

## File Structure

```
dist/
└── v1.0.0/
    ├── executables/
    │   ├── HELIOS.Platform.exe
    │   ├── HELIOS-Setup.exe
    │   └── ...
    ├── nuget/
    │   ├── HELIOS.Platform.nuspec
    │   └── HELIOS.Platform.1.0.0.nupkg
    ├── demos/
    │   ├── demo-games.exe
    │   ├── demo-dev.exe
    │   └── demo-security.exe
    ├── documentation/
    │   ├── README.txt
    │   ├── INSTALLATION_GUIDE.md
    │   ├── QUICK_START.md
    │   └── ...
    ├── installer/
    │   └── Setup.exe
    ├── checksums/
    │   └── CHECKSUMS.txt
    └── CHECKSUMS.txt
```

## Deployment Scripts

### 1. prepare-distribution.ps1

Prepares all distribution files and packages.

```powershell
.\scripts\deployment\prepare-distribution.ps1 `
  -Version "1.0.0" `
  -OutputPath "dist" `
  -BuildConfiguration "Release"
```

### 2. verify-distribution.ps1

Verifies all distribution files are present and valid.

```powershell
.\scripts\deployment\verify-distribution.ps1 `
  -DistributionPath "dist" `
  -Version "1.0.0"
```

### 3. publish-nuget.ps1

Publishes NuGet package to NuGet.org.

```powershell
$env:NUGET_API_KEY = "your-api-key"
.\scripts\deployment\publish-nuget.ps1 `
  -NuSpecPath "dist\v1.0.0\nuget\HELIOS.Platform.nuspec" `
  -Version "1.0.0"
```

### 4. create-release.ps1

Creates GitHub Release with artifacts.

```powershell
$env:GITHUB_TOKEN = "your-token"
.\scripts\deployment\create-release.ps1 `
  -Version "1.0.0" `
  -DistributionPath "dist" `
  -ChangelogPath "RELEASE_NOTES.md"
```

## API Keys & Secrets

Required secrets in GitHub:

| Secret | Purpose | Acquire From |
|--------|---------|--------------|
| `NUGET_API_KEY` | NuGet.org publishing | https://www.nuget.org/account/api-keys |
| `GITHUB_TOKEN` | GitHub API access | Automatic (GitHub Actions) |
| `CHOCO_API_KEY` | Chocolatey publishing | https://community.chocolatey.org/account |

Configure in GitHub:

1. Go to: Settings → Secrets and variables → Actions
2. Click: New repository secret
3. Add each secret with corresponding value

## Troubleshooting

### NuGet Publishing Fails

- Verify API key is correct
- Check package ID uniqueness
- Review NuSpec XML formatting
- Ensure version is not already published

### GitHub Release Issues

- Verify GitHub token has write permissions
- Check artifact file sizes
- Ensure tag name matches expected format
- Review release notes formatting

### Package Manager Submissions

- Chocolatey: Wait 10-30 minutes for approval
- Winget: Submit PR, wait for community review
- Keep package descriptions updated

## Rollback Procedure

If issues are discovered after release:

### 1. NuGet.org Rollback

```powershell
# Unlist package (keeps history)
nuget delete HELIOS.Platform 1.0.0 -Source https://api.nuget.org/v3/index.json -ApiKey $key
```

### 2. GitHub Release Rollback

```powershell
git tag -d v1.0.0
git push origin :v1.0.0
# Delete release in GitHub UI
```

### 3. Chocolatey Rollback

- Contact Chocolatey support for unlisting
- Or submit updated package with patch version

### 4. Communication

- Notify all users via:
  - GitHub Release notes (correction)
  - Email to subscribers
  - Social media announcement
  - Community forums

## Monitoring & Analytics

### Track Distribution

- NuGet.org: View package statistics
- GitHub: Monitor release downloads
- Chocolatey: Check installation metrics
- Winget: Review store analytics

### Common Metrics

- Downloads per day
- Active installations
- Version adoption
- Platform usage (Windows, .NET versions)

## Release Cadence

**Version Numbering**: Semantic Versioning (Major.Minor.Patch)

- **Major (1.0.0)**: Breaking changes
- **Minor (1.1.0)**: New features
- **Patch (1.0.1)**: Bug fixes

## Support

For distribution-related questions:

- 📧 Email: support@helios-platform.org
- 🐛 Issues: https://github.com/HELIOS-Platform/helios-platform/issues
- 💬 Discussions: https://github.com/HELIOS-Platform/helios-platform/discussions

---

**Last Updated**: 2024
**Distribution System Version**: 1.0
**Status**: Production Ready
