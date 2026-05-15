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
# brave-browser-nightly is the correct package name in the nightly repo.
# The repo and GPG key are configured in scripts/system/02-repos.sh.
# Do NOT use the curl-pipe-sh installer — it is not idempotent and adds its
# own conflicting repo.
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
    DROPBOX_SERVICE_DIR="${REAL_HOME}/.config/systemd/user"
    sudo -u "${REAL_USER}" mkdir -p "${DROPBOX_SERVICE_DIR}"
    sudo -u "${REAL_USER}" tee "${DROPBOX_SERVICE_DIR}/dropbox.service" > /dev/null <<'EOF'
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
# 4. JetBrains Toolbox — manual installation (removed from automation)
# =============================================================================
log_step "JetBrains Toolbox — manual installation required"
log_warn "JetBrains Toolbox is intentionally not automated."
log_info "Install manually after setup:"
echo "  1. Download from: https://www.jetbrains.com/toolbox-app/"
echo "  2. Extract: tar -xzf jetbrains-toolbox-*.tar.gz"
echo "  3. Run:     ./jetbrains-toolbox-*/jetbrains-toolbox"
echo "     (Toolbox installs to ~/.local/share/JetBrains/Toolbox automatically)"
echo ""
log_info "Wayland note: enable native Wayland per IDE via:"
echo "     Help → Edit Custom VM Options → add: -Dawt.toolkit.name=WLToolkit"

# =============================================================================
# 5. Lotion — Unofficial Notion desktop app for Linux
# =============================================================================
# Source:  https://github.com/puneetsl/lotion
# Release: v1.5.0 (2025-10-27) — Electron-based, actively maintained.
#
# Install method: direct RPM download from GitHub releases.
# There is no DNF repo and no upstream GPG signing key published.
# The RPM must be installed with --nogpgcheck for a local file install.
# Integrity is verified via SHA256 checksum against the published value.
#
# Updates are MANUAL: check https://github.com/puneetsl/lotion/releases
# and re-run this module when a new version is published.
#
# Wayland note: Lotion is Electron-based. Electron supports Wayland natively
# via the --ozone-platform=wayland flag. The desktop entry written below
# enables this automatically for KDE Plasma 6 / Wayland sessions.
# =============================================================================
log_section "Lotion (Unofficial Notion Desktop App)"

LOTION_VERSION="1.5.0"
LOTION_RPM="lotion-${LOTION_VERSION}-1.x86_64.rpm"
LOTION_URL="https://github.com/puneetsl/lotion/releases/download/v${LOTION_VERSION}/${LOTION_RPM}"
LOTION_SHA256="e18b35803c8da9c22dec523cc17e001abce1f568a51283790d267bbf50ec4720"
LOTION_TMP="/tmp/${LOTION_RPM}"

# Check if already installed (rpm -q uses the package name without version)
if rpm_installed lotion; then
  INSTALLED_VER="$(rpm -q lotion --qf '%{VERSION}' 2>/dev/null)"
  if [[ "${INSTALLED_VER}" == "${LOTION_VERSION}" ]]; then
    log_skip "Lotion ${LOTION_VERSION} (already installed)"
  else
    log_warn "Lotion ${INSTALLED_VER} installed, expected ${LOTION_VERSION}"
    log_warn "To upgrade: re-run this module after updating LOTION_VERSION in the script"
  fi
else
  if ! "${DRY_RUN}"; then
    log_step "Downloading Lotion ${LOTION_VERSION} RPM"
    curl -fsSL "${LOTION_URL}" -o "${LOTION_TMP}"

    # Verify SHA256 checksum against the value published on the GitHub release page
    log_step "Verifying SHA256 checksum"
    ACTUAL_SHA256="$(sha256sum "${LOTION_TMP}" | cut -d' ' -f1)"
    if [[ "${ACTUAL_SHA256}" != "${LOTION_SHA256}" ]]; then
      rm -f "${LOTION_TMP}"
      die "SHA256 mismatch for ${LOTION_RPM}
  Expected: ${LOTION_SHA256}
  Got:      ${ACTUAL_SHA256}
Aborting install. Do not proceed with a corrupted package."
    fi
    log_success "Checksum verified"

    # Install the local RPM. --nogpgcheck is required because lotion does not
    # publish a GPG signing key — SHA256 verification above is the integrity check.
    log_step "Installing Lotion RPM"
    sudo "${DNF_CMD}" install -y --nogpgcheck "${LOTION_TMP}"
    rm -f "${LOTION_TMP}"
    log_success "Lotion ${LOTION_VERSION} installed"

    # Patch the desktop entry to enable native Wayland via Ozone.
    # Without this, Electron falls back to XWayland on a Wayland session,
    # which causes blurry rendering on HiDPI and broken clipboard behaviour.
    LOTION_DESKTOP="/usr/share/applications/lotion.desktop"
    if [[ -f "${LOTION_DESKTOP}" ]]; then
      log_step "Patching Lotion desktop entry for Wayland (Ozone)"
      # Add --ozone-platform=wayland --enable-features=WaylandWindowDecorations
      # to the Exec line if not already present
      if ! grep -q "ozone-platform" "${LOTION_DESKTOP}"; then
        sudo sed -i \
          's|^Exec=lotion\b|Exec=lotion --ozone-platform=wayland --enable-features=WaylandWindowDecorations|' \
          "${LOTION_DESKTOP}"
        log_success "Wayland Ozone flags added to desktop entry"
      else
        log_skip "Wayland flags already present in desktop entry"
      fi
    else
      log_warn "Desktop entry not found at ${LOTION_DESKTOP} — skipping Wayland patch"
      log_warn "If Lotion installs its .desktop file elsewhere, add manually:"
      log_warn "  --ozone-platform=wayland --enable-features=WaylandWindowDecorations"
    fi

  else
    log_dry "Would download and verify Lotion ${LOTION_VERSION} RPM from GitHub releases"
    log_dry "Would install with: sudo ${DNF_CMD} install --nogpgcheck ${LOTION_TMP}"
    log_dry "Would patch desktop entry for Wayland Ozone"
  fi
fi

log_warn "Lotion updates are MANUAL — no DNF repo exists."
log_warn "Check for new releases at: https://github.com/puneetsl/lotion/releases"
log_warn "To update: change LOTION_VERSION in this script and re-run with --only apps"

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
