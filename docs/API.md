# {{PROJECT_NAME}} - Complete API Reference

**Template Version:** 1.0  
**API Version:** {{API_VERSION}}  
**Last Updated:** {{LAST_UPDATED}}

---

## 📚 API Overview

This document provides complete reference for all {{PROJECT_NAME}} functions, including:

- Function signatures and parameters
- Return values and types
- Usage examples
- Error handling
- Performance considerations

---

## 🔍 Quick Reference

### Function Categories

| Category | Count | Purpose |
|----------|-------|---------|
| {{CATEGORY_1}} | {{COUNT_1}} | {{PURPOSE_1}} |
| {{CATEGORY_2}} | {{COUNT_2}} | {{PURPOSE_2}} |
| {{CATEGORY_3}} | {{COUNT_3}} | {{PURPOSE_3}} |
| {{CATEGORY_4}} | {{COUNT_4}} | {{PURPOSE_4}} |

**Total Functions:** {{TOTAL_FUNCTIONS}}

---

## {{CATEGORY_1}} Functions

### {{FUNCTION_1}}

**Synopsis:** {{FUNCTION_1_SYNOPSIS}}

**Syntax:**

```powershell
{{FUNCTION_1_SYNTAX}}
```

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| {{PARAM_1_1}} | {{TYPE_1_1}} | {{REQ_1_1}} | {{DEF_1_1}} | {{DESC_1_1}} |
| {{PARAM_1_2}} | {{TYPE_1_2}} | {{REQ_1_2}} | {{DEF_1_2}} | {{DESC_1_2}} |
| {{PARAM_1_3}} | {{TYPE_1_3}} | {{REQ_1_3}} | {{DEF_1_3}} | {{DESC_1_3}} |

**Returns:**

```
Type: {{RETURN_TYPE}}
Description: {{RETURN_DESC}}
```

**Example:**

```powershell
# {{EXAMPLE_1_DESC}}
{{EXAMPLE_1_CODE}}

# Expected output
{{EXAMPLE_1_OUTPUT}}
```

**Error Handling:**

```powershell
try {
    {{FUNCTION_1}} -Parameter1 $value
} catch {
    Write-Error "{{ERROR_DESC}}: $($_.Exception.Message)"
}
```

**Performance Notes:**

- Time Complexity: {{TIME_COMPLEXITY}}
- Space Complexity: {{SPACE_COMPLEXITY}}
- Typical Duration: {{TYPICAL_DURATION}}

**See Also:**

- {{RELATED_FUNC_1}}
- {{RELATED_FUNC_2}}

---

### {{FUNCTION_2}}

**Synopsis:** {{FUNCTION_2_SYNOPSIS}}

**Syntax:**

```powershell
{{FUNCTION_2_SYNTAX}}
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| {{PARAM_2_1}} | {{TYPE_2_1}} | Yes | {{DESC_2_1}} |
| {{PARAM_2_2}} | {{TYPE_2_2}} | No | {{DESC_2_2}} |

**Returns:**

```
Type: {{RETURN_TYPE_2}}
```

**Example:**

```powershell
{{EXAMPLE_2_CODE}}
```

---

### {{FUNCTION_3}}

**Synopsis:** {{FUNCTION_3_SYNOPSIS}}

**Syntax:**

```powershell
{{FUNCTION_3_SYNTAX}}
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| {{PARAM_3_1}} | {{TYPE_3_1}} | {{REQ_3_1}} | {{DESC_3_1}} |

**Returns:**

```
Type: {{RETURN_TYPE_3}}
```

**Example:**

```powershell
{{EXAMPLE_3_CODE}}
```

---

## {{CATEGORY_2}} Functions

### {{FUNCTION_4}}

**Synopsis:** {{FUNCTION_4_SYNOPSIS}}

**Syntax:**

