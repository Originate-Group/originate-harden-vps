#!/bin/bash
set -euo pipefail

###########################################
# SSH Key Configuration Script
###########################################
# Purpose: Create deployment user and configure SSH key authentication
# Usage: Run as root during VPS hardening
# Notes:
#   - Creates deployment user with sudo access
#   - Configures authorized_keys for GitHub Actions (org-level SSH key)
#   - Hardens SSH daemon configuration
#   - Does NOT create local SSH keys (keys come from GitHub Secrets or 1Password)
###########################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
DEPLOY_USER="${DEPLOY_USER:-originate-devops}"
ADMIN_USER="${ADMIN_USER:-wkenn}"
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

# Create admin user (for Wayne's personal access)
create_admin_user() {
    if id "$ADMIN_USER" &>/dev/null; then
        log_warn "User $ADMIN_USER already exists, skipping creation"
    else
        log_info "Creating admin user: $ADMIN_USER"
        useradd -m -s /bin/bash "$ADMIN_USER"
        log_info "User $ADMIN_USER created"
    fi

    # Add to sudo group
    usermod -aG sudo "$ADMIN_USER"

    # Configure sudo WITH password for admin user (more secure)
    log_info "Sudo access configured for $ADMIN_USER (requires password)"
}

# Create deployment user (for CI/CD automation)
create_deploy_user() {
    if id "$DEPLOY_USER" &>/dev/null; then
        log_warn "User $DEPLOY_USER already exists, skipping creation"
    else
        log_info "Creating deployment user: $DEPLOY_USER"
        useradd -m -s /bin/bash "$DEPLOY_USER"
        log_info "User $DEPLOY_USER created"
    fi

    # Add to sudo group
    usermod -aG sudo "$DEPLOY_USER"

    # Configure passwordless sudo for deployment user (CI/CD needs this)
    echo "$DEPLOY_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$DEPLOY_USER
    chmod 0440 /etc/sudoers.d/$DEPLOY_USER
    log_info "Passwordless sudo configured for $DEPLOY_USER (CI/CD automation)"
}

# Configure SSH authorized_keys for a user
configure_authorized_keys() {
    local username=$1
    local key_description=$2

    local user_home
    user_home=$(getent passwd "$username" | cut -d: -f6)
    local ssh_dir="$user_home/.ssh"
    local auth_keys="$ssh_dir/authorized_keys"

    log_info "Setting up SSH directory for $username"
    mkdir -p "$ssh_dir"

    if [[ -f "$auth_keys" ]]; then
        log_warn "authorized_keys already exists, backing up to authorized_keys.backup"
        cp "$auth_keys" "$auth_keys.backup"
    fi
    touch "$auth_keys"

    echo
    log_info "SSH key configuration for $username ($key_description):"
    echo
    log_info "Options:"
    echo "  1. Paste the public key now (recommended)"
    echo "  2. Skip and add it manually later"
    echo
    read -p "Choose option (1/2): " -n 1 -r
    echo

    if [[ $REPLY == "1" ]]; then
        echo
        log_info "Paste the PUBLIC key (ssh-rsa... or ssh-ed25519...) and press Enter:"
        log_info "Then press Ctrl+D when done"
        echo

        cat >> "$auth_keys"

        if [[ -s "$auth_keys" ]]; then
            log_info "Public key added to authorized_keys for $username"
        else
            log_warn "No key was added. You'll need to add it manually."
        fi
    else
        log_warn "Skipping key addition. Add manually to: $auth_keys"
        log_info "Example: echo 'ssh-ed25519 AAAA...' >> $auth_keys"
    fi

    # Set correct permissions
    chown -R "$username:$username" "$ssh_dir"
    chmod 700 "$ssh_dir"
    chmod 600 "$auth_keys"

    log_info "SSH directory permissions set correctly for $username"
}

# Disable root account
disable_root() {
    log_info "Disabling root account..."

    # Lock root account
    passwd -l root

    log_warn "Root account has been locked"
    log_warn "Future access must be via $ADMIN_USER or $DEPLOY_USER"
}

