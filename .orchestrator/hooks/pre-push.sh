#!/bin/bash
# hooks/pre-push
# Pre-push hook for dependency and release checks

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

remote="$1"
url="$2"

echo "Running pre-push checks..."

# Check for dependency updates needed
python3 -c "
import yaml

with open('configs/repositories.yaml') as f:
    config = yaml.safe_load(f)

# Check if dependencies are synchronized
issues = []
for repo_name, repo_config in config['repositories'].items():
    for dep in repo_config.get('dependencies', []):
        dep_repo = config['repositories'].get(dep['name'])
        if dep_repo:
            # Simple check - can be enhanced
            if '^' in dep['version']:
                required_major = dep['version'].split('.')[0][1:]
                actual_major = dep_repo['version'].split('.')[0]
                if required_major != actual_major:
                    issues.append(f'{repo_name} requires {dep['name']} ^{required_major}.x but actual is {dep_repo['version']}')

if issues:
    print('${YELLOW}Warning: Dependency mismatches detected:${NC}')
    for issue in issues:
        print(f'  - {issue}')
" 2>/dev/null || true

# Check for unreleased changes
current_branch=$(git branch --show-current)
if [[ "$current_branch" == release/* ]]; then
    echo -e "${YELLOW}Pushing release branch - ensure release process is followed${NC}"
fi

# Validate CI/CD workflows
if [ -d .github/workflows ]; then
    for workflow in .github/workflows/*.yml; do
        if [ -f "$workflow" ]; then
            python3 -c "import yaml; yaml.safe_load(open('$workflow'))" 2>/dev/null || {
                echo -e "${RED}Invalid YAML in $workflow${NC}"
                exit 1
            }
        fi
    done
fi

echo -e "${GREEN}Pre-push checks completed!${NC}"