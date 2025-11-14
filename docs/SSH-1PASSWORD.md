# 1Password SSH Agent Configuration

Guide for configuring 1Password SSH agent on Windows with WSL2 bridge for secure SSH key management.

## Overview

This setup allows Wayne to:
- Store SSH keys securely in 1Password vault (no local key files)
- Use SSH keys from Windows 1Password agent in WSL2 environment
- Authenticate to VPS instances via `wkenn` admin user
- Keep GitHub CI/CD keys separate (stored in GitHub Secrets)

## Architecture

```
┌─────────────────────────────────────────┐
│          Windows 11 Host                │
│  ┌───────────────────────────────────┐  │
│  │   1Password Desktop App           │  │
│  │   - SSH Agent enabled             │  │
│  │   - Keys in vault                 │  │
│  │   - Named pipe: \\.\pipe\openssh  │  │
│  └───────────────────────────────────┘  │
│                  │                       │
│                  │ Named Pipe           │
│                  ▼                       │
│  ┌───────────────────────────────────┐  │
│  │   npiperelay.exe                  │  │
│  │   (Bridge to WSL2)                │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
                   │
                   │ socat relay
                   ▼
┌─────────────────────────────────────────┐
│          WSL2 (Ubuntu)                  │
│  ┌───────────────────────────────────┐  │
│  │   SSH Client                      │  │
│  │   SSH_AUTH_SOCK=~/.ssh/agent.sock │  │
│  └───────────────────────────────────┘  │
│                  │                       │
│                  ▼                       │
│  ┌───────────────────────────────────┐  │
│  │   Remote VPS                      │  │
│  │   User: wkenn                     │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

## Prerequisites

- Windows 11 with WSL2 installed
- 1Password Desktop application (not browser extension)
- Ubuntu running in WSL2
- Root access to configure VPS instances

## Setup Instructions

### 1. Enable 1Password SSH Agent (Windows)

1. Open 1Password desktop app on Windows
2. Go to Settings → Developer
3. Enable "Use the SSH agent"
4. Optionally enable "Display key names when authorizing connections"

Your SSH keys should already be stored in 1Password vault.

### 2. Install npiperelay (WSL2)

`npiperelay` bridges Windows named pipes to WSL2 Unix sockets.

```bash
# Download npiperelay
cd /tmp
wget https://github.com/jstarks/npiperelay/releases/latest/download/npiperelay_windows_amd64.zip
unzip npiperelay_windows_amd64.zip

# Move to accessible location
sudo mkdir -p /usr/local/bin
sudo mv npiperelay.exe /usr/local/bin/
sudo chmod +x /usr/local/bin/npiperelay.exe
```

### 3. Install socat (WSL2)

```bash
sudo apt-get update
sudo apt-get install -y socat
```

### 4. Configure SSH Agent Bridge

Add to your `~/.bashrc` or `~/.zshrc`:

```bash
# 1Password SSH Agent Bridge
export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"

# Start socat relay if not already running
if ! pgrep -x "socat" > /dev/null; then
    rm -f "$SSH_AUTH_SOCK"
    (setsid socat UNIX-LISTEN:"$SSH_AUTH_SOCK",fork EXEC:"/usr/local/bin/npiperelay.exe -ei -s //./pipe/openssh-ssh-agent",nofork &) >/dev/null 2>&1
fi
```

### 5. Apply Configuration

```bash
# Reload shell configuration
source ~/.bashrc

# Verify SSH agent is accessible
ssh-add -l
# Should list your SSH keys from 1Password
```

## Usage

### SSH to VPS as Admin User

```bash
# Connect to VPS using wkenn account
ssh wkenn@YOUR_VPS_IP

# 1Password will prompt for authorization (on Windows)
# Approve the connection in 1Password popup

# Once connected, you have sudo access (requires password)
sudo apt-get update
```

### Managing SSH Keys in 1Password

1. Open 1Password vault
2. Find SSH key item
3. Can add notes, tags, or restrictions
4. Can temporarily disable keys without deleting

### Adding New SSH Keys to 1Password

```bash
# Generate new SSH key (temporarily)
ssh-keygen -t ed25519 -C "description"

