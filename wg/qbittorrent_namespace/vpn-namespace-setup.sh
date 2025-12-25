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

# Add route to WireGuard endpoint through veth (so handshake works)
ip netns exec $NAMESPACE ip route add $WG_ENDPOINT_IP via $HOST_IP dev $VETH_NS

# Enable IP forwarding on host
echo 1 > /proc/sys/net/ipv4/ip_forward

# Add SNAT rule for traffic from namespace to internet (for WireGuard handshake)
iptables -t nat -C POSTROUTING -s ${NS_IP}/32 -o br0 -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -s ${NS_IP}/32 -o br0 -j MASQUERADE

# Bring up WireGuard in the namespace
ip netns exec $NAMESPACE wg-quick up $WG_INTERFACE 2>/dev/null || echo "WireGuard already up"

# Wait for WireGuard to establish connection
sleep 3

# Now set default route through WireGuard (this will override the endpoint route added by wg-quick)
# But we need to keep the specific route to the endpoint
ip netns exec $NAMESPACE ip route add default dev $WG_INTERFACE metric 100

echo "VPN namespace $NAMESPACE created successfully"
echo ""
echo "WireGuard status:"
ip netns exec $NAMESPACE wg show
echo ""
echo "Routes:"
ip netns exec $NAMESPACE ip route
echo ""
echo "DNS: $(ip netns exec $NAMESPACE cat /etc/resolv.conf)"
