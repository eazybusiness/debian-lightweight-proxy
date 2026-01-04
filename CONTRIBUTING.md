# Contributing to Debian Lightweight Proxy

Thank you for your interest in contributing to this project!

## Development Setup

1. Fork the repository
2. Clone your fork to a Debian test environment
3. Make your changes
4. Test thoroughly on a clean Debian VM

## Testing Requirements

Before submitting a pull request, ensure:

- [ ] Script runs successfully on fresh Debian 11 (Bullseye)
- [ ] Script runs successfully on fresh Debian 12 (Bookworm)
- [ ] Script is idempotent (can be run multiple times safely)
- [ ] Port forwarding works for both IPv4 and IPv6
- [ ] HTTP 302 redirects work correctly
- [ ] Rules persist across reboot
- [ ] Rollback script completely removes all changes
- [ ] Verification script passes all checks

## Code Style

- Use bash best practices
- Include error handling with `set -euo pipefail`
- Add logging for all major operations
- Keep functions focused and single-purpose
- Comment complex logic
- Use meaningful variable names

## Testing Checklist

### Basic Functionality
```bash
# 1. Run setup
sudo ./setup-proxy.sh

# 2. Verify installation
sudo ./verify-proxy.sh

# 3. Test HTTP redirect
curl -I http://localhost/

# 4. Test port forwarding (adjust port as needed)
nc -zv <server-ip> 8080

# 5. Reboot and verify persistence
sudo reboot
# After reboot:
sudo ./verify-proxy.sh

# 6. Test rollback
sudo ./rollback-proxy.sh
sudo ./verify-proxy.sh  # Should show rules removed
```

### Edge Cases to Test

- Running setup script twice in a row
- Running setup after partial manual configuration
- Network interruption during setup
- Missing dependencies
- Invalid IP addresses in configuration
- Empty PORT_LIST array
- Conflicting Nginx configurations

## Submitting Changes

1. Create a descriptive branch name (e.g., `fix-ipv6-forwarding`)
2. Make your changes with clear commit messages
3. Test on a clean Debian VM
4. Submit a pull request with:
   - Description of changes
   - Why the change is needed
   - Test results from Debian 11 and 12
   - Any breaking changes or migration notes

## Reporting Issues

When reporting issues, include:

- Debian version (`cat /etc/debian_version`)
- Script version or commit hash
- Full error output
- Steps to reproduce
- Output of `./verify-proxy.sh -v`
- Relevant logs from `/var/log/proxy-setup.log`

## Questions?

Open an issue for discussion before starting major changes.
