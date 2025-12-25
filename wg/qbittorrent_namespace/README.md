# qBittorrent VPN Namespace

Isolates qBittorrent traffic through WireGuard VPN using Linux network namespaces. Zero impact on other applications.

## What It Does

- Creates isolated network namespace `qbtorrent`
- Routes ALL qBittorrent traffic through WireGuard VPN
- Other applications use normal network (br0, wt0, etc. untouched)
- Built-in kill switch: if VPN drops, qBittorrent has no connection

## How It Works

1. **Network namespace** - Isolated network stack for qBittorrent
2. **veth pair** - Virtual ethernet connecting namespace to host (10.200.200.0/24)
3. **WireGuard in namespace** - VPN runs only in isolated namespace
4. **Endpoint routing** - WireGuard endpoint routes through veth to host, then host routes to internet
5. **Default route** - All other namespace traffic uses WireGuard tunnel

## Key Fix

The critical issue was routing the WireGuard endpoint itself:
```bash
# Endpoint must reach internet through host, not through tunnel
ip route add <endpoint_ip> via 10.200.200.1 dev veth-qbt-ns
```

Without this, WireGuard handshake fails (tunnel tries to route through itself).

## Installation
```bash
sudo ./install.sh
```

## Usage
```bash
# Launch qBittorrent through VPN
qbittorrent-vpn

# Check VPN status
sudo systemctl status vpn-namespace
sudo ip netns exec qbtorrent wg show

# Verify VPN IP
sudo ip netns exec qbtorrent curl ifconfig.me
```

## Files

- `wg-torrent.conf` - WireGuard configuration
- `vpn-namespace-setup.sh` - Creates and configures namespace
- `vpn-namespace-cleanup.sh` - Tears down namespace
- `vpn-namespace.service` - Systemd service (auto-start at boot)
- `qbittorrent-vpn` - Wrapper to launch qBittorrent in namespace
- `vpn-namespace` - Sudoers config for passwordless namespace access

## Verification
```bash
# Namespace should exist
ip netns list

# WireGuard should show handshake
sudo ip netns exec qbtorrent wg show

# Should show VPN IP, not your real IP
sudo ip netns exec qbtorrent curl ifconfig.me

# Your normal IP (should be different)
curl ifconfig.me
```

## Troubleshooting

**No handshake / 0 B received:**
```bash
sudo systemctl restart vpn-namespace
sleep 5
sudo ip netns exec qbtorrent wg show
```

**DNS not working:**
Check `/etc/netns/qbtorrent/resolv.conf` exists with public DNS servers.

**Service won't start:**
```bash
journalctl -u vpn-namespace -n 50
```

## Uninstall
```bash
sudo systemctl stop vpn-namespace
sudo systemctl disable vpn-namespace
sudo rm /etc/systemd/system/vpn-namespace.service
sudo rm /usr/local/bin/vpn-namespace-*.sh
sudo rm /usr/local/bin/qbittorrent-vpn
sudo rm /etc/sudoers.d/vpn-namespace
sudo rm -rf /etc/netns/qbtorrent
ip netns delete qbtorrent
```
