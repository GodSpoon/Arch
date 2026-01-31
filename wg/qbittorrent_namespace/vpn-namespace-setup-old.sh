#!/bin/bash
# Setup network namespace for qBittorrent VPN isolation

NAMESPACE="qbtorrent"
VETH_HOST="veth-qbt"
VETH_NS="veth-qbt-ns"
WG_INTERFACE="wg-torrent"
HOST_IP="10.200.200.1"
NS_IP="10.200.200.2"
WG_ENDPOINT="ord-323-wg.whiskergalaxy.com"

# Create namespace if it doesn't exist
ip netns add $NAMESPACE 2>/dev/null || true

# Create namespace config directory
mkdir -p /etc/netns/$NAMESPACE

# Set up DNS for namespace
cat > /etc/netns/$NAMESPACE/resolv.conf << EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

# Create veth pair for namespace communication
ip link add $VETH_HOST type veth peer name $VETH_NS 2>/dev/null || true
ip link set $VETH_NS netns $NAMESPACE

# Configure host side
ip addr flush dev $VETH_HOST 2>/dev/null || true
ip addr add ${HOST_IP}/24 dev $VETH_HOST
ip link set $VETH_HOST up

# Configure namespace side
ip netns exec $NAMESPACE ip addr flush dev $VETH_NS 2>/dev/null || true
ip netns exec $NAMESPACE ip addr add ${NS_IP}/24 dev $VETH_NS
ip netns exec $NAMESPACE ip link set $VETH_NS up
ip netns exec $NAMESPACE ip link set lo up

# Resolve WireGuard endpoint IP
WG_ENDPOINT_IP=$(dig +short $WG_ENDPOINT | head -1)
echo "WireGuard endpoint: $WG_ENDPOINT ($WG_ENDPOINT_IP)"

# Enable IP forwarding on host
echo 1 > /proc/sys/net/ipv4/ip_forward

# Add FORWARD rules
iptables -D FORWARD -i $VETH_HOST -o br0 -j ACCEPT 2>/dev/null || true
iptables -I FORWARD 1 -i $VETH_HOST -o br0 -j ACCEPT

iptables -D FORWARD -i br0 -o $VETH_HOST -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
iptables -I FORWARD 1 -i br0 -o $VETH_HOST -m state --state RELATED,ESTABLISHED -j ACCEPT

# Add SNAT rule for traffic from namespace to internet
iptables -t nat -D POSTROUTING -s ${NS_IP}/32 -o br0 -j MASQUERADE 2>/dev/null || true
iptables -t nat -A POSTROUTING -s ${NS_IP}/32 -o br0 -j MASQUERADE

# Bring up WireGuard in the namespace
ip netns exec $NAMESPACE wg-quick up $WG_INTERFACE 2>/dev/null || echo "WireGuard already up"

# Wait for WireGuard to come up
sleep 2

# CRITICAL FIX: Add route to endpoint in main table (before wg-quick's policy routing)
# This must be in main table so WireGuard's fwmark packets can find it
ip netns exec $NAMESPACE ip route add $WG_ENDPOINT_IP via $HOST_IP dev $VETH_NS table main 2>/dev/null || true

# Add a policy rule to ensure WireGuard control traffic (with fwmark) uses endpoint route
# Priority 32764 (just before the fwmark rule at 32765)
ip netns exec $NAMESPACE ip rule del priority 32764 2>/dev/null || true
ip netns exec $NAMESPACE ip rule add priority 32764 to $WG_ENDPOINT_IP lookup main

# Set default route through WireGuard for application traffic
ip netns exec $NAMESPACE ip route replace default dev $WG_INTERFACE metric 100

echo "VPN namespace $NAMESPACE created successfully"
echo ""
echo "Policy routing rules:"
ip netns exec $NAMESPACE ip rule show
echo ""
echo "Main routing table:"
ip netns exec $NAMESPACE ip route show table main
echo ""
echo "WireGuard status:"
ip netns exec $NAMESPACE wg show
echo ""
echo "DNS: $(ip netns exec $NAMESPACE cat /etc/resolv.conf)"
