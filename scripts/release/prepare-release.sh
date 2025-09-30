#!/bin/bash
# scripts/release/prepare-release.sh
# Prepare repositories for coordinated release

set -e

VERSION=${1:-}
REPOS=${2:-all}
RELEASE_BRANCH=${3:-release/$VERSION}

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

usage() {
    echo "Usage: $0 <version> [repos] [release-branch]"
    echo "Example: $0 v2.0.0 'backend,frontend' release/v2.0.0"
    exit 1
}

if [ -z "$VERSION" ]; then
    usage
fi

# Ensure version format
[[ "$VERSION" =~ ^v ]] || VERSION="v$VERSION"

# Get repositories
get_repositories() {
    if [ "$REPOS" = "all" ]; then
        python3 -c "import yaml; print('\n'.join(yaml.safe_load(open('configs/repositories.yaml'))['repositories'].keys()))"
    else
        echo "$REPOS" | tr ',' '\n'
    fi
}

# Prepare single repository
prepare_repository() {
    local repo=$1
    local version=$2
    local branch=$3
    
    echo -e "${BLUE}Preparing $repo for release $version...${NC}"
    
    cd "repos/$repo"
    
    # Create release branch
    git fetch origin
    git checkout -b "$branch" origin/main
    
    # Update version files
    if [ -f package.json ]; then
        jq ".version = \"${version#v}\"" package.json > tmp.json && mv tmp.json package.json
        git add package.json
    fi
    
    if [ -f setup.py ]; then
        sed -i "s/version='[^']*'/version='${version#v}'/" setup.py
        git add setup.py
    fi
    
    # Update CHANGELOG
    if [ -f CHANGELOG.md ]; then
        {
            echo "## $version - $(date +%Y-%m-%d)"
            echo
            echo "### Release Notes"
            echo "* Prepared for release"
            echo
            cat CHANGELOG.md
        } > CHANGELOG.tmp && mv CHANGELOG.tmp CHANGELOG.md
        git add CHANGELOG.md
    fi
    
    # Commit changes
    git commit -m "chore: prepare release $version" || true
    
    # Push release branch
    git push -u origin "$branch"
    
    cd - > /dev/null
    
    echo -e "${GREEN}✓ $repo prepared${NC}"
}

# Create release plan
create_release_plan() {
    cat > ".octo/releases/$VERSION.yaml" << EOF
release:
  version: $VERSION
  branch: $RELEASE_BRANCH
  created: $(date -Iseconds)
  status: preparing
  repositories:
$(for repo in $1; do
    echo "    - name: $repo"
    echo "      status: pending"
    echo "      branch: $RELEASE_BRANCH"
done)
  checklist:
    - task: version_bump
      status: pending
    - task: changelog_update
      status: pending
    - task: dependency_update
      status: pending
    - task: tests_pass
      status: pending
    - task: documentation_update
      status: pending
    - task: release_notes
      status: pending
EOF
}

# Main execution
echo -e "${GREEN}═══ RELEASE PREPARATION ═══${NC}"
echo "Version: $VERSION"
echo "Branch: $RELEASE_BRANCH"
echo

repos_list=$(get_repositories)

# Create release tracking
mkdir -p .octo/releases
create_release_plan "$repos_list"

# Prepare each repository
for repo in $repos_list; do
    if [ -d "repos/$repo" ]; then
        prepare_repository "$repo" "$VERSION" "$RELEASE_BRANCH"
    else
        echo -e "${YELLOW}Warning: $repo not cloned${NC}"
    fi
done

echo
echo -e "${GREEN}Release preparation complete!${NC}"
echo "Next steps:"
echo "  1. Review and test release branches"
echo "  2. Update dependencies between repositories"
echo "  3. Run: ./scripts/release/coordinate-release.sh $VERSION"