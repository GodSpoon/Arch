#!/bin/bash
# Verify qBittorrent VPN Namespace

echo "=== VPN Namespace Verification ==="
echo ""

echo "1. Checking namespace..."
if ip netns list | grep -q qbtorrent; then
    echo "   ✓ Namespace 'qbtorrent' exists"
else
    echo "   ✗ Namespace not found"
    exit 1
fi

echo ""
echo "2. Checking WireGuard..."
if sudo ip netns exec qbtorrent wg show | grep -q "latest handshake"; then
    echo "   ✓ WireGuard connected"
    sudo ip netns exec qbtorrent wg show | grep -E "(endpoint|handshake|transfer)"
else
    echo "   ✗ No handshake established"
    exit 1
fi

echo ""
echo "3. Testing connectivity..."
if sudo ip netns exec qbtorrent ping -c 2 1.1.1.1 &>/dev/null; then
    echo "   ✓ Ping successful"
else
    echo "   ✗ Cannot ping through tunnel"
    exit 1
fi

echo ""
echo "4. Checking DNS..."
if sudo ip netns exec qbtorrent nslookup google.com &>/dev/null; then
    echo "   ✓ DNS resolution works"
else
    echo "   ✗ DNS not working"
fi

echo ""
echo "5. Checking IPs..."
VPN_IP=$(timeout 5 sudo ip netns exec qbtorrent curl -s https://ifconfig.me 2>/dev/null)
REAL_IP=$(timeout 5 curl -s https://ifconfig.me 2>/dev/null)

echo "   VPN IP:  $VPN_IP"
echo "   Real IP: $REAL_IP"

if [ "$VPN_IP" != "$REAL_IP" ]; then
    echo "   ✓ IPs are different (VPN working)"
else
    echo "   ✗ IPs are the same (VPN not working)"
    exit 1
fi

echo ""
echo "=== All checks passed! ==="
