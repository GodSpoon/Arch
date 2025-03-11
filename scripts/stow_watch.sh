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
