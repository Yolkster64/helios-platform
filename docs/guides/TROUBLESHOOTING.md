# Troubleshooting Guide - HELIOS Platform v2

## 🆘 Overview

This guide covers common issues and their solutions for the HELIOS Platform v2. Check here first before creating a GitHub issue.

---

## 📋 Common Issues by Category

---

## 🔧 General Setup Issues

### Issue: "I can't access the GitHub Project board"

**Symptoms:**

- 404 error or "Not Found" when accessing https://github.com/orgs/M0nado/projects/3
- Page says "You don't have access to this project"

**Solutions:**

1. **Verify You're Logged In**
   - Check GitHub profile icon in top right
   - If not logged in, click and sign in

2. **Check Organization Membership**
   - Go to https://github.com/orgs/M0nado/people
   - Look for your GitHub username
   - If not there, ask admin to add you

3. **Verify Project Access**
   - Go to project: https://github.com/orgs/M0nado/projects/3
   - Project admin should grant "Edit" access
   - Wait 5-10 minutes for changes to take effect

4. **Clear Browser Cache**
   - Press Ctrl+Shift+Delete
   - Clear browsing data for "All time"
   - Try again

**Still not working?**
→ Contact your GitHub organization admin

---

### Issue: "Repository not found" when cloning

**Symptoms:**

```
fatal: repository 'https://github.com/M0nado/helios-platform.git' not found
```

**Solutions:**

1. **Verify Repository URL**
   - Should be: `https://github.com/M0nado/helios-platform.git`
   - Check spelling (case-sensitive)

2. **Check GitHub Access**
   - Go to https://github.com/M0nado/helios-platform
   - If you see "404 Not Found", you don't have access
   - Ask admin to grant access

3. **Authenticate with Git**

   ```bash
   git config --global user.email "your-email@example.com"
   git config --global user.name "Your Name"
   ```

4. **Generate GitHub Token (if needed)**
   - Go to GitHub → Settings → Developer settings → Personal access tokens
   - Click "Generate new token"
   - Select "repo" scope
   - Save token securely

5. **Use Token for HTTPS**

   ```bash
   git clone https://[TOKEN]@github.com/M0nado/helios-platform.git
   ```

**Still not working?**
→ See [DEVELOPMENT.md](DEVELOPMENT.md) for detailed setup instructions

---

## ☁️ GitHub Codespaces Troubleshooting

### Issue: "Codespace creation times out"

**Symptoms:**

- Codespace spinner runs for >5 minutes
- Eventually shows error "Creation timed out"
- Can't access development environment

**Solutions:**

1. **Try Again**
   - Codespaces sometimes need retry
   - Close browser tab
   - Go to https://github.com/codespaces
   - Click "New codespace"
   - Wait 2-3 minutes

2. **Check Quota**
   - Go to https://github.com/settings/codespaces
   - Check "Codespace creation" quota
   - If exceeded, wait for reset (monthly)
   - Or delete old codespaces

3. **Try Different Branch**
   - Create codespace on `develop` branch instead
   - Sometimes `main` has build issues
   - Switch to `main` after creation

4. **Clear Cache**
   - Delete existing codespaces
   - Go to https://github.com/codespaces
   - For each codespace, click ⋮ → Delete
   - Try creating fresh codespace

5. **Check Status Page**
   - Go to https://www.githubstatus.com/
   - Check if Codespaces is degraded
   - Wait for service to recover

**Still not working?**
→ Switch to local development using [DEVELOPMENT.md](DEVELOPMENT.md)

---

### Issue: "VS Code can't find dependencies in Codespace"

**Symptoms:**

- Red squiggly lines under imports
- "Cannot find module" errors
- But `npm run build` works

**Solutions:**

1. **Reinstall Packages**

   ```bash
   npm ci    # Clean install
   npm run build
   npm run test
   ```

2. **Reload VS Code**
   - Press F1 (or Cmd+Shift+P)
   - Type "Developer: Reload Window"
   - Press Enter
   - Wait for reload

3. **Check Node Version**

   ```bash
   node --version    # Should be 18 or 20
   npm --version     # Should be 8+
   ```

