# {{PROJECT_NAME}} - Release Notes & Version History

**Template Version:** 1.0  
**Latest Release:** {{LATEST_VERSION}}  
**Last Updated:** {{LAST_UPDATED}}

---

## 📋 Quick Navigation

- [Latest Release](#-latest-release)
- [Version History](#-version-history)
- [Migration Guides](#-migration-guides)
- [Deprecations](#-deprecations)
- [Known Issues](#-known-issues)

---

## 🎉 Latest Release

### {{LATEST_VERSION}} ({{LATEST_RELEASE_DATE}})

**Status:** {{RELEASE_STATUS}} | **Stability:** {{STABILITY_LEVEL}}

#### 🎯 Release Highlights

{{LATEST_HIGHLIGHTS}}

---

#### ✨ New Features

- **{{FEATURE_1}}**: {{FEATURE_1_DESC}}
  - Use case: {{FEATURE_1_USE_CASE}}
  - Example: `{{FEATURE_1_EXAMPLE}}`

- **{{FEATURE_2}}**: {{FEATURE_2_DESC}}
  - Impact: {{FEATURE_2_IMPACT}}

- **{{FEATURE_3}}**: {{FEATURE_3_DESC}}

---

#### 🐛 Bug Fixes

- Fixed {{BUG_1}}: {{BUG_1_DESC}} (#{{BUG_1_ISSUE_NUMBER}})
- Fixed {{BUG_2}}: {{BUG_2_DESC}} (#{{BUG_2_ISSUE_NUMBER}})
- Fixed {{BUG_3}}: {{BUG_3_DESC}} (#{{BUG_3_ISSUE_NUMBER}})

---

#### 🚀 Performance Improvements

- {{PERF_IMPROVEMENT_1}}: {{PERF_IMPROVEMENT_1_DESC}}
  - Before: {{BEFORE_PERF_1}}
  - After: {{AFTER_PERF_1}}
  - Improvement: {{IMPROVEMENT_PERCENT_1}}%

- {{PERF_IMPROVEMENT_2}}: {{PERF_IMPROVEMENT_2_DESC}}

---

#### 🔒 Security Updates

- {{SECURITY_UPDATE_1}}: {{SECURITY_UPDATE_1_DESC}} (CVSS: {{CVSS_1}})
- {{SECURITY_UPDATE_2}}: {{SECURITY_UPDATE_2_DESC}} (CVSS: {{CVSS_2}})

**Affected Versions:** {{AFFECTED_VERSIONS}}  
**Upgrade:** {{SECURITY_UPGRADE_IMPORTANCE}}

---

#### 📦 Dependencies Updated

| Dependency | From | To | Reason |
|------------|------|-----|--------|
| {{DEP_1}} | {{DEP_1_FROM}} | {{DEP_1_TO}} | {{DEP_1_REASON}} |
| {{DEP_2}} | {{DEP_2_FROM}} | {{DEP_2_TO}} | {{DEP_2_REASON}} |
| {{DEP_3}} | {{DEP_3_FROM}} | {{DEP_3_TO}} | {{DEP_3_REASON}} |

---

#### 📚 Documentation Updates

- {{DOC_UPDATE_1}}: {{DOC_UPDATE_1_DESC}}
- {{DOC_UPDATE_2}}: {{DOC_UPDATE_2_DESC}}
- {{DOC_UPDATE_3}}: {{DOC_UPDATE_3_DESC}}

---

#### 🔄 Breaking Changes

{{BREAKING_CHANGES_INTRO}}

```powershell
# Old (v{{OLD_VERSION}})
{{OLD_CODE_EXAMPLE}}

# New (v{{LATEST_VERSION}})
{{NEW_CODE_EXAMPLE}}
```

**Migration Guide:** [See below](#-migration-guides)

---

#### ⚠️ Deprecations

The following are deprecated and will be removed in {{DEPRECATION_REMOVAL_VERSION}}:

- `{{DEPRECATED_ITEM_1}}`: Use `{{REPLACEMENT_1}}` instead
- `{{DEPRECATED_ITEM_2}}`: Use `{{REPLACEMENT_2}}` instead

---

#### 📊 Release Statistics

| Metric | Value |
|--------|-------|
| Commits | {{COMMITS_COUNT}} |
| Files Changed | {{FILES_CHANGED}} |
| Lines Added | +{{LINES_ADDED}} |
| Lines Removed | -{{LINES_REMOVED}} |
| Contributors | {{CONTRIBUTOR_COUNT}} |
| Issues Closed | {{ISSUES_CLOSED}} |
| Pull Requests | {{PR_COUNT}} |

---

#### 🙏 Contributors

This release was made possible by {{CONTRIBUTOR_COUNT}} contributors:

{{CONTRIBUTOR_LIST}}

---

#### 📥 Installation / Upgrade

**For new installations:**

```powershell
{{INSTALL_CMD}}
```

**For upgrades from previous version:**

```powershell
# Backup current version
{{BACKUP_CURRENT_CMD}}

# Upgrade
{{UPGRADE_CMD}}

# Verify upgrade
{{VERIFY_UPGRADE_CMD}}
```

**See:** [Upgrade Guide](#migration-guide-vprev_version-to-vlatest_version)

---

#### 📖 Documentation

- [README](./README.md) - Project overview
- [QUICK_START](./QUICK_START.md) - Get started in 5 minutes
- [CHANGELOG](https://github.com/{{REPO}}/blob/main/CHANGELOG.md) - Full changelog

---

---

## 📅 Version History

### Version {{VERSION_2}} ({{VERSION_2_DATE}})

**Status:** {{VERSION_2_STATUS}}

**Key Changes:**

- {{CHANGE_2_1}}
- {{CHANGE_2_2}}
- {{CHANGE_2_3}}

**Download:**

- [GitHub Release]({{GITHUB_RELEASE_2}})
- [NPM Package]({{NPM_RELEASE_2}})
- [Docker Image]({{DOCKER_RELEASE_2}})

**[Full Release Notes →]({{RELEASE_NOTES_2}})**

---

### Version {{VERSION_3}} ({{VERSION_3_DATE}})

**Status:** {{VERSION_3_STATUS}}

**Key Changes:**

- {{CHANGE_3_1}}
- {{CHANGE_3_2}}

**[Full Release Notes →]({{RELEASE_NOTES_3}})**

---

### Version {{VERSION_4}} ({{VERSION_4_DATE}})

**Status:** {{VERSION_4_STATUS}}

---

### Older Versions

| Version | Release Date | Status | Download |
|---------|-------------|--------|----------|
| {{OLD_V_1}} | {{OLD_D_1}} | {{OLD_STATUS_1}} | [Link]({{OLD_DL_1}}) |
| {{OLD_V_2}} | {{OLD_D_2}} | {{OLD_STATUS_2}} | [Link]({{OLD_DL_2}}) |
| {{OLD_V_3}} | {{OLD_D_3}} | {{OLD_STATUS_3}} | [Link]({{OLD_DL_3}}) |

---

## 🔄 Migration Guides

### Migration Guide: v{{PREV_VERSION}} to v{{LATEST_VERSION}}

**Overview:** Major improvements in {{MIGRATION_FOCUS}}.

#### What's Changing

1. **{{CHANGE_AREA_1}}**: {{CHANGE_AREA_1_DESC}}
2. **{{CHANGE_AREA_2}}**: {{CHANGE_AREA_2_DESC}}
3. **{{CHANGE_AREA_3}}**: {{CHANGE_AREA_3_DESC}}

#### Step-by-Step Migration

##### Step 1: Backup Current Data

```powershell
# Create backup
{{BACKUP_CMD}}

# Verify backup
{{VERIFY_BACKUP_CMD}}
```

##### Step 2: Update Configuration

**Old configuration (v{{PREV_VERSION}}):**

```json
{
  "{{OLD_SETTING_1}}": "{{OLD_VALUE_1}}",
  "{{OLD_SETTING_2}}": "{{OLD_VALUE_2}}"
}
```

**New configuration (v{{LATEST_VERSION}}):**

```json
{
  "{{NEW_SETTING_1}}": "{{NEW_VALUE_1}}",
  "{{NEW_SETTING_2}}": "{{NEW_VALUE_2}}"
}
```

##### Step 3: Update Dependencies

```powershell
# Update dependencies
{{UPDATE_DEPS_CMD}}

# Verify versions
{{CHECK_VERSIONS_CMD}}
```

##### Step 4: Code Changes

If you extended {{PROJECT_NAME}}, update your code:

```powershell
# Old API (v{{PREV_VERSION}})
$result = Invoke-{{OLD_FUNCTION}} -Parameter $value

# New API (v{{LATEST_VERSION}})
$result = Invoke-{{NEW_FUNCTION}} -Parameter $value -NewParameter $newValue
```

[See breaking changes](#-breaking-changes) for complete list.

##### Step 5: Run Migration Scripts

```powershell
# Run automatic migration
{{MIGRATION_SCRIPT_CMD}}

# Or manual migration
{{MANUAL_MIGRATION_CMD}}
```

##### Step 6: Verify Upgrade

```powershell
# Check version
{{VERSION_CHECK_CMD}}

# Run tests
{{TEST_CMD}}

# Verify functionality
{{FUNCTIONAL_TEST_CMD}}
```

#### Rollback Plan

If upgrade fails, rollback:

```powershell
# Stop application
{{STOP_CMD}}

# Restore backup
Restore-Backup -Path "{{BACKUP_PATH}}"

# Start application
{{START_CMD}}
```

#### Support

- **Questions:** {{MIGRATION_SUPPORT_EMAIL}}
- **Issues:** [GitHub Issues]({{MIGRATION_ISSUES_URL}})
- **Community:** [Forum]({{FORUM_URL}})

---

### Migration Guide: v{{OLDER_VERSION}} to v{{LATEST_VERSION}}

**Time Estimate:** {{MIGRATION_TIME}}

**Difficulty:** {{DIFFICULTY_LEVEL}}

See the v{{OLDER_VERSION}} → v{{INTERMEDIATE_VERSION}} guide, then v{{INTERMEDIATE_VERSION}} → v{{LATEST_VERSION}} guide.

---

## 🚫 Deprecations

### Deprecated in v{{LATEST_VERSION}}

Items deprecated in this release will be removed in {{DEPRECATION_REMOVAL_VERSION}}:

#### {{DEPRECATED_FEATURE_1}}

- **Deprecated:** v{{LATEST_VERSION}}
- **Removal:** v{{REMOVAL_VERSION_1}}
- **Reason:** {{DEPRECATION_REASON_1}}
- **Replacement:** `{{NEW_API_1}}`

**Migration example:**

```powershell
# Old (deprecated)
{{OLD_DEPRECATED_CODE_1}}

# New (replacement)
{{NEW_REPLACEMENT_CODE_1}}
```

#### {{DEPRECATED_FEATURE_2}}

- **Deprecated:** v{{LATEST_VERSION}}
- **Removal:** v{{REMOVAL_VERSION_2}}
- **Replacement:** `{{NEW_API_2}}`

---

### Deprecation Timeline

| Item | Deprecated | Removal | Replacement |
|------|-----------|---------|------------|
| {{ITEM_1}} | {{DEP_DATE_1}} | {{REM_DATE_1}} | {{REP_1}} |
| {{ITEM_2}} | {{DEP_DATE_2}} | {{REM_DATE_2}} | {{REP_2}} |
| {{ITEM_3}} | {{DEP_DATE_3}} | {{REM_DATE_3}} | {{REP_3}} |

---

## 🐛 Known Issues

### v{{LATEST_VERSION}} Known Issues

#### {{KNOWN_ISSUE_1}}

- **Description:** {{KNOWN_ISSUE_1_DESC}}
- **Severity:** {{SEVERITY_1}}
- **Affected:** {{AFFECTED_PLATFORMS_1}}
- **Status:** {{STATUS_1}}
- **Workaround:** {{WORKAROUND_1}}
- **Fix:** Expected in v{{FIX_VERSION_1}}

---

#### {{KNOWN_ISSUE_2}}

- **Description:** {{KNOWN_ISSUE_2_DESC}}
- **Workaround:** {{WORKAROUND_2}}

---

### Previous Version Issues

#### v{{PREV_VERSION}}

- {{PREV_ISSUE_1}}: {{PREV_ISSUE_1_STATUS}} (Fixed in v{{FIX_VERSION_P1}})
- {{PREV_ISSUE_2}}: {{PREV_ISSUE_2_STATUS}} (Fixed in v{{FIX_VERSION_P2}})

---

## 🔍 Version Support Status

| Version | Release Date | Status | Support Until |
|---------|-------------|--------|---|
| {{LATEST_VERSION}} | {{LATEST_DATE}} | LTS (Active) | {{SUPPORT_DATE_LATEST}} |
| {{VERSION_2}} | {{VERSION_2_DATE}} | Stable | {{SUPPORT_DATE_2}} |
| {{VERSION_3}} | {{VERSION_3_DATE}} | End of Life | {{EOL_DATE_3}} |
| {{VERSION_4}} | {{VERSION_4_DATE}} | End of Life | {{EOL_DATE_4}} |

**LTS:** Long-term support version (receive patches for {{LTS_DURATION}})  
**Stable:** Receive critical patches only  
**End of Life:** No longer supported

---

## 📊 Release Statistics

### Release Frequency

| Period | Count | Average Gap |
|--------|-------|------------|
| Last 12 months | {{RELEASES_YEAR}} | {{AVG_GAP_YEAR}} |
| Last 3 months | {{RELEASES_QUARTER}} | {{AVG_GAP_QUARTER}} |
| Last month | {{RELEASES_MONTH}} | {{AVG_GAP_MONTH}} |

### Commit Activity

```
v{{LATEST_VERSION}} ████████████ {{COMMITS_LATEST}} commits
v{{VERSION_2}} ████████ {{COMMITS_2}} commits
v{{VERSION_3}} ██████ {{COMMITS_3}} commits
```

---

## 🔗 Additional Resources

- **GitHub Releases:** {{GITHUB_RELEASES_URL}}
- **Changelog:** {{CHANGELOG_URL}}
- **Upgrade Guide:** [See above](#-migration-guides)
- **Support:** {{SUPPORT_EMAIL}}

---

## ❓ FAQ About Releases

**Q: How often are releases made?**  
A: {{RELEASE_FREQUENCY}}

**Q: How long is support provided?**  
A: {{SUPPORT_DURATION}}

**Q: Can I stay on an older version?**  
A: {{OLDER_VERSION_SUPPORT}}

**Q: What's the breaking change policy?**  
A: {{BREAKING_CHANGE_POLICY}}

---

**Last Generated:** {{GENERATION_DATE}}  
**Latest Version:** {{LATEST_VERSION}}  
**Next Release:** {{NEXT_RELEASE_DATE}} (estimated)

---

Generated from template version 1.0
