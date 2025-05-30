#!/bin/bash

set -e

echo "=== Cloudflare Pass Setup Script ==="

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install pass if needed
if ! command_exists pass; then
    echo "Installing pass..."
    sudo pacman -S --noconfirm pass
else
    echo "✓ pass is already installed"
fi

# Check if GPG keys exist
if ! gpg --list-secret-keys --keyid-format LONG 2>/dev/null | grep -q "sec"; then
    echo "No GPG keys found. Creating a new GPG key..."
    echo "You'll be prompted for:"
    echo "  - Real name"
    echo "  - Email address (suggest: dev@spoon.rip)"
    echo "  - Passphrase (remember this!)"
    echo ""
    read -p "Press Enter to continue..."

    # Generate GPG key non-interactively but with prompts
    gpg --full-generate-key
else
    echo "✓ GPG keys already exist"
    gpg --list-secret-keys --keyid-format LONG
fi

# Check if pass is initialized
if [ ! -d "$HOME/.password-store" ]; then
    echo ""
    echo "Initializing pass..."

    # Get the email from GPG key
    GPG_EMAIL=$(gpg --list-secret-keys --keyid-format LONG | grep uid | head -1 | sed 's/.*<\(.*\)>.*/\1/')

    if [ -z "$GPG_EMAIL" ]; then
        echo "Could not find GPG email. Please enter the email you used for your GPG key:"
        read -p "Email: " GPG_EMAIL
    fi

    echo "Initializing pass with email: $GPG_EMAIL"
    pass init "$GPG_EMAIL"
else
    echo "✓ pass is already initialized"
fi

# Store CF API token
echo ""
echo "Now we'll store your Cloudflare API token securely."
echo "You can get your API token from: https://dash.cloudflare.com/profile/api-tokens"
echo ""

if pass show cloudflare/api-token >/dev/null 2>&1; then
    echo "Cloudflare API token already exists in pass."
    read -p "Do you want to update it? (y/N): " UPDATE_TOKEN
    if [[ "$UPDATE_TOKEN" =~ ^[Yy]$ ]]; then
        pass insert -f cloudflare/api-token
    fi
else
    echo "Storing Cloudflare API token..."
    pass insert cloudflare/api-token
fi

echo ""
echo "✓ Setup complete!"
echo ""
echo "Add this to your ~/.bashrc or ~/.zshrc:"
echo 'export CF_API_TOKEN="$(pass show cloudflare/api-token)"'
echo ""
echo 'export CF_API_TOKEN=\"\$(pass show cloudflare/api-token)\"' >> ~/.zshrc"
