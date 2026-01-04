# Quick Start Guide

Get your Debian proxy running in under 5 minutes.

## One-Liner Installation

```bash
# Download and run (replace with your actual repository URL)
git clone <repo-url> && cd debian-lightweight-proxy && sudo ./setup-proxy.sh
```

## Step-by-Step

### 1. Configure

Edit `setup-proxy.sh` and set your values:

```bash
PORT_LIST=(8080 8443 9000 9090 3000)  # Ports to forward
FORWARD_IP4="203.0.113.10"            # Target IPv4
FORWARD_IP6="2001:db8::1"             # Target IPv6
REDIRECT_DOMAIN="https://example.com" # Redirect destination
```

### 2. Install

```bash
sudo ./setup-proxy.sh
```

### 3. Verify

```bash
sudo ./verify-proxy.sh
```

Expected output:
```
✓ PROXY_FORWARD chain exists with DNAT rules
✓ PROXY_REDIRECT chain exists with REDIRECT rules
✓ IPv4 forwarding enabled
✓ IPv6 forwarding enabled
✓ Nginx is running
✓ HTTP 302 redirect working
```

### 4. Test

**Test redirect:**
```bash
curl -I http://your-server-ip/
# Should return: HTTP/1.1 302 Moved Temporarily
# Location: https://example.com/
```

**Test port forwarding:**
```bash
# From another machine
nc -zv your-server-ip 8080
# Should connect if target is listening
```

## Common Scenarios

### Scenario 1: Forward web traffic to backend server

```bash
PORT_LIST=(80 443)
FORWARD_IP4="192.168.1.100"
FORWARD_IP6="fd00::100"
REDIRECT_DOMAIN="https://maintenance.example.com"
```

### Scenario 2: Development proxy with multiple services

```bash
PORT_LIST=(3000 3001 8080 8081 9000)
FORWARD_IP4="10.0.0.50"
FORWARD_IP6="fd00::50"
REDIRECT_DOMAIN="https://dev.example.com"
```

### Scenario 3: Game server proxy

```bash
PORT_LIST=(25565 27015 7777)
FORWARD_IP4="203.0.113.50"
FORWARD_IP6="2001:db8::50"
REDIRECT_DOMAIN="https://gameserver.example.com"
```

## Troubleshooting

### Issue: Port forwarding not working

```bash
# Check rules
sudo iptables -t nat -L PROXY_FORWARD -n -v

# Check IP forwarding
sysctl net.ipv4.ip_forward

# Test connectivity to target
ping <FORWARD_IP4>
```

### Issue: Redirect returns connection refused

```bash
# Check Nginx
systemctl status nginx

# Test Nginx directly
curl -I http://localhost:8888/

# Check logs
tail -f /var/log/nginx/proxy-redirect-error.log
```

### Issue: Rules don't persist after reboot

```bash
# Check systemd service
systemctl status lightweight-proxy.service

# Enable if needed
sudo systemctl enable lightweight-proxy.service

# Save rules manually
sudo netfilter-persistent save
```

## Rollback

Remove everything:
```bash
sudo ./rollback-proxy.sh
```

## Next Steps

- Read [README.md](README.md) for detailed documentation
- Review [ARCHITECTURE.md](ARCHITECTURE.md) for technical details
- Check [CONTRIBUTING.md](CONTRIBUTING.md) to contribute
