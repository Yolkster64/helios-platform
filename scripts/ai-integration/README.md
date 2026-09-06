# HELIOS Platform - AI Integration Scripts

Complete AI integration suite for the HELIOS Platform build system, providing ChatGPT Pro and Codex-powered automation with comprehensive conflict detection and change tracking.

## 📋 Overview

This integration provides:

- **ChatGPT Pro Integration**: Build optimization, validation, suggestions, and documentation (5 scripts, 250+ lines each)
- **Codex Integration**: Code generation, refactoring, testing, and documentation (5 scripts, 250+ lines each)  
- **AI Coordination**: Conflict detection, change tracking, approval workflows, and rollback (6 scripts, 300+ lines each)
- **Production-Ready**: Full error handling, logging, rate limiting, and dry-run support

## 📁 Directory Structure

```
ai-integration/
├── config/
│   ├── .env.template          # Configuration template
│   ├── .codex-config.json     # Codex settings
│   ├── api-clients.ps1        # Shared API client functions
│   └── audit-log.json         # Audit trail
│
├── chatgpt-pro/               # ChatGPT Pro Integration
│   ├── sync-with-chatgpt.ps1
│   ├── get-ai-suggestions.ps1
│   ├── validate-with-ai.ps1
│   ├── document-with-chatgpt.ps1
│   └── chatgpt-context.md
│
├── codex-integration/         # Codex Integration
│   ├── generate-code-snippets.ps1
│   ├── refactor-with-codex.ps1
│   ├── test-with-codex.ps1
│   ├── document-with-codex.ps1
│   └── .codex-config.json
│
└── ai-coordination/           # AI Coordination
    ├── detect-ai-conflicts.ps1
    ├── resolve-ai-conflicts.ps1
    ├── track-ai-modifications.ps1
    ├── approve-ai-changes.ps1
    ├── view-ai-version-history.ps1
    └── rollback-ai-change.ps1
```

## 🚀 Quick Start

### 1. Configuration

```powershell
# Copy template and configure
Copy-Item config\.env.template config\.env
code config\.env
```

### 2. Test Connection

```powershell
cd chatgpt-pro
.\sync-with-chatgpt.ps1 -DryRun -Verbose
```

### 3. Get Recommendations

```powershell
.\get-ai-suggestions.ps1 -FocusArea all -SaveResults
```

## 🔧 Scripts

### ChatGPT Pro

**sync-with-chatgpt.ps1** - Initialize and sync configurations

```powershell
.\sync-with-chatgpt.ps1 [-DryRun] [-Verbose]
```

**get-ai-suggestions.ps1** - Get optimization suggestions

```powershell
.\get-ai-suggestions.ps1 -FocusArea {performance|caching|dependencies|security|all}
```

**validate-with-ai.ps1** - Validate configurations

```powershell
.\validate-with-ai.ps1 -ConfigPath ./build-config.json [-StrictMode]
```

**document-with-chatgpt.ps1** - Generate documentation

```powershell
.\document-with-chatgpt.ps1 -DocumentType {guide|reference|troubleshooting|all}
```

### Codex

**generate-code-snippets.ps1** - Generate code

```powershell
.\generate-code-snippets.ps1 -Description "parallel build runner" -Language powershell
```

**refactor-with-codex.ps1** - Analyze and refactor

```powershell
.\refactor-with-codex.ps1 -FilePath ./build.ps1
```

**test-with-codex.ps1** - Generate tests

```powershell
.\test-with-codex.ps1 -CodeFile ./build.ps1 -TestFramework pester
```

**document-with-codex.ps1** - Generate documentation

```powershell
.\document-with-codex.ps1 -FilePath ./build.ps1
```

### AI Coordination

**detect-ai-conflicts.ps1** - Find conflicts

```powershell
.\detect-ai-conflicts.ps1 -RecommendationFiles @('./rec1.json', './rec2.json')
```

**resolve-ai-conflicts.ps1** - Resolve conflicts

```powershell
.\resolve-ai-conflicts.ps1 -ConflictFile ./conflicts.json
```

**track-ai-modifications.ps1** - Track changes

```powershell
.\track-ai-modifications.ps1 -Action summary
.\track-ai-modifications.ps1 -Action record -ChangeDescription "..." -ApprovalStatus pending
```

**approve-ai-changes.ps1** - Approve changes

