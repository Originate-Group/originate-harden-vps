# common-infrastructure

Production-grade VPS hardening automation for Ubuntu 24.04 LTS.

## Purpose

Automated security hardening for Ubuntu VPS instances using GitHub Actions. Implements defense-in-depth security controls based on industry best practices and compliance standards (CIS Benchmarks, NIST guidelines).

Invoked via the `/bootstrap-vps` Claude Code skill for streamlined deployment.

## Prerequisites

**GitHub Organization Variables** (one-time setup by org admin):

| Name | Example | Purpose |
|------|---------|---------|
| `SSH_USER` | `deploy` | Deployment username |
| `SSH_PORT` | `22` | SSH port |
| `ADMIN_EMAIL` | `admin@example.com` | Let's Encrypt contact |
| `ADMIN_USER` | `admin` | Personal admin username |
| `ADMIN_KEY` | `ssh-ed25519 AAAA...` | Admin public SSH key |

**GitHub Organization Secret**:

| Name | Value |
|------|-------|
| `SSH_PRIVATE_KEY` | `-----BEGIN OPENSSH PRIVATE KEY-----...` |

**Optional Repository Variable** (if not providing VPS IP to skill):

| Name | Example |
|------|---------|
| `VPS_HOST` | `192.168.1.100` |

## Usage

**From Claude Code chat:**
```
/bootstrap-vps
```

**From Claude Code CLI:**
```bash
claude chat "/bootstrap-vps"
```

The skill will guide you through:
1. Providing VPS IP address
2. Triggering the GitHub Actions workflow
3. Monitoring progress
4. Verifying the hardened VPS

## Security Hardening Features

### Network Security
- **UFW Firewall**: Default-deny incoming, allow only SSH (22), HTTP (80), HTTPS (443)
- **SSH Rate Limiting**: UFW limit rule prevents SSH flooding (max 6 connections per 30 seconds)
- **fail2ban**: Brute-force attack prevention with SSH jail (3 retry limit, 1-hour ban)
- **Kernel Network Hardening**: SYN flood protection, IP spoofing prevention, ICMP attack mitigation via sysctl

### Access Control
- **SSH Hardening**: Root login disabled, password authentication disabled, key-based auth only
- **User Management**:
  - Admin user: Full sudo access (passwordless)
  - Deploy user: Full sudo access (passwordless)
  - **Rationale**: Passwordless sudo is safe when password authentication is completely disabled and only SSH key authentication is permitted. The security barrier is the SSH private key, not sudo passwords.

