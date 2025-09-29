#!/bin/bash
# scripts/deps/update-cross-deps.sh
# Update cross-repository dependencies

set -e

SOURCE_REPO=${1:-}
NEW_VERSION=${2:-}

usage() {
    echo "Usage: $0 <source-repo> <new-version>"
    echo "Example: $0 shared-lib v2.0.0"
    exit 1
}

if [ -z "$SOURCE_REPO" ] || [ -z "$NEW_VERSION" ]; then
    usage
fi

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Updating dependencies on $SOURCE_REPO to $NEW_VERSION${NC}"

# Find dependent repositories
python3 << EOF
import yaml
import json
import subprocess

# Load config
with open('configs/repositories.yaml') as f:
    config = yaml.safe_load(f)

# Find dependents
dependents = []
for repo_name, repo_config in config['repositories'].items():
    for dep in repo_config.get('dependencies', []):
        if dep['name'] == '$SOURCE_REPO':
            dependents.append({
                'repo': repo_name,
                'current_spec': dep['version']
            })

if not dependents:
    print("No repositories depend on $SOURCE_REPO")
    exit(0)

print(f"Found {len(dependents)} dependent repositories:")

for dep in dependents:
    print(f"  - {dep['repo']}: {dep['current_spec']}")
    
    # Update the dependency version
    repo_path = f"repos/{dep['repo']}"
    
    # Update package.json if exists
    pkg_file = f"{repo_path}/package.json"
    try:
        with open(pkg_file) as f:
            pkg = json.load(f)
        
        if 'dependencies' in pkg and '$SOURCE_REPO' in pkg['dependencies']:
            pkg['dependencies']['$SOURCE_REPO'] = '^$NEW_VERSION'
            
            with open(pkg_file, 'w') as f:
                json.dump(pkg, f, indent=2)
            
            print(f"    ✓ Updated package.json")
            
            # Commit the change
            subprocess.run([
                'git', '-C', repo_path, 'add', 'package.json'
            ])
            subprocess.run([
                'git', '-C', repo_path, 'commit', '-m',
                f'chore: update {SOURCE_REPO} to {NEW_VERSION}'
            ])
    except FileNotFoundError:
        pass

# Update orchestrator config
config['repositories']['$SOURCE_REPO']['version'] = '${NEW_VERSION#v}'

with open('configs/repositories.yaml', 'w') as f:
    yaml.dump(config, f, default_flow_style=False)

print("\n✓ Orchestrator configuration updated")
EOF

echo
echo -e "${GREEN}Dependencies updated successfully!${NC}"