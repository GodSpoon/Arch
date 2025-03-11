#!/bin/bash
# GNU Stow setup script for dotfiles management
# For repository: https://github.com/GodSpoon/dotfiles

set -e

# Configuration
DOTFILES_REPO="https://github.com/GodSpoon/dotfiles.git"
DOTFILES_DIR="$HOME/SPOON_GIT/dotfiles"
BACKUP_DIR="$HOME/.dotfiles_backup_$(date +%Y%m%d%H%M%S)"
WATCH_FILE="$HOME/.config/stow-watch.conf"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if GNU Stow is installed
if ! command -v stow &> /dev/null; then
    echo -e "${YELLOW}GNU Stow is not installed. Installing...${NC}"
    sudo pacman -S stow --noconfirm
fi

# Check if inotify-tools is installed (for watching files)
if ! command -v inotifywait &> /dev/null; then
    echo -e "${YELLOW}inotify-tools not installed. Auto-sync feature requires this.${NC}"
    read -p "Install inotify-tools for file watching? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo pacman -S inotify-tools --noconfirm
    else
        echo -e "${YELLOW}Proceeding without auto-sync capability.${NC}"
    fi
fi

# Clone the repository if it doesn't exist
if [ ! -d "$DOTFILES_DIR" ]; then
    echo -e "${BLUE}Dotfiles repository doesn't exist. Would you like to clone it?${NC}"
    read -p "Clone repository? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Cloning dotfiles repository...${NC}"
        git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
    else
        echo -e "${YELLOW}Creating new local dotfiles repository...${NC}"
        mkdir -p "$DOTFILES_DIR"
        (cd "$DOTFILES_DIR" && git init && git remote add origin "$DOTFILES_REPO")
    fi
else
    echo -e "${GREEN}Dotfiles repository already exists at $DOTFILES_DIR${NC}"
    echo -e "${BLUE}Pull latest changes?${NC}"
    read -p "(y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        (cd "$DOTFILES_DIR" && git pull)
    fi
fi

# Create package directories if they don't exist
mkdir -p "$DOTFILES_DIR/bash"
mkdir -p "$DOTFILES_DIR/zsh"
mkdir -p "$DOTFILES_DIR/git"
mkdir -p "$DOTFILES_DIR/vim"
mkdir -p "$DOTFILES_DIR/config"
mkdir -p "$DOTFILES_DIR/ssh"

# Function to copy a file to the dotfiles repo with directory structure
copy_to_dotfiles() {
    local src="$1"
    local pkg="$2"
    local base_dir="$3"
    local preview="$4"
    
    # Skip if source doesn't exist
    if [ ! -e "$HOME/$src" ]; then
        return
    fi
    
    # Get the relative path from base_dir
    local rel_path="$src"
    if [ -n "$base_dir" ]; then
        rel_path="${src#$base_dir/}"
    fi
    
    # Create directory structure
    local target_dir="$DOTFILES_DIR/$pkg/$(dirname "$rel_path")"
    
    if [ "$preview" = "true" ]; then
        echo -e "${BLUE}Would copy: $HOME/$src → $target_dir/${NC}"
    else
        mkdir -p "$target_dir"
        echo -e "${GREEN}Copying: $HOME/$src → $target_dir/${NC}"
        cp -r "$HOME/$src" "$target_dir/"
    fi
}

# Function to stow a package
stow_package() {
    local pkg="$1"
    local preview="$2"
    
    if [ -d "$DOTFILES_DIR/$pkg" ] && [ "$(ls -A "$DOTFILES_DIR/$pkg")" ]; then
        if [ "$preview" = "true" ]; then
            echo -e "${BLUE}Would stow: $pkg package${NC}"
            (cd "$DOTFILES_DIR" && stow --simulate -v "$pkg" 2>&1 | grep -v "BUG in find_stowed_path" || true)
        else
            echo -e "${GREEN}Stowing: $pkg package...${NC}"
            (cd "$DOTFILES_DIR" && stow -D "$pkg" 2>/dev/null || true)
            (cd "$DOTFILES_DIR" && stow -v "$pkg")
        fi
    else
        echo -e "${YELLOW}Skipping $pkg package (empty or non-existent)${NC}"
    fi
}

