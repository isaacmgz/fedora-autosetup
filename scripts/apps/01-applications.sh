#!/usr/bin/env bash
# =============================================================================
# scripts/apps/01-applications.sh — Desktop application installation
# =============================================================================
#
# APPLICATION ANALYSIS:
#
# 1. BRAVE NIGHTLY — Official RPM repo (configured in 02-repos.sh). Best method.
#
# 2. DROPBOX:
#    nautilus-dropbox conflicts with KDE — it installs GNOME file manager extensions.
#    On KDE the correct approach is the official Dropbox headless daemon + a
#    systray indicator. Options:
#    a) headless Dropbox daemon (dropbox.py from official installer) — works everywhere
#    b) dropbox RPM from Dropbox's repo — installs CLI and daemon, no GNOME deps
#    c) Flatpak — sandboxed, limited filesystem access by design (bad for Dropbox)
#    RECOMMENDATION: Use the official Dropbox RPM + systemd user service.
#    The RPM from dropbox.com is available for Fedora and is KDE-compatible.
#
# 3. SPOTIFY:
#    - RPM Fusion has historically included Spotify but it's unreliable.
#    - Flatpak from Flathub is the CANONICAL and most reliable method.
#    - The Flatpak version receives faster updates and is sandbox-contained.
#    - Works perfectly on KDE Wayland.
#    VERDICT: Flatpak from Flathub. No COPR, no sketchy repos.
#
# 4. JETBRAINS TOOLBOX:
#    - No official RPM repo. JetBrains provides a .tar.gz binary.
#    - Toolbox installs to ~/.local/share/JetBrains/Toolbox
#    - Creates systemd user service and desktop integration automatically.
#    - This is the correct method — do not use unofficial COPRs.
#
# 5. LOTION (Notion for Linux):
#    - Lotion is UNMAINTAINED (last commit ~2019). DO NOT USE.
#    - It was an unofficial wrapper around Notion's web app.
#    - Better alternatives in 2024+:
#      a) notion-app-enhanced (Flatpak via Flathub) — maintained community wrapper
#      b) Notion web app in Brave — works perfectly, no wrapper needed
#      c) notionify (COPR) — another wrapper, less popular
#    RECOMMENDATION: Use Notion as a PWA in Brave Browser (site settings →
#    "Install as app"). This gives a native-feeling app without maintenance risk.
#    We install the Flatpak as an optional alternative.
#
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

source "${LIB_DIR}/helpers.sh"
source "${LIB_DIR}/pkg.sh"

log_section "Desktop Applications"

REAL_USER="${SUDO_USER:-${USER}}"
REAL_HOME="$(real_home)"

# =============================================================================
# 1. Brave Browser Nightly
# =============================================================================
log_step "Installing Brave Browser Nightly"
dnf_install brave-browser-nightly

# =============================================================================
# 2. Dropbox (KDE-compatible approach)
# =============================================================================
log_step "Installing Dropbox (KDE-compatible daemon method)"

# We use the official Dropbox RPM which provides the daemon without GNOME deps.
# The RPM adds the Dropbox repository itself.
DROPBOX_REPO="/etc/yum.repos.d/dropbox.repo"

if ! rpm_installed dropbox; then
  if ! "${DRY_RUN}"; then
    # Import Dropbox GPG key
    sudo rpm --import "https://linux.dropbox.com/fedora/rpm-public-key.asc" || \
      log_warn "Dropbox GPG key import failed — verify manually"

    # Add Dropbox repo
    sudo tee "${DROPBOX_REPO}" > /dev/null <<'EOF'
[Dropbox]
name=Dropbox Repository
baseurl=https://linux.dropbox.com/fedora/$releasever/
gpgkey=https://linux.dropbox.com/fedora/rpm-public-key.asc
enabled=1
gpgcheck=1
EOF

    sudo "${DNF_CMD}" makecache
    # 'dropbox' package provides daemon + CLI, no GNOME dependencies
    sudo "${DNF_CMD}" install -y dropbox || {
      log_warn "Dropbox RPM install failed — this sometimes happens on new Fedora releases"
      log_warn "Alternative: Download the .tar.gz from https://www.dropbox.com/install-linux"
      log_warn "Then run: ~/.dropbox-dist/dropboxd"
    }

    # Create systemd user service for Dropbox daemon
    local service_dir="${REAL_HOME}/.config/systemd/user"
    sudo -u "${REAL_USER}" mkdir -p "${service_dir}"
    sudo -u "${REAL_USER}" tee "${service_dir}/dropbox.service" > /dev/null <<'EOF'
[Unit]
Description=Dropbox Daemon
After=network-online.target

[Service]
ExecStart=/usr/bin/dropbox start -i
ExecStop=/usr/bin/dropbox stop
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
    sudo -u "${REAL_USER}" systemctl --user daemon-reload
    sudo -u "${REAL_USER}" systemctl --user enable dropbox.service || true
    log_success "Dropbox installed and systemd user service configured"
  else
    log_dry "Would install Dropbox RPM and configure systemd user service"
  fi
else
  log_skip "Dropbox (already installed)"
fi

# ── KDE systray note ──────────────────────────────────────────────────────────
log_info "Dropbox uses native systray. On KDE Plasma 6, it should appear in the system tray automatically."
log_info "Run 'dropbox start' to initialize and link your account."