# Import to 1Password
# 1. Copy private key content
# 2. Create new "SSH Key" item in 1Password
# 3. Paste private key
# 4. Delete local key file

# Or use 1Password CLI
op item create --category="SSH Key" \
  --title="VPS Admin Key" \
  'private_key=@/path/to/private_key'
```

## VPS Configuration for wkenn User

When hardening a new VPS, the setup script creates the `wkenn` user and configures SSH access.

### Manual Setup (if needed)

On the VPS:

```bash
# Create wkenn user
sudo useradd -m -s /bin/bash wkenn
sudo usermod -aG sudo wkenn

# Configure SSH directory
sudo mkdir -p /home/wkenn/.ssh
sudo chmod 700 /home/wkenn/.ssh

# Add your 1Password public key
# Get public key from your local machine:
ssh-add -L | grep "comment_or_identifier"

# Add to VPS authorized_keys
sudo bash -c 'echo "YOUR_PUBLIC_KEY" >> /home/wkenn/.ssh/authorized_keys'
sudo chmod 600 /home/wkenn/.ssh/authorized_keys
sudo chown -R wkenn:wkenn /home/wkenn/.ssh
```

## Troubleshooting

### SSH agent not accessible

```bash
# Check if socat is running
pgrep -a socat

# Kill existing socat processes
pkill socat

# Restart shell to reinitialize
exec bash
```

### 1Password not prompting

1. Verify 1Password SSH agent is enabled in Settings
2. Check Windows notification area for 1Password popup
3. Try `ssh-add -l` to force connection test

### Permission denied (publickey)

```bash
# Verify your public key
ssh-add -L

# Check VPS authorized_keys
ssh root@VPS_IP 'cat /home/wkenn/.ssh/authorized_keys'

# Verify key format matches (ssh-ed25519 or ssh-rsa)
```

### WSL2 networking issues

```bash
# Test Windows named pipe accessibility
ls -la /usr/local/bin/npiperelay.exe

# Check socat errors
socat -v UNIX-LISTEN:/tmp/test.sock EXEC:"/usr/local/bin/npiperelay.exe -ei -s //./pipe/openssh-ssh-agent"
```

## Security Considerations

### Advantages

1. **No local key files**: Keys stored encrypted in 1Password vault
2. **Approval prompts**: 1Password prompts before using keys
3. **Audit trail**: 1Password logs when keys are used
4. **Cross-device sync**: Same keys available on all devices
5. **Key rotation**: Easy to update keys without file management

### Best Practices

1. **Separate keys for different purposes**:
   - Personal admin key (wkenn) in 1Password
   - CI/CD key (originate-devops) in GitHub Secrets
   - Never share keys between users

2. **Use key restrictions**:
   - In 1Password, add notes about key purpose
   - Document which keys are for which VPS instances

3. **Regular audits**:
   - Review 1Password activity logs
   - Check VPS auth logs: `sudo tail -f /var/log/auth.log`

4. **Key rotation schedule**:
   - Rotate personal keys annually
   - Rotate CI/CD keys after team changes
   - Revoke immediately if compromised

## Alternative: GitHub Actions Only

If you don't need personal SSH access to VPS (not recommended for admin tasks):

```yaml
# GitHub Actions can deploy directly
- name: Deploy via SSH
  uses: appleboy/ssh-action@master
  with:
    host: ${{ secrets.SSH_HOST }}
    username: ${{ secrets.SSH_USER }}
    key: ${{ secrets.SSH_PRIVATE_KEY }}
    script: |
      cd /opt/myapp
      docker compose pull
      docker compose up -d
```

However, for troubleshooting and emergency fixes, personal admin access (wkenn via 1Password) is essential.

## Resources

- [1Password SSH Agent Documentation](https://developer.1password.com/docs/ssh)
- [npiperelay GitHub](https://github.com/jstarks/npiperelay)
- [WSL2 SSH Agent Forwarding](https://stuartleeks.com/posts/wsl-ssh-key-forward-to-windows/)

## Support

- **1Password Issues**: Contact 1Password support
- **WSL2 Issues**: Check WSL2 documentation
- **VPS SSH Issues**: Review [VPS-SETUP.md](./VPS-SETUP.md)
- **DevOps Questions**: Contact Wayne (@wkenn)
