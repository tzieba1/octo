# Repo Orchestrator Makefile
.PHONY: help install test lint format clean bootstrap health release rollback

# Default target
help:
	@echo "Repo Orchestrator - Available Commands:"
	@echo ""
	@echo "Setup & Installation:"
	@echo "  make bootstrap    - Initial setup and configuration"
	@echo "  make install      - Install Python dependencies"
	@echo "  make install-dev  - Install development dependencies"
	@echo ""
	@echo "Repository Management:"
	@echo "  make clone-all    - Clone all configured repositories"
	@echo "  make pull-all     - Pull latest changes for all repos"
	@echo "  make status       - Show status of all repositories"
	@echo ""
	@echo "Health & Monitoring:"
	@echo "  make health       - Run health checks on all repositories"
	@echo "  make metrics      - Collect and display metrics"
	@echo "  make deps-check   - Check dependency status"
	@echo ""
	@echo "Release Management:"
	@echo "  make release      - Start interactive release process"
	@echo "  make rollback     - Emergency rollback procedure"
	@echo "  make changelog    - Generate changelogs"
	@echo ""
	@echo "Development:"
	@echo "  make test         - Run test suite"
	@echo "  make test-cov     - Run tests with coverage"
	@echo "  make lint         - Run code linting"
	@echo "  make format       - Format code with black"
	@echo "  make clean        - Clean temporary files"
	@echo ""
	@echo "Docker:"
	@echo "  make docker-build - Build orchestrator Docker image"
	@echo "  make docker-run   - Run orchestrator in Docker"

# Setup & Installation
bootstrap:
	@echo "🚀 Bootstrapping Repo Orchestrator..."
	@bash scripts/bootstrap.sh

install:
	@echo "📦 Installing dependencies..."
	@pip install -r requirements.txt

install-dev: install
	@echo "🔧 Installing development dependencies..."
	@pip install -r requirements-dev.txt 2>/dev/null || true
	@pre-commit install 2>/dev/null || true

# Repository Management
clone-all:
	@echo "📥 Cloning all repositories..."
	@mkdir -p repos
	@python3 -c "import yaml; config=yaml.safe_load(open('configs/repositories.yaml')); \
		import subprocess; \
		[subprocess.run(['git', 'clone', repo['url'], f\"repos/{name}\"], capture_output=True) \
		for name, repo in config['repositories'].items()]"
	@echo "✅ All repositories cloned"

