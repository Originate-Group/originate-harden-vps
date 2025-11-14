#!/bin/bash
set -euo pipefail

###########################################
# Originate Group VPS Hardening Script
###########################################
# Purpose: Bootstrap and harden fresh Ubuntu VPS instances
# Target: Ubuntu 24.04 LTS (compatible with 22.04)
# Execution: Run as root on fresh VPS
###########################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration variables
DEPLOY_USER="${DEPLOY_USER:-originate-devops}"
SSH_PORT="${SSH_PORT:-22}"

# Logging
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
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Verify Ubuntu version
check_ubuntu_version() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot determine OS version"
        exit 1
    fi

    source /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        log_error "This script is designed for Ubuntu only (detected: $ID)"
        exit 1
    fi

    log_info "Detected Ubuntu $VERSION_ID"

    if [[ "$VERSION_ID" != "24.04" && "$VERSION_ID" != "22.04" ]]; then
        log_warn "This script is tested on Ubuntu 22.04 and 24.04. Your version: $VERSION_ID"
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Update system packages
update_system() {
    log_info "Updating system packages..."
    apt-get update
    apt-get upgrade -y
    apt-get autoremove -y
}

# Install essential packages
install_essentials() {
    log_info "Installing essential packages..."
    apt-get install -y \
        curl \
        wget \
        git \
        vim \
        ufw \
        fail2ban \
        unattended-upgrades \
        apt-listchanges \
        software-properties-common \
        ca-certificates \
        gnupg \
        lsb-release
}

# Configure automatic security updates
configure_auto_updates() {
    log_info "Configuring automatic security updates..."

    cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

    cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

    log_info "Automatic security updates configured"
}

# Configure fail2ban
configure_fail2ban() {
    log_info "Configuring fail2ban..."

    cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
destemail = root@localhost
sendername = Fail2Ban

[sshd]
enabled = true
port = ${SSH_PORT}
logpath = %(sshd_log)s
backend = %(sshd_backend)s
EOF

    systemctl enable fail2ban
    systemctl restart fail2ban
    log_info "Fail2ban configured and started"
}

# Main execution
main() {
    log_info "Starting Originate Group VPS hardening..."
    echo

    check_root
    check_ubuntu_version
    echo

    # System updates
    update_system
    echo

    # Install essentials
    install_essentials
    echo

    # Configure automatic updates
    configure_auto_updates
    echo

    # Run firewall setup
    if [[ -f "$SCRIPT_DIR/setup-firewall.sh" ]]; then
        log_info "Running firewall setup..."
        bash "$SCRIPT_DIR/setup-firewall.sh"
        echo
    else
        log_warn "Firewall setup script not found, skipping"
    fi

    # Configure fail2ban
    configure_fail2ban
    echo

    # Run SSH key setup
    if [[ -f "$SCRIPT_DIR/setup-ssh-keys.sh" ]]; then
        log_info "Running SSH key setup..."
        bash "$SCRIPT_DIR/setup-ssh-keys.sh"
        echo
    else
        log_warn "SSH key setup script not found, skipping"
    fi

    # Run Docker setup
    if [[ -f "$SCRIPT_DIR/setup-docker.sh" ]]; then
        log_info "Running Docker setup..."
        bash "$SCRIPT_DIR/setup-docker.sh"
        echo
    else
        log_warn "Docker setup script not found, skipping"
    fi

    # Final steps
    log_info "Hardening complete!"
    echo
    log_info "Next steps:"
    log_info "  1. Verify you can SSH as ${DEPLOY_USER}"
    log_info "  2. Test sudo access: sudo -l"
    log_info "  3. Verify Docker: docker --version"
    log_info "  4. Check firewall: sudo ufw status"
    log_info "  5. Review fail2ban: sudo fail2ban-client status"
    echo
    log_warn "IMPORTANT: Do not log out until you've verified SSH access with the new user!"
}

main "$@"
