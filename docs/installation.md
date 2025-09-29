# Installation Guide

Complete guide for installing and bootstrapping the Repo Orchestrator system.

## System Requirements

### Minimum Requirements

- **OS**: Linux (Ubuntu 20.04+, Debian 11+) or macOS 11+
- **Python**: 3.8 or higher
- **Git**: 2.20 or higher
- **Memory**: 512 MB RAM minimum, 2 GB recommended
- **Disk**: 500 MB free space minimum

### Supported Platforms

- Ubuntu 20.04 LTS, 22.04 LTS, 24.04 LTS
- Debian 11, 12
- macOS 11 (Big Sur) or later
- WSL2 on Windows 10/11

## Prerequisites

### Required System Packages

#### Ubuntu/Debian

```bash
# Update package index
sudo apt update

# Install required packages
sudo apt install -y \
    python3 \
    python3-pip \
    python3-venv \
    git \
    curl \
    wget

# Verify installations
python3 --version  # Should be 3.8+
git --version      # Should be 2.20+
```

#### macOS

```bash
# Install Homebrew if not present
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install required packages
brew install python git

# Verify installations
python3 --version
git --version
```

### Optional but Recommended Packages

#### JSON and YAML Processors

**jq (JSON processor):**

```bash
# Ubuntu/Debian
sudo apt install -y jq

# macOS
brew install jq

# Verify
jq --version
```

**yq (YAML processor):**

```bash
# Download latest release
sudo wget -qO /usr/local/bin/yq \
  https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64

# Make executable
sudo chmod +x /usr/local/bin/yq

# For macOS
# brew install yq

# Verify
yq --version
```

#### GitHub CLI (for GitHub integration)

```bash
# Ubuntu/Debian
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
  sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | \
  sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null

sudo apt update
sudo apt install -y gh

# macOS
brew install gh

# Authenticate with GitHub
gh auth login
```

## Git Configuration

Configure Git with your identity before running the bootstrap:

```bash
# Set global user configuration
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"

# Set default branch name
git config --global init.defaultBranch main

# Configure line endings (Unix-style)
git config --global core.autocrlf input

# Verify configuration
git config --list | grep -E "user\.|init\.|core\.autocrlf"
```

## Python Virtual Environment Setup

The bootstrap script creates a virtual environment automatically, but the `python3-venv` package must be installed first.

### Verify Python venv Module

```bash
# Test if venv module is available
python3 -m venv --help

# If the command fails, install python3-venv
sudo apt install python3-venv  # Ubuntu/Debian

# Verify pip is available
python3 -m pip --version
```

## Bootstrap Process

### Step 1: Clone the Repository

```bash
# Clone the orchestrator repository
git clone https://github.com/yourorg/repo-orchestrator.git
cd repo-orchestrator

# Or if you're initializing from scratch
mkdir repo-orchestrator
cd repo-orchestrator
git init
```

### Step 2: Prepare Bootstrap Script

```bash
# Ensure bootstrap script is executable
chmod +x scripts/bootstrap.sh

# Review the script (optional)
less scripts/bootstrap.sh
```

### Step 3: Run Bootstrap

```bash
# Execute bootstrap
./scripts/bootstrap.sh
```

The bootstrap script performs the following operations:

1. **Prerequisite Check**: Validates required tools (git, python3, gh, jq, yq)
2. **Directory Creation**: Sets up orchestrator directory structure
3. **Git Initialization**: Configures git repository, hooks, and notes
4. **Python Environment**: Creates virtual environment and installs dependencies
5. **Configuration**: Generates initial configuration files
6. **GitHub Auth**: Validates GitHub CLI authentication (if available)
7. **Self-Management**: Creates initial commit and version tag

### Step 4: Activate Virtual Environment

```bash
# Activate Python virtual environment
source venv/bin/activate

# Verify activation (prompt should show (venv))
which python3
# Should output: /path/to/repo-orchestrator/venv/bin/python3

# Verify packages are installed
pip list | grep -E "(pyyaml|semantic-version|networkx)"
```

### Step 5: Validate Installation

```bash
# Run validation script
./scripts/validate-setup.sh

# Test core functionality
python3 -c "from orchestrator import DependencyResolver; print('✓ Imports working')"

# Test CLI
python3 scripts/orchestrate.py --help
```

## Common Issues and Solutions

### Issue: `python3-venv` Not Available

**Symptom:**

```log
The virtual environment was not created successfully because ensurepip is not available.
```

**Solution:**

```bash
# Install python3-venv package
sudo apt install python3-venv

# Remove incomplete venv and retry
rm -rf venv
./scripts/bootstrap.sh
```

### Issue: Git Notes Configuration Error

**Symptom:**

```log
error: cannot overwrite multiple values with a single value
```

**Solution:**

```bash
# Clear existing notes configuration
git config --unset-all notes.displayRef

# Re-run bootstrap
./scripts/bootstrap.sh
```

### Issue: Commit Message Format Error

**Symptom:**

```log
Invalid commit message format!
```

**Context:** The orchestrator enforces conventional commit messages. The bootstrap script's initial commit must follow this format.

**Solution:** The bootstrap script should use:

```bash
git commit -m "chore(bootstrap): initialize orchestrator environment"
```

If you need to commit manually:

```bash
# Use conventional commit format
git commit -m "chore: your commit message"

# Valid types: feat, fix, docs, style, refactor, perf, test, chore, build, ci, orchestration
```

### Issue: Permission Denied on Scripts

**Symptom:**

```log
bash: ./scripts/bootstrap.sh: Permission denied
```

**Solution:**

