#!/usr/bin/env python3
"""Main orchestration CLI"""

import click
import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from orchestrator import VersionCoordinator, DependencyResolver, IssueTracker, RepoHealthMonitor

@click.group()
def cli():
    """Repo Orchestrator - Multi-repository coordination system"""
    pass

@cli.command()
@click.argument('repo')
@click.option('--type', default='patch', help='Version bump type: patch, minor, major')
@click.option('--dry-run/--no-dry-run', default=True, help='Perform dry run')
def release(repo, type, dry_run):
    """Coordinate a release across repositories"""
    coordinator = VersionCoordinator()
    plan = coordinator.coordinate_release(repo, type)
    
    click.echo(f"Release plan for {repo}:")
    click.echo(f"  Source: {plan['source']['repo']} -> v{plan['source']['new_version']}")
    
    if plan['affected']:
        click.echo("  Affected repositories:")
        for affected in plan['affected']:
            click.echo(f"    - {affected['repo']}: {affected['suggested_action']}")
    
    if not dry_run:
        results = coordinator.execute_release_plan(plan, dry_run=False)
        click.echo(f"Results: {len(results['success'])} succeeded, {len(results['failed'])} failed")

@cli.command()
def health():
    """Check health of all repositories"""
    monitor = RepoHealthMonitor()
    report = monitor.generate_health_report()
    click.echo(report)

@cli.command()
def deps():
    """Analyze dependencies"""
    resolver = DependencyResolver()
    
    # Check for circular dependencies
    cycles = resolver.check_circular_dependencies()
    if cycles:
        click.echo("⚠️  Circular dependencies detected:")
        for cycle in cycles:
            click.echo(f"  {' -> '.join(cycle)}")
    else:
        click.echo("✅ No circular dependencies")
    
    # Show build order
    order = resolver.get_build_order()
    click.echo(f"\nBuild order: {' -> '.join(order)}")

if __name__ == '__main__':
    cli()
