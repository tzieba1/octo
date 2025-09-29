"""
Repo Orchestrator - Multi-repository coordination system
"""

from .version_manager import VersionCoordinator
from .dependency_graph import DependencyResolver
from .tracker import IssueTracker
from .monitor import RepoHealthMonitor

__version__ = "0.1.0"
__all__ = [
    "VersionCoordinator",
    "DependencyResolver", 
    "IssueTracker",
    "RepoHealthMonitor"
]