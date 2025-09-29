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