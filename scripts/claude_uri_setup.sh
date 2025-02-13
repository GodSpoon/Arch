#!/bin/bash

# Registers a custom x-scheme-handler/claude via a user-local .desktop file, ensuring claude-desktop handles claude:// URIs independent of any distribution-managed .desktop file updates.

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
echo '    claude x-scheme uri handler setup'
echo '    ==================='
echo '    Other arch scripts, configs & documentation available at'
echo '    https://github.com/GodSpoon/Arch'


# Create the custom .desktop file
cat <<EOF > ~/.local/share/applications/claude-uri-handler.desktop
[Desktop Entry]
Type=Application
Name=Claude Link Handler
Exec=$(which claude-desktop) "%u"  # Use 'which' to find the executable
MimeType=x-scheme-handler/claude;
NoDisplay=true
EOF

# Make the .desktop file executable
chmod +x ~/.local/share/applications/claude-uri-handler.desktop

# Update the system's MIME database
update-desktop-database ~/.local/share/applications

# Optional: Display a success message
echo "Claude URI handler configured successfully."

# Test command 
xdg-open claude://claude.ai/magic-link#TEST_LINK  (replace with a real link for testing)
