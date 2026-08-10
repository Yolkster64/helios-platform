# HELIOS Platform - Automation Scripts Suite

Complete PowerShell automation framework for setting up, configuring, and optimizing the HELIOS Platform GitHub project board with full ecosystem integration.

> **Starting from scratch?** `scripts/bootstrap/` is the entry point: browser/device-code
> auth for GitHub + Azure and the full cross-LLM CLI fleet bring-up, identical in Azure
> Cloud Shell, Codespaces, and local shells. `scripts/build/` builds the C++ spoke.

## 📋 Overview

This suite provides production-ready scripts for:
- **Board Setup**: Create 25 custom fields, 8 phase templates, 4 automation rules, 6 board views
- **Integration**: Link GitHub issues, PR workflows, status updates, notifications
- **Optimization**: Performance tuning for GitHub Actions, builds, deployments
- **Monitoring**: Health checks, metrics, alerting, and reporting
- **Orchestration**: Master setup script that coordinates all components

## 🚀 Quick Start

### Prerequisites
- PowerShell 5.1 or higher
- GitHub Personal Access Token with `repo`, `workflow`, and `project` scopes
- Organization administrator access
- Repository admin permissions

### Basic Setup

```powershell
# Set your credentials
$token = 'ghp_YOUR_GITHUB_TOKEN'
$org = 'your-org'
$repo = 'your-repo'
$owner = 'your-org'
$project = 1

# Run complete setup
.\scripts\setup\complete-system-setup.ps1 `
    -GitHubToken $token `
    -ProjectNumber $project `
    -OrganizationName $org `
    -RepositoryName $repo `
    -RepositoryOwner $owner `
    -Verbose
```

## 📁 Directory Structure

```
scripts/
├── board-setup/
│   ├── setup-board.ps1              # Master board setup orchestrator
│   ├── setup-custom-fields.ps1      # Create all 25 custom fields
│   ├── setup-templates.ps1          # Create 8 phase templates
│   ├── setup-automation-rules.ps1   # Configure 4 automation rules
│   ├── setup-views.ps1              # Create 6 board views
│   └── validate-board.ps1           # Comprehensive board validation
├── integration/
│   └── setup-github-ecosystem.ps1   # Configure GitHub integrations
├── optimization/
│   ├── run-optimization.ps1         # Performance optimization
│   └── setup-monitoring.ps1         # Monitoring and alerting
├── setup/
│   └── complete-system-setup.ps1    # Master orchestrator
└── config/
    ├── board-config.json            # Board configuration template
    ├── integration-mapping.json      # Integration field mappings
    ├── optimization-parameters.json  # Optimization settings
    ├── monitoring-rules.json         # Monitoring thresholds
    └── alert-thresholds.json         # Alert configuration
```

## 📊 Custom Fields (25 Total)

### Tier 1: Core Planning (5 fields)
- Priority (Critical/High/Medium/Low)
- Sprint (Sprint 1-4, Backlog)
- Effort (XS/S/M/L/XL/XXL)
- Component (API/Frontend/Backend/DevOps/etc.)
- DueDate

### Tier 2: Execution (5 fields)
- AssignedTo
- ProgressStatus (0-100% stages)
- QAStatus (Pending/In QA/Approved/Failed)
- BlockedBy
- TimeEstimate

### Tier 3: Review & Approval (5 fields)
- ReviewStatus (Not Reviewed/In Review/Changes Requested/Approved)
- ReviewedBy
- ApprovalRequired (Yes/No)
- RiskLevel (Low/Medium/High/Critical)
- ComplianceCheck (Passed/Failed/Pending)

### Tier 4: Deployment & Integration (5 fields)
- DeploymentEnvironment (Dev/Staging/Production/All)
- DeploymentStatus (Not Deployed/Deployed to Dev/etc.)
- IntegrationPoints
- DependsOn
- DataMigration (Required/Not Required/In Progress/Completed)

