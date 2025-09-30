"""
Cross-repository issue and milestone tracking
"""

import json
import subprocess
from typing import Dict, List, Optional, Any
from abc import ABC, abstractmethod
from datetime import datetime, timedelta
from pathlib import Path
import logging

logger = logging.getLogger(__name__)


class ProviderInterface(ABC):
    """Abstract interface for issue tracking providers"""

    @abstractmethod
    def create_issue(self, repo: str, title: str, body: str, labels: List[str], milestone: Optional[str]) -> Dict:
        pass

    @abstractmethod
    def create_milestone(self, repo: str, title: str, description: str, due_date: Optional[str]) -> Dict:
        pass

    @abstractmethod
    def link_issues(self, repo1: str, issue1: int, repo2: str, issue2: int) -> bool:
        pass

    @abstractmethod
    def get_issues(self, repo: str, state: str = 'open', labels: Optional[List[str]] = None) -> List[Dict]:
        pass


class IssueTracker:
    """Main tracker for cross-repository coordination"""

    def __init__(self, provider: str = 'github', config_path: str = "configs/tracker.yaml"):
        self.provider_name = provider
        self.provider = self._load_provider(provider)
        self.epics = {}  # Track epics across repositories
        self._load_epic_state()

    def _load_provider(self, name: str) -> ProviderInterface:
        """Load the appropriate provider"""
        if name == 'github':
            from octo.providers.github import GitHubProvider
            return GitHubProvider()
        elif name == 'gitlab':
            from octo.providers.gitlab import GitLabProvider
            return GitLabProvider()
        elif name == 'gitea':
            from octo.providers.gitea import GiteaProvider
            return GiteaProvider()
        else:
            raise ValueError(f"Unknown provider: {name}")

    def _load_epic_state(self):
        """Load epic state from git notes"""
        try:
            result = subprocess.check_output(
                ["git", "notes", "--ref=epics", "list"],
                text=True
            )
            for line in result.strip().split('\n'):
                if line:
                    note_hash, commit = line.split()
                    note_content = subprocess.check_output(
                        ["git", "notes", "--ref=epics", "show", commit],
                        text=True
                    )
                    epic_data = json.loads(note_content)
                    self.epics[epic_data['epic_id']] = epic_data
        except subprocess.CalledProcessError:
            # No epics yet
            pass

    def _save_epic_state(self, epic_id: str, data: Dict):
        """Save epic state to git notes"""
        note_content = json.dumps(data)
        subprocess.run(
            ["git", "notes", "--ref=epics", "add", "-f", "-m", note_content],
            check=True
        )
        self.epics[epic_id] = data

    def create_cross_repo_epic(self, title: str, description: str, repos: List[str],
                               milestones: Optional[Dict[str, str]] = None) -> Dict:
        """
        Create an epic that spans multiple repositories
        """
        epic_id = self._generate_epic_id()
        epic_data = {
            'epic_id': epic_id,
            'title': title,
            'description': description,
            'created_at': datetime.now().isoformat(),
            'repositories': repos,
            'issues': {},
            'milestones': milestones or {},
            'status': 'open'
        }

        # Create issues in each repository
        for repo in repos:
            issue_title = f"[EPIC-{epic_id}] {title}"
            issue_body = f"""
## Epic: {title}

{description}

### Epic Tracking
- Epic ID: `{epic_id}`
- Cross-repository epic spanning: {', '.join(repos)}
- Created: {epic_data['created_at']}

### Related Issues
This issue will be updated with links to related issues across repositories.

---
*This issue is part of a cross-repository epic managed by repo-octo*
            """

            labels = ['epic', 'cross-repo']
            milestone = milestones.get(repo) if milestones else None

            try:
                issue = self.provider.create_issue(
                    repo=repo,
                    title=issue_title,
                    body=issue_body,
                    labels=labels,
                    milestone=milestone
                )

                epic_data['issues'][repo] = {
                    'number': issue['number'],
                    'url': issue['url'],
                    'state': 'open'
                }

                logger.info(f"Created epic issue #{issue['number']} in {repo}")
            except Exception as e:
                logger.error(f"Failed to create epic issue in {repo}: {e}")

        # Save epic state
        self._save_epic_state(epic_id, epic_data)

        return epic_data

    def _generate_epic_id(self) -> str:
        """Generate unique epic ID"""
        timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
        return f"EP{timestamp}"

    def create_coordinated_milestone(self, title: str, description: str,
                                     repos: List[str], due_date: Optional[str] = None) -> Dict:
        """
        Create synchronized milestones across multiple repositories
        """
        milestone_data = {
            'title': title,
            'description': description,
            'due_date': due_date or (datetime.now() + timedelta(days=30)).isoformat(),
            'repositories': {},
            'created_at': datetime.now().isoformat()
        }

        for repo in repos:
            try:
                milestone = self.provider.create_milestone(
                    repo=repo,
                    title=title,
                    description=f"{description}\n\n*Coordinated milestone across: {', '.join(repos)}*",
                    due_date=due_date
                )

                milestone_data['repositories'][repo] = {
                    'number': milestone['number'],
                    'state': 'open',
                    'url': milestone.get('url', '')
                }

                logger.info(f"Created milestone '{title}' in {repo}")
            except Exception as e:
                logger.error(f"Failed to create milestone in {repo}: {e}")

        return milestone_data

    def link_related_issues(self, issue_links: List[tuple[str, int, str, int]]) -> List[bool]:
        """
        Link related issues across repositories
        Args:
            issue_links: List of tuples (repo1, issue1, repo2, issue2)
        """
        results = []
        for repo1, issue1, repo2, issue2 in issue_links:
            try:
                success = self.provider.link_issues(
                    repo1, issue1, repo2, issue2)
                results.append(success)

                if success:
                    logger.info(
                        f"Linked {repo1}#{issue1} <-> {repo2}#{issue2}")
            except Exception as e:
                logger.error(f"Failed to link issues: {e}")
                results.append(False)

        return results

    def get_epic_status(self, epic_id: str) -> Dict:
        """Get the current status of an epic"""
        if epic_id not in self.epics:
            raise ValueError(f"Epic {epic_id} not found")

        epic = self.epics[epic_id]
        status = {
            'epic_id': epic_id,
            'title': epic['title'],
            'created_at': epic['created_at'],
            'repositories': {},
            'progress': {}
        }

        total_issues = 0
        closed_issues = 0

        for repo, issue_data in epic['issues'].items():
            issues = self.provider.get_issues(
                repo=repo,
                state='all',
                labels=['epic', f'epic-{epic_id}']
            )

            repo_open = sum(1 for i in issues if i['state'] == 'open')
            repo_closed = sum(1 for i in issues if i['state'] == 'closed')

            status['repositories'][repo] = {
                'open': repo_open,
                'closed': repo_closed,
                'total': repo_open + repo_closed
            }

            total_issues += repo_open + repo_closed
            closed_issues += repo_closed

        status['progress'] = {
            'total': total_issues,
            'completed': closed_issues,
            'percentage': (closed_issues / total_issues * 100) if total_issues > 0 else 0
        }

        return status

    def create_release_checklist(self, version: str, repos: List[str]) -> Dict:
        """
        Create a release checklist across repositories
        """
        checklist_items = [
            "Update version numbers",
            "Update CHANGELOG.md",
            "Run test suite",
            "Update documentation",
            "Create git tag",
            "Build and publish artifacts",
            "Update dependency versions in dependent repos",
            "Deploy to staging",
            "Smoke test staging",
            "Deploy to production",
            "Verify production deployment",
            "Announce release"
        ]

        checklist_data = {
            'version': version,
            'created_at': datetime.now().isoformat(),
            'repositories': {}
        }

        for repo in repos:
            checklist_body = f"""
## Release Checklist for v{version}

### Pre-release
- [ ] Update version numbers
- [ ] Update CHANGELOG.md
- [ ] Run test suite
- [ ] Update documentation

### Release
- [ ] Create git tag
- [ ] Build and publish artifacts
- [ ] Update dependency versions in dependent repos

### Deployment
- [ ] Deploy to staging
- [ ] Smoke test staging
- [ ] Deploy to production
- [ ] Verify production deployment

### Post-release
- [ ] Announce release
- [ ] Close milestone
- [ ] Archive release artifacts

---
*Generated by repo-octo*
            """

            try:
                issue = self.provider.create_issue(
                    repo=repo,
                    title=f"Release Checklist: v{version}",
                    body=checklist_body,
                    labels=['release', 'checklist'],
                    milestone=f"v{version}"
                )

                checklist_data['repositories'][repo] = {
                    'issue_number': issue['number'],
                    'url': issue['url']
                }

                logger.info(f"Created release checklist in {repo}")
            except Exception as e:
                logger.error(
                    f"Failed to create release checklist in {repo}: {e}")

        return checklist_data

    def aggregate_issue_metrics(self, repos: List[str],
                                start_date: Optional[str] = None,
                                end_date: Optional[str] = None) -> Dict:
        """
        Aggregate issue metrics across multiple repositories
        """
        metrics = {
            'repositories': {},
            'totals': {
                'open': 0,
                'closed': 0,
                'total': 0
            },
            'by_label': {},
            'response_times': []
        }

        for repo in repos:
            try:
                all_issues = self.provider.get_issues(repo, state='all')

                repo_metrics = {
                    'open': sum(1 for i in all_issues if i['state'] == 'open'),
                    'closed': sum(1 for i in all_issues if i['state'] == 'closed'),
                    'total': len(all_issues),
                    'labels': {}
                }

                # Count by label
                for issue in all_issues:
                    for label in issue.get('labels', []):
                        label_name = label if isinstance(
                            label, str) else label.get('name', '')
                        repo_metrics['labels'][label_name] = repo_metrics['labels'].get(
                            label_name, 0) + 1
                        metrics['by_label'][label_name] = metrics['by_label'].get(
                            label_name, 0) + 1

                metrics['repositories'][repo] = repo_metrics
                metrics['totals']['open'] += repo_metrics['open']
                metrics['totals']['closed'] += repo_metrics['closed']
                metrics['totals']['total'] += repo_metrics['total']

            except Exception as e:
                logger.error(f"Failed to get metrics for {repo}: {e}")

        return metrics

    def sync_labels_across_repos(self, repos: List[str], labels: List[Dict[str, str]]) -> Dict:
        """
        Synchronize label definitions across repositories
        Args:
            labels: List of dicts with 'name', 'color', 'description'
        """
        results = {'success': [], 'failed': []}

        for repo in repos:
            for label in labels:
                try:
                    self.provider.create_label(
                        repo=repo,
                        name=label['name'],
                        color=label.get('color', 'ffffff'),
                        description=label.get('description', '')
                    )
                    results['success'].append(f"{repo}:{label['name']}")
                except Exception as e:
                    logger.error(
                        f"Failed to create label {label['name']} in {repo}: {e}")
                    results['failed'].append(f"{repo}:{label['name']}")

        return results
