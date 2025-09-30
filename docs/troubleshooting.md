# Troubleshooting Guide

Comprehensive guide to diagnosing and resolving common issues with Repo Orchestrator.

## Diagnostic Tools

### System Information Script

Create and run this diagnostic script:

```bash
cat > diagnose.sh << 'SCRIPT'
#!/bin/bash
echo "=== System Diagnostics ==="
echo "OS: $(uname -s) $(uname -r)"
echo "Python: $(python3 --version 2>&1)"
echo "Git: $(git --version 2>&1)"
echo "PWD: $(pwd)"
echo "User: $(whoami)"
echo ""
echo "=== Python Environment ==="
echo "Virtual env: ${VIRTUAL_ENV:-Not activated}"
echo "Python path: $(which python3)"
echo "Pip version: $(pip --version 2>&1)"
echo ""
echo "=== Git Configuration ==="
git config --get user.name && echo "Git user: $(git config --get user.name)"
git config --get user.email && echo "Git email: $(git config --get user.email)"
echo "Git notes refs: $(git config --get-all notes.displayRef | wc -l)"
echo ""
echo "=== Directory Structure ==="
ls -ld .octo octo configs scripts 2>/dev/null || echo "Missing directories"
SCRIPT
chmod +x diagnose.sh
./diagnose.sh
```

## Bootstrap Issues

### Bootstrap Script Fails Immediately

**Symptom:** Script exits with permission error

**Cause:** Script not executable

**Solution:**

```bash
chmod +x scripts/bootstrap.sh
./scripts/bootstrap.sh
```

### Python venv Creation Fails

**Symptom:**

```log
The virtual environment was not created successfully because ensurepip is not available.
```

**Diagnosis:**

```bash
# Check if python3-venv is installed
dpkg -l | grep python3-venv
```

**Solution:**

```bash
# Install python3-venv
sudo apt update
sudo apt install python3-venv python3-pip

# Clean and retry
rm -rf venv
./scripts/bootstrap.sh
```

**Alternative for macOS:**

```bash
# Ensure Python 3 is from Homebrew
brew install python
which python3  # Should show /usr/local/bin/python3 or /opt/homebrew/bin/python3
```

### Git Notes Configuration Error

**Symptom:**

```log
error: cannot overwrite multiple values with a single value
```

**Diagnosis:**

```bash
# Check existing notes configuration
git config --get-all notes.displayRef
```

**Solution:**

```bash
# Clear and reconfigure
git config --unset-all notes.displayRef
git config --add notes.displayRef "refs/notes/epics"
git config --add notes.displayRef "refs/notes/metrics"
git config --add notes.displayRef "refs/notes/releases"

# Verify
git config --get-all notes.displayRef
```

### Commit Message Validation Fails

**Symptom:**

```log
Invalid commit message format!
```

**Cause:** Commit doesn't follow conventional commit format

**Solution:**

```bash
# Use proper format
git commit -m "type(scope): description"

# Valid types:
# feat, fix, docs, style, refactor, perf, test, chore, build, ci, orchestration

# Examples:
git commit -m "chore(bootstrap): initialize octo"
git commit -m "feat(release): add coordination system"
git commit -m "fix(deps): resolve circular dependency"
```

**Bypass (not recommended):**

```bash
# Skip hooks for this commit only
git commit --no-verify -m "Your message"
```

## Python Import Errors

### Module Not Found

**Symptom:**

```log
ModuleNotFoundError: No module named 'yaml'
```

**Diagnosis:**

```bash
# Check if virtual environment is activated
echo $VIRTUAL_ENV

# Check installed packages
pip list | grep -i yaml
```

**Solution:**

```bash
# Activate virtual environment
source venv/bin/activate

# Reinstall dependencies
pip install -r requirements.txt

# Verify specific module
python3 -c "import yaml; print(yaml.__version__)"
```

### Wrong Python Version

**Symptom:** Module imports fail with syntax errors

**Diagnosis:**

```bash
# Check Python version
python3 --version

# Check which Python is being used
which python3
```

**Solution:**

