#!/bin/bash
# Script to diagnose KDE Store network connectivity issues

echo "=== Network Connectivity Test for KDE Store ==="
echo "Testing connection to api.kde-look.org..."

# Check basic connectivity
if ping -c 3 api.kde-look.org &> /dev/null; then
  echo "✓ Basic connectivity: GOOD"
else
  echo "✗ Basic connectivity: FAILED - Cannot reach api.kde-look.org"
  echo "Trying IP resolution..."
  host api.kde-look.org
fi

# Check HTTP connectivity
if curl -sI https://api.kde-look.org -o /dev/null; then
  echo "✓ HTTPS connection: GOOD"
else
  echo "✗ HTTPS connection: FAILED"
  # Show more detailed error
  curl -v https://api.kde-look.org 2>&1 | grep -E "^[<>]|error|fail"
fi

# Check system proxy settings
if [[ -n "$http_proxy" || -n "$https_proxy" ]]; then
  echo "System proxy detected: $http_proxy $https_proxy"
  echo "This might be interfering with KDE Store connections"
fi

# Check KDE proxy settings
if grep -q "Proxy" ~/.config/kioslaverc; then
  echo "KDE proxy settings found:"
  grep -A 10 "Proxy" ~/.config/kioslaverc
fi

echo "=== Firewall Status ==="
if command -v ufw &> /dev/null; then
  ufw status
elif command -v firewalld &> /dev/null; then
  firewall-cmd --list-all
fi

echo "=== Done ==="
echo "If all tests pass but you still have errors, try the kde_store_cache_clear.sh script"
