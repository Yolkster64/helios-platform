> Historical reference for the separate Dockerfile/Compose setup. The current
> `devcontainer.json` does not select this path; claims below have not been
> revalidated. Use [README.md](README.md) for the active Codespaces configuration.

# Helios Platform Development Container Setup

Complete, production-ready development environment configuration for Helios Platform with Docker, PowerShell, Node.js, Python, and comprehensive tooling.

## 📦 What's Included

### Core Development Tools
- **PowerShell 7.4** with modules (posh-git, oh-my-posh, Terminal-Icons)
- **Node.js 20 & 22 LTS** with npm, yarn, pnpm
- **Python 3** with pipenv, poetry, pip
- **GitHub CLI** for repository management
- **Docker & Docker Compose** for containerization
- **Git** with pre-configured hooks and settings
- **SQLite3** for local database

### Development Utilities
- TypeScript, ESLint, Prettier
- Jupyter Notebook & Labs
- Azure CLI (az module)
- Testing frameworks (pytest, jest)
- Code quality tools (black, pylint, flake8)

### Port Mappings
| Port | Service | Purpose |
|------|---------|---------|
| 8080 | Wiki | Application |
| 5432 | PostgreSQL | Database (optional) |
| 3000 | Dev Server | Node.js development |
| 5173 | Vite | Frontend dev server |
| 3001 | API | Backend API |
| 4200 | Angular | Angular dev server |
| 8000 | Python | FastAPI/Django |
| 8888 | Jupyter | Notebook server |

## 🚀 Quick Start

### Option 1: Using Dev Container (Recommended)

```bash
# Open in VS Code and reopen in container
code .

# Or from command line
cd .devcontainer
docker-compose up -d

# Access the container
docker-compose exec devcontainer bash
```

### Option 2: Local Setup

```bash
# Run setup script
bash devsetup.sh

# Or from PowerShell
./devsetup.ps1
```

## 📁 File Structure

```
.devcontainer/
├── devcontainer.json          # VS Code dev container config
├── Dockerfile                 # Base container image
├── docker-compose.yml         # Multi-service orchestration
├── onCreateCommand.sh         # Post-creation setup script (130+ lines)
└── init-db.sh                 # PostgreSQL initialization

.vscode/
├── settings.json              # Editor configuration
├── extensions.json            # Recommended extensions
├── launch.json                # Debug configurations
└── tasks.json                 # Build and run tasks

.gitignore                      # Git exclusions
.editorconfig                   # Cross-editor formatting
.prettierrc                     # Code formatter config
devsetup.sh                     # Local setup script
```

## 🔧 Features

### devcontainer.json (208 lines)
- Docker Compose orchestration
- Feature installation (git, GitHub CLI, PowerShell, Docker)
- Port forwarding with labels
- VS Code settings and extensions
- Post-create and post-start commands
- Volume mounts for persistence
- Environment variables
- Security capabilities

### Dockerfile (150 lines)
- Ubuntu 22.04 base (focal)
- System dependencies and build tools
- PowerShell 7.4 installation
- Node.js via NVM (versions 20 & 22)
- GitHub CLI setup
- Python 3 with dev tools
- PowerShell modules (PSReadLine, posh-git, etc.)
- Non-root user (devuser)
- Git configuration

### docker-compose.yml (180 lines)
- Devcontainer service with full configuration
- PostgreSQL 16 Alpine (optional database)
- 8 port mappings with proper protocols
- Volume mounts for caching and persistence
- Environment variables for Node, Python, Docker, Database
- Health checks
- Network configuration
- Dependency management

### onCreateCommand.sh (280+ lines)
- Git configuration and hooks setup
- Pre-commit hook for code quality
- Commit message validation
- Directory structure creation
- Node.js environment initialization
- Python virtual environment setup
- PowerShell profile configuration
- SQLite database initialization
- .env file generation
- Comprehensive tool verification
- Helper scripts creation

### VS Code Configuration
**settings.json** - Editor, formatting, and extension settings
- Python linting with pylint
- Black code formatting
- Prettier for JavaScript/TypeScript
- ESLint integration
- File exclusions and search patterns
- Terminal profiles for bash and PowerShell
- Line rulers and word wrap

**extensions.json** - 26 recommended extensions
- PowerShell, Python, Pylance, Black
- Prettier, ESLint, Docker, Remote Containers
- GitHub Copilot and PR extension
- GitLens, YAML, Markdown

**launch.json** - Debug configurations
- PowerShell attach and launch
- Python current file, Django, FastAPI
- Node.js debugging

**tasks.json** - Build and development tasks
- npm install, build, test, lint
- Docker Compose commands
- Python testing with pytest

## 🔑 Key Configuration Details

### Git Hooks
- **pre-commit**: Prettier formatting, code quality
- **commit-msg**: Enforces conventional commit format
- **post-merge**: Checks for dependency updates

