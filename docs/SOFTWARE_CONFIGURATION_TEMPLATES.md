# Software Installation Configuration Templates

## Developer Workstation Setup

### config-developer.yaml

```yaml
packages:
  # Version Control
  - name: "Git"
    method: "winget"
  
  - name: "GitHub Desktop"
    method: "winget"
  
  - name: "TortoiseGit"
    method: "chocolatey"
  
  # Code Editors
  - name: "Visual Studio Code"
    method: "winget"
    config:
      extensions:
        - "ms-dotnettools.csharp"
        - "ms-vscode-remote.remote-wsl"
        - "ms-python.python"
        - "ms-vscode.powershell"
        - "eamodio.gitlens"
        - "ms-azuretools.vscode-docker"
  
  - name: "Visual Studio 2022"
    method: "official"
    config:
      workloads:
        - ".NET desktop development"
        - "Web & cloud"
        - "Desktop & mobile"
  
  # Runtime & SDK
  - name: "Python"
    version: "3.11"
    method: "official"
    config:
      add_to_path: true
      install_dev_tools: true
  
  - name: "Node.js LTS"
    method: "winget"
  
  - name: ".NET SDK"
    method: "official"
  
  - name: "Java JDK"
    method: "winget"
  
  # Build Tools
  - name: "Git Bash"
    method: "chocolatey"
  
  - name: "CMake"
    method: "winget"
  
  - name: "Maven"
    method: "chocolatey"
  
  - name: "Gradle"
    method: "winget"
  
  # Virtualization & Containers
  - name: "Docker Desktop"
    method: "official"
    config:
      enable_wsl2: true
  
  - name: "VirtualBox"
    method: "chocolatey"
  
  - name: "WSL2"
    method: "official"
  
  # Development Tools
  - name: "Postman"
    method: "winget"
  
  - name: "Insomnia"
    method: "winget"
  
  - name: "IntelliJ IDEA"
    method: "official"

  # Utilities
  - name: "NotePad++"
    method: "winget"
  
  - name: "WinSCP"
    method: "winget"
  
  - name: "PuTTY"
    method: "chocolatey"
  
  - name: "7-Zip"
    method: "winget"
```

## Creative Professional Setup

### config-creative.yaml

```yaml
packages:
  # Adobe Suite
  - name: "Adobe Photoshop"
    method: "official"
  
  - name: "Adobe Illustrator"
    method: "official"
  
  - name: "Adobe Premiere Pro"
    method: "official"
  
  - name: "Adobe Lightroom"
    method: "official"
  
  - name: "Adobe After Effects"
    method: "official"
  
  # Open Source Alternatives
  - name: "GIMP"
    method: "winget"
  
  - name: "Krita"
    method: "winget"
  
  - name: "Blender"
    method: "official"
    config:
      enable_cuda: true
  
  - name: "Inkscape"
    method: "winget"
  
  # Video & Audio
  - name: "DaVinci Resolve"
    method: "official"
  
  - name: "OBS Studio"
    method: "winget"
  
  - name: "Audacity"
    method: "winget"
  
  - name: "FL Studio"
    method: "official"
  
  - name: "Reaper"
    method: "official"
  
  # Utilities
  - name: "VLC Media Player"
    method: "winget"
  
  - name: "FFmpeg"
    method: "chocolatey"
  
  - name: "Shotcut"
    method: "winget"
```

## Gaming Setup

### config-gaming.yaml

```yaml
packages:
  # Game Platforms
  - name: "Steam"
    method: "official"
  
  - name: "Epic Games Launcher"
    method: "official"
  
  - name: "Battle.net"
    method: "official"
  
  - name: "Ubisoft Connect"
    method: "official"
  
  - name: "GOG Galaxy"
    method: "official"
  
  - name: "Xbox App"
    method: "winget"
  
  # Game Settings
  - name: "NVIDIA GeForce Experience"
    method: "official"
  
  - name: "AMD Adrenaline"
    method: "official"
  
  # Streaming & Recording
  - name: "OBS Studio"
    method: "winget"
  
  - name: "Streamlabs OBS"
    method: "official"
  
  # Communication
  - name: "Discord"
    method: "winget"
  
  - name: "Teamspeak"
    method: "official"
  
  # Utilities
  - name: "Razer Synapse"
    method: "official"
  
  - name: "Corsair iCUE"
    method: "official"
  
  - name: "Logitech G HUB"
    method: "official"
```

## System Administrator Setup

### config-sysadmin.yaml

