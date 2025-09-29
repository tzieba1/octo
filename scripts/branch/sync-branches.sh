#!/bin/bash
# scripts/branch/sync-branches.sh
# Synchronize branches across multiple repositories

set -e

BRANCH_NAME=${1:-}
ACTION=${2:-pull}  # pull, push, or merge
SOURCE_REPO=${3:-}

usage() {
    echo "Usage: $0 <branch-name> [pull|push|merge] [source-repo]"
    echo "Example: $0 feature/new-api pull"
    echo "Example: $0 develop merge backend"
    exit 1
}

if [ -z "$BRANCH_NAME" ]; then
    usage
fi

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Get repositories
get_repositories() {
    yq e '.repositories | keys | .[]' configs/repositories.yaml 2>/dev/null || \
    python3 -c "import yaml; print('\n'.join(yaml.safe_load(open('configs/repositories.yaml'))['repositories'].keys()))"
}

# Sync branch in repository
sync_branch() {
    local repo=$1
    local branch=$2
    local action=$3
    local source=$4
    
    echo -e "${GREEN}Syncing $branch in $repo...${NC}"
    
    cd "repos/$repo"
    
    # Check if branch exists
    if ! git show-ref --verify --quiet "refs/heads/$branch"; then
        echo -e "${YELLOW}  Branch $branch doesn't exist locally, fetching...${NC}"
        git fetch origin "$branch:$branch" 2>/dev/null || {
            echo -e "${RED}  Branch $branch not found in $repo${NC}"
            cd - > /dev/null
            return 1
        }
    fi
    
    git checkout "$branch"
    
    case $action in
        pull)
            echo "  Pulling latest changes..."
            git pull origin "$branch"
            ;;
        push)
            echo "  Pushing local changes..."
            git push origin "$branch"
            ;;
        merge)
            if [ -n "$source" ] && [ "$repo" != "$source" ]; then
                echo "  Merging from $source/$branch..."
                git pull "../$source" "$branch" --no-edit
                git push origin "$branch"
            else
                echo "  Merging from origin/main..."
                git fetch origin main
                git merge origin/main --no-edit
                git push origin "$branch"
            fi
            ;;
    esac
    
    cd - > /dev/null
    echo -e "${GREEN}  ✓ Synced successfully${NC}"
}

# Main execution
echo -e "${GREEN}═══ BRANCH SYNCHRONIZATION ═══${NC}"
echo "Branch: $BRANCH_NAME"
echo "Action: $ACTION"
[ -n "$SOURCE_REPO" ] && echo "Source: $SOURCE_REPO"
echo

repos_list=$(get_repositories)
success_count=0
failed_repos=""

for repo in $repos_list; do
    if [ -d "repos/$repo" ]; then
        if sync_branch "$repo" "$BRANCH_NAME" "$ACTION" "$SOURCE_REPO"; then
            ((success_count++))
        else
            failed_repos="$failed_repos $repo"
        fi
    else
        echo -e "${YELLOW}Skipping $repo - not cloned${NC}"
        failed_repos="$failed_repos $repo"
    fi
done

echo
echo -e "${GREEN}═══ SUMMARY ═══${NC}"
echo "Successful: $success_count"
[ -n "$failed_repos" ] && echo -e "${RED}Failed/Skipped:$failed_repos${NC}"