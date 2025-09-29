#!/bin/bash
# scripts/release/coordinate-release.sh
# Coordinate multi-repository release

set -e

VERSION=${1:-}
DRY_RUN=${2:-true}

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

usage() {
    echo "Usage: $0 <version> [dry-run]"
    echo "Example: $0 v2.0.0 false"
    exit 1
}

if [ -z "$VERSION" ]; then
    usage
fi

# Load release plan
load_release_plan() {
    if [ ! -f ".orchestrator/releases/$VERSION.yaml" ]; then
        echo -e "${RED}Release plan for $VERSION not found${NC}"
        echo "Run prepare-release.sh first"
        exit 1
    fi
    
    python3 -c "
import yaml
with open('.orchestrator/releases/$VERSION.yaml') as f:
    data = yaml.safe_load(f)
    for repo in data['release']['repositories']:
        print(repo['name'])
"
}

# Run release checks
run_release_checks() {
    local repo=$1
    
    echo -e "${BLUE}Running release checks for $repo...${NC}"
    
    cd "repos/$repo"
    
    # Check for uncommitted changes
    if [ -n "$(git status --porcelain)" ]; then
        echo -e "  ${RED}✗ Uncommitted changes detected${NC}"
        return 1
    fi
    
    # Run tests if available
    if [ -f package.json ] && grep -q '"test"' package.json; then
        echo "  Running tests..."
        npm test > /dev/null 2>&1 && echo -e "  ${GREEN}✓ Tests passed${NC}" || {
            echo -e "  ${RED}✗ Tests failed${NC}"
            return 1
        }
    fi
    
    if [ -f setup.py ] && [ -f pytest.ini ]; then
        echo "  Running Python tests..."
        python -m pytest > /dev/null 2>&1 && echo -e "  ${GREEN}✓ Tests passed${NC}" || {
            echo -e "  ${RED}✗ Tests failed${NC}"
            return 1
        }
    fi
    
    cd - > /dev/null
    return 0
}

# Execute release
execute_release() {
    local repo=$1
    local version=$2
    local dry_run=$3
    
    echo -e "${BLUE}Releasing $repo at $version...${NC}"
    
    cd "repos/$repo"
    
    if [ "$dry_run" = "true" ]; then
        echo -e "  ${YELLOW}[DRY RUN] Would execute:${NC}"
        echo "    - Merge release branch to main"
        echo "    - Create tag $version"
        echo "    - Push tag and main branch"
        echo "    - Create GitHub release"
    else
        # Merge release branch
        git checkout main
        git pull origin main
        git merge "release/$version" --no-ff -m "chore: release $version"
        
        # Create tag
        git tag -a "$version" -m "Release $version"
        
        # Push changes
        git push origin main
        git push origin "$version"
        
        # Create release if gh is available
        if command -v gh &> /dev/null; then
            gh release create "$version" \
                --title "Release $version" \
                --generate-notes
        fi
    fi
    
    cd - > /dev/null
    
    echo -e "${GREEN}✓ $repo released${NC}"
}

# Update release tracking
update_release_status() {
    local version=$1
    local status=$2
    
    python3 << EOF
import yaml
from datetime import datetime

with open('.orchestrator/releases/$version.yaml', 'r') as f:
    data = yaml.safe_load(f)

data['release']['status'] = '$status'
data['release']['completed'] = datetime.now().isoformat()

with open('.orchestrator/releases/$version.yaml', 'w') as f:
    yaml.dump(data, f, default_flow_style=False)
EOF
}

# Main execution
echo -e "${GREEN}═══ COORDINATED RELEASE ═══${NC}"
echo "Version: $VERSION"
echo "Dry Run: $DRY_RUN"
echo

# Load repositories from release plan
repos_list=$(load_release_plan)

# Phase 1: Pre-release checks
echo -e "${BLUE}Phase 1: Pre-release checks${NC}"
all_checks_pass=true
for repo in $repos_list; do
    if ! run_release_checks "$repo"; then
        all_checks_pass=false
    fi
done

if [ "$all_checks_pass" = false ]; then
    echo
    echo -e "${RED}Pre-release checks failed!${NC}"
    echo "Fix issues and try again"
    exit 1
fi

echo
echo -e "${GREEN}All pre-release checks passed!${NC}"

# Phase 2: Execute releases
echo
echo -e "${BLUE}Phase 2: Execute releases${NC}"

# Determine release order based on dependencies
python3 << EOF
import yaml
from collections import defaultdict

# Load repository config
with open('configs/repositories.yaml') as f:
    config = yaml.safe_load(f)

# Build dependency graph
deps = defaultdict(list)
for repo, data in config['repositories'].items():
    for dep in data.get('dependencies', []):
        deps[dep['name']].append(repo)

# Topological sort for release order
visited = set()
order = []

def visit(repo):
    if repo in visited:
        return
    visited.add(repo)
    for dependent in deps.get(repo, []):
        visit(dependent)
    order.insert(0, repo)

for repo in config['repositories']:
    visit(repo)

for repo in order:
    print(repo)
EOF > /tmp/release_order.txt

# Execute releases in order
while read -r repo; do
    if echo "$repos_list" | grep -q "^$repo$"; then
        execute_release "$repo" "$VERSION" "$DRY_RUN"
    fi
done < /tmp/release_order.txt

# Update status
if [ "$DRY_RUN" = "false" ]; then
    update_release_status "$VERSION" "completed"
fi

echo
echo -e "${GREEN}═══ RELEASE COMPLETE ═══${NC}"
if [ "$DRY_RUN" = "true" ]; then
    echo -e "${YELLOW}This was a dry run. To execute:${NC}"
    echo "  $0 $VERSION false"
fi