```powershell
{{FUNCTION_4_SYNTAX}}
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| {{PARAM_4_1}} | {{TYPE_4_1}} | {{REQ_4_1}} | {{DESC_4_1}} |
| {{PARAM_4_2}} | {{TYPE_4_2}} | {{REQ_4_2}} | {{DESC_4_2}} |

**Returns:**

```
Type: {{RETURN_TYPE_4}}
```

**Example:**

```powershell
{{EXAMPLE_4_CODE}}
```

---

### {{FUNCTION_5}}

**Synopsis:** {{FUNCTION_5_SYNOPSIS}}

**Example:**

```powershell
{{EXAMPLE_5_CODE}}
```

---

## {{CATEGORY_3}} Functions

### {{FUNCTION_6}}

**Synopsis:** {{FUNCTION_6_SYNOPSIS}}

**Syntax:**

```powershell
{{FUNCTION_6_SYNTAX}}
```

**Example:**

```powershell
{{EXAMPLE_6_CODE}}
```

---

## {{CATEGORY_4}} Functions

### {{FUNCTION_7}}

**Synopsis:** {{FUNCTION_7_SYNOPSIS}}

**Syntax:**

```powershell
{{FUNCTION_7_SYNTAX}}
```

**Example:**

```powershell
{{EXAMPLE_7_CODE}}
```

---

## 🔄 Common Workflows

### Workflow 1: {{WORKFLOW_1_NAME}}

**Objective:** {{WORKFLOW_1_OBJECTIVE}}

**Steps:**

1. {{WORKFLOW_1_STEP_1}}
2. {{WORKFLOW_1_STEP_2}}
3. {{WORKFLOW_1_STEP_3}}

**Complete Example:**

```powershell
# Workflow: {{WORKFLOW_1_NAME}}

# Step 1: {{WORKFLOW_1_STEP_1}}
$result1 = {{FUNCTION_FOR_STEP_1}} -Parameter {{VALUE_1}}

# Step 2: {{WORKFLOW_1_STEP_2}}
$result2 = {{FUNCTION_FOR_STEP_2}} -Input $result1

# Step 3: {{WORKFLOW_1_STEP_3}}
{{FUNCTION_FOR_STEP_3}} -Data $result2
```

---

### Workflow 2: {{WORKFLOW_2_NAME}}

**Objective:** {{WORKFLOW_2_OBJECTIVE}}

**Complete Example:**

```powershell
{{WORKFLOW_2_CODE}}
```

---

## 🔐 Authentication

### Authentication Functions

#### {{AUTH_FUNCTION_1}}

**Purpose:** {{AUTH_FUNCTION_1_PURPOSE}}

**Syntax:**

```powershell
{{AUTH_FUNCTION_1_SYNTAX}}
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| {{AUTH_PARAM_1}} | {{AUTH_PARAM_TYPE_1}} | {{AUTH_PARAM_DESC_1}} |
| {{AUTH_PARAM_2}} | {{AUTH_PARAM_TYPE_2}} | {{AUTH_PARAM_DESC_2}} |

**Example:**

```powershell
# Authenticate
{{AUTH_EXAMPLE_1}}

# Use token
{{AUTH_EXAMPLE_2}}
```

---

## ❌ Error Codes

### Standard Error Codes

| Code | Message | Meaning | Solution |
|------|---------|---------|----------|
| {{ERROR_1_CODE}} | {{ERROR_1_MSG}} | {{ERROR_1_MEANING}} | {{ERROR_1_SOLUTION}} |
| {{ERROR_2_CODE}} | {{ERROR_2_MSG}} | {{ERROR_2_MEANING}} | {{ERROR_2_SOLUTION}} |
| {{ERROR_3_CODE}} | {{ERROR_3_MSG}} | {{ERROR_3_MEANING}} | {{ERROR_3_SOLUTION}} |

### Error Handling Pattern

```powershell
try {
    {{API_CALL}}
} catch {
    $errorCode = $_.Exception.HResult
    switch ($errorCode) {
        {{ERROR_1_CODE}} { Write-Error "{{ERROR_1_MSG}}" }
        {{ERROR_2_CODE}} { Write-Error "{{ERROR_2_MSG}}" }
        default { Write-Error "Unknown error: $($_.Exception.Message)" }
    }
}
```

---

## 📊 Data Types

### {{DATATYPE_1}}

**Description:** {{DATATYPE_1_DESC}}

**Structure:**

```json
{
  "{{FIELD_1}}": "{{TYPE_1}}",
  "{{FIELD_2}}": "{{TYPE_2}}",
  "{{FIELD_3}}": "{{TYPE_3}}"
}
```

**Example:**

```json
{{DATATYPE_1_EXAMPLE}}
```

---

### {{DATATYPE_2}}

**Description:** {{DATATYPE_2_DESC}}

**Structure:**

