#!/bin/bash
# scripts/deps/track-dependencies.sh
# Track and manage dependencies across repositories

set -e

ACTION=${1:-status}  # status, update, lock, check
REPO=${2:-all}

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    echo "Usage: $0 [status|update|lock|check] [repo]"
    echo "Example: $0 status all"
    echo "Example: $0 update backend"
    exit 1
}

# Check dependency status
check_dependency_status() {
    local repo=$1
    
    echo -e "${BLUE}Checking dependencies for $repo...${NC}"
    
    python3 << EOF
import yaml
import json
from pathlib import Path

# Load repository config
with open('configs/repositories.yaml') as f:
    config = yaml.safe_load(f)

repo_config = config['repositories'].get('$repo')
if not repo_config:
    print(f"  Repository $repo not found")
    exit(1)

deps = repo_config.get('dependencies', [])

if not deps:
    print("  No dependencies")
else:
    for dep in deps:
        dep_name = dep['name']
        dep_version = dep['version']
        dep_type = dep.get('type', 'runtime')
        
        # Check actual version
        dep_repo_config = config['repositories'].get(dep_name)
        if dep_repo_config:
            actual_version = dep_repo_config['version']
            
            # Simple version check (can be enhanced)
            if dep_version.startswith('^'):
                required = dep_version[1:]
                if actual_version.startswith(required.split('.')[0]):
                    print(f"  ✓ {dep_name}: {dep_version} (actual: v{actual_version})")
                else:
                    print(f"  ✗ {dep_name}: {dep_version} (actual: v{actual_version}) - MISMATCH")
            else:
                print(f"  ? {dep_name}: {dep_version} (actual: v{actual_version})")
EOF
}

# Update dependencies
update_dependencies() {
    local repo=$1
    
    echo -e "${YELLOW}Updating dependencies for $repo...${NC}"
    
    cd "repos/$repo"
    
    # Update based on package manager
    if [ -f package.json ]; then
        echo "  Updating npm dependencies..."
        npm update
        npm audit fix || true
    elif [ -f requirements.txt ]; then
        echo "  Updating Python dependencies..."
        pip install --upgrade -r requirements.txt
    elif [ -f go.mod ]; then
        echo "  Updating Go dependencies..."
        go get -u ./...
        go mod tidy
    elif [ -f Gemfile ]; then
        echo "  Updating Ruby dependencies..."
        bundle update
    fi
    
    cd - > /dev/null
    
    echo -e "${GREEN}✓ Dependencies updated${NC}"
}

# Create dependency lock
create_dependency_lock() {
    echo -e "${BLUE}Creating dependency lock file...${NC}"
    
    python3 << 'EOF'
import yaml
import json
from datetime import datetime

# Load repository config
with open('configs/repositories.yaml') as f:
    config = yaml.safe_load(f)

lock = {
    'version': '1.0',
    'created': datetime.now().isoformat(),
    'repositories': {}
}

for repo_name, repo_config in config['repositories'].items():
    deps = {}
    for dep in repo_config.get('dependencies', []):
        dep_repo = config['repositories'].get(dep['name'])
        if dep_repo:
            deps[dep['name']] = {
                'version': dep['version'],
                'resolved': dep_repo['version'],
                'type': dep.get('type', 'runtime')
            }
    
    lock['repositories'][repo_name] = {
        'version': repo_config['version'],
        'dependencies': deps
    }

# Write lock file
with open('configs/dependencies.lock', 'w') as f:
    yaml.dump(lock, f, default_flow_style=False)

print("✓ Lock file created: configs/dependencies.lock")
EOF
}

# Check for dependency conflicts
check_conflicts() {
    echo -e "${BLUE}Checking for dependency conflicts...${NC}"
    
    python3 << 'EOF'
import yaml
from collections import defaultdict

# Load repository config
with open('configs/repositories.yaml') as f:
    config = yaml.safe_load(f)

# Track all dependencies
dep_versions = defaultdict(list)

for repo_name, repo_config in config['repositories'].items():
    for dep in repo_config.get('dependencies', []):
        dep_name = dep['name']
        dep_version = dep['version']
        dep_versions[dep_name].append({
            'repo': repo_name,
            'version': dep_version
        })

# Check for conflicts
conflicts = []
for dep_name, versions in dep_versions.items():
    unique_versions = set(v['version'] for v in versions)
    if len(unique_versions) > 1:
        conflicts.append({
            'dependency': dep_name,
            'versions': versions
        })

if conflicts:
    print("⚠️  Dependency conflicts detected:")
    for conflict in conflicts:
        print(f"\n  {conflict['dependency']}:")
        for v in conflict['versions']:
            print(f"    - {v['repo']}: {v['version']}")
else:
    print("✓ No dependency conflicts found")
EOF
}

# Main execution
case $ACTION in
    status)
        if [ "$REPO" = "all" ]; then
            repos=$(python3 -c "import yaml; print(' '.join(yaml.safe_load(open('configs/repositories.yaml'))['repositories'].keys()))")
            for r in $repos; do
                check_dependency_status "$r"
                echo
            done
        else
            check_dependency_status "$REPO"
        fi
        ;;
    update)
        if [ "$REPO" = "all" ]; then
            repos=$(python3 -c "import yaml; print(' '.join(yaml.safe_load(open('configs/repositories.yaml'))['repositories'].keys()))")
            for r in $repos; do
                [ -d "repos/$r" ] && update_dependencies "$r"
            done
        else
            update_dependencies "$REPO"
        fi
        ;;
    lock)
        create_dependency_lock
        ;;
    check)
        check_conflicts
        ;;
    *)
        usage
        ;;
esac

---

