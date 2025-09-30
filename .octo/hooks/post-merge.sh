#!/bin/bash
# hooks/post-merge
# Post-merge hook for dependency updates

set -e

# Check if dependencies changed
if git diff-tree -r --name-only --no-commit-id ORIG_HEAD HEAD | grep -E "package.json|requirements.txt|go.mod|Gemfile" > /dev/null; then
    echo "Dependencies may have changed - consider running:"
    echo "  ./scripts/deps/install-deps.sh"
fi

# Check if octo config changed
if git diff-tree -r --name-only --no-commit-id ORIG_HEAD HEAD | grep "configs/repositories.yaml" > /dev/null; then
    echo "Repository configuration changed - updating dependency graph..."
    python3 -c "
from octo.dependency_graph import DependencyResolver
resolver = DependencyResolver()
resolver.visualize_graph('dependency_graph.png')
print('Dependency graph updated: dependency_graph.png')
" 2>/dev/null || true
fi