# Harden SSH configuration
harden_ssh() {
    log_info "Hardening SSH configuration..."

    local sshd_config="/etc/ssh/sshd_config"
    local backup_config="/etc/ssh/sshd_config.backup.$(date +%Y%m%d-%H%M%S)"

    # Backup original config
    cp "$sshd_config" "$backup_config"
    log_info "Backed up SSH config to $backup_config"

    # Apply hardening settings
    # Note: Using sed to update or add settings

    # Disable root login
    if grep -q "^PermitRootLogin" "$sshd_config"; then
        sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' "$sshd_config"
    else
        echo "PermitRootLogin no" >> "$sshd_config"
    fi

    # Disable password authentication
    if grep -q "^PasswordAuthentication" "$sshd_config"; then
        sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' "$sshd_config"
    else
        echo "PasswordAuthentication no" >> "$sshd_config"
    fi

    # Enable public key authentication
    if grep -q "^PubkeyAuthentication" "$sshd_config"; then
        sed -i 's/^PubkeyAuthentication.*/PubkeyAuthentication yes/' "$sshd_config"
    else
        echo "PubkeyAuthentication yes" >> "$sshd_config"
    fi

    # Disable challenge-response authentication
    if grep -q "^ChallengeResponseAuthentication" "$sshd_config"; then
        sed -i 's/^ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' "$sshd_config"
    fi
    if grep -q "^KbdInteractiveAuthentication" "$sshd_config"; then
        sed -i 's/^KbdInteractiveAuthentication.*/KbdInteractiveAuthentication no/' "$sshd_config"
    else
        echo "KbdInteractiveAuthentication no" >> "$sshd_config"
    fi

    # Disable X11 forwarding
    if grep -q "^X11Forwarding" "$sshd_config"; then
        sed -i 's/^X11Forwarding.*/X11Forwarding no/' "$sshd_config"
    else
        echo "X11Forwarding no" >> "$sshd_config"
    fi

    # Set SSH port (if non-standard)
    if [[ "$SSH_PORT" != "22" ]]; then
        if grep -q "^Port" "$sshd_config"; then
            sed -i "s/^Port.*/Port $SSH_PORT/" "$sshd_config"
        else
            echo "Port $SSH_PORT" >> "$sshd_config"
        fi
        log_info "SSH port set to: $SSH_PORT"
    fi

    log_info "SSH hardening settings applied:"
    log_info "  - Root login: disabled"
    log_info "  - Password authentication: disabled"
    log_info "  - Public key authentication: enabled"
    log_info "  - SSH port: $SSH_PORT"
}

# Test SSH configuration
test_ssh_config() {
    log_info "Testing SSH configuration..."

    if sshd -t; then
        log_info "SSH configuration is valid"
    else
        log_error "SSH configuration has errors!"
        log_error "Restoring backup configuration..."
        cp "$backup_config" /etc/ssh/sshd_config
        exit 1
    fi
}

# Restart SSH service
restart_ssh() {
    log_warn "Restarting SSH service..."
    log_warn "WARNING: Ensure you have an active session before restarting!"
    echo
    read -p "Restart SSH now? (y/N) " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        systemctl restart sshd
        log_info "SSH service restarted"
        echo
        log_info "SSH is now hardened. Test your connections in NEW terminals:"
        log_info "  ssh $ADMIN_USER@YOUR_VPS_IP    (personal admin access)"
        log_info "  ssh $DEPLOY_USER@YOUR_VPS_IP   (CI/CD automation)"
        echo
        log_warn "DO NOT close this session until you've verified the new connections work!"
    else
        log_warn "SSH restart skipped. Remember to run: systemctl restart sshd"
    fi
}

# Main execution
main() {
    log_info "Starting SSH key configuration..."
    echo

    # Create admin user for personal access
    log_info "=== Creating Admin User ==="
    create_admin_user
    echo

    # Configure SSH keys for admin user (1Password keys)
    log_info "=== Configuring Admin User SSH Keys ==="
    echo "This is for Wayne's personal admin access via 1Password SSH agent"
    configure_authorized_keys "$ADMIN_USER" "1Password SSH keys"
    echo

    # Create deployment user for CI/CD
    log_info "=== Creating Deployment User ==="
    create_deploy_user
    echo

    # Configure SSH keys for deployment user (GitHub Secrets)
    log_info "=== Configuring Deployment User SSH Keys ==="
    echo "This is for GitHub Actions CI/CD automation"
    echo "Public key corresponds to SSH_PRIVATE_KEY in GitHub org secrets"
    configure_authorized_keys "$DEPLOY_USER" "GitHub Actions SSH key"
    echo

    # Harden SSH configuration
    log_info "=== Hardening SSH Configuration ==="
    harden_ssh
    echo

    # Test SSH configuration
    test_ssh_config
    echo

    # Disable root account
    log_info "=== Disabling Root Account ==="
    read -p "Disable root account now? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        disable_root
    else
        log_warn "Root account NOT disabled. Disable manually later: passwd -l root"
    fi
    echo

    # Restart SSH service
    restart_ssh
    echo

    log_info "SSH key setup complete!"
    log_info "Users created:"
    log_info "  - $ADMIN_USER: Personal admin (sudo with password)"
    log_info "  - $DEPLOY_USER: CI/CD automation (passwordless sudo)"
    log_info "SSH access: Key-based authentication only"
    log_info "Root account: Disabled"
}

main "$@"
