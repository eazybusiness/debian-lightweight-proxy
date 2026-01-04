#!/bin/bash
set -euo pipefail

################################################################################
# Verification Script for Lightweight Proxy
# 
# This script tests that the proxy is working correctly:
# - Port forwarding is active
# - HTTP 302 redirects are working
################################################################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

REDIRECT_PORT=8888

print_header() {
    echo ""
    echo "========================================================================"
    echo "  Lightweight Proxy Verification"
    echo "========================================================================"
    echo ""
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${YELLOW}WARNING: Running without root. Some checks may be limited.${NC}"
    fi
}

test_iptables_rules() {
    echo "Checking iptables rules..."
    echo ""
    
    echo "IPv4 NAT rules:"
    if iptables -t nat -L PROXY_FORWARD -n 2>/dev/null | grep -q "DNAT"; then
        echo -e "${GREEN}✓${NC} PROXY_FORWARD chain exists with DNAT rules"
    else
        echo -e "${RED}✗${NC} PROXY_FORWARD chain missing or empty"
    fi
    
    if iptables -t nat -L PROXY_REDIRECT -n 2>/dev/null | grep -q "REDIRECT"; then
        echo -e "${GREEN}✓${NC} PROXY_REDIRECT chain exists with REDIRECT rules"
    else
        echo -e "${RED}✗${NC} PROXY_REDIRECT chain missing or empty"
    fi
    
    echo ""
    echo "IPv6 NAT rules:"
    if ip6tables -t nat -L PROXY_FORWARD -n 2>/dev/null | grep -q "DNAT"; then
        echo -e "${GREEN}✓${NC} PROXY_FORWARD chain exists with DNAT rules"
    else
        echo -e "${RED}✗${NC} PROXY_FORWARD chain missing or empty"
    fi
    
    if ip6tables -t nat -L PROXY_REDIRECT -n 2>/dev/null | grep -q "REDIRECT"; then
        echo -e "${GREEN}✓${NC} PROXY_REDIRECT chain exists with REDIRECT rules"
    else
        echo -e "${RED}✗${NC} PROXY_REDIRECT chain missing or empty"
    fi
    
    echo ""
}

test_ip_forwarding() {
    echo "Checking IP forwarding..."
    echo ""
    
    ipv4_forward=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "0")
    ipv6_forward=$(sysctl -n net.ipv6.conf.all.forwarding 2>/dev/null || echo "0")
    
    if [[ "$ipv4_forward" == "1" ]]; then
        echo -e "${GREEN}✓${NC} IPv4 forwarding enabled"
    else
        echo -e "${RED}✗${NC} IPv4 forwarding disabled"
    fi
    
    if [[ "$ipv6_forward" == "1" ]]; then
        echo -e "${GREEN}✓${NC} IPv6 forwarding enabled"
    else
        echo -e "${RED}✗${NC} IPv6 forwarding disabled"
    fi
    
    echo ""
}

test_nginx_redirect() {
    echo "Checking Nginx redirect handler..."
    echo ""
    
    if systemctl is-active --quiet nginx; then
        echo -e "${GREEN}✓${NC} Nginx is running"
    else
        echo -e "${RED}✗${NC} Nginx is not running"
        return
    fi
    
    if netstat -tlnp 2>/dev/null | grep -q ":${REDIRECT_PORT}.*nginx" || ss -tlnp 2>/dev/null | grep -q ":${REDIRECT_PORT}.*nginx"; then
        echo -e "${GREEN}✓${NC} Nginx listening on port ${REDIRECT_PORT}"
    else
        echo -e "${RED}✗${NC} Nginx not listening on port ${REDIRECT_PORT}"
    fi
    
    # Test actual redirect
    echo ""
    echo "Testing HTTP 302 redirect..."
    response=$(curl -s -o /dev/null -w "%{http_code}|%{redirect_url}" http://localhost:${REDIRECT_PORT}/test 2>/dev/null || echo "000|")
    http_code=$(echo "$response" | cut -d'|' -f1)
    redirect_url=$(echo "$response" | cut -d'|' -f2)
    
    if [[ "$http_code" == "302" ]]; then
        echo -e "${GREEN}✓${NC} HTTP 302 redirect working"
        echo "  Redirect URL: $redirect_url"
    else
        echo -e "${RED}✗${NC} HTTP redirect not working (got HTTP $http_code)"
    fi
    
    echo ""
}

test_systemd_service() {
    echo "Checking systemd service..."
    echo ""
    
    if systemctl is-enabled --quiet lightweight-proxy.service 2>/dev/null; then
        echo -e "${GREEN}✓${NC} lightweight-proxy.service is enabled"
    else
        echo -e "${YELLOW}!${NC} lightweight-proxy.service is not enabled"
    fi
    
    echo ""
}

show_detailed_rules() {
    echo "Detailed iptables rules:"
    echo ""
    echo "--- IPv4 PROXY_FORWARD ---"
    iptables -t nat -L PROXY_FORWARD -n -v 2>/dev/null || echo "Chain not found"
    echo ""
    echo "--- IPv4 PROXY_REDIRECT ---"
    iptables -t nat -L PROXY_REDIRECT -n -v 2>/dev/null || echo "Chain not found"
    echo ""
    echo "--- IPv6 PROXY_FORWARD ---"
    ip6tables -t nat -L PROXY_FORWARD -n -v 2>/dev/null || echo "Chain not found"
    echo ""
    echo "--- IPv6 PROXY_REDIRECT ---"
    ip6tables -t nat -L PROXY_REDIRECT -n -v 2>/dev/null || echo "Chain not found"
    echo ""
}

print_one_liners() {
    echo "========================================================================"
    echo "  Quick Verification Commands"
    echo "========================================================================"
    echo ""
    echo "Test HTTP redirect (should return 302):"
    echo "  curl -I http://localhost:${REDIRECT_PORT}/"
    echo ""
    echo "Test port forwarding (replace 8080 with your forwarded port):"
    echo "  nc -zv <server-ip> 8080"
    echo ""
    echo "View IPv4 NAT rules:"
    echo "  sudo iptables -t nat -L -n -v"
    echo ""
    echo "View IPv6 NAT rules:"
    echo "  sudo ip6tables -t nat -L -n -v"
    echo ""
    echo "Check IP forwarding:"
    echo "  sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding"
    echo ""
    echo "========================================================================"
}

main() {
    print_header
    check_root
    test_iptables_rules
    test_ip_forwarding
    test_nginx_redirect
    test_systemd_service
    
    if [[ "${1:-}" == "-v" ]] || [[ "${1:-}" == "--verbose" ]]; then
        show_detailed_rules
    fi
    
    print_one_liners
}

main "$@"
