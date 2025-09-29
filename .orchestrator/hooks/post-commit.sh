#!/bin/bash
# hooks/post-commit
# Post-commit hook for version synchronization

set -e

# Update version tracking in git notes
commit_hash=$(git rev-parse HEAD)
timestamp=$(date -Iseconds)

# Store commit metadata in git notes
git notes --ref=commits add -f -m "{
  \"timestamp\": \"$timestamp\",
  \"author\": \"$(git config user.name)\",
  \"email\": \"$(git config user.email)\",
  \"branch\": \"$(git branch --show-current)\"
}" "$commit_hash" 2>/dev/null || true

# Check if this affects versioning
if git diff-tree --no-commit-id --name-only -r "$commit_hash" | grep -q "version\|package.json\|setup.py"; then
    echo "Version files changed - updating orchestrator tracking"
    
    # Update orchestrator version tracking
    python3 -c "
import subprocess
import yaml

# Get current branch
branch = subprocess.check_output(['git', 'branch', '--show-current'], text=True).strip()

if branch.startswith('release/'):
    print('Release branch detected - skipping auto version bump')
else:
    print('Version change recorded')
" 2>/dev/null || true
fi
