from setuptools import setup, find_packages

setup(
    name="repo-octo",
    version="0.1.0",
    packages=find_packages(),
    python_requires=">=3.8",
    install_requires=[
        "pyyaml>=6.0",
        "semantic-version>=2.10.0",
        "networkx>=3.0",
        "matplotlib>=3.6",
        "requests>=2.28",
        "click>=8.1",
    ],
    entry_points={
        'console_scripts': [
            'orchestrate=scripts.orchestrate:cli',
        ],
    },
)
