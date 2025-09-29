"""
Gitea provider implementation for issue tracking and repository management
"""

import os
import json
import subprocess
from typing import Dict, List, Optional
import requests
from urllib.parse import quote
import logging

logger = logging.getLogger(__name__)


class GiteaProvider:
    """Gitea-specific implementation using Gitea API"""
    
    def __init__(self):
        self.api_url = os.environ.get('GITEA_API_URL', 'https://gitea.example.com/api/v1')
        self.token = os.environ.get('GITEA_TOKEN')
        
        if not self.token:
            raise ValueError("GITEA_TOKEN environment variable is required")
        
        self.headers = {
            'Authorization': f'token {self.token}',
            'Content-Type': 'application/json'
        }
        
        self.owner = self._get_owner()
    
    def _get_owner(self) -> str:
        """Get repository owner from git config or environment"""
        try:
            result = subprocess.check_output(
                ["git", "config", "--get", "remote.origin.url"],
                text=True
            ).strip()
            
            # Parse owner from URL
            if "gitea" in result:
                parts = result.split("/")[-2:]
                owner = parts[0].split(":")[-1]
                return owner
        except:
            pass
        
        return os.environ.get('GITEA_OWNER', 'user')
    
    def create_issue(self, repo: str, title: str, body: str,
                    labels: List[str], milestone: Optional[str] = None) -> Dict:
        """Create an issue in a repository"""
        
        # Get or create labels first
        label_ids = []
        for label_name in labels:
            label_resp = requests.get(
                f"{self.api_url}/repos/{self.owner}/{repo}/labels",
                headers=self.headers
            )
            
            if label_resp.status_code == 200:
                existing_labels = label_resp.json()
                label_id = None
                
                for existing in existing_labels:
                    if existing['name'] == label_name:
                        label_id = existing['id']
                        break
                
                if label_id:
                    label_ids.append(label_id)
                else:
                    # Create new label
                    new_label = requests.post(
                        f"{self.api_url}/repos/{self.owner}/{repo}/labels",
                        headers=self.headers,
                        json={
                            'name': label_name,
                            'color': '#' + ''.join(['%02x' % x for x in [100, 100, 100]])
                        }
                    )
                    if new_label.status_code == 201:
                        label_ids.append(new_label.json()['id'])
        
        data = {
            'title': title,
            'body': body,
            'labels': label_ids
        }
        
        if milestone:
            # Get milestone ID
            milestones = requests.get(
                f"{self.api_url}/repos/{self.owner}/{repo}/milestones",
                headers=self.headers
            ).json()
            
            for ms in milestones:
                if ms['title'] == milestone:
                    data['milestone'] = ms['id']
                    break
        
        response = requests.post(
            f"{self.api_url}/repos/{self.owner}/{repo}/issues",
            headers=self.headers,
            json=data
        )
        
        if response.status_code == 201:
            issue = response.json()
            return {
                'number': issue['number'],
                'url': issue['html_url'],
                'title': issue['title'],
                'state': issue['state']
            }
        else:
            raise RuntimeError(f"Failed to create issue: {response.text}")
    
    def create_milestone(self, repo: str, title: str,
                        description: str, due_date: Optional[str] = None) -> Dict:
        """Create a milestone in a repository"""
        data = {
            'title': title,
            'description': description,
            'state': 'open'
        }
        
        if due_date:
            # Convert to ISO format
            if not due_date.endswith('Z'):
                due_date = f"{due_date.split('T')[0]}T23:59:59Z"
            data['due_on'] = due_date
        
        response = requests.post(
            f"{self.api_url}/repos/{self.owner}/{repo}/milestones",
            headers=self.headers,
            json=data
        )
        
        if response.status_code == 201:
            milestone = response.json()
            return {
                'number': milestone['id'],
                'title': milestone['title'],
                'state': milestone['state'],
                'url': f"{self.api_url.replace('/api/v1', '')}/{self.owner}/{repo}/milestone/{milestone['id']}"
            }
        else:
            raise RuntimeError(f"Failed to create milestone: {response.text}")
    
    def link_issues(self, repo1: str, issue1: int,
                   repo2: str, issue2: int) -> bool:
        """Link two issues by adding cross-references in comments"""
        try:
            # Add comment to first issue
            comment1 = f"Related to {self.owner}/{repo2}#{issue2}"
            response1 = requests.post(
                f"{self.api_url}/repos/{self.owner}/{repo1}/issues/{issue1}/comments",
                headers=self.headers,
                json={'body': comment1}
            )
            
            # Add comment to second issue
            comment2 = f"Related to {self.owner}/{repo1}#{issue1}"
            response2 = requests.post(
                f"{self.api_url}/repos/{self.owner}/{repo2}/issues/{issue2}/comments",
                headers=self.headers,
                json={'body': comment2}
            )
            
            return response1.status_code == 201 and response2.status_code == 201
        except Exception as e:
            logger.error(f"Failed to link issues: {e}")
            return False
    
    def get_issues(self, repo: str, state: str = 'open',
                  labels: Optional[List[str]] = None) -> List[Dict]:
        """Get issues from a repository"""
        params = {
            'state': state if state != 'all' else 'all',
            'type': 'issues'
        }
        
        if labels:
            params['labels'] = ','.join(labels)
        
        response = requests.get(
            f"{self.api_url}/repos/{self.owner}/{repo}/issues",
            headers=self.headers,
            params=params
        )
        
        if response.status_code == 200:
            issues = response.json()
            formatted = []
            
            for issue in issues:
                # Skip pull requests
                if 'pull_request' in issue:
                    continue
                    
                formatted.append({
                    'number': issue['number'],
                    'title': issue['title'],
                    'state': issue['state'],
                    'labels': [label['name'] for label in issue.get('labels', [])],
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
        # Ensure color format is correct
        if not color.startswith('#'):
            color = f"#{color}"
        color = color[1:]  # Gitea expects color without #
        
        data = {
            'name': name,
            'color': color,
            'description': description
        }
        
        response = requests.post(
            f"{self.api_url}/repos/{self.owner}/{repo}/labels",
            headers=self.headers,
            json=data
        )
        
        if response.status_code == 201:
            return True
        elif response.status_code == 409:
            # Label exists, try to update
            response = requests.patch(
                f"{self.api_url}/repos/{self.owner}/{repo}/labels/{name}",
                headers=self.headers,
                json=data
            )
            return response.status_code == 200
        else:
            logger.error(f"Failed to create label: {response.text}")
            return False
    
    def create_release(self, repo: str, tag: str, title: str,
                      notes: str, prerelease: bool = False) -> Dict:
        """Create a release"""
        data = {
            'tag_name': tag,
            'name': title,
            'body': notes,
            'prerelease': prerelease,
            'target_commitish': 'main'
        }
        
        response = requests.post(
            f"{self.api_url}/repos/{self.owner}/{repo}/releases",
            headers=self.headers,
            json=data
        )
        
        if response.status_code in [201, 409]:
            if response.status_code == 201:
                release = response.json()
            else:
                # Release exists, get it
                releases = requests.get(
                    f"{self.api_url}/repos/{self.owner}/{repo}/releases",
                    headers=self.headers
                ).json()
                
                release = next((r for r in releases if r['tag_name'] == tag), {'tag_name': tag})
            
            return {
                'tag': tag,
                'title': title,
                'url': release.get('html_url', f"{self.api_url.replace('/api/v1', '')}/{self.owner}/{repo}/releases/tag/{tag}"),
                'prerelease': prerelease
            }
        else:
            raise RuntimeError(f"Failed to create release: {response.text}")
    
    def get_pull_requests(self, repo: str, state: str = 'open') -> List[Dict]:
        """Get pull requests from a repository"""
        params = {
            'state': state if state != 'all' else 'all'
        }
        
        response = requests.get(
            f"{self.api_url}/repos/{self.owner}/{repo}/pulls",
            headers=self.headers,
            params=params
        )
        
        if response.status_code == 200:
            prs = response.json()
            formatted = []
            
            for pr in prs:
                formatted.append({
                    'number': pr['number'],
                    'title': pr['title'],
                    'state': pr['state'],
                    'author': pr['user']['login'],
                    'created_at': pr['created_at'],
                    'merged_at': pr.get('merged_at'),
                    'labels': [label['name'] for label in pr.get('labels', [])]
                })
            
            return formatted
        else:
            raise RuntimeError(f"Failed to get pull requests: {response.text}")
    
    def create_pull_request(self, repo: str, title: str, body: str,
                          head: str, base: str = 'main') -> Dict:
        """Create a pull request"""
        data = {
            'title': title,
            'body': body,
            'head': head,
            'base': base
        }
        
        response = requests.post(
            f"{self.api_url}/repos/{self.owner}/{repo}/pulls",
            headers=self.headers,
            json=data
        )
        
        if response.status_code == 201:
            pr = response.json()
            return {
                'number': pr['number'],
                'url': pr['html_url'],
                'title': pr['title'],
                'state': 'open'
            }
        else:
            raise RuntimeError(f"Failed to create pull request: {response.text}")
    
    def get_repository_info(self, repo: str) -> Dict:
        """Get repository information"""
        response = requests.get(
            f"{self.api_url}/repos/{self.owner}/{repo}",
            headers=self.headers
        )
        
        if response.status_code == 200:
            repo_data = response.json()
            return {
                'name': repo_data['name'],
                'full_name': repo_data['full_name'],
                'description': repo_data['description'],
                'default_branch': repo_data['default_branch'],
                'created_at': repo_data['created_at'],
                'updated_at': repo_data['updated_at'],
                'clone_url': repo_data['clone_url'],
                'ssh_url': repo_data['ssh_url']
            }
        else:
            raise RuntimeError(f"Failed to get repository info: {response.text}")