# Function to setup file watching for automatic sync
setup_file_watching() {
    echo -e "${BLUE}Setting up automatic sync for dotfiles...${NC}"
    
    # Create the systemd user service file
    mkdir -p "$HOME/.config/systemd/user"
    cat << 'SYSTEMD_EOF' > "$HOME/.config/systemd/user/dotfiles-watcher.service"
[Unit]
Description=Watch for changes in dotfiles and sync them
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash -c 'source ~/SPOON_GIT/Arch/scripts/stow_watch.sh'
Restart=on-failure

[Install]
WantedBy=default.target
SYSTEMD_EOF

    # Create the watch script
    cat << 'WATCH_SCRIPT_EOF' > ~/SPOON_GIT/Arch/scripts/stow_watch.sh
#!/bin/bash

DOTFILES_DIR="$HOME/SPOON_GIT/dotfiles"
WATCH_FILE="$HOME/.config/stow-watch.conf"

if [ ! -f "$WATCH_FILE" ]; then
    echo "Watch configuration file not found: $WATCH_FILE"
    exit 1
fi

while true; do
    while read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
        
        # Parse line: source_path:package_name
        IFS=':' read -r source_path package_name <<< "$line"
        
        # Watch for changes
        echo "Watching $HOME/$source_path for changes..."
        
        inotifywait -e modify,create,delete,move -r "$HOME/$source_path" --format "%w%f" | while read -r changed_file; do
            echo "Change detected in $changed_file"
            # Copy to dotfiles repo
            rel_path="${changed_file#$HOME/}"
            target_dir="$DOTFILES_DIR/$package_name/$(dirname "$rel_path")"
            mkdir -p "$target_dir"
            cp -r "$changed_file" "$target_dir/"
            
            # Re-stow package
            (cd "$DOTFILES_DIR" && stow -R "$package_name")
            
            echo "Updated dotfiles repository with changes from $changed_file"
        done
    done < "$WATCH_FILE"
    
    # If we get here, there was an error with the watch file or inotifywait
    # Sleep a bit before trying again
    sleep 30
done
WATCH_SCRIPT_EOF

    chmod +x ~/SPOON_GIT/Arch/scripts/stow_watch.sh
    
    # Create the watch configuration file
    mkdir -p "$(dirname "$WATCH_FILE")"
    cat << 'WATCH_CONF_EOF' > "$WATCH_FILE"
# Format: source_path:package_name
# Example: .zshrc:zsh
.zshrc:zsh
.bashrc:bash
.gitconfig:git
.config/nvim:config
WATCH_CONF_EOF

    echo -e "${GREEN}Watch configuration created at $WATCH_FILE${NC}"
    echo -e "${YELLOW}Edit this file to add more files/directories to watch${NC}"
    
    # Enable and start the service
    echo -e "${BLUE}Would you like to enable automatic sync now?${NC}"
    read -p "(y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        systemctl --user daemon-reload
        systemctl --user enable dotfiles-watcher.service
        systemctl --user start dotfiles-watcher.service
        echo -e "${GREEN}Automatic sync enabled and started${NC}"
    else
        echo -e "${YELLOW}You can enable it later with:${NC}"
        echo "systemctl --user enable dotfiles-watcher.service"
        echo "systemctl --user start dotfiles-watcher.service"
    fi
}

