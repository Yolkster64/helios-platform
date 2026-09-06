# HELIOS Platform - Board Custom Fields Complete Guide

**Document Version:** 1.0  
**Last Updated:** 2026-04-13  
**Total Custom Fields:** 25 (5 Tiers)  
**Field Integration Level:** Enterprise

---

## Table of Contents

1. [Overview](#overview)
2. [Tier 1: Basic Tracking Fields](#tier-1-basic-tracking-fields)
3. [Tier 2: Component Tracking Fields](#tier-2-component-tracking-fields)
4. [Tier 3: Phase Management Fields](#tier-3-phase-management-fields)
5. [Tier 4: Resource Tracking Fields](#tier-4-resource-tracking-fields)
6. [Tier 5: Advanced Automation Fields](#tier-5-advanced-automation-fields)
7. [Field Creation Instructions](#field-creation-instructions)
8. [Field Integration Matrix](#field-integration-matrix)
9. [Best Practices](#best-practices)

---

## Overview

### Field Architecture

The HELIOS Platform board implements a 5-tier custom field architecture:

| Tier | Purpose | Fields | Complexity | Automation |
|------|---------|--------|-----------|-----------|
| **1** | Basic Issue Tracking | 5 | Low | Minimal |
| **2** | Component Classification | 8 | Low-Medium | Direct |
| **3** | Phase Assignment | 6 | Medium | Heavy |
| **4** | Resource Planning | 3 | Medium-High | Advanced |
| **5** | Advanced Automation | 3 | High | Full |

### Field Usage Statistics

- **Required Fields:** 3 (Priority, Component, Status Phase)
- **Optional Fields:** 22
- **Auto-Populated Fields:** 17
- **Manual Fields:** 8
- **Calculated Fields:** 0 (all manual or automated)

---

## Tier 1: Basic Tracking Fields

### Field 1: Priority

**Field Details:**

```yaml
Field Name: Priority
Type: Single Select
Icon: Flag
Field ID: priority_field
Required: Yes
Default Value: Medium
Options: [Critical, High, Medium, Low]
```

**Purpose:**

- Enable issue prioritization across backlog
- Determine work order and sprint inclusion
- Identify urgent vs. strategic work

**Usage Examples:**

| Priority | When to Use | Examples | SLA Response |
|----------|-----------|----------|-------------|
| Critical | System down, security breach, major data loss | Security vulnerability, prod outage, data corruption | 1 hour |
| High | Important feature, significant blocker | Critical performance issue, essential feature delay | 4 hours |
| Medium | Standard feature, normal bug | Feature implementation, UI improvement | 1 day |
| Low | Enhancement, nice-to-have | Documentation update, minor UI tweak | 1 week |

**Automation Integration:**

- Used by Rule 4 to auto-assign tier (Critical → Enterprise minimum)
- Triggers in Priority-based board view sorting
- Influences sprint planning algorithms
- Used in notifications for escalation

**Best Practices:**

- Review priority weekly for accuracy
- Escalate if critical issues accumulate (>5 concurrent)
- Avoid overusing critical designation
- Document priority rationale for high items

---

### Field 2: Component

**Field Details:**

```yaml
Field Name: Component
Type: Single Select
Icon: Component
Field ID: component_field
Required: Yes
Default Value: None (must select)
Options: [Monado, Security, AI, GUI, Agents, Hub, Stack, Infrastructure, DevOps, Documentation]
```

**Purpose:**

- Categorize issues by technical component
- Route work to appropriate team
- Enable component-based metrics and views
- Identify cross-component dependencies

**Component Descriptions:**

| Component | Owner | Responsibilities | Related Fields |
|-----------|-------|------------------|-----------------|
| **Monado** | Display Team | Display server, rendering, output handling | Phase 1-2 |
| **Security** | Security Team | Auth, encryption, access control, auditing | Phase 3-5 |
| **AI** | ML Team | ML models, predictions, intelligent features | Phase 4-6 |
| **GUI** | Frontend Team | UI components, user interface, user experience | Phase 2-4 |
| **Agents** | Systems Team | Autonomous components, background services | Phase 3-5 |
| **Hub** | Core Team | Coordination layer, central services, integration | Phase 1-7 |
| **Stack** | DevOps Team | Infrastructure, dependencies, tech stack | Phase 0-1 |
| **Infrastructure** | DevOps Team | Servers, networking, storage, deployment | Phase 1-3 |
| **DevOps** | DevOps Team | CI/CD, monitoring, alerting, incident response | Phase 2-4 |
| **Documentation** | Docs Team | Technical docs, user guides, API docs | All Phases |

**Automation Integration:**

- Rule 1: Auto-assigns phase based on component
- Rule 4: Auto-assigns tier classification based on component
- Component checkbox fields auto-checked when this field set
- Component-based board view populated automatically
- Component lead notifications triggered

**Usage in Workflows:**

```
Creating New Issue:
1. Select most relevant component
2. If multi-component, create separate issues
3. Link cross-component issues with comments

Updating Existing Issue:
1. Can change component if understanding evolves
2. Notifies component lead of change
3. May trigger automation rule re-evaluation
```

**Best Practices:**

- One issue = one component (split if multi)
- Document component selection rationale
- Escalate cross-component blockers to coordinator
- Review component distribution monthly

---

### Field 3: Effort Estimate

**Field Details:**

```yaml
Field Name: Effort Estimate
Type: Single Select
Icon: Zap
Field ID: effort_estimate_field
Required: No
Default Value: None
Options: [1 (XS), 2 (S), 3 (M), 5 (L), 8 (XL), 13 (XXL)]
Scale: Modified Fibonacci (powers of phi: 1, 2, 3, 5, 8, 13)
```

**Purpose:**

- Estimate work effort using story points
- Enable capacity planning and sprint planning
- Calculate team velocity
- Identify sizing anomalies

**Sizing Guide:**

| Points | Effort | Time | Complexity | Examples |
|--------|--------|------|-----------|----------|
| **1 (XS)** | Minimal | < 1 day | Trivial | Typo fix, doc update, config change |
| **2 (S)** | Small | 1 day | Simple | Single function, simple UI fix |
| **3 (M)** | Medium | 2-3 days | Moderate | Module enhancement, feature addition |
| **5 (L)** | Large | 3-5 days | Complex | New subsystem, major refactor |
| **8 (XL)** | Extra Large | 1-2 weeks | Very Complex | Major feature, system redesign |
| **13 (XXL)** | Huge | 2-4 weeks | Extreme | Platform migration, new architecture |

**Point Estimation Process:**

```
Step 1: Read and understand requirements fully
Step 2: Consider dependencies and risks
Step 3: Compare to similar previous issues
Step 4: Account for unknowns (add 20-30%)
Step 5: Make team estimate in planning
Step 6: Discuss outliers (points > 2x average)
Step 7: Finalize with consensus
```

**Automation Integration:**

- Used in velocity calculations
- Rule 4: Issues with Effort >= 5 get Professional tier minimum
- Impacts capacity and sprint planning
- Used in team workload distribution

**Usage Examples:**

```
Issue: "Fix typo in README.md"
Estimate: 1 point (< 1 hour)

Issue: "Add dark mode toggle"
Estimate: 3 points (2-3 days including testing)

Issue: "Implement SSO authentication"
Estimate: 8 points (1-2 weeks with testing and docs)

Issue: "Platform architecture redesign"
Estimate: 13 points (2-4 weeks)
```

**Best Practices:**

- Estimate in team planning sessions
- Use reference issues as anchors
- Avoid cognitive bias (planning fallacy)
- Review actual time vs. estimate post-completion
- Adjust estimates for team velocity changes

---

### Field 4: Status Phase

**Field Details:**

```yaml
Field Name: Status Phase
Type: Single Select
Icon: Layout
Field ID: status_phase_field
Required: Yes
Default Value: Phase 0
Options: [Phase 0, Phase 1, Phase 2, Phase 3, Phase 4, Phase 5, Phase 6, Phase 7]
Immutable After Set: No (can change if needed)
```

**Purpose:**

- Track which implementation phase the issue belongs to
- Enable phase-based planning and deployment
- Support staged rollout strategy
- Organize work by maturity level

**Phase Definitions:**

| Phase | Release Stage | Focus | Typical Duration |
|-------|---------------|-------|------------------|
| **0** | Pre-Installation | Planning, design, requirements | 2-4 weeks |
| **1** | Fresh Install | Base system, core features | 1-2 weeks |
| **2** | Enhanced | Advanced features, optimization | 2-3 weeks |
| **3** | Advanced | Enterprise features, HA/DR | 3-4 weeks |
| **4** | Professional Tier | Professional features, analytics | 2-3 weeks |
| **5** | Enterprise Tier | Enterprise integration, governance | 4-6 weeks |
| **6** | Ultimate Tier | AI/ML, advanced automation | 6-8 weeks |
| **7** | Specialized | Industry-specific deployment | 8-12 weeks |

**Automation Integration:**

- Rule 1: Auto-assigns based on component and labels
- Phase checkbox fields auto-checked based on this field
- Phase-based board view column positioning
- Phase-based timeline and scheduling
- Phase progression notifications

**Usage Workflow:**

```
Issue Created:
1. Assigned to appropriate phase (based on component)
2. Added to that phase's template if applicable
3. Scheduled for that phase timeline
4. Grouped in phase-based reports

Issue Progresses:
1. May stay in same phase through completion
2. Can advance to next phase if scope expands
3. Rarely moves backward (escalation only)
4. Final phase indicates release readiness
```

**Best Practices:**

- Ensure phase alignment with component team
- Document phase assignment rationale
- Review phase progression monthly
- Escalate phase blocking issues immediately

---

### Field 5: Assigned Team Member

**Field Details:**

```yaml
Field Name: Assigned Team Member
Type: User Select (Multiple)
Field ID: assigned_member_field
Required: No
Default Value: None
Max Assignees: 3 (recommended)
Options: All repository collaborators
Can Add External Users: Yes
```

**Purpose:**

- Track issue ownership and accountability
- Enable personal task views
- Support workload distribution
- Drive task notifications

**Assignment Guidelines:**

| Situation | Assignment | Count | Notes |
|-----------|-----------|-------|-------|
| Clearly owned task | Single owner | 1 | Primary responsibility |
| Cross-functional work | Multiple | 2-3 | Each has section responsibility |
| Mentoring/review | Mentor + learner | 2 | Skill transfer |
| Paired programming | Both developers | 2 | Collaborative work |
| Large task | Primary + secondary | 2 | Workload distribution |

**Assignment Process:**

```
Step 1: Identify task owner based on expertise
Step 2: Verify their capacity (use My Work view)
Step 3: Assign at sprint planning or ad-hoc
Step 4: Set start date if deferred
Step 5: Communicate assignment
Step 6: Update as circumstances change
```

**Automation Integration:**

- Triggers personal task notifications
- Populates "My Work" board view
- Used in individual velocity calculations
- Influences capacity planning
- Escalates overdue personal tasks

**Multi-Assignment Scenarios:**

```
Scenario 1: Code review and merge
- Developer (primary): 80% responsibility
- Tech lead (reviewer): 20% responsibility

Scenario 2: Cross-team initiative
- Team A lead: 60% for section A
- Team B lead: 40% for section B

Scenario 3: Mentoring
- Mentor: 30% oversight
- Junior engineer: 70% implementation
```

**Best Practices:**

- Verify capacity before assigning
- Limit to 3 maximum assignees
- Clear primary responsibility
- Update when priorities shift
- Track personal workload with My Work view

---

## Tier 2: Component Tracking Fields

### Fields 6-13: Component Checkbox Fields

**Overview:**
These eight checkbox fields provide fine-grained component tracking and enable multi-component issue handling through individual checkboxes.

**Field Details:**

```yaml
Base Configuration:
Type: Checkbox
Multiple: Yes (all can be checked simultaneously)
Required: No
Default: Unchecked
Auto-Update: Yes (when Component field changes)
Display: Show in component-specific views
```

### Field 6: Component: Monado

**Purpose:** Mark if issue affects display server functionality

**Auto-Checked When:**

```
Component field = "Monado" OR
Labels include "component-monado" OR
Scope includes display rendering
```

**Related Work:**

- Rendering pipeline
- Display management
- Output handling
- Graphics optimization

**When to Check Manually:**

```
Issue crosses into display concerns even if
primary component is different.

Example: "Optimize AI model for display performance"
- Primary Component: AI
- Also check: Monado (because affects display)
```

**Team:** Display Team
**Related Phase:** Phase 1-2 (base features), Phase 4+ (enhancements)

---

### Field 7: Component: Security

**Purpose:** Mark if issue affects security infrastructure

**Auto-Checked When:**

```
Component field = "Security" OR
Labels include "component-security" OR
Issue involves auth, encryption, audit
```

**Related Work:**

- Authentication & authorization
- Encryption (at-rest, in-transit, end-to-end)
- Access control lists
- Security audit logging
- Compliance requirements
- Vulnerability management

**When to Check Manually:**

```
Any security implications regardless of
primary component.

Example: "Add rate limiting to API"
- Primary Component: Stack
- Also check: Security (rate limit is security)
```

**Team:** Security Team
**Related Phase:** Phase 3-5 (security hardening)

---

### Field 8: Component: AI

**Purpose:** Mark if issue affects AI/ML functionality

**Auto-Checked When:**

```
Component field = "AI" OR
Labels include "component-ai" OR
Involves ML models, predictions, intelligence
```

**Related Work:**

- ML model development & training
- Model inference optimization
- Recommendation engine
- Predictive analytics
- Natural language processing
- Computer vision

**When to Check Manually:**

```
ML concerns in non-AI components.

Example: "Add ML-based anomaly detection to monitoring"
- Primary Component: DevOps
- Also check: AI (uses AI feature)
```

**Team:** ML/AI Team
**Related Phase:** Phase 4-6 (AI features)

---

### Field 9: Component: GUI

**Purpose:** Mark if issue affects GUI/UI components

**Auto-Checked When:**

```
Component field = "GUI" OR
Labels include "component-gui" OR
Involves user interface changes
```

**Related Work:**

- UI component development
- User experience improvements
- Accessibility enhancements
- Responsive design
- Theme and styling
- User interaction flows

**When to Check Manually:**

```
UI implications in backend work.

Example: "Add new data export format"
- Primary Component: Stack
- Also check: GUI (needs UI for export)
```

**Team:** Frontend/GUI Team
**Related Phase:** Phase 2-4 (UI features)

---

### Field 10: Component: Agents

**Purpose:** Mark if issue affects Agent/autonomous systems

**Auto-Checked When:**

```
Component field = "Agents" OR
Labels include "component-agents" OR
Involves autonomous or background services
```

**Related Work:**

- Background service development
- Autonomous agent implementation
- Worker process optimization
- Message queue handling
- Service orchestration
- Event-driven architecture

**When to Check Manually:**

```
Agent involvement in cross-component work.

Example: "Implement background retry mechanism"
- Primary Component: Hub
- Also check: Agents (agents do retries)
```

**Team:** Systems/Agent Team
**Related Phase:** Phase 3-5 (agent features)

---

### Field 11: Component: Hub

**Purpose:** Mark if issue affects Hub/coordination layer

**Auto-Checked When:**

```
Component field = "Hub" OR
Labels include "component-hub" OR
Involves central coordination or orchestration
```

**Related Work:**

- Central coordination logic
- Service mesh/communication
- Data routing and flow
- Integration orchestration
- System-wide transactions
- State management

**When to Check Manually:**

```
Coordination concerns across components.

Example: "Implement distributed transaction coordination"
- Primary Component: Stack
- Also check: Hub (central coordination)
```

**Team:** Core/Platform Team
**Related Phase:** Phase 1-7 (foundational)

---

### Field 12: Component: Stack

**Purpose:** Mark if issue affects technology stack

**Auto-Checked When:**

```
Component field = "Stack" OR
Labels include "component-stack" OR
Involves dependencies, frameworks, or infrastructure code
```

**Related Work:**

- Dependency management
- Framework upgrades
- Library integration
- Build system
- Runtime optimization
- Package management

**When to Check Manually:**

```
Stack implications in feature work.

Example: "Upgrade to new Node.js LTS"
- Primary Component: Stack
- Also check: Infrastructure (affects deployment)
```

**Team:** DevOps/Platform Team
**Related Phase:** Phase 0-1 (base), Phase 4+ (upgrades)

---

### Field 13: Component: Infrastructure

**Purpose:** Mark if issue affects infrastructure/DevOps

**Auto-Checked When:**

```
Component field = "Infrastructure" OR
Labels include "component-infrastructure" OR
Involves servers, networking, storage, deployment
```

**Related Work:**

- Server provisioning
- Network configuration
- Storage management
- Database administration
- Deployment pipelines
- Cloud infrastructure
- Disaster recovery

**When to Check Manually:**

```
Infrastructure needs in any work.

Example: "Implement database replication"
- Primary Component: Hub
- Also check: Infrastructure (uses infra)
```

**Team:** DevOps/Infrastructure Team
**Related Phase:** Phase 1+ (persistent need)

---

## Tier 3: Phase Management Fields

### Fields 14-19: Phase Assignment Checkboxes

**Overview:**
These six fields enable phase-based filtering, reporting, and dependency tracking.

### Field 14: Phase 0: Pre-Install

**Purpose:** Mark pre-installation phase work

**Auto-Checked When:**

```
Status Phase field = "Phase 0"
```

**Typical Work:**

- Requirements gathering
- Architecture design
- Resource planning
- Risk assessment
- Timeline creation
- Success criteria definition

**Usage:**

```
View: "View all Phase 0 work"
Filter: Show only Phase 0 items
Report: Phase 0 completion percentage
Metrics: Phase 0 velocity and cycle time
```

---

### Field 15: Phase 1: Fresh Install

**Purpose:** Mark fresh installation phase work

**Auto-Checked When:**

```
Status Phase field = "Phase 1"
```

**Typical Work:**

- System installation
- Base configuration
- Initial testing
- Documentation
- Team training
- Baseline establishment

**Phase Dependencies:**

```
Must complete Phase 0 before Phase 1 work
Cannot deploy Phase 1 until Phase 0 complete
Blockers in Phase 0 block Phase 1 start
```

---

### Field 16: Phase 2: Enhanced

**Purpose:** Mark enhanced configuration phase work

**Auto-Checked When:**

```
Status Phase field = "Phase 2"
```

**Typical Work:**

- Feature enablement
- Performance tuning
- Security hardening
- Integration enhancement
- Advanced configuration
- User training

---

### Field 17: Phase 3: Advanced

**Purpose:** Mark advanced deployment phase work

**Auto-Checked When:**

```
Status Phase field = "Phase 3"
```

**Typical Work:**

- High availability setup
- Disaster recovery configuration
- Multi-tenant support
- Enterprise security
- SLA compliance
- Advanced monitoring

---

### Field 18: Phase 4: Professional

**Purpose:** Mark professional tier phase work

**Auto-Checked When:**

```
Status Phase field = "Phase 4"
```

**Typical Work:**

- Professional features
- Advanced analytics
- Custom workflows
- Professional APIs
- Premium support
- Professional reporting

---

### Field 19: Phase 5: Enterprise

**Purpose:** Mark enterprise tier phase work

**Auto-Checked When:**

```
Status Phase field = "Phase 5"
```

**Typical Work:**

- Enterprise licensing
- Enterprise integrations
- Advanced governance
- Enterprise analytics
- Enterprise support
- Executive dashboards

---

## Tier 4: Resource Tracking Fields

### Field 20: Estimated Days

**Field Details:**

```yaml
Field Name: Estimated Days
Type: Number
Range: 0-365 days
Icon: Calendar
Required: No
Default: 0
Unit: Calendar days (not business days)
```

**Purpose:**

- Estimate calendar duration for task
- Enable resource scheduling
- Plan team capacity across days
- Communicate timeline expectations

**Relationship to Effort Estimate:**

```
Effort Estimate (Story Points):
  - Measure of work complexity
  - 1 point ≈ 1-2 hours dev work
  - Team velocity: 40-50 points/week

Estimated Days:
  - Calendar time needed
  - Includes planning, review, integration, testing
  - More realistic for stakeholder communication
  - Accounts for parallelization and dependencies

Conversion Formula:
  Estimated Days = (Points / Team Velocity) * 5 days/week + 1
  
  Example:
  - 8 points, 40 points/week velocity
  - 8/40 * 5 = 1 day development
  - + 0.5 days planning
  - + 0.5 days testing/review
  - + 1 day integration/deployment
  = 3.5 days ≈ 4 days estimated
```

**Usage Guidelines:**

| Scenario | Days | Formula | Notes |
|----------|------|---------|-------|
| Quick fix | 1 | Points: 1-2 | Same day if started early |
| Feature | 3-5 | Points: 3-5 | Includes review and testing |
| Major feature | 5-10 | Points: 8 | Includes multiple phases |
| Complex system | 10-20 | Points: 13 | Multiple developer weeks |
| Platform change | 20+ | Points: 13+ | Requires coordination |

**Setting Process:**

```
Step 1: Determine effort in story points
Step 2: Convert to estimated days using formula
Step 3: Account for dependencies and blockers
Step 4: Consider team parallel capacity
Step 5: Add buffer for unknowns (10-20%)
Step 6: Discuss with team lead
Step 7: Finalize estimate
```

**Automation Integration:**

- Used for timeline and Gantt chart views
- Combined with start date for deadline calculation
- Influences resource allocation
- Used in capacity planning
- Impacts sprint scheduling

**Best Practices:**

- Keep between estimated days and actual effort consistent
- Review and update as work progresses
- Use historical data for calibration
- Consider external factors (meetings, support)
- Build in 15-20% buffer for unknowns

---

### Field 21: Start Date

**Field Details:**

```yaml
Field Name: Start Date
Type: Date
Icon: Calendar Start
Required: No
Default: Today (when first set)
Past Dates: Allowed
Future Dates: Allowed
Nullable: Yes (can be cleared)
```

**Purpose:**

- Set planned work start date
- Enable timeline and schedule views
- Trigger "time to start" notifications
- Support Gantt chart visualization
- Plan resource allocation

**Start Date Scenarios:**

| Scenario | Start Date | Rationale | Notes |
|----------|-----------|-----------|-------|
| Immediate work | Today | Start ASAP | Phase 0 dependencies met |
| Planned next week | +7 days | Capacity planning | Waiting for resource |
| Future phase work | +30 days | Phase blocking | Depends on earlier phase |
| Blocked work | [Future] | Blocked | Update when blocker resolves |
| Already started | [Past] | Retroactive | Set to actual start |

**Timeline Example:**

```
Issue: "Implement authentication"
Effort: 5 points
Estimated Days: 3
Start Date: 2026-04-20 (Monday)
Target Date: 2026-04-23 (Thursday)

Timeline View:
  Apr 20 → ████ ← Work period
  Apr 21 → ████
  Apr 22 → ████
  Apr 23 → ████ ← Target completion
```

**Automation Integration:**

- Triggers start notifications when date arrives
- Used in personal task views and reminders
- Influences sprint planning
- Enables timeline conflict detection
- Used in workload distribution

**Best Practices:**

- Set start date during sprint planning
- Use future dates for planned work
- Update if plans change
- Consider team capacity when planning
- Schedule high-priority items first

---

### Field 22: Target Completion Date

**Field Details:**

```yaml
Field Name: Target Completion Date
Type: Date
Icon: Target
Required: No
Default: 30 days from start date
Past Dates: Allowed if completed
Future Dates: Recommended
Nullable: Yes
```

**Purpose:**

- Set target completion deadline
- Enable due date tracking
- Trigger deadline notifications
- Support deadline-based prioritization
- Calculate on-time delivery metrics

**Setting Target Date:**

```
Formula: Target Date = Start Date + Estimated Days

Example 1: Simple task
- Start Date: 2026-04-20 (Monday)
- Estimated Days: 1
- Target Date: 2026-04-20 (same day)

Example 2: Medium task
- Start Date: 2026-04-20 (Monday)
- Estimated Days: 3
- Target Date: 2026-04-23 (Thursday)

Example 3: Long task
- Start Date: 2026-04-20 (Monday)
- Estimated Days: 10
- Target Date: 2026-05-02 (Friday, 2 weeks later)

Example 4: Strategic deadline
- Business Requirement: Ship by 2026-05-15
- Start Date: 2026-04-15 (planning buffer)
- Target Date: 2026-05-13 (2-day buffer)
```

**Deadline Management:**

| Days Until Deadline | Status | Action |
|-------------------|--------|--------|
| > 7 days | Healthy | Monitor |
| 3-7 days | Yellow | Increase focus |
| 1-3 days | Red | Daily check-in |
| 0 days | Overdue | Escalate |
| Overdue | Critical | Report daily |

**Automation Integration:**

- Notifications when deadline approaches
- Escalation when overdue
- Red highlighting in board view
- Impacts sprint prioritization
- Used in on-time delivery metrics
- Blocks vacation approvals if overdue

**Best Practices:**

- Set realistic deadlines considering dependencies
- Add buffer for unknowns
- Communicate deadlines clearly
- Escalate early if at risk
- Track on-time delivery metrics

---

## Tier 5: Advanced Automation Fields

### Field 23: Tier Classification

**Field Details:**

```yaml
Field Name: Tier Classification
Type: Single Select
Icon: Star
Required: No
Default: None (set by automation or manually)
Options: [Professional, Enterprise, Ultimate, Basic, Custom]
Automation Level: Rule 4 (Auto-assign based on component)
```

**Purpose:**

- Classify feature tier for rollout planning
- Enable tier-specific filtering and reporting
- Support tier-based prioritization
- Track tier feature completion

**Tier Definitions:**

| Tier | Target Market | Features | Entry Cost | SLA |
|------|---------------|----------|-----------|-----|
| **Basic** | Startups | Core features only | Free/Low | Best-effort |
| **Professional** | Growing companies | Advanced features, analytics | Medium | 4-hour response |
| **Enterprise** | Large enterprises | All features, SLA, support | High | 1-hour response |
| **Ultimate** | Specialized/Premium | Everything + customization | Premium | 30-min response |
| **Custom** | One-off implementations | As required | Variable | Custom |

**Auto-Assignment Logic (Rule 4):**

```
IF Component IN (Monado, Hub, Stack) THEN Tier = Enterprise
IF Component IN (AI, Agents) THEN Tier = Professional
IF Component IN (GUI, Security) THEN
  IF Priority = Critical THEN Tier = Enterprise
  ELSE Tier = Professional
ELSE Tier = Professional

IF Priority = Critical THEN Tier >= Enterprise (minimum)
IF Effort >= 5 THEN suggest Tier >= Professional
```

**Manual Override:**

```
When to Override Auto-Assignment:
1. Tier conflicts: Choose highest tier
2. Cross-tier features: Assign to highest applicable tier
3. Strategic priority: Elevate tier if business critical
4. Customer-specific: Use Custom tier

Override Process:
- Set field manually
- Add comment explaining rationale
- Notify affected team leads
- Document in tier-specific view
```

**Usage in Workflows:**

```
Professional Board View:
- Show all Professional tier items
- Filter by phase and component
- Track professional feature adoption

Enterprise Board View:
- Show all Enterprise+ tier items
- High-visibility tracking
- Executive reporting

Tier-Based Planning:
- Schedule tiers for sequential rollout
- Allocate resources by tier
- Manage feature dependencies
```

**Automation Integration:**

- Triggers tier-specific notifications
- Used in tier-based board views
- Influences customer-facing roadmap
- Impacts pricing and licensing
- Used in revenue tracking

---

### Field 24: Automation Status

**Field Details:**

```yaml
Field Name: Automation Status
Type: Single Select
Icon: Robot
Required: No
Default: Manual
Options: [Manual, Auto-Tracked, Auto-Updated, Full-Automation]
Auto-Updated: Yes (by automation rules)
```

**Purpose:**

- Track automation level for each issue
- Enable automation efficiency metrics
- Identify opportunities for increased automation
- Debug automation rule effectiveness

**Automation Status Levels:**

| Status | Meaning | Updated By | Actions | Example |
|--------|---------|-----------|---------|---------|
| **Manual** | No automation involved | Manual assignment | All manual | Simple doc update |
| **Auto-Tracked** | Issue creation auto-handled | Rule 1 (phase assign) | Auto phase/component | Created with label |
| **Auto-Updated** | Status sync with PR/Action | Rule 2 (PR status) | Auto column moves | PR created, linked |
| **Full-Automation** | End-to-end automated | Rules 1-4 combined | Create to Done | Auto-closed by PR merge |

**Automation Status Progression:**

```
Issue Lifecycle with Automation:

1. Issue Created
   Status: Manual (requires manual setup)
   
2. Label Applied → Component Auto-Set
   Status: Auto-Tracked (tracking started)
   
3. PR Linked → Status Updates Begin
   Status: Auto-Updated (PR drives status)
   
4. PR Merged → Issue Auto-Closes
   Status: Full-Automation (complete automation)
```

**Metrics by Automation Status:**

```
Manual Issues:
- Count: 20% of total
- Cycle Time: 18 days average
- Effort: High manual overhead

Auto-Tracked Issues:
- Count: 30% of total
- Cycle Time: 14 days average
- Effort: Reduced overhead

Auto-Updated Issues:
- Count: 35% of total
- Cycle Time: 10 days average
- Effort: Low overhead

Full-Automation Issues:
- Count: 15% of total
- Cycle Time: 6 days average
- Effort: Minimal overhead

Goal: Increase Full-Automation to 40%+
```

**Automation Integration:**

- Updated automatically when rules trigger
- Used in automation efficiency dashboard
- Identifies process optimization opportunities
- Tracks automation ROI
- Supports continuous improvement

**Best Practices:**

- Apply labels to enable auto-tracking
- Link PRs to enable auto-updates
- Write clear issue descriptions for automation
- Review automation status distributions
- Target high-value manual items for automation

---

### Field 25: Integration Reference

**Field Details:**

```yaml
Field Name: Integration Reference
Type: Text (Single line)
Icon: Link
Required: No
Default: None
Max Length: 255 characters
Format: Free text, suggest format: SYSTEM:ID
Example: JIRA:PROJ-1234
```

**Purpose:**

- Cross-reference external system issues
- Enable bi-directional tracking
- Support system migrations
- Track related work in other tools
- Maintain audit trail

**Supported Formats:**

| System | Format | Example | Purpose |
|--------|--------|---------|---------|
| **Jira** | JIRA:PROJECT-NUM | JIRA:HELIOS-456 | Jira sync |
| **Linear** | LINEAR:KEY | LINEAR:JOH-123 | Linear tracking |
| **Azure DevOps** | ADO:PROJECT/NUM | ADO:Helios/789 | Azure sync |
| **Notion** | NOTION:DB/ID | NOTION:abc123def456 | Notion link |
| **Slack** | SLACK:CHANNEL/TS | SLACK:dev/1234567890.5678 | Slack thread |
| **Custom** | CUSTOM:ID | CUSTOM:EXT-5000 | Custom system |

**Usage Scenarios:**

```
Scenario 1: Jira Migration
Issue: "Implement feature X"
Integration Ref: JIRA:OLD-1234
Status: Migrated from old system, reference preserved

Scenario 2: Multi-system tracking
Issue: "Security audit"
Integration Ref: JIRA:SEC-890 + LINEAR:SEC-45
Status: Tracked in multiple systems

Scenario 3: External customer
Issue: "Customer feature request"
Integration Ref: SLACK:customer-requests/1234567
Status: Linked to customer request
```

**Entry Process:**

```
Step 1: Identify external system issue
Step 2: Copy external system ID
Step 3: Enter in Integration Reference field
Step 4: Use format: SYSTEM:ID
Step 5: Include URL in comment if helpful
Step 6: Link bidirectionally if possible
```

**Automation Integration:**

- Used for cross-system reporting
- Enables integration data sync
- Supports system migration tracking
- Used in audit compliance
- Enables historical reference

**Best Practices:**

- Use consistent format conventions
- Include external URL in description
- Keep reference current during status changes
- Remove reference after system migration complete
- Use for historical tracking and compliance

---

## Field Creation Instructions

### GitHub Projects Field Creation Process

#### Step 1: Access Project Settings

```
1. Navigate to GitHub Repository
2. Click "Projects" tab
3. Select HELIOS Platform board
4. Click "⋯" (more options)
5. Select "Settings"
6. Click "Custom fields" (left sidebar)
```

#### Step 2: Add New Field

```
1. Click "+ Add field"
2. Enter field name (use names from guide)
3. Select field type (see field details)
4. Configure options (for select fields)
5. Set default value (if applicable)
6. Save field
```

#### Step 3: Field Configuration Example

**Priority Field:**

```
1. Click "+ Add field"
2. Name: "Priority"
3. Type: "Single select"
4. Options:
   - Critical
   - High
   - Medium
   - Low
5. Default: "Medium"
6. Click "Save field"
```

**Effort Estimate Field:**

```
1. Click "+ Add field"
2. Name: "Effort Estimate"
3. Type: "Single select"
4. Options:
   - 1 (XS)
   - 2 (S)
   - 3 (M)
   - 5 (L)
   - 8 (XL)
   - 13 (XXL)
5. No default (optional field)
6. Click "Save field"
```

---

## Field Integration Matrix

### Automation Rule Integration

| Rule | Trigger Fields | Action Fields | Output |
|------|--------|--------|---------|
| **Rule 1: Phase Assignment** | Label, Component | Status Phase, Phase Checkboxes, Automation Status | Auto-assign phase |
| **Rule 2: PR Status Sync** | PR Status, Linked Issue | Column, Automation Status, Updated Field | Update on PR change |
| **Rule 3: Auto-Move to Done** | Column = Review, PR = Merged, Checkboxes = All | Column = Done, Cycle Time, Metrics | Auto-complete |
| **Rule 4: Tier Assignment** | Component, Priority, Effort | Tier Classification, Automation Status | Auto-assign tier |

### View Integration

| View | Primary Field | Secondary Fields | Filter | Sort |
|------|--------|--------|--------|--------|
| **By Phase** | Status Phase | Component, Priority | By phase | By priority |
| **By Component** | Component | Phase, Status | By component | By priority |
| **By Tier** | Tier Classification | Component, Status Phase | By tier | By priority |
| **By Status** | Board Column | Priority, Assignee | By column | By priority |
| **By Priority** | Priority | Component, Status Phase | By priority | By due date |
| **My Work** | Assigned Team | Priority, Status | Assigned to = Me | By due date |

---

## Best Practices

### Field Selection & Usage

**DO:**

- ✓ Use all 5 tiers for comprehensive tracking
- ✓ Set required fields (Priority, Component, Status Phase) for every issue
- ✓ Update fields as issue progresses
- ✓ Use consistent terminology
- ✓ Review field usage monthly

**DON'T:**

- ✗ Leave required fields empty
- ✗ Use custom fields inconsistently
- ✗ Create duplicate fields (consolidate instead)
- ✗ Ignore automation updates
- ✗ Use fields for purposes not intended

### Field Maintenance

**Weekly:**

- Review blocked items and update component fields
- Verify effort estimates accuracy
- Check deadlines for upcoming items

**Monthly:**

- Analyze field usage patterns
- Identify underutilized fields
- Plan field optimization
- Review automation status distribution
- Update field definitions if needed

### Field Documentation

- Keep field purposes clear
- Document field value options
- Explain automation integration
- Provide usage examples
- Maintain this guide with updates

---

**Document Control:**

- Version: 1.0
- Last Updated: 2026-04-13
- Field Count: 25
- Integration Status: Complete
- Automation Status: Fully Configured

For questions on specific fields, refer to the BOARD_SETUP_COMPLETION_SUMMARY.md or contact your project administrator.