### Environment Variables
```
NODE_ENV=development
PYTHONUNBUFFERED=1
WORKSPACE=/workspace
POSTGRES_HOST=postgres
POSTGRES_DB=helios_dev
```

### Database Setup
PostgreSQL 16 with automatic initialization:
- Creates extensions (uuid, pg_trgm, btree_gin)
- Sets up wiki_pages and users tables
- Configures indexes
- Grants permissions

### Security Features
- SYS_PTRACE capability for debugging
- Non-root user (devuser) execution
- SSH key mounting (read-only)
- Docker socket access
- Seccomp unconfined

## 🎯 Usage Examples

### Starting Development

```bash
# Build and start all services
cd .devcontainer
docker-compose up -d

# Access devcontainer
docker-compose exec devcontainer bash

# View logs
docker-compose logs -f devcontainer
```

### Node.js Development

```bash
npm install
npm start
npm run build
npm test
npm run lint
```

### Python Development

```bash
source .venv/bin/activate
pip install -r requirements.txt
python main.py
pytest -v
```

### PowerShell

```powershell
pwsh
# Access PowerShell functions, modules, and environment
```

### Database Operations

```bash
# Connect to PostgreSQL
psql -h postgres -U devuser -d helios_dev

# View status
docker-compose ps
```

## 📊 Container Specifications

- **Base Image**: mcr.microsoft.com/devcontainers/universal:2-focal
- **OS**: Ubuntu 22.04 (Focal)
- **Memory**: 4GB default (configurable)
- **Volumes**: Named volumes for caching (node_modules, .venv, etc.)
- **Network**: Bridge network (helios-network)

## 🔄 Persistent Volumes

All volumes are automatically created and managed:
- `devcontainer-node-modules` - Node.js dependencies cache
- `devcontainer-python-cache` - Python venv
- `devcontainer-home` - User home directory
- `devcontainer-npm-cache` - npm cache
- `devcontainer-nvm` - NVM installation
- `postgres-data` - PostgreSQL data

## 📝 Configuration Files

### .editorconfig
Ensures consistent coding styles:
- Python: 4 spaces, 100 char limit
- JavaScript/JSON: 2 spaces
- YAML: 2 spaces
- Markdown: no trim

### .prettierrc
Code formatting rules:
- 100 char line width
- Single quotes
- Trailing commas (ES5)
- LF line endings
- Semicolons enabled

### .gitignore
Excludes 50+ patterns:
- node_modules, .venv, __pycache__
- Build artifacts (dist, build, out)
- IDE files (.vscode, .idea)
- OS files (.DS_Store, Thumbs.db)
- Temporary and log files

## 🛠️ Commands

### Dev Container Lifecycle

```bash
# Start services
docker-compose up -d

# Stop services
docker-compose down

# Rebuild image
docker-compose build --no-cache

# View logs
docker-compose logs -f [service]

# Execute command in container
docker-compose exec devcontainer [command]
```

### Common Tasks

```bash
# Open bash shell
docker-compose exec devcontainer bash

# Open PowerShell
docker-compose exec devcontainer pwsh

# Run tests
docker-compose exec devcontainer npm test

# Format code
docker-compose exec devcontainer npm run format
```

## 🐛 Troubleshooting

### Port Already in Use
```bash
# Find and kill process on port
lsof -i :8080
kill -9 <PID>

# Or change port in docker-compose.yml
```

### Docker Daemon Issues
```bash
# Restart Docker
systemctl restart docker
# or on macOS
open -a Docker
```

### Volume Permission Issues
```bash
# Fix volume permissions
docker-compose down -v
docker-compose up -d
```

### Clear Cache
```bash
docker-compose down -v
docker system prune -a
docker-compose build --no-cache
```

## 📚 Documentation

- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Dev Containers](https://containers.dev/)
- [PowerShell Docs](https://docs.microsoft.com/powershell/)
- [Node.js NVM](https://github.com/nvm-sh/nvm)
- [Python venv](https://docs.python.org/3/library/venv.html)

## 🔐 Security Considerations

- Non-root user (devuser) runs all processes
- SSH keys mounted read-only
- No hardcoded credentials in config
- Use .env for sensitive values
- PostgreSQL password in docker-compose (change for production)
- seccomp enabled with necessary capabilities

## 📋 Requirements

- Docker 20.10+
- Docker Compose 1.29+
- VS Code 1.60+ (for dev container support)
- 8GB RAM minimum
- 20GB disk space (for images and volumes)

## 🤝 Contributing

When adding new tools or features:
1. Update Dockerfile with installation
2. Add environment variables to docker-compose.yml
3. Update .devcontainer/onCreateCommand.sh
4. Document in README.md
5. Test locally: `docker-compose up --build`

## 📄 License

Helios Platform Configuration - 2024

---

**Last Updated**: 2024
**Version**: 1.0
**Maintainer**: Helios Platform Dev Team
