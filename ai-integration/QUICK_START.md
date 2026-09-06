# HELIOS AI Integration - Quick Start Guide

## Installation

### 1. Verify Directory Structure

```powershell
# Check that all files are in place
Get-ChildItem -Path "C:\Users\ADMIN\helios-platform\ai-integration" -Recurse | 
    Select-Object FullName | 
    Format-Table -AutoSize
```

### 2. Set Up API Keys

```powershell
# ChatGPT Pro Setup
$env:OPENAI_API_KEY = "sk-your-actual-openai-key-here"

# Persist for future sessions (optional)
[Environment]::SetEnvironmentVariable("OPENAI_API_KEY", "sk-your-key", "User")

# Verify it's set
Write-Host "API Key configured: $($env:OPENAI_API_KEY.Substring(0,7))..."
```

### 3. Test ChatGPT Integration

```powershell
# Load the ChatGPT script
. "C:\Users\ADMIN\helios-platform\ai-integration\scripts\ask-chatgpt.ps1"

# Test basic functionality
$response = Invoke-ChatGPT -Prompt "Hello, what is AppLocker?" `
    -SystemPrompt "You are a helpful security expert" `
    -Model "gpt-3.5-turbo" `
    -MaxTokens 500

# Display response
Write-Host $response.choices[0].message.content
```

### 4. Test Codex Integration

```powershell
# Load the Codex script
. "C:\Users\ADMIN\helios-platform\ai-integration\scripts\ask-codex.ps1"

# Test code generation
$spec = @"
Generate a simple PowerShell function that:
- Takes a file path as input
- Checks if file exists
- Returns file info
- Includes error handling
"@

$code = Invoke-Codex -Spec $spec -Language "powershell" `
    -AddSafetyChecks $true

Write-Host $code
```

## Common Tasks

### Task 1: Get Build Recommendations

```powershell
# Load ChatGPT
. "C:\Users\ADMIN\helios-platform\ai-integration\scripts\ask-chatgpt.ps1"

# Ask for build strategy
$buildRec = Invoke-ChatGPT `
    -Prompt @"
We have 5000 users across 3 departments. We want to implement AppLocker 
for Microsoft Office. What phases should we follow?
"@ `
    -SystemPrompt "You are a HELIOS Build Advisor with expertise in AppLocker deployment" `
    -Model "gpt-4" `
    -Temperature 0.5

Write-Host $buildRec.choices[0].message.content
```

### Task 2: Generate AppLocker Script

```powershell
# Load Codex
. "C:\Users\ADMIN\helios-platform\ai-integration\scripts\ask-codex.ps1"

# Generate rule consolidation script
$spec = @"
Generate a PowerShell script that:
1. Reads all AppLocker rules from Group Policy
2. Identifies rules that can be consolidated
3. Generates a report of consolidation opportunities
4. Creates a backup of current rules
5. Includes comprehensive error handling and logging
"@

$script = Invoke-Codex -Spec $spec -Language "powershell" `
    -IncludeErrorHandling $true `
    -AddSafetyChecks $true

# Save to file
$script | Set-Content -Path "consolidate-rules.ps1" -Encoding UTF8
Write-Host "Script saved to consolidate-rules.ps1"
```

### Task 3: Get Security Analysis

```powershell
# Load ChatGPT
. "C:\Users\ADMIN\helios-platform\ai-integration\scripts\ask-chatgpt.ps1"

# Ask for security review
$secReview = Invoke-ChatGPT `
    -Prompt @"
I'm planning to use only Publisher rules for AppLocker. 
What are the security gaps and how do I address them?
"@ `
    -SystemPrompt "You are a HELIOS Security Architect with expertise in AppLocker security" `
    -Model "gpt-4" `
    -Temperature 0.3

Write-Host $secReview.choices[0].message.content
```

### Task 4: Coordinate AI Recommendations

```powershell
# Load all scripts
. "C:\Users\ADMIN\helios-platform\ai-integration\scripts\ask-chatgpt.ps1"
. "C:\Users\ADMIN\helios-platform\ai-integration\scripts\ask-codex.ps1"
. "C:\Users\ADMIN\helios-platform\ai-integration\scripts\coordinate-ai.ps1"

# Get planning from ChatGPT
$planning = Invoke-ChatGPT -Prompt "Should we consolidate our 500 rules?" `
    -SystemPrompt "You are an optimizer" -Model "gpt-4"

# Generate code with Codex
$spec = $planning.choices[0].message.content
$code = Invoke-Codex -Spec $spec -Language "powershell"

# Coordinate results
$coordination = Invoke-AICoordination `
    -ChatGPTResponse $planning `
    -CodexResponse $code `
    -ConflictResolution $true `
    -GenerateReport $true
```

## Advanced Usage

### Using System Prompts

```powershell
# Review available system prompts
Get-Content "C:\Users\ADMIN\helios-platform\ai-integration\chatgpt-integration\SYSTEM_PROMPTS.md"

# Use predefined personas
$systemPrompts = @{
    Optimizer = "You are a HELIOS AppLocker optimization specialist..."
    SecurityArchitect = "You are a HELIOS Security Architect..."
    PerformanceAnalyst = "You are a HELIOS Performance Analyst..."
    BuildAdvisor = "You are a HELIOS Build Advisor..."
    ConflictDetector = "You are a HELIOS Conflict Detection Expert..."
    CodeReviewer = "You are a HELIOS Code Review Expert..."
}

# Use one
$response = Invoke-ChatGPT -Prompt "Optimize our rules" `
    -SystemPrompt $systemPrompts.Optimizer
