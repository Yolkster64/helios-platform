# ChatGPT Pro Integration Guide

Complete setup and usage guide for integrating OpenAI's ChatGPT Pro (GPT-4) with HELIOS Platform.

## Overview

ChatGPT Pro integration enables intelligent assistance for:

- Build phase planning and optimization
- Security analysis and risk assessment
- Component conflict detection
- Performance recommendations
- Code review and analysis
- Change impact prediction

## API Setup

### Step 1: Obtain API Key

1. Go to [OpenAI Platform](https://platform.openai.com)
2. Sign up or log in to your account
3. Navigate to API keys section
4. Create a new secret key
5. Copy the key (shown only once)

### Step 2: Configure Environment

Store your API key securely:

```powershell
# Option 1: Set environment variable (temporary, session-only)
$env:OPENAI_API_KEY = "sk-your-actual-key-here"

# Option 2: Set permanently in user profile
[Environment]::SetEnvironmentVariable("OPENAI_API_KEY", "sk-your-key", "User")

# Option 3: Use secure vault (recommended for production)
# Store in Windows Credential Manager
cmdkey /add:openai /user:api-key /pass:"sk-your-key-here"
```

### Step 3: Verify Access

```powershell
# Test API connectivity
$headers = @{
    "Authorization" = "Bearer $env:OPENAI_API_KEY"
    "Content-Type" = "application/json"
}

$body = @{
    "model" = "gpt-4"
    "messages" = @(@{"role" = "user"; "content" = "Hello"})
    "max_tokens" = 100
} | ConvertTo-Json

$response = Invoke-RestMethod -Uri "https://api.openai.com/v1/chat/completions" `
    -Method Post -Headers $headers -Body $body

Write-Host "API Status: Success" -ForegroundColor Green
```

## API Specifications

### Endpoints

**Chat Completions Endpoint**

```
POST https://api.openai.com/v1/chat/completions
```

### Request Format

```json
{
  "model": "gpt-4",
  "messages": [
    {
      "role": "system",
      "content": "You are a HELIOS AppLocker expert..."
    },
    {
      "role": "user",
      "content": "What phases should I enable?"
    }
  ],
  "temperature": 0.7,
  "max_tokens": 2000,
  "top_p": 1.0
}
```

### Response Format

```json
{
  "id": "chatcmpl-8J3x...",
  "object": "chat.completion",
  "created": 1705324800,
  "model": "gpt-4-0613",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Based on your requirements..."
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 150,
    "completion_tokens": 500,
    "total_tokens": 650
  }
}
```

## System Prompts

System prompts are the most critical element of ChatGPT integration. They define the AI's behavior, expertise level, and response format.

### Effective System Prompt Structure

```
1. Role Definition: "You are a [specific role]"
2. Context: "[HELIOS/Security/Technical Context]"
3. Expertise Areas: List specific knowledge areas
4. Response Format: Specify JSON, markdown, bullet points, etc.
5. Constraints: Safety, compliance, and business rules
6. Example: Show desired output format
```

### Example System Prompt

```
You are a HELIOS AppLocker Security Expert with 10+ years of Windows security experience.

Context: You provide recommendations for Microsoft AppLocker policies in the HELIOS Platform.
Your expertise includes:
- AppLocker phases (Audit, Enforcement, Hybrid)
- Rule types (Publisher, Hash, Path, File Attributes)
- Group Policy integration
- Performance impact analysis
- Security hardening techniques

Rules:
1. Always consider business requirements alongside security
2. Recommend audit mode before enforcement
3. Warn about potential application breaks
4. Suggest backup strategies for rule modification
5. Reference official Microsoft documentation
6. Provide specific, actionable recommendations

Response Format:
- Start with a brief summary
- Provide numbered recommendations
- Include risk assessment for each recommendation
- End with testing strategy

Example:
[Provide example of desired output structure]
```

## Conversation Patterns

### Pattern 1: Phase Planning

Use this pattern to get ChatGPT to recommend optimal AppLocker phases:

```powershell
$systemPrompt = @"
You are a HELIOS AppLocker phase planning expert. Your role is to recommend 
the optimal sequence of AppLocker phases (Audit → Enforcement → Hybrid) 
based on organizational requirements.

Provide recommendations in this JSON format:
{
  "recommended_phases": ["Audit", "Enforcement"],
  "duration_per_phase": "2-4 weeks",
  "risk_level": "Medium",
  "success_criteria": ["Monitoring shows X% compliance"],
  "monitoring_points": ["Check event logs weekly"]
}
"@

$userPrompt = @"
We have 10,000 users in our organization. We want to enable AppLocker 
for Microsoft Office applications. Currently, we're in audit mode.

What phases should we follow? How long should we stay in each phase?
"@

# This will be handled by invoke-chatgpt.ps1
```

### Pattern 2: Optimization Suggestions

```powershell
$systemPrompt = @"
You are a HELIOS AppLocker optimization specialist. Your task is to analyze 
AppLocker rules and suggest optimizations for:
- Rule consolidation (combining similar rules)
- Performance improvement
- Maintainability enhancement
- Coverage gap identification