4. **Install TypeScript Types** (if applicable)

   ```bash
   npm install --save-dev @types/node
   npm run build:types
   ```

5. **Restart Terminal**
   - Close terminal in VS Code
   - Click + icon to open new terminal
   - Run `npm run build` again

**Still not working?**
→ See "Dependency resolution failed" below

---

### Issue: "Codespace closed unexpectedly"

**Symptoms:**

- Codespace stops running
- Browser shows "Codespace stopped"
- Can reconnect but work is lost

**Solutions:**

1. **Check Inactivity Timeout**
   - Codespaces auto-stop after 30 minutes idle
   - This is normal behavior
   - Click "Reconnect" to resume

2. **Check Codespace Quota**
   - Go to https://github.com/settings/codespaces
   - Look for "Free included usage"
   - May have monthly limit
   - Usage resets monthly

3. **Save Work Frequently**
   - Use Ctrl+S to save files
   - Use `git push` to push commits
   - Codespaces may close unexpectedly

4. **Increase Timeout** (if owner)
   - Go to Codespace settings
   - Search "idle"
   - Set timeout to maximum

**Prevention:**
→ Regularly push commits to GitHub: `git push origin [branch-name]`

---

## 🔨 GitHub Actions Troubleshooting

### Issue: "Workflow failed" status on PR

**Symptoms:**

- Red X next to PR status checks
- GitHub Actions workflow failed
- Can't merge PR

**Solutions:**

1. **Check Workflow Logs**
   - Go to PR → Click "Details" next to failed check
   - Read error message in workflow logs
   - Look for specific error

2. **Common Causes**
   - **Linting failed**: Fix code style with `npm run lint:fix`
   - **Tests failed**: Run tests locally with `npm run test`
   - **Build failed**: Check build logs for errors
   - **Permissions**: Check if you have push access

3. **Fix Locally and Push**

   ```bash
   npm run lint:fix      # Fix style issues
   npm run test          # Check tests pass
   npm run build         # Verify build works
   git add .
   git commit -m "fix: resolve CI issues"
   git push
   ```

4. **Re-run Workflow**
   - Go to PR
   - Click "Actions" tab
   - Find failed workflow
   - Click ⋮ → "Re-run failed jobs"
   - Wait for completion

5. **Check Branch Protection**
   - Some repos require checks to pass
   - Merge when all checks are green ✅

**Still not working?**
→ Check workflow YAML in `.github/workflows/` directory

---

### Issue: "Workflow doesn't trigger on push"

**Symptoms:**

- You push code but no GitHub Actions appear
- "Actions" tab is empty
- Workflow should run but doesn't

**Solutions:**

1. **Verify Workflow File Exists**
   - Go to `.github/workflows/` directory
   - Look for `*.yml` or `*.yaml` files
   - Common files:
     - `build-all-modules.yml`
     - `multi-repo-sync.yml`
     - `component-version-check.yml`

2. **Check Trigger Conditions**
   - Open workflow YAML file
   - Look for `on:` section
   - Verify your branch matches filter
   - Example: `branches: [main, develop]`

3. **Verify Actions Are Enabled**
   - Go to repository Settings → Actions
   - Check "Allow all actions and reusable workflows"
   - Or select specific workflows to allow

4. **Check Commit Message**
   - Some workflows skip on certain commit messages
   - Try conventional commit: `git commit -m "feat: add feature"`

5. **Push to Main Branch**
   - Workflows often only trigger on `main` or `develop`
   - Create PR from feature branch to trigger
   - Or push directly to trigger branch

**Still not working?**
→ Check "Actions" tab for disabled workflows or errors

---

## 🔨 Build and Compilation Issues

### Issue: "Build fails with 'module not found'"

**Symptoms:**

```
Error: Cannot find module 'xyz'
npm ERR! code ENOENT
```

**Solutions:**

1. **Install Dependencies**

   ```bash
   npm install              # Install all dependencies
   npm ci                   # Clean install
   ```

2. **Verify Syntax of package.json**

   ```bash
   cat package.json         # Check for JSON syntax errors
   npm ls                   # List all dependencies
   ```

3. **Clear npm Cache**

   ```bash
   npm cache clean --force
   npm install
   ```

