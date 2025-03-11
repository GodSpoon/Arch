#!/bin/bash

OUTPUT_FILE="$HOME/dotfiles_structure.txt"

echo "Saving dotfiles structure to $OUTPUT_FILE..."
find ~ -maxdepth 3 -name ".*" -type f -o -name ".*" -type d | grep -v "\.git/" | sort > "$OUTPUT_FILE"
echo "Done! You can find the structure at $OUTPUT_FILE"
chmod +x "$0"
