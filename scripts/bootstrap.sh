#!/bin/bash
# Bootstrap script for repo-orchestrator

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Git
    if ! command -v git &> /dev/null; then
        log_error "Git is not installed. Please install Git first."
        exit 1
    fi
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is not installed. Please install Python 3 first."
        exit 1
    fi
    
    # Check GitHub CLI (optional but recommended)
    if command -v gh &> /dev/null; then
        log_success "GitHub CLI found"
        GH_CLI=true
    else
        log_warning "GitHub CLI not found. Some features will be limited."
        log_warning "Install from: https://cli.github.com"
        GH_CLI=false
    fi
    
    # Check jq for JSON processing
    if ! command -v jq &> /dev/null; then
        log_warning "jq not found. Installing jq is recommended for JSON processing."
    fi
    
    # Check yq for YAML processing
    if ! command -v yq &> /dev/null; then
        log_warning "yq not found. Installing yq is recommended for YAML processing."
    fi
}

# Initialize repository
init_repository() {
    log_info "Initializing repository..."
    
    # Initialize git if not already
    if [ ! -d .git ]; then
        git init
        log_success "Git repository initialized"
    else
        log_info "Git repository already exists"
    fi
    
    # Set up git notes refs
    git config --unset-all notes.displayRef 2>/dev/null || true
    git config --add notes.displayRef "refs/notes/epics"
    git config --add notes.displayRef "refs/notes/metrics"
    git config --add notes.displayRef "refs/notes/releases"
    log_success "Git notes configured"
    
    # Set up git hooks
    if [ -d .orchestrator/hooks/ ]; then
        log_info "Installing git hooks..."
        mkdir -p .git/hooks
        cp .orchestrator/hooks/*.sh .git/hooks/
        # Remove .sh extension for git hooks
        for hook in .git/hooks/*.sh; do
            mv "$hook" "${hook%.sh}"
        done
        chmod +x .git/hooks/*
        log_success "Git hooks installed"
    fi
}

# Create directory structure
create_directory_structure() {
    log_info "Creating directory structure..."
    
    # Create main directories
    directories=(
        ".orchestrator"
        "orchestrator/providers"
        "scripts/version"
        "scripts/branch"
        "scripts/release"
        "scripts/deps"
        "scripts/rollback"
        "configs/workflows"
        ".github/workflows"
        "repos"
        "docs"
        "hooks"
        "templates"
    )
    
    for dir in "${directories[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            log_success "Created $dir"
        else
            log_info "$dir already exists"
        fi
    done
}

# Set up Python environment
setup_python_env() {
    log_info "Setting up Python environment..."
    
    # Create virtual environment
    if [ ! -d "venv" ]; then
        python3 -m venv venv
        log_success "Virtual environment created"
    else
        log_info "Virtual environment already exists"
    fi
    
    # Activate virtual environment
    source venv/bin/activate
    
    # Install requirements
    if [ -f requirements.txt ]; then
        pip install -r requirements.txt
        log_success "Python dependencies installed"
    else
        log_warning "requirements.txt not found. Creating with default dependencies..."
        cat > requirements.txt << EOF
# Core dependencies
pyyaml>=6.0
semantic-version>=2.10.0
networkx>=3.0
matplotlib>=3.6.0
requests>=2.28.0
click>=8.1.0

# Development dependencies
pytest>=7.2.0
black>=22.0.0
flake8>=6.0.0
mypy>=0.991
EOF
        pip install -r requirements.txt
        log_success "Default dependencies installed"
    fi
}

# Create initial configuration
create_initial_config() {
    log_info "Creating initial configuration..."
    
    # Create orchestrator self-config
    if [ ! -f ".orchestrator/self.yaml" ]; then
        cat > .orchestrator/self.yaml << 'EOF'
orchestrator:
  version: 0.1.0
  bootstrap:
    hooks:
      - pre-commit: validate-config
      - post-commit: sync-version
      - pre-push: dependency-check
  
  self-management:
    versioning:
      strategy: semver
      auto-bump: patch
      trigger: commit-message
    
    workflows:
      - name: self-update
        on: [push, workflow_dispatch]
        jobs:
          - validate-orchestration
          - update-dependencies
          - sync-configurations
EOF
        log_success "Created orchestrator self-config"
    fi
    
    # Create repositories config
    if [ ! -f "configs/repositories.yaml" ]; then
        cat > configs/repositories.yaml << 'EOF'
# Repository manifest
repositories:
  example-lib:
    url: git@github.com:user/example-lib.git
    version: 1.0.0
    type: library
    dependencies: []
  
  example-service:
    url: git@github.com:user/example-service.git
    version: 1.0.0
    type: service
    dependencies:
      - name: example-lib
        version: "^1.0.0"
        type: compile

dependency_rules:
  resolution: highest-compatible
  lock_strategy: conservative
  update_policy: explicit
EOF
        log_success "Created repositories config"
    fi
    
    # Create tracker config
    if [ ! -f "configs/tracker.yaml" ]; then
        cat > configs/tracker.yaml << 'EOF'
# Issue and milestone tracking configuration
tracker:
  provider: github  # github, gitlab, or gitea
  
  labels:
    - name: epic
      color: "7057ff"
      description: "Cross-repository epic"
    - name: cross-repo
      color: "0052cc"
      description: "Spans multiple repositories"
    - name: release
      color: "0e8a16"
      description: "Release tracking"
    - name: orchestration
      color: "fbca04"
      description: "Orchestration task"
  
  epic_template: |
    ## Epic: {{title}}
    
    {{description}}
    
    ### Acceptance Criteria
    - [ ] Criteria 1
    - [ ] Criteria 2
    
    ### Related Issues
    {{issues}}
EOF
        log_success "Created tracker config"
    fi
}

# Set up GitHub authentication
setup_github_auth() {
    if [ "$GH_CLI" = true ]; then
        log_info "Setting up GitHub authentication..."
        
        # Check if already authenticated
        if gh auth status &> /dev/null; then
            log_success "GitHub CLI already authenticated"
        else
            log_warning "GitHub CLI not authenticated"
            read -p "Would you like to authenticate now? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                gh auth login
            fi
        fi
    fi
}

# Create example scripts
create_example_scripts() {
    log_info "Creating example orchestration scripts..."
    
    # Make scripts executable
    cat > scripts/orchestrate.py << 'EOF'
#!/usr/bin/env python3
"""Main orchestration CLI"""

import click
import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from orchestrator import VersionCoordinator, DependencyResolver, IssueTracker, RepoHealthMonitor

@click.group()
def cli():
    """Repo Orchestrator - Multi-repository coordination system"""
    pass

@cli.command()
@click.argument('repo')
@click.option('--type', default='patch', help='Version bump type: patch, minor, major')
@click.option('--dry-run/--no-dry-run', default=True, help='Perform dry run')
def release(repo, type, dry_run):
    """Coordinate a release across repositories"""
    coordinator = VersionCoordinator()
    plan = coordinator.coordinate_release(repo, type)
    
    click.echo(f"Release plan for {repo}:")
    click.echo(f"  Source: {plan['source']['repo']} -> v{plan['source']['new_version']}")
    
    if plan['affected']:
        click.echo("  Affected repositories:")
        for affected in plan['affected']:
            click.echo(f"    - {affected['repo']}: {affected['suggested_action']}")
    
    if not dry_run:
        results = coordinator.execute_release_plan(plan, dry_run=False)
        click.echo(f"Results: {len(results['success'])} succeeded, {len(results['failed'])} failed")

@cli.command()
def health():
    """Check health of all repositories"""
    monitor = RepoHealthMonitor()
    report = monitor.generate_health_report()
    click.echo(report)

@cli.command()
def deps():
    """Analyze dependencies"""
    resolver = DependencyResolver()
    
    # Check for circular dependencies
    cycles = resolver.check_circular_dependencies()
    if cycles:
        click.echo("⚠️  Circular dependencies detected:")
        for cycle in cycles:
            click.echo(f"  {' -> '.join(cycle)}")
    else:
        click.echo("✅ No circular dependencies")
    
    # Show build order
    order = resolver.get_build_order()
    click.echo(f"\nBuild order: {' -> '.join(order)}")

if __name__ == '__main__':
    cli()
EOF
    
    chmod +x scripts/orchestrate.py
    log_success "Created orchestration CLI script"
}

# Initialize self-management
init_self_management() {
    log_info "Initializing self-management..."
    
    # Stage all files
    git add -A
    
    # Check if there are changes to commit
    if git diff-index --quiet HEAD -- 2>/dev/null; then
        log_info "No changes to commit (already initialized)"
    else
        # Commit with proper conventional format
        git commit -m "chore(bootstrap): initialize orchestrator environment

Initialize repository with:
- Directory structure for multi-repo orchestration
- Git hooks for conventional commits and version tracking
- Python virtual environment with dependencies
- Configuration templates for repositories and tracking
- Initial orchestrator self-management setup

Refs: #init" 2>/dev/null || {
            log_warning "Commit failed - may already be initialized"
            return 0
        }
        log_success "Created initial commit"
    fi
    
    # Create version tag if it doesn't exist
    if ! git rev-parse v0.1.0 >/dev/null 2>&1; then
        git tag -a v0.1.0 -m "chore: release orchestrator v0.1.0" 2>/dev/null || {
            log_warning "Tag v0.1.0 may already exist"
            return 0
        }
        log_success "Created tag v0.1.0"
    else
        log_info "Tag v0.1.0 already exists"
    fi
    
    log_success "Self-management initialized"
}

# Main bootstrap process
main() {
    echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     Repo Orchestrator Bootstrap     ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
    echo
    
    check_prerequisites
    create_directory_structure
    init_repository
    setup_python_env
    create_initial_config
    setup_github_auth
    create_example_scripts
    init_self_management
    
    echo
    echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   Bootstrap completed successfully!  ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
    echo
    echo "Next steps:"
    echo "  1. Update configs/repositories.yaml with your repositories"
    echo "  2. Run 'source venv/bin/activate' to activate Python environment"
    echo "  3. Use './scripts/orchestrate.py --help' to see available commands"
    echo "  4. Run './scripts/orchestrate.py health' to check repository health"
    echo
    log_info "Ready to orchestrate!"
}

# Run main function
main "$@"