4. **Check Node Version**

   ```bash
   node --version           # Should match .nvmrc or package.json
   npm --version
   ```

5. **Reinstall Specific Package**

   ```bash
   npm install [package-name]
   npm run build            # Try build again
   ```

6. **Check for Submodule Issues**

   ```bash
   git submodule update --init --recursive
   npm install
   ```

**Still not working?**
→ Try clean build: `rm -rf node_modules && npm install`

---

### Issue: "TypeScript compilation errors"

**Symptoms:**

```
error TS2339: Property 'xyz' does not exist
error TS2307: Cannot find module
```

**Solutions:**

1. **Check TypeScript Version**

   ```bash
   npx tsc --version        # Should be 4.5+
   ```

2. **Generate Type Definitions**

   ```bash
   npm run build:types      # If available
   npm run build            # TypeScript compilation
   ```

3. **Fix tsconfig.json**
   - Check `tsconfig.json` in project root
   - Verify `compilerOptions.lib` includes needed types
   - Verify `compilerOptions.target` matches Node version

4. **Install @types Packages**

   ```bash
   npm install --save-dev @types/node
   npm install --save-dev @types/jest
   ```

5. **Clear Build Cache**

   ```bash
   rm -rf dist/ build/ .tsbuildinfo
   npm run build
   ```

**Still not working?**
→ Consult TypeScript handbook: https://www.typescriptlang.org/

---

## 🧪 Testing Issues

### Issue: "Jest tests fail with 'Cannot find module'"

**Symptoms:**

```
FAIL src/test.spec.ts
Cannot find module '../src/file'
```

**Solutions:**

1. **Check Jest Config**
   - Look for `jest.config.js` or `jest.config.json`
   - Verify `moduleNameMapper` for path aliases
   - Verify `testEnvironment` is correct

2. **Install Test Dependencies**

   ```bash
   npm install --save-dev jest @types/jest ts-jest
   npm run test
   ```

3. **Run with Verbose Output**

   ```bash
   npm run test -- --verbose
   npm run test -- --no-coverage  # Skip coverage
   ```

4. **Clear Jest Cache**

   ```bash
   npm run test -- --clearCache
   ```

5. **Check Test File Names**
   - Should end with `.spec.ts` or `.test.ts`
   - Verify they exist in correct directory
   - Run single test: `npm run test -- src/test.spec.ts`

**Still not working?**
→ Check `jest.config.js` configuration

---

### Issue: "Coverage reports missing"

**Symptoms:**

- `npm run test` runs but no coverage report
- No `coverage/` directory created
- Can't see coverage stats

**Solutions:**

1. **Enable Coverage**

   ```bash
   npm run test -- --coverage
   ```

2. **Check Jest Config**
   - Verify `collectCoverage: true` in `jest.config.js`
   - Verify coverage thresholds are reasonable

3. **Generate HTML Report**

   ```bash
   npm run test -- --coverage
   # Open coverage/index.html in browser
   ```

**Still not working?**
→ Manual coverage check: `npm run test -- --coverage`

---

## 🌐 Network and Connectivity Issues

### Issue: "Cannot reach GitHub"

**Symptoms:**

- `git push` hangs or times out
- "Connection refused" error
- Can't clone or fetch

**Solutions:**

1. **Check Internet Connection**

   ```bash
   ping 8.8.8.8           # Check internet
   ping github.com        # Check GitHub reachability
   ```

2. **Check SSH Keys** (if using SSH)

   ```bash
   ssh -T git@github.com  # Should show success message
   ```

3. **Use HTTPS Instead of SSH**

   ```bash
   git config --global url."https://".insteadOf git://
   git clone https://github.com/M0nado/helios-platform.git
   ```

4. **Check Firewall**
   - Firewall may block GitHub
   - Try from different network (mobile hotspot)
   - Contact IT if blocked by corporate firewall

5. **Check GitHub Status**
   - Go to https://www.githubstatus.com/
   - Look for incidents
   - Wait if service is degraded

**Still not working?**
→ Contact IT or network administrator

---

### Issue: "Slow git operations"

**Symptoms:**

