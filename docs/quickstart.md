# Quick Start Guide

Get up and running with Repo Orchestrator in 5 minutes.

## Prerequisites Checklist

Ensure you have these installed:

```bash
# Check versions
python3 --version    # 3.8+
git --version        # 2.20+
jq --version         # latest (optional)
yq --version         # latest (optional)
gh --version         # latest (optional)
```

## One-Line Installation

For Ubuntu/Debian systems with all prerequisites:

```bash
curl -fsSL https://raw.githubusercontent.com/yourorg/repo-octo/main/scripts/quick-install.sh | bash
```

## Manual Installation

### 1. Install System Dependencies

```bash
# Ubuntu/Debian
sudo apt update && sudo apt install -y python3 python3-pip python3-venv git jq

# macOS
brew install python git jq
```

### 2. Clone and Bootstrap

```bash
git clone https://github.com/yourorg/repo-octo.git
cd repo-octo
./scripts/bootstrap.sh
```

### 3. Activate and Verify

```bash
source venv/bin/activate
python3 scripts/orchestrate.py --help
```

## Quick Configuration

### Configure Git

```bash
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

### Configure Your Repositories

Edit `configs/repositories.yaml`:

```yaml
repositories:
  my-lib:
    url: git@github.com:yourorg/my-lib.git
    version: 1.0.0
    type: library
    dependencies: []
  
  my-service:
    url: git@github.com:yourorg/my-service.git
    version: 2.0.0
    type: service
    dependencies:
      - name: my-lib
        version: "^1.0.0"
        type: compile
```

## First Commands

```bash
# Activate environment
source venv/bin/activate

# Check dependency graph
python3 scripts/orchestrate.py deps

# Visualize dependencies
make visualize

# Check health
python3 scripts/orchestrate.py health

# Create feature branch across repos
./scripts/branch/create-feature.sh my-feature main all
```

## Common First-Time Issues

### Issue: Bootstrap Fails on venv

```bash
sudo apt install python3-venv
rm -rf venv
./scripts/bootstrap.sh
```

### Issue: Commit Message Format

Use conventional commits:

```bash
git commit -m "feat: add new feature"
git commit -m "fix: resolve bug"
git commit -m "chore: update dependencies"
```

### Issue: Import Errors

```bash
source venv/bin/activate
pip install -r requirements.txt
```

## Next Steps

1. **Add your repositories**: Update `configs/repositories.yaml`
2. **Clone repositories**: `make clone-all`
3. **Run health check**: `python3 scripts/orchestrate.py health`
4. **Read full docs**: See `docs/installation.md`

## Getting Help

- Full Installation Guide: [docs/installation.md](./installation.md)
- Architecture Overview: [docs/architecture.md](./architecture.md)
- Troubleshooting: [docs/troubleshooting.md](./troubleshooting.md)
