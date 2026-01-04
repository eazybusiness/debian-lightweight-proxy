#!/bin/bash
set -euo pipefail

################################################################################
# Debian Lightweight Proxy Setup Script
# 
# This script configures a Debian server as a transparent proxy:
# - Forwards traffic on specified ports to a static IPv4/IPv6 address
# - Redirects all other traffic with HTTP 302 to a specified domain
################################################################################

# ============================================================================
# CONFIGURATION VARIABLES - EDIT THESE
# ============================================================================

# Ports to forward transparently (space-separated list)
PORT_LIST=(8080 8443 9000 9090 3000)

# Forward destination addresses
FORWARD_IP4="203.0.113.10"  # Replace with your target IPv4
FORWARD_IP6="2001:db8::1"   # Replace with your target IPv6

# Domain for HTTP 302 redirects
REDIRECT_DOMAIN="https://example.com"

# Local redirect handler port (internal use only)
REDIRECT_PORT=8888

# ============================================================================
# SCRIPT LOGIC - DO NOT EDIT BELOW UNLESS YOU KNOW WHAT YOU'RE DOING
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/proxy-setup.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "ERROR: This script must be run as root"
        exit 1
    fi
}

install_dependencies() {
    log "Installing required packages..."
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        iptables \
        iptables-persistent \
        nginx-light \
        netfilter-persistent \
        curl \
        net-tools \
        > /dev/null 2>&1 || true
    log "Dependencies installed"
}

enable_ip_forwarding() {
    log "Enabling IP forwarding..."
    
    # Enable IPv4 forwarding
    sysctl -w net.ipv4.ip_forward=1 > /dev/null
    sysctl -w net.ipv4.conf.all.forwarding=1 > /dev/null
    
    # Enable IPv6 forwarding
    sysctl -w net.ipv6.conf.all.forwarding=1 > /dev/null
    
    # Make persistent
    cat > /etc/sysctl.d/99-proxy-forwarding.conf <<EOF
net.ipv4.ip_forward=1
net.ipv4.conf.all.forwarding=1
net.ipv6.conf.all.forwarding=1
EOF
    
    log "IP forwarding enabled"
}

configure_nginx_redirect() {
    log "Configuring Nginx for HTTP 302 redirects..."
    
    # Create Nginx configuration
    cat > /etc/nginx/sites-available/proxy-redirect <<EOF
server {
    listen ${REDIRECT_PORT} default_server;
    listen [::]:${REDIRECT_PORT} default_server;
    
    server_name _;
    
    location / {
        return 302 ${REDIRECT_DOMAIN}\$request_uri;
    }
    
    access_log /var/log/nginx/proxy-redirect-access.log;
    error_log /var/log/nginx/proxy-redirect-error.log;
}
EOF
    
    # Enable site
    ln -sf /etc/nginx/sites-available/proxy-redirect /etc/nginx/sites-enabled/proxy-redirect
    
    # Remove default site if it conflicts
    rm -f /etc/nginx/sites-enabled/default
    
    # Test and reload Nginx
    nginx -t > /dev/null 2>&1 || {
        log "ERROR: Nginx configuration test failed"
        exit 1
    }
    
    systemctl enable nginx > /dev/null 2>&1
    systemctl restart nginx
    
    log "Nginx configured and running on port ${REDIRECT_PORT}"
}

clear_existing_rules() {
    log "Clearing existing proxy rules (idempotent)..."
    
    # IPv4 rules
    iptables -t nat -D PREROUTING -j PROXY_FORWARD 2>/dev/null || true
    iptables -t nat -F PROXY_FORWARD 2>/dev/null || true
    iptables -t nat -X PROXY_FORWARD 2>/dev/null || true
    
    iptables -t nat -D PREROUTING -j PROXY_REDIRECT 2>/dev/null || true
    iptables -t nat -F PROXY_REDIRECT 2>/dev/null || true
    iptables -t nat -X PROXY_REDIRECT 2>/dev/null || true
    
    # IPv6 rules
    ip6tables -t nat -D PREROUTING -j PROXY_FORWARD 2>/dev/null || true
    ip6tables -t nat -F PROXY_FORWARD 2>/dev/null || true
    ip6tables -t nat -X PROXY_FORWARD 2>/dev/null || true
    
    ip6tables -t nat -D PREROUTING -j PROXY_REDIRECT 2>/dev/null || true
    ip6tables -t nat -F PROXY_REDIRECT 2>/dev/null || true
    ip6tables -t nat -X PROXY_REDIRECT 2>/dev/null || true
    
    log "Existing rules cleared"
}

