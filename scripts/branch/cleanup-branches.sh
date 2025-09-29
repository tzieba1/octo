#!/bin/bash
# scripts/branch/cleanup-branches.sh
# Clean up stale branches across repositories

set -e

DRY_RUN=${1:-true}
DAYS_OLD=${2:-90}
EXCLUDE_PATTERN=${3:-"main|master|develop|release"}

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

usage() {
    echo "Usage: $0 [dry-run] [days-old] [exclude-pattern]"
    echo "Example: $0 false 30 'main|develop'"
    echo "Default: dry-run=true, days=90, exclude main/master/develop/release"
    exit 1
}

# Find stale branches
find_stale_branches() {
    local repo=$1
    local days=$2
    local exclude=$3
    
    cd "repos/$repo"
    
    echo -e "${GREEN}Checking $repo for stale branches...${NC}"
    
    # Get all remote branches
    git fetch --prune origin
    
    # Find branches older than specified days
    local cutoff_date=$(date -d "$days days ago" +%Y-%m-%d)
    
    stale_branches=""
    for branch in $(git for-each-ref --format='%(refname:short)' refs/remotes/origin/); do
        branch_name=${branch#origin/}
        
        # Skip excluded branches
        if echo "$branch_name" | grep -qE "$exclude"; then
            continue
        fi
        
        # Get last commit date
        last_commit=$(git log -1 --format=%ai "$branch" 2>/dev/null | cut -d' ' -f1)
        
        if [[ "$last_commit" < "$cutoff_date" ]]; then
            stale_branches="$stale_branches $branch_name"
        fi
    done
    
    cd - > /dev/null
    
    echo "$stale_branches"
}

# Delete stale branches
delete_branches() {
    local repo=$1
    local branches=$2
    local dry_run=$3
    
    if [ -z "$branches" ]; then
        echo "  No stale branches found in $repo"
        return
    fi
    
    cd "repos/$repo"
    
    for branch in $branches; do
        if [ "$dry_run" = "true" ]; then
            echo -e "  ${YELLOW}[DRY RUN]${NC} Would delete: $branch"
        else
            echo -e "  ${RED}Deleting${NC}: $branch"
            git push origin --delete "$branch" 2>/dev/null || \
                echo -e "    ${YELLOW}Failed to delete $branch${NC}"
        fi
    done
    
    cd - > /dev/null
}

# Load repositories
get_repositories() {
    yq e '.repositories | keys | .[]' configs/repositories.yaml 2>/dev/null || \
    python3 -c "import yaml; print('\n'.join(yaml.safe_load(open('configs/repositories.yaml'))['repositories'].keys()))"
}

# Main execution
echo -e "${GREEN}═══ BRANCH CLEANUP ═══${NC}"
echo "Settings:"
echo "  Dry run: $DRY_RUN"
echo "  Days old: $DAYS_OLD"
echo "  Excluding: $EXCLUDE_PATTERN"
echo

repos_list=$(get_repositories)
total_branches=0

# Collect all stale branches
cleanup_report=""
for repo in $repos_list; do
    if [ -d "repos/$repo" ]; then
        stale=$(find_stale_branches "$repo" "$DAYS_OLD" "$EXCLUDE_PATTERN")
        
        if [ -n "$stale" ]; then
            branch_count=$(echo "$stale" | wc -w)
            total_branches=$((total_branches + branch_count))
            cleanup_report="$cleanup_report\n$repo: $branch_count branches"
            
            delete_branches "$repo" "$stale" "$DRY_RUN"
        fi
    fi
done

# Summary
echo
echo -e "${GREEN}═══ CLEANUP SUMMARY ═══${NC}"
echo -e "$cleanup_report"
echo
echo "Total stale branches: $total_branches"

if [ "$DRY_RUN" = "true" ]; then
    echo
    echo -e "${YELLOW}This was a dry run. To actually delete branches, run:${NC}"
    echo "  $0 false $DAYS_OLD '$EXCLUDE_PATTERN'"
fi