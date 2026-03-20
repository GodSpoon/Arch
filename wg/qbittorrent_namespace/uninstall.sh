#!/bin/bash
# Uninstall qBittorrent VPN Namespace

echo "Uninstalling qBittorrent VPN Namespace..."
echo ""
read -p "Are you sure you want to completely remove the VPN namespace? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstall cancelled."
    exit 0
fi

echo ""
echo "Stopping and disabling service..."
sudo systemctl stop vpn-namespace.service 2>/dev/null || true
sudo systemctl disable vpn-namespace.service 2>/dev/null || true

echo "Removing systemd service..."
sudo rm -f /etc/systemd/system/vpn-namespace.service
sudo systemctl daemon-reload

echo "Removing scripts..."
sudo rm -f /usr/local/bin/vpn-namespace-setup.sh
sudo rm -f /usr/local/bin/vpn-namespace-cleanup.sh
sudo rm -f /usr/local/bin/qbittorrent-vpn

echo "Removing sudoers config..."
sudo rm -f /etc/sudoers.d/vpn-namespace

echo "Removing namespace config..."
sudo rm -rf /etc/netns/qbtorrent

echo "Cleaning up namespace..."
sudo /usr/local/bin/vpn-namespace-cleanup.sh 2>/dev/null || true
sudo ip netns delete qbtorrent 2>/dev/null || true

echo "Removing desktop entry..."
rm -f ~/.local/share/applications/qbittorrent-vpn.desktop

echo "Removing WireGuard config..."
read -p "Remove WireGuard config (/etc/wireguard/wg-torrent.conf)? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo rm -f /etc/wireguard/wg-torrent.conf
    echo "WireGuard config removed."
else
    echo "WireGuard config kept."
fi

echo ""
echo "Uninstall complete!"
echo ""
echo "This directory still contains backup files for reinstallation."
echo "To reinstall: sudo ./install.sh"
