# Power Automate Workflow Templates for HELIOS

**Version:** 1.0.0 | **Last Updated**: 2024

## Template 1: Auto-Create Teams Profile

**Purpose**: Automatically create Teams profile when user joins

**Trigger**: When user is added to security group

**Steps**:

```
1. Trigger: User added to HELIOS-Team group
2. Get User Details:
   - DisplayName, Email, JobTitle, Department
3. Create Teams Channel:
   - Channel Name: user-{FirstName}-{LastName}
   - Description: Personal channel for {User}
   - Privacy: Private
4. Send Welcome Message:
   - @mention user
   - Link to documentation
   - Link to onboarding checklist
5. Create OneDrive Folder:
   - /HELIOS-Platform/Users/{Email}/
6. Add to Distribution List:
   - helios-team@company.com
7. Create Welcome Email:
   - Welcome message
   - Quick start guide
   - Support contact info
8. Log: Record creation in audit database
```

## Template 2: Sync Data to SharePoint

**Purpose**: Sync HELIOS configuration data to SharePoint

**Schedule**: Daily at 11 PM UTC

**Steps**:

```
1. Query Azure SQL Database:
   - SELECT * FROM helios_configurations
   - WHERE modified_date > yesterday
2. Transform Data:
   - Convert to CSV format
   - Add metadata (timestamp, version)
3. Create SharePoint Files:
   - Upload to /Configurations/Current/
   - Archive previous version to /Archive/
4. Update SharePoint List:
   - Add metadata row
   - Update "Last Sync" timestamp
5. Send Notification:
   - Post in Teams #documentation channel
   - Include file location and change summary
6. Verify Upload:
   - Check file size matches source
   - Confirm file is readable
7. Log Sync Results:
   - Record count synced
   - Success/failure status
   - Timestamp and user
```

## Template 3: Generate Power BI Reports

**Purpose**: Auto-generate daily compliance reports

**Schedule**: Daily at 7 AM UTC (before executives arrive)

**Steps**:

```
1. Get Report Data:
   - Query data warehouse
   - Filter by date range (last 24 hours)
2. Execute Power BI Refresh:
   - Trigger dataset refresh
   - Wait for completion
3. Export Report:
   - Download executive dashboard as PDF
   - Download operational dashboard as Excel
4. Add Annotations:
   - Insert date/timestamp
   - Add "CONFIDENTIAL" watermark
5. Send Reports via Email:
   - To: executives@company.com
   - Subject: Daily HELIOS Report - {Date}
   - Attachment: PDF with highlights
6. Post Summary to Teams:
   - #monitoring channel
   - Key metrics (KPIs)
   - Any anomalies or alerts
7. Archive Report:
   - Save to SharePoint compliance folder
   - Add to audit log
```

## Template 4: Alert on Security Events

**Purpose**: Real-time alerting for security events

**Trigger**: Security event from Azure Security Center

**Steps**:

```
1. Receive Alert:
   - Alert type (high/medium/low)
   - Affected resource
   - Timestamp
2. Evaluate Severity:
   - If HIGH:
     - Skip to step 3 (escalate)
   - Else:
     - Continue to step 4
3. Escalate Critical Alert:
   - Get on-call security engineer from schedule
   - Send SMS via Twilio or Teams mobile
   - Create incident in ITSM system
   - Page on-call team
4. Create Alert Notification:
   - Format message with context
   - Include remediation steps if known
5. Post to Teams Channels:
   - #security channel (all team)
   - Private message to on-call (if HIGH)
6. Trigger Investigation Workflow:
   - Automated remediation steps
   - Collect logs and evidence
7. Create Incident Ticket:
   - Title: Alert type + resource
   - Body: Full alert details
   - Assigned to: Security team
   - Priority: Based on severity
8. Log Alert:
   - Record in security audit log
   - Track response time
```

## Template 5: Compliance Checks

**Purpose**: Daily automated compliance verification

**Schedule**: Daily at 3 AM UTC

**Steps**:

```
1. Check GDPR Controls:
   - Verify data retention policies enforced
   - Check DLP policies are active
   - Confirm encryption is enabled
   - Status: If all pass → "COMPLIANT"
2. Verify HIPAA Requirements:
   - Check access logs < 7 days old
   - Verify audit trail is immutable
   - Confirm encryption on sensitive data
   - Check physical access controls
3. Validate SOC 2 Controls:
   - Verify backups completed last 24h
   - Check monitoring is active
   - Confirm incident response plan exists
   - Verify user access reviews < 30 days old
4. Check Azure Security:
   - Run Azure Security Posture Management
   - Check for open firewall rules
   - Verify MFA is enforced
   - Check for public IP exposure
5. Compile Results:
   - Score: # Passed / Total Checks
   - List all failures with remediation steps
6. If Issues Found:
   - Alert compliance team immediately
   - Create remediation ticket
   - Set deadline (24-48 hours based on severity)
7. Generate Report:
   - Save to compliance SharePoint folder
   - Email to compliance officer
   - Post summary to #compliance channel
8. Update Audit Log:
   - Record check date and results
   - Keep 2-year history
```

## Template 6: VM Auto-Shutdown

**Purpose**: Automatically stop VMs during off-hours

