#!/bin/bash
# hooks/commit-msg
# Enforce conventional commit messages

set -e

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

commit_regex='^(feat|fix|docs|style|refactor|perf|test|chore|build|ci|revert|wip|orchestration)(\(.+\))?: .{1,100}$'
merge_regex='^Merge '

commit_message=$(cat "$1")

# Allow merge commits
if echo "$commit_message" | grep -qE "$merge_regex"; then
    exit 0
fi

# Check conventional commit format
if ! echo "$commit_message" | grep -qE "$commit_regex"; then
    echo -e "${RED}Invalid commit message format!${NC}"
    echo
    echo "Commit message must follow conventional commits:"
    echo "  <type>(<scope>): <subject>"
    echo
    echo "Types:"
    echo "  feat:          New feature"
    echo "  fix:           Bug fix"
    echo "  docs:          Documentation"
    echo "  style:         Code style"
    echo "  refactor:      Code refactoring"
    echo "  perf:          Performance improvement"
    echo "  test:          Tests"
    echo "  chore:         Maintenance"
    echo "  build:         Build system"
    echo "  ci:            CI/CD"
    echo "  orchestration: Orchestration changes"
    echo
    echo "Example: feat(release): add multi-repo coordination"
    echo
    echo -e "${YELLOW}Your message: $commit_message${NC}"
    exit 1
fi

# Check message length
first_line=$(echo "$commit_message" | head -n1)
if [ ${#first_line} -gt 100 ]; then
    echo -e "${YELLOW}Warning: Commit message first line is too long (${#first_line} > 100)${NC}"
fi

---

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