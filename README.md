# Arch
Arch linux scripts, configs, tools, documentation, etc.

## Scripts
**Podman Setup**

Installs and configures Podman, podman dependencies, storage, networking, and rootless support, aiming for Docker compatibility via aliases and socket activation.  It also installs yay if missing.
```
curl -sSL https://raw.githubusercontent.com/GodSpoon/Arch/main/scripts/podman_setup.sh | bash
```
---

**Claude URI Handler**

Registers a custom x-scheme-handler/claude via a user-local .desktop file, ensuring claude-desktop handles claude:// URIs independent of any distribution-managed .desktop file updates.
```
curl -sSL https://github.com/GodSpoon/Arch/blob/main/scripts/claude_uri_setup.sh | bash
```
---

**GNU Stow Dotfiles Setup**

Sets up and manages dotfiles using GNU Stow with automatic change detection and synchronization. Clones the dotfiles repository, organizes configurations into packages, and creates symbolic links. Includes a systemd service for real-time monitoring and syncing of changes.
```
curl -sSL https://raw.githubusercontent.com/GodSpoon/Arch/main/scripts/stow_setup.sh | bash
```

**Adding Custom Files and Directories to Stow**

1. **Manual Addition**:
   ```bash
   # Add files to the appropriate package directory
   cp ~/.custom_file ~/SPOON_GIT/dotfiles/package_name/
   
   # Re-stow the package to create symlinks
   cd ~/SPOON_GIT/dotfiles && stow package_name
   ```

2. **Configure Auto-sync**:
   - Edit the watch configuration to include your files:
   ```bash
   echo ".custom_file:package_name" >> ~/.config/stow-watch.conf
   ```
   - Restart the watcher service:
   ```bash
   systemctl --user restart dotfiles-watcher.service
   ```

3. **Common Package Names**:
   - `bash`: Bash shell configuration
   - `zsh`: Zsh shell configuration
   - `git`: Git configuration
   - `vim`: Vim editor configuration
   - `config`: XDG config directory items
   - `ssh`: SSH configuration (without keys)

---
## Tools
**AUR**

Cool obscure repository where people upload their custom arch application PKGBUILDS for the community to use as well I guess
Not many people seem to know about it so keep an eye out

https://aur.archlinux.org/packages






---
## Naming Convention and README Structure Overview

| Feature        | Description                                                                                                                                                                                                                                                           |
|----------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **File Naming** | `scripts/<tool>_<action>.sh` where `<tool>` is the primary software being configured (e.g., `podman`, `claude`) and `<action>` describes the script's purpose (e.g., `setup`, `uri_setup`). This emphasizes the target software and the operation performed.                                  |
| **README Description** | Each script entry has a concise, technically-oriented summary explaining its function.                                                                                                                                                                                                |
| **README Execution** | The README provides a direct `curl` command to execute the script, facilitating easy installation and configuration. Where appropriate, the raw file URL is used for direct execution; otherwise the blob URL is used.                                                                                                |
| **README Organization** | The README is structured with clear headings (e.g., `## Scripts`) to categorize the scripts and uses separators (`---`) for visual clarity between entries. Each script entry includes a title, description, and execution command. The top-level heading provides a brief overview of the repository's contents. |
