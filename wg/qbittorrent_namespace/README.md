# qBittorrent VPN Namespace

Isolates qBittorrent traffic through WireGuard VPN using Linux network namespaces. Zero impact on other applications.

## What It Does

- Creates isolated network namespace `qbtorrent`
- Routes ALL qBittorrent traffic through WireGuard VPN (Windscribe)
- Other applications use normal network (br0, wt0/Netbird, etc. untouched)
- Built-in kill switch: if VPN drops, qBittorrent has no connection

## How It Works

1. **Network namespace** - Isolated network stack for qBittorrent
2. **veth pair** - Virtual ethernet connecting namespace to host (10.200.200.0/24)
3. **Manual WireGuard setup** - VPN configured without wg-quick to avoid policy routing conflicts
4. **Endpoint routing** - WireGuard endpoint routes through veth to host, then host NATs to internet
5. **Default route** - All application traffic in namespace uses WireGuard tunnel

## Critical Implementation Details

### Why Manual WireGuard (Not wg-quick)

`wg-quick` creates policy routing rules with fwmark that cause a routing loop:
- wg-quick sets fwmark 0xca6c on WireGuard packets
- Creates rule: "packets WITHOUT fwmark use table 51820"
- WireGuard control packets (WITH fwmark) skip table 51820
- Falls through to default route which points to wg-torrent interface
- **Result: WireGuard tries to route through itself = no handshake**

Solution: Manual WireGuard configuration without fwmark, explicit endpoint route in main table.

### Netbird Compatibility

This setup works alongside Netbird mesh network (wt0 interface):
- Netbird runs on host (wt0) - unaffected
- WireGuard runs in namespace (wg-torrent) - isolated
- No interference between the two

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
- `vpn-namespace-setup.sh` - Creates namespace with manual WireGuard config
- `vpn-namespace-cleanup.sh` - Tears down namespace
- `vpn-namespace.service` - Systemd service (auto-start at boot)
- `qbittorrent-vpn` - Wrapper to launch qBittorrent in namespace
- `vpn-namespace` - Sudoers config for passwordless namespace access

## Verification
```bash
./verify.sh
```

Or manually:
```bash
# Namespace should exist
sudo ip netns list

# WireGuard should show handshake
sudo ip netns exec qbtorrent wg show

# Should show VPN IP (Windscribe), not your real IP
sudo ip netns exec qbtorrent curl ifconfig.me

# Your normal IP (should be different)
curl ifconfig.me

# Netbird should still work on host
sudo wg show wt0
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

**Endpoint routing issues:**
```bash
# Should show route via veth
sudo ip netns exec qbtorrent ip route get 154.47.25.67
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
sudo ip netns delete qbtorrent
```
