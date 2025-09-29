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

#!/bin/bash
# scripts/deps/install-deps.sh
# Install dependencies for all repositories

set -e

REPOS=${1:-all}
ENV=${2:-development}  # development or production

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get repositories
get_repositories() {
    if [ "$REPOS" = "all" ]; then
        python3 -c "import yaml; print(' '.join(yaml.safe_load(open('configs/repositories.yaml'))['repositories'].keys()))"
    else
        echo "$REPOS" | tr ',' ' '
    fi
}

# Install for a single repository
install_repository_deps() {
    local repo=$1
    local env=$2
    
    echo -e "${BLUE}Installing dependencies for $repo...${NC}"
    
    if [ ! -d "repos/$repo" ]; then
        echo -e "${YELLOW}  Repository not cloned, skipping${NC}"
        return
    fi
    
    cd "repos/$repo"
    
    # Node.js projects
    if [ -f package.json ]; then
        echo "  Installing npm packages..."
        if [ "$env" = "production" ]; then
            npm ci --production
        else
            npm install
        fi
    fi
    
    # Python projects
    if [ -f requirements.txt ]; then
        echo "  Installing Python packages..."
        pip install -r requirements.txt
        
        if [ "$env" = "development" ] && [ -f requirements-dev.txt ]; then
            pip install -r requirements-dev.txt
        fi
    fi
    
    # Go projects
    if [ -f go.mod ]; then
        echo "  Installing Go modules..."
        go mod download
    fi
    
    # Ruby projects
    if [ -f Gemfile ]; then
        echo "  Installing Ruby gems..."
        if [ "$env" = "production" ]; then
            bundle install --without development test
        else
            bundle install
        fi
    fi
    
    cd - > /dev/null
    
    echo -e "${GREEN}  ✓ Dependencies installed${NC}"
}

# Main execution
echo -e "${GREEN}═══ DEPENDENCY INSTALLATION ═══${NC}"
echo "Environment: $ENV"
echo

repos_list=$(get_repositories)

for repo in $repos_list; do
    install_repository_deps "$repo" "$ENV"
done

echo
echo -e "${GREEN}All dependencies installed!${NC}"

---

#!/bin/bash
# scripts/deps/update-cross-deps.sh
# Update cross-repository dependencies

set -e

SOURCE_REPO=${1:-}
NEW_VERSION=${2:-}

usage() {
    echo "Usage: $0 <source-repo> <new-version>"
    echo "Example: $0 shared-lib v2.0.0"
    exit 1
}

if [ -z "$SOURCE_REPO" ] || [ -z "$NEW_VERSION" ]; then
    usage
fi

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Updating dependencies on $SOURCE_REPO to $NEW_VERSION${NC}"

# Find dependent repositories
python3 << EOF
import yaml
import json
import subprocess

# Load config
with open('configs/repositories.yaml') as f:
    config = yaml.safe_load(f)

# Find dependents
dependents = []
for repo_name, repo_config in config['repositories'].items():
    for dep in repo_config.get('dependencies', []):
        if dep['name'] == '$SOURCE_REPO':
            dependents.append({
                'repo': repo_name,
                'current_spec': dep['version']
            })

if not dependents:
    print("No repositories depend on $SOURCE_REPO")
    exit(0)

print(f"Found {len(dependents)} dependent repositories:")

for dep in dependents:
    print(f"  - {dep['repo']}: {dep['current_spec']}")
    
    # Update the dependency version
    repo_path = f"repos/{dep['repo']}"
    
    # Update package.json if exists
    pkg_file = f"{repo_path}/package.json"
    try:
        with open(pkg_file) as f:
            pkg = json.load(f)
        
        if 'dependencies' in pkg and '$SOURCE_REPO' in pkg['dependencies']:
            pkg['dependencies']['$SOURCE_REPO'] = '^$NEW_VERSION'
            
            with open(pkg_file, 'w') as f:
                json.dump(pkg, f, indent=2)
            
            print(f"    ✓ Updated package.json")
            
            # Commit the change
            subprocess.run([
                'git', '-C', repo_path, 'add', 'package.json'
            ])
            subprocess.run([
                'git', '-C', repo_path, 'commit', '-m',
                f'chore: update {SOURCE_REPO} to {NEW_VERSION}'
            ])
    except FileNotFoundError:
        pass

# Update orchestrator config
config['repositories']['$SOURCE_REPO']['version'] = '${NEW_VERSION#v}'

with open('configs/repositories.yaml', 'w') as f:
    yaml.dump(config, f, default_flow_style=False)

print("\n✓ Orchestrator configuration updated")
EOF

echo
echo -e "${GREEN}Dependencies updated successfully!${NC}"