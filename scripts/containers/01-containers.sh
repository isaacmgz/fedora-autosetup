#!/usr/bin/env bash
# =============================================================================
# scripts/containers/01-containers.sh — Podman, Kubernetes tooling
# =============================================================================
#
# ARCHITECTURE DECISIONS:
#
# DOCKER ENGINE: NOT installed. Here's why:
#   Fedora 44 uses cgroups v2 by default. Docker CE (Moby) has historically
#   had issues with cgroups v2, though recent versions improved. More critically:
#   - Podman is rootless by default, Docker still requires a daemon running as root
#   - Podman is socket-compatible with Docker (DOCKER_HOST=unix:///run/user/$UID/podman/podman.sock)
#   - Fedora ships podman-docker for drop-in compatibility (alias + socket)
#   - Red Hat deprecated Docker in RHEL and invested heavily in Podman
#   - podman-compose is a direct replacement for docker-compose
#   If you absolutely need Docker Engine (e.g. company policy), see the
#   comment at the bottom of this file.
#
# KIND vs MINIKUBE — RECOMMENDATION: kind
#   kind (Kubernetes IN Docker) actually uses Podman-compatible containers.
#   Minikube creates a VM by default (requires KVM/VirtualBox on Linux),
#   which adds overhead and complexity for a dev laptop.
#   kind runs K8s nodes as containers — faster startup, lower RAM usage,
#   better suited for local dev/testing, and works seamlessly with rootless Podman.
#   Minikube is better if you need to test with a specific driver (hyperkit, VirtualBox)
#   or need full VM isolation.
#   Verdict: kind for DevOps/CI simulation; both installed so you choose per use case.
#
# CGROUPS v2:
#   Fedora has used cgroups v2 as default since Fedora 31.
#   Podman and all OCI tools work correctly with it.
#   Systemd user sessions use cgroup delegation properly.
#
# ROOTLESS CONTAINERS:
#   Podman runs rootless by default — containers run as your user UID.
#   /etc/subuid and /etc/subgid are configured automatically during podman install.
#   No daemon, no root socket, no attack surface.
#
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

source "${LIB_DIR}/helpers.sh"
source "${LIB_DIR}/pkg.sh"

log_section "Containers & Kubernetes"

REAL_USER="${SUDO_USER:-${USER}}"
REAL_HOME="$(real_home)"

# =============================================================================
# 1. Podman stack (OCI containers — rootless)
# =============================================================================
log_step "Installing Podman and OCI tools"

dnf_install \
  podman \
  podman-compose \
  podman-docker \
  buildah \
  skopeo \
  crun \
  slirp4netns \
  fuse-overlayfs \
  aardvark-dns \
  netavark

# podman-docker provides:
#   - /usr/bin/docker symlink → podman
#   - Docker-compatible socket via podman.socket
# This gives Docker CLI compatibility without installing Docker Engine.

# =============================================================================
# 2. Configure rootless Podman
# =============================================================================
log_step "Configuring rootless Podman for ${REAL_USER}"

if ! "${DRY_RUN}"; then
  # Verify subuid/subgid entries exist (podman install usually creates them)
  if ! grep -q "^${REAL_USER}:" /etc/subuid 2>/dev/null; then
    log_warn "No subuid entry for ${REAL_USER} — adding default range"
    echo "${REAL_USER}:100000:65536" | sudo tee -a /etc/subuid
  fi
  if ! grep -q "^${REAL_USER}:" /etc/subgid 2>/dev/null; then
    log_warn "No subgid entry for ${REAL_USER} — adding default range"
    echo "${REAL_USER}:100000:65536" | sudo tee -a /etc/subgid
  fi

  # Enable and start podman socket for the user (Docker API compatibility)
  # This is a USER-level systemd socket — no root required
  sudo -u "${REAL_USER}" systemctl --user enable --now podman.socket 2>/dev/null || \
    log_warn "Could not enable user podman.socket (likely no active user session — enable manually after login)"

  # Set DOCKER_HOST env var in user's shell config (handled in shell module)
  log_success "Rootless Podman configured"
fi

