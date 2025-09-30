#!/bin/bash
# scripts/verify-installation.sh
# Comprehensive installation verification for Repo Orchestrator

# Don't exit on errors - we want to check everything
set +e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Debug mode
DEBUG=${DEBUG:-0}
debug() {
    [ "$DEBUG" -eq 1 ] && echo "[DEBUG] $*" >&2
}

# Functions
print_header() {
    echo -e "\n${BOLD}${BLUE}=== $1 ===${NC}"
}

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED++))
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED++))
    [ -n "$2" ] && echo -e "  ${YELLOW}→${NC} $2"
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
    [ -n "$2" ] && echo -e "  ${YELLOW}→${NC} $2"
}

# Main verification
echo -e "${BOLD}${BLUE}"
echo "╔═══════════════════════════════════════════╗"
echo "║   Repo Orchestrator Installation Check    ║"
echo "╚═══════════════════════════════════════════╝"
echo -e "${NC}"

# System Requirements
print_header "System Requirements"

# Python
debug "Checking Python..."
if command -v python3 >/dev/null 2>&1; then
    PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
    PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
    PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)
    
    if [ "$PYTHON_MAJOR" -ge 3 ] && [ "$PYTHON_MINOR" -ge 8 ]; then
        check_pass "Python $PYTHON_VERSION"
    else
        check_fail "Python $PYTHON_VERSION (need 3.8+)" "Upgrade Python"
    fi
else
    check_fail "Python not found" "Install: sudo apt install python3"
fi

# Git
debug "Checking Git..."
if command -v git >/dev/null 2>&1; then
    GIT_VERSION=$(git --version 2>&1 | awk '{print $3}')
    check_pass "Git $GIT_VERSION"
else
    check_fail "Git not found" "Install: sudo apt install git"
fi

# Optional Tools
debug "Checking optional tools..."
if command -v jq >/dev/null 2>&1; then
    JQ_VERSION=$(jq --version 2>&1 | cut -d'-' -f2)
    check_pass "jq $JQ_VERSION"
else
    check_warn "jq not found (optional)" "Install: sudo apt install jq"
fi

if command -v yq >/dev/null 2>&1; then
    YQ_VERSION=$(yq --version 2>&1 | awk '{print $NF}')
    check_pass "yq $YQ_VERSION"
else
    check_warn "yq not found (optional)" "Install: see docs/installation.md"
fi

if command -v gh >/dev/null 2>&1; then
    GH_VERSION=$(gh --version 2>&1 | head -1 | awk '{print $3}')
    check_pass "GitHub CLI $GH_VERSION"
    if gh auth status >/dev/null 2>&1; then
        check_pass "GitHub CLI authenticated"
    else
        check_warn "GitHub CLI not authenticated" "Run: gh auth login"
    fi
else
    check_warn "GitHub CLI not found (optional)" "Install: see docs/installation.md"
fi

# Virtual Environment
print_header "Python Virtual Environment"

debug "Checking virtual environment..."
if [ -d "venv" ]; then
    check_pass "Virtual environment exists"
    
    # Check if activated
    if [ -n "$VIRTUAL_ENV" ]; then
        check_pass "Virtual environment activated"
    else
        check_warn "Virtual environment not activated" "Run: source venv/bin/activate"
    fi
    
    # Check pip
    if [ -n "$VIRTUAL_ENV" ]; then
        if command -v pip >/dev/null 2>&1; then
            PIP_VERSION=$(pip --version 2>&1 | awk '{print $2}')
            check_pass "pip $PIP_VERSION"
        else
            check_fail "pip not found in venv"
        fi
    fi
else
    check_fail "Virtual environment missing" "Run: ./scripts/bootstrap.sh"
fi

# Python Packages
print_header "Python Dependencies"

debug "Checking Python packages..."
if [ -n "$VIRTUAL_ENV" ] || command -v python3 >/dev/null 2>&1; then
    REQUIRED_PACKAGES=(
        "yaml:PyYAML"
        "semantic_version:semantic-version"
        "networkx:networkx"
        "matplotlib:matplotlib"
        "requests:requests"
        "click:click"
    )
    
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        module="${pkg%%:*}"
        name="${pkg##*:}"
        
        debug "Checking module: $module"
        if python3 -c "import $module" 2>/dev/null; then
            VERSION=$(python3 -c "import $module; print(getattr($module, '__version__', 'installed'))" 2>/dev/null)
            check_pass "$name ($VERSION)"
        else
            check_fail "$name not installed" "Run: pip install $name"
        fi
    done
else
    check_warn "Skipping package check (Python not available)"
fi

# Orchestrator Modules
print_header "Orchestrator Modules"

debug "Checking octo modules..."
if python3 --version >/dev/null 2>&1; then
    MODULES=(
        "octo.version_manager:VersionCoordinator"
        "octo.dependency_graph:DependencyResolver"
        "octo.tracker:IssueTracker"
        "octo.monitor:RepoHealthMonitor"
    )
    
    for mod in "${MODULES[@]}"; do
        module="${mod%%:*}"
        class="${mod##*:}"
        
        debug "Checking: $module.$class"
        if python3 -c "from $module import $class" 2>/dev/null; then
            check_pass "$class"
        else
            check_fail "$class import failed" "Check PYTHONPATH and dependencies"
        fi
    done
