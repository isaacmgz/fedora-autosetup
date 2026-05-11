#!/usr/bin/env bash
# =============================================================================
# lib/checks.sh — Pre-flight and environment validation functions
# =============================================================================
[[ -n "${_CHECKS_LOADED:-}" ]] && return 0
_CHECKS_LOADED=1

# ── Must not be run as root ───────────────────────────────────────────────────
check_not_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    die "Do NOT run install.sh as root. Run as your normal user — sudo will be called internally where needed."
  fi
  log_success "Running as non-root user: ${USER}"
}

# ── Fedora version gate ───────────────────────────────────────────────────────
check_fedora_version() {
  if [[ ! -f /etc/os-release ]]; then
    die "/etc/os-release not found — is this a Fedora system?"
  fi

  # shellcheck source=/dev/null
  source /etc/os-release

  if [[ "${ID}" != "fedora" ]]; then
    die "This setup targets Fedora. Detected: ${ID} ${VERSION_ID:-}"
  fi

  local ver="${VERSION_ID:-0}"
  if [[ "${ver}" -lt 44 ]]; then
    die "Fedora 44+ required. Detected: Fedora ${ver}"
  fi

  if [[ "${ver}" -gt 44 ]]; then
    log_warn "Running on Fedora ${ver} (> 44). Package names may have changed — proceed with caution."
    confirm "Continue on Fedora ${ver}?" || die "Aborted by user."
  fi

  log_success "Fedora ${ver} detected"
  export FEDORA_VERSION="${ver}"
}

# ── KDE Plasma 6 check ────────────────────────────────────────────────────────
check_kde_plasma() {
  local desktop="${XDG_CURRENT_DESKTOP:-}"
  if [[ "${desktop}" != *"KDE"* ]]; then
    log_warn "KDE Plasma not detected as current desktop (XDG_CURRENT_DESKTOP='${desktop}')"
    log_warn "Some KDE-specific configurations will still be applied but may not take effect"
    confirm "Continue anyway?" || die "Aborted by user."
    return 0
  fi

  # Verify Plasma 6 (plasmashell --version returns "plasmashell 6.x.x")
  if has_cmd plasmashell; then
    local plasma_ver
    plasma_ver="$(plasmashell --version 2>/dev/null | grep -oP '\d+' | head -1)"
    if [[ "${plasma_ver:-0}" -lt 6 ]]; then
      log_warn "Plasma ${plasma_ver} detected — this setup targets Plasma 6"
    else
      log_success "KDE Plasma ${plasma_ver} detected"
    fi
  fi
}

# ── Wayland session check ─────────────────────────────────────────────────────
check_wayland() {
  local session_type="${XDG_SESSION_TYPE:-}"
  if [[ "${session_type}" != "wayland" ]]; then
    log_warn "Not running a Wayland session (XDG_SESSION_TYPE='${session_type}')"
    log_warn "Wayland-specific configurations are still applied for future sessions"
    return 0
  fi
  log_success "Wayland session confirmed"
}

# ── Internet connectivity ─────────────────────────────────────────────────────
check_internet() {
  log_step "Checking internet connectivity..."
  local test_hosts=("1.1.1.1" "8.8.8.8" "9.9.9.9")
  local ok=false

  for host in "${test_hosts[@]}"; do
    if ping -c 1 -W 3 "${host}" &>/dev/null; then
      ok=true
      break
    fi
  done

  if ! "${ok}"; then
    die "No internet connectivity. Please check your network connection."
  fi

  # Also verify DNS works (common issue on corporate networks)
  if ! getent hosts fedoraproject.org &>/dev/null; then
    log_warn "DNS resolution may be impaired (fedoraproject.org unresolvable)"
    confirm "Continue anyway?" || die "Aborted."
  fi

  log_success "Internet connectivity OK"
}

# ── Sudo access ───────────────────────────────────────────────────────────────
check_sudo_access() {
  log_step "Verifying sudo access..."
  if ! sudo -v; then
    die "sudo access required. Please ensure your user is in the wheel group."
  fi

  # Refresh sudo timestamp to avoid mid-run prompts on long operations
  # We'll keep it alive via a background loop only during the setup
  (while true; do sudo -v; sleep 55; done) &
  SUDO_KEEPALIVE_PID=$!
  export SUDO_KEEPALIVE_PID
  # Register cleanup to kill the keepalive on exit
  trap 'kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true' EXIT

  log_success "Sudo access verified"
}

# ── Disk space ────────────────────────────────────────────────────────────────
check_disk_space() {
  local required_gb=10
  local available_gb
  # df returns KB, convert to GB
  available_gb=$(df --output=avail -BG / | tail -1 | tr -d 'G ')

  if [[ "${available_gb}" -lt "${required_gb}" ]]; then
    log_warn "Low disk space: ${available_gb}GB available, ${required_gb}GB recommended"
    confirm "Continue with limited disk space?" || die "Aborted."
  else
    log_success "Disk space OK: ${available_gb}GB available"
  fi
}

# ── Virtualization support ────────────────────────────────────────────────────
check_virt_support() {
  if ! grep -qE '(vmx|svm)' /proc/cpuinfo; then
    log_warn "Hardware virtualization (VT-x/AMD-V) not detected in /proc/cpuinfo"
    log_warn "KVM will not function. Ensure VT-x/AMD-V is enabled in BIOS."
    return 1
  fi
  log_success "Hardware virtualization support detected"
  return 0
}
