"""
GitLab provider implementation for issue tracking and repository management
"""

import os
import json
import subprocess
from typing import Dict, List, Optional
import requests
from urllib.parse import quote
import logging

logger = logging.getLogger(__name__)


class GitLabProvider:
    """GitLab-specific implementation using GitLab API"""
    
    def __init__(self):
        self.api_url = os.environ.get('GITLAB_API_URL', 'https://gitlab.com/api/v4')
        self.token = os.environ.get('GITLAB_TOKEN')
        
        if not self.token:
            raise ValueError("GITLAB_TOKEN environment variable is required")
        
        self.headers = {
            'PRIVATE-TOKEN': self.token,
            'Content-Type': 'application/json'
        }
        
        self.namespace = self._get_namespace()
    
    def _get_namespace(self) -> str:
        """Get namespace/group from git config"""
        try:
            result = subprocess.check_output(
                ["git", "config", "--get", "remote.origin.url"],
                text=True
            ).strip()
            
            if "gitlab.com" in result:
                # Parse namespace from URL
                parts = result.split("/")[-2:]
                namespace = parts[0].split(":")[-1]
                return namespace
        except:
            pass
        
        return os.environ.get('GITLAB_NAMESPACE', 'user')
    
    def _get_project_id(self, repo: str) -> str:
        """Get GitLab project ID from repo name"""
        project_path = f"{self.namespace}/{repo}"
        encoded_path = quote(project_path, safe='')
        
        response = requests.get(
            f"{self.api_url}/projects/{encoded_path}",
            headers=self.headers
        )
        
        if response.status_code == 200:
            return response.json()['id']
        else:
            raise ValueError(f"Project {project_path} not found")
    
    def create_issue(self, repo: str, title: str, body: str,
                    labels: List[str], milestone: Optional[str] = None) -> Dict:
        """Create an issue in a repository"""
        project_id = self._get_project_id(repo)
        
        data = {
            'title': title,
            'description': body,
            'labels': ','.join(labels)
        }
        
        if milestone:
            # Get milestone ID
            milestones = requests.get(
                f"{self.api_url}/projects/{project_id}/milestones",
                headers=self.headers,
                params={'title': milestone}
            ).json()
            
            if milestones:
                data['milestone_id'] = milestones[0]['id']
        
        response = requests.post(
            f"{self.api_url}/projects/{project_id}/issues",
            headers=self.headers,
            json=data
        )
        
        if response.status_code == 201:
            issue = response.json()
            return {
                'number': issue['iid'],
                'url': issue['web_url'],
                'title': issue['title'],
                'state': issue['state']
            }
        else:
            raise RuntimeError(f"Failed to create issue: {response.text}")
    
    def create_milestone(self, repo: str, title: str,
                        description: str, due_date: Optional[str] = None) -> Dict:
        """Create a milestone in a repository"""
        project_id = self._get_project_id(repo)
        
        data = {
            'title': title,
            'description': description
        }
        
        if due_date:
            # Format: YYYY-MM-DD
            if 'T' in due_date:
                due_date = due_date.split('T')[0]
            data['due_date'] = due_date
        
        response = requests.post(
            f"{self.api_url}/projects/{project_id}/milestones",
            headers=self.headers,
            json=data
        )
        
        if response.status_code == 201:
            milestone = response.json()
            return {
                'number': milestone['iid'],
                'title': milestone['title'],
                'state': milestone['state'],
                'url': milestone['web_url']
            }
        else:
            raise RuntimeError(f"Failed to create milestone: {response.text}")
    
    def link_issues(self, repo1: str, issue1: int,
                   repo2: str, issue2: int) -> bool:
        """Link two issues using related issues"""
        project1_id = self._get_project_id(repo1)
        project2_id = self._get_project_id(repo2)
        
        # Add a note to each issue referencing the other
        note1 = f"Related to {self.namespace}/{repo2}#{issue2}"
        note2 = f"Related to {self.namespace}/{repo1}#{issue1}"
        
        try:
            # Add note to first issue
            response1 = requests.post(
                f"{self.api_url}/projects/{project1_id}/issues/{issue1}/notes",
                headers=self.headers,
                json={'body': note1}
            )
            
            # Add note to second issue
            response2 = requests.post(
                f"{self.api_url}/projects/{project2_id}/issues/{issue2}/notes",
                headers=self.headers,
                json={'body': note2}
            )
            
            return response1.status_code == 201 and response2.status_code == 201
        except Exception as e:
            logger.error(f"Failed to link issues: {e}")
            return False
    
    def get_issues(self, repo: str, state: str = 'open',
                  labels: Optional[List[str]] = None) -> List[Dict]:
        """Get issues from a repository"""
        project_id = self._get_project_id(repo)
        
        params = {}
        if state != 'all':
            params['state'] = 'opened' if state == 'open' else 'closed'
        
        if labels:
            params['labels'] = ','.join(labels)
        
        response = requests.get(
            f"{self.api_url}/projects/{project_id}/issues",
            headers=self.headers,
            params=params
        )
        
        if response.status_code == 200:
            issues = response.json()
            formatted = []
            
            for issue in issues:
                formatted.append({
                    'number': issue['iid'],
                    'title': issue['title'],
                    'state': 'open' if issue['state'] == 'opened' else 'closed',
                    'labels': issue.get('labels', []),
                    'milestone': issue.get('milestone', {}).get('title') if issue.get('milestone') else None,
                    'created_at': issue.get('created_at'),
                    'closed_at': issue.get('closed_at')
                })
            
            return formatted
        else:
            raise RuntimeError(f"Failed to get issues: {response.text}")
    
    def create_label(self, repo: str, name: str,
                    color: str, description: str = "") -> bool:
        """Create a label in a repository"""
        project_id = self._get_project_id(repo)
        
        # Ensure color has # prefix
        if not color.startswith('#'):
            color = f"#{color}"
        
        data = {
            'name': name,
            'color': color,
            'description': description
        }
        
        response = requests.post(
            f"{self.api_url}/projects/{project_id}/labels",
            headers=self.headers,
            json=data
        )
        
        if response.status_code == 201:
            return True
        elif response.status_code == 409:
            # Label exists, try to update
            response = requests.put(
                f"{self.api_url}/projects/{project_id}/labels/{name}",
                headers=self.headers,
                json={'new_name': name, 'color': color, 'description': description}
            )
            return response.status_code == 200
        else:
            logger.error(f"Failed to create label: {response.text}")
            return False
    
    def create_release(self, repo: str, tag: str, title: str,
                      notes: str, prerelease: bool = False) -> Dict:
        """Create a release"""
        project_id = self._get_project_id(repo)
        
        # Create tag first
        tag_data = {
            'tag_name': tag,
            'ref': 'main',
            'message': title,
            'release_description': notes
        }
        
        response = requests.post(
            f"{self.api_url}/projects/{project_id}/repository/tags",
            headers=self.headers,
            json=tag_data
        )
        
        if response.status_code in [201, 409]:  # Created or already exists
            # Create or update release
            release_data = {
                'name': title,
                'tag_name': tag,
                'description': notes
            }
            
            response = requests.post(
                f"{self.api_url}/projects/{project_id}/releases",
                headers=self.headers,
                json=release_data
            )
            
            if response.status_code in [201, 409]:
                release = response.json() if response.status_code == 201 else {'tag_name': tag}
                return {
                    'tag': tag,
                    'title': title,
                    'url': f"https://gitlab.com/{self.namespace}/{repo}/-/releases/{tag}",
                    'prerelease': prerelease
                }
        
        raise RuntimeError(f"Failed to create release: {response.text}")
    
    def get_merge_requests(self, repo: str, state: str = 'open') -> List[Dict]:
        """Get merge requests from a repository"""
        project_id = self._get_project_id(repo)
        
        params = {'state': 'opened' if state == 'open' else state}
        
        response = requests.get(
            f"{self.api_url}/projects/{project_id}/merge_requests",
            headers=self.headers,
            params=params
        )
        
        if response.status_code == 200:
            mrs = response.json()
            formatted = []
            
            for mr in mrs:
                formatted.append({
                    'number': mr['iid'],
                    'title': mr['title'],
                    'state': mr['state'],
                    'author': mr['author']['username'],
                    'created_at': mr['created_at'],
                    'merged_at': mr.get('merged_at'),
                    'labels': mr.get('labels', [])
                })
            
            return formatted
        else:
            raise RuntimeError(f"Failed to get merge requests: {response.text}")
    
    def create_merge_request(self, repo: str, title: str, body: str,
                           source_branch: str, target_branch: str = 'main') -> Dict:
        """Create a merge request"""
        project_id = self._get_project_id(repo)
        
        data = {
            'title': title,
            'description': body,
            'source_branch': source_branch,
            'target_branch': target_branch
        }
        
        response = requests.post(
            f"{self.api_url}/projects/{project_id}/merge_requests",
            headers=self.headers,
            json=data
        )
        
        if response.status_code == 201:
            mr = response.json()
            return {
                'number': mr['iid'],
                'url': mr['web_url'],
                'title': mr['title'],
                'state': 'open'
            }
        else:
            raise RuntimeError(f"Failed to create merge request: {response.text}")
    
    def trigger_pipeline(self, repo: str, ref: str = 'main',
                        variables: Optional[Dict] = None) -> Dict:
        """Trigger a CI/CD pipeline"""
        project_id = self._get_project_id(repo)
        
        data = {'ref': ref}
        if variables:
            data['variables'] = [
                {'key': k, 'value': v}
                for k, v in variables.items()
            ]
        
        response = requests.post(
            f"{self.api_url}/projects/{project_id}/pipeline",
            headers=self.headers,
            json=data
        )
        
        if response.status_code == 201:
            pipeline = response.json()
            return {
                'id': pipeline['id'],
                'status': pipeline['status'],
                'url': pipeline['web_url']
            }
        else:
            raise RuntimeError(f"Failed to trigger pipeline: {response.text}")