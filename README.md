# Fedora Workstation 44 — Developer Setup

A production-quality, modular bootstrap for a **Fedora 44 / KDE Plasma 6 / Wayland** developer workstation targeting Systems Engineering, DevOps, Cloud, Containers, and Kubernetes workflows.

---

## Table of Contents

1. [Analysis: Package Validation](#1-analysis-package-validation)
2. [Architecture](#2-architecture)
3. [Prerequisites](#3-prerequisites)
4. [Usage](#4-usage)
5. [Modules](#5-modules)
6. [Application Decisions](#6-application-decisions)
7. [Shell Configuration](#7-shell-configuration)
8. [Containers & Kubernetes](#8-containers--kubernetes)
9. [Virtualization](#9-virtualization)
10. [Neovim](#10-neovim)
11. [Security Considerations](#11-security-considerations)
12. [Post-Install Verification](#12-post-install-verification)
13. [Fedora-Specific Caveats](#13-fedora-specific-caveats)

---

## 1. Analysis: Package Validation

### ✅ Valid Fedora 44 RPM Packages

All of the following have been validated for Fedora 44 standard repositories:

| Requested | Fedora 44 Name | Notes |
|-----------|---------------|-------|
| `git` | `git` | ✅ |
| `gcc` | `gcc` | ✅ |
| `gcc-c++` | `gcc-c++` | ✅ |
| `make` | `make` | ✅ |
| `cmake` | `cmake` | ✅ |
| `ninja-build` | `ninja-build` | ✅ |
| `python3` | `python3` | ✅ |
| `python3-pip` | `python3-pip` | ✅ |
| `neovim` | `neovim` | ✅ Fedora 44 ships 0.10.x |
| `vim-enhanced` | `vim-enhanced` | ✅ |
| `ripgrep` | `ripgrep` | ✅ |
| `fd-find` | `fd-find` | ✅ Binary is `fd` (not `fdfind` like Debian) |
| `fzf` | `fzf` | ✅ |
| `htop` | `htop` | ✅ |
| `jq` | `jq` | ✅ |
| `unzip` | `unzip` | ✅ |
| `curl` | `curl` | ✅ |
| `gettext` | `gettext` | ✅ |
| `glibc-gconv-extra` | `glibc-gconv-extra` | ✅ |
| `tree` | `tree` | ✅ (also use `eza --tree`) |
| `git-delta` | `git-delta` | ✅ In Fedora repos since F37 |
| `bat` | `bat` | ✅ |
| `eza` | `eza` | ✅ In Fedora repos since F38, replaces deprecated `exa` |
| `tldr` | `tldr` | ✅ Tealdeer-based client |

### ⚠️ Packages Requiring Special Handling

| Package | Status | Solution |
|---------|--------|----------|
| `thefuck` | `python3-thefuck` dropped after F38 | Install via **pipx** (correct canonical method) |

### 🔍 Renamed / Deprecated Packages

| Old Name | Status | Action |
|----------|--------|--------|
| `exa` | Deprecated, abandoned 2023 | Replaced by `eza` (maintained fork) — already handled |
| `docker-ce` | Not recommended on Fedora | Use **Podman** (rootless, native Fedora) |
| `docker-compose` | Not recommended | Use **podman-compose** or `podman compose` |
| `nautilus-dropbox` | GNOME-only, conflicts KDE | Use **Dropbox RPM** + systemd user service |
| `lotion` | Unmaintained since ~2019 | Use Notion PWA in Brave or Flathub wrapper |

### 📦 COPR Requirements

| Package | COPR | Notes |
|---------|------|-------|
| Neovim nightly | `@neovim/neovim` | Only if Fedora ships < 0.10; F44 ships 0.10.x |

### 🌐 External Repositories Required

| Tool | Repo | Why |
|------|------|-----|
| Brave Nightly | `brave-browser-rpm-nightly.s3.brave.com` | Official Brave repo — most reliable |
| kubectl | `pkgs.k8s.io` | Official Kubernetes repo (replaces deprecated packages.cloud.google.com) |
| Helm | `baltocdn.com/helm` | Official Helm RPM repo |
| GitHub CLI | `cli.github.com` | Official GitHub repo |
| Dropbox | `linux.dropbox.com` | Official Dropbox Linux repo |

### 📱 Flatpak-Only Applications

| App | Flatpak ID | Rationale |
|-----|-----------|-----------|
| Spotify | `com.spotify.Client` | Most reliable, maintained, Wayland-compatible |
| Notion (optional) | `notion.id.Notion` | Official Lotion is dead; Flatpak wrapper is the next best |

### 🔧 Binary Installs (No RPM Available)

| Tool | Version | Source |
|------|---------|--------|
| `kind` | 0.27.0 | GitHub releases |
| `minikube` | latest | Google Storage |
| `sops` | 3.9.1 | GitHub releases |
| `kustomize` | latest | GitHub script |
| `stern` | 1.31.0 | GitHub releases |
| JetBrains Toolbox | latest | JetBrains CDN |

---

## 2. Architecture

```
fedora-workstation-setup/
├── install.sh                    # Main orchestrator
├── lib/
│   ├── helpers.sh                # Logging, prompting, run_cmd, run_as_user
│   ├── checks.sh                 # Pre-flight validation functions
│   └── pkg.sh                    # DNF5/Flatpak/cargo/pip helpers (idempotent)
├── scripts/
│   ├── system/
│   │   ├── 01-system-update.sh   # dnf upgrade, RPM Fusion, fwupd, reboot prompt
│   │   ├── 02-repos.sh           # Brave, kubectl, Helm, GitHub CLI, Flathub repos
│   │   └── 03-devtools.sh        # Build tools, CLI tools, Neovim deps
│   ├── containers/
│   │   └── 01-containers.sh      # Podman, kubectl, Helm, kind, minikube, k9s, stern
│   ├── virt/
│   │   └── 01-kvm.sh             # KVM/QEMU/libvirt, nested virt, polkit rules
│   ├── apps/
│   │   └── 01-applications.sh    # Brave, Dropbox, Spotify, JetBrains, Notion
│   └── shell/
│       ├── 01-zsh.sh             # Zsh, Zinit, Starship, Nerd Font, .zshrc
│       └── 02-neovim.sh          # Neovim config with lazy.nvim, LSP, Telescope
├── configs/
│   ├── zsh/                      # Additional zsh config snippets
│   ├── neovim/                   # Neovim config templates
│   └── kde/                      # KDE-specific settings
├── logs/                         # Run logs (gitignored)
└── README.md
```

### Design Principles

- **Non-root execution**: `install.sh` must be run as your normal user. `sudo` is invoked only where truly needed, from within scripts.
- **Idempotency**: Every operation checks before acting. Re-running is safe.
- **Strict mode**: All scripts use `set -euo pipefail` and `IFS=$'\n\t'`.
- **Correct home handling**: `real_home()` and `run_as_user()` prevent writing to `/root` when operating in sudo contexts.
- **Modular**: Run any single module with `--only <name>`.
- **Logged**: All output tee'd to `./logs/setup-TIMESTAMP.log`.

---

## 3. Prerequisites

- Fedora 44 Workstation installed
- KDE Plasma 6 (optional but recommended)
- Active internet connection
- User in `wheel` group (for sudo)
- At least 10 GB free disk space

---

## 4. Usage

```bash
# Clone or copy this repo to your home directory
cd ~/fedora-workstation-setup

# Make executable
chmod +x install.sh scripts/**/*.sh

# Full interactive setup (recommended)
./install.sh

# Preview all actions without executing
./install.sh --dry-run

# Non-interactive (CI/automation)
./install.sh --yes --skip-reboot

# Run only one module
./install.sh --only containers
./install.sh --only shell
./install.sh --only neovim

# After first run (post-reboot), skip the update/reboot steps
./install.sh --skip-reboot
```

### Flags

| Flag | Effect |
|------|--------|
| `--dry-run` | Print all actions without executing. Safe to run anytime. |
| `--yes` / `-y` | Auto-confirm all prompts. |
| `--skip-reboot` | Skip the reboot prompt after system update. |
| `--only <module>` | Run only the specified module. |

---

## 5. Modules

### `system` — System Update
1. `dnf upgrade --best --allowerasing`
2. Enables RPM Fusion Free + Nonfree
3. Runs `fwupdmgr` firmware check
4. Prompts for reboot (strongly recommended)

### `repos` — Repository Configuration
Configures: Brave Nightly, kubectl (pkgs.k8s.io), Helm, GitHub CLI, Flathub.

### `devtools` — Developer Tools
All core build tools, modern CLI replacements, GitHub CLI, SOPS, pre-commit.

### `containers` — Containers & Kubernetes
Podman stack, rootless config, kubectl, Helm, kind, minikube, k9s, kubectx, stern, kustomize.

### `virt` — Virtualization
KVM/QEMU/libvirt, nested virtualization, polkit rules, user group config.

### `apps` — Applications
Brave Nightly, Dropbox (KDE-compatible), Spotify (Flatpak), JetBrains Toolbox, Notion.

### `shell` — Shell Environment
Zsh + Zinit + Starship, JetBrains Mono Nerd Font, complete `.zshrc` with aliases.

### `neovim` — Neovim
Neovim config with lazy.nvim: LSP (Mason), Telescope, Treesitter, Catppuccin, completion.

---

## 6. Application Decisions

### Dropbox on KDE

`nautilus-dropbox` pulls in GNOME file manager extensions — wrong for KDE. The correct approach:
- Install the `dropbox` RPM (from dropbox.com repo) — provides daemon + CLI, no GNOME deps
- Configure a systemd user service to auto-start the daemon
- Dropbox uses native systray, which KDE Plasma 6 supports

### Spotify

Flathub Flatpak is the canonical, most reliable method. Reasons:
- RPM Fusion's Spotify package is often outdated
- Flatpak receives updates from Spotify directly
- Works on Wayland via XWayland (Spotify doesn't support Wayland natively)
- Proper audio via Pipewire's PulseAudio compatibility

### Notion / Lotion

**Lotion is dead.** Last commit ~2019, uses outdated Electron 2.x, security vulnerabilities unfixed. Options in order of recommendation:

1. **Notion as PWA in Brave** ← Best. Native app experience, always up to date.
2. **Flathub `notion.id.Notion`** ← Community-maintained wrapper, reasonable.

### JetBrains Toolbox

No official RPM. Binary install from JetBrains CDN is the only supported method. Toolbox auto-manages all JetBrains IDEs and keeps them updated.

---

## 7. Shell Configuration

### Why Starship Instead of OMZ + Agnoster

| | Oh My Zsh + Agnoster | Zinit + Starship |
|--|--|--|
| Startup time | 150–400ms | < 30ms |
| Kubernetes context | Plugin required | Built-in |
| Cloud context (AWS/GCP) | Manual setup | Built-in |
| Git status detail | Basic | Rich (stash, diverged, etc.) |
| Language versions | Separate plugins | Built-in |
| Maintenance | High (many plugins) | Low (one binary) |
| Wayland support | Fine | Fine |

**Verdict**: Starship is objectively better for a DevOps workstation. If you prefer OMZ:

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
# Then set ZSH_THEME="agnoster" in ~/.zshrc
```

### Key Aliases Added

- `ll`, `la`, `lt` — eza with icons and git status
- `cat` → bat (syntax highlighting, git integration)
- `top` → btop (better process viewer)
- `k` → kubectl; full suite: `kgp`, `kns`, `kctx`, `krun`
- `docker` → podman; `dc` → podman-compose
- `v`, `vi`, `vim` → nvim
- Git: `gs`, `gl`, `gd`, `gp`, `gpl`, `gco`, etc.

---

## 8. Containers & Kubernetes

### Docker Engine: NOT Installed

Fedora is a Red Hat ecosystem OS — Podman is the native, first-class container runtime:
- Rootless by default (better security posture)
- No daemon (no single point of failure)
- OCI-compatible (same images as Docker)
- `podman-docker` provides drop-in compatibility (`/usr/bin/docker` → `podman`)
- Socket-compatible: set `DOCKER_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock`

### kind vs Minikube

**kind is recommended** for local Kubernetes development:
- Runs K8s nodes as containers (fast startup, ~< 1 min vs. 3–5 min for Minikube VM)
- Works with Podman: `export KIND_EXPERIMENTAL_PROVIDER=podman`
- Closer to real cluster behavior
- Better for CI simulation

Minikube is installed as an alternative for cases where you need a full VM-based cluster (PCIe passthrough testing, specific network topologies, etc.).

### cgroups v2

Fedora 44 uses **cgroups v2 exclusively**. All tools configured here are compatible:
- Podman: full cgroups v2 support since 3.0
- kind: cgroups v2 supported
- minikube: cgroups v2 supported with `--driver=kvm2` or `--driver=podman`

---

## 9. Virtualization

### KVM on Wayland/KDE

virt-manager on Fedora 44 with KDE Plasma 6:
- GTK3 with Wayland ozone backend — works natively
- VM display via Spice (high performance) or VNC — both Wayland compatible
- No XWayland required for the manager itself

### Nested Virtualization

Enabled by default for Intel and AMD CPUs. Verify:
```bash
cat /sys/module/kvm_intel/parameters/nested  # Intel: should print 1
cat /sys/module/kvm_amd/parameters/nested    # AMD: should print 1
```

Use case: Running Kubernetes clusters (kubeadm/kind) inside VMs.

---

## 10. Neovim

### Plugin Architecture

| Layer | Plugin |
|-------|--------|
| Plugin manager | `lazy.nvim` |
| LSP | `nvim-lspconfig` + `mason.nvim` |
| LSP installer | `mason-lspconfig.nvim` |
| Completion | `nvim-cmp` + `LuaSnip` |
| Fuzzy finder | `telescope.nvim` (requires `ripgrep` + `fd`) |
| File tree | `neo-tree.nvim` |
| Syntax | `nvim-treesitter` |
| Formatting | `conform.nvim` |
| Git | `gitsigns.nvim` + `vim-fugitive` |
| Terminal | `toggleterm.nvim` |
| Colorscheme | `catppuccin` |
| Status bar | `lualine.nvim` |
| Buffer tabs | `bufferline.nvim` |
| UI | `noice.nvim` |

### Clipboard on Wayland

`wl-clipboard` is installed. Neovim auto-detects it when `$WAYLAND_DISPLAY` is set. The `clipboard = "unnamedplus"` option syncs vim registers with the system clipboard.

---

## 11. Security Considerations

- **No root shell usage**: `install.sh` must be run as a normal user. Sudo is used only for specific operations (package install, service enable, file writes to /etc).
- **GPG key verification**: All third-party repos have GPG keys imported before use. Never add repos with `gpgcheck=0`.
- **Rootless containers**: Podman runs containers as your user UID. No Docker daemon running as root.
- **SOPS**: Installed for secret management in GitOps workflows. Use with `age` keys (also installed).
- **Dropbox**: The daemon is run as a user-level systemd service, not root.
- **JetBrains Toolbox**: Installed to `~/.local` (user space), not system-wide.
- **Polkit for libvirt**: Explicit polkit rule for the `libvirt` group — avoids overly broad sudo access.
- **Sudo keepalive**: The background sudo keepalive loop is killed via `trap EXIT` — it never persists after setup.

---

## 12. Post-Install Verification Checklist

```bash
# System
fedora-release --version          # Should show 44
uname -r                          # Kernel version
echo $WAYLAND_DISPLAY             # Should be set in Wayland session

# Shell
which zsh && zsh --version
echo $SHELL                       # Should be /usr/bin/zsh after re-login
starship --version

# Developer tools
git --version
gcc --version
rg --version                      # ripgrep
fd --version                      # fd-find
bat --version
eza --version
delta --version                   # git-delta
fzf --version
thefuck --version

# Containers
podman --version
podman run --rm hello-world       # Test rootless container
podman info | grep -A2 "store"    # Should show overlay driver
systemctl --user status podman.socket

# Kubernetes
kubectl version --client
helm version
kind version
minikube version
k9s version

# KVM
virt-host-validate                # Should all show PASS
virsh list --all                  # List VMs
ls -la /dev/kvm                   # Should be accessible

# Applications
brave-browser-nightly --version
flatpak list | grep spotify
nvim --version                    # Should be 0.10+

# Neovim
nvim +":Lazy health" +qa          # Check lazy.nvim health
nvim +":checkhealth" +qa          # Full health check

# Groups
groups                            # Should include: libvirt, kvm

# Clipboard (Wayland)
echo "test" | wl-copy && wl-paste # Should print "test"
```

---

## 13. Fedora-Specific Caveats

1. **DNF5**: Fedora 44 uses DNF5 as the default package manager. This setup auto-detects `dnf5` vs `dnf`. Most commands are backward-compatible but `dnf5 copr` output format differs slightly.

2. **SELinux**: Fedora runs SELinux in enforcing mode. Do **not** disable it. All configured services are compatible with SELinux enforcing. If you encounter AVC denials, use `audit2allow` or file a bug — don't set `SELINUX=permissive`.

3. **Wayland clipboard**: `xclip`/`xsel` require XWayland. On a native Wayland session, use `wl-copy`/`wl-paste`. Neovim handles this automatically via `wl-clipboard`.

4. **fd binary name**: On Fedora, `fd-find` installs the binary as `fd`. On Debian/Ubuntu it's `fdfind`. Scripts use `fd` directly.

5. **Cgroups v2**: Fedora 44 uses cgroups v2 exclusively. If an old tool requires cgroups v1, do not add `systemd.unified_cgroup_hierarchy=0` to the kernel cmdline — update the tool instead.

6. **KDE Plasma 6**: Uses Wayland-native KWin. XWayland is available for X11 apps. Most apps work natively. GTK3 apps (virt-manager) use the Wayland backend automatically.

7. **Pipewire**: Fedora 44 uses Pipewire for audio (replacing PulseAudio). All installed apps support Pipewire natively or via its PulseAudio compatibility layer.

8. **Flatpak permissions**: Spotify Flatpak has limited filesystem access by design. Use `flatpak override` or Flatseal if you need to expand permissions.

9. **Group membership**: Adding yourself to `libvirt`, `kvm`, `docker` groups requires a complete logout/login to take effect. `newgrp libvirt` works for the current session only.

10. **JetBrains Toolbox + Wayland**: Toolbox itself runs via XWayland. Individual JetBrains IDEs have Wayland support (enable via `_JAVA_AWT_WM_NONREPARENTING=1` in the IDE's `.vmoptions` or use the `--enable-native-access` JVM flag that newer IDEs use automatically).
