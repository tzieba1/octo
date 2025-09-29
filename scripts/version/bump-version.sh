#!/bin/bash
# scripts/version/bump-version.sh
# Semantic version bumping for repositories

set -e

# Configuration
REPO=${1:-}
BUMP_TYPE=${2:-patch}  # patch, minor, major

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

usage() {
    echo "Usage: $0 <repository> <patch|minor|major>"
    echo "Example: $0 backend minor"
    exit 1
}

if [ -z "$REPO" ]; then
    usage
fi

# Get current version
get_current_version() {
    cd "repos/$REPO" 2>/dev/null || {
        echo -e "${RED}Repository $REPO not found${NC}"
        exit 1
    }
    
    git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0"
}

# Bump version
bump_version() {
    local current=$1
    local type=$2
    
    # Remove 'v' prefix if present
    current=${current#v}
    
    IFS='.' read -r major minor patch <<< "$current"
    
    case $type in
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        patch)
            patch=$((patch + 1))
            ;;
        *)
            echo "Invalid bump type: $type"
            exit 1
            ;;
    esac
    
    echo "v${major}.${minor}.${patch}"
}

# Main
current_version=$(get_current_version)
new_version=$(bump_version "$current_version" "$BUMP_TYPE")

echo -e "${GREEN}Bumping $REPO from $current_version to $new_version${NC}"

cd "repos/$REPO"

# Update version in package files
update_package_files() {
    # Update package.json if it exists
    if [ -f package.json ]; then
        jq ".version = \"${new_version#v}\"" package.json > tmp.json && mv tmp.json package.json
        git add package.json
    fi
    
    # Update setup.py if it exists
    if [ -f setup.py ]; then
        sed -i "s/version='[^']*'/version='${new_version#v}'/" setup.py
        git add setup.py
    fi
    
    # Update version.txt if it exists
    if [ -f version.txt ]; then
        echo "${new_version#v}" > version.txt
        git add version.txt
    fi
}

update_package_files

# Commit version bump
git commit -m "chore: bump version to $new_version" || true

# Create tag
git tag -a "$new_version" -m "Release $new_version"

echo -e "${GREEN}Version bumped successfully!${NC}"
echo "Run 'git push origin $new_version' to push the tag"

---