### System Security
- **Kernel Hardening (sysctl)**:
  - Network attack prevention (SYN cookies, reverse path filtering, martian packet logging)
  - Process isolation (ptrace restrictions, dmesg restriction)
  - Filesystem protections (symlink/hardlink attack prevention)
  - References: [nixCraft sysctl guide](https://www.cyberciti.biz/faq/linux-kernel-etcsysctl-conf-security-hardening/), [Linux Audit hardening](https://linux-audit.com/system-hardening/linux-hardening-with-sysctl/)

- **Kernel-Level Audit Logging (auditd)**:
  - Monitors authentication events, SSH config changes, privileged commands
  - Tracks file modifications, network config changes, Docker/Caddy activity
  - Forensic evidence for incident response and compliance (PCI-DSS, HIPAA, SOC2)
  - References: [Linux Audit Framework](https://linux-audit.com/configuring-and-auditing-linux-systems-with-audit-daemon/), [Mastering auditd](https://medium.com/@bmcrathnayaka/your-must-have-linux-security-superpower-mastering-auditd-f107cd54bd77)

- **AppArmor (MAC)**: Mandatory Access Control enabled by default on Ubuntu 24.04
  - Docker container isolation via `docker-default` profile
  - Unprivileged user namespace restrictions
  - References: [Ubuntu AppArmor docs](https://documentation.ubuntu.com/server/how-to/security/apparmor/), [Docker AppArmor integration](https://docs.docker.com/engine/security/apparmor/)

- **File Integrity Monitoring (AIDE)**:
  - Monitors system binaries, libraries, boot files, and configuration directories
  - Detects unauthorized changes to critical files (rootkits, backdoors, tampering)
  - Daily automated checks via cron with syslog integration
  - Tracks Docker and Caddy binaries and configurations
  - References: [AIDE Installation and Configuration](https://linux-audit.com/aide-file-integrity-scanner-installation-and-configuration/)

- **Shared Memory Protection**:
  - `/run/shm` mounted with `noexec,nosuid,nodev` to prevent shared memory exploits
  - Prevents execution of malicious code from shared memory
  - Mitigates privilege escalation via shared memory attacks

### Container Security
- **Docker Security Hardening**:
  - Privilege escalation blocked (`no-new-privileges`)
  - Inter-container communication disabled by default (`icc=false`)
  - Resource limits configured (prevents DoS attacks)
  - Log rotation enabled (10MB max, 3 files)
  - AppArmor profile enforcement
  - References: [Docker Security 2025](https://cloudnativenow.com/topics/cloudnativedevelopment/docker/docker-security-in-2025-best-practices-to-protect-your-containers-from-cyberthreats/), [OWASP Docker Security](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)

### Infrastructure
- **Caddy Web Server**:
  - Automatic HTTPS with Let's Encrypt
  - Multi-application reverse proxy architecture
  - Modular configuration (`/etc/caddy/conf.d/*.caddy`)
  - **Hardened Security Headers** (example config includes):
    - HSTS (HTTP Strict Transport Security) with preload
    - Content Security Policy (CSP)
    - X-Frame-Options, X-Content-Type-Options, X-XSS-Protection
    - Referrer-Policy, Permissions-Policy
    - Server header removal (fingerprinting prevention)
    - References: [OWASP Secure Headers](https://owasp.org/www-project-secure-headers/)

- **Automatic Security Updates**: Unattended-upgrades configured for security patches

- **Service Auditing**: Automated audit of enabled services and network listeners to identify unnecessary attack surface

## What Gets Installed

| Component | Version | Purpose |
|-----------|---------|---------|
| Docker Engine + Compose V2 | Latest stable | Container runtime with security hardening |
| Caddy | Latest stable | Reverse proxy with automatic HTTPS |
| auditd | Latest stable | Kernel-level security event logging |
| AIDE | Latest stable | File integrity monitoring |
| fail2ban | Latest stable | Brute-force attack prevention |
| UFW | Default | Firewall (uncomplicated firewall) |
| Python 3 + venv | Ubuntu default | Application deployment support |

## Security Philosophy

This project implements **defense-in-depth** security:

1. **Multiple Layers**: Network (firewall), system (kernel hardening), application (Docker isolation), and monitoring (auditd)
2. **Least Privilege**: Users and processes run with minimum necessary permissions
3. **Fail Secure**: Services configured to fail closed rather than open
4. **Audit Everything**: Comprehensive logging for forensics and compliance
5. **Assume Breach**: Security controls designed assuming attackers will gain initial access

**Why these specific controls?**

Research from 2025 security best practices shows:
- VPS instances are under attack within minutes of going live ([Ubuntu Security Guide](https://moss.sh/server-management/best-practices-for-ubuntu-server-security-2025/))
- Kernel-level hardening prevents 70%+ of common network attacks ([Linux Audit](https://linux-audit.com/system-hardening/linux-hardening-with-sysctl/))
- Container escapes are mitigated by AppArmor + no-new-privileges ([Docker Security 2025](https://cloudnativenow.com/topics/cloudnativedevelopment/docker/docker-security-in-2025-best-practices-to-protect-your-containers-from-cyberthreats/))
- Audit logging is required for compliance and incident response ([auditd guide](https://medium.com/@bmcrathnayaka/your-must-have-linux-security-superpower-mastering-auditd-f107cd54bd77))

## Workflow

The workflow is **fully idempotent** - safe to run multiple times on the same VPS without side effects.

**Manual trigger** (if not using skill):
- GitHub UI: Actions → Harden VPS → Run workflow
- GitHub CLI: `gh workflow run harden-vps.yml -f vps_host=YOUR_VPS_IP`

## Post-Deployment

After hardening completes:

1. **Verify Security Status**:
   ```bash
   # Check firewall
   sudo ufw status verbose

   # Check fail2ban
   sudo fail2ban-client status sshd

   # Review audit logs
   sudo ausearch -k sshd_config
   sudo aureport --summary

   # Verify AppArmor
   sudo aa-status

   # Check kernel parameters
   sudo sysctl net.ipv4.tcp_syncookies
   ```

2. **Container Best Practices**: When deploying Docker containers, use:
   ```bash
   docker run \
     --security-opt=no-new-privileges:true \
     --cap-drop=ALL \
     --cap-add=NET_BIND_SERVICE \
     --user 1000:1000 \
     --read-only \
     your-image
   ```

3. **Monitor Logs**:
   - Audit logs: `/var/log/audit/audit.log`
   - AIDE reports: Check syslog for AIDE tag
   - Fail2ban: `/var/log/fail2ban.log`
   - UFW: `/var/log/ufw.log`
   - Caddy: `/var/log/caddy/*.log`

4. **File Integrity Checks**:
   ```bash
   # Run AIDE manual check
   sudo aide --check

   # Update AIDE database after legitimate changes
   sudo aide --update
   sudo mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
   ```

## Future Enhancements

The following security improvements are planned but not yet implemented:

### Centralized Logging (Planned)
**Priority:** High
**Status:** Deferred pending syslog infrastructure
**Description:** Forward logs to remote syslog server to prevent log tampering after compromise and ensure log persistence if server fails. Will use rsyslog or journald remote forwarding.
**References:**
- [Centralized Logging Best Practices](https://moss.sh/server-management/best-practices-for-ubuntu-server-security-2025/)
- Remote syslog server required (not yet deployed)

### Docker Rootless Mode (Planned)
**Priority:** Medium (for ultra-sensitive deployments)
**Status:** Deferred due to complexity and compatibility concerns
**Description:** Run Docker daemon without root privileges for additional isolation. Note: May break some container features and require significant testing.
**References:**
- [Docker Rootless Mode](https://docs.docker.com/engine/security/rootless/)
- [Docker Security Best Practices 2025](https://cloudnativenow.com/topics/cloudnativedevelopment/docker/docker-security-in-2025-best-practices-to-protect-your-containers-from-cyberthreats/)

**Trade-offs:** Increased complexity, potential compatibility issues, reduced performance vs. marginal security gain when proper hardening is in place.

## Contributing

Contributions welcome! When proposing security changes:
1. Cite authoritative sources (CIS, NIST, OWASP, vendor docs)
2. Explain the threat model being addressed
3. Test on fresh Ubuntu 24.04 VPS
4. Ensure idempotency

## References

### General Security
- [Ubuntu 24.04 Security Best Practices 2025](https://moss.sh/server-management/best-practices-for-ubuntu-server-security-2025/)
- [CIS Ubuntu 24.04 Benchmarks](https://ubuntu.com/blog/hardening-automation-for-cis-benchmarks-now-available-for-ubuntu-24-04-lts)

### Kernel & System Hardening
- [Linux Kernel Security Hardening (nixCraft)](https://www.cyberciti.biz/faq/linux-kernel-etcsysctl-conf-security-hardening/)
- [Linux Hardening with sysctl](https://linux-audit.com/system-hardening/linux-hardening-with-sysctl/)

### Audit & Monitoring
- [Linux Audit Framework Configuration](https://linux-audit.com/configuring-and-auditing-linux-systems-with-audit-daemon/)
- [Mastering auditd](https://medium.com/@bmcrathnayaka/your-must-have-linux-security-superpower-mastering-auditd-f107cd54bd77)
- [AIDE File Integrity Scanner](https://linux-audit.com/aide-file-integrity-scanner-installation-and-configuration/)

### Container Security
- [Docker Security in 2025: Best Practices](https://cloudnativenow.com/topics/cloudnativedevelopment/docker/docker-security-in-2025-best-practices-to-protect-your-containers-from-cyberthreats/)
- [OWASP Docker Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)
- [Ubuntu AppArmor Documentation](https://documentation.ubuntu.com/server/how-to/security/apparmor/)
- [Docker AppArmor Security](https://docs.docker.com/engine/security/apparmor/)

### Web Security
- [OWASP Secure Headers Project](https://owasp.org/www-project-secure-headers/)
- [Caddy Reverse Proxy Documentation](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy)

---

**License**: Apache License 2.0 - See [LICENSE](LICENSE) file for details.

Copyright 2025 Originate Group
