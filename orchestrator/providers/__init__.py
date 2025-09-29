"""
Provider implementations for different Git hosting platforms
"""

from .github import GitHubProvider
from .gitlab import GitLabProvider
from .gitea import GiteaProvider

__all__ = [
    'GitHubProvider',
    'GitLabProvider',
    'GiteaProvider'
]

def get_provider(name: str):
    """
    Factory function to get the appropriate provider
    
    Args:
        name: Provider name ('github', 'gitlab', 'gitea')
    
    Returns:
        Provider instance
    
    Raises:
        ValueError: If provider name is not recognized
    """
    providers = {
        'github': GitHubProvider,
        'gitlab': GitLabProvider,
        'gitea': GiteaProvider
    }
    
    if name not in providers:
        raise ValueError(f"Unknown provider: {name}. Available: {', '.join(providers.keys())}")
    
    return providers[name]()