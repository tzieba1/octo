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

