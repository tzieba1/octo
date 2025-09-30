"""
Repository health monitoring and metrics collection
"""

import subprocess
import json
import yaml
from typing import Dict, List, Optional, Any
from datetime import datetime, timedelta
from pathlib import Path
from collections import defaultdict
import logging

logger = logging.getLogger(__name__)


class RepoHealthMonitor:
    """Monitor health metrics across repositories"""
    
    def __init__(self, config_path: str = "configs/repositories.yaml"):
        self.config_path = Path(config_path)
        self.repos = self._load_config()
        self.metrics_history = []
        self._load_metrics_history()
    
    def _load_config(self) -> Dict:
        """Load repository configuration"""
        with open(self.config_path) as f:
            return yaml.safe_load(f)
    
    def _load_metrics_history(self):
        """Load historical metrics from git notes"""
        try:
            result = subprocess.check_output(
                ["git", "notes", "--ref=metrics", "list"],
                text=True,
                stderr=subprocess.DEVNULL
            )
            for line in result.strip().split('\n'):
                if line:
                    note_hash, commit = line.split()
                    note_content = subprocess.check_output(
                        ["git", "notes", "--ref=metrics", "show", commit],
                        text=True
                    )
                    metrics = json.loads(note_content)
                    self.metrics_history.append(metrics)
        except subprocess.CalledProcessError:
            # No metrics history yet
            pass
    
    def _persist_metrics(self, metrics: Dict):
        """Save metrics to git notes"""
        metrics['timestamp'] = datetime.now().isoformat()
        note_content = json.dumps(metrics, indent=2)
        
        # Create empty commit for metrics
        subprocess.run(
            ["git", "commit", "--allow-empty", "-m", f"Metrics snapshot: {metrics['timestamp']}"],
            check=True
        )
        
        # Add metrics as note
        subprocess.run(
            ["git", "notes", "--ref=metrics", "add", "-m", note_content],
            check=True
        )
        
        self.metrics_history.append(metrics)
    
    def collect_metrics(self) -> Dict:
        """Collect comprehensive metrics for all repositories"""
        metrics = {
            'timestamp': datetime.now().isoformat(),
            'repositories': {},
            'summary': {
                'total_commits': 0,
                'total_branches': 0,
                'total_tags': 0,
                'active_repos': 0
            }
        }
        
        for repo_name in self.repos['repositories']:
            repo_metrics = self._collect_repo_metrics(repo_name)
            metrics['repositories'][repo_name] = repo_metrics
            
            # Update summary
            metrics['summary']['total_commits'] += repo_metrics['commit_count']
            metrics['summary']['total_branches'] += repo_metrics['branch_count']
            metrics['summary']['total_tags'] += repo_metrics['tag_count']
            if repo_metrics['is_active']:
                metrics['summary']['active_repos'] += 1
        
        # Add cross-repo metrics
        metrics['health_score'] = self._calculate_health_score(metrics)
        metrics['alerts'] = self._check_alerts(metrics)
        
        # Persist metrics
        self._persist_metrics(metrics)
        
        return metrics
    
    def _collect_repo_metrics(self, repo: str) -> Dict:
        """Collect metrics for a single repository"""
        repo_path = Path(f"repos/{repo}")
        
        metrics = {
            'name': repo,
            'exists': repo_path.exists()
        }
        
        if not repo_path.exists():
            logger.warning(f"Repository {repo} not found at {repo_path}")
            return metrics
        
        try:
            # Commit metrics
            metrics['commit_count'] = self._get_commit_count(repo_path)
            metrics['commit_frequency'] = self._get_commit_frequency(repo_path)
            metrics['last_commit'] = self._get_last_commit_date(repo_path)
            
            # Branch metrics
            metrics['branch_count'] = self._count_branches(repo_path)
            metrics['active_branches'] = self._get_active_branches(repo_path)
            metrics['stale_branches'] = self._get_stale_branches(repo_path)
            
            # Tag metrics
            metrics['tag_count'] = self._count_tags(repo_path)
            metrics['last_tag'] = self._get_last_tag(repo_path)
            metrics['tag_age_days'] = self._get_tag_age(repo_path)
            
            # Contributor metrics
            metrics['contributor_count'] = self._count_contributors(repo_path)
            metrics['active_contributors'] = self._get_active_contributors(repo_path)
            
            # Code metrics
            metrics['file_count'] = self._count_files(repo_path)
            metrics['lines_of_code'] = self._count_lines_of_code(repo_path)
            metrics['language_stats'] = self._get_language_stats(repo_path)
            
            # Activity indicators
            metrics['is_active'] = self._is_active(metrics)
            metrics['activity_level'] = self._calculate_activity_level(metrics)
            
            # Dependency freshness
            metrics['dependency_freshness'] = self._check_dependency_freshness(repo)
            
        except Exception as e:
            logger.error(f"Error collecting metrics for {repo}: {e}")
            metrics['error'] = str(e)
        
        return metrics
    
    def _get_commit_count(self, repo_path: Path) -> int:
        """Get total number of commits"""
        result = subprocess.check_output(
            ["git", "-C", str(repo_path), "rev-list", "--count", "HEAD"],
            text=True
        ).strip()
        return int(result)
    
    def _get_commit_frequency(self, repo_path: Path, days: int = 30) -> float:
        """Get average commits per day over the last N days"""
        since_date = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d")
        result = subprocess.check_output(
            ["git", "-C", str(repo_path), "log", f"--since={since_date}", "--oneline"],
            text=True
        ).strip()
        
        commit_count = len(result.split('\n')) if result else 0
        return commit_count / days
    
    def _get_last_commit_date(self, repo_path: Path) -> str:
        """Get date of last commit"""
        try:
            result = subprocess.check_output(
                ["git", "-C", str(repo_path), "log", "-1", "--format=%aI"],
                text=True
            ).strip()
            return result
        except:
            return None
    
    def _count_branches(self, repo_path: Path) -> int:
        """Count total branches"""
        result = subprocess.check_output(
            ["git", "-C", str(repo_path), "branch", "-r"],
            text=True
        ).strip()
        return len(result.split('\n')) if result else 0
    
    def _get_active_branches(self, repo_path: Path, days: int = 30) -> List[str]:
        """Get branches with recent activity"""
        since_date = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d")
        result = subprocess.check_output(
            ["git", "-C", str(repo_path), "for-each-ref", 
             "--format=%(refname:short) %(committerdate:iso)",
             f"--sort=-committerdate", "refs/remotes"],
            text=True
        ).strip()
        
        active = []
        for line in result.split('\n'):
            if line:
                parts = line.split()
                if len(parts) >= 2:
                    branch = parts[0].replace('origin/', '')
                    date = parts[1]
                    if date >= since_date:
                        active.append(branch)
        
        return active
    
    def _get_stale_branches(self, repo_path: Path, days: int = 90) -> List[str]:
        """Get branches with no recent activity"""
        cutoff_date = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d")
        result = subprocess.check_output(
            ["git", "-C", str(repo_path), "for-each-ref",
             "--format=%(refname:short) %(committerdate:iso)",
             "refs/remotes"],
            text=True
        ).strip()
        
        stale = []
        for line in result.split('\n'):
            if line:
                parts = line.split()
                if len(parts) >= 2:
                    branch = parts[0].replace('origin/', '')
                    date = parts[1]
                    if date < cutoff_date and branch != 'main' and branch != 'master':
                        stale.append(branch)
        
        return stale
    
    def _count_tags(self, repo_path: Path) -> int:
        """Count total tags"""
        try:
            result = subprocess.check_output(
                ["git", "-C", str(repo_path), "tag", "-l"],
                text=True
            ).strip()
            return len(result.split('\n')) if result else 0
        except:
            return 0
    
    def _get_last_tag(self, repo_path: Path) -> Optional[str]:
        """Get the most recent tag"""
        try:
            result = subprocess.check_output(
                ["git", "-C", str(repo_path), "describe", "--tags", "--abbrev=0"],
                text=True,
                stderr=subprocess.DEVNULL
            ).strip()
            return result
        except:
            return None
    
    def _get_tag_age(self, repo_path: Path) -> Optional[int]:
        """Get age of last tag in days"""
        last_tag = self._get_last_tag(repo_path)
        if not last_tag:
            return None
        
        try:
            result = subprocess.check_output(
                ["git", "-C", str(repo_path), "log", "-1", "--format=%aI", last_tag],
                text=True
            ).strip()
            tag_date = datetime.fromisoformat(result.replace('+00:00', '+00:00'))
            return (datetime.now(tag_date.tzinfo) - tag_date).days
        except:
            return None
    
    def _count_contributors(self, repo_path: Path) -> int:
        """Count unique contributors"""
        result = subprocess.check_output(
            ["git", "-C", str(repo_path), "shortlog", "-sn"],
            text=True
        ).strip()
        return len(result.split('\n')) if result else 0
    
    def _get_active_contributors(self, repo_path: Path, days: int = 30) -> int:
        """Count active contributors in the last N days"""
        since_date = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d")
        result = subprocess.check_output(
            ["git", "-C", str(repo_path), "shortlog", "-sn", f"--since={since_date}"],
            text=True
        ).strip()
        return len(result.split('\n')) if result else 0
    
    def _count_files(self, repo_path: Path) -> int:
        """Count tracked files"""
        result = subprocess.check_output(
            ["git", "-C", str(repo_path), "ls-files"],
            text=True
        ).strip()
        return len(result.split('\n')) if result else 0
    
    def _count_lines_of_code(self, repo_path: Path) -> Dict[str, int]:
        """Count lines of code by file type"""
        # Simple implementation - can be enhanced with tools like cloc
        result = subprocess.check_output(
            ["git", "-C", str(repo_path), "ls-files"],
            text=True
        ).strip()
        
        stats = defaultdict(int)
        for file in result.split('\n'):
            if file:
                ext = Path(file).suffix
                if ext:
                    try:
                        file_path = repo_path / file
                        if file_path.exists():
                            with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                                stats[ext] += len(f.readlines())
                    except:
                        pass
        
        return dict(stats)
    
    def _get_language_stats(self, repo_path: Path) -> Dict[str, float]:
        """Get language distribution percentages"""
        loc = self._count_lines_of_code(repo_path)
        total = sum(loc.values())
        
        if total == 0:
            return {}
        
        return {ext: (count / total * 100) for ext, count in loc.items()}
    
    def _is_active(self, metrics: Dict) -> bool:
        """Determine if repository is active"""
        if not metrics.get('last_commit'):
            return False
        
        try:
            last_commit = datetime.fromisoformat(metrics['last_commit'].replace('+00:00', '+00:00'))
            days_since_commit = (datetime.now(last_commit.tzinfo) - last_commit).days
            return days_since_commit < 30
        except:
            return False
    
    def _calculate_activity_level(self, metrics: Dict) -> str:
        """Calculate activity level (high/medium/low/inactive)"""
        freq = metrics.get('commit_frequency', 0)
        contributors = metrics.get('active_contributors', 0)
        
        if freq > 1 and contributors > 2:
            return 'high'
        elif freq > 0.3 and contributors > 0:
            return 'medium'
        elif freq > 0:
            return 'low'
        else:
            return 'inactive'
    
    def _check_dependency_freshness(self, repo: str) -> Dict[str, Any]:
        """Check if dependencies are up to date"""
        repo_config = self.repos['repositories'].get(repo, {})
        deps = repo_config.get('dependencies', [])
        
        freshness = {
            'total': len(deps),
            'current': 0,
            'outdated': 0,
            'details': []
        }
        
        for dep in deps:
            dep_repo = dep['name']
            dep_spec = dep['version']
            
            # Get actual version of dependency
            try:
                actual_version = subprocess.check_output(
                    ["git", "-C", f"repos/{dep_repo}", "describe", "--tags", "--abbrev=0"],
                    text=True,
                    stderr=subprocess.DEVNULL
                ).strip()
                
                # Simple check - can be enhanced with semantic version comparison
                is_current = dep_spec in actual_version or actual_version in dep_spec
                
                if is_current:
                    freshness['current'] += 1
                else:
                    freshness['outdated'] += 1
                
                freshness['details'].append({
                    'dependency': dep_repo,
                    'specified': dep_spec,
                    'actual': actual_version,
                    'is_current': is_current
                })
            except:
                freshness['details'].append({
                    'dependency': dep_repo,
                    'specified': dep_spec,
                    'actual': 'unknown',
                    'is_current': False
                })
        
        return freshness
    
    def _calculate_health_score(self, metrics: Dict) -> float:
        """Calculate overall health score (0-100)"""
        scores = []
        
        for repo_name, repo_metrics in metrics['repositories'].items():
            if not repo_metrics.get('exists', False):
                continue
            
            repo_score = 0
            max_score = 0
            
            # Activity score (30 points)
            if repo_metrics.get('is_active'):
                repo_score += 20
            if repo_metrics.get('activity_level') == 'high':
                repo_score += 10
            elif repo_metrics.get('activity_level') == 'medium':
                repo_score += 5
            max_score += 30
            
            # Maintenance score (30 points)
            if repo_metrics.get('tag_age_days', float('inf')) < 30:
                repo_score += 15
            if len(repo_metrics.get('stale_branches', [])) < 3:
                repo_score += 15
            max_score += 30
            
            # Collaboration score (20 points)
            if repo_metrics.get('active_contributors', 0) > 1:
                repo_score += 20
            max_score += 20
            
            # Dependency health (20 points)
            freshness = repo_metrics.get('dependency_freshness', {})
            if freshness.get('total', 0) > 0:
                fresh_ratio = freshness.get('current', 0) / freshness['total']
                repo_score += int(fresh_ratio * 20)
            else:
                repo_score += 20  # No dependencies = full score
            max_score += 20
            
            # Calculate percentage
            if max_score > 0:
                scores.append((repo_score / max_score) * 100)
        
        return sum(scores) / len(scores) if scores else 0
    
    def _check_alerts(self, metrics: Dict) -> List[Dict]:
        """Check for conditions that should trigger alerts"""
        alerts = []
        
        for repo_name, repo_metrics in metrics['repositories'].items():
            if not repo_metrics.get('exists', False):
                alerts.append({
                    'level': 'error',
                    'repo': repo_name,
                    'message': f"Repository {repo_name} not found"
                })
                continue
            
            # Check for inactivity
            if not repo_metrics.get('is_active'):
                alerts.append({
                    'level': 'warning',
                    'repo': repo_name,
                    'message': f"Repository {repo_name} has been inactive for >30 days"
                })
            
            # Check for stale branches
            stale_count = len(repo_metrics.get('stale_branches', []))
            if stale_count > 5:
                alerts.append({
                    'level': 'info',
                    'repo': repo_name,
                    'message': f"Repository {repo_name} has {stale_count} stale branches"
                })
            
            # Check for outdated tags
            tag_age = repo_metrics.get('tag_age_days')
            if tag_age and tag_age > 90:
                alerts.append({
                    'level': 'info',
                    'repo': repo_name,
                    'message': f"Last tag in {repo_name} is {tag_age} days old"
                })
            
            # Check for dependency issues
            freshness = repo_metrics.get('dependency_freshness', {})
            if freshness.get('outdated', 0) > 0:
                alerts.append({
                    'level': 'warning',
                    'repo': repo_name,
                    'message': f"Repository {repo_name} has {freshness['outdated']} outdated dependencies"
                })
        
        return alerts
    
    def generate_health_report(self) -> str:
        """Generate a formatted health report"""
        metrics = self.collect_metrics()
        
        report = []
        report.append("# Repository Health Report")
        report.append(f"Generated: {metrics['timestamp']}")
        report.append(f"Overall Health Score: {metrics['health_score']:.1f}/100\n")
        
        # Summary
        report.append("## Summary")
        summary = metrics['summary']
        report.append(f"- Active Repositories: {summary['active_repos']}/{len(metrics['repositories'])}")
        report.append(f"- Total Commits: {summary['total_commits']}")
        report.append(f"- Total Branches: {summary['total_branches']}")
        report.append(f"- Total Tags: {summary['total_tags']}\n")
        
        # Alerts
        if metrics['alerts']:
            report.append("## ⚠️ Alerts")
            for alert in metrics['alerts']:
                icon = "🔴" if alert['level'] == 'error' else "🟡" if alert['level'] == 'warning' else "ℹ️"
                report.append(f"{icon} **{alert['repo']}**: {alert['message']}")
            report.append("")
        
        # Repository Details
        report.append("## Repository Details")
        for repo_name, repo_metrics in metrics['repositories'].items():
            if not repo_metrics.get('exists', False):
                continue
            
            report.append(f"\n### {repo_name}")
            report.append(f"- **Activity Level**: {repo_metrics.get('activity_level', 'unknown')}")
            report.append(f"- **Last Commit**: {repo_metrics.get('last_commit', 'unknown')}")
            report.append(f"- **Commit Frequency**: {repo_metrics.get('commit_frequency', 0):.2f} commits/day")
            report.append(f"- **Active Contributors**: {repo_metrics.get('active_contributors', 0)}")
            report.append(f"- **Stale Branches**: {len(repo_metrics.get('stale_branches', []))}")
            
            freshness = repo_metrics.get('dependency_freshness', {})
            if freshness.get('total', 0) > 0:
                report.append(f"- **Dependencies**: {freshness['current']}/{freshness['total']} current")
        
        return '\n'.join(report)