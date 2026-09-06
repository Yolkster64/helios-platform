# AI Coordination Guide

Coordinating ChatGPT and GitHub Codex for maximum effectiveness in HELIOS development.

## Overview

AI coordination enables:

- Using ChatGPT for planning, Codex for code generation
- Detecting conflicting AI suggestions
- Unified recommendation generation
- Automatic conflict resolution
- Complete audit trail

## Typical Workflow

### Phase 1: Planning with ChatGPT

```
1. Define requirements to ChatGPT
2. Get recommendations for approach
3. Review security implications
4. Confirm build strategy
```

### Phase 2: Code Generation with Codex

```
1. Pass approved spec to Codex
2. Generate initial code
3. Review generated code
4. Request refinements if needed
```

### Phase 3: Validation with ChatGPT

```
1. Ask ChatGPT to review generated code
2. Get security assessment
3. Check for performance issues
4. Confirm compliance
```

### Phase 4: Coordination

```
1. Compare ChatGPT and Codex suggestions
2. Detect conflicts
3. Apply resolution logic
4. Generate unified recommendations
```

## Workflow Example

```powershell
# Step 1: Get planning from ChatGPT
$plan = Invoke-ChatGPT -Prompt "We need to consolidate 500 AppLocker rules" `
    -SystemPrompt "Build Advisor"

# Step 2: Generate code from plan with Codex
$spec = $plan.recommendations[0].description
$code = Invoke-Codex -Spec $spec -Language "powershell"

# Step 3: Review code with ChatGPT
$review = Invoke-ChatGPT -Prompt "Review this code: $code" `
    -SystemPrompt "Code Reviewer"

# Step 4: Coordinate results
$final = Invoke-AICoordination -ChatGPTResponse $review `
    -CodexResponse $code
```

## Detecting Conflicts

Conflicts occur when AI services suggest contradictory approaches:

### Example Conflict 1: Rule Consolidation

- ChatGPT (Security Architect): "Use granular rules for better control"
- Codex: Generates script that consolidates rules for performance

**Resolution**: Evaluate trade-off between security and performance

### Example Conflict 2: Implementation Approach

- ChatGPT (Build Advisor): "Use audit mode for 4 weeks"
- ChatGPT (Performance Analyst): "Move to enforcement after 2 weeks"

**Resolution**: Weight risk vs. velocity

### Example Conflict 3: Code Style

- Codex: Generates compact, performance-optimized code
- ChatGPT (Code Reviewer): Recommends verbose, readable code

**Resolution**: Choose based on maintenance requirements

## Conflict Resolution Matrix

| Conflict Type | ChatGPT Weight | Codex Weight | Resolution |
|---------------|----------------|--------------|-----------|
| Security vs. Performance | High | Low | Security first |
| Speed vs. Caution | Medium | High | Context dependent |
| Consolidation vs. Granularity | High | Low | Security first |
| Readability vs. Optimization | Medium | Medium | Code review decides |

## Coordination Scripts

Use coordinate-ai.ps1 to automatically handle coordination:

```powershell
. .\scripts\coordinate-ai.ps1

$result = Invoke-AICoordination `
    -ChatGPTResponse $chatgptAnalysis `
    -CodexResponse $codexGeneration `
    -ConflictResolution $true `
    -GenerateReport $true
```

## Integration Points

### GitHub Actions Integration

```yaml
name: AI Code Review
on: [pull_request]
jobs:
  ai-review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: ChatGPT Security Review
        run: ./scripts/ask-chatgpt.ps1
      - name: Codex Suggestions
        run: ./scripts/ask-codex.ps1
      - name: Coordinate
        run: ./scripts/coordinate-ai.ps1
```

### Manual Coordination

```powershell
# When conflicts are complex, escalate to human review
if ($conflict.severity -eq "High") {
    Invoke-MarkForReview -ConflictId $conflict.id `
        -AssignTo "security-team"
}
```

## Approval Workflow

```
1. AI generates recommendations
2. System detects conflicts
3. If High risk: Human review required
4. If Low risk: Auto-approve if criteria met
5. Generate audit log
6. Implement approved changes
```

## Tracking AI Interactions

Every AI interaction is logged:

```
[2024-01-15T10:30:00Z] CHATGPT_REQUEST
- Prompt: "Should we consolidate?"
- Model: gpt-4
- Status: Success

[2024-01-15T10:30:03Z] CHATGPT_RESPONSE
- Recommendation: Consolidate for performance

[2024-01-15T10:31:00Z] CODEX_REQUEST
- Spec: "Generate consolidation script"
- Status: Success

[2024-01-15T10:31:15Z] CODEX_RESPONSE
- Code: [generated script]
- Validation: Passed safety checks

[2024-01-15T10:31:30Z] COORDINATION
- Conflict Detected: Security vs. Performance
- Resolution: Security prioritized
- Decision: Use ChatGPT recommendation
```

## Best Practices

1. **Always Start with ChatGPT**
   - Define requirements
   - Get recommendations
   - Validate approach

2. **Then Use Codex**
   - Generate based on approved spec
   - Review for quality
   - Request refinements

3. **Always Validate Both**
   - Security review
   - Performance check
   - Compliance verification

4. **Document Everything**
   - Store original specs
   - Track AI recommendations
   - Log all decisions

5. **Have Conflict Plan**
   - Define decision criteria
   - Assign escalation path
   - Review regularly
