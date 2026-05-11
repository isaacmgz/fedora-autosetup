#!/usr/bin/env bash
# =============================================================================
# lib/pkg.sh — Idempotent package management helpers for Fedora/DNF5
# =============================================================================
# Fedora 44 ships DNF5 as the default package manager.
# DNF5 is faster and has a slightly different CLI in some edge cases,
# but remains backward-compatible with DNF4 syntax for most operations.
# =============================================================================
[[ -n "${_PKG_LOADED:-}" ]] && return 0
_PKG_LOADED=1

# ── Detect DNF version ────────────────────────────────────────────────────────
_detect_dnf() {
  if has_cmd dnf5; then
    echo "dnf5"
  elif has_cmd dnf; then
    echo "dnf"
  else
    die "Neither dnf5 nor dnf found — is this really Fedora?"
  fi
}

DNF_CMD="$(_detect_dnf)"
export DNF_CMD

# Base DNF flags for non-interactive use
DNF_FLAGS=(-y --setopt=install_weak_deps=False)

# ── Check if an RPM package is installed ─────────────────────────────────────
rpm_installed() {
  rpm -q "$1" &>/dev/null
}

# ── Install packages idempotently ─────────────────────────────────────────────
# Usage: dnf_install pkg1 pkg2 ...
# Skips already-installed packages. Never fails on "already installed".
dnf_install() {
  local to_install=()

  for pkg in "$@"; do
    if rpm_installed "${pkg}"; then
      log_skip "${pkg} (already installed)"
    else
      to_install+=("${pkg}")
    fi
  done

  if [[ ${#to_install[@]} -eq 0 ]]; then
    log_success "All packages already installed"
    return 0
  fi

  log_step "Installing: ${to_install[*]}"
  if "${DRY_RUN:-false}"; then
    log_dry "sudo ${DNF_CMD} install ${DNF_FLAGS[*]} ${to_install[*]}"
    return 0
  fi

  sudo "${DNF_CMD}" install "${DNF_FLAGS[@]}" "${to_install[@]}"
}

# ── Remove packages ───────────────────────────────────────────────────────────
dnf_remove() {
  local to_remove=()

  for pkg in "$@"; do
    if rpm_installed "${pkg}"; then
      to_remove+=("${pkg}")
    else
      log_skip "Not installed (nothing to remove): ${pkg}"
    fi
  done

  [[ ${#to_remove[@]} -eq 0 ]] && return 0

  log_step "Removing: ${to_remove[*]}"
  if "${DRY_RUN:-false}"; then
    log_dry "sudo ${DNF_CMD} remove ${DNF_FLAGS[*]} ${to_remove[*]}"
    return 0
  fi

  sudo "${DNF_CMD}" remove "${DNF_FLAGS[@]}" "${to_remove[@]}"
}

# ── Enable a DNF/COPR repository ─────────────────────────────────────────────
dnf_copr_enable() {
  local repo="$1"
  local repo_id
  # Normalize "user/repo" to "copr:copr.fedorainfracloud.org:user:repo"
  repo_id="$(echo "${repo}" | tr '/' ':')"

  if sudo "${DNF_CMD}" copr list --enabled 2>/dev/null | grep -q "${repo_id}"; then
    log_skip "COPR ${repo} (already enabled)"
    return 0
  fi

  log_step "Enabling COPR: ${repo}"
  if "${DRY_RUN:-false}"; then
    log_dry "sudo ${DNF_CMD} copr enable -y ${repo}"
    return 0
  fi

  sudo "${DNF_CMD}" copr enable -y "${repo}"
}

# ── Add an external .repo file ────────────────────────────────────────────────
add_repo_file() {
  local name="$1"
  local url="$2"
  local dest="/etc/yum.repos.d/${name}.repo"

  if [[ -f "${dest}" ]]; then
    log_skip "Repo file ${dest} (already exists)"
    return 0
  fi

  log_step "Adding repo: ${name} → ${dest}"
  if "${DRY_RUN:-false}"; then
    log_dry "curl -fsSL ${url} | sudo tee ${dest}"
    return 0
  fi

  curl -fsSL "${url}" | sudo tee "${dest}" > /dev/null
}

# ── Add RPM key ───────────────────────────────────────────────────────────────
import_rpm_key() {
  local url="$1"
  log_step "Importing RPM key: ${url}"
  if "${DRY_RUN:-false}"; then
    log_dry "sudo rpm --import ${url}"
    return 0
  fi
  sudo rpm --import "${url}"
}

# ── Flatpak install (idempotent) ──────────────────────────────────────────────
flatpak_install() {
  local remote="${1}"
  local app_id="${2}"

  if flatpak list --app --columns=application 2>/dev/null | grep -q "^${app_id}$"; then
    log_skip "Flatpak ${app_id} (already installed)"
    return 0
  fi

  log_step "Installing Flatpak: ${app_id} from ${remote}"
  if "${DRY_RUN:-false}"; then
    log_dry "flatpak install -y ${remote} ${app_id}"
    return 0
  fi

  flatpak install -y "${remote}" "${app_id}"
}

# ── Enable Flathub if not already configured ─────────────────────────────────
ensure_flathub() {
  if flatpak remotes 2>/dev/null | grep -q "^flathub"; then
    log_skip "Flathub remote (already configured)"
    return 0
  fi

  log_step "Adding Flathub remote"
  if "${DRY_RUN:-false}"; then
    log_dry "flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo"
    return 0
  fi

  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
}

# ── Cargo install (idempotent) ────────────────────────────────────────────────
cargo_install() {
  local crate="$1"
  local bin="${2:-${crate}}"  # binary name if different from crate

  if has_cmd "${bin}"; then
    log_skip "cargo crate ${crate} (binary '${bin}' already on PATH)"
    return 0
  fi

  log_step "cargo install ${crate}"
  if "${DRY_RUN:-false}"; then
    log_dry "cargo install ${crate}"
    return 0
  fi

  cargo install "${crate}"
}

# ── pip install (into user space, idempotent) ────────────────────────────────
pip_install() {
  local package="$1"
  local bin="${2:-${package}}"

  if has_cmd "${bin}" || pip3 show "${package}" &>/dev/null; then
    log_skip "pip package ${package} (already installed)"
    return 0
  fi

  log_step "pip install --user ${package}"
  if "${DRY_RUN:-false}"; then
    log_dry "pip install --user ${package}"
    return 0
  fi

  pip install --user "${package}"
}

# ── Enable and start a systemd service (idempotent) ──────────────────────────
systemd_enable_start() {
  local service="$1"
  local scope="${2:-system}"  # "system" or "user"

  local systemctl_args=()
  [[ "${scope}" == "user" ]] && systemctl_args+=("--user")

  if service_enabled "${service}" && service_active "${service}"; then
    log_skip "Service ${service} (already enabled and active)"
    return 0
  fi

  log_step "Enabling and starting: ${service}"
  if "${DRY_RUN:-false}"; then
    log_dry "systemctl ${systemctl_args[*]} enable --now ${service}"
    return 0
  fi

  if [[ "${scope}" == "user" ]]; then
    systemctl --user enable --now "${service}"
  else
    sudo systemctl enable --now "${service}"
  fi
}

# ── Add user to group (idempotent) ────────────────────────────────────────────
add_user_to_group() {
  local group="$1"
  local target_user="${SUDO_USER:-${USER}}"

  if user_in_group "${group}"; then
    log_skip "User ${target_user} already in group ${group}"
    return 0
  fi

  log_step "Adding ${target_user} to group: ${group}"
  if "${DRY_RUN:-false}"; then
    log_dry "sudo usermod -aG ${group} ${target_user}"
    return 0
  fi

  sudo usermod -aG "${group}" "${target_user}"
  log_warn "Group ${group} added — log out and back in for it to take effect"
}

# ── Download a binary to /usr/local/bin (idempotent by version check) ─────────
install_binary() {
  local name="$1"
  local url="$2"
  local dest="/usr/local/bin/${name}"

  if [[ -f "${dest}" ]]; then
    log_skip "Binary ${name} (already at ${dest})"
    return 0
  fi

  log_step "Installing binary: ${name}"
  if "${DRY_RUN:-false}"; then
    log_dry "curl -fsSL ${url} → ${dest}"
    return 0
  fi

  curl -fsSL "${url}" -o "/tmp/${name}"
  chmod +x "/tmp/${name}"
  sudo mv "/tmp/${name}" "${dest}"
}