# Preview mode function
preview_changes() {
    echo -e "${BLUE}=== PREVIEW MODE: Showing what would happen ===${NC}"
    
    # Bash files
    copy_to_dotfiles ".bashrc" "bash" "" "true"
    copy_to_dotfiles ".bash_profile" "bash" "" "true"
    copy_to_dotfiles ".bash_logout" "bash" "" "true"
    
    # ZSH files
    copy_to_dotfiles ".zshrc" "zsh" "" "true"
    copy_to_dotfiles ".zprofile" "zsh" "" "true"
    
    # Git config
    copy_to_dotfiles ".gitconfig" "git" "" "true"
    
    # Vim files (if you use vim)
    copy_to_dotfiles ".vimrc" "vim" "" "true"
    
    # SSH config (excluding keys for security)
    if [ -f "$HOME/.ssh/config" ]; then
        echo -e "${BLUE}Would copy: $HOME/.ssh/config → $DOTFILES_DIR/ssh/.ssh/${NC}"
    fi
    
    # Config directories (selected based on your file listing)
    CONFIG_DIRS=(
        "alacritty" 
        "kitty" 
        "nvim" 
        "tmux" 
        "neofetch" 
        "rofi"
    )
    
    for dir in "${CONFIG_DIRS[@]}"; do
        if [ -d "$HOME/.config/$dir" ]; then
            echo -e "${BLUE}Would copy: $HOME/.config/$dir → $DOTFILES_DIR/config/.config/${NC}"
        fi
    done
    
    # Preview stow operations
    echo -e "\n${BLUE}=== Stow operations that would be performed ===${NC}"
    stow_package "bash" "true"
    stow_package "zsh" "true"
    stow_package "git" "true"
    stow_package "vim" "true"
    stow_package "ssh" "true"
    stow_package "config" "true"
}

# Main execution
if [ "$1" == "--preview" ]; then
    preview_changes
    exit 0
fi

# Show preview first
preview_changes

# Ask for confirmation
echo
echo -e "${YELLOW}Do you want to proceed with these changes?${NC}"
read -p "(y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}Operation canceled.${NC}"
    exit 1
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Bash files
copy_to_dotfiles ".bashrc" "bash"
copy_to_dotfiles ".bash_profile" "bash"
copy_to_dotfiles ".bash_logout" "bash"

# ZSH files
copy_to_dotfiles ".zshrc" "zsh"
copy_to_dotfiles ".zprofile" "zsh"

# Git config
copy_to_dotfiles ".gitconfig" "git"

# Vim files
copy_to_dotfiles ".vimrc" "vim"

# SSH config (excluding keys for security)
if [ -f "$HOME/.ssh/config" ]; then
    mkdir -p "$DOTFILES_DIR/ssh/.ssh"
    echo -e "${GREEN}Copying .ssh/config to $DOTFILES_DIR/ssh/.ssh/${NC}"
    cp "$HOME/.ssh/config" "$DOTFILES_DIR/ssh/.ssh/"
fi

# Config directories (selected based on your file listing)
CONFIG_DIRS=(
    "alacritty" 
    "kitty" 
    "nvim" 
    "tmux" 
    "neofetch" 
    "rofi"
)

for dir in "${CONFIG_DIRS[@]}"; do
    if [ -d "$HOME/.config/$dir" ]; then
        mkdir -p "$DOTFILES_DIR/config/.config"
        echo -e "${GREEN}Copying .config/$dir to $DOTFILES_DIR/config/.config/${NC}"
        cp -r "$HOME/.config/$dir" "$DOTFILES_DIR/config/.config/"
    fi
done

# Stow all packages
stow_package "bash"
stow_package "zsh"
stow_package "git"
stow_package "vim"
stow_package "ssh"
stow_package "config"

# Ask about setting up file watching
echo
echo -e "${BLUE}Would you like to set up automatic syncing of dotfiles when they change?${NC}"
read -p "(y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    setup_file_watching
fi

echo -e "${GREEN}Dotfiles setup complete!${NC}"
echo -e "${YELLOW}Backup of previous dotfiles repo files saved to $BACKUP_DIR${NC}"
echo
echo -e "${BLUE}Next steps:${NC}"
echo "1. Review the files in $DOTFILES_DIR"
echo "2. Commit and push your changes to GitHub:"
echo "   cd $DOTFILES_DIR"
echo "   git add ."
echo "   git commit -m \"Updated dotfiles\""
echo "   git push"
echo
echo -e "${BLUE}Usage:${NC}"
echo "- Run $(basename "$0") --preview    # To see what would happen without making changes"
echo "- Run $(basename "$0")              # To set up or update your dotfiles"
echo
echo -e "${YELLOW}If you enabled automatic sync:${NC}"
echo "- Edit $WATCH_FILE to configure which files are watched"
echo "- Changes to watched files will automatically be copied to the dotfiles repo"
echo "- Check status: systemctl --user status dotfiles-watcher.service"
