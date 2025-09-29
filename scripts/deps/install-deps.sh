#!/bin/bash
# scripts/deps/install-deps.sh
# Install dependencies for all repositories

set -e

REPOS=${1:-all}
ENV=${2:-development}  # development or production

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get repositories
get_repositories() {
    if [ "$REPOS" = "all" ]; then
        python3 -c "import yaml; print(' '.join(yaml.safe_load(open('configs/repositories.yaml'))['repositories'].keys()))"
    else
        echo "$REPOS" | tr ',' ' '
    fi
}

# Install for a single repository
install_repository_deps() {
    local repo=$1
    local env=$2
    
    echo -e "${BLUE}Installing dependencies for $repo...${NC}"
    
    if [ ! -d "repos/$repo" ]; then
        echo -e "${YELLOW}  Repository not cloned, skipping${NC}"
        return
    fi
    
    cd "repos/$repo"
    
    # Node.js projects
    if [ -f package.json ]; then
        echo "  Installing npm packages..."
        if [ "$env" = "production" ]; then
            npm ci --production
        else
            npm install
        fi
    fi
    
    # Python projects
    if [ -f requirements.txt ]; then
        echo "  Installing Python packages..."
        pip install -r requirements.txt
        
        if [ "$env" = "development" ] && [ -f requirements-dev.txt ]; then
            pip install -r requirements-dev.txt
        fi
    fi
    
    # Go projects
    if [ -f go.mod ]; then
        echo "  Installing Go modules..."
        go mod download
    fi
    
    # Ruby projects
    if [ -f Gemfile ]; then
        echo "  Installing Ruby gems..."
        if [ "$env" = "production" ]; then
            bundle install --without development test
        else
            bundle install
        fi
    fi
    
    cd - > /dev/null
    
    echo -e "${GREEN}  ✓ Dependencies installed${NC}"
}

# Main execution
echo -e "${GREEN}═══ DEPENDENCY INSTALLATION ═══${NC}"
echo "Environment: $ENV"
echo

repos_list=$(get_repositories)

for repo in $repos_list; do
    install_repository_deps "$repo" "$ENV"
done

echo
echo -e "${GREEN}All dependencies installed!${NC}"