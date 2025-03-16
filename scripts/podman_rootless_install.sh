#!/bin/bash
#
# Podman Rootless Installation Script for Arch Linux
# This script sets up podman in rootless mode with networking and filesystem access
# Path: ~/SPOON_GIT/Arch/scripts/podman_rootless_install.sh

set -e

echo "=== Podman Rootless Setup for Arch Linux ==="
echo "This script will install and configure podman in rootless mode"

# Function to check if running as root
check_not_root() {
    if [ "$(id -u)" -eq 0 ]; then
        echo "Error: This script is designed for rootless setup and should NOT be run as root"
        echo "Please run as a regular user"
        exit 1
    fi
}

# Function to install required packages
install_packages() {
    echo "=== Installing required packages ==="
    sudo pacman -Syu --noconfirm
    sudo pacman -S --needed --noconfirm podman fuse-overlayfs slirp4netns crun catatonit

    # Check if packages were installed correctly
    if ! command -v podman &> /dev/null; then
        echo "Error: podman installation failed"
        exit 1
    fi
    
    echo "Packages installed successfully"
}

# Function to configure user namespaces
configure_user_namespaces() {
    echo "=== Configuring user namespaces ==="
    
    # Check if already configured
    if grep -q "user.max_user_namespaces" /etc/sysctl.d/userns.conf 2>/dev/null; then
        echo "User namespaces already configured"
    else
        echo "Configuring user namespaces limits"
        echo 'kernel.unprivileged_userns_clone=1' | sudo tee -a /etc/sysctl.d/userns.conf
        echo 'user.max_user_namespaces=28633' | sudo tee -a /etc/sysctl.d/userns.conf
        
        # Apply sysctl settings
        sudo sysctl --system
    fi
    
    # Verify configuration
    current_max=$(sysctl -n user.max_user_namespaces 2>/dev/null || echo "0")
    if [ "$current_max" -lt 10000 ]; then
        echo "Warning: user.max_user_namespaces is set to $current_max, which might be too low"
        echo "The configuration has been updated, but you may need to reboot for changes to take effect"
    else
        echo "User namespace configuration verified"
    fi
}

# Function to configure subuid and subgid mappings
configure_subuid_subgid() {
    echo "=== Configuring subuid and subgid mappings ==="
    
    USERNAME=$(whoami)
    
    # Check if already configured with sufficient range
    if grep -q "$USERNAME:100000:65536" /etc/subuid 2>/dev/null && 
       grep -q "$USERNAME:100000:65536" /etc/subgid 2>/dev/null; then
        echo "subuid and subgid already configured correctly"
    else
        # Configure subuid and subgid
        echo "Configuring subuid and subgid for $USERNAME"
        sudo usermod --add-subuids 100000-165535 $USERNAME
        sudo usermod --add-subgids 100000-165535 $USERNAME
        
        # Verify configuration
        echo "Verifying subuid configuration:"
        grep "$USERNAME" /etc/subuid
        echo "Verifying subgid configuration:"
        grep "$USERNAME" /etc/subgid
    fi
}

# Function to configure podman storage
configure_storage() {
    echo "=== Configuring podman storage ==="
    
    STORAGE_CONF_DIR="$HOME/.config/containers"
    mkdir -p "$STORAGE_CONF_DIR"
    
    if [ -f "$STORAGE_CONF_DIR/storage.conf" ]; then
        echo "Storage configuration already exists"
        echo "Backing up existing configuration to $STORAGE_CONF_DIR/storage.conf.bak"
        cp "$STORAGE_CONF_DIR/storage.conf" "$STORAGE_CONF_DIR/storage.conf.bak"
    fi
    
    # Get current user ID
USER_ID=$(id -u)

cat > "$STORAGE_CONF_DIR/storage.conf" << EOF
[storage]
driver = "overlay"
runroot = "/run/user/$USER_ID/containers"
graphroot = "$HOME/.local/share/containers/storage"

[storage.options]
pull_options = {enable_partial_images = "false", use_hard_links = "false", ostree_repos=""}

[storage.options.overlay]
mount_program = "/usr/bin/fuse-overlayfs"
mountopt = "nodev,fsync=0"

[storage.options.thinpool]
EOF
    
    echo "Storage configuration created at $STORAGE_CONF_DIR/storage.conf"
}

# Function to configure podman networking
configure_networking() {
    echo "=== Configuring podman networking ==="
    
    NETWORK_CONF_DIR="$HOME/.config/containers"
    mkdir -p "$NETWORK_CONF_DIR"
    
    if [ -f "$NETWORK_CONF_DIR/networks/podman-default-bridge.conflist" ]; then
        echo "Network configuration directory already exists"
    else
        mkdir -p "$NETWORK_CONF_DIR/networks"
        
        # Create default network configuration
        cat > "$NETWORK_CONF_DIR/networks/podman-default-bridge.conflist" << EOF
{
  "cniVersion": "0.4.0",
  "name": "podman",
  "plugins": [
    {
      "type": "bridge",
      "bridge": "cni-podman0",
      "isGateway": true,
      "ipMasq": true,
      "hairpinMode": true,
      "ipam": {
        "type": "host-local",
        "routes": [{ "dst": "0.0.0.0/0" }],
        "ranges": [
          [
            {
              "subnet": "10.88.0.0/16",
              "gateway": "10.88.0.1"
            }
          ]
        ]
      }
    },
    {
      "type": "portmap",
      "capabilities": {
        "portMappings": true
      }
    },
    {
      "type": "firewall"
    },
    {
      "type": "tuning"
    }
  ]
}
EOF
    fi
    
    # Create containers.conf with network configuration
    if [ -f "$NETWORK_CONF_DIR/containers.conf" ]; then
        echo "Container configuration already exists"
        echo "Backing up existing configuration to $NETWORK_CONF_DIR/containers.conf.bak"
        cp "$NETWORK_CONF_DIR/containers.conf" "$NETWORK_CONF_DIR/containers.conf.bak"
    fi
    
    cat > "$NETWORK_CONF_DIR/containers.conf" << 'EOF'
[containers]
netns="host"
userns="auto"
ipcns="host"
utsns="private"
cgroupns="host"
cgroups="enabled"
log_driver = "k8s-file"
network_backend = "cni"

[engine]
cgroup_manager = "systemd"
events_logger = "file"
runtime = "crun"

[network]
network_backend = "cni"
default_network = "podman"
EOF
    
    echo "Network configuration created"
}

