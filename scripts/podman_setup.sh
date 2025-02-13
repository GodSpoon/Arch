#!/bin/bash

echo '                                            '
echo '                                            '
echo ' _______  _______  _______  _______  __    _        ______    ___   _______ '
echo '|       ||       ||       ||       ||  |  | |      |    _ |  |   | |       |'
echo '|  _____||    _  ||   _   ||   _   ||   |_| |      |   | ||  |   | |    _  |'
echo '| |_____ |   |_| ||  | |  ||  | |  ||       |      |   |_||_ |   | |   |_| |'
echo '|_____  ||    ___||  |_|  ||  |_|  ||  _    | ___  |    __  ||   | |    ___|'
echo ' _____| ||   |    |       ||       || | |   ||   | |   |  | ||   | |   |    '
echo '|_______||___|    |_______||_______||_|  |__||___| |___|  |_||___| |___|    '
echo '                                            '
echo '    podman setup script'
echo '    ==================='
echo '    Other arch scripts, configs & documentation available at'
echo '    https://github.com/GodSpoon/Arch'

# Check for yay and install if needed
if ! command -v yay &> /dev/null; then
    echo "Installing yay..."
    sudo pacman -S --needed git base-devel
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si
    cd ..
    rm -rf yay
fi

# Install Podman and related packages
yay -S --needed \
    podman \
    podman-docker \
    podman-compose \
    crun \
    fuse-overlayfs \
    slirp4netns \
    aardvark-dns \
    netavark

# Create required directories
mkdir -p ~/.config/containers
mkdir -p ~/.local/share/containers/storage
mkdir -p /run/user/$(id -u)

# Configure container engine to use Podman
cat << EOF > ~/.config/containers/containers.conf
[containers]
netns="bridge"
network_backend="netavark"
dns_backend="aardvark"

[engine]
runtime="crun"
events_logger="file"
cgroup_manager="systemd"
volumes_driver="local"
volume_path="/home/$USER/.local/share/containers/storage/volumes"
num_locks=2048
EOF

# Configure storage to use overlay with fuse-overlayfs
cat << EOF > ~/.config/containers/storage.conf
[storage]
driver = "overlay"
runroot = "/run/user/1000"
graphroot = "/home/$USER/.local/share/containers/storage"

[storage.options]
mount_program = "/usr/bin/fuse-overlayfs"

[storage.options.overlay]
mount_program = "/usr/bin/fuse-overlayfs"
mountopt = "nodev,metacopy=on"
EOF

# Configure registries
cat << EOF > ~/.config/containers/registries.conf
[registries.search]
registries = ['docker.io', 'quay.io', 'registry.fedoraproject.org']

[registries.insecure]
registries = []

[registries.block]
registries = []
EOF

# Set up subuid and subgid mappings for rootless mode
sudo touch /etc/subuid /etc/subgid
sudo usermod --add-subuids 100000-165535 $USER
sudo usermod --add-subgids 100000-165535 $USER

# Enable and start the podman socket (optional, for Docker API compatibility)
systemctl --user enable podman.socket
systemctl --user start podman.socket

# Set up docker alias (optional)
echo 'alias docker=podman' >> ~/.bashrc

# Create default network (optional)
podman network create podman

# Verify installation
echo "Verifying Podman installation..."
podman --version
podman info

echo "Podman setup complete. You may need to log out and back in for all changes to take effect."
echo "To use Docker Compose with Podman, use: podman-compose"
