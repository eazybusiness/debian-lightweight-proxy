# Debian Lightweight Proxy

A self-contained solution that transforms a fresh Debian server into a lightweight transparent proxy with port forwarding and HTTP 302 redirection.

## Features

- **Transparent Port Forwarding**: Forward specific ports to a static IPv4/IPv6 address
- **HTTP 302 Redirection**: Redirect all other traffic to a specified domain
- **Dual Stack**: Full IPv4 and IPv6 support
- **Idempotent**: Safe to run multiple times without creating duplicate rules
- **Persistent**: Rules survive reboots via systemd service
- **Minimal Footprint**: Uses only Debian-stable packages (iptables, nginx-light)

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Incoming Traffic                          │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
         ┌─────────────────────────────┐
         │  iptables/ip6tables NAT     │
         │  (PREROUTING chains)        │
         └─────────────┬───────────────┘
                       │
          ┌────────────┴────────────┐
          │                         │
          ▼                         ▼
┌──────────────────┐    ┌──────────────────────┐
│ Port in          │    │ Port NOT in          │
│ PORT_LIST?       │    │ PORT_LIST?           │
│                  │    │                      │
│ ▼ DNAT           │    │ ▼ REDIRECT           │
│ Forward to       │    │ Send to Nginx:8888   │
│ FORWARD_IP4/6    │    │                      │
└──────────────────┘    └──────────┬───────────┘
                                   │
                                   ▼
                        ┌──────────────────────┐
                        │ Nginx returns        │
                        │ HTTP 302 to          │
                        │ REDIRECT_DOMAIN      │
                        └──────────────────────┘
```

## Prerequisites

- Fresh Debian 11 (Bullseye) or Debian 12 (Bookworm) server
- Root access
- Internet connectivity for package installation
- Basic understanding of networking and iptables

## Configuration

Edit the variables at the top of `setup-proxy.sh`:

```bash
# Ports to forward transparently
PORT_LIST=(8080 8443 9000 9090 3000)

# Forward destination addresses
FORWARD_IP4="203.0.113.10"  # Your target IPv4
FORWARD_IP6="2001:db8::1"   # Your target IPv6

# Domain for HTTP 302 redirects
REDIRECT_DOMAIN="https://example.com"
```

## Installation

1. **Clone or download this repository to your Debian server:**
   ```bash
   git clone <repository-url>
   cd debian-lightweight-proxy
   ```

2. **Make scripts executable:**
   ```bash
   chmod +x setup-proxy.sh rollback-proxy.sh verify-proxy.sh
   ```

3. **Edit configuration variables in `setup-proxy.sh`:**
   ```bash
   vim setup-proxy.sh  # Edit PORT_LIST, FORWARD_IP4, FORWARD_IP6, REDIRECT_DOMAIN
   ```

4. **Run the setup script as root:**
   ```bash
   sudo ./setup-proxy.sh
   ```

   The script will:
   - Install required packages (iptables, nginx-light, etc.)
   - Enable IP forwarding
   - Configure Nginx for HTTP 302 redirects
   - Set up iptables/ip6tables rules
   - Create systemd service for persistence
   - Save rules to survive reboots

## Verification

### Quick Test

Run the verification script:
```bash
sudo ./verify-proxy.sh
```

### Manual Verification

**Test HTTP 302 redirect:**
```bash
curl -I http://<server-ip>:80/
# Should return: HTTP/1.1 302 Moved Temporarily
# Location: https://example.com/
```

**Test port forwarding (from another machine):**
```bash
# Test that forwarded port is reachable
nc -zv <server-ip> 8080

# Or use netcat to listen on the target server
# On target server (FORWARD_IP4):
nc -l 8080

# On proxy server or client:
echo "test" | nc <proxy-server-ip> 8080
# Message should appear on target server
```

**View iptables rules:**
```bash
# IPv4 rules
sudo iptables -t nat -L -n -v

# IPv6 rules
sudo ip6tables -t nat -L -n -v
```

**Check IP forwarding:**
```bash
sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding
# Both should return: = 1
```

**Check systemd service:**
```bash
systemctl status lightweight-proxy.service
```

## Rollback

To completely remove all proxy configurations and restore the server to its original state:

```bash
sudo ./rollback-proxy.sh
```

This will:
- Remove all iptables rules
- Disable IP forwarding
- Remove Nginx redirect configuration
- Disable and remove systemd service
- Save clean state

## Persistence

Rules automatically persist across reboots via:
- **netfilter-persistent**: Saves and restores iptables rules
- **systemd service**: `lightweight-proxy.service` ensures configuration on boot
- **sysctl configuration**: `/etc/sysctl.d/99-proxy-forwarding.conf` for IP forwarding

To manually disable persistence:
```bash
sudo systemctl disable lightweight-proxy.service
sudo systemctl disable netfilter-persistent
```

## Troubleshooting

### Port forwarding not working

1. Check iptables rules are loaded:
   ```bash
   sudo iptables -t nat -L PROXY_FORWARD -n -v
   ```

2. Verify IP forwarding is enabled:
   ```bash
   sysctl net.ipv4.ip_forward
   ```

3. Check target server is reachable:
   ```bash
   ping <FORWARD_IP4>
   ```

4. Verify no firewall blocking on target server

### HTTP redirect not working

1. Check Nginx is running:
   ```bash
   systemctl status nginx
   ```

2. Test Nginx directly:
   ```bash
   curl -I http://localhost:8888/
   ```

3. Check Nginx logs:
   ```bash
   tail -f /var/log/nginx/proxy-redirect-error.log
   ```

### Rules not persisting after reboot

1. Check netfilter-persistent service:
   ```bash
   systemctl status netfilter-persistent
   ```

2. Manually save rules:
   ```bash
   sudo netfilter-persistent save
   ```

3. Verify systemd service is enabled:
   ```bash
   systemctl is-enabled lightweight-proxy.service
   ```

## Security Considerations

- **Firewall**: This proxy opens your server to forward traffic. Ensure your firewall rules are appropriate.
- **Rate Limiting**: Consider adding rate limiting to prevent abuse.
- **Monitoring**: Monitor logs in `/var/log/proxy-setup.log` and `/var/log/nginx/`.
- **Target Server**: Ensure the target server (FORWARD_IP4/6) has appropriate security measures.

## Files

- `setup-proxy.sh` - Main installation script
- `rollback-proxy.sh` - Complete removal script
- `verify-proxy.sh` - Verification and testing script
- `README.md` - This file

## Logs

- Setup logs: `/var/log/proxy-setup.log`
- Nginx access: `/var/log/nginx/proxy-redirect-access.log`
- Nginx errors: `/var/log/nginx/proxy-redirect-error.log`

## Technical Details

### iptables Chains

The script creates custom chains for organization:
- `PROXY_FORWARD` - DNAT rules for port forwarding
- `PROXY_REDIRECT` - REDIRECT rules for HTTP 302

### Packages Installed

- `iptables` - IPv4 firewall and NAT
- `iptables-persistent` - Save/restore iptables rules
- `nginx-light` - Lightweight web server for redirects
- `netfilter-persistent` - Persist netfilter rules
- `curl` - Testing HTTP requests
- `net-tools` - Network utilities

## License

MIT License - Feel free to modify and distribute.

## Contributing

Contributions welcome! Please test on a clean Debian VM before submitting pull requests.
