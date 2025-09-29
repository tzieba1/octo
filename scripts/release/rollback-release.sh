#!/bin/bash
# scripts/release/rollback-release.sh
# Emergency rollback procedure

set -e

VERSION=${1:-}
TARGET_VERSION=${2:-}
REPOS=${3:-all}

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

usage() {
    echo "Usage: $0 <current-version> <target-version> [repos]"
    echo "Example: $0 v2.0.1 v2.0.0 'backend,frontend'"
    exit 1
}

if [ -z "$VERSION" ] || [ -z "$TARGET_VERSION" ]; then
    usage
fi

echo -e "${RED}╔════════════════════════════════════╗${NC}"
echo -e "${RED}║        EMERGENCY ROLLBACK          ║${NC}"
echo -e "${RED}╚════════════════════════════════════╝${NC}"
echo
echo -e "${YELLOW}⚠️  WARNING: This will rollback production!${NC}"
echo "Current Version: $VERSION"
echo "Target Version: $TARGET_VERSION"
echo

read -p "Are you sure you want to proceed? Type 'ROLLBACK' to confirm: " confirm
if [ "$confirm" != "ROLLBACK" ]; then
    echo "Rollback cancelled"
    exit 0
fi

# Get repositories
get_repositories() {
    if [ "$REPOS" = "all" ]; then
        python3 -c "import yaml; print('\n'.join(yaml.safe_load(open('configs/repositories.yaml'))['repositories'].keys()))"
    else
        echo "$REPOS" | tr ',' '\n'
    fi
}

# Perform rollback
rollback_repository() {
    local repo=$1
    local target=$2
    
    echo -e "${YELLOW}Rolling back $repo to $target...${NC}"
    
    cd "repos/$repo"
    
    # Create rollback branch
    git checkout -b "rollback-$(date +%Y%m%d-%H%M%S)" "$target"
    
    # Force update main (dangerous!)
    git checkout main
    git reset --hard "$target"
    
    # Push forced update
    echo -e "${RED}Force pushing to main...${NC}"
    git push --force-with-lease origin main
    
    # Tag the rollback
    git tag -a "rollback-from-$VERSION" -m "Rollback from $VERSION to $TARGET_VERSION"
    git push origin "rollback-from-$VERSION"
    
    cd - > /dev/null
    
    echo -e "${GREEN}✓ $repo rolled back${NC}"
}

# Create rollback record
create_rollback_record() {
    mkdir -p .orchestrator/rollbacks
    cat > ".orchestrator/rollbacks/$(date +%Y%m%d-%H%M%S).yaml" << EOF
rollback:
  from_version: $VERSION
  to_version: $TARGET_VERSION
  timestamp: $(date -Iseconds)
  reason: "Emergency rollback"
  repositories:
$(for repo in $1; do echo "    - $repo"; done)
  performed_by: $(git config user.name)
EOF
}

# Main execution
repos_list=$(get_repositories)

echo
echo -e "${RED}Starting rollback...${NC}"

# Record pre-rollback state
git stash create "pre-rollback-$VERSION" > /dev/null

# Perform rollbacks
for repo in $repos_list; do
    if [ -d "repos/$repo" ]; then
        rollback_repository "$repo" "$TARGET_VERSION"
    else
        echo -e "${YELLOW}Warning: $repo not found locally${NC}"
    fi
done

# Create rollback record
create_rollback_record "$repos_list"

echo
echo -e "${RED}═══ ROLLBACK COMPLETE ═══${NC}"
echo "Actions taken:"
echo "  - Rolled back to version $TARGET_VERSION"
echo "  - Created rollback tags"
echo "  - Recorded rollback in orchestrator"
echo
echo -e "${YELLOW}Post-rollback tasks:${NC}"
echo "  1. Verify services are running correctly"
echo "  2. Check monitoring dashboards"
echo "  3. Notify team of rollback"
echo "  4. Create incident report"