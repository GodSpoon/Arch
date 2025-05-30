#!/bin/bash
# Script to clear KDE Store cache and reset connections

# Stop KDE Store services if running
kquitapp6 discover &>/dev/null || true
kquitapp6 plasmashell &>/dev/null || true

# Clear the cache directories
rm -rf ~/.cache/discover
rm -rf ~/.cache/plasma-discover
rm -rf ~/.cache/kioworker
rm -rf ~/.local/share/kactivitymanagerd/resources/database
rm -rf ~/.config/discoverrc

# Force update the system configuration cache
kbuildsycoca6 --noincremental

# Restart Plasma
plasmashell &>/dev/null &

echo "KDE Store cache has been cleared. Network errors should be resolved after restart."