# Function to enable lingering for systemd user services
enable_lingering() {
    echo "=== Enabling lingering for systemd user services ==="
    
    USERNAME=$(whoami)
    if loginctl show-user "$USERNAME" | grep -q "Linger=yes"; then
        echo "Lingering already enabled for $USERNAME"
    else
        sudo loginctl enable-linger "$USERNAME"
        echo "Lingering enabled for $USERNAME"
    fi
}

# Function to setup systemd socket activation
setup_systemd_socket() {
    echo "=== Setting up systemd socket activation ==="
    
    SYSTEMD_DIR="$HOME/.config/systemd/user"
    mkdir -p "$SYSTEMD_DIR"
    
    # Create podman.socket
    cat > "$SYSTEMD_DIR/podman.socket" << 'EOF'
[Unit]
Description=Podman API Socket
Documentation=man:podman-system-service(1)

[Socket]
ListenStream=%t/podman/podman.sock
SocketMode=0660

[Install]
WantedBy=sockets.target
EOF
    
    # Create podman.service
    cat > "$SYSTEMD_DIR/podman.service" << 'EOF'
[Unit]
Description=Podman API Service
Requires=podman.socket
After=podman.socket
Documentation=man:podman-system-service(1)

[Service]
Type=oneshot
ExecStart=/usr/bin/podman system service --time=0
RemainAfterExit=yes

[Install]
WantedBy=default.target
EOF
    
    # Reload systemd
    systemctl --user daemon-reload
    
    # Enable and start the socket
    systemctl --user enable --now podman.socket
    
    # Check status
    systemctl --user status podman.socket --no-pager
    
    echo "Systemd socket activation configured and started"
}

# Function to test podman installation
test_podman() {
    echo "=== Testing podman installation ==="
    
    echo "Running basic podman test (podman info):"
    podman info
    
    echo "Testing container run:"
    podman run --rm hello-world
    
    echo "Setup a simple container with port mapping:"
    podman run -d --name nginx-test -p 8080:80 nginx:alpine
    
    echo "Testing port mapping (should show HTML output):"
    curl -s localhost:8080 | head -5
    
    echo "Cleaning up test container:"
    podman stop nginx-test
    podman rm nginx-test
    
    echo "Podman test completed successfully"
}

# Function to setup podman auto-updates
setup_auto_updates() {
    echo "=== Setting up podman auto-update service ==="
    
    SYSTEMD_DIR="$HOME/.config/systemd/user"
    
    # Create auto-update timer
    cat > "$SYSTEMD_DIR/podman-auto-update.timer" << 'EOF'
[Unit]
Description=Podman auto-update timer

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    # Create auto-update service
    cat > "$SYSTEMD_DIR/podman-auto-update.service" << 'EOF'
[Unit]
Description=Podman auto-update service
Documentation=man:podman-auto-update(1)

[Service]
Type=oneshot
ExecStart=/usr/bin/podman auto-update

[Install]
WantedBy=default.target
EOF
    
    # Reload systemd
    systemctl --user daemon-reload
    
    # Enable the timer
    systemctl --user enable podman-auto-update.timer
    
    echo "Podman auto-update service configured"
}

# Function to setup environment variables
setup_environment() {
    echo "=== Setting up environment variables ==="
    
    BASHRC="$HOME/.bashrc"
    
    # Check if variables are already set
    if grep -q "CONTAINER ENVIRONMENT" "$BASHRC"; then
        echo "Environment variables already configured in $BASHRC"
    else
        cat >> "$BASHRC" << 'EOF'

# CONTAINER ENVIRONMENT
export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock
export CONTAINER_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock
alias docker='podman'
EOF
        
        echo "Environment variables added to $BASHRC"
        echo "Please run 'source ~/.bashrc' or start a new shell to apply changes"
    fi
}

# Function to set up a docker compose replacement
setup_compose() {
    echo "=== Setting up podman-compose ==="
    
    # Check if podman-compose is already installed
    if command -v podman-compose &> /dev/null; then
        echo "podman-compose is already installed"
    else
        # Install pip if not already installed
        if ! command -v pip &> /dev/null; then
            sudo pacman -S --needed --noconfirm python-pip
        fi
        
        # Install podman-compose
        pip install --user podman-compose
        
        echo "podman-compose installed successfully"
    fi
}

# Main execution
main() {
    # Check if not root
    check_not_root
    
    # Run setup functions
    install_packages
    configure_user_namespaces
    configure_subuid_subgid
    configure_storage
    configure_networking
    enable_lingering
    setup_systemd_socket
    setup_auto_updates
    setup_environment
    setup_compose
    
    # Test podman
    test_podman
    
    echo ""
    echo "=== Podman rootless setup completed successfully ==="
    echo "You can now use podman and docker-compose with your regular user"
    echo "To start using podman right away, run: source ~/.bashrc"
}

# Run main function
main