```bash
# Make script executable
chmod +x scripts/bootstrap.sh

# Or run with bash
bash scripts/bootstrap.sh
```

### Issue: GitHub CLI Not Authenticated

**Symptom:**

```log
WARNING: GitHub CLI not authenticated
```

**Solution:**

```bash
# Authenticate with GitHub
gh auth login

# Follow the prompts to authenticate via browser or token
```

### Issue: Module Import Errors

**Symptom:**

```log
ModuleNotFoundError: No module named 'yaml'
```

**Solution:**

```bash
# Ensure virtual environment is activated
source venv/bin/activate

# Reinstall dependencies
pip install -r requirements.txt

# Or install specific missing module
pip install pyyaml
```

## Post-Installation Steps

### Configure Repositories

Edit the repository manifest to define your multi-repo system:

```bash
# Edit configuration
vim configs/repositories.yaml

# Example configuration structure:
# repositories:
#   your-lib:
#     url: git@github.com:yourorg/your-lib.git
#     version: 1.0.0
#     type: library
#     dependencies: []
```

### Initialize Test Environment

Create test repositories for validation:

```bash
# Create test repository structure
./scripts/setup-test-env.sh

# Verify test repositories
ls -la repos/
```

### Run Initial Health Check

```bash
# Activate virtual environment
source venv/bin/activate

# Check repository health
python3 scripts/orchestrate.py health

# Analyze dependencies
python3 scripts/orchestrate.py deps

# Generate dependency graph
make visualize
```

### Configure Provider Integration

If using GitHub, GitLab, or Gitea:

```bash
# For GitHub (using GitHub CLI)
gh auth login

# For GitLab (set environment variable)
export GITLAB_TOKEN=your-token
export GITLAB_API_URL=https://gitlab.com/api/v4

# For Gitea
export GITEA_TOKEN=your-token
export GITEA_API_URL=https://gitea.example.com/api/v1
```

## Verification Checklist

Run through this checklist to ensure proper installation:

```bash
# 1. Python environment
python3 --version                    # ✓ Version 3.8+
which python3 | grep venv            # ✓ Points to venv

# 2. Required modules
python3 -c "import yaml, networkx, semantic_version, matplotlib"  # ✓ No errors

# 3. Orchestrator modules
python3 -c "from orchestrator import VersionCoordinator, DependencyResolver"  # ✓ No errors

# 4. Configuration files
ls configs/repositories.yaml         # ✓ Exists
python3 -c "import yaml; yaml.safe_load(open('configs/repositories.yaml'))"  # ✓ Valid

# 5. Git configuration
git config --get-all notes.displayRef | wc -l  # ✓ Returns 3

# 6. Git hooks
ls -la .git/hooks/pre-commit         # ✓ Exists and executable

# 7. CLI functionality
python3 scripts/orchestrate.py --help  # ✓ Displays help

# 8. Make targets
make help                            # ✓ Displays available commands
```

## Development Setup

For development and testing:

```bash
# Install development dependencies
pip install -r requirements-dev.txt 2>/dev/null || pip install pytest pytest-cov black flake8 mypy

# Install pre-commit hooks
pre-commit install 2>/dev/null || echo "pre-commit not available"

# Run tests
pytest tests/ -v

# Check code formatting
black --check orchestrator/ tests/

# Run linter
flake8 orchestrator/ --max-line-length=100
```

## Docker Alternative

For containerized deployment:

```bash
# Build Docker image
docker build -t repo-orchestrator:latest .

# Run orchestrator in container
docker run -it --rm \
  -v $(pwd):/workspace \
  -v ~/.ssh:/root/.ssh:ro \
  -v ~/.gitconfig:/root/.gitconfig:ro \
  repo-orchestrator:latest

# Run specific command
docker run --rm repo-orchestrator:latest \
  python3 scripts/orchestrate.py health
```

## Environment Variables

Optional environment variables for configuration:

```bash
# GitHub configuration
export GITHUB_TOKEN=ghp_xxxxxxxxxxxxx
export GITHUB_OWNER=yourorg

# GitLab configuration
export GITLAB_TOKEN=glpat-xxxxxxxxxxxxx
export GITLAB_API_URL=https://gitlab.com/api/v4
export GITLAB_NAMESPACE=yourgroup

# Gitea configuration
export GITEA_TOKEN=xxxxxxxxxxxxx
export GITEA_API_URL=https://gitea.example.com/api/v1

# Orchestrator configuration
export ORCHESTRATOR_HOME=/path/to/orchestrator
export PYTHONPATH=$ORCHESTRATOR_HOME:$PYTHONPATH
```

## Uninstallation

To completely remove the orchestrator:

```bash
# Deactivate virtual environment
deactivate

# Remove orchestrator directory
cd ..
rm -rf repo-orchestrator

# Optional: Remove global git configurations
git config --global --unset-all notes.displayRef
```

## Next Steps

After successful installation:

1. **Configure repositories**: Update `configs/repositories.yaml` with your actual repositories
2. **Clone repositories**: Use the orchestrator to clone and manage your repos
3. **Create feature branches**: Test cross-repository branch creation
4. **Run health checks**: Monitor repository health and metrics
5. **Coordinate releases**: Perform a dry-run release to test the workflow

For detailed usage instructions, see:

- [User Guide](./user-guide.md)
- [Release Management](./release-management.md)
- [Dependency Management](./dependency-management.md)

## Support

For issues or questions:

- Check [Troubleshooting Guide](./troubleshooting.md)
- Review [FAQ](./faq.md)
- Open an issue on GitHub
- Consult the [Architecture Documentation](./architecture.md)