- `git push` takes >30 seconds
- `git fetch` is very slow
- Network seems fine

**Solutions:**

1. **Compress Objects**

   ```bash
   git gc --aggressive
   ```

2. **Enable Compression**

   ```bash
   git config --global core.compression 9
   ```

3. **Check SSH Tunnel**

   ```bash
   ssh -T git@github.com
   # If using SSH, may be slower than HTTPS
   # Switch to HTTPS if slow
   ```

4. **Increase Buffer Size**

   ```bash
   git config --global http.postBuffer 524288000
   ```

5. **Check Network Conditions**
   - Run `speedtest.net` to check connection
   - May be legitimate network slowness
   - Try during off-peak hours

---

## 📝 Documentation Issues

### Issue: "Documentation link is broken"

**Symptoms:**

- Link in documentation points to non-existent file
- 404 error when clicking link
- File is referenced but can't find it

**Solutions:**

1. **Verify File Exists**

   ```bash
   ls -la [filename]      # Check if file exists
   ```

2. **Check Link Format**
   - Should use relative paths: `[text](../file.md)`
   - Not absolute paths: `[text](/C:/path/file.md)`
   - Files should be in repository

3. **Update Broken Links**
   - Find correct file location
   - Update link in documentation
   - Test link works

4. **Check File Name Case**
   - GitHub is case-sensitive
   - `README.md` ≠ `readme.md`
   - Verify exact spelling

**Still not working?**
→ Create GitHub issue with broken link

---

### Issue: "Documentation is outdated"

**Symptoms:**

- Documentation says to do X but X doesn't exist
- Screenshots are from old version
- Instructions don't work

**Solutions:**

1. **Check Last Update Date**
   - Look at "Last Updated" section
   - Documentation may be from different version

2. **Check GitHub History**
   - Click "History" button on GitHub
   - See when file was last updated
   - Check commits to see changes

3. **Create GitHub Issue**
   - Title: "Docs: [Section] outdated"
   - Description: What's wrong and what should be correct
   - Label: "documentation"

4. **Contribute Fix** (if you know correct info)
   - Edit file on GitHub (or locally)
   - Submit pull request with fix
   - Add "documentation" label

---

## 🆘 Still Having Issues?

### Before Creating Issue

1. **Check This Guide** - You may have found the answer
2. **Search GitHub Issues** - https://github.com/M0nado/helios-platform/issues
3. **Check Status Page** - https://www.githubstatus.com/
4. **Review Logs** - GitHub Actions logs often have clues

### Creating a Good GitHub Issue

**Title:**

```
[Category]: Brief description (e.g., "Build: npm install fails")
```

**Description:**

```markdown
## Description
[What are you trying to do?]

## Error Message
[Exact error, with code block]

## Steps to Reproduce
1. [Step 1]
2. [Step 2]
3. [Step 3]

## Expected Behavior
[What should happen?]

## Actual Behavior
[What actually happened?]

## Environment
- OS: [Windows/macOS/Linux]
- Node: [version]
- npm: [version]
- Browser: [if applicable]

## Attempts
- [What you've already tried]
```

### Getting Help

**Quick Questions:**

- Post in GitHub Discussions (if available)
- Comment on existing related issues
- Tag with @team-lead or @maintainer

**Urgent Issues:**

- Create GitHub issue with "urgent" label
- Post in team Slack/Teams channel
- Mention in standup meeting

**Documentation Questions:**

- Check [INDEX.md](INDEX.md) for guide list
- Look for specific guide in MASTER_DOCS/
- Create issue if documentation is unclear

---

## 📚 Related Documentation

- **Setup Issues**: See [DEVELOPMENT.md](DEVELOPMENT.md)
- **GitHub Issues**: See [GITHUB_INFRASTRUCTURE.md](GITHUB_INFRASTRUCTURE.md)
- **Codespaces**: See [CODESPACES_READINESS.md](CODESPACES_READINESS.md)
- **General Help**: See [QUICK_START.md](QUICK_START.md)

---

**Last Updated**: April 2026  
**Status**: ✅ Troubleshooting Guide Complete  
**Found an issue not listed?** Create a GitHub issue or update this guide
