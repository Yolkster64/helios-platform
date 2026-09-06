# Microsoft Copilot Prompt Templates for HELIOS

**Version:** 1.0.0 | **Last Updated**: 2024

## Template 1: Analyze System Configuration

**Purpose**: Review current HELIOS configuration for issues

**Prompt**:

```
Please analyze the following HELIOS Platform configuration and provide recommendations:

Infrastructure:
- Azure Subscription: Production
- Resource Group: helios-platform-prod (eastus2)
- VMs: 10x Standard_D4s_v3 (Windows 11 Pro)
- Database: SQL Server Standard (Single Database, 500GB)
- Storage: Premium SSD (2TB total)
- Backup: Daily snapshots (7-day retention)
- Monitoring: Application Insights enabled

Identity:
- Entra ID: Yes, MFA for admins only
- Conditional Access: 1 policy (block legacy auth)
- Service Principals: 5 registered
- Groups: 10 security groups

Security:
- Network Security Groups: Yes
- Key Vault: No secrets management
- Firewall: Azure Firewall not deployed
- DLP: No data loss prevention

Compliance:
- Audit Logging: Enabled (90 days)
- Backups: Automated (7-day retention)
- Documentation: In SharePoint
- Incident Response: Manual process

Please provide:
1. Current state assessment (strengths/weaknesses)
2. Top 5 improvements prioritized by impact
3. Implementation effort for each (hours)
4. Risk if not implemented
5. ROI/benefit of each improvement
```

## Template 2: Recommend Security Improvements

**Purpose**: Get security-focused recommendations

**Prompt**:

```
Our HELIOS Platform needs security hardening. Current state:
- No MFA for regular users (only admins have MFA)
- SSH accessible from 0.0.0.0/0 on port 22
- No encryption in transit for internal APIs
- Secrets stored in config files
- No DLP policies
- Compliance: Need GDPR, SOC2 Type II

Environment:
- 500+ users across 5 countries
- 50+ external API integrations
- Processes PII and financial data
- 99.95% uptime requirement

Provide:
1. Critical security gaps (with risk level)
2. Specific fixes with implementation steps
3. Timeline for remediation (phased approach)
4. Ongoing security practices to implement
5. Tools/services needed with costs
```

## Template 3: Generate Deployment Script

**Purpose**: Create automation scripts

**Prompt**:

```
Generate a PowerShell script to deploy HELIOS Platform infrastructure to Azure with:

Requirements:
- Create resource group: helios-platform-prod
- Deploy VNet: 10.0.0.0/16 with 3 subnets
- Create 3x Standard_D4s_v3 VMs (Ubuntu 22.04)
- Configure NSGs with:
  - SSH: Allowed from 203.0.113.0/24 only
  - HTTPS: Allowed from internet
  - Backend communication: Only between subnets
- Create SQL Database: helios-db-prod
- Configure backup: Daily, 30-day retention
- Enable monitoring: Application Insights
- Tag all resources with: Project=HELIOS, Env=Prod

Error handling:
- Check for existing resources
- Validate input parameters
- Log all operations
- Rollback on failure

The script should:
1. Be production-ready (error handling, logging)
2. Include parameter validation
3. Support idempotent execution
4. Output resource IDs for verification
5. Include documentation
```

## Template 4: Suggest Performance Optimizations

**Purpose**: Identify and fix performance issues

**Prompt**:

```
HELIOS Platform is experiencing performance issues. Current metrics:

Performance Issues:
- API Response Time: Avg 2.5s, P95 8s (SLA: <500ms)
- Database Query Time: Avg 1.2s (SLA: <100ms)
- Memory Usage: VMs averaging 85% (threshold: 75%)
- CPU Spikes: Reaches 90% during business hours
- Network I/O: 500 Mbps (saturating 1Gbps link)

Workload:
- 10,000 concurrent users
- 100,000 requests/minute peak
- Data warehouse: 50 TB
- Daily data ingestion: 1 TB

Current Implementation:
- 10 VMs (Standard_D4s_v3)
- Single SQL Database
- Synchronous API calls (no caching)
- No database indexing strategy

Please provide:
1. Root cause analysis for each issue
2. Specific optimizations with expected improvement
3. Architecture changes needed
4. Caching strategy
5. Database optimization (indexing, partitioning)
6. Load balancing recommendations
7. Estimated cost/benefit
```

## Template 5: Review and Improve Code

**Purpose**: Get code quality and best practices suggestions

**Prompt**:

```
Please review the following PowerShell script for:
1. Best practices and security
2. Error handling and logging
3. Performance improvements
4. Production readiness
5. Azure/Microsoft best practices

[Paste PowerShell code here]

Specifically:
- Are there security vulnerabilities?
- Is error handling comprehensive?
- Can performance be improved?
- Are Azure best practices followed?
- Is the code maintainable and documented?

Provide:
1. Issues found (by severity)
2. Specific fixes with code examples
3. Improved version of the script
4. Testing recommendations
5. Performance metrics (if applicable)
```

## Template 6: Create Disaster Recovery Plan

**Purpose**: Generate DR procedures

**Prompt**:

```
Help me create a Disaster Recovery plan for HELIOS Platform with:

Recovery Objectives:
- RTO (Recovery Time Objective): 4 hours
- RPO (Recovery Point Objective): 1 hour
- MTTR (Mean Time To Repair): < 2 hours

Infrastructure to Protect:
- 50 VMs across 2 Azure regions
- 10 SQL Databases
- 5 TB application data
- 1 TB configuration files
- 500 users (SaaS)

Current Protections:
- Daily snapshots (7-day retention)
- SQL backup (14-day retention)
- No geo-replication
- No hot standby

Scenarios to Handle:
1. Single VM failure
2. SQL Database failure
3. Region-wide outage
4. Data corruption
5. Security breach/ransomware

Provide:
1. Architecture for disaster recovery
2. Backup strategy (frequency, retention)
3. Replication approach
4. Detailed runbooks for each scenario
5. Testing procedures
6. Cost/benefit analysis
7. Implementation timeline
```

