# Bootstrap VPS Skill

Interactive VPS hardening and setup workflow using GitHub Actions automation.

## Purpose

Guides the user through bootstrapping a fresh Ubuntu VPS with production-grade security hardening and infrastructure components. This skill provides a conversational, step-by-step approach to:

1. Setting up GitHub secrets and variables (if not already configured)
2. Preparing VPS for automation (initial user creation if needed)
3. Triggering automated hardening via GitHub Actions workflow
4. Verifying successful deployment

## When to Use

Invoke this skill when you need to:
- Set up a fresh Ubuntu VPS instance
- Harden a new VPS for production deployments
- Configure initial infrastructure for application hosting
- Prepare a VPS for GitHub Actions CI/CD deployments

## Prerequisites

**Required:**
1. Fresh Ubuntu 24.04 LTS VPS with root SSH access
2. **GitHub CLI (`gh`)** installed and authenticated
   - Install: `brew install gh` (macOS) or `apt install gh` (Ubuntu)
   - Authenticate: `gh auth login`
3. SSH key pair generated for CI/CD access
   - Generate if needed: `ssh-keygen -t ed25519 -C "ci-cd-deploy"`
   - Public key: `cat ~/.ssh/id_ed25519.pub`
   - Private key: `cat ~/.ssh/id_ed25519`

**Optional (skill will help configure if missing):**
- GitHub organization/repository secrets and variables

## Bootstrap Workflow

When this skill is invoked, guide the user through these steps:

### Step 1: Verify Prerequisites

Check that the user has:
```bash
# Verify gh CLI is installed and authenticated
gh auth status

# Verify SSH key pair exists
ls -la ~/.ssh/id_ed25519*
```

### Step 2: Configure GitHub Secrets and Variables

**Check if already configured:**
```bash
# Check for organization variables
gh variable list --org YOUR-ORG

# Check for organization secrets
gh secret list --org YOUR-ORG
```

**If not configured, guide setup:**

**Set Organization Secret (SSH_PRIVATE_KEY):**
```bash
# Copy private key to clipboard or file
cat ~/.ssh/id_ed25519 | gh secret set SSH_PRIVATE_KEY --org YOUR-ORG
```

**Set Organization Variables:**
```bash
gh variable set SSH_USER --org YOUR-ORG --body "deploy"
gh variable set SSH_PORT --org YOUR-ORG --body "22"
gh variable set ADMIN_EMAIL --org YOUR-ORG --body "admin@example.com"
gh variable set ADMIN_USER --org YOUR-ORG --body "your-username"
gh variable set ADMIN_KEY --org YOUR-ORG --body "$(cat ~/.ssh/id_ed25519.pub)"
```

**Note:** Replace `YOUR-ORG` with actual organization name, and update values as appropriate.

### Step 3: Prepare VPS (One-Time Initial Setup)

**If VPS is brand new with only root access**, the user needs to create the initial deploy user:

```bash
# SSH to VPS as root
ssh root@VPS_IP_ADDRESS

# Create deploy user (use same username as SSH_USER variable)
useradd -m -s /bin/bash deploy
usermod -aG sudo deploy
mkdir -p /home/deploy/.ssh
echo "YOUR_PUBLIC_KEY" > /home/deploy/.ssh/authorized_keys
chown -R deploy:deploy /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
chmod 600 /home/deploy/.ssh/authorized_keys

# Test access in new terminal (don't close root session yet!)
ssh deploy@VPS_IP_ADDRESS

# If successful, exit root session
exit
```

**If deploy user already exists**, skip this step.

### Step 4: Trigger GitHub Actions Workflow

Use GitHub CLI to trigger the hardening workflow:

```bash
# Trigger workflow
gh workflow run harden-vps.yml \
  -R YOUR-ORG/common-infrastructure \
  -f vps_host=YOUR_VPS_IP

# Monitor progress
gh run watch
```

The workflow will:
- Connect to VPS using the deploy user
- Install and configure all security hardening
- Create admin user with SSH key access
- Harden SSH, configure firewall, install Docker/Caddy
- Apply all security controls (auditd, AIDE, sysctl, etc.)

### Step 5: Verify Deployment

Once workflow completes successfully, verify access:

```bash
# Test deployment user access (for CI/CD)
ssh deploy@VPS_IP_ADDRESS
sudo -l    # Verify passwordless sudo
docker --version
caddy version
exit

# Test admin user access (personal access)
ssh your-username@VPS_IP_ADDRESS
sudo -l    # Verify passwordless sudo
sudo ufw status
sudo systemctl status auditd
exit
```