pull-all:
	@echo "🔄 Updating all repositories..."
	@for repo in repos/*; do \
		if [ -d "$$repo/.git" ]; then \
			echo "  Updating $$(basename $$repo)..."; \
			git -C "$$repo" pull origin main --quiet; \
		fi \
	done
	@echo "✅ All repositories updated"

status:
	@echo "📊 Repository Status:"
	@echo "========================"
	@for repo in repos/*; do \
		if [ -d "$$repo/.git" ]; then \
			echo "\n$$(basename $$repo):"; \
			git -C "$$repo" status --short; \
		fi \
	done

# Health & Monitoring
health:
	@echo "🏥 Running health checks..."
	@python3 scripts/orchestrate.py health

metrics:
	@echo "📈 Collecting metrics..."
	@python3 -c "from orchestrator import RepoHealthMonitor; \
		monitor = RepoHealthMonitor(); \
		metrics = monitor.collect_metrics(); \
		print(f\"Health Score: {metrics['health_score']:.1f}/100\")"

deps-check:
	@echo "🔍 Checking dependencies..."
	@bash scripts/deps/track-dependencies.sh check

deps-status:
	@bash scripts/deps/track-dependencies.sh status all

deps-lock:
	@echo "🔒 Creating dependency lock file..."
	@bash scripts/deps/track-dependencies.sh lock

# Release Management
release:
	@echo "🚀 Starting release process..."
	@echo "Repository to release:"
	@read -p "Repository name: " repo; \
	read -p "Release type (patch/minor/major): " type; \
	python3 scripts/orchestrate.py release $$repo --type $$type

prepare-release:
	@read -p "Version (e.g., v2.0.0): " version; \
	bash scripts/release/prepare-release.sh $$version all

rollback:
	@echo "⚠️  EMERGENCY ROLLBACK"
	@read -p "Current version: " current; \
	read -p "Target version: " target; \
	read -p "Repositories (all or comma-separated): " repos; \
	bash scripts/release/rollback-release.sh $$current $$target $$repos

changelog:
	@echo "📝 Generating changelogs..."
	@for repo in repos/*; do \
		if [ -d "$$repo/.git" ]; then \
			echo "  Generating for $$(basename $$repo)..."; \
			bash scripts/version/changelog.sh "$$(basename $$repo)"; \
		fi \
	done

# Development
test:
	@echo "🧪 Running tests..."
	@pytest tests/ -v

test-cov:
	@echo "🧪 Running tests with coverage..."
	@pytest tests/ --cov=orchestrator --cov-report=term-missing --cov-report=html

test-watch:
	@echo "👀 Running tests in watch mode..."
	@pytest-watch tests/

lint:
	@echo "🔍 Running linters..."
	@flake8 orchestrator/ --max-line-length=100 --ignore=E203,W503
	@mypy orchestrator/ --ignore-missing-imports

format:
	@echo "✨ Formatting code..."
	@black orchestrator/ tests/ scripts/*.py
	@isort orchestrator/ tests/ scripts/*.py

clean:
	@echo "🧹 Cleaning up..."
	@find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name "*.pyc" -delete
	@find . -type f -name "*.pyo" -delete
	@find . -type f -name "*.tmp" -delete
	@rm -rf .coverage htmlcov/ .pytest_cache/
	@rm -rf build/ dist/ *.egg-info/
	@rm -f dependency_graph.png health_report.md release_plan.json
	@echo "✅ Cleaned"

# Branch Management
branch-create:
	@read -p "Feature name: " feature; \
	read -p "Base branch (main): " base; base=$${base:-main}; \
	bash scripts/branch/create-feature.sh $$feature $$base all

branch-cleanup:
	@echo "🧹 Cleaning up stale branches..."
	@bash scripts/branch/cleanup-branches.sh true 90

branch-sync:
	@read -p "Branch name: " branch; \
	bash scripts/branch/sync-branches.sh $$branch pull

# Docker
docker-build:
	@echo "🐳 Building Docker image..."
	@docker build -t repo-orchestrator:latest .

docker-run:
	@echo "🐳 Running orchestrator in Docker..."
	@docker run -it --rm \
		-v $(PWD):/workspace \
		-v ~/.ssh:/root/.ssh:ro \
		-v ~/.gitconfig:/root/.gitconfig:ro \
		repo-orchestrator:latest

# Git hooks
install-hooks:
	@echo "🎣 Installing git hooks..."
	@cp hooks/* .git/hooks/
	@chmod +x .git/hooks/*
	@echo "✅ Hooks installed"

# Validation
validate:
	@echo "✓ Validating configuration..."
	@python3 -c "import yaml; yaml.safe_load(open('configs/repositories.yaml'))"
	@python3 -c "import yaml; yaml.safe_load(open('configs/tracker.yaml'))"
	@python3 -c "import yaml; yaml.safe_load(open('.orchestrator/self.yaml'))"
	@echo "✅ All configurations valid"

# Visualization
visualize:
	@echo "📊 Generating dependency graph..."
	@python3 -c "from orchestrator import DependencyResolver; \
		resolver = DependencyResolver(); \
		resolver.visualize_graph('dependency_graph.png'); \
		print('✅ Graph saved to dependency_graph.png')"

# Interactive shell
shell:
	@echo "🐚 Starting interactive Python shell..."
	@python3 -i -c "from orchestrator import *; \
		print('Orchestrator modules loaded'); \
		print('Available: VersionCoordinator, DependencyResolver, IssueTracker, RepoHealthMonitor')"

# CI/CD
ci-local:
	@echo "🔄 Running CI checks locally..."
	@make lint
	@make test
	@make validate
	@echo "✅ All CI checks passed"

# Version management
version-bump:
	@read -p "Repository: " repo; \
	read -p "Bump type (patch/minor/major): " type; \
	bash scripts/version/bump-version.sh $$repo $$type

version-tag:
	@read -p "Repository: " repo; \
	read -p "Version: " version; \
	bash scripts/version/tag-version.sh $$repo $$version

# Emergency commands
emergency-stop:
	@echo "🛑 Emergency stop - killing all orchestrator processes..."
	@pkill -f "orchestrator" || true
	@pkill -f "orchestrate.py" || true
	@echo "✅ All processes stopped"

# Development server
dev-server:
	@echo "🌐 Starting development server..."
	@python3 -m http.server 8000 --directory docs/

.DEFAULT_GOAL := help