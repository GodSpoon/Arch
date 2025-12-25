#!/bin/bash
# Script to download, build, and install KerJoe/RTDMultiProg on Arch Linux
# Installs to ~/SPOON_GIT/RTDMultiProg and makes it globally callable as `rtdmultiprog`

set -e

REPO_URL="https://github.com/KerJoe/RTDMultiProg.git"
INSTALL_DIR="$HOME/SPOON_GIT/RTDMultiProg"
BINARY_NAME="rtdmultiprog"
SHELL_RC="$HOME/.zshrc"

echo "----[ 1. Install dependencies ]----"
sudo pacman -Sy --needed --noconfirm git base-devel

echo "----[ 2. Clone RTDMultiProg repo ]----"
if [ ! -d "$INSTALL_DIR" ]; then
  git clone "$REPO_URL" "$INSTALL_DIR"
else
  echo "Directory $INSTALL_DIR already exists. Skipping clone."
fi

cd "$INSTALL_DIR"

echo "----[ 3. Build project ]----"
if [ -f "Makefile" ]; then
  make clean || true
  make
elif [ -f "CMakeLists.txt" ]; then
  mkdir -p build && cd build
  cmake ..
  make
  cd ..
else
  echo "Error: No Makefile or CMakeLists.txt found. Please check the build instructions."
  exit 1
fi

echo "----[ 4. Find built binary ]----"
# Try to find the binary after build
BIN_PATH=""
if [ -f "./$BINARY_NAME" ]; then
  BIN_PATH="$PWD/$BINARY_NAME"
elif [ -f "./build/$BINARY_NAME" ]; then
  BIN_PATH="$PWD/build/$BINARY_NAME"
else
  # Try to find the binary in the directory
  BIN_PATH=$(find . -type f -executable -name "$BINARY_NAME" | head -n1)
  if [ -z "$BIN_PATH" ]; then
    echo "Error: Could not find built binary named $BINARY_NAME"
    exit 1
  fi
fi

echo "----[ 5. Install binary to ~/bin or ~/.local/bin ]----"
# Prefer ~/.local/bin if it exists, else make ~/bin
if [ -d "$HOME/.local/bin" ]; then
  TARGET_DIR="$HOME/.local/bin"
elif [ -d "$HOME/bin" ]; then
  TARGET_DIR="$HOME/bin"
else
  TARGET_DIR="$HOME/.local/bin"
  mkdir -p "$TARGET_DIR"
fi

cp "$BIN_PATH" "$TARGET_DIR/$BINARY_NAME"
chmod +x "$TARGET_DIR/$BINARY_NAME"

echo "----[ 6. Add binary to PATH in .zshrc if needed ]----"
if ! grep -q "$TARGET_DIR" "$SHELL_RC"; then
  echo "export PATH=\"$TARGET_DIR:\$PATH\"" >> "$SHELL_RC"
  echo "Added $TARGET_DIR to PATH in $SHELL_RC"
else
  echo "$TARGET_DIR already in PATH in $SHELL_RC"
fi

echo "----[ 7. Done! ]----"
echo "You may need to restart your terminal or run 'source $SHELL_RC' for the binary to be available as '$BINARY_NAME'."
echo "Test with: $BINARY_NAME --help"
