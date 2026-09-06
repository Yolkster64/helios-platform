# HELIOS Platform - Guide for Team Leads

**Document Version:** 1.0  
**Date:** April 13, 2026  
**Audience:** Team Leads, Scrum Masters, Squad Leads

## Team Structure & Roles

### Recommended Team Size: 6-8 People

```
Team Lead (1)
├─ Backend Developers (2-3)
├─ QA/Test Engineer (1)
├─ DevOps Engineer (1)
└─ Documentation Specialist (1)
```

### Role Responsibilities

| Role | Primary | Secondary | Backup |
|------|---------|-----------|--------|
| Lead | Coordination | Decisions | Technical |
| Dev | Code | Testing | Docs |
| QA | Testing | Docs | Dev |
| DevOps | Deployment | Monitoring | Infrastructure |
| Docs | Documentation | Communication | Support |

## Sprint Planning

### 2-Week Sprint Cycle

**Sprint Planning (Day 1, 1 hour)**

```
Team Meeting: 1 hour total
├─ Review previous sprint (10 min)
│  ├─ What went well?
│  ├─ What can improve?
│  └─ Velocity: ___ points
│
├─ Plan current sprint (30 min)
│  ├─ Select features (40-50 points)
│  ├─ Assign tasks
│  ├─ Identify blockers
│  └─ Set sprint goal
│
└─ Breakdown & commit (20 min)
   ├─ Break features into tasks
   ├─ Estimate each task
   ├─ Team commits
   └─ Update project board
```

**Daily Standup (15 minutes)**

```
Every morning, 09:00 AM, all team
├─ Completed yesterday (3 min)
│  └─ Everyone: 1-2 sentences
│
├─ Working today (3 min)
│  └─ Everyone: 1-2 sentences
│
├─ Blockers (5 min)
│  └─ Anyone stuck? How can we help?
│
└─ Focus (4 min)
   └─ Confirm today's priorities
```

**Sprint Review (Day 10, 45 min)**

```
Demo & Feedback: 45 minutes
├─ Demo completed items (20 min)
│  └─ Show working features
│
├─ Collect feedback (15 min)
│  └─ Questions & suggestions
│
└─ Document (10 min)
   └─ Record decisions
```

**Sprint Retrospective (Day 10, 45 min)**

```
Continuous Improvement: 45 minutes
├─ What went well? (10 min)
├─ What could improve? (10 min)
├─ Action items (15 min)
│  └─ 2-3 specific improvements
└─ Celebrate wins (10 min)
```

## Task Management

### Story Template

```markdown
# Story Title

## User Story
As a [user type]
I want to [capability]
So that [business value]

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

## Definition of Done
- [ ] Code written & reviewed
- [ ] Tests passing (85%+ coverage)
- [ ] Documentation updated
- [ ] Demo-ready
- [ ] Merged to main

## Complexity
- [Simple/Medium/Complex]

## Phase
- [0/1/2/3]

## Effort
- [X points]
```

### Task Assignment

**Assignment Process:**

1. **Discuss** - Team understands task
2. **Estimate** - Estimate effort (points)
3. **Assign** - Assign to person who volunteers or has capacity
4. **Commit** - Assignee confirms doable in sprint
5. **Track** - Update status daily

**Task Status Workflow:**

```
Backlog → Ready → In Progress → Review → Done

- Backlog: Not ready for sprint
- Ready: Meets Definition of Ready
- In Progress: Developer working on it
- Review: PR open, waiting review
- Done: Merged & tested
```

## Metrics & Health Checks

### Sprint Velocity

**Calculate:**

```
Week 1: 20 points
Week 2: 15 points
Sprint Total: 35 points

Velocity: 35 points/sprint
Trend: Stable or improving?
```

**Interpretation:**

- Stable velocity (±10%): Team is healthy
- Increasing: Team improving
- Decreasing: Blockers or burnout?

### Team Health Indicators

| Indicator | Healthy | Warning | Action |
|-----------|---------|---------|--------|
| Velocity | Stable | ±20% | Investigate |
| Quality | 85%+ tests | 70-85% | Improve testing |
| Burndown | Smooth | Steep | Investigate |
| Attendance | 100% | <95% | Check-in |
| Morale | High | Declining | 1-on-1s |
| Blockers | <2 | >5 | Daily resolution |

### Track KPIs

**Weekly Report Template:**

```
WEEK OF APRIL 8-12, 2026

✅ Completed
├─ Feature X: Done ✅
├─ Bug Fix Y: Done ✅
└─ Docs Update: Done ✅

⏳ In Progress
├─ Feature Z: 80% complete
└─ Refactoring: 50% complete

🚫 Blockers
├─ Waiting for approval from...
└─ Dependency issue with...

📊 Metrics
├─ Points completed: 35/40 (87.5%)
├─ Velocity trend: Stable
├─ Test coverage: 86%
├─ Build success: 98%

📝 Notes
├─ Team morale: High
├─ No major issues
└─ On track for sprint goal
```

## Communication

### Communication Plan

**Daily:**

- Morning standup (15 min)
- Slack updates on blockers
- GitHub notifications (auto)

