#!/bin/bash

# Complete Podman Setup for Arch Linux (Rootless + Root)
# Based on official Arch Wiki documentation

echo "Setting up Podman complete environment on Arch Linux..."

# Update system first
echo "Updating system packages..."
sudo pacman -Sy archlinux-keyring
sudo pacman-key --populate archlinux
sudo pacman -Syyu

# Install Podman and all components
echo "Installing Podman and related packages..."
sudo pacman -S podman podman-compose podman-docker fuse-overlayfs

# Install optional dependencies for full functionality
sudo pacman -S netavark crun slirp4netns

# Setup rootless containers (user namespaces)
echo "Configuring rootless container support..."

# Create subuid and subgid files if they don't exist
sudo touch /etc/subuid
sudo touch /etc/subgid

# Add subordinate UID/GID ranges for current user
USERNAME=$(whoami)
echo "Adding UID/GID ranges for user: $USERNAME"

# Add ranges if not already present
if ! grep -q "^$USERNAME:" /etc/subuid; then
    echo "$USERNAME:100000:65536" | sudo tee -a /etc/subuid
fi

if ! grep -q "^$USERNAME:" /etc/subgid; then
    echo "$USERNAME:100000:65536" | sudo tee -a /etc/subgid
fi

# Migrate existing containers to new user namespace setup
podman system migrate

# Setup rootless services
echo "Setting up rootless Podman services..."
systemctl --user enable --now podman.socket

# Setup root-level Podman services
echo "Setting up root-level Podman services..."
sudo systemctl enable --now podman.socket
sudo systemctl enable --now podman.service

# Enable containers with restart policy support (both user and system)
echo "Enabling container restart policy services..."
systemctl --user enable podman-restart.service
sudo systemctl enable podman-restart.service

# Configure Docker compatibility for both user and root
echo "Configuring Docker compatibility..."

# For current user (rootless)
echo 'export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock' >> ~/.bashrc
echo 'alias docker=podman' >> ~/.bashrc
echo 'export DOCKER_BUILDKIT=0' >> ~/.bashrc

# For root (system-wide)
sudo tee -a /etc/profile.d/podman-docker.sh << 'EOF'
# Podman Docker compatibility
export DOCKER_HOST=unix:///run/podman/podman.sock
alias docker=podman
export DOCKER_BUILDKIT=0
EOF

# Create convenience functions to switch between root and rootless
echo 'podman-root() { sudo -E podman "$@"; }' >> ~/.bashrc
echo 'podman-rootless() { podman "$@"; }' >> ~/.bashrc
echo 'docker-root() { sudo -E podman "$@"; }' >> ~/.bashras
echo 'docker-rootless() { podman "$@"; }' >> ~/.bashrc

# Setup container storage for root
echo "Configuring root container storage..."
sudo mkdir -p /var/lib/containers/storage

# Install Podman Desktop (if desired)
read -p "Do you want to install Podman Desktop GUI? (y/N): " install_desktop
if [[ $install_desktop =~ ^[Yy]$ ]]; then
    echo "Installing Podman Desktop..."
    # Install from AUR (requires yay or similar AUR helper)
    if command -v yay &> /dev/null; then
        yay -S podman-desktop
    else
        echo "Please install Podman Desktop manually from AUR or official website"
        echo "AUR package: podman-desktop"
        echo "Official download: https://podman-desktop.io/downloads"
    fi
fi

# Create a systemd service for root-level container management (optional)
sudo tee /etc/systemd/system/podman-auto-update.service << 'EOF'
[Unit]
Description=Podman auto-update service
Documentation=man:podman-auto-update(1)
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/podman auto-update
StandardOutput=journal

[Install]
WantedBy=multi-user.target
EOF

# Create timer for auto-updates
sudo tee /etc/systemd/system/podman-auto-update.timer << 'EOF'
[Unit]
Description=Podman auto-update timer

[Timer]
OnCalendar=daily
RandomizedDelaySec=900
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Enable auto-update timer
sudo systemctl enable podman-auto-update.timer

# Test installations
echo "Testing Podman installations..."
echo "Rootless Podman:"
podman --version
podman info --format="{{.Host.Security.Rootless}}"

echo "Root Podman:"
sudo podman --version
sudo podman info --format="{{.Host.Security.Rootless}}"

# Test rootless container
echo "Testing rootless container functionality..."
podman run --rm alpine echo "Rootless Podman container working!"

# Test root container
echo "Testing root container functionality..."
sudo podman run --rm alpine echo "Root Podman container working!"

echo "Setup complete!"
echo ""
echo "Configuration summary:"
echo "- Podman installed with compose support"
echo "- Rootless containers configured for user: $USERNAME"
echo "- Root containers configured and enabled"
echo "- Docker compatibility enabled for both modes"
echo "- Podman socket services enabled (user and system)"
echo "- Container restart policy services enabled"
echo "- Auto-update timer enabled for root containers"
echo ""
echo "Usage examples:"
echo ""
echo "Rootless mode (default):"
echo "  podman run -it alpine"
echo "  docker run -it alpine"
echo "  podman-compose up"
echo ""
echo "Root mode:"
echo "  sudo podman run -it alpine"
echo "  podman-root run -it alpine"
echo "  sudo DOCKER_HOST=unix:///run/podman/podman.sock docker-compose up"
echo ""
echo "Socket locations:"
echo "  Rootless: \$XDG_RUNTIME_DIR/podman/podman.sock"
echo "  Root: /run/podman/podman.sock"
echo ""
echo "Container storage locations:"
echo "  Rootless: ~/.local/share/containers/storage"
echo "  Root: /var/lib/containers/storage"
echo ""
echo "Restart your shell or run 'source ~/.bashrc' to apply environment changes."