Provide analysis in JSON with:
- Current state assessment
- Issues identified
- Specific optimization recommendations
- Estimated performance improvement
"@

$userPrompt = @"
I have analyzed my AppLocker logs and found:
- 500 total rules
- 50 duplicate rules with different criteria
- 150 hash rules that could be consolidated to path rules
- 30 rules that never matched any events

How should I optimize this rule set?
"@
```

### Pattern 3: Component Conflict Detection

```powershell
$systemPrompt = @"
You are a HELIOS AppLocker conflict detection specialist. You analyze 
AppLocker rules for potential conflicts, precedence issues, and problematic 
interactions.

Analyze for:
1. Rule precedence conflicts
2. Overlapping conditions that create ambiguity
3. Exception rules that might be bypassed
4. Performance implications of rule count
5. Maintenance complexity

Format response as JSON with:
- Conflicts identified (array)
- Risk level for each (High/Medium/Low)
- Recommended resolution
- Testing approach
"@

$userPrompt = @"
I have these AppLocker rules:
- Rule 1: Allow all executables in C:\Program Files\*
- Rule 2: Deny executables from C:\Program Files\BadApp\*
- Rule 3: Allow C:\Program Files\BadApp\SafeModule.exe by hash

Will these rules conflict? What's the precedence?
"@
```

### Pattern 4: Build Recommendations

```powershell
$systemPrompt = @"
You are a HELIOS Platform build advisor. Your role is to recommend 
which AppLocker features and components users should enable based on 
their specific requirements and environment.

Provide recommendations as JSON:
{
  "recommended_components": ["Publisher Rules", "Path Rules"],
  "phases": ["Audit", "Enforcement"],
  "features": ["Group Policy Integration"],
  "prerequisites": ["Active Directory"],
  "estimated_effort": "40 hours",
  "success_probability": "85%"
}
"@

$userPrompt = @"
Small company with 50 employees, mix of Windows 10/11, basic security 
requirements. We want to prevent unauthorized software installation. 
What's the best build strategy?
"@
```

### Pattern 5: Security Analysis

```powershell
$systemPrompt = @"
You are a HELIOS security architect. Analyze AppLocker configurations 
for security implications, gaps, and risks.

Assess:
1. Coverage gaps
2. Bypass potential
3. Business continuity risks
4. Compliance implications
5. Exploitation vectors

Output JSON with risk matrix and mitigations.
"@

$userPrompt = @"
I'm implementing AppLocker with only Publisher rules. What are the 
security gaps and how do I address them?
"@
```

### Pattern 6: Change Analysis

```powershell
$systemPrompt = @"
You are a HELIOS change impact analyst. Predict the effects of 
AppLocker configuration changes before deployment.

Analyze impact on:
1. Application functionality
2. User experience
3. Performance
4. Security posture
5. Compliance

Provide predictions with confidence levels.
"@

$userPrompt = @"
I want to change from Publisher rules to Path rules for better performance.
What are the impacts of this change?
"@
```

## Best Practices

### Prompt Engineering

1. **Be Specific**: Provide detailed context

   ```
   ❌ Bad: "Give me AppLocker advice"
   ✅ Good: "I have 500 AppLocker rules for Office. Current issues: 50 duplicates, 
            30 non-matching rules. Environment: 10k users, hybrid cloud. Goal: 
            reduce rule count by 30%. Should I consolidate to path rules?"
   ```

2. **Provide Context**: Include constraints and requirements

   ```
   ✅ "We must maintain compatibility with legacy app XYZ. We're migrating 
        to cloud. We need audit logging for compliance."
   ```

3. **Request Specific Format**: Ask for structured responses

   ```
   ✅ "Provide your analysis as JSON with fields: issues, solutions, 
        risk_level, testing_approach"
   ```

4. **Reference System Prompts**: Use our predefined personas

   ```
   ✅ Use the "Security Architect" system prompt for security concerns
   ```

### Cost Optimization

1. **Use Caching**: Store responses for repeated questions
   - Implement response caching in scripts
   - Cache frequently used system prompts
   - Estimated savings: 50-70%

2. **Batch Requests**: Group related questions

   ```
   ❌ Send 10 separate API calls for 10 questions
   ✅ Combine into single well-structured prompt
   ```

3. **Use Appropriate Models**

   ```
   gpt-3.5-turbo  → Quick questions, general guidance ($0.0005/1K tokens)
   gpt-4          → Complex analysis, security decisions ($0.03/1K tokens)
   ```

4. **Set Token Limits**

   ```powershell
   # Limit responses to save money
   "max_tokens" = 1000  # Instead of default 2000+
   ```

### Response Quality

1. **Validate Outputs**: Always verify AI responses
   - Security recommendations: Validate against best practices
   - Code suggestions: Test in non-production environment
   - Analysis: Cross-reference with official documentation

2. **Temperature Settings**

   ```
   Temperature 0.3-0.5   → Analytical, factual responses (analysis, code)
   Temperature 0.7       → Balanced creativity and accuracy (planning)
   Temperature 0.9+      → Creative, varied responses (brainstorming)
   ```

3. **Request Follow-ups**: Build multi-turn conversations

   ```
   - Initial question: Get overview
   - Follow-up: Deep dive into specific area
   - Validation: Confirm recommendations
   ```

## Integration with Scripts

The `ask-chatgpt.ps1` script provides a ready-to-use PowerShell interface:

```powershell
# Basic usage
. .\scripts\ask-chatgpt.ps1

