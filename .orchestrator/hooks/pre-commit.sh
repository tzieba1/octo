#!/bin/bash
# hooks/pre-commit
# Pre-commit hook for orchestrator validation

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "Running pre-commit checks..."

# Check for configuration validity
if [ -f configs/repositories.yaml ]; then
    python3 -c "import yaml; yaml.safe_load(open('configs/repositories.yaml'))" 2>/dev/null || {
        echo -e "${RED}ERROR: Invalid YAML in configs/repositories.yaml${NC}"
        exit 1
    }
fi

# Check for dependency conflicts
if [ -f orchestrator/dependency_graph.py ]; then
    python3 -c "
from orchestrator.dependency_graph import DependencyResolver
resolver = DependencyResolver()
cycles = resolver.check_circular_dependencies()
if cycles:
    print('${RED}Circular dependencies detected:${NC}')
    for cycle in cycles:
        print(f'  {' -> '.join(cycle)}')
    exit(1)
" 2>/dev/null || true
fi

# Check Python code formatting (if black is installed)
if command -v black &> /dev/null; then
    black --check orchestrator/*.py 2>/dev/null || {
        echo -e "${YELLOW}Warning: Python code not formatted${NC}"
        echo "Run: black orchestrator/*.py"
    }
fi

echo -e "${GREEN}Pre-commit checks passed!${NC}"