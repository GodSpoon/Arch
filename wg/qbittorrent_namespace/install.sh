#!/bin/bash
# Install qBittorrent VPN Namespace Setup

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USERNAME="${SUDO_USER:-$USER}"

echo "Installing qBittorrent VPN Namespace..."

# Check for required packages
if ! command -v wg &> /dev/null; then
    echo "Installing wireguard-tools..."
    pacman -S --noconfirm wireguard-tools
fi

if ! command -v dig &> /dev/null; then
    echo "Installing bind-tools..."
    pacman -S --noconfirm bind-tools
fi

# Install WireGuard config
echo "Installing WireGuard configuration..."
mkdir -p /etc/wireguard
cp "$SCRIPT_DIR/wg-torrent.conf" /etc/wireguard/
chmod 600 /etc/wireguard/wg-torrent.conf

# Install scripts
echo "Installing namespace scripts..."
cp "$SCRIPT_DIR/vpn-namespace-setup.sh" /usr/local/bin/
cp "$SCRIPT_DIR/vpn-namespace-cleanup.sh" /usr/local/bin/
cp "$SCRIPT_DIR/qbittorrent-vpn" /usr/local/bin/
chmod +x /usr/local/bin/vpn-namespace-setup.sh
chmod +x /usr/local/bin/vpn-namespace-cleanup.sh
chmod +x /usr/local/bin/qbittorrent-vpn

# Install systemd service
echo "Installing systemd service..."
cp "$SCRIPT_DIR/vpn-namespace.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable vpn-namespace.service

# Install sudoers config
echo "Installing sudoers configuration..."
cp "$SCRIPT_DIR/vpn-namespace" /etc/sudoers.d/
chmod 440 /etc/sudoers.d/vpn-namespace

# Install desktop entry (if exists)
if [ -f "$SCRIPT_DIR/qbittorrent-vpn.desktop" ]; then
    echo "Installing desktop entry..."
    sudo -u $USERNAME mkdir -p /home/$USERNAME/.local/share/applications
    sudo -u $USERNAME cp "$SCRIPT_DIR/qbittorrent-vpn.desktop" /home/$USERNAME/.local/share/applications/
fi

# Start the service
echo "Starting VPN namespace..."
systemctl start vpn-namespace.service

# Wait for initialization
sleep 3

# Verify setup
echo ""
echo "Verifying setup..."
if ip netns list | grep -q qbtorrent; then
    echo "✓ Namespace created"
else
    echo "✗ Namespace not found"
    exit 1
fi

if ip netns exec qbtorrent wg show | grep -q "latest handshake"; then
    echo "✓ WireGuard connected"
    VPN_IP=$(timeout 5 ip netns exec qbtorrent curl -s https://ifconfig.me 2>/dev/null || echo "timeout")
    echo "✓ VPN IP: $VPN_IP"
else
    echo "⚠ WireGuard handshake not established yet (may take a moment)"
fi

echo ""
echo "Installation complete!"
echo "Launch qBittorrent with: qbittorrent-vpn"
echo "Check status with: sudo systemctl status vpn-namespace"
echo "View logs with: journalctl -u vpn-namespace -f"