### Step 6: Next Steps

Once verified, the VPS is hardened and ready:

**For Application Deployments:**
1. Add `VPS_HOST` variable to each application repository:
   ```bash
   gh variable set VPS_HOST --repo YOUR-ORG/your-app --body "VPS_IP_ADDRESS"
   ```

2. Applications can now deploy to this VPS via their CI/CD workflows

3. Each app writes its Caddy config to `/etc/caddy/conf.d/<app-name>.caddy`

**Security Status:**
- ✅ SSH hardened (key-only auth, no root, no passwords)
- ✅ Both users have passwordless sudo (safe with key-only auth)
- ✅ Firewall configured (SSH rate limited, fail2ban active)
- ✅ Kernel hardened (sysctl), audit logging (auditd), file integrity (AIDE)
- ✅ Docker secured (privilege escalation blocked, network isolated)
- ✅ Caddy ready for automatic HTTPS with Let's Encrypt

## What the Workflow Does

The `harden-vps.yml` workflow is a single, self-contained file that:

**Installs & Configures (idempotently):**
- Docker Engine + Compose V2 + log rotation
- Caddy web server + multi-app snippet architecture
- UFW firewall (22, 80, 443 only)
- fail2ban + automatic security updates
- Python venv support

**Creates Users:**
- `${SSH_USER}` (from GitHub variables): CI/CD deployment user, passwordless sudo, Docker group
- `${ADMIN_USER}` (from GitHub variables): Personal admin, passwordless sudo, SSH key auth
- Disables root login

**Hardens SSH:**
- No root login, no password auth, key-only
- Restarts SSH service after validation

**Sets Up Directories:**
- `/etc/caddy/conf.d/` for app configs
- `/var/log/caddy/` with proper ownership

**Fully Idempotent:**
- Safe to run multiple times
- Skips already-installed components
- Overwrites configs safely (e.g., Caddyfile, SSH config)

## Post-Bootstrap Actions

After bootstrap completes, guide them to:

1. **Configure Application Repository Variables**
   - Add `VPS_HOST` variable to each app repository
   - See `/github-secrets-variables` skill for details

2. **Deploy Applications**
   - Applications can now deploy via GitHub Actions
   - Each app writes its Caddy config to `/etc/caddy/conf.d/<app-name>.caddy`

3. **Configure DNS**
   - Point domain A records to the VPS IP
   - Caddy will automatically handle SSL certificates

## Troubleshooting

### GitHub CLI Not Authenticated
```bash
gh auth login
# Follow prompts to authenticate with GitHub
```

### Cannot Set Organization Secrets/Variables
- Ensure user has admin permissions in the GitHub organization
- Alternatively, use repository-level secrets: `gh secret set SECRET_NAME --repo YOUR-ORG/common-infrastructure`

### Workflow Cannot Connect to VPS
- Verify deploy user exists on VPS with SSH key configured
- Test SSH from local machine: `ssh deploy@VPS_IP`
- Check GitHub Actions can reach VPS (firewall/network rules)

### Workflow Fails During Execution
- Review workflow logs in GitHub Actions UI
- Common issues:
  - Incorrect SSH_USER variable (username doesn't match actual user on VPS)
  - SSH_PRIVATE_KEY doesn't match public key on VPS
  - VPS firewall blocking GitHub Actions IP ranges

### Cannot SSH After Hardening
- Always test access in a NEW terminal before closing root/initial session
- If locked out, use VPS provider's console access to fix SSH config
- Check UFW status: `sudo ufw status` (port 22 should be allowed)

## Example Conversation Flow

```
User: /bootstrap-vps
Assistant: I'll help you bootstrap your VPS with production-grade security hardening using our GitHub Actions workflow.

First, let me check if you have the prerequisites:

1. Do you have the GitHub CLI (`gh`) installed and authenticated?
   Run: `gh auth status`

2. Do you have an SSH key pair for CI/CD deployments?
   Check: `ls -la ~/.ssh/id_ed25519*`

[Skill then guides user through checking/configuring GitHub secrets/variables, preparing VPS if needed, triggering workflow, and verifying deployment]
```

## Key Points

- **GitHub CLI required**: All setup done via `gh` commands (no manual SSH from skill)
- **One-time VPS prep**: User creates initial deploy user manually (guided by skill)
- **Workflow does everything else**: All hardening automated via GitHub Actions
- **Fully idempotent**: Safe to re-run workflow multiple times

## References

- [README.md](../../README.md) - Complete security hardening documentation
- [GitHub Secrets Variables Standards](../github-secrets-variables.md) - Variable naming conventions

