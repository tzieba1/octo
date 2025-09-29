"""
GitHub provider implementation for issue tracking and repository management
"""

import os
import json
import subprocess
from typing import Dict, List, Optional
from datetime import datetime
import logging

logger = logging.getLogger(__name__)


class GitHubProvider:
    """GitHub-specific implementation using GitHub CLI"""
    
    def __init__(self):
        self.owner = self._get_owner()
        self._verify_cli()
    
    def _get_owner(self) -> str:
        """Get repository owner from git config"""
        try:
            result = subprocess.check_output(
                ["git", "config", "--get", "remote.origin.url"],
                text=True
            ).strip()
            
            # Parse owner from URL
            if "github.com" in result:
                if result.startswith("git@"):
                    # SSH format: git@github.com:owner/repo.git
                    parts = result.split(":")[-1].split("/")
                else:
                    # HTTPS format: https://github.com/owner/repo.git
                    parts = result.split("/")[-2:]
                
                return parts[0]
        except:
            pass
        
        # Fallback to environment variable or config
        return os.environ.get('GITHUB_OWNER', 'user')
    
    def _verify_cli(self):
        """Verify GitHub CLI is installed and authenticated"""
        try:
            subprocess.run(
                ["gh", "auth", "status"],
                check=True,
                capture_output=True
            )
        except subprocess.CalledProcessError:
            raise RuntimeError("GitHub CLI not authenticated. Run 'gh auth login' first.")
        except FileNotFoundError:
            raise RuntimeError("GitHub CLI not found. Install from https://cli.github.com")
    
    def create_issue(self, repo: str, title: str, body: str, 
                    labels: List[str], milestone: Optional[str] = None) -> Dict:
        """Create an issue in a repository"""
        cmd = [
            "gh", "issue", "create",
            "--repo", f"{self.owner}/{repo}",
            "--title", title,
            "--body", body
        ]
        
        if labels:
            cmd.extend(["--label", ",".join(labels)])
        
        if milestone:
            cmd.extend(["--milestone", milestone])
        
        try:
            result = subprocess.check_output(cmd, text=True).strip()
            
            # Parse the issue URL to get number
            issue_number = result.split("/")[-1]
            
            return {
                'number': int(issue_number),
                'url': result,
                'title': title,
                'state': 'open'
            }
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to create issue: {e}")
            raise
    
    def create_milestone(self, repo: str, title: str, 
                        description: str, due_date: Optional[str] = None) -> Dict:
        """Create a milestone in a repository"""
        # GitHub CLI doesn't have direct milestone creation, use API
        cmd = [
            "gh", "api",
            f"repos/{self.owner}/{repo}/milestones",
            "--method", "POST",
            "--field", f"title={title}",
            "--field", f"description={description}"
        ]
        
        if due_date:
            # Convert to ISO format if needed
            if not due_date.endswith('Z'):
                due_date = f"{due_date}T00:00:00Z"
            cmd.extend(["--field", f"due_on={due_date}"])
        
        try:
            result = subprocess.check_output(cmd, text=True)
            data = json.loads(result)
            
            return {
                'number': data['number'],
                'title': data['title'],
                'state': data['state'],
                'url': data['html_url']
            }
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to create milestone: {e}")
            raise
    
    def link_issues(self, repo1: str, issue1: int, 
                   repo2: str, issue2: int) -> bool:
        """Link two issues by adding cross-references"""
        try:
            # Add comment to first issue
            comment1 = f"Related to {self.owner}/{repo2}#{issue2}"
            subprocess.run([
                "gh", "issue", "comment", str(issue1),
                "--repo", f"{self.owner}/{repo1}",
                "--body", comment1
            ], check=True)
            
            # Add comment to second issue
            comment2 = f"Related to {self.owner}/{repo1}#{issue1}"
            subprocess.run([
                "gh", "issue", "comment", str(issue2),
                "--repo", f"{self.owner}/{repo2}",
                "--body", comment2
            ], check=True)
            
            return True
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to link issues: {e}")
            return False
    
    def get_issues(self, repo: str, state: str = 'open', 
                  labels: Optional[List[str]] = None) -> List[Dict]:
        """Get issues from a repository"""
        cmd = [
            "gh", "issue", "list",
            "--repo", f"{self.owner}/{repo}",
            "--state", state,
            "--json", "number,title,state,labels,milestone,createdAt,closedAt"
        ]
        
        if labels:
            cmd.extend(["--label", ",".join(labels)])
        
        if state == 'all':
            # GitHub CLI doesn't have 'all' state, so get both
            cmd[cmd.index('all')] = 'open'
            open_issues = json.loads(subprocess.check_output(cmd, text=True))
            
            cmd[cmd.index('open')] = 'closed'
            closed_issues = json.loads(subprocess.check_output(cmd, text=True))
            
            issues = open_issues + closed_issues
        else:
            result = subprocess.check_output(cmd, text=True)
            issues = json.loads(result)
        
        # Format the response
        formatted = []
        for issue in issues:
            formatted.append({
                'number': issue['number'],
                'title': issue['title'],
                'state': issue['state'],
                'labels': [label['name'] for label in issue.get('labels', [])],
                'milestone': issue.get('milestone', {}).get('title') if issue.get('milestone') else None,
                'created_at': issue.get('createdAt'),
                'closed_at': issue.get('closedAt')
            })
        
        return formatted
    
    def create_label(self, repo: str, name: str, 
                    color: str, description: str = "") -> bool:
        """Create a label in a repository"""
        try:
            subprocess.run([
                "gh", "label", "create", name,
                "--repo", f"{self.owner}/{repo}",
                "--color", color,
                "--description", description
            ], check=True, capture_output=True)
            
            return True
        except subprocess.CalledProcessError:
            # Label might already exist, try to update it
            try:
                subprocess.run([
                    "gh", "label", "edit", name,
                    "--repo", f"{self.owner}/{repo}",
                    "--color", color,
                    "--description", description
                ], check=True, capture_output=True)
                
                return True
            except subprocess.CalledProcessError as e:
                logger.error(f"Failed to create/update label: {e}")
                return False
    
    def create_release(self, repo: str, tag: str, title: str, 
                      notes: str, prerelease: bool = False) -> Dict:
        """Create a release"""
        cmd = [
            "gh", "release", "create", tag,
            "--repo", f"{self.owner}/{repo}",
            "--title", title,
            "--notes", notes
        ]
        
        if prerelease:
            cmd.append("--prerelease")
        
        try:
            result = subprocess.check_output(cmd, text=True).strip()
            
            return {
                'tag': tag,
                'title': title,
                'url': result,
                'prerelease': prerelease
            }
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to create release: {e}")
            raise
    
    def get_pull_requests(self, repo: str, state: str = 'open') -> List[Dict]:
        """Get pull requests from a repository"""
        cmd = [
            "gh", "pr", "list",
            "--repo", f"{self.owner}/{repo}",
            "--state", state,
            "--json", "number,title,state,author,createdAt,mergedAt,labels"
        ]
        
        result = subprocess.check_output(cmd, text=True)
        prs = json.loads(result)
        
        formatted = []
        for pr in prs:
            formatted.append({
                'number': pr['number'],
                'title': pr['title'],
                'state': pr['state'],
                'author': pr['author']['login'],
                'created_at': pr['createdAt'],
                'merged_at': pr.get('mergedAt'),
                'labels': [label['name'] for label in pr.get('labels', [])]
            })
        
        return formatted
    
    def create_pull_request(self, repo: str, title: str, body: str,
                          base: str = 'main', head: str = None) -> Dict:
        """Create a pull request"""
        cmd = [
            "gh", "pr", "create",
            "--repo", f"{self.owner}/{repo}",
            "--title", title,
            "--body", body,
            "--base", base
        ]
        
        if head:
            cmd.extend(["--head", head])
        
        try:
            result = subprocess.check_output(cmd, text=True).strip()
            
            # Parse PR number from URL
            pr_number = result.split("/")[-1]
            
            return {
                'number': int(pr_number),
                'url': result,
                'title': title,
                'state': 'open'
            }
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to create pull request: {e}")
            raise
    
    def get_workflows(self, repo: str) -> List[Dict]:
        """Get GitHub Actions workflows"""
        cmd = [
            "gh", "workflow", "list",
            "--repo", f"{self.owner}/{repo}",
            "--json", "name,state,path"
        ]
        
        result = subprocess.check_output(cmd, text=True)
        return json.loads(result)
    
    def trigger_workflow(self, repo: str, workflow: str, 
                        ref: str = 'main', inputs: Optional[Dict] = None) -> bool:
        """Trigger a GitHub Actions workflow"""
        cmd = [
            "gh", "workflow", "run", workflow,
            "--repo", f"{self.owner}/{repo}",
            "--ref", ref
        ]
        
        if inputs:
            for key, value in inputs.items():
                cmd.extend(["--field", f"{key}={value}"])
        
        try:
            subprocess.run(cmd, check=True)
            return True
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to trigger workflow: {e}")
            return False
    
    def get_workflow_runs(self, repo: str, workflow: Optional[str] = None) -> List[Dict]:
        """Get workflow run history"""
        cmd = [
            "gh", "run", "list",
            "--repo", f"{self.owner}/{repo}",
            "--json", "databaseId,name,status,conclusion,createdAt"
        ]
        
        if workflow:
            cmd.extend(["--workflow", workflow])
        
        result = subprocess.check_output(cmd, text=True)
        runs = json.loads(result)
        
        return [{
            'id': run['databaseId'],
            'name': run['name'],
            'status': run['status'],
            'conclusion': run.get('conclusion'),
            'created_at': run['createdAt']
        } for run in runs]
    
    def create_project(self, repo: str, name: str, 
                      body: str = "", public: bool = True) -> Dict:
        """Create a project board"""
        # Using GraphQL for project creation
        query = """
        mutation($ownerId: ID!, $title: String!, $body: String!) {
          createProjectV2(input: {
            ownerId: $ownerId,
            title: $title,
            body: $body
          }) {
            projectV2 {
              id
              number
              title
              url
            }
          }
        }
        """
        
        # Get repository ID first
        repo_data = subprocess.check_output([
            "gh", "api", f"repos/{self.owner}/{repo}",
            "--jq", ".node_id"
        ], text=True).strip()
        
        variables = {
            "ownerId": repo_data,
            "title": name,
            "body": body
        }
        
        try:
            result = subprocess.check_output([
                "gh", "api", "graphql",
                "-f", f"query={query}",
                "--jq", ".data.createProjectV2.projectV2"
            ] + [f"-f {k}={v}" for k, v in variables.items()], text=True)
            
            return json.loads(result)
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to create project: {e}")
            raise