# =============================================================================
# 3. Spotify (Flatpak from Flathub — RECOMMENDED)
# =============================================================================
log_step "Installing Spotify via Flatpak (Flathub)"

# Rationale: Flathub Spotify is the most reliable method:
#   - Maintained by Spotify and the Flatpak community
#   - Works on all distros including Fedora 44
#   - Proper Wayland support (runs via XWayland, Spotify doesn't natively use Wayland)
#   - Sandboxed (good security posture)
#   - Avoids RPM Fusion's older Spotify packages

flatpak_install flathub com.spotify.Client

# ── Pipewire/audio note ────────────────────────────────────────────────────────
log_info "Spotify Flatpak uses Pipewire (via PulseAudio compatibility layer) on Fedora."
log_info "Audio should work out of the box with KDE/Pipewire."

# =============================================================================
# 4. JetBrains Toolbox
# =============================================================================
log_step "Installing JetBrains Toolbox"

TOOLBOX_INSTALL_DIR="${REAL_HOME}/.local/share/JetBrains/Toolbox"
TOOLBOX_BIN="${TOOLBOX_INSTALL_DIR}/bin/jetbrains-toolbox"

if [[ -f "${TOOLBOX_BIN}" ]]; then
  log_skip "JetBrains Toolbox (already installed at ${TOOLBOX_BIN})"
else
  if ! "${DRY_RUN}"; then
    log_step "Fetching latest JetBrains Toolbox release"

    # Fetch latest download URL from JetBrains data API
    TOOLBOX_URL=$(curl -fsSL 'https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release' \
      | python3 -c "
import sys, json
data = json.load(sys.stdin)
releases = data.get('TBA', [])
if releases:
    for asset in releases[0].get('downloads', {}).values():
        if 'linux' in asset.get('link', '').lower():
            print(asset['link'])
            break
" 2>/dev/null)

    if [[ -z "${TOOLBOX_URL}" ]]; then
      log_warn "Could not auto-detect Toolbox URL. Using known stable URL."
      TOOLBOX_URL="https://download.jetbrains.com/toolbox/jetbrains-toolbox-2.5.4.35118.tar.gz"
    fi

    log_step "Downloading JetBrains Toolbox from: ${TOOLBOX_URL}"
    curl -fsSL "${TOOLBOX_URL}" -o /tmp/jetbrains-toolbox.tar.gz

    # Extract to temp dir
    TOOLBOX_TMP=$(mktemp -d)
    tar -xzf /tmp/jetbrains-toolbox.tar.gz -C "${TOOLBOX_TMP}" --strip-components=1

    # Run as the real user — Toolbox installs to ~/.local
    sudo -u "${REAL_USER}" bash -c "
      export HOME='${REAL_HOME}'
      '${TOOLBOX_TMP}/jetbrains-toolbox' --install
    " || {
      # Fallback: manual install
      sudo -u "${REAL_USER}" mkdir -p "${TOOLBOX_INSTALL_DIR}/bin"
      cp "${TOOLBOX_TMP}/jetbrains-toolbox" "${TOOLBOX_BIN}"
      chmod +x "${TOOLBOX_BIN}"
    }

    rm -rf "${TOOLBOX_TMP}" /tmp/jetbrains-toolbox.tar.gz
    log_success "JetBrains Toolbox installed"
    log_info "Launch: ${TOOLBOX_BIN}"
    log_info "Toolbox will set up desktop integration and auto-update on first launch"
  else
    log_dry "Would download and install JetBrains Toolbox to ${TOOLBOX_INSTALL_DIR}"
  fi
fi

# =============================================================================
# 5. Notion — LOTION DEPRECATED, using PWA recommendation
# =============================================================================
log_section "Notion / Lotion"

log_warn "IMPORTANT: Lotion is UNMAINTAINED since ~2019. Do NOT use it."
log_warn "Lotion is based on an outdated Electron wrapper that is no longer maintained."
echo ""
log_info "Recommended Notion approaches for Fedora 44 / KDE:"
echo "  1. [BEST]   Use Notion as a Progressive Web App in Brave Browser:"
echo "                - Open notion.so in Brave"
echo "                - Menu → More tools → 'Install Notion as app'"
echo "                - Creates a desktop entry with app-like experience"
echo ""
echo "  2. [GOOD]   Flatpak community wrapper (notion-app-enhanced):"
echo "                flatpak install flathub notion.id.Notion"
echo ""

if confirm "Install Notion Flatpak (community wrapper)?" ; then
  if ! "${DRY_RUN}"; then
    # notion-app-enhanced is the maintained community wrapper on Flathub
    flatpak install -y flathub notion.id.Notion 2>/dev/null || \
    flatpak install -y flathub io.github.davidlj95.notion-app 2>/dev/null || {
      log_warn "Notion Flatpak not found under known app IDs."
      log_warn "Check https://flathub.org/apps/search?q=notion for current app ID"
      log_warn "Fallback: Use Notion as a PWA in Brave (recommended)"
    }
  else
    log_dry "flatpak install flathub notion.id.Notion"
  fi
else
  log_info "Skipping Notion Flatpak. Use as PWA in Brave Browser (recommended)"
fi

# =============================================================================
# 6. Additional KDE applications
# =============================================================================
log_step "Installing KDE utility applications"

dnf_install \
  ark \
  dolphin \
  okular \
  spectacle \
  gwenview \
  kcalc \
  krdc

log_success "Desktop applications installation complete"
