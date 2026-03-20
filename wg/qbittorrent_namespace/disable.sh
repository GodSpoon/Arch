#!/bin/bash
# Disable qBittorrent VPN Namespace (without uninstalling)

echo "Disabling qBittorrent VPN Namespace..."

# Stop the service
echo "Stopping vpn-namespace service..."
sudo systemctl stop vpn-namespace.service

# Disable auto-start on boot
echo "Disabling auto-start on boot..."
sudo systemctl disable vpn-namespace.service

# Clean up the namespace
echo "Cleaning up namespace..."
sudo /usr/local/bin/vpn-namespace-cleanup.sh

echo ""
echo "VPN namespace disabled!"
echo ""
echo "Status:"
sudo systemctl status vpn-namespace.service --no-pager || true
echo ""
echo "To re-enable: ./enable.sh"
echo "To uninstall completely: ./uninstall.sh"
