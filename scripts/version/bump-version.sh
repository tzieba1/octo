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

#!/bin/bash
# scripts/version/create-release.sh
# Create GitHub release from tag

set -e

REPO=${1:-}
TAG=${2:-}
NOTES_FILE=${3:-}

usage() {
    echo "Usage: $0 <repository> <tag> [notes-file]"
    echo "Example: $0 backend v1.2.0 CHANGELOG.md"
    exit 1
}

if [ -z "$REPO" ] || [ -z "$TAG" ]; then
    usage
fi

cd "repos/$REPO"

# Generate release notes if not provided
if [ -z "$NOTES_FILE" ]; then
    echo "## What's Changed" > release_notes.md
    
    # Get commits since last tag
    PREV_TAG=$(git describe --tags --abbrev=0 "$TAG^" 2>/dev/null || echo "")
    
    if [ -n "$PREV_TAG" ]; then
        git log "${PREV_TAG}..${TAG}" --pretty=format:"* %s (%h)" >> release_notes.md
    else
        git log "$TAG" --pretty=format:"* %s (%h)" >> release_notes.md
    fi
    
    NOTES_FILE="release_notes.md"
fi

# Check if GitHub CLI is available
if command -v gh &> /dev/null; then
    gh release create "$TAG" \
        --title "Release $TAG" \
        --notes-file "$NOTES_FILE" \
        --target main
    
    echo "Release $TAG created successfully!"
else
    echo "GitHub CLI not found. Please create release manually."
    echo "Tag $TAG has been created and pushed."
fi

# Clean up
[ -f release_notes.md ] && rm release_notes.md

---

#!/bin/bash
# scripts/version/tag-version.sh
# Create and push git tags

set -e

REPO=${1:-}
VERSION=${2:-}
MESSAGE=${3:-"Release $VERSION"}

usage() {
    echo "Usage: $0 <repository> <version> [message]"
    echo "Example: $0 backend v1.2.0 'Feature release'"
    exit 1
}

if [ -z "$REPO" ] || [ -z "$VERSION" ]; then
    usage
fi

cd "repos/$REPO"

# Ensure version starts with 'v'
[[ "$VERSION" =~ ^v ]] || VERSION="v$VERSION"

# Create annotated tag
git tag -a "$VERSION" -m "$MESSAGE"

echo "Tag $VERSION created in $REPO"

# Ask to push
read -p "Push tag to origin? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    git push origin "$VERSION"
    echo "Tag pushed successfully!"
fi

---

#!/bin/bash
# scripts/version/changelog.sh
# Generate changelog from git history

set -e

REPO=${1:-}
OUTPUT=${2:-CHANGELOG.md}
FROM_TAG=${3:-}
TO_TAG=${4:-HEAD}

usage() {
    echo "Usage: $0 <repository> [output-file] [from-tag] [to-tag]"
    echo "Example: $0 backend CHANGELOG.md v1.0.0 v1.1.0"
    exit 1
}

if [ -z "$REPO" ]; then
    usage
fi

cd "repos/$REPO"

# Header
{
    echo "# Changelog"
    echo
    echo "All notable changes to this project will be documented in this file."
    echo
} > "$OUTPUT"

# Get all tags
tags=($(git tag -l --sort=-v:refname))

# Generate changelog entries
for i in "${!tags[@]}"; do
    tag="${tags[$i]}"
    prev_tag="${tags[$((i+1))]:-}"
    
    echo "## $tag - $(git log -1 --format=%ai "$tag" | cut -d ' ' -f1)" >> "$OUTPUT"
    echo >> "$OUTPUT"
    
    # Categorize commits
    echo "### Added" >> "$OUTPUT"
    git log "${prev_tag:+$prev_tag..}$tag" --grep="^feat" --pretty=format:"- %s" >> "$OUTPUT" || true
    echo >> "$OUTPUT"
    
    echo "### Changed" >> "$OUTPUT"
    git log "${prev_tag:+$prev_tag..}$tag" --grep="^refactor\|^perf" --pretty=format:"- %s" >> "$OUTPUT" || true
    echo >> "$OUTPUT"
    
    echo "### Fixed" >> "$OUTPUT"
    git log "${prev_tag:+$prev_tag..}$tag" --grep="^fix" --pretty=format:"- %s" >> "$OUTPUT" || true
    echo >> "$OUTPUT"
    
    echo "### Security" >> "$OUTPUT"
    git log "${prev_tag:+$prev_tag..}$tag" --grep="^security" --pretty=format:"- %s" >> "$OUTPUT" || true
    echo >> "$OUTPUT"
    
    # Add separator
    echo "---" >> "$OUTPUT"
    echo >> "$OUTPUT"
done

echo "Changelog generated: $OUTPUT"