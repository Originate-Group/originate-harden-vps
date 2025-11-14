# VPS Setup Guide

Complete guide for hardening fresh Ubuntu VPS instances for Originate Group deployments.

## Prerequisites

### Required Access
- Root SSH access to fresh VPS instance
- 1Password SSH agent configured (for Wayne's workstation)
- GitHub organization SSH public key (from GitHub Secrets)

### Target Environment
- Ubuntu 24.04 LTS (recommended)
- Ubuntu 22.04 LTS (supported)
- Minimum 2GB RAM
- Minimum 20GB disk space

### GitHub Secrets Required
At the organization level, you should have:
- `SSH_PRIVATE_KEY` - Private key for CI/CD deployments
- `SSH_USER` - Deployment username (should be `originate-devops`)
- `SSH_HOST` - Will be set per VPS

## Quick Start

### 1. Initial SSH Access

From your WSL2 environment (with 1Password SSH agent bridge):

```bash
# SSH to new VPS as root
ssh root@YOUR_VPS_IP
```

### 2. Clone Repository

```bash
# Install git if needed
apt-get update && apt-get install -y git

# Clone common-infrastructure repo
git clone https://github.com/Originate-Group/common-infrastructure.git
cd common-infrastructure
```

### 3. Run Hardening Script

```bash
# Make scripts executable (if needed)
chmod +x scripts/*.sh

# Run main hardening script
./scripts/harden-ubuntu-vps.sh
```

The script will:
- Update all system packages
- Install essential tools (curl, wget, git, vim)
- Configure automatic security updates
- Set up UFW firewall (ports 22, 80, 443)
- Configure fail2ban
- Create `originate-devops` user with sudo access
- Configure SSH keys for deployment
- Install Docker Engine and Docker Compose
- Harden SSH configuration

### 4. Add GitHub SSH Public Key

During the SSH setup phase, you'll be prompted to add the public key.

**Get the public key from your GitHub private key:**

```bash
# On your local machine (WSL2), extract public key from private key
# This assumes you have the private key temporarily available
ssh-keygen -y -f /path/to/private_key > public_key.pub

# Or if the key is in GitHub Secrets, you can derive it from the private key
```

**Important:** The public key corresponds to the `SSH_PRIVATE_KEY` stored in GitHub organization secrets.

Paste the public key when prompted during script execution.

### 5. Verify Access

**Do not close your root session until you've verified these steps!**

Open a new terminal and test:

```bash
# Test SSH access with deployment user
ssh originate-devops@YOUR_VPS_IP

# Verify sudo access
sudo -l

# Verify Docker
docker --version
docker compose version

# Check firewall status
sudo ufw status

# Check fail2ban
sudo fail2ban-client status sshd
```

### 6. Finalize

Once verified:
- Close the root SSH session
- Future access should be via `originate-devops` user only
- Root login is now disabled

## Manual Script Execution

If you prefer to run scripts individually:

```bash
cd common-infrastructure/scripts

# 1. System updates and essentials (handled by main script)
# 2. Configure firewall
./setup-firewall.sh

# 3. Configure SSH and create deployment user
./setup-ssh-keys.sh

# 4. Install Docker
./setup-docker.sh
```

## Configuration Options

### Custom Deployment User

```bash
# Change deployment username
export DEPLOY_USER="custom-user"
./scripts/harden-ubuntu-vps.sh
```

### Custom SSH Port

```bash
# Use non-standard SSH port
export SSH_PORT="2222"
./scripts/harden-ubuntu-vps.sh
```

### Additional Firewall Ports

```bash
# Allow additional ports (comma-separated)
export ALLOW_PORTS="8080,8443,5432"
./scripts/setup-firewall.sh
```

## Post-Setup Configuration

### Add Wayne's 1Password SSH Access

Wayne's personal access is handled via 1Password SSH agent. No additional configuration needed on VPS - the `originate-devops` user's authorized_keys already contains the necessary public key.

### Configure GitHub Actions

In your application repository (e.g., `originate-keycloak-deployment`), add these secrets:

**Repository secrets:**
- `SSH_HOST` - VPS IP address
- `SSH_PORT` - SSH port (default: 22)

**Organization secrets (already configured):**
- `SSH_PRIVATE_KEY` - Private key for CI/CD
- `SSH_USER` - Deployment username (`originate-devops`)

### Test GitHub Actions Deployment

Create a test workflow:

```yaml
name: Test SSH Connection
on: workflow_dispatch

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Test SSH
        uses: appleboy/ssh-action@master
        with:
          host: ${{ secrets.SSH_HOST }}
          username: ${{ secrets.SSH_USER }}
          key: ${{ secrets.SSH_PRIVATE_KEY }}
          port: ${{ secrets.SSH_PORT }}
          script: |
            whoami
            docker --version
            sudo -l
```

## Troubleshooting

### Cannot SSH After Hardening

1. Verify you tested access BEFORE closing root session
2. Check UFW status: `sudo ufw status`
3. Verify SSH port is open: `sudo ufw allow 22/tcp`
4. Check SSH service: `sudo systemctl status sshd`

### Docker Permission Denied

The `originate-devops` user needs to log out and back in after being added to docker group:

```bash
# Log out and back in
exit
ssh originate-devops@YOUR_VPS_IP

# Verify docker group
groups
# Should show: originate-devops sudo docker
```

### Fail2ban Not Starting

Check configuration:

```bash
sudo fail2ban-client status
sudo journalctl -u fail2ban -n 50
```

### SSH Keys Not Working

1. Verify authorized_keys permissions:
```bash
ls -la ~/.ssh/
# Should show:
# drwx------ .ssh/
# -rw------- authorized_keys
```

2. Check SSH daemon logs:
```bash
sudo tail -f /var/log/auth.log
```

3. Verify key format:
```bash
cat ~/.ssh/authorized_keys
# Should start with: ssh-ed25519 or ssh-rsa
```

## Security Best Practices

### Regular Maintenance

```bash
# Check for security updates
sudo apt-get update
sudo apt-get upgrade

# Review firewall rules
sudo ufw status verbose

# Check fail2ban logs
sudo fail2ban-client status sshd

# Review system logs
sudo journalctl -p err -b
```

### Monitoring

Consider adding:
- Log monitoring (e.g., Grafana Loki)
- Uptime monitoring (e.g., UptimeRobot)
- Security scanning (e.g., Lynis)

### Backup Strategy

- Regular snapshots via VPS provider
- Automated database backups
- Docker volume backups
- Configuration backups

## Multiple VPS Setup

For setting up multiple VPS instances:

```bash
# VPS 1 - Keycloak
ssh root@keycloak-vps-ip
# Run hardening script
# Add SSH_HOST secret to originate-keycloak-deployment repo

# VPS 2 - Requirements Service
ssh root@raas-vps-ip
# Run hardening script
# Add SSH_HOST secret to originate-requirements-service repo
```

Each VPS should:
- Use the same `originate-devops` user
- Use the same SSH key from org secrets
- Have unique SSH_HOST in repository secrets

## Next Steps

After VPS hardening is complete:

1. Deploy applications via GitHub Actions
2. Configure domain DNS records
3. Set up SSL certificates (Let's Encrypt)
4. Configure application-specific environment variables
5. Set up monitoring and alerting

## Support

- **Technical Issues**: [Open an issue](https://github.com/Originate-Group/common-infrastructure/issues)
- **Security Concerns**: Contact @originate-group/security
- **DevOps Questions**: Contact Wayne (@wkenn)
