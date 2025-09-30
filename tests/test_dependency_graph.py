"""
Tests for dependency graph and resolution
"""

import pytest
from unittest.mock import Mock, patch, mock_open
import networkx as nx
from octo.dependency_graph import DependencyResolver


class TestDependencyResolver:
    """Test suite for DependencyResolver"""

    @pytest.fixture
    def resolver(self, tmp_path):
        """Create a DependencyResolver with test configuration"""
        config_file = tmp_path / "test_config.yaml"
        config_file.write_text("""
repositories:
  core-lib:
    url: git@github.com:test/core-lib.git
    version: 1.0.0
    type: library
    dependencies: []
  
  utils-lib:
    url: git@github.com:test/utils-lib.git
    version: 1.1.0
    type: library
    dependencies:
      - name: core-lib
        version: "^1.0.0"
        type: compile
  
  service-a:
    url: git@github.com:test/service-a.git
    version: 2.0.0
    type: service
    dependencies:
      - name: core-lib
        version: "^1.0.0"
        type: compile
      - name: utils-lib
        version: "^1.0.0"
        type: compile
  
  service-b:
    url: git@github.com:test/service-b.git
    version: 2.1.0
    type: service
    dependencies:
      - name: service-a
        version: "^2.0.0"
        type: runtime
      - name: utils-lib
        version: "^1.0.0"
        type: compile
  
  app:
    url: git@github.com:test/app.git
    version: 3.0.0
    type: application
    dependencies:
      - name: service-a
        version: "^2.0.0"
        type: runtime
      - name: service-b
        version: "^2.0.0"
        type: runtime

dependency_rules:
  resolution: highest-compatible
  lock_strategy: conservative
  update_policy: explicit
""")
        return DependencyResolver(str(config_file))

    def test_initialization(self, resolver):
        """Test resolver initialization"""
        assert resolver.repos is not None
        assert len(resolver.graph.nodes) == 5
        assert 'core-lib' in resolver.graph
        assert 'app' in resolver.graph

    def test_dependency_graph_structure(self, resolver):
        """Test that dependency graph is built correctly"""
        # Check edges (dependencies)
        assert resolver.graph.has_edge('utils-lib', 'core-lib')
        assert resolver.graph.has_edge('service-a', 'core-lib')
        assert resolver.graph.has_edge('service-a', 'utils-lib')
        assert resolver.graph.has_edge('service-b', 'service-a')
        assert resolver.graph.has_edge('app', 'service-a')
        assert resolver.graph.has_edge('app', 'service-b')

    def test_get_dependency_tree(self, resolver):
        """Test dependency tree generation"""
        tree = resolver.get_dependency_tree('service-b')

        assert tree['name'] == 'service-b'
        assert tree['version'] == '2.1.0'
        assert len(tree['dependencies']) == 2

        # Check nested dependencies
        deps = {d['name']: d for d in tree['dependencies']}
        assert 'service-a' in deps
        assert 'utils-lib' in deps

        # Check transitive dependencies
        service_a_deps = deps['service-a']['dependencies']
        assert len(service_a_deps) == 2
        dep_names = [d['name'] for d in service_a_deps]
        assert 'core-lib' in dep_names
        assert 'utils-lib' in dep_names

    def test_get_dependents(self, resolver):
        """Test getting direct dependents"""
        dependents = resolver.get_dependents('core-lib')

        assert 'utils-lib' in dependents
        assert 'service-a' in dependents
        assert 'service-b' not in dependents  # Not a direct dependent

    def test_get_all_dependents(self, resolver):
        """Test getting all transitive dependents"""
        all_dependents = resolver.get_all_dependents('core-lib')

        # Should include all repos except core-lib itself
        assert 'utils-lib' in all_dependents
        assert 'service-a' in all_dependents
        assert 'service-b' in all_dependents
        assert 'app' in all_dependents
        assert 'core-lib' not in all_dependents

    def test_check_circular_dependencies(self, resolver):
        """Test circular dependency detection"""
        cycles = resolver.check_circular_dependencies()

        # Should have no cycles in our test configuration
        assert len(cycles) == 0

    def test_check_circular_dependencies_with_cycle(self, tmp_path):
        """Test circular dependency detection with actual cycle"""
        config_file = tmp_path / "circular_config.yaml"
        config_file.write_text("""
repositories:
  repo-a:
    url: git@github.com:test/repo-a.git
    version: 1.0.0
    type: library
    dependencies:
      - name: repo-b
        version: "^1.0.0"
        type: compile
  
  repo-b:
    url: git@github.com:test/repo-b.git
    version: 1.0.0
    type: library
    dependencies:
      - name: repo-c
        version: "^1.0.0"
        type: compile
  
  repo-c:
    url: git@github.com:test/repo-c.git
    version: 1.0.0
    type: library
    dependencies:
      - name: repo-a
        version: "^1.0.0"
        type: compile
""")

        resolver = DependencyResolver(str(config_file))
        cycles = resolver.check_circular_dependencies()

        assert len(cycles) > 0
        # The cycle should contain all three repos
        cycle = cycles[0]
        assert len(cycle) == 3
        assert 'repo-a' in cycle
        assert 'repo-b' in cycle
        assert 'repo-c' in cycle

    def test_get_build_order(self, resolver):
        """Test topological build order"""
        build_order = resolver.get_build_order()

        # Check that dependencies come before dependents
        core_idx = build_order.index('core-lib')
        utils_idx = build_order.index('utils-lib')
        service_a_idx = build_order.index('service-a')
        service_b_idx = build_order.index('service-b')
        app_idx = build_order.index('app')

        # core-lib should come before everything that depends on it
        assert core_idx < utils_idx
        assert core_idx < service_a_idx

        # utils-lib should come before services that depend on it
        assert utils_idx < service_a_idx
        assert utils_idx < service_b_idx

        # service-a should come before service-b and app
        assert service_a_idx < service_b_idx
        assert service_a_idx < app_idx

        # service-b should come before app
        assert service_b_idx < app_idx

    def test_get_release_order(self, resolver):
        """Test release order calculation"""
        repos_to_release = ['service-a', 'service-b', 'app']
        release_order = resolver.get_release_order(repos_to_release)

        # Release order should be reverse topological (leaf nodes first)
        assert release_order.index('app') < release_order.index('service-b')
        assert release_order.index('app') < release_order.index('service-a')
        assert release_order.index(
            'service-b') < release_order.index('service-a')

    def test_generate_dependency_lock(self, resolver):
        """Test dependency lock file generation"""
        lock = resolver.generate_dependency_lock()

        assert lock['version'] == '1.0'
        assert 'repositories' in lock
        assert len(lock['repositories']) == 5

        # Check service-b lock entry
        service_b_lock = lock['repositories']['service-b']
        assert service_b_lock['version'] == '2.1.0'
        assert service_b_lock['type'] == 'service'
        assert 'service-a' in service_b_lock['dependencies']
        assert service_b_lock['dependencies']['service-a']['resolved'] == '2.0.0'

    def test_analyze_impact(self, resolver):
        """Test impact analysis for version changes"""
        impact = resolver.analyze_impact('core-lib', '2.0.0')

        assert impact['repository'] == 'core-lib'
        assert impact['current_version'] == '1.0.0'
        assert impact['new_version'] == '2.0.0'
        assert impact['is_breaking_change'] == True  # Major version bump

        # Check direct impact
        direct_impact = {d['repository']: d for d in impact['direct_impact']}
        assert 'utils-lib' in direct_impact
        assert 'service-a' in direct_impact

        # These should not be compatible with major version bump
        assert not direct_impact['utils-lib']['compatible']
        assert not direct_impact['service-a']['compatible']

        # Check transitive impact
        assert 'service-b' in impact['transitive_impact']
        assert 'app' in impact['transitive_impact']

    def test_resolve_version_conflicts(self, tmp_path):
        """Test version conflict detection"""
        config_file = tmp_path / "conflict_config.yaml"
        config_file.write_text("""
repositories:
  shared-lib:
    url: git@github.com:test/shared-lib.git
    version: 2.0.0
    type: library
    dependencies: []
  
  service-x:
    url: git@github.com:test/service-x.git
    version: 1.0.0
    type: service
    dependencies:
      - name: shared-lib
        version: "^1.0.0"
        type: compile
  
  service-y:
    url: git@github.com:test/service-y.git
    version: 1.0.0
    type: service
    dependencies:
      - name: shared-lib
        version: "^2.0.0"
        type: compile
""")

        resolver = DependencyResolver(str(config_file))
        conflicts = resolver.resolve_version_conflicts()

        # Should detect conflict for shared-lib
        assert 'shared-lib' in conflicts
        assert len(conflicts['shared-lib']) > 0

        conflict = conflicts['shared-lib'][0]
        assert 'service-x' in conflict['repos']
        assert 'service-y' in conflict['repos']
        assert not conflict['compatible']

    @patch('matplotlib.pyplot.savefig')
    @patch('matplotlib.pyplot.show')
    def test_visualize_graph(self, mock_show, mock_savefig, resolver, tmp_path):
        """Test graph visualization"""
        output_path = str(tmp_path / "test_graph.png")

        resolver.visualize_graph(output_path, highlight_repo='service-a')

        # Check that savefig was called with correct path
        mock_savefig.assert_called_once()
        args = mock_savefig.call_args[0]
        assert output_path in args[0]

    def test_export_to_mermaid(self, resolver):
        """Test Mermaid diagram export"""
        mermaid = resolver.export_to_mermaid()

        assert 'graph TD' in mermaid
        assert 'core-lib' in mermaid
        assert 'app' in mermaid

        # Check that edges are represented
        assert '-->' in mermaid
        assert 'service-a -->|"^2.0.0"| service-b' in mermaid or \
               'service-b -->|"^2.0.0"| service-a' in mermaid
