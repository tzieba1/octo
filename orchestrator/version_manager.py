"""
Version coordination across multiple repositories
"""

import subprocess
import json
import yaml
from typing import Dict, List, Optional, Tuple
from pathlib import Path
from semantic_version import Version, Spec
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class VersionCoordinator:
    """Coordinates version management across multiple repositories"""
    
    def __init__(self, config_path: str = "configs/repositories.yaml"):
        self.config_path = Path(config_path)
        self.repos = self._load_config()
        self.dependency_graph = self._build_graph()
    
    def _load_config(self) -> Dict:
        """Load repository configuration"""
        with open(self.config_path) as f:
            return yaml.safe_load(f)
    
    def _build_graph(self) -> Dict[str, List[str]]:
        """Build dependency graph from configuration"""
        graph = {}
        for repo_name, repo_config in self.repos['repositories'].items():
            dependents = []
            for other_repo, other_config in self.repos['repositories'].items():
                if other_repo != repo_name:
                    deps = other_config.get('dependencies', [])
                    if any(d['name'] == repo_name for d in deps):
                        dependents.append(other_repo)
            graph[repo_name] = dependents
        return graph
    
    def get_current_version(self, repo: str) -> Version:
        """Get current version from git tags"""
        try:
            cmd = f"git -C repos/{repo} describe --tags --abbrev=0"
            result = subprocess.check_output(cmd, shell=True, text=True).strip()
            # Remove 'v' prefix if present
            version_str = result[1:] if result.startswith('v') else result
            return Version(version_str)
        except subprocess.CalledProcessError:
            logger.warning(f"No tags found for {repo}, defaulting to 0.1.0")
            return Version("0.1.0")
    
    def bump_version(self, current: Version, bump_type: str) -> Version:
        """Bump version based on type"""
        if bump_type == 'major':
            return Version(f"{current.major + 1}.0.0")
        elif bump_type == 'minor':
            return Version(f"{current.major}.{current.minor + 1}.0")
        elif bump_type == 'patch':
            return Version(f"{current.major}.{current.minor}.{current.patch + 1}")
        else:
            raise ValueError(f"Invalid bump type: {bump_type}")
    
    def coordinate_release(self, repo_name: str, version_type: str = 'patch') -> Dict:
        """
        Coordinate cascading version updates across dependent repositories
        """
        if repo_name not in self.repos['repositories']:
            raise ValueError(f"Repository {repo_name} not found in configuration")
        
        # Get current and new version
        current_version = self.get_current_version(repo_name)
        new_version = self.bump_version(current_version, version_type)
        
        logger.info(f"Planning release for {repo_name}: {current_version} -> {new_version}")
        
        # Calculate impact radius
        affected_repos = self._find_affected_repositories(repo_name, new_version)
        
        # Generate update plan
        update_plan = {
            'source': {
                'repo': repo_name,
                'current_version': str(current_version),
                'new_version': str(new_version),
                'bump_type': version_type
            },
            'affected': affected_repos,
            'execution_order': self._determine_execution_order(repo_name, affected_repos)
        }
        
        return update_plan
    
    def _find_affected_repositories(self, repo_name: str, new_version: Version) -> List[Dict]:
        """Find all repositories affected by this version change"""
        affected = []
        dependents = self.dependency_graph.get(repo_name, [])
        
        for dep_repo in dependents:
            dep_config = self.repos['repositories'][dep_repo]
            deps = dep_config.get('dependencies', [])
            
            for dep in deps:
                if dep['name'] == repo_name:
                    version_spec = Spec(dep['version'])
                    requires_update = not version_spec.match(new_version)
                    
                    affected.append({
                        'repo': dep_repo,
                        'current_dependency': dep['version'],
                        'requires_update': requires_update,
                        'suggested_action': 'bump_patch' if requires_update else 'none',
                        'reason': f"Dependency {repo_name} updated to {new_version}"
                    })
        
        return affected
    
    def _determine_execution_order(self, source_repo: str, affected: List[Dict]) -> List[str]:
        """Determine the order in which to execute updates"""
        # Simple topological sort based on dependencies
        order = [source_repo]
        
        # Add affected repos that need updates
        for item in affected:
            if item['requires_update'] and item['repo'] not in order:
                order.append(item['repo'])
        
        return order
    
    def execute_release_plan(self, plan: Dict, dry_run: bool = True) -> Dict:
        """Execute the release plan"""
        results = {'success': [], 'failed': [], 'skipped': []}
        
        for repo in plan['execution_order']:
            try:
                if repo == plan['source']['repo']:
                    # Release source repository
                    version = plan['source']['new_version']
                    if not dry_run:
                        self._tag_and_push(repo, version)
                    results['success'].append({
                        'repo': repo,
                        'version': version,
                        'action': 'released'
                    })
                else:
                    # Handle dependent repository
                    affected_item = next(
                        (a for a in plan['affected'] if a['repo'] == repo),
                        None
                    )
                    
                    if affected_item and affected_item['requires_update']:
                        current = self.get_current_version(repo)
                        new = self.bump_version(current, 'patch')
                        
                        if not dry_run:
                            self._update_dependency(
                                repo, 
                                plan['source']['repo'],
                                plan['source']['new_version']
                            )
                            self._tag_and_push(repo, str(new))
                        
                        results['success'].append({
                            'repo': repo,
                            'version': str(new),
                            'action': 'bumped',
                            'reason': affected_item['reason']
                        })
                    else:
                        results['skipped'].append({
                            'repo': repo,
                            'reason': 'No update required'
                        })
                        
            except Exception as e:
                results['failed'].append({
                    'repo': repo,
                    'error': str(e)
                })
                logger.error(f"Failed to process {repo}: {e}")
        
        return results
    
    def _tag_and_push(self, repo: str, version: str):
        """Create git tag and push to remote"""
        commands = [
            f"git -C repos/{repo} tag -a v{version} -m 'Release v{version}'",
            f"git -C repos/{repo} push origin v{version}"
        ]
        
        for cmd in commands:
            logger.info(f"Executing: {cmd}")
            subprocess.run(cmd, shell=True, check=True)
    
    def _update_dependency(self, repo: str, dep_name: str, dep_version: str):
        """Update dependency version in repository configuration"""
        config_file = Path(f"repos/{repo}/package.json")  # Adjust based on your stack
        
        if config_file.exists():
            with open(config_file) as f:
                config = json.load(f)
            
            # Update dependency version
            if 'dependencies' in config and dep_name in config['dependencies']:
                config['dependencies'][dep_name] = f"^{dep_version}"
            
            with open(config_file, 'w') as f:
                json.dump(config, f, indent=2)
            
            # Commit the change
            subprocess.run(
                f"git -C repos/{repo} commit -am 'Update {dep_name} to v{dep_version}'",
                shell=True,
                check=True
            )
    
    def validate_versions(self) -> Dict[str, List[str]]:
        """Validate version consistency across all repositories"""
        issues = []
        
        for repo_name, repo_config in self.repos['repositories'].items():
            current_version = self.get_current_version(repo_name)
            config_version = Version(repo_config['version'])
            
            if current_version != config_version:
                issues.append({
                    'repo': repo_name,
                    'issue': 'version_mismatch',
                    'git_version': str(current_version),
                    'config_version': str(config_version)
                })
            
            # Check dependency versions
            for dep in repo_config.get('dependencies', []):
                dep_name = dep['name']
                dep_spec = Spec(dep['version'])
                actual_version = self.get_current_version(dep_name)
                
                if not dep_spec.match(actual_version):
                    issues.append({
                        'repo': repo_name,
                        'issue': 'dependency_mismatch',
                        'dependency': dep_name,
                        'expected': dep['version'],
                        'actual': str(actual_version)
                    })
        
        return {'valid': len(issues) == 0, 'issues': issues}