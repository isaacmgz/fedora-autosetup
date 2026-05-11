#!/usr/bin/env bash
# =============================================================================
# scripts/system/01-system-update.sh — Full system update with reboot handling
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

# Source helpers (path relative to repo root, exported by install.sh)
# shellcheck source=../../lib/helpers.sh
source "${LIB_DIR}/helpers.sh"
# shellcheck source=../../lib/pkg.sh
source "${LIB_DIR}/pkg.sh"

log_section "System Update"

# ── Step 1: Refresh metadata ──────────────────────────────────────────────────
log_step "Refreshing DNF metadata"
run_cmd --as-root "${DNF_CMD}" makecache

# ── Step 2: Upgrade all packages ─────────────────────────────────────────────
log_step "Upgrading system packages (this may take a while)"
if ! "${DRY_RUN}"; then
  # Use --best to catch dependency issues early; --allowerasing for conflicts
  sudo "${DNF_CMD}" upgrade -y --best --allowerasing
else
  log_dry "sudo ${DNF_CMD} upgrade -y --best --allowerasing"
fi

log_success "System upgrade complete"

# ── Step 3: RPM Fusion (Free + Nonfree) ──────────────────────────────────────
# RPM Fusion is required for: ffmpeg, VLC, NVIDIA drivers, and some multimedia.
# Enabling it here (not in repos script) so it's available for the firmware update.
log_step "Enabling RPM Fusion repositories"

FEDORA_VER="${FEDORA_VERSION:-44}"

RPM_FUSION_FREE="https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm"
RPM_FUSION_NONFREE="https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm"

if ! rpm_installed rpmfusion-free-release; then
  run_cmd --as-root "${DNF_CMD}" install -y "${RPM_FUSION_FREE}"
else
  log_skip "rpmfusion-free-release (already installed)"
fi

if ! rpm_installed rpmfusion-nonfree-release; then
  run_cmd --as-root "${DNF_CMD}" install -y "${RPM_FUSION_NONFREE}"
else
  log_skip "rpmfusion-nonfree-release (already installed)"
fi

# ── Step 4: Firmware updates via fwupd ───────────────────────────────────────
# fwupd is Fedora's standard firmware update mechanism.
# Safe to run; it will no-op if no updates are available.
if has_cmd fwupdmgr; then
  log_step "Checking firmware updates"
  if ! "${DRY_RUN}"; then
    # Refresh metadata; ignore exit code 1 (no updates) and 2 (nothing to do)
    sudo fwupdmgr refresh --force || true
    sudo fwupdmgr get-updates || true
    # Don't auto-apply firmware updates — user should do this manually
    log_warn "Firmware updates listed above. Apply manually with: sudo fwupdmgr update"
  else
    log_dry "fwupdmgr refresh && fwupdmgr get-updates"
  fi
else
  log_warn "fwupdmgr not found — skipping firmware check"
fi

# ── Step 5: Reboot prompt ─────────────────────────────────────────────────────
# A reboot is strongly recommended after a full system upgrade, especially if
# the kernel or glibc was updated.
if "${SKIP_REBOOT}"; then
  log_warn "--skip-reboot set. Skipping reboot prompt. Some updates may not take effect."
  log_warn "Remember to reboot before continuing the setup in a new session."
else
  echo ""
  log_warn "A reboot is STRONGLY recommended after a full system upgrade."
  log_warn "Kernel, glibc, or other critical packages may have been updated."
  echo ""
  log_info "After rebooting, re-run install.sh with --skip-reboot to skip this step:"
  echo "    ./install.sh --skip-reboot"
  echo ""

  if confirm "Reboot now?" --default-yes; then
    log_info "Rebooting in 5 seconds... (Ctrl+C to cancel)"
    sleep 5
    sudo systemctl reboot
    exit 0
  else
    log_warn "Reboot skipped. Continuing — some behaviour may be unpredictable."
  fi
fi
