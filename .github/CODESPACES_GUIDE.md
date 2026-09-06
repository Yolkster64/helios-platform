# GitHub Codespaces Quick Start

## 🚀 Launch Codespaces

### Option 1: Via Web

1. Go to: https://github.com/M0nado/helios-platform
2. Click **Code** (green button)
3. Click **Codespaces** tab
4. Click **Create codespace on main**
5. Wait ~2 minutes for environment to build

### Option 2: Via GitHub CLI

```bash
gh codespace create --repo M0nado/helios-platform
gh codespace code --repo M0nado/helios-platform
```

### Option 3: Via VS Code

1. Install Remote - Codespaces extension
2. Open Command Palette (Ctrl+Shift+P)
3. Type: **Codespaces: Create New Codespace**
4. Select repository and branch

## 💻 What's Included

When Codespaces starts, you get:

- ✅ Ubuntu 22.04 environment
- ✅ PowerShell 7.x pre-installed
- ✅ GitHub CLI authenticated
- ✅ Docker-in-Docker ready
- ✅ Git configured
- ✅ VS Code with extensions:
  - PowerShell extension
  - GitHub Copilot
  - Docker extension
  - Azure Account extension
  - YAML language support

## 🎯 First Steps in Codespaces

### 1. Terminal is Ready

```bash
# You're already in the repo root
pwd  # Shows: /workspaces/helios-platform
ls   # Lists all top-level files and folders
```

### 2. Read Documentation

```bash
# View README
cat README.md

# View kickoff guide
cat 00-KICKOFF-START-HERE.md

# List all phases
ls -la phases/
```

### 3. Run Your First Script

```powershell
# Switch to PowerShell
pwsh

# Navigate to a phase
cd phases/0-foundation

# See what's available
ls -la

# Read the phase guide
cat README.md
cat PLAIN_ENGLISH_GUIDE.md

# Run a build script (if available)
./build.ps1
```

### 4. Make Changes & Commit

```bash
# Create a new branch
git checkout -b feature/my-feature

# Make edits in VS Code (Ctrl+K Ctrl+O to open files)
# Example: Edit a documentation file

# See your changes
git status

# Stage changes
git add .

# Commit
git commit -m "Add new documentation for feature X"

# Push (creates PR)
git push -u origin feature/my-feature
```

### 5. Submit Pull Request

After pushing, GitHub will show a notification to create a PR:

1. Click **Create Pull Request**
2. Add title and description
3. Click **Create Pull Request**
4. GitHub Actions will automatically:
   - Run syntax validation
   - Run tests
   - Check documentation
   - Scan for security issues

## 📊 Available Commands in Codespaces

```bash
# View environment variables
env | grep HELIOS

# Check available disk space
df -h

# List installed PowerShell modules
pwsh -c "Get-Module -ListAvailable"

# Check Git status
git status

# View recent commits
git log --oneline -5

# Install additional packages (if needed)
sudo apt update && sudo apt install <package>
```

## 🔧 Configure Your Codespace

### VS Code Settings

1. Press **Ctrl+Comma** to open Settings
2. Search for "PowerShell" to configure shell
3. Search for "Copilot" to configure AI

### Terminal Preferences

```bash
# Set default shell to PowerShell
echo 'set-option -g default-shell /usr/bin/pwsh' >> ~/.bashrc

# Or edit .bashrc
nano ~/.bashrc
```

### Editor Configuration

- **Format on Save**: Enabled (auto-formats on Ctrl+S)
- **Theme**: GitHub Dark (default)
- **Font Size**: 13 (adjustable)
- **Word Wrap**: Enabled

## 🌐 Forwarded Ports

Codespaces forwards these ports automatically:

- **8080**: Application server
- **8443**: Secure server (HTTPS)

To access:

1. In VS Code, go to **Ports** tab
2. Right-click port 8080
3. Click **Open in Browser**

## 💾 File Storage

- **Repository files**: `/workspaces/helios-platform/` (unlimited)
- **Temporary files**: `/tmp/` (limited, auto-cleaned)
- **Home directory**: `~/.` (for persistent config)

## ⏱️ Codespace Lifecycle

- **Idle timeout**: 30 minutes (auto-suspend if inactive)
- **Max storage**: 32GB per codespace
- **Max running time**: Depends on GitHub plan
- **Auto-delete**: After 30 days without use

### Resume Suspended Codespace

1. Go to: https://github.com/codespaces
2. Click the suspended codespace
3. Click **Resume**
4. Wait ~30 seconds to resume

### Delete Codespace

```bash
gh codespace delete --repo M0nado/helios-platform
```

## 🐛 Troubleshooting

### "Extensions are not loading"

- Wait 2-3 minutes for full initialization
- Reload window: Ctrl+Shift+P → "Reload Window"

### "PowerShell not found"

```bash
# Check if installed
which pwsh

# If not, install
sudo apt-get install -y powershell
```

### "Git push rejected"

- Check you have permissions on repo
- Use GitHub CLI: `gh auth login`

### "Out of disk space"

- Delete temp files: `rm -rf /tmp/*`
- Prune Docker: `docker system prune`

## 🚀 Tips & Tricks

### 1. Use GitHub Copilot for Code

```powershell
# Start typing and Copilot will suggest
# Press Tab to accept suggestion
# Press Escape to dismiss

# Example: Start typing a function
function New-SecurityPolicy {
    # Copilot suggests complete implementation
}
```

### 2. Quick File Preview

- Click any markdown file in Explorer
- Press Ctrl+Shift+V to preview formatted

### 3. Terminal Tips

```bash
# Clear screen
clear

# Search previous commands
Ctrl+R  # (in bash)

# Kill a process
Ctrl+C

# Detach (keep running): nohup command &
```

### 4. Create Bookmarks

```bash
# Create a bookmark to jump back to repo
cd /workspaces/helios-platform
pwd > ~/.bookmarks/helios
```

## 📞 Getting Help in Codespaces

### Built-in Help

- **VS Code Help**: F1 or Ctrl+Shift+P
- **GitHub Help**: `gh help`
- **PowerShell Help**: `Get-Help -Full`

### Documentation

- All `.md` files in repo are readable
- Preview markdown: Right-click → "Open Preview"
- GitHub Flavored Markdown supported

### Contacting Team

- Create GitHub Issue
- Use GitHub Discussions
- Email via GitHub

## ✅ Checklist Before Starting Work

- [ ] Environment fully loaded (2-3 min wait)
- [ ] Terminal responsive
- [ ] Git shows correct branch
- [ ] PowerShell working (type `pwsh` to test)
- [ ] VS Code extensions loaded
- [ ] Can view markdown files
- [ ] Disk space available (`df -h`)

## 🎊 You're Ready!

Everything is configured. Your Codespace is:

- ✅ Fully isolated (no impact on local machine)
- ✅ Pre-configured with all tools
- ✅ Ready for development
- ✅ Auto-saved in cloud
- ✅ Can be accessed from anywhere

Start editing, commit, and push to GitHub!

---

## Quick Reference

| Task | Command |
|------|---------|
| List files | `ls -la` |
| View file | `cat filename` |
| Edit file | Click in Explorer, then edit |
| Search files | Ctrl+Shift+F |
| Find file | Ctrl+P |
| New terminal | Ctrl+Backtick |
| Git commit | `git add . && git commit -m "message"` |
| Git push | `git push` |
| Create PR | `gh pr create` |
| Check status | `git status` |
| View diffs | `git diff` |

---

**Ready to code? Start now! 🚀**