### Tier 5: Analytics & Metrics (5 fields)
- SuccessMetrics
- UserImpact (High/Medium/Low/Internal Only)
- PerformanceImpact (Positive/Neutral/Negative/TBD)
- Documentation (Complete/Incomplete/Not Required)
- ArchitectureDecision

## 🎯 Phase Templates (8 Total)

1. **Requirements & Planning** - 5-10 days
2. **Design & Architecture** - 7-14 days
3. **Development** - 10-20 days
4. **Testing & QA** - 5-10 days
5. **Code Review & Integration** - 3-5 days
6. **Pre-Production Staging** - 3-5 days
7. **Production Deployment** - 1-2 days
8. **Post-Launch & Monitoring** - Ongoing (14+ days)

Each template includes:
- Acceptance criteria
- Success metrics
- Field defaults
- Expected duration

## ⚡ Automation Rules (4 Total)

1. **Auto-assign Priority** - New items get Medium priority
2. **Update on PR Merge** - Mark items complete when linked PRs merge
3. **Escalate Critical** - Notify team when critical items are created
4. **Deploy When QA Approved** - Auto-move items to deployment phase

## 👁️ Board Views (6 Total)

1. **All Tasks - By Priority** - Executive overview organized by priority
2. **Sprint View** - Current sprint items grouped by component
3. **Critical & High** - Management view of high-impact work
4. **Deployment Pipeline** - DevOps view of deployment readiness
5. **Review Required** - Review queue management
6. **Team Workload** - Team capacity and workload tracking

## 🔗 GitHub Ecosystem Integration

Integrated with:
- Issues → Project Board linking
- PR → Workflow triggering
- Workflow → Status updates
- Action → Notification routing
- Pages → Documentation sync

## 📈 Performance Optimization

### GitHub Actions
- Concurrency control (max 3 concurrent)
- Aggressive caching strategy
- Job matrix optimization

### Build System
- Incremental compilation
- Parallel builds (4 jobs)
- Artifact caching

### Deployment
- Blue-green deployment strategy
- Canary releases (10% → 25% → 50% → 100%)
- Automatic rollback on failures

### Resources
- Alpine-based containers
- G1GC garbage collection
- Connection pooling (50 connections)

## 📊 Monitoring & Alerting

### Performance Metrics
- Workflow Duration
- Deployment Success Rate
- Build Cache Hit Rate
- Average Response Time
- Error Rate
- Resource Utilization

### Health Checks
- GitHub API (60s interval)
- Project Board (300s interval)
- Workflow Engine (120s interval)
- Deployment Pipeline (180s interval)

### Alert Routing
- **Critical**: Slack + Email + PagerDuty
- **High**: Slack + Email
- **Medium**: Slack only
- **Warning**: Email daily summary

## 🛠️ Individual Script Usage

### Board Setup
```powershell
.\scripts\board-setup\setup-board.ps1 `
    -GitHubToken $token `
    -ProjectNumber 1 `
    -OrganizationName "helios" `
    -BoardName "HELIOS Platform" `
    -Verbose
```

### Custom Fields
```powershell
.\scripts\board-setup\setup-custom-fields.ps1 `
    -GitHubToken $token `
    -ProjectNumber 1 `
    -OrganizationName "helios" `
    -Verbose
```

### GitHub Integration
```powershell
.\scripts\integration\setup-github-ecosystem.ps1 `
    -GitHubToken $token `
    -RepositoryName "platform" `
    -RepositoryOwner "helios" `
    -ProjectNumber 1 `
    -OrganizationName "helios" `
    -Verbose
```

### Performance Optimization
```powershell
.\scripts\optimization\run-optimization.ps1 `
    -RepositoryOwner "helios" `
    -RepositoryName "platform" `
    -GitHubToken $token `
    -Verbose
```

### Board Validation
```powershell
.\scripts\board-setup\validate-board.ps1 `
    -GitHubToken $token `
    -ProjectNumber 1 `
    -OrganizationName "helios" `
    -GenerateReport `
    -Verbose
```