```json
{
  "{{FIELD_A}}": "{{TYPE_A}}",
  "{{FIELD_B}}": "{{TYPE_B}}"
}
```

---

## ⚙️ Configuration

### Configuration Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| {{CONFIG_1}} | {{CONFIG_TYPE_1}} | {{CONFIG_DEFAULT_1}} | {{CONFIG_DESC_1}} |
| {{CONFIG_2}} | {{CONFIG_TYPE_2}} | {{CONFIG_DEFAULT_2}} | {{CONFIG_DESC_2}} |
| {{CONFIG_3}} | {{CONFIG_TYPE_3}} | {{CONFIG_DEFAULT_3}} | {{CONFIG_DESC_3}} |

**Setting Configuration:**

```powershell
# Method 1: Environment variable
$env:{{CONFIG_VAR}} = "{{CONFIG_VALUE}}"

# Method 2: Configuration file
{{CONFIG_FILE_EXAMPLE}}

# Method 3: API call
Set-Configuration -Parameter {{VALUE}}
```

---

## 🔄 Pagination

### Paginated Results

Many functions support pagination for large result sets.

**Parameters:**

```powershell
-Skip <int>     # Number of items to skip
-Take <int>     # Number of items to return
-Sort <string>  # Sort field and direction
```

**Example:**

```powershell
# Get first 10 items
{{FUNCTION}} -Skip 0 -Take 10

# Get next 10 items
{{FUNCTION}} -Skip 10 -Take 10

# Sort results
{{FUNCTION}} -Skip 0 -Take 10 -Sort "Name:asc"
```

**Response:**

```json
{
  "data": [{{ITEM_1}}, {{ITEM_2}}],
  "total": {{TOTAL_COUNT}},
  "skip": {{SKIP_VALUE}},
  "take": {{TAKE_VALUE}}
}
```

---

## 🧵 Asynchronous Operations

### Async Function Pattern

For long-running operations:

```powershell
# Start async operation
$jobId = {{ASYNC_FUNCTION}} -Async

# Check status
Get-OperationStatus -JobId $jobId

# Wait for completion
Wait-Operation -JobId $jobId -Timeout 300

# Get result
Get-OperationResult -JobId $jobId
```

---

## ⏱️ Rate Limiting

### Rate Limits

| Endpoint Type | Requests/Min | Requests/Hour |
|---------------|-------------|---------------|
| {{TYPE_1}} | {{RATE_1}} | {{RATE_1_HOUR}} |
| {{TYPE_2}} | {{RATE_2}} | {{RATE_2_HOUR}} |
| {{TYPE_3}} | {{RATE_3}} | {{RATE_3_HOUR}} |

**Handling Rate Limits:**

```powershell
try {
    {{API_CALL}}
} catch {
    if ($_.Exception.Response.StatusCode -eq 429) {
        $retryAfter = $_.Exception.Response.Headers['Retry-After']
        Start-Sleep -Seconds $retryAfter
        {{API_CALL}}  # Retry
    }
}
```

---

## 🔄 Backwards Compatibility

### Version Support

| API Version | Status | Support Ends |
|------------|--------|------------|
| {{VERSION_1}} | Deprecated | {{DATE_1}} |
| {{VERSION_2}} | Stable | {{DATE_2}} |
| {{VERSION_3}} | Current | {{DATE_3}} |

### Migration Guide

For upgrading from API v{{OLD_VERSION}} to v{{NEW_VERSION}}:

```powershell
# Old (deprecated)
{{OLD_FUNCTION}} -OldParam $value

# New (recommended)
{{NEW_FUNCTION}} -NewParam $value
```

---

## 📖 Additional Resources

- [MODULES.md](./MODULES.md) - Module reference
- [EXAMPLES.md](./EXAMPLES.md) - Detailed examples
- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - Common issues
- Category EXAMPLES.md files for specific use cases

---

## 📝 API Change Log

| Version | Date | Changes |
|---------|------|---------|
| {{VERSION_1}} | {{DATE_1}} | {{CHANGES_1}} |
| {{VERSION_2}} | {{DATE_2}} | {{CHANGES_2}} |
| {{VERSION_3}} | {{DATE_3}} | {{CHANGES_3}} |

---

**Generated from template version 1.0 on {{GENERATION_DATE}}**  
**API Version: {{API_VERSION}}**  
**Last Updated: {{LAST_UPDATED}}**