setup_iptables_rules() {
    log "Setting up iptables rules..."
    
    # ========== IPv4 Rules ==========
    
    # Create custom chains
    iptables -t nat -N PROXY_FORWARD
    iptables -t nat -N PROXY_REDIRECT
    
    # Forward specified ports to target IPv4
    for port in "${PORT_LIST[@]}"; do
        iptables -t nat -A PROXY_FORWARD -p tcp --dport "$port" -j DNAT --to-destination "${FORWARD_IP4}:${port}"
        iptables -t nat -A PROXY_FORWARD -p udp --dport "$port" -j DNAT --to-destination "${FORWARD_IP4}:${port}"
        log "  IPv4: Forwarding port $port to ${FORWARD_IP4}:${port}"
    done
    
    # Redirect all other TCP traffic to Nginx redirect handler
    iptables -t nat -A PROXY_REDIRECT -p tcp -j REDIRECT --to-port "$REDIRECT_PORT"
    
    # Apply chains to PREROUTING
    iptables -t nat -A PREROUTING -j PROXY_FORWARD
    iptables -t nat -A PREROUTING -j PROXY_REDIRECT
    
    # Enable MASQUERADE for forwarded traffic
    iptables -t nat -A POSTROUTING -j MASQUERADE
    
    # ========== IPv6 Rules ==========
    
    # Create custom chains
    ip6tables -t nat -N PROXY_FORWARD
    ip6tables -t nat -N PROXY_REDIRECT
    
    # Forward specified ports to target IPv6
    for port in "${PORT_LIST[@]}"; do
        ip6tables -t nat -A PROXY_FORWARD -p tcp --dport "$port" -j DNAT --to-destination "[${FORWARD_IP6}]:${port}"
        ip6tables -t nat -A PROXY_FORWARD -p udp --dport "$port" -j DNAT --to-destination "[${FORWARD_IP6}]:${port}"
        log "  IPv6: Forwarding port $port to [${FORWARD_IP6}]:${port}"
    done
    
    # Redirect all other TCP traffic to Nginx redirect handler
    ip6tables -t nat -A PROXY_REDIRECT -p tcp -j REDIRECT --to-port "$REDIRECT_PORT"
    
    # Apply chains to PREROUTING
    ip6tables -t nat -A PREROUTING -j PROXY_FORWARD
    ip6tables -t nat -A PREROUTING -j PROXY_REDIRECT
    
    # Enable MASQUERADE for forwarded traffic
    ip6tables -t nat -A POSTROUTING -j MASQUERADE
    
    log "iptables rules configured"
}

save_iptables_rules() {
    log "Saving iptables rules for persistence..."
    
    # Save rules
    netfilter-persistent save > /dev/null 2>&1 || {
        # Fallback method
        iptables-save > /etc/iptables/rules.v4
        ip6tables-save > /etc/iptables/rules.v6
    }
    
    # Enable netfilter-persistent service
    systemctl enable netfilter-persistent > /dev/null 2>&1
    
    log "iptables rules saved and will persist across reboots"
}

create_systemd_service() {
    log "Creating systemd service for proxy..."
    
    cat > /etc/systemd/system/lightweight-proxy.service <<EOF
[Unit]
Description=Lightweight Proxy Service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=${SCRIPT_DIR}/setup-proxy.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable lightweight-proxy.service > /dev/null 2>&1
    
    log "Systemd service created and enabled"
}

print_summary() {
    echo ""
    echo "========================================================================"
    echo "  Lightweight Proxy Setup Complete"
    echo "========================================================================"
    echo ""
    echo "Configuration:"
    echo "  Forwarded Ports: ${PORT_LIST[*]}"
    echo "  Forward IPv4:    ${FORWARD_IP4}"
    echo "  Forward IPv6:    ${FORWARD_IP6}"
    echo "  Redirect Domain: ${REDIRECT_DOMAIN}"
    echo ""
    echo "Status:"
    echo "  - Port forwarding active for specified ports"
    echo "  - All other traffic redirects to ${REDIRECT_DOMAIN}"
    echo "  - Rules will persist across reboots"
    echo ""
    echo "Verification:"
    echo "  Run: ./verify-proxy.sh"
    echo ""
    echo "Rollback:"
    echo "  Run: ./rollback-proxy.sh"
    echo ""
    echo "Logs: ${LOG_FILE}"
    echo "========================================================================"
}

main() {
    log "========== Starting Proxy Setup =========="
    
    check_root
    install_dependencies
    enable_ip_forwarding
    configure_nginx_redirect
    clear_existing_rules
    setup_iptables_rules
    save_iptables_rules
    create_systemd_service
    
    log "========== Proxy Setup Complete =========="
    print_summary
}

main "$@"
