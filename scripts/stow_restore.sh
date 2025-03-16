#!/bin/bash
# Quick dotfiles restore script for new machines

set -e

DOTFILES_REPO="https://github.com/GodSpoon/dotfiles.git"
DOTFILES_DIR="$HOME/SPOON_GIT/dotfiles"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check dependencies
echo -e "${BLUE}Checking dependencies...${NC}"
if ! command -v git &> /dev/null || ! command -v stow &> /dev/null; then
    echo -e "${YELLOW}Installing required packages...${NC}"
    if command -v pacman &> /dev/null; then
        # Arch-based
        sudo pacman -S git stow --noconfirm
    elif command -v apt &> /dev/null; then
        # Debian-based
        sudo apt update && sudo apt install -y git stow
    elif command -v dnf &> /dev/null; then
        # Fedora-based
        sudo dnf install -y git stow
    else
        echo -e "${RED}ERROR: Please install git and stow manually for your distribution${NC}"
        exit 1
    fi
fi

# Create directory and clone repo
echo -e "${BLUE}Setting up dotfiles directory...${NC}"
mkdir -p "$(dirname "$DOTFILES_DIR")"

if [ ! -d "$DOTFILES_DIR" ]; then
    echo -e "${BLUE}Cloning dotfiles repository...${NC}"
    git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
else
    echo -e "${YELLOW}Dotfiles directory already exists. Checking status...${NC}"
    if [ -z "$(ls -A "$DOTFILES_DIR")" ]; then
        echo -e "${YELLOW}Directory is empty. Removing and cloning again...${NC}"
        rm -rf "$DOTFILES_DIR"
        git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
    else
        echo -e "${BLUE}Updating existing repository...${NC}"
        (cd "$DOTFILES_DIR" && git pull)
    fi
fi

# Apply all stowable packages
cd "$DOTFILES_DIR"
if [ -z "$(ls -A "$DOTFILES_DIR")" ]; then
    echo -e "${YELLOW}The dotfiles repository is empty.${NC}"
    echo -e "${BLUE}You need to set up your dotfiles first using the stow_setup.sh script.${NC}"
    echo -e "${BLUE}Run: ~/SPOON_GIT/Arch/scripts/stow_setup.sh${NC}"
    exit 1
fi

echo -e "${BLUE}Applying dotfiles...${NC}"
for pkg in */; do
    pkg=${pkg%/}  # Remove trailing slash
    if [ -d "$pkg" ] && [ "$(ls -A "$pkg" 2>/dev/null)" ]; then
        echo -e "${GREEN}Stowing $pkg...${NC}"
        stow -v "$pkg"
    fi
done

echo -e "${GREEN}Dotfiles successfully restored! Your configuration is now active.${NC}"
