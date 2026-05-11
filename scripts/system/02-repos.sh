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
if [[ ! -f "${BRAVE_REPO}" ]]; then
  if ! "${DRY_RUN}"; then
    # Import Brave GPG key
    sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc

    # Add repo file
    sudo tee "${BRAVE_REPO}" > /dev/null <<'EOF'
[brave-browser-nightly]
name=Brave Browser Nightly
baseurl=https://brave-browser-rpm-nightly.s3.brave.com/x86_64/
enabled=1
autorefresh=1
type=rpm
gpgcheck=1
gpgkey=https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
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
# 3. Helm (from official Helm repo)
# =============================================================================
# Helm provides an official RPM repo via Artifact Hub / Helm CDN.
# This is preferred over COPR or manual binary downloads.
# -----------------------------------------------------------------------------
log_step "Configuring Helm repository"

HELM_REPO="/etc/yum.repos.d/helm.repo"
if [[ ! -f "${HELM_REPO}" ]]; then
  if ! "${DRY_RUN}"; then
    # Import Helm GPG key
    curl -fsSL https://baltocdn.com/helm/signing.asc | sudo gpg --dearmor -o /etc/pki/rpm-gpg/helm.gpg

    sudo tee "${HELM_REPO}" > /dev/null <<'EOF'
[helm-stable]
name=Helm Stable
baseurl=https://baltocdn.com/helm/stable/rpm/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/helm.gpg
EOF
    log_success "Helm repo configured"
  else
    log_dry "Would configure Helm repo at ${HELM_REPO}"
  fi
else
  log_skip "Helm repo (already configured)"
fi

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