$response = Invoke-ChatGPT `
    -Prompt "What phases should I enable?" `
    -SystemPrompt "HELIOS Optimizer"

# Advanced usage with caching
$response = Invoke-ChatGPT `
    -Prompt "Complex security analysis..." `
    -SystemPrompt "Security Architect" `
    -Model "gpt-4" `
    -Temperature 0.3 `
    -UseCache $true `
    -CacheDuration (New-TimeSpan -Hours 24)

# Extract specific fields from JSON response
$recommendations = $response.choices[0].message.content | ConvertFrom-Json
foreach ($rec in $recommendations.items) {
    Write-Host "- $($rec.title): $($rec.description)"
}
```

## Error Handling

### Common Errors and Solutions

| Error | Cause | Solution |
|-------|-------|----------|
| 401 Unauthorized | Invalid API key | Verify key in environment variable |
| 429 Rate Limited | Too many requests | Implement exponential backoff |
| 500 Server Error | OpenAI service issue | Retry with exponential backoff |
| Timeout | Network/API slow | Increase timeout, reduce token limit |
| 403 Forbidden | Quota exceeded | Check API usage in OpenAI dashboard |

### Retry Strategy

```powershell
function Invoke-ChatGPTWithRetry {
    param(
        [string]$Prompt,
        [int]$MaxRetries = 3,
        [int]$InitialWaitSeconds = 1
    )
    
    for ($i = 0; $i -lt $MaxRetries; $i++) {
        try {
            return Invoke-ChatGPT -Prompt $Prompt
        }
        catch {
            if ($i -lt $MaxRetries - 1) {
                $waitTime = $InitialWaitSeconds * [Math]::Pow(2, $i)
                Write-Host "Retry attempt $($i+1) after ${waitTime}s..."
                Start-Sleep -Seconds $waitTime
            }
        }
    }
}
```

## Monitoring and Logging

### Log Format

```powershell
# All ChatGPT interactions are logged:
[2024-01-15T10:30:00Z] CHATGPT_REQUEST
- Prompt: "What phases..."
- System: "HELIOS Optimizer"
- Model: "gpt-4"
- Tokens: 150 → 500
- Cost: $0.0195
- Duration: 2.3s
- Status: Success

[2024-01-15T10:30:02Z] CHATGPT_RESPONSE
- Content: "Based on requirements..."
- Cached: No
```

### Cost Tracking

```powershell
# Track API costs over time
$costs = @{
    "gpt-4"         = @{ "input" = 0.03; "output" = 0.06 }
    "gpt-3.5-turbo" = @{ "input" = 0.0005; "output" = 0.0015 }
}

# Calculate cost for your request
$inputTokens = 150
$outputTokens = 500
$model = "gpt-4"
$cost = ($inputTokens * $costs[$model].input + 
         $outputTokens * $costs[$model].output) / 1000

Write-Host "Estimated cost: `$$($cost.ToString('F4'))"
```

## Security Considerations

### API Key Security

- ✅ Store in environment variables (session scope)
- ✅ Store in Windows Credential Manager (persistent)
- ✅ Use separate keys for prod/dev/test
- ❌ Never commit to version control
- ❌ Never log API keys
- ❌ Never share in chat/email

### Prompt Injection Prevention

```powershell
# ❌ UNSAFE: Direct user input
$userInput = "What should I do?"
$prompt = "User question: $userInput"

# ✅ SAFE: Sanitized input with clear boundaries
$userInput = "What should I do?"
$prompt = @"
User Question:
---
$userInput
---
Please analyze as HELIOS expert.
"@
```

### Response Validation

```powershell
# Always validate AI responses before using them
function Validate-ChatGPTResponse {
    param([PSObject]$Response)
    
    # Check for credential leaks
    if ($Response.content -match "password|api.?key|secret") {
        throw "Response contains sensitive data!"
    }
    
    # Check for code injection vectors
    if ($Response.content -match '(cmd\.exe|powershell.*-nop|bypass)') {
        Write-Warning "Response may contain bypass attempts"
    }
    
    return $true
}
```

## Next Steps

1. **Set up API key** (Step 1-3 above)
2. **Review system prompts** (`SYSTEM_PROMPTS.md`)
3. **Test integration** using `scripts/ask-chatgpt.ps1`
4. **Review monitoring and logging** setup
5. **Implement in production** with proper approval workflows

## Additional Resources

- [OpenAI API Documentation](https://platform.openai.com/docs/api-reference)
- [GPT-4 Release Notes](https://openai.com/research/gpt-4)
- [Best Practices](https://platform.openai.com/docs/guides/gpt-best-practices)
- [HELIOS System Prompts](./SYSTEM_PROMPTS.md)
