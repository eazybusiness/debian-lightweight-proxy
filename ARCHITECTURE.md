# Architecture Overview

## System Design

This lightweight proxy uses a combination of Linux kernel networking features and a minimal web server to achieve transparent port forwarding and HTTP redirection.

### Components

1. **iptables/ip6tables (Netfilter)**
   - Handles packet filtering and NAT (Network Address Translation)
   - Creates custom chains for organized rule management
   - Provides transparent port forwarding via DNAT
   - Redirects non-forwarded traffic to local redirect handler

2. **Nginx (Lightweight)**
   - Listens on internal port 8888
   - Returns HTTP 302 redirects for all requests
   - Minimal configuration, low memory footprint

3. **Systemd Service**
   - Ensures configuration persists across reboots
   - Manages service dependencies

4. **Kernel IP Forwarding**
   - Enables routing of packets between interfaces
   - Required for transparent proxying

## Traffic Flow

### Forwarded Port Traffic

```
Client → [Port in PORT_LIST] → Server
                                  ↓
                            iptables PREROUTING
                                  ↓
                            PROXY_FORWARD chain
                                  ↓
                            DNAT to FORWARD_IP4/6:port
                                  ↓
                            iptables POSTROUTING
                                  ↓
                            MASQUERADE (source NAT)
                                  ↓
                            Target Server
```

### Non-Forwarded Traffic

```
Client → [Any other port] → Server
                              ↓
                        iptables PREROUTING
                              ↓
                        PROXY_REDIRECT chain
                              ↓
                        REDIRECT to localhost:8888
                              ↓
                        Nginx
                              ↓
                        HTTP 302 → REDIRECT_DOMAIN
                              ↓
                        Client follows redirect
```

## iptables Chain Structure

### IPv4 (iptables)

```
nat table
├── PREROUTING
│   ├── → PROXY_FORWARD (custom)
│   │   ├── tcp --dport 8080 → DNAT to FORWARD_IP4:8080
│   │   ├── tcp --dport 8443 → DNAT to FORWARD_IP4:8443
│   │   └── ... (for each port in PORT_LIST)
│   └── → PROXY_REDIRECT (custom)
│       └── tcp → REDIRECT to :8888
└── POSTROUTING
    └── → MASQUERADE
```

### IPv6 (ip6tables)

```
nat table
├── PREROUTING
│   ├── → PROXY_FORWARD (custom)
│   │   ├── tcp --dport 8080 → DNAT to [FORWARD_IP6]:8080
│   │   ├── tcp --dport 8443 → DNAT to [FORWARD_IP6]:8443
│   │   └── ... (for each port in PORT_LIST)
│   └── → PROXY_REDIRECT (custom)
│       └── tcp → REDIRECT to :8888
└── POSTROUTING
    └── → MASQUERADE
```

## Rule Processing Order

1. **PREROUTING PROXY_FORWARD**: Checked first for port matches
   - If port matches → DNAT and forward to target
   - If no match → continue to next chain

2. **PREROUTING PROXY_REDIRECT**: Catches all remaining traffic
   - Redirects TCP traffic to local Nginx on port 8888

3. **POSTROUTING MASQUERADE**: Applied to forwarded traffic
   - Changes source IP to proxy server IP
   - Enables return traffic routing

## Persistence Mechanisms

### 1. netfilter-persistent
- Saves iptables rules to `/etc/iptables/rules.v4`
- Saves ip6tables rules to `/etc/iptables/rules.v6`
- Automatically restores on boot

### 2. systemd Service
- `/etc/systemd/system/lightweight-proxy.service`
- Runs setup script on boot
- Ensures all components are configured

### 3. sysctl Configuration
- `/etc/sysctl.d/99-proxy-forwarding.conf`
- Enables IP forwarding at boot
- Persists kernel parameters

## Idempotency Design

The script can be run multiple times safely:

1. **Clear existing rules first**
   - Removes old PROXY_FORWARD and PROXY_REDIRECT chains
   - Prevents duplicate rules

2. **Recreate chains from scratch**
   - Ensures clean state
   - No accumulation of rules

3. **Overwrite configuration files**
   - Nginx config replaced completely
   - Systemd service replaced
   - sysctl config replaced

## Security Considerations

### Attack Surface
- Exposed ports: All ports are accessible
- Forwarded ports: Direct access to target server
- Redirect handler: Minimal Nginx instance

### Mitigations
- No authentication required (by design for transparency)
- Nginx runs with minimal privileges
- No CGI or dynamic content execution
- Rate limiting should be added for production use

### Recommendations
1. Add fail2ban for brute force protection
2. Implement rate limiting in iptables
3. Monitor logs for suspicious activity
4. Use connection tracking limits
5. Consider adding GeoIP filtering

## Performance Characteristics

### Resource Usage
- **Memory**: ~10-20 MB (Nginx + iptables)
- **CPU**: Minimal (kernel-level processing)
- **Latency**: <1ms added (NAT overhead)

### Scalability
- Handles thousands of concurrent connections
- Limited by network bandwidth and target server capacity
- iptables rules are O(n) where n = number of forwarded ports

### Bottlenecks
- Network I/O (primary limitation)
- Connection tracking table size
- Target server capacity

## Monitoring Points

### Key Metrics
1. **iptables counters**: Packets/bytes per rule
2. **Nginx access logs**: Redirect requests
3. **System logs**: Service status
4. **Connection tracking**: Active connections

### Log Locations
- Setup: `/var/log/proxy-setup.log`
- Nginx access: `/var/log/nginx/proxy-redirect-access.log`
- Nginx errors: `/var/log/nginx/proxy-redirect-error.log`
- System: `journalctl -u lightweight-proxy.service`

## Limitations

1. **Protocol Support**
   - Port forwarding: All protocols (TCP/UDP)
   - Redirect: TCP only (HTTP)
   - Non-TCP traffic to non-forwarded ports is dropped

2. **Transparency**
   - Source IP is masked (MASQUERADE)
   - Target sees proxy IP, not client IP
   - Consider TPROXY for true transparency

3. **IPv6**
   - Requires IPv6 connectivity
   - Target must support IPv6
   - Dual-stack recommended

## Future Enhancements

- [ ] Add nftables support (modern replacement for iptables)
- [ ] Implement connection tracking limits
- [ ] Add rate limiting rules
- [ ] Support for TPROXY (preserve source IP)
- [ ] Web-based configuration interface
- [ ] Prometheus metrics export
- [ ] Dynamic port list updates without restart
- [ ] Load balancing across multiple targets
