# Multi-stage Dockerfile for Repo Orchestrator
FROM python:3.11-slim as builder

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    g++ \
    make \
    git \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy requirements
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir --user -r requirements.txt

# Production stage
FROM python:3.11-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    openssh-client \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Install yq for YAML processing
RUN curl -L https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/bin/yq \
    && chmod +x /usr/bin/yq

# Copy Python packages from builder
COPY --from=builder /root/.local /root/.local

# Set PATH to include user packages
ENV PATH=/root/.local/bin:$PATH

# Set working directory
WORKDIR /workspace

# Copy octo code
COPY octo/ ./octo/
COPY scripts/ ./scripts/
COPY hooks/ ./hooks/
COPY configs/ ./configs/
COPY .octo/ ./.octo/
COPY templates/ ./templates/

# Make scripts executable
RUN chmod +x scripts/*.sh scripts/*/*.sh hooks/*

# Create necessary directories
RUN mkdir -p repos .github/workflows docs tests

# Set environment variables
ENV PYTHONPATH=/workspace:$PYTHONPATH
ENV OCTO_HOME=/workspace

# Git configuration
RUN git config --global user.name "Repo Orchestrator" \
    && git config --global user.email "octo@example.com" \
    && git config --global init.defaultBranch main

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python3 -c "from octo import VersionCoordinator; print('OK')" || exit 1

# Default command
CMD ["/bin/bash"]

# Labels
LABEL maintainer="octo@example.com"
LABEL version="0.1.0"
LABEL description="Multi-repository orchestration system"

# Volume for repository data
VOLUME ["/workspace/repos", "/workspace/configs"]

# Expose port for future web UI
EXPOSE 8080