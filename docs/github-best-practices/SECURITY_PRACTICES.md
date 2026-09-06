# Security Best Practices for HELIOS Platform

Security guidelines for protecting the codebase and user data.

---

## Table of Contents

1. [Secret Management](#secret-management)
2. [Sensitive Data Handling](#sensitive-data-handling)
3. [Dependency Security](#dependency-security)
4. [Code Scanning](#code-scanning)
5. [Security Advisories](#security-advisories-response)
6. [Branch Protection](#branch-protection)
7. [Access Control](#access-control)
8. [Incident Response](#incident-response)

---

## Secret Management

### The Golden Rule

**NEVER commit secrets to the repository. Period.**

Secrets include:

- API keys and tokens
- Database passwords
- Private encryption keys
- OAuth secrets
- Personal access tokens
- AWS/cloud credentials
- Certificate private keys

### What to Do Instead

**1. Use Environment Variables**

```bash
# .env (never commit this)
DATABASE_PASSWORD=secret123
API_KEY=sk_test_abc123

# .env.template (commit this, no secrets)
DATABASE_PASSWORD=your_password_here
API_KEY=your_api_key_here
```

**2. Use GitHub Secrets**

For CI/CD:

```yaml
name: Deploy
on: [push]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Deploy
        env:
          API_KEY: ${{ secrets.API_KEY }}
          DB_PASSWORD: ${{ secrets.DB_PASSWORD }}
        run: npm run deploy
```

**3. Use Secrets Management Tools**

Production environments:

- AWS Secrets Manager
- HashiCorp Vault
- Azure Key Vault
- Google Cloud Secret Manager

```bash
# Runtime: Load from secrets manager
const apiKey = await secretsManager.getSecret('api_key');
```

### Detecting Exposed Secrets

**If a secret is accidentally committed:**

1. **Immediately revoke the secret**

   ```bash
   # Don't just remove it in next commit!
   # Revoke the actual secret first
   ```

2. **Rewrite git history** (only if not shared)

   ```bash
   # Option 1: BFG Repo Cleaner (recommended)
   bfg --delete-files secrets.json
   
   # Option 2: git filter-branch
   git filter-branch --tree-filter 'rm -f secrets.json' HEAD
   ```

3. **Force push (only if appropriate)**

   ```bash
   git push origin --force-with-lease
   ```

4. **Notify team**

   ```
   Incident: Secret exposed in commit abc123
   - Revoked API key immediately
   - Removed from history
   - New key created and deployed
   ```

### .gitignore for Secrets

```bash
# Environment files
.env
.env.local
.env.*.local
.env.prod

# Keys and certificates
*.key
*.pem
*.pfx
*.p12
privatekey.txt

# Secrets directories
/secrets/
/private/
/.aws/
/.gcloud/

# Configuration files with secrets
config/secrets.json
credentials.json
credentials.yml

# IDE secrets
.vscode/settings.json
.idea/runConfigurations/
.idea/workspace.xml
```

---

## Sensitive Data Handling

### Data Classification

**Public Data**

- Non-sensitive information
- Can be in source code
- Examples: product names, documentation

**Internal Data**

- Not for external use but not sensitive
- Can be in development branches
- Examples: internal tool names, non-critical IPs

**Confidential Data**

- Requires protection
- Never in source code
- Examples: API keys, passwords, user data

**Restricted Data**

- Highly sensitive, subject to regulations
- PII (Personally Identifiable Information)
- Financial data, health information
- Examples: social security numbers, payment methods

### Handling Sensitive Data in Code

**❌ Don't:**

```typescript
// Don't log sensitive data
console.log(`User password: ${password}`);

// Don't pass in URLs
const url = `https://api.example.com?apiKey=secret123`;

// Don't show in error messages
throw new Error(`Database error: ${connectionString}`);

// Don't include in comments
// ADMIN PASSWORD: admin123
```

**✓ Do:**

```typescript
// Log only identifiers
console.log(`Authenticating user: ${userId}`);

// Use environment variables
const url = `https://api.example.com`;
const apiKey = process.env.API_KEY;

// Sanitize error messages
throw new Error(`Database connection failed`);

// Document security considerations
// This function handles sensitive authentication data.
// Never log parameters.
function authenticateUser(username, password) {
  // ...
}
```

### Encryption

```typescript
// Passwords: Use bcrypt, not raw hashing
import bcrypt from 'bcrypt';

const hashedPassword = await bcrypt.hash(password, 10);
const isValid = await bcrypt.compare(password, hashedPassword);

// Data in transit: Always use HTTPS
// No unencrypted HTTP in production

// Data at rest: Encrypt sensitive data
import crypto from 'crypto';

const cipher = crypto.createCipher('aes-256-cbc', encryptionKey);
let encrypted = cipher.update(sensitiveData, 'utf8', 'hex');
encrypted += cipher.final('hex');

// Decrypt
const decipher = crypto.createDecipher('aes-256-cbc', encryptionKey);
let decrypted = decipher.update(encrypted, 'hex', 'utf8');
decrypted += decipher.final('utf8');
```

### GDPR and Privacy

```typescript
// Collect minimal data
function registerUser(email: string, password: string) {
  // Only collect what's needed
  // Not: age, phone, address, etc.
}

// Allow data deletion
async function deleteUserData(userId: string) {
  // Delete all user data
  // Must happen within 30 days of request
}

// Allow data export
async function exportUserData(userId: string) {
  // Export user's data in portable format
}
```

---

## Dependency Security

### Checking Dependencies

```bash
# Check for known vulnerabilities
npm audit

# Fix automatically (where possible)
npm audit fix

# Fix specific package
npm audit fix --package-name=express

# Review before fixing
npm audit fix --audit-level=high --dry-run
```

### Automated Dependency Updates

Configure Dependabot in `.github/dependabot.yml`:

```yaml
version: 2
updates:
  # Daily version updates
  - package-ecosystem: npm
    directory: "/"
    schedule:
      interval: daily
      time: "03:00"
    open-pull-requests-limit: 5
    # Auto-merge minor updates
    auto-merge:
      type: all
      # Only for dev dependencies
      target-branch: develop
```

### Dependency Audit Checklist

Before updating dependencies:

```markdown
□ Check for security advisories: npm audit
□ Review changelog for breaking changes
□ Run tests: npm test
□ Check compatibility with other packages
□ Review security updates (CVEs)
□ Test on staging first
□ Plan rollback if needed
```

### Dangerous Packages

```markdown
⚠️ Be cautious with packages that:
- Have security vulnerabilities
- Are no longer maintained
- Have known bad practices
- Request excessive permissions
- Have large or suspicious code

Check before installing:
- npm-stat.com (popularity)
- snyk.io (vulnerabilities)
- github.com (source code)
- repositories/weekly-downloads (usage)
```

---

## Code Scanning

### Enable GitHub CodeQL

In GitHub repository settings:

```markdown
Security & Analysis
├─ Code scanning
│  ├─ Enable CodeQL (default)
│  └─ Weekly analysis
├─ Secret scanning
│  ├─ Enable scanning
│  └─ Enable push protection
└─ Dependency alerts
   ├─ Enable alerts
   └─ Enable automated fixes
```

### .github/workflows/codeql.yml

```yaml
name: CodeQL
on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ develop ]
  schedule:
    - cron: '0 0 * * 0'

jobs:
  analyze:
    name: Analyze
    runs-on: ubuntu-latest
    strategy:
      matrix:
        language: [ 'javascript' ]
    steps:
    - name: Checkout repository
      uses: actions/checkout@v3
    
    - name: Initialize CodeQL
      uses: github/codeql-action/init@v2
      with:
        languages: ${{ matrix.language }}
    
    - name: Build
      run: npm run build
    
    - name: Perform CodeQL Analysis
      uses: github/codeql-action/analyze@v2
```

### Response to Code Scan Issues

```markdown
For each issue found:
1. Review the issue detail
2. Understand the vulnerability
3. Implement fix
4. Test thoroughly
5. Create PR with fix
6. Link to original alert
7. Close alert after merge
```

---

## Security Advisories Response

### GitHub Security Advisories

When GitHub reports security issue:

```markdown
1. Read advisory details
2. Assess impact on your project
3. Check if you're affected
4. Plan upgrade timeline

Critical: Fix within 24 hours
High: Fix within 1 week
Medium: Fix within 2 weeks
Low: Fix within sprint
```

### Responsible Disclosure

If you find a vulnerability:

```markdown
1. DO NOT publicly disclose
2. Email security@yourcompany.com
3. Include:
   - Vulnerability description
   - Affected versions
   - Impact assessment
   - Suggested fix
4. Give time for patch before disclosure
```

---

## Branch Protection

### Security-Focused Protection Rules

```markdown
For main branch:
✓ Require pull request reviews (2 required)
✓ Require status checks (all must pass):
  - CI/CD tests
  - Code coverage
  - CodeQL scanning
  - Lint checks
  - Security scanning
✓ Require branches up-to-date
✓ Include administrators
✓ Require conversation resolution
✓ Require code owner review (for critical files)
✓ Dismiss stale reviews when new commits
✓ Allow auto-merge (squash only)

For develop branch:
✓ Require pull request reviews (1 required)
✓ Require status checks
✓ Require conversation resolution
```

### CODEOWNERS for Security

Create `.github/CODEOWNERS`:

```
# Security-sensitive paths
/src/auth/          @security-team
/src/payment/       @security-team @finance-team
/.github/secrets*   @security-team
/docker/           @devops-team
/config/prod*      @devops-team

# Database
/migrations/       @core-team
/database/        @core-team

# Default
*                 @core-team
```

---

## Access Control

### Repository Roles

| Role | Permissions | Use For |
|------|-------------|---------|
| Owner | Full access | Repository admin |
| Maintain | Merge PRs | Trusted maintainers |
| Write | Push branches | Core developers |
| Triage | Manage issues | Issue managers |
| Read | Clone only | External contributors |

### Team Structure

```markdown
@platform-team (Maintainers)
├─ Can merge PRs
├─ Can manage releases
└─ Can configure CI/CD

@core-team (Developers)
├─ Can create PRs
├─ Can push to develop
└─ Cannot push to main directly

@security-team (Security)
├─ Reviews security PRs
├─ Can approve hot-fixes
└─ Receives security alerts

@devops-team (DevOps)
├─ Manages deployment
├─ Configures CI/CD
└─ Manages secrets
```

### Principle of Least Privilege

```markdown
✓ Give users only permissions they need
✓ Remove permissions when role changes
✓ Regularly audit who has access
✓ Require 2-factor authentication
✓ Use service accounts with limited scope
✗ Don't give admin access by default
✗ Don't keep access after role change
✗ Don't share personal access tokens
```

---

## Incident Response

### Security Incident Checklist

**Upon discovering security issue:**

```markdown
□ Assess severity (Critical/High/Medium/Low)
□ Determine affected components
□ Identify data exposure
□ Contain the issue (if needed, take offline)
□ Create incident ticket (private)
□ Notify security team immediately
□ Document timeline

Critical issues:
□ Immediate notification to CEO/CTO
□ Prepare customer communication
□ Begin mitigation
□ Document everything
```

### Vulnerability Disclosure

```markdown
Timeline:
- Day 0: Vulnerability discovered
- Day 1: Security team confirms
- Day 7: Patch available
- Day 14: Public disclosure (if appropriate)

Before disclosure:
□ Notify affected customers
□ Provide fix/workaround
□ Allow time for patching
□ Coordinate with security researchers
```

### Post-Incident Review

```markdown
After security incident:

1. Complete RCA (Root Cause Analysis)
   - What went wrong?
   - Why did it happen?
   - How was it caught?

2. Document findings
   - Timeline
   - Impact
   - Response actions
   - Customer communication

3. Implement preventive measures
   - Code changes
   - Policy changes
   - Monitoring additions
   - Training needs

4. Share learnings
   - Team meeting
   - Documentation update
   - Process improvements
```

---

## Security Audit Checklist

Regular security audit (monthly):

```markdown
Authentication & Authorization:
□ All endpoints require auth
□ Authorization checks in place
□ Passwords properly hashed
□ Tokens have expiration
□ MFA enabled for sensitive operations

Data Protection:
□ Sensitive data encrypted
□ No secrets in code
□ Backups encrypted
□ Access logs maintained
□ Data retention policies followed

Infrastructure:
□ HTTPS enforced
□ Firewall rules reviewed
□ Network segmentation
□ VPN required for admin access
□ Security groups properly configured

Dependency Management:
□ No high-risk dependencies
□ Regular update schedule
□ Audit results reviewed
□ Automated vulnerability scanning

Code Security:
□ CodeQL scanning enabled
□ SAST tools running
□ Regular code reviews
□ Security-focused testing
□ No hardcoded secrets

Monitoring & Alerting:
□ Security alerts configured
□ Log aggregation enabled
□ Anomaly detection active
□ On-call security support
□ Incident playbooks ready
```

---

## Security Resources

**Internal:**

- Security team: @security-team on Slack
- Security wiki: [Internal Link]
- Incident playbook: [Internal Link]

**External:**

- OWASP Top 10: https://owasp.org/Top10/
- CWE List: https://cwe.mitre.org/
- CVE Database: https://cve.mitre.org/
- NIST Guidelines: https://www.nist.gov/

---

**Last Updated:** April 2026  
**Version:** 1.0

See also: [GITHUB_BEST_PRACTICES.md](GITHUB_BEST_PRACTICES.md), [PULL_REQUEST_GUIDE.md](PULL_REQUEST_GUIDE.md)