## Template 7: Compliance Documentation

**Purpose**: Generate compliance reports and documentation

**Prompt**:

```
Generate GDPR compliance documentation for HELIOS Platform:

Data Handling:
- Store user personal data: Yes (names, emails, addresses, phone)
- Store financial data: Yes (invoices, payment info)
- Process biometric data: No
- Share with third parties: Partially (3 vendors)
- Data retention: 3 years

Current Controls:
- Encryption at rest: Yes (AES-256)
- Encryption in transit: Yes (TLS 1.2+)
- Access controls: RBAC via Entra ID
- Audit logging: 90 days
- Data classification: Basic (Public/Internal/Confidential)

Need to Generate:
1. Data Processing Inventory
2. Data Subject Rights Procedures
3. Privacy Impact Assessment (PIA)
4. Data Breach Response Plan
5. Vendor Data Processing Agreements (DPA)
6. Policy documentation

Provide:
- Templates for each document
- Specific recommendations for HELIOS
- Implementation checklist
- Timeline for completion
- Monthly compliance checklist
```

## Template 8: Cost Analysis & Optimization

**Purpose**: Analyze and reduce cloud spending

**Prompt**:

```
Analyze HELIOS Platform Azure costs for optimization:

Current Monthly Costs: $12,500

Breakdown:
- Compute (VMs): $7,200 (58%)
- Database: $2,800 (22%)
- Storage: $1,200 (10%)
- Networking: $800 (6%)
- Other: $500 (4%)

Infrastructure:
- 10x Standard_D4s_v3 VMs running 24/7
- 1x SQL Database (Standard tier, 500GB)
- Geo-redundant storage (1TB)
- Data transfer: 500GB/month

Usage Patterns:
- Peak hours: 8 AM - 6 PM (weekdays)
- Off-peak: Nights and weekends
- Seasonal variation: 30% higher during Q4

Cost Reduction Goals:
- Target monthly cost: $5,000 (60% reduction)
- Maintain uptime: 99.95%
- No performance degradation

Provide:
1. Detailed cost analysis by service
2. Savings opportunities ranked by impact
3. Implementation effort for each
4. Risks/trade-offs
5. Timeline for implementation
6. Expected final cost breakdown
7. Alternative architectures with costs
```

## Template 9: Security Incident Analysis

**Purpose**: Help analyze and respond to security incidents

**Prompt**:

```
HELIOS Platform detected a potential security incident:

Incident Details:
- Time Detected: 2024-01-15 14:30 UTC
- Detection Method: Anomaly in data access logs
- System: SQL Database helios-db-prod
- Affected: Employee records (50k users)

Anomalous Activity:
- Source: VM-12 (internal)
- SQL Account: app_service (automation account)
- Query Type: SELECT * from employees (30 tables)
- Duration: 45 minutes
- Data Volume: 2.3 GB extracted
- Destination: Network drive (X:)

Initial Response:
- Query stopped manually
- VM network isolated (pending verification)
- Database access logs reviewed (4 hour window)
- No other anomalies found

Questions:
1. What likely happened?
2. What data might be compromised?
3. What are the impacts?
4. What's the immediate response?
5. What's the investigation procedure?
6. What reporting is required (legal, users)?
7. How do we prevent recurrence?

Provide:
- Incident classification (severity)
- Immediate containment steps
- Forensic analysis approach
- Communication plan
- Legal/compliance obligations
- Prevention recommendations
```

## Template 10: Compliance Audit

**Purpose**: Prepare for and conduct compliance audits

**Prompt**:

```
Help prepare HELIOS Platform for SOC 2 Type II audit:

Audit Scope:
- Security (CC controls)
- Availability (A controls)
- Processing Integrity (PI controls)
- Confidentiality (C controls)
- Privacy (P controls)

Current Status:
- Previous Audit: Never audited
- Controls Implemented: ~60%
- Documentation: Partial
- Testing Evidence: Minimal
- Audit Timeline: 60 days until audit

Key Areas:
1. Access controls (user provisioning, role management)
2. Monitoring (logs, alerting, incident response)
3. Availability (backup, disaster recovery, SLA tracking)
4. Encryption (data at rest and in transit)
5. Change management (code deployment, approvals)
6. Incident management (detection, response, communication)

Required:
1. Gap analysis vs. SOC 2 criteria
2. Evidence collection checklist
3. Testing procedures for auditor
4. Documentation templates
5. Audit readiness assessment
6. Timeline for remediation
7. Communication plan for stakeholders
```

## Tips for Using Copilot Effectively

1. **Provide Context**: Include current state, goals, and constraints
2. **Be Specific**: Use exact names, numbers, and configurations
3. **Ask for Formats**: Request specific output (checklist, code, table, narrative)
4. **Iterate**: Ask follow-up questions to refine responses
5. **Verify**: Always validate recommendations independently
6. **Reference**: Save useful responses for future reference
7. **Combine**: Use multiple prompts to gather comprehensive information

## Privacy Reminder

⚠️ **Never include** in Copilot prompts:

- Credentials, passwords, or API keys
- Full database connection strings
- Real email addresses (use examples like user@company.com)
- Actual IP addresses of production systems
- Personally identifiable information (unless anonymized)
- Sensitive business data or financial figures

---

**Version 1.0.0** | **Last Updated**: 2024