**Schedule**: Daily at 6 PM UTC (end of business)

**Steps**:

```
1. Get List of VMs:
   - Query all VMs with tag: Environment=Dev or Staging
2. For Each VM:
   - Check tag: ScheduledShutdown = true
   - Get PowerState:
     - If Running → Proceed to step 3
     - If Stopped → Skip to next VM
3. Notify VM Owner:
   - Get owner email from VM tags
   - Send Teams message: "VM will shut down in 15 minutes"
   - Include: Stop/Keep-Running options
4. Wait 15 Minutes:
   - Allow owner to choose "Keep Running" via Teams message
   - If chosen, skip shutdown
5. Perform Graceful Shutdown:
   - Connect to VM
   - Run graceful shutdown command
   - Wait for completion (30 min timeout)
6. Deallocate VM:
   - Stop VM in Azure
   - Wait for deallocated status
7. Verify Stopped:
   - Confirm PowerState = deallocated
   - Calculate cost savings
8. Send Confirmation:
   - Post to Teams: "VMs stopped, estimated savings: ${amount}"
   - Log to database
9. Schedule Startup (Optional):
   - Create timer for 7 AM next morning
   - Start VMs automatically
```

## Template 7: Backup Verification

**Purpose**: Verify backups completed successfully

**Schedule**: Daily at 2 AM UTC

**Steps**:

```
1. Get Backup Jobs:
   - Query Azure Backup vault
   - Filter for last 24 hours
2. Check Each Backup:
   - Status: Successful, Failed, Warning
   - Duration: Check if within SLA
   - Size: Compare to baseline (alert if 50%+ variance)
3. For Failed Backups:
   - Get error details
   - Get resource name and owner
4. Alert for Failures:
   - Send email to DBA team
   - Post in Teams #backup-alerts
   - Include: Resource, Error, Remediation steps
5. Calculate Metrics:
   - % backups successful (target: 100%)
   - Average duration (track trends)
   - Total size (track growth)
6. Create Report:
   - Time period: 24 hours
   - Failed: N of M backups
   - Warnings: N alerts
   - Recommendations: Suggest optimizations
7. Archive Report:
   - Save to backup history folder
   - Maintain 3-year retention
8. Escalate if Critical:
   - If > 10% failures → Alert VP of Operations
   - If multiple critical DB failures → Page on-call DBA
```

## Template 8: User Access Review

**Purpose**: Quarterly review of user access

**Schedule**: Monthly (on 1st of month)

**Steps**:

```
1. Get All Users:
   - Query Entra ID
   - Get all users in HELIOS groups
2. For Each User:
   - Get DisplayName, Email, Manager, Department
   - Get group memberships
   - Get role assignments
   - Get last login date
3. Identify Inactive Users:
   - Last login > 90 days ago
   - Flag for manager review
4. Build Access Report:
   - Create table: User | Groups | Roles | Last Login
5. Send to Managers:
   - Email manager with their team's access
   - Request confirmation/updates
   - Deadline: 2 weeks
6. Track Responses:
   - Auto-reminder after 1 week
   - Escalate non-responsive to HR
7. Process Changes:
   - Remove users from groups (if requested)
   - Add new users (if new hires)
   - Update roles (if requested)
8. Disable Stale Accounts:
   - Auto-disable after 30 days no login
   - Notify user via email
   - Can re-enable with approval
9. Audit Log:
   - Record all changes
   - Keep 3-year audit trail
10. Report to Compliance:
    - Send summary to compliance officer
    - Include: Changes made, users removed, exceptions
```

## Template 9: Cost Optimization Alert

**Purpose**: Alert when Azure costs exceed threshold

**Trigger**: Daily cost comparison

**Steps**:

```
1. Get Current Month Costs:
   - Query Azure Cost Management API
   - Get YTD spend
2. Calculate Burn Rate:
   - Daily spend = YTD / days elapsed
   - Project monthly cost = daily * 30
3. Compare to Budget:
   - Get approved budget for month
   - Calculate % of budget used
4. If Costs High:
   - Calculate days until budget exhausted
   - Identify top cost drivers (VMs, storage, etc)
5. Alert Threshold:
   - If > 80% of budget → Email finance team
   - If > 95% of budget → Escalate to CTO
   - If > 100% of budget → Page ops lead
6. Provide Recommendations:
   - Top 5 cost optimization opportunities
   - Estimated savings for each
   - Implementation effort
7. Create Ticket:
   - Title: Cost Optimization - {Month}
   - Assigned: Operations team
   - Priority: Based on overage %
8. Track Optimization:
   - Monitor if recommendations are implemented
   - Verify cost reduction next period
```

## Best Practices

1. **Error Handling**: Add try-catch for all API calls
2. **Logging**: Log all workflow executions
3. **Notifications**: Use multiple channels (email, Teams, SMS)
4. **Timeouts**: Set realistic timeout values
5. **Approvals**: Route critical changes for approval
6. **Testing**: Test in non-production first
7. **Documentation**: Document workflow logic
8. **Monitoring**: Alert on workflow failures
9. **Versioning**: Version all workflows
10. **Governance**: Get security review before deploying

---

**Version 1.0.0** | **Last Updated**: 2024