```

### Batch Operations

```powershell
# Generate multiple scripts in batch
. "C:\Users\ADMIN\helios-platform\ai-integration\scripts\ask-codex.ps1"

$specs = @(
    "Generate rule validation script",
    "Generate rule consolidation script",
    "Generate audit logging script"
)

foreach ($spec in $specs) {
    $code = Invoke-Codex -Spec $spec -Language "powershell" `
        -AddSafetyChecks $true
    
    $fileName = ($spec -replace ' ', '-').ToLower() + ".ps1"
    $code | Set-Content -Path $fileName -Encoding UTF8
    Write-Host "Generated: $fileName"
}
```

### Monitoring Costs

```powershell
# Load ChatGPT script for cost calculation
. "C:\Users\ADMIN\helios-platform\ai-integration\scripts\ask-chatgpt.ps1"

# Check logs
$logDir = "$env:LOCALAPPDATA\helios-ai-logs"
$logs = Get-Content "$logDir\chatgpt-*.log" | 
    Select-String "Cost:" | 
    ForEach-Object { [double]($_ -replace '.*Cost: \$', '').Split("`n")[0] }

$totalCost = ($logs | Measure-Object -Sum).Sum
Write-Host "Total ChatGPT cost: `$$totalCost"
```

## Troubleshooting

### Issue: "OPENAI_API_KEY environment variable not set"

```powershell
# Verify key is set
if ($env:OPENAI_API_KEY) {
    Write-Host "✓ API key is set"
} else {
    Write-Host "✗ API key not found"
    Write-Host "  Solution: Run:"
    Write-Host "  `$env:OPENAI_API_KEY = 'sk-your-key-here'"
}
```

### Issue: "API returns 401 Unauthorized"

```powershell
# Check key validity
$testKey = $env:OPENAI_API_KEY
Write-Host "Key length: $($testKey.Length)"
Write-Host "Starts with 'sk-': $($testKey.StartsWith('sk-'))"
Write-Host "Action: Generate new key at https://platform.openai.com/api-keys"
```

### Issue: "Code generation quality is poor"

```powershell
# Solution: Be more specific in your spec
# Bad:
$spec = "Generate PowerShell script"

# Good:
$spec = @"
Generate PowerShell script that:
1. Accepts input parameter 'Path' (required, type string)
2. Lists all executable files recursively
3. Returns array of file objects with properties: Name, Path, Size
4. Includes Try-Catch error handling
5. Validates path exists before processing
6. Logs all operations to Windows Event Log
"@
```

### Issue: "Conflicts detected between AI services"

```powershell
# Check the coordination report
$coordination = Invoke-AICoordination -ChatGPTResponse $gpt `
    -CodexResponse $codex -GenerateReport $true

# Review the report output for conflict details
# Contact security team if severity is High
```

## Best Practices

### ✅ DO

- Test generated code in non-production first
- Review all AI-generated code before use
- Document why you chose one AI recommendation over another
- Use caching to reduce API costs
- Monitor token usage and costs
- Keep API keys secure in environment variables
- Version control your approved AI-generated code
- Use specific, detailed prompts
- Set appropriate temperature for task type

### ❌ DON'T

- Don't commit API keys to version control
- Don't run generated code without review
- Don't ignore security warnings from validation
- Don't use generic, vague prompts
- Don't rely solely on AI for critical decisions
- Don't ignore conflict warnings
- Don't skip testing
- Don't use in production without approval
- Don't modify approved code without re-review

## Integration with CI/CD

The GitHub Actions workflow (`.github/workflows/ai-code-review.yml`) provides:

1. **Automatic security scanning** on all PR code
2. **Credential detection** to prevent leaks
3. **Syntax validation** for PowerShell code
4. **Documentation checks**
5. **Flags AI-generated code** for required review

To enable:

```powershell
# Workflow is already in place at:
# .github/workflows/ai-code-review.yml

# It runs on all PRs automatically
# Check Results → AI Code Review Pipeline
```

## Getting Help

### Documentation

- [Main README](./ai-integration/README.md) - Overview and setup
- [ChatGPT Integration](./ai-integration/chatgpt-integration/README.md) - API details
- [System Prompts](./ai-integration/chatgpt-integration/SYSTEM_PROMPTS.md) - Pre-built prompts
- [Codex Integration](./ai-integration/codex-integration/README.md) - Code generation
- [Code Templates](./ai-integration/codex-integration/CODE_GENERATION_TEMPLATES.md) - Generation templates
- [AI Coordination](./ai-integration/ai-coordination/README.md) - Multi-AI workflows
- [Conflict Resolution](./ai-integration/ai-coordination/CONFLICT_RESOLUTION.md) - Handling conflicts
- [Version Control](./ai-integration/ai-coordination/VERSION_CONTROL.md) - Tracking AI code

### Quick Links

- OpenAI API Docs: https://platform.openai.com/docs/api-reference
- GPT-4 Capabilities: https://openai.com/research/gpt-4
- GitHub Copilot: https://github.com/features/copilot

## Next Steps

1. ✅ Set up API keys (done in step 2)
2. ✅ Test integrations (done in steps 3-4)
3. 📋 Start with simple tasks (get a recommendation)
4. 🚀 Graduate to code generation
5. 🔄 Implement AI coordination workflow
6. 📊 Monitor costs and usage
7. 🎓 Train team on best practices

## Support

- Check logs: `$env:LOCALAPPDATA\helios-ai-logs\`
- Review examples in this guide
- Check documentation for your use case
- File an issue on GitHub if problems persist