else
    check_warn "Skipping module check (Python not available)"
fi

# Configuration Files
print_header "Configuration Files"

debug "Checking configuration files..."
CONFIGS=(
    "configs/repositories.yaml"
    "configs/tracker.yaml"
    ".octo/self.yaml"
)

for config in "${CONFIGS[@]}"; do
    debug "Checking: $config"
    if [ -f "$config" ]; then
        if python3 -c "import yaml; yaml.safe_load(open('$config'))" 2>/dev/null; then
            check_pass "$config (valid)"
        else
            check_fail "$config (invalid YAML)" "Check syntax"
        fi
    else
        check_fail "$config (missing)" "Run: ./scripts/bootstrap.sh"
    fi
done

# Directory Structure
print_header "Directory Structure"

debug "Checking directory structure..."
DIRS=(
    ".octo"
    "octo/providers"
    "scripts/version"
    "scripts/branch"
    "scripts/release"
    "scripts/deps"
    "configs"
    "repos"
    "docs"
)

for dir in "${DIRS[@]}"; do
    if [ -d "$dir" ]; then
        check_pass "$dir/"
    else
        check_fail "$dir/ missing" "Run: ./scripts/bootstrap.sh"
    fi
done

# Git Configuration
print_header "Git Configuration"

debug "Checking Git configuration..."
# User identity
if git config user.name >/dev/null 2>&1 && git config user.email >/dev/null 2>&1; then
    USER_NAME=$(git config user.name)
    USER_EMAIL=$(git config user.email)
    check_pass "Git identity configured ($USER_NAME <$USER_EMAIL>)"
else
    check_fail "Git identity not configured" "Run: git config --global user.name 'Your Name'"
fi

# Git notes
NOTE_COUNT=$(git config --get-all notes.displayRef 2>/dev/null | wc -l)
NOTE_COUNT=${NOTE_COUNT:-0}
if [ "$NOTE_COUNT" -eq 3 ]; then
    check_pass "Git notes configured (3 refs)"
else
    check_warn "Git notes configuration incomplete ($NOTE_COUNT/3)" "See docs/installation.md"
fi

# Git hooks
print_header "Git Hooks"

debug "Checking Git hooks..."
HOOKS=(
    "pre-commit"
    "commit-msg"
    "post-commit"
    "pre-push"
    "post-merge"
)

for hook in "${HOOKS[@]}"; do
    if [ -f ".git/hooks/$hook" ]; then
        if [ -x ".git/hooks/$hook" ]; then
            check_pass "$hook hook"
        else
            check_warn "$hook hook not executable" "Run: chmod +x .git/hooks/$hook"
        fi
    else
        check_warn "$hook hook missing (optional)" "Copy from .octo/hooks/"
    fi
done

# Functional Tests
print_header "Functional Tests"

debug "Running functional tests..."
if python3 --version >/dev/null 2>&1; then
    # Test dependency resolution
    if python3 -c "from octo import DependencyResolver; r = DependencyResolver(); r.get_build_order()" 2>/dev/null; then
        check_pass "Dependency resolution works"
    else
        check_fail "Dependency resolution failed" "Check repositories.yaml"
    fi
    
    # Test CLI
    if [ -f "scripts/orchestrate.py" ]; then
        if python3 scripts/orchestrate.py --help >/dev/null 2>&1; then
            check_pass "CLI interface works"
        else
            check_fail "CLI interface failed" "Check script permissions"
        fi
    else
        check_fail "CLI script missing" "Run: ./scripts/bootstrap.sh"
    fi
    
    # Test version coordination
    if python3 -c "from octo import VersionCoordinator; v = VersionCoordinator()" 2>/dev/null; then
        check_pass "Version coordination works"
    else
        check_fail "Version coordination failed" "Check dependencies"
    fi
else
    check_warn "Skipping functional tests (Python not available)"
fi

# Summary
print_header "Summary"

TOTAL=$((PASSED + FAILED + WARNINGS))
echo ""
echo -e "Tests run:  ${BOLD}$TOTAL${NC}"
echo -e "Passed:     ${GREEN}${BOLD}$PASSED${NC}"
echo -e "Failed:     ${RED}${BOLD}$FAILED${NC}"
echo -e "Warnings:   ${YELLOW}${BOLD}$WARNINGS${NC}"
echo ""

# Final verdict
if [ "$FAILED" -eq 0 ]; then
    if [ "$WARNINGS" -eq 0 ]; then
        echo -e "${GREEN}${BOLD}✓ Installation complete and verified!${NC}"
        echo ""
        echo "Next steps:"
        echo "  1. Configure repositories: vim configs/repositories.yaml"
        echo "  2. Run health check: python3 scripts/orchestrate.py health"
        echo "  3. Read user guide: docs/user-guide.md"
        exit 0
    else
        echo -e "${YELLOW}${BOLD}⚠ Installation complete with warnings${NC}"
        echo ""
        echo "Review warnings above and consider installing optional tools."
        echo "Run with DEBUG=1 for more information."
        exit 0
    fi
else
    echo -e "${RED}${BOLD}✗ Installation incomplete - $FAILED critical issues${NC}"
    echo ""
    echo "Fix the failed checks above and re-run this script."
    echo "Run with DEBUG=1 for detailed diagnostics."
    echo "See docs/troubleshooting.md for help."
    exit 1
fi