```bash
# Ensure you're using Python 3.8+
python3 --version

# Recreate venv with specific Python version
rm -rf venv
python3.11 -m venv venv  # Use specific version
source venv/bin/activate
pip install -r requirements.txt
```

### PYTHONPATH Issues

**Symptom:** Orchestrator modules can't be imported

**Diagnosis:**

```bash
python3 -c "import sys; print('\n'.join(sys.path))"
```

**Solution:**

```bash
# Add current directory to PYTHONPATH
export PYTHONPATH="${PWD}:${PYTHONPATH}"

# Or add to venv activation
echo 'export PYTHONPATH="${VIRTUAL_ENV}/..:${PYTHONPATH}"' >> venv/bin/activate
source venv/bin/activate
```

## Git Hook Issues

### Hooks Not Executing

**Symptom:** Pre-commit checks don't run

**Diagnosis:**

```bash
# Check if hooks exist
ls -la .git/hooks/

# Check if they're executable
ls -l .git/hooks/pre-commit
```

**Solution:**

```bash
# Reinstall hooks
cp .octo/hooks/*.sh .git/hooks/
for hook in .git/hooks/*.sh; do
    mv "$hook" "${hook%.sh}"
done
chmod +x .git/hooks/*

# Test manually
.git/hooks/pre-commit
```

### Hook Fails with Python Errors

**Symptom:** Hook exits with import errors

**Diagnosis:**

```bash
# Check if hook uses correct Python
head -1 .git/hooks/pre-commit

# Test hook directly
bash -x .git/hooks/pre-commit
```

**Solution:**

```bash
# Ensure hooks use correct Python path
sed -i '1s|.*|#!/usr/bin/env python3|' .git/hooks/pre-commit

# Or ensure PATH includes venv
export PATH="${PWD}/venv/bin:${PATH}"
```

## Configuration Issues

### Invalid YAML Syntax

**Symptom:**

```log
yaml.scanner.ScannerError: mapping values are not allowed here
```

**Diagnosis:**

```bash
# Validate YAML syntax
python3 -c "import yaml; yaml.safe_load(open('configs/repositories.yaml'))"
```

**Solution:**

```bash
# Check for common YAML errors:
# - Incorrect indentation (use 2 spaces, not tabs)
# - Missing colons after keys
# - Unquoted special characters

# Use a YAML linter
yamllint configs/repositories.yaml

# Or validate with yq
yq eval '.' configs/repositories.yaml
```

### Circular Dependency Detected

**Symptom:**

```log
ERROR: Circular dependency detected: A -> B -> C -> A
```

**Diagnosis:**

```bash
python3 << 'EOF'
from octo import DependencyResolver
resolver = DependencyResolver()
cycles = resolver.check_circular_dependencies()
print("Cycles found:", cycles)
EOF
```

**Solution:**

```bash
# Identify and break the cycle by refactoring dependencies
# Update configs/repositories.yaml to remove circular references

# Verify fix
python3 scripts/orchestrate.py deps
```

## Repository Clone Issues

### Authentication Failures

**Symptom:**

```log
Permission denied (publickey)
```

**Diagnosis:**

```bash
# Test SSH connection
ssh -T git@github.com

# Check SSH keys
ls -la ~/.ssh/
```

**Solution:**

```bash
# Generate SSH key if needed
ssh-keygen -t ed25519 -C "your.email@example.com"

# Add to SSH agent
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# Add public key to GitHub/GitLab
cat ~/.ssh/id_ed25519.pub
# Copy and add to your Git provider

# Or use HTTPS with credentials
git config --global credential.helper store
```

### Repository Not Found

**Symptom:**

```log
fatal: repository 'https://github.com/org/repo.git' not found
```

**Diagnosis:**

```bash
# Check repository URL
git ls-remote https://github.com/org/repo.git

# Verify access
gh repo view org/repo  # If using GitHub CLI
```

**Solution:**

```bash
# Update repository URL in configs/repositories.yaml
# Ensure you have access to the repository
# Check organization/team permissions
```

## Performance Issues

### Slow Dependency Resolution

**Symptom:** Dependency analysis takes excessive time

**Diagnosis:**

