#!/bin/bash
# scripts/branch/create-feature.sh
# Create synchronized feature branches across repositories

set -e

FEATURE_NAME=${1:-}
BASE_BRANCH=${2:-main}
REPOS=${3:-all}  # Can be "all" or comma-separated list

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

usage() {
    echo "Usage: $0 <feature-name> [base-branch] [repos]"
    echo "Example: $0 new-auth-system main 'backend,frontend'"
    echo "Example: $0 bugfix-123 develop all"
    exit 1
}

if [ -z "$FEATURE_NAME" ]; then
    usage
fi

# Load repositories from config
get_repositories() {
    if [ "$REPOS" = "all" ]; then
        yq e '.repositories | keys | .[]' configs/repositories.yaml 2>/dev/null || \
        python3 -c "import yaml; print('\n'.join(yaml.safe_load(open('configs/repositories.yaml'))['repositories'].keys()))"
    else
        echo "$REPOS" | tr ',' '\n'
    fi
}

# Create feature branch in repository
create_feature_branch() {
    local repo=$1
    local feature=$2
    local base=$3
    
    echo -e "${GREEN}Creating feature branch in $repo...${NC}"
    
    if [ ! -d "repos/$repo" ]; then
        echo -e "${YELLOW}Warning: $repo not cloned locally${NC}"
        return 1
    fi
    
    cd "repos/$repo"
    
    # Fetch latest
    git fetch origin
    
    # Check if branch already exists
    if git show-ref --verify --quiet "refs/heads/feature/$feature"; then
        echo -e "${YELLOW}Branch feature/$feature already exists in $repo${NC}"
        return 1
    fi
    
    # Create and checkout new branch
    git checkout -b "feature/$feature" "origin/$base"
    
    # Push to origin
    git push -u origin "feature/$feature"
    
    cd - > /dev/null
    
    echo -e "${GREEN}✓ Created feature/$feature in $repo${NC}"
}

# Main execution
echo -e "${GREEN}Creating feature branches for: $FEATURE_NAME${NC}"
echo -e "Base branch: $BASE_BRANCH"
echo

# Get list of repositories
repos_list=$(get_repositories)

# Track success and failures
success_count=0
failed_repos=""

# Create branches
for repo in $repos_list; do
    if create_feature_branch "$repo" "$FEATURE_NAME" "$BASE_BRANCH"; then
        ((success_count++))
    else
        failed_repos="$failed_repos $repo"
    fi
done

# Create orchestration tracking
echo
echo -e "${GREEN}Creating orchestration tracking...${NC}"

git checkout -b "orchestrate/feature-$FEATURE_NAME" 2>/dev/null || \
git checkout "orchestrate/feature-$FEATURE_NAME"

# Create tracking file
cat > ".orchestrator/features/$FEATURE_NAME.yaml" << EOF
feature:
  name: $FEATURE_NAME
  base: $BASE_BRANCH
  created: $(date -Iseconds)
  repositories:
$(for repo in $repos_list; do echo "    - $repo"; done)
  status: active
EOF

mkdir -p .orchestrator/features
git add ".orchestrator/features/$FEATURE_NAME.yaml"
git commit -m "orchestration: Start feature $FEATURE_NAME" || true

echo
echo -e "${GREEN}Feature branch creation complete!${NC}"
echo "  Successful: $success_count"
[ -n "$failed_repos" ] && echo -e "  ${RED}Failed: $failed_repos${NC}"