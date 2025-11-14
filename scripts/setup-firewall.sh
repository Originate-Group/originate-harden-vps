#!/bin/bash
set -euo pipefail

###########################################
# UFW Firewall Configuration Script
###########################################
# Purpose: Configure UFW firewall with secure defaults
# Usage: Run as root during VPS hardening
# Notes:
#   - Denies all incoming by default
#   - Allows outgoing traffic
#   - Opens only essential ports (SSH, HTTP, HTTPS)
###########################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
SSH_PORT="${SSH_PORT:-22}"

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

# Check if UFW is installed
if ! command -v ufw &> /dev/null; then
    log_error "UFW is not installed. Install it first: apt-get install ufw"
    exit 1
fi

# Configure UFW
configure_ufw() {
    log_info "Configuring UFW firewall..."

    # Disable UFW first to avoid locking ourselves out during configuration
    ufw --force disable

    # Reset to default settings
    log_info "Resetting UFW to defaults..."
    ufw --force reset

    # Set default policies
    log_info "Setting default policies (deny incoming, allow outgoing)..."
    ufw default deny incoming
    ufw default allow outgoing

    # Allow SSH (CRITICAL - must be done before enabling)
    log_info "Allowing SSH on port $SSH_PORT..."
    ufw allow "$SSH_PORT"/tcp comment 'SSH'

    # Allow HTTP and HTTPS for web services
    log_info "Allowing HTTP and HTTPS..."
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'

    # Optional: Allow additional ports based on environment variables
    if [[ -n "${ALLOW_PORTS:-}" ]]; then
        log_info "Allowing additional ports: $ALLOW_PORTS"
        IFS=',' read -ra PORTS <<< "$ALLOW_PORTS"
        for port in "${PORTS[@]}"; do
            ufw allow "$port" comment 'Custom'
        done
    fi

    # Enable UFW
    log_warn "Enabling UFW firewall..."
    echo "y" | ufw enable

    log_info "UFW firewall configured and enabled"
}

# Display firewall status
show_status() {
    echo
    log_info "Current UFW status:"
    ufw status verbose
    echo
    log_info "Firewall rules summary:"
    log_info "  - SSH: Port $SSH_PORT (OPEN)"
    log_info "  - HTTP: Port 80 (OPEN)"
    log_info "  - HTTPS: Port 443 (OPEN)"
    log_info "  - All other incoming: BLOCKED"
    log_info "  - All outgoing: ALLOWED"
}

# Main execution
main() {
    log_info "Starting UFW firewall setup..."
    echo

    configure_ufw
    show_status

    echo
    log_info "Firewall configuration complete!"
    log_warn "IMPORTANT: Verify SSH access works before logging out!"
    echo
    log_info "To add custom ports later, use:"
    log_info "  sudo ufw allow PORT/tcp comment 'Description'"
    log_info "  sudo ufw reload"
}

main "$@"
