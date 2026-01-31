#!/bin/bash
NAMESPACE="qbtorrent"
VETH_HOST="veth-qbt"
WG_INTERFACE="wg-torrent"

# Stop any processes in namespace
ip netns pids $NAMESPACE 2>/dev/null | xargs -r kill 2>/dev/null

# Bring down WireGuard manually (not wg-quick)
ip netns exec $NAMESPACE ip link set $WG_INTERFACE down 2>/dev/null || true
ip netns exec $NAMESPACE ip link del $WG_INTERFACE 2>/dev/null || true

# Remove iptables rules
iptables -D FORWARD -i $VETH_HOST -o br0 -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -i br0 -o $VETH_HOST -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
iptables -t nat -D POSTROUTING -s 10.200.200.2/32 -o br0 -j MASQUERADE 2>/dev/null || true

# Delete veth pair
ip link delete $VETH_HOST 2>/dev/null || true

# Delete namespace
ip netns delete $NAMESPACE 2>/dev/null || true

echo "VPN namespace cleaned up"
