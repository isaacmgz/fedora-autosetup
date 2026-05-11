#!/usr/bin/env bash
# =============================================================================
# lib/helpers.sh — Shared utilities for all setup scripts
# =============================================================================
# Sourced by install.sh and all module scripts. Never executed directly.
# =============================================================================

# Guard against double-sourcing
[[ -n "${_HELPERS_LOADED:-}" ]] && return 0
_HELPERS_LOADED=1

# ── ANSI color codes ──────────────────────────────────────────────────────────
readonly CLR_RESET='\033[0m'
readonly CLR_RED='\033[0;31m'
readonly CLR_GREEN='\033[0;32m'
readonly CLR_YELLOW='\033[1;33m'
readonly CLR_BLUE='\033[0;34m'
readonly CLR_CYAN='\033[0;36m'
readonly CLR_BOLD='\033[1m'
readonly CLR_DIM='\033[2m'

# ── Logging primitives ────────────────────────────────────────────────────────

# Timestamp prefix for every log line
_ts() { date '+%H:%M:%S'; }

log_info() {
  echo -e "${CLR_BLUE}[$(_ts)] INFO${CLR_RESET}  $*"
}

log_success() {
  echo -e "${CLR_GREEN}[$(_ts)]  OK ${CLR_RESET}  $*"
}

log_warn() {
  echo -e "${CLR_YELLOW}[$(_ts)] WARN${CLR_RESET}  $*" >&2
}

log_error() {
  echo -e "${CLR_RED}[$(_ts)] ERR ${CLR_RESET}  $*" >&2
}

log_section() {
  echo ""
  echo -e "${CLR_BOLD}${CLR_CYAN}══════════════════════════════════════════════════${CLR_RESET}"
  echo -e "${CLR_BOLD}${CLR_CYAN}  $*${CLR_RESET}"
  echo -e "${CLR_BOLD}${CLR_CYAN}══════════════════════════════════════════════════${CLR_RESET}"
}

log_step() {
  echo -e "${CLR_BOLD}[$(_ts)] ───▶${CLR_RESET} $*"
}

log_dry() {
  echo -e "${CLR_DIM}[$(_ts)] DRY ${CLR_RESET}  [would run] $*"
}

log_skip() {
  echo -e "${CLR_DIM}[$(_ts)] SKIP${CLR_RESET}  $*"
}

# Fatal error — print message and exit
die() {
  log_error "$*"
  exit 1
}

# ── Banner ────────────────────────────────────────────────────────────────────
print_banner() {
  echo ""
  echo -e "${CLR_BOLD}${CLR_CYAN}"
  cat <<'BANNER'
  ███████╗███████╗██████╗  ██████╗ ██████╗  █████╗
  ██╔════╝██╔════╝██╔══██╗██╔═══██╗██╔══██╗██╔══██╗
  █████╗  █████╗  ██║  ██║██║   ██║██████╔╝███████║
  ██╔══╝  ██╔══╝  ██║  ██║██║   ██║██╔══██╗██╔══██║
  ██║     ███████╗██████╔╝╚██████╔╝██║  ██║██║  ██║
  ╚═╝     ╚══════╝╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝
  Workstation 44 · KDE Plasma 6 · Developer Setup
BANNER
  echo -e "${CLR_RESET}"
}

# ── Post-install summary ──────────────────────────────────────────────────────
print_summary() {
  echo ""
  log_section "Setup Complete"
  echo -e "${CLR_GREEN}"
  cat <<'EOF'
  ✔  System updated & hardened
  ✔  Developer tools installed
  ✔  Containers & Kubernetes tooling configured
  ✔  KVM/libvirt virtualization ready
  ✔  Desktop applications installed
  ✔  Zsh + Starship shell configured
  ✔  Neovim ready
EOF
  echo -e "${CLR_RESET}"
  log_warn "Log file saved to: ${LOG_FILE}"
  log_info "Recommended next steps:"
  echo "  1. Log out and back in (group memberships take effect)"
  echo "  2. Run: zsh   (or set as default shell: chsh -s \$(which zsh))"
  echo "  3. Open Neovim and let lazy.nvim finish installing plugins"
  echo "  4. Verify: podman run --rm hello-world"
  echo "  5. Verify: kubectl version --client"
  echo ""
}

# ── Prompting ─────────────────────────────────────────────────────────────────

# Usage: confirm "Do something?" [--default-yes]
# Returns 0 for yes, 1 for no
# Respects AUTO_YES global flag
confirm() {
  local prompt="$1"
  local default="${2:-}"

  if "${AUTO_YES:-false}"; then
    log_info "(--yes) Auto-confirming: ${prompt}"
    return 0
  fi

  local choices="[y/N]"
  [[ "${default}" == "--default-yes" ]] && choices="[Y/n]"

  echo -en "${CLR_YELLOW}${prompt} ${choices}: ${CLR_RESET}"
  read -r reply

  if [[ -z "${reply}" && "${default}" == "--default-yes" ]]; then
    return 0
  fi

  [[ "${reply,,}" == "y" || "${reply,,}" == "yes" ]]
}

# ── Command wrappers ──────────────────────────────────────────────────────────

# Run a command respecting --dry-run
# Usage: run_cmd [--as-root] COMMAND [ARGS...]
run_cmd() {
  local as_root=false
  if [[ "${1:-}" == "--as-root" ]]; then
    as_root=true
    shift
  fi

  local cmd_str="$*"
  [[ "${as_root}" == true ]] && cmd_str="sudo $*"

  if "${DRY_RUN:-false}"; then
    log_dry "${cmd_str}"
    return 0
  fi

  log_step "${cmd_str}"
  if "${as_root}"; then
    sudo "$@"
  else
    "$@"
  fi
}

# Run command as the real user even inside a sudo context
# Useful when a script is called with sudo and needs to write to $HOME
run_as_user() {
  local real_user="${SUDO_USER:-${USER}}"
  if [[ "${real_user}" == "root" ]]; then
    "$@"
  else
    sudo -u "${real_user}" "$@"
  fi
}

# ── Safe home directory resolution ───────────────────────────────────────────
# When running sudo, $HOME might be /root — this always returns the real user's home
real_home() {
  local real_user="${SUDO_USER:-${USER}}"
  getent passwd "${real_user}" | cut -d: -f6
}

# ── Package helpers (thin wrappers — see lib/pkg.sh for full logic) ───────────

# Check if a binary is on PATH
has_cmd() {
  command -v "$1" &>/dev/null
}

# Check if a systemd service is active
service_active() {
  systemctl is-active --quiet "$1" 2>/dev/null
}

# Check if a systemd service is enabled
service_enabled() {
  systemctl is-enabled --quiet "$1" 2>/dev/null
}

# Check if a user is in a group
user_in_group() {
  local user="${SUDO_USER:-${USER}}"
  groups "${user}" | grep -qw "$1"
}