```bash
# Profile the operation
time python3 scripts/orchestrate.py deps
```

**Solution:**

```bash
# Reduce repository count if testing
# Use sparse checkouts for large repos
# Check for extremely deep dependency chains
```

### Memory Issues with Large Repositories

**Symptom:** Process killed or out of memory errors

**Solution:**

```bash
# Increase available memory
# Use sparse checkout
git config --global core.sparseCheckout true

# Clone with depth limit
git clone --depth 1 <repository-url>

# Process repositories in batches
```

## GitHub CLI Issues

### Not Authenticated

**Symptom:**

```log
To authenticate, please run: gh auth login
```

**Solution:**

```bash
# Authenticate with GitHub
gh auth login

# Follow prompts to:
# 1. Choose GitHub.com or Enterprise
# 2. Choose HTTPS or SSH
# 3. Authenticate via browser or token

# Verify authentication
gh auth status
```

### Token Expired

**Symptom:**

```log
HTTP 401: Bad credentials
```

**Solution:**

```bash
# Re-authenticate
gh auth logout
gh auth login

# Or refresh token
gh auth refresh
```

## Testing Issues

### Pytest Not Found

**Symptom:**

```log
bash: pytest: command not found
```

**Solution:**

```bash
# Ensure virtual environment is activated
source venv/bin/activate

# Install pytest
pip install pytest pytest-cov pytest-mock

# Verify
pytest --version
```

### Tests Fail on Import

**Symptom:**

```log
ImportError: No module named 'octo'
```

**Solution:**

```bash
# Ensure PYTHONPATH includes project root
export PYTHONPATH="${PWD}:${PYTHONPATH}"

# Or run from project root
cd /path/to/repo-octo
pytest tests/
```

## Recovery Procedures

### Complete Reset

If everything is broken, start fresh:

```bash
# Backup your custom configurations
cp configs/repositories.yaml /tmp/repositories.yaml.backup

# Clean everything
rm -rf venv .git/hooks/* configs/dependencies.lock

# Clear git notes configuration
git config --unset-all notes.displayRef

# Re-run bootstrap
./scripts/bootstrap.sh

# Restore configurations
cp /tmp/repositories.yaml.backup configs/repositories.yaml
```

### Restore from Known Good State

```bash
# Find last working commit
git log --oneline

# Reset to that commit
git reset --hard <commit-hash>

# Re-bootstrap
./scripts/bootstrap.sh
```

## Getting Help

### Generate Diagnostic Report

```bash
cat > diagnostic-report.txt << 'EOF'
=== Environment ===
$(uname -a)
Python: $(python3 --version)
Git: $(git --version)

=== Orchestrator ===
$(ls -la .octo/)
$(git config --get-all notes.displayRef)

=== Python Packages ===
$(pip list)

=== Recent Errors ===
$(tail -50 /var/log/syslog 2>/dev/null | grep -i python || echo "No logs")
EOF

# Review and share
cat diagnostic-report.txt
```

### Enable Debug Logging

```bash
# Set debug environment variable
export DEBUG=1

# Run with verbose output
bash -x ./scripts/bootstrap.sh

# Python debug mode
python3 -v scripts/orchestrate.py deps
```

### Contact Support

When opening an issue, include:

1. Output of `./diagnose.sh`
2. Operating system and version
3. Python version
4. Full error message and stack trace
5. Steps to reproduce
6. What you've tried already

## Preventive Measures

### Regular Maintenance

```bash
# Update dependencies monthly
pip install --upgrade -r requirements.txt

# Update system packages
sudo apt update && sudo apt upgrade  # Ubuntu/Debian
brew upgrade  # macOS

# Validate configurations
make validate

# Run health checks
python3 scripts/orchestrate.py health
```

### Backup Critical Files

```bash
# Backup configurations
tar -czf octo-backup-$(date +%Y%m%d).tar.gz \
  configs/ .octo/ .git/config

# Store safely
mv octo-backup-*.tar.gz ~/backups/
```

### Keep Documentation Updated

- Document custom configurations
- Maintain internal runbooks
- Update team wiki with solutions to common issues
- Share learning across the team