# ── Storage configuration ─────────────────────────────────────────────────────
# Ensure overlay storage driver is configured (fuse-overlayfs for rootless)
CONTAINERS_CONF_DIR="${REAL_HOME}/.config/containers"
if ! "${DRY_RUN}"; then
  sudo -u "${REAL_USER}" mkdir -p "${CONTAINERS_CONF_DIR}"

  if [[ ! -f "${CONTAINERS_CONF_DIR}/storage.conf" ]]; then
    sudo -u "${REAL_USER}" tee "${CONTAINERS_CONF_DIR}/storage.conf" > /dev/null <<'EOF'
[storage]
driver = "overlay"

[storage.options.overlay]
# Use native overlay if kernel supports unprivileged user namespaces
# Falls back to fuse-overlayfs automatically if not
mountopt = "nodev,metacopy=on"
EOF
    log_success "Podman storage config written"
  else
    log_skip "Podman storage.conf (already exists)"
  fi
fi

# =============================================================================
# 3. kubectl — Kubernetes CLI
# =============================================================================
log_step "Installing kubectl"
dnf_install kubectl

# =============================================================================
# 4. Helm — Kubernetes package manager
# =============================================================================
log_step "Installing Helm (from Fedora official repo)"
# Fedora 44 ships Helm 4 in the standard repos — no external repo needed.
# helm3 is also available as a parallel package for backward compatibility.
# Helm 4 has intentional breaking changes vs Helm 3.
dnf_install helm

if ! "${DRY_RUN}" && has_cmd helm; then
  HELM_MAJOR="$(helm version --short 2>/dev/null | grep -oP 'v\K\d+' | head -1)"
  if [[ "${HELM_MAJOR:-0}" -ge 4 ]]; then
    log_warn "Helm ${HELM_MAJOR} installed (Fedora 44 default). Helm 4 has breaking changes."
    log_warn "If your charts require Helm 3 syntax: sudo dnf install helm3"
  fi
fi

# =============================================================================
# 5. kind — Kubernetes IN Docker/Podman (RECOMMENDED for local dev)
# =============================================================================
log_step "Installing kind"

KIND_VERSION="0.27.0"
KIND_BINARY="/usr/local/bin/kind"

if [[ ! -f "${KIND_BINARY}" ]]; then
  if ! "${DRY_RUN}"; then
    KIND_URL="https://kind.sigs.k8s.io/dl/v${KIND_VERSION}/kind-linux-amd64"
    curl -fsSL "${KIND_URL}" -o /tmp/kind
    chmod +x /tmp/kind
    sudo mv /tmp/kind "${KIND_BINARY}"
    log_success "kind ${KIND_VERSION} installed"
  else
    log_dry "Would install kind ${KIND_VERSION}"
  fi
else
  log_skip "kind (already at ${KIND_BINARY})"
fi

# ── kind + Podman integration ─────────────────────────────────────────────────
# kind works with Podman via KIND_EXPERIMENTAL_PROVIDER=podman
# Configure a provider alias in the user's shell (handled in shell module)
# For rootless kind with Podman, also need:
#   export KIND_EXPERIMENTAL_PROVIDER=podman

# =============================================================================
# 6. minikube — alternative local K8s (secondary option)
# =============================================================================
log_step "Installing minikube (secondary local K8s option)"

MINIKUBE_BINARY="/usr/local/bin/minikube"
if [[ ! -f "${MINIKUBE_BINARY}" ]]; then
  if ! "${DRY_RUN}"; then
    MINIKUBE_URL="https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64"
    curl -fsSL "${MINIKUBE_URL}" -o /tmp/minikube
    chmod +x /tmp/minikube
    sudo mv /tmp/minikube "${MINIKUBE_BINARY}"
    log_success "minikube installed"
  else
    log_dry "Would install minikube"
  fi
else
  log_skip "minikube (already at ${MINIKUBE_BINARY})"
fi

# =============================================================================
# 7. Additional Kubernetes tooling
# =============================================================================
log_step "Installing additional Kubernetes tools"

# ── k9s — terminal-based K8s dashboard (Fedora repos since F39) ───────────
dnf_install k9s

# ── kubectx + kubens — fast context/namespace switching ──────────────────────
# kubectx is NOT in the Fedora official repos. Install as version-pinned shell
# scripts from the official GitHub release. No COPR needed — these are
# standalone bash scripts with no compilation required.
log_step "Installing kubectx and kubens"
KUBECTX_VERSION="0.9.5"
KUBECTX_BIN="/usr/local/bin/kubectx"
KUBENS_BIN="/usr/local/bin/kubens"
KUBECTX_BASE="https://github.com/ahmetb/kubectx/releases/download/v${KUBECTX_VERSION}"

