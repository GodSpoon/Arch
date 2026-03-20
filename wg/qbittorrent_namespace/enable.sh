#!/bin/bash
# Enable qBittorrent VPN Namespace

echo "Enabling qBittorrent VPN Namespace..."

# Enable auto-start on boot
echo "Enabling auto-start on boot..."
sudo systemctl enable vpn-namespace.service

# Start the service
echo "Starting vpn-namespace service..."
sudo systemctl start vpn-namespace.service

# Wait for initialization
sleep 5

# Verify
echo ""
echo "Verifying setup..."
if sudo ip netns list | grep -q qbtorrent; then
    echo "✓ Namespace created"
else
    echo "✗ Namespace not found"
    exit 1
fi

if sudo ip netns exec qbtorrent wg show | grep -q "latest handshake"; then
    echo "✓ WireGuard connected"
    VPN_IP=$(timeout 5 sudo ip netns exec qbtorrent curl -s https://ifconfig.me 2>/dev/null || echo "timeout")
    echo "✓ VPN IP: $VPN_IP"
else
    echo "⚠ WireGuard handshake not established yet (may take a moment)"
fi

echo ""
echo "VPN namespace enabled!"
echo "Launch qBittorrent with: qbittorrent-vpn"
