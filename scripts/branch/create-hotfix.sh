#!/bin/bash
# scripts/branch/create-hotfix.sh
# Create hotfix branches for emergency fixes

set -e

HOTFIX_NAME=${1:-}
TARGET_VERSION=${2:-latest}  # Version to hotfix or 'latest'
REPOS=${3:-all}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
    echo "Usage: $0 <hotfix-name> [target-version] [repos]"
    echo "Example: $0 security-patch v1.2.0 backend"
    echo "Example: $0 critical-fix latest all"
    exit 1
}

if [ -z "$HOTFIX_NAME" ]; then
    usage
fi

# Get the tag to base hotfix on
get_hotfix_base() {
    local repo=$1
    local version=$2
    
    cd "repos/$repo"
    
    if [ "$version" = "latest" ]; then
        # Get latest tag
        git describe --tags --abbrev=0 2>/dev/null || echo "main"
    else
        # Verify tag exists
        if git rev-parse "$version" >/dev/null 2>&1; then
            echo "$version"
        else
            echo -e "${RED}Tag $version not found in $repo${NC}" >&2
            echo "main"
        fi
    fi
    
    cd - > /dev/null
}

# Create hotfix branch
create_hotfix_branch() {
    local repo=$1
    local hotfix=$2
    local base_tag=$3
    
    echo -e "${YELLOW}Creating hotfix in $repo from $base_tag...${NC}"
    
    cd "repos/$repo"
    
    # Fetch latest
    git fetch origin --tags
    
    # Create hotfix branch
    git checkout -b "hotfix/$hotfix" "$base_tag"
    
    # Push to origin
    git push -u origin "hotfix/$hotfix"
    
    # Set up PR/MR template
    cat > .github/pull_request_template.md << EOF
## Hotfix: $hotfix

### Issue
Brief description of the critical issue being fixed

### Solution
Description of the fix

### Testing
- [ ] Tested locally
- [ ] Regression tests pass
- [ ] Smoke tests pass

### Rollback Plan
Steps to rollback if this hotfix causes issues

---
**This is a hotfix branch targeting $base_tag**
EOF
    
    git add .github/pull_request_template.md 2>/dev/null || true
    git commit -m "hotfix: Add PR template for $hotfix" 2>/dev/null || true
    
    cd - > /dev/null
    
    echo -e "${GREEN}✓ Hotfix branch created in $repo${NC}"
}

# Load repositories
get_repositories() {
    if [ "$REPOS" = "all" ]; then
        yq e '.repositories | keys | .[]' configs/repositories.yaml 2>/dev/null || \
        python3 -c "import yaml; print('\n'.join(yaml.safe_load(open('configs/repositories.yaml'))['repositories'].keys()))"
    else
        echo "$REPOS" | tr ',' '\n'
    fi
}

# Main execution
echo -e "${RED}═══ HOTFIX CREATION ═══${NC}"
echo -e "Hotfix: $HOTFIX_NAME"
echo -e "Target: $TARGET_VERSION"
echo

repos_list=$(get_repositories)

for repo in $repos_list; do
    if [ -d "repos/$repo" ]; then
        base=$(get_hotfix_base "$repo" "$TARGET_VERSION")
        create_hotfix_branch "$repo" "$HOTFIX_NAME" "$base"
    else
        echo -e "${YELLOW}Skipping $repo - not cloned${NC}"
    fi
done

# Create hotfix tracking
mkdir -p .octo/hotfixes
cat > ".octo/hotfixes/$HOTFIX_NAME.yaml" << EOF
hotfix:
  name: $HOTFIX_NAME
  target_version: $TARGET_VERSION
  created: $(date -Iseconds)
  repositories:
$(for repo in $repos_list; do
    base=$(get_hotfix_base "$repo" "$TARGET_VERSION" 2>/dev/null)
    echo "    - repo: $repo"
    echo "      base: $base"
done)
  status: in_progress
  priority: high
EOF

echo
echo -e "${RED}Hotfix branches created!${NC}"
echo "Next steps:"
echo "  1. Apply fixes to hotfix branches"
echo "  2. Test thoroughly"
echo "  3. Create PRs/MRs to merge back"
echo "  4. Deploy hotfix releases"