if [[ ! -x "${KUBECTX_BIN}" ]]; then
  if ! "${DRY_RUN}"; then
    curl -fsSL "${KUBECTX_BASE}/kubectx" -o /tmp/kubectx
    chmod +x /tmp/kubectx
    sudo mv /tmp/kubectx "${KUBECTX_BIN}"
    log_success "kubectx ${KUBECTX_VERSION} installed"
  else
    log_dry "Would install kubectx ${KUBECTX_VERSION} to ${KUBECTX_BIN}"
  fi
else
  log_skip "kubectx (already at ${KUBECTX_BIN})"
fi

if [[ ! -x "${KUBENS_BIN}" ]]; then
  if ! "${DRY_RUN}"; then
    curl -fsSL "${KUBECTX_BASE}/kubens" -o /tmp/kubens
    chmod +x /tmp/kubens
    sudo mv /tmp/kubens "${KUBENS_BIN}"
    log_success "kubens ${KUBECTX_VERSION} installed"
  else
    log_dry "Would install kubens ${KUBECTX_VERSION} to ${KUBENS_BIN}"
  fi
else
  log_skip "kubens (already at ${KUBENS_BIN})"
fi

# ── kustomize — Kubernetes config management ──────────────────────────────────
KUSTOMIZE_BINARY="/usr/local/bin/kustomize"
if [[ ! -f "${KUSTOMIZE_BINARY}" ]]; then
  if ! "${DRY_RUN}"; then
    # Use the official install script
    curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" \
      | bash -s -- /tmp
    sudo mv /tmp/kustomize "${KUSTOMIZE_BINARY}"
    log_success "kustomize installed"
  else
    log_dry "Would install kustomize"
  fi
else
  log_skip "kustomize (already at ${KUSTOMIZE_BINARY})"
fi

# ── Stern — multi-pod log tailing ─────────────────────────────────────────────
STERN_VERSION="1.31.0"
STERN_BINARY="/usr/local/bin/stern"
if [[ ! -f "${STERN_BINARY}" ]]; then
  if ! "${DRY_RUN}"; then
    STERN_URL="https://github.com/stern/stern/releases/download/v${STERN_VERSION}/stern_${STERN_VERSION}_linux_amd64.tar.gz"
    curl -fsSL "${STERN_URL}" | tar -xz -C /tmp stern
    sudo mv /tmp/stern "${STERN_BINARY}"
    log_success "stern ${STERN_VERSION} installed"
  else
    log_dry "Would install stern ${STERN_VERSION}"
  fi
else
  log_skip "stern (already at ${STERN_BINARY})"
fi

# =============================================================================
# 8. Verification
# =============================================================================
log_step "Verifying container toolchain"
if ! "${DRY_RUN}"; then
  has_cmd podman    && log_success "podman:    $(podman --version)"
  has_cmd buildah   && log_success "buildah:   $(buildah --version)"
  has_cmd skopeo    && log_success "skopeo:    $(skopeo --version | head -1)"
  has_cmd kubectl   && log_success "kubectl:   $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
  has_cmd helm      && log_success "helm:      $(helm version --short)"
  has_cmd kind      && log_success "kind:      $(kind version)"
  has_cmd minikube  && log_success "minikube:  $(minikube version --short)"
  has_cmd k9s       && log_success "k9s:       $(k9s version --short 2>/dev/null | head -1)"
fi

log_success "Container & Kubernetes tooling complete"

# =============================================================================
# NOTE: Docker Engine (optional, not installed by default)
# =============================================================================
# If you require Docker Engine for a specific reason (e.g., BuildKit features,
# Docker Swarm, or company policy), you can add it separately:
#
#   sudo dnf config-manager addrepo \
#     --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
#   sudo dnf install docker-ce docker-ce-cli containerd.io docker-buildx-plugin
#   sudo systemctl enable --now docker
#   sudo usermod -aG docker $USER
#
# WARNING: Docker daemon runs as root. This conflicts with Fedora's security model.
# You will also need to disable cgroups v2 delegation workarounds.
# We strongly recommend staying with Podman for Fedora workstations.
# =============================================================================