```yaml
packages:
  # Remote Access
  - name: "TeamViewer"
    method: "winget"
  
  - name: "AnyDesk"
    method: "winget"
  
  - name: "PuTTY"
    method: "chocolatey"
  
  - name: "WinSCP"
    method: "winget"
  
  # System Utilities
  - name: "Process Explorer"
    method: "official"
  
  - name: "Process Hacker"
    method: "portable"
  
  - name: "Everything"
    method: "winget"
  
  - name: "CCleaner"
    method: "winget"
  
  - name: "WinDirStat"
    method: "portable"
  
  # Disk Management
  - name: "MiniTool Partition Wizard"
    method: "official"
  
  - name: "EaseUS Partition Master"
    method: "official"
  
  # Security & Monitoring
  - name: "Malwarebytes"
    method: "official"
  
  - name: "Bitwarden"
    method: "winget"
  
  - name: "NordVPN"
    method: "official"
  
  - name: "Windows Defender"
    method: "official"
  
  # Productivity
  - name: "Microsoft Teams"
    method: "winget"
  
  - name: "Slack"
    method: "winget"
  
  - name: "Zoom"
    method: "official"
  
  # Monitoring
  - name: "NVIDIA Control Panel"
    method: "official"
```

## Enterprise Development Setup

### config-enterprise.yaml

```yaml
packages:
  # Version Control
  - name: "Git"
    method: "winget"
  
  - name: "SourceTree"
    method: "official"
  
  # IDEs & Editors
  - name: "Visual Studio 2022"
    method: "official"
    config:
      workloads:
        - ".NET desktop development"
        - "Web & cloud"
        - "Office/SharePoint development"
  
  - name: "Visual Studio Code"
    method: "winget"
  
  - name: "IntelliJ IDEA"
    method: "official"
    config:
      license: "enterprise"
  
  # Runtime
  - name: ".NET SDK"
    method: "official"
  
  - name: "Python"
    method: "official"
  
  - name: "Node.js LTS"
    method: "winget"
  
  - name: "Java JDK"
    method: "winget"
  
  # Databases
  - name: "SQL Server Management Studio"
    method: "official"
  
  - name: "MySQL Workbench"
    method: "official"
  
  - name: "MongoDB Compass"
    method: "official"
  
  # DevOps Tools
  - name: "Docker Desktop"
    method: "official"
  
  - name: "Kubernetes"
    method: "official"
  
  - name: "Terraform"
    method: "winget"
  
  # Collaboration & Communication
  - name: "Microsoft Teams"
    method: "winget"
  
  - name: "Slack"
    method: "winget"
  
  - name: "Jira"
    method: "official"
  
  - name: "Confluence"
    method: "official"
  
  # Testing & QA
  - name: "Postman"
    method: "winget"
  
  - name: "SOAP UI"
    method: "official"
  
  # Security
  - name: "Bitwarden"
    method: "winget"
  
  - name: "NordVPN"
    method: "official"
  
  - name: "Malwarebytes"
    method: "official"
```

## Minimal / Lean Setup

### config-minimal.yaml

```yaml
packages:
  - name: "Visual Studio Code"
    method: "winget"
  
  - name: "Git"
    method: "winget"
  
  - name: "Python"
    method: "official"
  
  - name: "Firefox"
    method: "winget"
  
  - name: "7-Zip"
    method: "winget"
```

## Configuration Specifications

### Installation Methods Priority

1. Winget (Windows Package Manager) - Fastest, officially maintained
2. Chocolatey - Wide package availability
3. Official installers - Most reliable, direct from vendor
4. Portable/Scoop - Alternative fallback options
5. Docker/WSL - For specific use cases

### Parallel Installation

- Winget packages install in parallel
- Official installers run sequentially
- Dependencies resolved automatically

### Pre-Installation Requirements

```yaml
prerequisites:
  - name: "Windows 10 version 1909+"
  - name: "Internet connectivity"
  - name: "Administrator privileges"
  - name: ".NET Framework 4.8+"
```

### Post-Installation Configuration

```yaml
post_install_tasks:
  - name: "Add to PATH"
  - name: "Create shortcuts"
  - name: "Import settings"
  - name: "Enable extensions"
  - name: "Configure environment variables"
```

---

**Usage**: Copy desired config file and modify as needed

```bash
helios-cli software bulk-install --config config-developer.yaml
```

**Total Packages Across All Configs**: 100+
**Installation Time**: 30 minutes - 2 hours depending on config
**Disk Space Required**: 10GB - 50GB depending on config
