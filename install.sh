#!/usr/bin/env bash
# =============================================================================
# Fedora Workstation 44 — Developer Setup Orchestrator
# =============================================================================
# Author  : Senior DevOps Engineer
# Target  : Fedora 44 / KDE Plasma 6 / Wayland
# Usage   : ./install.sh [--dry-run] [--yes] [--skip-reboot] [--only <module>]
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

# ── Resolve script root (works even when sourced via symlink) ─────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
LOGS_DIR="${SCRIPT_DIR}/logs"
CONFIGS_DIR="${SCRIPT_DIR}/configs"

# ── Bootstrap: load helpers before anything else ─────────────────────────────
# shellcheck source=lib/helpers.sh
source "${LIB_DIR}/helpers.sh"
# shellcheck source=lib/checks.sh
source "${LIB_DIR}/checks.sh"
# shellcheck source=lib/pkg.sh
source "${LIB_DIR}/pkg.sh"

# ── Global flags (mutated by parse_args) ─────────────────────────────────────
DRY_RUN=false
AUTO_YES=false
SKIP_REBOOT=false
ONLY_MODULE=""

# ── Log file for this run ─────────────────────────────────────────────────────
mkdir -p "${LOGS_DIR}"
LOG_FILE="${LOGS_DIR}/setup-$(date +%Y%m%d-%H%M%S).log"
# Tee all output to log file
exec > >(tee -a "${LOG_FILE}") 2>&1

# =============================================================================
# Argument parsing
# =============================================================================
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)    DRY_RUN=true   ;;
      --yes|-y)     AUTO_YES=true  ;;
      --skip-reboot) SKIP_REBOOT=true ;;
      --only)
        shift
        ONLY_MODULE="${1:-}"
        [[ -z "${ONLY_MODULE}" ]] && die "--only requires a module name"
        ;;
      --help|-h)    usage; exit 0  ;;
      *) die "Unknown argument: $1" ;;
    esac
    shift
  done
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

OPTIONS:
  --dry-run         Print actions without executing them
  --yes             Skip interactive confirmation prompts
  --skip-reboot     Do not prompt for reboot after system update
  --only <module>   Run only a specific module:
                      system | repos | devtools | containers |
                      virt   | apps  | shell    | neovim
  --help            Show this help

EXAMPLES:
  ./install.sh                      # Full interactive setup
  ./install.sh --dry-run            # Preview all actions
  ./install.sh --yes --skip-reboot  # Non-interactive CI-style run
  ./install.sh --only containers    # Run only the containers module
EOF
}

# =============================================================================
# Pre-flight checks
# =============================================================================
run_preflight() {
  log_section "Pre-flight Checks"

  check_not_root        # Must be run as normal user (sudo invoked internally)
  check_fedora_version  # Must be Fedora 44
  check_kde_plasma      # Warn if KDE not detected
  check_wayland         # Warn if not Wayland
  check_internet        # Abort if offline
  check_sudo_access     # Verify passwordless or prompt sudo now
  check_disk_space      # Need at least 10 GB free

  log_success "All pre-flight checks passed"
}

# =============================================================================
# Module runner — respects --dry-run and --only
# =============================================================================
run_module() {
  local name="$1"
  local script="$2"

  if [[ -n "${ONLY_MODULE}" && "${ONLY_MODULE}" != "${name}" ]]; then
    log_skip "Module [${name}] — skipped (--only ${ONLY_MODULE})"
    return 0
  fi

  log_section "Module: ${name}"

  if [[ ! -f "${script}" ]]; then
    log_warn "Script not found: ${script} — skipping"
    return 0
  fi

  if "${DRY_RUN}"; then
    log_dry "Would execute: ${script}"
    return 0
  fi

  # Export shared variables for child scripts
  export DRY_RUN AUTO_YES SKIP_REBOOT SCRIPT_DIR LIB_DIR CONFIGS_DIR LOG_FILE

  bash "${script}"
  log_success "Module [${name}] completed"
}

# =============================================================================
# Main
# =============================================================================
main() {
  parse_args "$@"

  print_banner

  log_info "Log file: ${LOG_FILE}"
  log_info "Flags: DRY_RUN=${DRY_RUN} AUTO_YES=${AUTO_YES} SKIP_REBOOT=${SKIP_REBOOT}"
  [[ -n "${ONLY_MODULE}" ]] && log_info "Running only module: ${ONLY_MODULE}"

  run_preflight

  # ── Phase 1: System update & base repos ─────────────────────────────────────
  run_module "system"    "${SCRIPTS_DIR}/system/01-system-update.sh"
  run_module "repos"     "${SCRIPTS_DIR}/system/02-repos.sh"

  # ── Phase 2: Developer tools (CLI, build tools, editors) ────────────────────
  run_module "devtools"  "${SCRIPTS_DIR}/system/03-devtools.sh"

  # ── Phase 3: Containers & Kubernetes ────────────────────────────────────────
  run_module "containers" "${SCRIPTS_DIR}/containers/01-containers.sh"

  # ── Phase 4: Virtualization ──────────────────────────────────────────────────
  run_module "virt"      "${SCRIPTS_DIR}/virt/01-kvm.sh"

  # ── Phase 5: Desktop applications ───────────────────────────────────────────
  run_module "apps"      "${SCRIPTS_DIR}/apps/01-applications.sh"

  # ── Phase 6: Shell environment ───────────────────────────────────────────────
  run_module "shell"     "${SCRIPTS_DIR}/shell/01-zsh.sh"

  # ── Phase 7: Neovim ─────────────────────────────────────────────────────────
  run_module "neovim"    "${SCRIPTS_DIR}/shell/02-neovim.sh"

  # ── Done ─────────────────────────────────────────────────────────────────────
  print_summary
}

main "$@"
