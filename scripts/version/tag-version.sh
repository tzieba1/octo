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

