"""
Dependency resolution and graph management
"""

import yaml
import json
from typing import Dict, List, Set, Optional, Tuple
from pathlib import Path
from collections import defaultdict, deque
import networkx as nx
import matplotlib.pyplot as plt
from semantic_version import Version, Spec
import logging

logger = logging.getLogger(__name__)


class DependencyResolver:
    """Manages and resolves dependencies across repositories"""
    
    def __init__(self, config_path: str = "configs/repositories.yaml"):
        self.config_path = Path(config_path)
        self.repos = self._load_config()
        self.graph = nx.DiGraph()
        self._build_dependency_graph()
    
    def _load_config(self) -> Dict:
        """Load repository configuration"""
        with open(self.config_path) as f:
            return yaml.safe_load(f)
    
    def _build_dependency_graph(self):
        """Build directed graph of dependencies"""
        for repo_name, repo_config in self.repos['repositories'].items():
            self.graph.add_node(
                repo_name,
                version=repo_config['version'],
                type=repo_config['type']
            )
            
            for dep in repo_config.get('dependencies', []):
                self.graph.add_edge(
                    repo_name,
                    dep['name'],
                    version_spec=dep['version'],
                    dep_type=dep.get('type', 'runtime')
                )
    
    def get_dependency_tree(self, repo: str, max_depth: Optional[int] = None) -> Dict:
        """Get dependency tree for a repository"""
        if repo not in self.graph:
            raise ValueError(f"Repository {repo} not found")
        
        def build_tree(node, depth=0):
            if max_depth and depth >= max_depth:
                return {'name': node, 'truncated': True}
            
            deps = []
            for successor in self.graph.successors(node):
                edge_data = self.graph[node][successor]
                dep_tree = build_tree(successor, depth + 1)
                dep_tree['version_spec'] = edge_data['version_spec']
                dep_tree['type'] = edge_data['dep_type']
                deps.append(dep_tree)
            
            return {
                'name': node,
                'version': self.graph.nodes[node]['version'],
                'dependencies': deps
            }
        
        return build_tree(repo)
    
    def get_dependents(self, repo: str) -> List[str]:
        """Get all repositories that depend on this one"""
        return list(self.graph.predecessors(repo))
    
    def get_all_dependents(self, repo: str) -> Set[str]:
        """Get all transitive dependents of a repository"""
        dependents = set()
        queue = deque([repo])
        
        while queue:
            current = queue.popleft()
            for dependent in self.graph.predecessors(current):
                if dependent not in dependents:
                    dependents.add(dependent)
                    queue.append(dependent)
        
        return dependents
    
    def check_circular_dependencies(self) -> List[List[str]]:
        """Check for circular dependencies in the graph"""
        try:
            cycles = list(nx.simple_cycles(self.graph))
            return cycles
        except nx.NetworkXNoCycle:
            return []
    
    def get_build_order(self) -> List[str]:
        """Get topological build order for all repositories"""
        try:
            return list(nx.topological_sort(self.graph))
        except nx.NetworkXUnfeasible:
            raise ValueError("Circular dependency detected")
    
    def get_release_order(self, repos: List[str]) -> List[str]:
        """Determine the order in which to release repositories"""
        # Create subgraph with only specified repos
        subgraph = self.graph.subgraph(repos)
        
        try:
            # Reverse topological sort for release order
            return list(reversed(list(nx.topological_sort(subgraph))))
        except nx.NetworkXUnfeasible:
            raise ValueError("Circular dependency in release set")
    
    def resolve_version_conflicts(self) -> Dict[str, List[Dict]]:
        """Find and resolve version conflicts in dependencies"""
        conflicts = defaultdict(list)
        
        for repo in self.graph.nodes:
            # Get all dependencies of this repo
            deps = {}
            for dep in self.graph.successors(repo):
                edge_data = self.graph[repo][dep]
                deps[dep] = edge_data['version_spec']
            
            # Check for conflicts with other repos depending on same packages
            for other_repo in self.graph.nodes:
                if other_repo == repo:
                    continue
                
                for dep in self.graph.successors(other_repo):
                    if dep in deps:
                        other_spec = self.graph[other_repo][dep]['version_spec']
                        if deps[dep] != other_spec:
                            # Check if specs are compatible
                            spec1 = Spec(deps[dep])
                            spec2 = Spec(other_spec)
                            
                            # Find intersection of version ranges
                            compatible = self._check_spec_compatibility(spec1, spec2)
                            
                            if not compatible:
                                conflicts[dep].append({
                                    'repos': [repo, other_repo],
                                    'specs': [deps[dep], other_spec],
                                    'compatible': False
                                })
        
        return dict(conflicts)
    
    def _check_spec_compatibility(self, spec1: Spec, spec2: Spec) -> bool:
        """Check if two version specs are compatible"""
        # Simple compatibility check - can be enhanced
        test_versions = [
            Version("1.0.0"), Version("1.1.0"), Version("1.2.0"),
            Version("2.0.0"), Version("2.1.0"), Version("3.0.0")
        ]
        
        for v in test_versions:
            if spec1.match(v) and spec2.match(v):
                return True
        return False
    
    def generate_dependency_lock(self) -> Dict:
        """Generate a lock file with resolved versions"""
        lock = {
            'version': '1.0',
            'repositories': {},
            'resolution': {}
        }
        
        for repo in self.graph.nodes:
            node_data = self.graph.nodes[repo]
            deps = {}
            
            for dep in self.graph.successors(repo):
                edge_data = self.graph[repo][dep]
                dep_version = self.graph.nodes[dep]['version']
                
                deps[dep] = {
                    'version': dep_version,
                    'resolved': dep_version,
                    'spec': edge_data['version_spec'],
                    'type': edge_data['dep_type']
                }
            
            lock['repositories'][repo] = {
                'version': node_data['version'],
                'type': node_data['type'],
                'dependencies': deps
            }
        
        # Add resolution metadata
        lock['resolution'] = {
            'timestamp': str(Path.ctime(Path.cwd())),
            'strategy': self.repos.get('dependency_rules', {}).get('resolution', 'highest-compatible')
        }
        
        return lock
    
    def visualize_graph(self, output_path: str = "dependency_graph.png", highlight_repo: Optional[str] = None):
        """Generate visual representation of dependency graph"""
        plt.figure(figsize=(12, 8))
        
        # Create layout
        pos = nx.spring_layout(self.graph, k=2, iterations=50)
        
        # Color nodes by type
        node_colors = []
        for node in self.graph.nodes:
            node_type = self.graph.nodes[node].get('type', 'unknown')
            if highlight_repo and node == highlight_repo:
                node_colors.append('red')
            elif node_type == 'library':
                node_colors.append('lightblue')
            elif node_type == 'service':
                node_colors.append('lightgreen')
            elif node_type == 'application':
                node_colors.append('lightyellow')
            else:
                node_colors.append('lightgray')
        
        # Draw graph
        nx.draw(
            self.graph,
            pos,
            node_color=node_colors,
            with_labels=True,
            node_size=2000,
            font_size=10,
            font_weight='bold',
            arrows=True,
            arrowsize=20,
            edge_color='gray',
            linewidths=2,
            node_shape='o'
        )
        
        # Add version labels
        labels = {node: f"{node}\nv{data['version']}" 
                  for node, data in self.graph.nodes(data=True)}
        nx.draw_networkx_labels(self.graph, pos, labels, font_size=8)
        
        # Add edge labels for version specs
        edge_labels = {(u, v): data['version_spec']
                       for u, v, data in self.graph.edges(data=True)}
        nx.draw_networkx_edge_labels(self.graph, pos, edge_labels, font_size=7)
        
        plt.title("Repository Dependency Graph")
        plt.axis('off')
        plt.tight_layout()
        plt.savefig(output_path, dpi=300, bbox_inches='tight')
        plt.close()
        
        logger.info(f"Dependency graph saved to {output_path}")
    
    def export_to_mermaid(self) -> str:
        """Export dependency graph to Mermaid diagram format"""
        lines = ["graph TD"]
        
        # Add nodes with versions
        for node, data in self.graph.nodes(data=True):
            node_type = data.get('type', 'unknown')
            version = data.get('version', 'unknown')
            lines.append(f'    {node}["{node}<br/>v{version}<br/>({node_type})"]')
        
        # Add edges with version specs
        for u, v, data in self.graph.edges(data=True):
            version_spec = data.get('version_spec', '')
            lines.append(f'    {u} -->|"{version_spec}"| {v}')
        
        return '\n'.join(lines)
    
    def analyze_impact(self, repo: str, new_version: str) -> Dict:
        """Analyze the impact of updating a repository to a new version"""
        if repo not in self.graph:
            raise ValueError(f"Repository {repo} not found")
        
        current_version = Version(self.graph.nodes[repo]['version'])
        new_version_obj = Version(new_version)
        
        # Determine breaking change
        is_breaking = new_version_obj.major > current_version.major
        
        # Find affected repositories
        direct_dependents = self.get_dependents(repo)
        all_dependents = self.get_all_dependents(repo)
        
        impact_analysis = {
            'repository': repo,
            'current_version': str(current_version),
            'new_version': new_version,
            'is_breaking_change': is_breaking,
            'direct_impact': [],
            'transitive_impact': list(all_dependents - set(direct_dependents))
        }
        
        # Analyze each direct dependent
        for dep in direct_dependents:
            edge_data = self.graph[dep][repo]
            version_spec = Spec(edge_data['version_spec'])
            
            compatible = version_spec.match(new_version_obj)
            
            impact_analysis['direct_impact'].append({
                'repository': dep,
                'current_spec': edge_data['version_spec'],
                'compatible': compatible,
                'action_required': 'update_spec' if not compatible else 'none'
            })
        
        return impact_analysis