#!/bin/bash
set -euo pipefail

################################################################################
# Rollback Script for Lightweight Proxy
# 
# This script removes all proxy configurations and restores the server
# to its original state.
################################################################################

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

remove_iptables_rules() {
    log "Removing iptables rules..."
    
    # IPv4 cleanup
    iptables -t nat -D PREROUTING -j PROXY_FORWARD 2>/dev/null || true
    iptables -t nat -D PREROUTING -j PROXY_REDIRECT 2>/dev/null || true
    iptables -t nat -F PROXY_FORWARD 2>/dev/null || true
    iptables -t nat -F PROXY_REDIRECT 2>/dev/null || true
    iptables -t nat -X PROXY_FORWARD 2>/dev/null || true
    iptables -t nat -X PROXY_REDIRECT 2>/dev/null || true
    
    # Remove MASQUERADE if it's the only rule
    iptables -t nat -D POSTROUTING -j MASQUERADE 2>/dev/null || true
    
    # IPv6 cleanup
    ip6tables -t nat -D PREROUTING -j PROXY_FORWARD 2>/dev/null || true
    ip6tables -t nat -D PREROUTING -j PROXY_REDIRECT 2>/dev/null || true
    ip6tables -t nat -F PROXY_FORWARD 2>/dev/null || true
    ip6tables -t nat -F PROXY_REDIRECT 2>/dev/null || true
    ip6tables -t nat -X PROXY_FORWARD 2>/dev/null || true
    ip6tables -t nat -X PROXY_REDIRECT 2>/dev/null || true
    
    # Remove MASQUERADE if it's the only rule
    ip6tables -t nat -D POSTROUTING -j MASQUERADE 2>/dev/null || true
    
    log "iptables rules removed"
}

disable_ip_forwarding() {
    log "Disabling IP forwarding..."
    
    # Disable forwarding
    sysctl -w net.ipv4.ip_forward=0 > /dev/null
    sysctl -w net.ipv4.conf.all.forwarding=0 > /dev/null
    sysctl -w net.ipv6.conf.all.forwarding=0 > /dev/null
    
    # Remove persistent configuration
    rm -f /etc/sysctl.d/99-proxy-forwarding.conf
    
    log "IP forwarding disabled"
}

remove_nginx_config() {
    log "Removing Nginx configuration..."
    
    # Remove site configuration
    rm -f /etc/nginx/sites-enabled/proxy-redirect
    rm -f /etc/nginx/sites-available/proxy-redirect
    
    # Reload Nginx if it's running
    if systemctl is-active --quiet nginx; then
        systemctl reload nginx 2>/dev/null || true
    fi
    
    log "Nginx configuration removed"
}

remove_systemd_service() {
    log "Removing systemd service..."
    
    # Stop and disable service
    systemctl stop lightweight-proxy.service 2>/dev/null || true
    systemctl disable lightweight-proxy.service 2>/dev/null || true
    
    # Remove service file
    rm -f /etc/systemd/system/lightweight-proxy.service
    
    systemctl daemon-reload
    
    log "Systemd service removed"
}

save_clean_rules() {
    log "Saving clean iptables state..."
    
    netfilter-persistent save > /dev/null 2>&1 || {
        iptables-save > /etc/iptables/rules.v4
        ip6tables-save > /etc/iptables/rules.v6
    }
    
    log "Clean state saved"
}

print_summary() {
    echo ""
    echo "========================================================================"
    echo "  Proxy Rollback Complete"
    echo "========================================================================"
    echo ""
    echo "All proxy configurations have been removed:"
    echo "  - iptables rules cleared"
    echo "  - IP forwarding disabled"
    echo "  - Nginx redirect configuration removed"
    echo "  - Systemd service removed"
    echo ""
    echo "Your server has been restored to its original state."
    echo ""
    echo "Logs: ${LOG_FILE}"
    echo "========================================================================"
}

main() {
    log "========== Starting Proxy Rollback =========="
    
    check_root
    remove_systemd_service
    remove_iptables_rules
    disable_ip_forwarding
    remove_nginx_config
    save_clean_rules
    
    log "========== Rollback Complete =========="
    print_summary
}

main "$@"
