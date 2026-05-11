#!/usr/bin/env bash
# =============================================================================
# scripts/system/02-repos.sh — External repository configuration
# =============================================================================
# Configures all required third-party repositories BEFORE package installation.
# Each repo addition is idempotent and explained.
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

source "${LIB_DIR}/helpers.sh"
source "${LIB_DIR}/pkg.sh"

log_section "Repository Configuration"

FEDORA_VER="${FEDORA_VERSION:-44}"

# =============================================================================
# 1. Brave Browser (Nightly)
# =============================================================================
# Brave provides an official DNF repository. This is the correct method —
# not Flatpak, not COPR. We use Nightly as requested.
# -----------------------------------------------------------------------------
log_step "Configuring Brave Nightly repository"

BRAVE_REPO="/etc/yum.repos.d/brave-browser-nightly.repo"
# Nightly/beta use a DIFFERENT signing key from stable (brave-core.asc).
# Using the wrong key causes GPG verification failures on package install.
BRAVE_NIGHTLY_KEY="https://brave-browser-rpm-beta.s3.brave.com/brave-core-nightly.asc"

if [[ ! -f "${BRAVE_REPO}" ]]; then
  if ! "${DRY_RUN}"; then
    # Import the correct nightly signing key
    sudo rpm --import "${BRAVE_NIGHTLY_KEY}"

    # repo_gpgcheck=0 is required: Brave does not GPG-sign the repomd.xml metadata,
    # only individual packages. DNF5 rejects unsigned metadata by default.
    sudo tee "${BRAVE_REPO}" > /dev/null <<EOF
[brave-browser-nightly]
name=Brave Browser Nightly
baseurl=https://brave-browser-rpm-nightly.s3.brave.com/x86_64/
enabled=1
autorefresh=1
type=rpm
gpgcheck=1
repo_gpgcheck=0
gpgkey=${BRAVE_NIGHTLY_KEY}
EOF
    log_success "Brave Nightly repo configured"
  else
    log_dry "Would configure Brave Nightly repo at ${BRAVE_REPO}"
  fi
else
  log_skip "Brave Nightly repo (already configured)"
fi

# =============================================================================
# 2. kubectl (from Kubernetes official repo)
# =============================================================================
# The Kubernetes project provides an official RPM repo for kubectl.
# This is preferred over COPR because it's maintained by the Kubernetes SIG.
# NOTE: The repo was updated in 2023 — the old packages.cloud.google.com repo
#       is deprecated. The new canonical URL is pkgs.k8s.io.
# -----------------------------------------------------------------------------
log_step "Configuring kubectl repository (pkgs.k8s.io)"

KUBECTL_REPO="/etc/yum.repos.d/kubernetes.repo"
# We pin to the latest stable major/minor. Update this for future versions.
KUBECTL_CHANNEL="v1.32"

if [[ ! -f "${KUBECTL_REPO}" ]]; then
  if ! "${DRY_RUN}"; then
    sudo tee "${KUBECTL_REPO}" > /dev/null <<EOF
[kubernetes]
name=Kubernetes ${KUBECTL_CHANNEL}
baseurl=https://pkgs.k8s.io/core:/stable:/${KUBECTL_CHANNEL}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${KUBECTL_CHANNEL}/rpm/repodata/repomd.xml.key
EOF
    log_success "kubectl repo configured (channel: ${KUBECTL_CHANNEL})"
  else
    log_dry "Would configure kubectl repo at ${KUBECTL_REPO}"
  fi
else
  log_skip "kubectl repo (already configured)"
fi

# =============================================================================
# 3. Helm — NO external repo needed
# =============================================================================
# Fedora 44 ships Helm 4 in the official repositories (tracked F44 change).
# A parallel `helm3` package is also available for backward compatibility.
# The baltocdn.com external repo is unnecessary and adds third-party risk.
# Helm installation is handled in scripts/containers/01-containers.sh.
# -----------------------------------------------------------------------------
log_info "Helm: no external repo needed — available in Fedora 44 official repos"

# =============================================================================
# 4. GitHub CLI (gh)
# =============================================================================
# GitHub provides an official RPM repo. Installing from here rather than
# Fedora repos ensures we get the latest version promptly.
# -----------------------------------------------------------------------------
log_step "Configuring GitHub CLI repository"

GH_REPO="/etc/yum.repos.d/gh-cli.repo"
if [[ ! -f "${GH_REPO}" ]]; then
  if ! "${DRY_RUN}"; then
    sudo tee "${GH_REPO}" > /dev/null <<'EOF'
[gh-cli]
name=packages for the GitHub CLI
baseurl=https://cli.github.com/packages/rpm
enabled=1
gpgcheck=1
gpgkey=https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x23F3D4EA75716059
EOF
    log_success "GitHub CLI repo configured"
  else
    log_dry "Would configure GitHub CLI repo at ${GH_REPO}"
  fi
else
  log_skip "GitHub CLI repo (already configured)"
fi

# =============================================================================
# 5. Flathub (for Flatpak apps)
# =============================================================================
# Flatpak ships pre-installed on Fedora Workstation but Flathub is not enabled
# by default in all cases. We add it here for Spotify and other apps.
# -----------------------------------------------------------------------------
log_step "Ensuring Flathub is configured"
ensure_flathub

# =============================================================================
# 6. Refresh DNF metadata after repo additions
# =============================================================================
log_step "Refreshing DNF metadata with new repos"
if ! "${DRY_RUN}"; then
  sudo "${DNF_CMD}" makecache
fi

log_success "All repositories configured"