## 🧪 Features

### Dry-Run Mode
Preview changes without applying them:
```powershell
.\scripts\setup\complete-system-setup.ps1 `
    -GitHubToken $token `
    -ProjectNumber 1 `
    -OrganizationName "helios" `
    -RepositoryName "platform" `
    -RepositoryOwner "helios" `
    -DryRun `
    -Verbose
```

### Skip Steps
Skip specific setup components:
```powershell
.\scripts\setup\complete-system-setup.ps1 `
    -GitHubToken $token `
    -ProjectNumber 1 `
    -OrganizationName "helios" `
    -RepositoryName "platform" `
    -RepositoryOwner "helios" `
    -SkipSteps @("fields", "templates")
```

### Verbose Logging
Enable detailed output:
```powershell
.\scripts\setup\complete-system-setup.ps1 `
    ... `
    -Verbose
```

## 📝 Output & Reports

All scripts generate:

1. **Execution Logs** - `logs/[script]_TIMESTAMP.log`
2. **JSON Reports** - `logs/[script]-report_TIMESTAMP.json`
3. **Configuration Backups** - `logs/[script]-backup_TIMESTAMP.json`
4. **Markdown Guides** - Documentation of setup

### Sample Report
```json
{
  "timestamp": "2024-04-13T10:30:00",
  "organization": "helios",
  "projectNumber": 1,
  "summary": {
    "fieldsCreated": 25,
    "templatesCreated": 8,
    "rulesConfigured": 4,
    "viewsCreated": 6
  },
  "success": true
}
```

## 🔄 Rollback Procedures

### Restore from Backup
```powershell
# Backups are stored in logs directory
# Restore by deleting new configurations and restoring from backup
cp logs/custom-fields-backup_TIMESTAMP.json .fields/backup.json
```

### Disable Automation Rules
Edit `.automation/rule-*.json` files and set `"enabled": false`

### Remove Custom Fields
Delete corresponding `.fields/*.json` files and re-run validation

## 🚨 Troubleshooting

### GitHub Authentication Failed
- Verify token has `repo`, `workflow`, `project` scopes
- Check token hasn't expired
- Verify organization access

### Project Not Found
- Verify project number is correct
- Ensure you have access to organization
- Check project exists in organization

### Fields Already Exist
- Scripts handle duplicates gracefully
- Use validation script to check status
- Manually delete duplicates if needed

### Integration Not Working
- Check webhook URLs are configured
- Verify repository permissions
- Review integration logs

## 📚 Configuration Files

### board-config.json
Overall board configuration template

### integration-mapping.json
Field mappings between GitHub and project board

### optimization-parameters.json
Performance tuning settings

### monitoring-rules.json
Metric thresholds and health check intervals

### alert-thresholds.json
Alert severity levels and escalation policies

## ✅ Validation Checklist

After running setup:
- [ ] 25 custom fields visible in project
- [ ] 8 phase templates available
- [ ] 4 automation rules enabled
- [ ] 6 board views configured
- [ ] GitHub integration working
- [ ] Monitoring dashboards accessible
- [ ] Automation rules tested
- [ ] Team can access board

## 📞 Support

For issues or questions:
1. Check logs in `logs/` directory
2. Review validation report
3. Run validation script again
4. Check GitHub Actions for workflow errors

## 📄 License

These automation scripts are part of the HELIOS Platform project.

## 🎓 Next Steps

1. **Customize Fields** - Modify field options and defaults for your team
2. **Adjust Automation** - Tune automation rules for your workflow
3. **Configure Notifications** - Set up Slack/Teams/Email for alerts
4. **Train Team** - Educate team on new board and workflows
5. **Monitor & Optimize** - Review metrics and adjust as needed

---

**Last Updated**: April 13, 2024  
**Version**: 1.0  
**Status**: Production Ready
