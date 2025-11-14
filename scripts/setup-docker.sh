#!/bin/bash
set -euo pipefail

###########################################
# Docker Installation Script
###########################################
# Purpose: Install Docker Engine and Docker Compose plugin
# Target: Ubuntu 24.04 LTS (compatible with 22.04)
# Usage: Run as root during VPS hardening
# Notes:
#   - Installs Docker from official repository
#   - Installs Docker Compose plugin (v2)
#   - Adds deployment user to docker group
###########################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
DEPLOY_USER="${DEPLOY_USER:-originate-devops}"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

# Check if Docker is already installed
check_existing_docker() {
    if command -v docker &> /dev/null; then
        log_warn "Docker is already installed:"
        docker --version
        read -p "Reinstall Docker? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Skipping Docker installation"
            exit 0
        fi
        log_info "Removing existing Docker installation..."
        apt-get remove -y docker docker-engine docker.io containerd runc || true
    fi
}

# Install prerequisites
install_prerequisites() {
    log_info "Installing prerequisites..."
    apt-get update
    apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
}

# Add Docker's official GPG key and repository
setup_docker_repo() {
    log_info "Setting up Docker repository..."

    # Create keyrings directory
    install -m 0755 -d /etc/apt/keyrings

    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Set up the repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    log_info "Docker repository configured"
}

# Install Docker Engine
install_docker() {
    log_info "Installing Docker Engine..."

    apt-get update
    apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    log_info "Docker Engine installed successfully"
}

# Configure Docker
configure_docker() {
    log_info "Configuring Docker..."

    # Enable Docker service
    systemctl enable docker
    systemctl start docker

    # Add deployment user to docker group (if user exists)
    if id "$DEPLOY_USER" &>/dev/null; then
        usermod -aG docker "$DEPLOY_USER"
        log_info "Added $DEPLOY_USER to docker group"
        log_warn "User $DEPLOY_USER will need to log out and back in for group changes to take effect"
    else
        log_warn "User $DEPLOY_USER does not exist yet, skipping group addition"
        log_info "Run this manually after user is created: usermod -aG docker $DEPLOY_USER"
    fi

    # Configure Docker daemon with sensible defaults
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "live-restore": true
}
EOF

    systemctl restart docker
    log_info "Docker daemon configured with log rotation and live-restore"
}

# Verify installation
verify_installation() {
    log_info "Verifying Docker installation..."

    if docker --version &> /dev/null; then
        log_info "Docker version:"
        docker --version
    else
        log_error "Docker installation verification failed"
        exit 1
    fi

    if docker compose version &> /dev/null; then
        log_info "Docker Compose version:"
        docker compose version
    else
        log_error "Docker Compose installation verification failed"
        exit 1
    fi

    # Run test container
    log_info "Running test container..."
    if docker run --rm hello-world &> /dev/null; then
        log_info "Docker test container ran successfully"
    else
        log_warn "Docker test container failed, but Docker is installed"
    fi
}

# Display post-installation info
show_post_install_info() {
    echo
    log_info "Docker installation complete!"
    echo
    log_info "Installed components:"
    log_info "  - Docker Engine (docker)"
    log_info "  - Docker Compose plugin (docker compose)"
    log_info "  - Docker Buildx plugin (docker buildx)"
    echo
    log_info "Docker configuration:"
    log_info "  - Log rotation: 10MB per file, 3 files max"
    log_info "  - Live restore: enabled"
    log_info "  - User access: $DEPLOY_USER (requires re-login)"
    echo
    log_info "Common Docker commands:"
    log_info "  docker ps                    # List running containers"
    log_info "  docker compose up -d         # Start services"
    log_info "  docker compose down          # Stop services"
    log_info "  docker system prune          # Clean up unused resources"
}

# Main execution
main() {
    log_info "Starting Docker installation..."
    echo

    check_existing_docker
    install_prerequisites
    setup_docker_repo
    install_docker
    configure_docker
    verify_installation
    show_post_install_info
}

main "$@"