**Weekly:**

- Status report (written)
- Sprint review (if applicable)
- 1-on-1 with manager

**Monthly:**

- All-hands meeting
- Leadership report
- Roadmap review

### Escalation Path

**Level 1 - Team Lead (< 4 hours)**

- Can resolve independently
- Minor blocking issues
- Process questions

**Level 2 - Skip Manager (4-24 hours)**

- Needs manager input
- Resource allocation
- Technical decisions

**Level 3 - Director (24+ hours)**

- Business decision needed
- Strategic impact
- Customer-facing

## One-on-One Meetings

### Individual Meetings (Weekly, 30 min)

**Agenda:**

```
1. Personal Check-in (5 min)
   - How's life? Everything okay?

2. Last Week Review (5 min)
   - What accomplished?
   - What blocked you?
   - Anything surprising?

3. This Week Planning (5 min)
   - What's the priority?
   - Anything you need from me?
   - Any concerns?

4. Growth/Career (10 min)
   - Skills you want to develop?
   - Feedback on performance?
   - Career goals?

5. Closing (5 min)
   - Next week priorities
   - Follow-ups needed
   - Confirm next meeting
```

## Performance Management

### Feedback Framework (Monthly)

```
WHAT: Specific behavior observed
IMPACT: How did it affect the team?
EXPECTATION: What should happen?
SUPPORT: How can I help?

Example:
"I noticed you've been staying late 3-4 nights
a week. That might lead to burnout. I expect
you to work a sustainable pace. Let's talk
about how to manage workload."
```

### Recognition & Development

**Recognition (Immediate):**

- Celebrate wins in public (Slack, standup)
- Thank for help
- Escalate great work to leadership

**Development:**

- Identify skill gaps
- Provide learning opportunities
- Stretch assignments
- Mentoring relationships

## Change Management

### Feature Rollout

**Phase 1: Announcement (1 week)**

- Explain "why" and "what"
- Answer questions
- Address concerns

**Phase 2: Training (1 week)**

- Hands-on training sessions
- Practice with support
- Collect feedback

**Phase 3: Rollout (1 week)**

- Monitor adoption
- Support team
- Adjust as needed

**Phase 4: Optimization (Ongoing)**

- Gather feedback
- Refine process
- Document learnings

## Decision Making

### Framework for Decisions

**Quick Decisions (< 30 min):**

- Lead decides with input
- Communicate to team
- Move forward

**Complex Decisions (> 30 min):**

- Team discussion (30-60 min)
- Gather data (if needed)
- Pros/cons list
- Leader decides
- Communicate rationale

**Strategic Decisions:**

- Escalate to manager
- Get stakeholder input
- Document decision & rationale
- Communicate transparently

## Conflict Resolution

### Issue Escalation

**Step 1: Direct Conversation (24 hours)**

```
People involved: Talk it out
├─ What's the issue?
├─ What do we both need?
└─ What solution works for both?
```

**Step 2: Mediation (48 hours)**

```
If Step 1 doesn't work: Involve Lead
├─ Hear both sides
├─ Find common ground
└─ Propose solution
```

**Step 3: Management (72 hours)**

```
If Step 2 doesn't work: Escalate up
├─ HR involvement if needed
├─ Formal process
└─ Resolution
```

## Team Health & Morale

### Red Flags (Take Action!)

- ⚠️ People arriving late/leaving early consistently
- ⚠️ Low participation in standups
- ⚠️ Declining test coverage or code quality
- ⚠️ Frequent conflicts between team members
- ⚠️ Burnout symptoms (long hours, stress)
- ⚠️ Quiet people becoming quieter
- ⚠️ Increased sick days or absences

### Team Building Activities

**Monthly:**

- Lunch & learn sessions
- Coffee chats (15 min 1-on-1s)
- Team lunch (in-person or virtual)
- Recognition ceremony

**Quarterly:**

- Offsite or team building
- Career development workshop
- Project retrospective
- Celebration of milestones

## Tools & Access

### Key Tools

| Tool | Purpose | Access |
|------|---------|--------|
| GitHub | Code & project mgmt | Project URL |
| Slack | Communication | Workspace |
| Jira/Board | Task tracking | Project URL |
| Documentation | Knowledge base | Wiki |
| Dashboard | Metrics | URL |

### Important Links

- **Project Board:** https://github.com/your-org/helios-platform/projects/3
- **Slack Channel:** #helios-development
- **Documentation:** https://your-org.github.io/helios-platform
- **Dashboard:** https://dashboard.helios-platform.org

## Coaching & Development

### Coaching Conversations

**When someone struggles:**

```
1. Ask questions (don't tell)
   "What did you try?"
   "What happened?"
   "What would you try next?"

2. Listen (really listen)
   Understand their thinking
   Don't interrupt

3. Guide (help them learn)
   "What have you learned?"
   "How could this apply here?"
   "What will you try?"

4. Follow up
   "How did it go?"
   "What did you learn?"
```

### Career Development

**Have career conversation:**

- Where do they want to go?
- What skills needed?
- How can we help?
- Create development plan

---

**Status: ✅ COMPLETE TEAM LEAD GUIDE**
