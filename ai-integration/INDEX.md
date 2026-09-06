# HELIOS AI Integration Layer - Index

**Quick Navigation to All Resources**

## 🎯 Start Here

- **First Time?** → Read [QUICK_START.md](./QUICK_START.md) (10 minutes)
- **Need Overview?** → Read [README.md](./README.md) (15 minutes)
- **Need Reference?** → Check [REFERENCE.md](./REFERENCE.md) (anytime)

## 📚 Complete Documentation

### Core Documentation

| File | Purpose | Read Time |
|------|---------|-----------|
| [README.md](./README.md) | Overview, capabilities, setup | 15 min |
| [QUICK_START.md](./QUICK_START.md) | Step-by-step setup guide | 10 min |
| [REFERENCE.md](./REFERENCE.md) | Function reference & examples | 5 min |
| [IMPLEMENTATION_CHECKLIST.md](./IMPLEMENTATION_CHECKLIST.md) | Verification checklist | 20 min |
| [COMPLETION_REPORT.md](./COMPLETION_REPORT.md) | Project completion summary | 5 min |

### ChatGPT Integration

| File | Purpose | Read Time |
|------|---------|-----------|
| [chatgpt-integration/README.md](./chatgpt-integration/README.md) | API setup & patterns | 20 min |
| [chatgpt-integration/SYSTEM_PROMPTS.md](./chatgpt-integration/SYSTEM_PROMPTS.md) | Pre-built system prompts | 10 min |

### Codex Integration

| File | Purpose | Read Time |
|------|---------|-----------|
| [codex-integration/README.md](./codex-integration/README.md) | Codex setup guide | 10 min |
| [codex-integration/CODE_GENERATION_TEMPLATES.md](./codex-integration/CODE_GENERATION_TEMPLATES.md) | Code generation templates | 15 min |

### AI Coordination

| File | Purpose | Read Time |
|------|---------|-----------|
| [ai-coordination/README.md](./ai-coordination/README.md) | Multi-AI workflows | 15 min |
| [ai-coordination/CONFLICT_RESOLUTION.md](./ai-coordination/CONFLICT_RESOLUTION.md) | Conflict handling | 20 min |
| [ai-coordination/VERSION_CONTROL.md](./ai-coordination/VERSION_CONTROL.md) | AI code version control | 15 min |

## 💻 PowerShell Scripts

| Script | Purpose | Location |
|--------|---------|----------|
| `Invoke-ChatGPT` | Send prompts to ChatGPT Pro | [scripts/ask-chatgpt.ps1](./scripts/ask-chatgpt.ps1) |
| `Invoke-Codex` | Generate code with GitHub Codex | [scripts/ask-codex.ps1](./scripts/ask-codex.ps1) |
| `Invoke-AICoordination` | Coordinate AI services | [scripts/coordinate-ai.ps1](./scripts/coordinate-ai.ps1) |

## 🔧 Quick Commands

### Load All Functions

```powershell
. ./scripts/ask-chatgpt.ps1
. ./scripts/ask-codex.ps1
. ./scripts/coordinate-ai.ps1
```

### Test ChatGPT

```powershell
. ./scripts/ask-chatgpt.ps1
Invoke-ChatGPT -Prompt "Hello"
```

### Generate Code

```powershell
. ./scripts/ask-codex.ps1
Invoke-Codex -Spec "Generate PowerShell function"
```

### Coordinate AI

```powershell
$result = Invoke-AICoordination `
    -ChatGPTResponse $gpt `
    -CodexResponse $codex `
    -GenerateReport $true
