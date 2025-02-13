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

