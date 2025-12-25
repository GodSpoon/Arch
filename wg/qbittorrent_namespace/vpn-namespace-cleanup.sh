#!/bin/bash
NAMESPACE="qbtorrent"
VETH_HOST="veth-qbt"
WG_INTERFACE="wg-torrent"

# Stop any processes in namespace
ip netns pids $NAMESPACE 2>/dev/null | xargs -r kill 2>/dev/null

# Bring down WireGuard
ip netns exec $NAMESPACE wg-quick down $WG_INTERFACE 2>/dev/null || true

# Delete veth pair (automatically removes from namespace too)
ip link delete $VETH_HOST 2>/dev/null || true

# Delete namespace
ip netns delete $NAMESPACE 2>/dev/null || true

# Clean up iptables
iptables -t nat -D POSTROUTING -s 10.200.200.2/32 -o br0 -j MASQUERADE 2>/dev/null || true

echo "VPN namespace cleaned up"