```

## 🎓 Learning Path

### Beginner (1 hour)

1. Read: QUICK_START.md
2. Set API key
3. Test ChatGPT function
4. Read: README.md

### Intermediate (2-3 hours)

1. Read: All chatgpt-integration docs
2. Read: All codex-integration docs
3. Test all functions
4. Try: Common workflows

### Advanced (4-5 hours)

1. Read: ai-coordination docs
2. Read: VERSION_CONTROL.md
3. Review: GitHub Actions workflow
4. Customize: System prompts

### Expert (Ongoing)

1. Monitor: Costs and usage
2. Optimize: System prompts
3. Scale: To new use cases
4. Share: With team

## 📊 File Map

```
ai-integration/
├── 📄 README.md                          [START: Overview]
├── 📄 QUICK_START.md                     [START: Setup]
├── 📄 REFERENCE.md                       [Lookup: Functions]
├── 📄 IMPLEMENTATION_CHECKLIST.md        [Verify: Setup]
├── 📄 COMPLETION_REPORT.md               [Info: Status]
├── 📁 chatgpt-integration/
│   ├── 📄 README.md                      [Learn: ChatGPT]
│   └── 📄 SYSTEM_PROMPTS.md              [Reference: Prompts]
├── 📁 codex-integration/
│   ├── 📄 README.md                      [Learn: Codex]
│   └── 📄 CODE_GENERATION_TEMPLATES.md   [Reference: Templates]
├── 📁 ai-coordination/
│   ├── 📄 README.md                      [Learn: Coordination]
│   ├── 📄 CONFLICT_RESOLUTION.md         [Reference: Conflicts]
│   └── 📄 VERSION_CONTROL.md             [Reference: Version Control]
├── 📁 scripts/
│   ├── 🔧 ask-chatgpt.ps1                [Use: ChatGPT Function]
│   ├── 🔧 ask-codex.ps1                  [Use: Codex Function]
│   └── 🔧 coordinate-ai.ps1              [Use: Coordination Function]
└── 📁 .github/workflows/
    └── ⚙️ ai-code-review.yml             [Use: GitHub Actions]
```

## 🚀 Five-Minute Quickstart

```bash
# Step 1: Set API Key
$env:OPENAI_API_KEY = "sk-your-key-here"

# Step 2: Load ChatGPT
. ./scripts/ask-chatgpt.ps1

# Step 3: Ask a Question
Invoke-ChatGPT -Prompt "What should I do with AppLocker?" `
    -SystemPrompt "HELIOS Optimizer" `
    -Model "gpt-3.5-turbo"

# Step 4: Read the Response
# (Response printed to console)

# Step 5: For More Info
cat QUICK_START.md
```

## 💡 Common Tasks

### Get Strategic Recommendations

→ Read: [chatgpt-integration/README.md](./chatgpt-integration/README.md)  
→ Use: HELIOS Optimizer system prompt  
→ Example: "Should we consolidate our AppLocker rules?"

### Generate AppLocker Script

→ Read: [codex-integration/README.md](./codex-integration/README.md)  
→ Use: Invoke-Codex function  
→ Example: "Generate rule consolidation script"

### Detect Rule Conflicts

→ Read: [ai-coordination/CONFLICT_RESOLUTION.md](./ai-coordination/CONFLICT_RESOLUTION.md)  
→ Use: Conflict Detector system prompt  
→ Example: "Will these two rules conflict?"

### Security Analysis

→ Read: [chatgpt-integration/SYSTEM_PROMPTS.md](./chatgpt-integration/SYSTEM_PROMPTS.md)  
→ Use: Security Architect prompt  
→ Example: "Analyze security gaps in my config"

### Code Review

→ Use: Code Reviewer system prompt  
→ Example: "Review this script for best practices"

## ⚠️ Critical Information

### API Key Setup

- **Required**: OpenAI API key from https://platform.openai.com
- **Store**: `$env:OPENAI_API_KEY = "sk-..."`
- **Never**: Commit to version control
- **Remember**: Rotate monthly

### Security Requirements

- ✅ All AI-generated code requires human review
- ✅ Automatic credential leak detection enabled
- ✅ Dangerous patterns flagged automatically
- ✅ Complete audit trail maintained

### Cost Control

- 🔄 Response caching saves ~70% on repeated questions
- 📊 Use GPT-3.5-turbo for non-critical questions (~40x cheaper)
- ⏱️ Monitor token usage in logs
- 💰 Set MaxTokens to limit response length

## 🆘 Help & Support

### Troubleshooting

→ Read: QUICK_START.md "Troubleshooting" section

### Common Issues

→ Read: chatgpt-integration/README.md "Error Handling" section

### API Documentation

→ Visit: https://platform.openai.com/docs

### GitHub Copilot

→ Visit: https://github.com/features/copilot

## ✅ Verification

- [ ] API key configured: `$env:OPENAI_API_KEY`
- [ ] ChatGPT test passed: `Invoke-ChatGPT -Prompt "Hello"`
- [ ] Codex test passed: `Invoke-Codex -Spec "Hello world"`
- [ ] Coordination test passed: `Invoke-AICoordination`
- [ ] Logs created: `$env:LOCALAPPDATA\helios-ai-logs\`

## 📞 Next Steps

1. **Now**: Read QUICK_START.md
2. **Soon**: Complete IMPLEMENTATION_CHECKLIST.md
3. **This Week**: Train team
4. **Ongoing**: Monitor and optimize

---

**Version:** 1.0  
**Status:** ✅ Ready for Use  
**Questions?** Start with QUICK_START.md or README.md