```powershell
.\approve-ai-changes.ps1 -RecommendationFile ./recommendations.json
```

**view-ai-version-history.ps1** - View history

```powershell
.\view-ai-version-history.ps1 [-Filter {all|pending|approved|rejected}]
```

**rollback-ai-change.ps1** - Rollback modifications

```powershell
.\rollback-ai-change.ps1 -ModificationId abc123def456 [-DryRun]
```

## 🔐 Features

- ✅ API key protection and environment variable support
- ✅ Comprehensive error handling
- ✅ Rate limiting (60 req/min default)
- ✅ Dry-run mode for safe testing
- ✅ Complete audit trail
- ✅ Conflict detection and resolution
- ✅ Interactive approval workflows
- ✅ Modification rollback capability
- ✅ Sanitized logging
- ✅ Production-ready

## 🔑 Configuration

### .env Variables

```bash
# OpenAI
OPENAI_API_KEY=sk-xxxxx
OPENAI_MODEL=gpt-4
OPENAI_MAX_TOKENS=4096
OPENAI_TEMPERATURE=0.7

# Codex
CODEX_API_KEY=sk-xxxxx
CODEX_ENGINE=code-davinci-002
CODEX_MAX_TOKENS=2048

# Rate Limiting
OPENAI_RATE_LIMIT=60
ENABLE_RATE_LIMITING=true

# Logging
LOG_LEVEL=INFO
LOG_DIR=./logs
SANITIZE_LOGS=true
```

## 📊 All Scripts Overview

### Statistics

- **Total Scripts**: 19
- **ChatGPT Pro**: 5 scripts (250+ lines each)
- **Codex Integration**: 5 scripts (250+ lines each)
- **AI Coordination**: 6 scripts (300+ lines each)
- **Configuration**: 3 files (templates + audit log)
- **Shared Functions**: 1 module (16 KB)

### Capabilities

- Code generation in 4 languages (PowerShell, Bash, C#, Python)
- Test generation for 4 frameworks (Pester, xUnit, NUnit, pytest)
- Documentation in 3 formats (Markdown, XML, Doxygen)
- 5 refactoring types (performance, quality, modernize, simplify, security)
- Multi-level conflict detection and resolution
- Complete audit trail with version history
- Interactive approval workflows

## 🛠️ Workflow Example

```powershell
# 1. Initialize and sync
.\chatgpt-pro\sync-with-chatgpt.ps1 -DryRun

# 2. Get suggestions
.\chatgpt-pro\get-ai-suggestions.ps1 -FocusArea all -SaveResults

# 3. Validate
.\chatgpt-pro\validate-with-ai.ps1 -ConfigPath ./build-config.json

# 4. Detect conflicts
.\ai-coordination\detect-ai-conflicts.ps1 -RecommendationFiles @('./suggestions.json')

# 5. Approve
.\ai-coordination\approve-ai-changes.ps1 -RecommendationFile ./suggestions.json

# 6. Track
.\ai-coordination\track-ai-modifications.ps1 -Action summary

# 7. Document
.\chatgpt-pro\document-with-chatgpt.ps1 -DocumentType guide -OutputDir ./docs
```

## 📚 Documentation

- See **README** in each subdirectory for detailed documentation
- Review **chatgpt-context.md** for system prompts
- Check **.codex-config.json** for code generation settings
- View **audit-log.json** for modification history

## 🔄 Update Process

1. Test with `-DryRun`
2. Review recommendations in logs
3. Use interactive approval workflow
4. Track modifications in audit log
5. Generate documentation
6. Rollback if needed

## ⚙️ Best Practices

1. **Always use dry-run first** for preview
2. **Track all modifications** through coordination scripts
3. **Review before approval** with interactive workflow
4. **Enable verbose logging** for troubleshooting
5. **Maintain backup** of audit log
6. **Use rate limiting** to respect API quotas
7. **Sanitize logs** in production environments

## 📖 Help

```powershell
# Get help for any script
Get-Help .\script-name.ps1 -Full

# Run with verbose output
.\script-name.ps1 -Verbose

# Preview with dry-run
.\script-name.ps1 -DryRun
```

## 📝 Version

**Version**: 1.0.0  
**Last Updated**: 2024-01-15  
**Status**: Production-Ready

---

**HELIOS Platform AI Integration Suite**  
Complete automation for build optimization, code generation, and AI coordination.
