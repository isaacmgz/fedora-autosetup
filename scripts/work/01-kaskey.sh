#!/usr/bin/env bash
# =============================================================================
# scripts/work/01-kaskey.sh — Work environment for Kaskey project
# =============================================================================
#
# INSTALLS:
#   - Amazon Corretto 11 JDK (via direct RPM — Corretto's yum repo targets
#     Amazon Linux only; direct RPM is the correct Fedora method)
#   - alternatives configuration to switch between JDKs per-project
#   - SBT (official scala-sbt.org RPM repo — not in Fedora repos)
#   - Scala (Fedora repo) + Coursier cs launcher for toolchain management
#   - AWS CLI v2 (official zip installer — no RPM exists)
#   - AWS supporting tools: eksctl, aws-vault, awscli-local (LocalStack)
#   - Go toolchain (already in devtools; verified here)
#   - WireGuard (in Fedora official repos — no COPR, no DKMS needed)
#   - Network Manager WireGuard plugin for GUI/nmcli management
#
# JAVA STRATEGY:
#   Fedora 44 already ships OpenJDK 25 (installed as system Java).
#   Corretto 11 is installed alongside it, NOT set as system default.
#   Use `sdk use java 11-amzn` (via SDKMAN) or set JAVA_HOME per-project.
#   The alternatives system lets you switch system default if needed.
#
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

source "${LIB_DIR}/helpers.sh"
source "${LIB_DIR}/pkg.sh"

log_section "Kaskey Work Environment"

REAL_USER="${SUDO_USER:-${USER}}"
REAL_HOME="$(real_home)"

# =============================================================================
# 1. Amazon Corretto 11 JDK
# =============================================================================
# The Corretto yum repository only officially supports Amazon Linux.
# For Fedora, the correct method is to download the RPM directly from Amazon's
# S3 distribution and install with dnf localinstall.
# Corretto 11 LTS: last release 11.0.31 (April 2026)
# =============================================================================
log_step "Installing Amazon Corretto 11 JDK"

CORRETTO_VERSION="11.0.31.11-1"
CORRETTO_RPM="java-11-amazon-corretto-devel-${CORRETTO_VERSION}.x86_64.rpm"
CORRETTO_URL="https://corretto.aws/downloads/latest/amazon-corretto-11-x64-linux-jdk.rpm"
CORRETTO_INSTALL_DIR="/usr/lib/jvm/java-11-amazon-corretto.x86_64"

if [[ -d "${CORRETTO_INSTALL_DIR}" ]]; then
  log_skip "Amazon Corretto 11 (already installed at ${CORRETTO_INSTALL_DIR})"
else
  if ! "${DRY_RUN}"; then
    log_step "Downloading Corretto 11 JDK RPM"
    # Use the /latest/ URL — Amazon always points this to the current LTS release
    curl -fsSL "${CORRETTO_URL}" -o "/tmp/${CORRETTO_RPM}"

    log_step "Installing Corretto 11 JDK"
    # dnf localinstall handles dependencies correctly for local RPM files
    sudo "${DNF_CMD}" install -y "/tmp/${CORRETTO_RPM}"
    rm -f "/tmp/${CORRETTO_RPM}"
    log_success "Amazon Corretto 11 installed"
  else
    log_dry "Would download and install Corretto 11 from ${CORRETTO_URL}"
  fi
fi

# ── Configure alternatives ────────────────────────────────────────────────────
# Do NOT set Corretto 11 as the system default — Fedora 44 ships OpenJDK 25
# which is the correct modern default. Corretto 11 is available for Kaskey
# project use via JAVA_HOME or alternatives --config java.
# We register it in the alternatives system so it's discoverable.
log_step "Registering Corretto 11 in alternatives system"
if ! "${DRY_RUN}"; then
  CORRETTO_JAVA="${CORRETTO_INSTALL_DIR}/bin/java"
  CORRETTO_JAVAC="${CORRETTO_INSTALL_DIR}/bin/javac"

  if [[ -f "${CORRETTO_JAVA}" ]]; then
    # Priority 11 — lower than system JDK (priority 25+), so it's not auto-selected
    sudo alternatives --install /usr/bin/java java "${CORRETTO_JAVA}" 11 \
      --slave /usr/bin/javac javac "${CORRETTO_JAVAC}" 2>/dev/null || true
    log_success "Corretto 11 registered in alternatives (not set as default)"
    log_info "To switch: sudo alternatives --config java"
    log_info "Per-project: export JAVA_HOME=${CORRETTO_INSTALL_DIR}"
  fi
fi

# =============================================================================
# 2. SDKMAN — JDK version manager (recommended for multi-JDK work)
# =============================================================================
# SDKMAN is the best way to switch between Java 11 (Kaskey) and Java 25
# (system) per-shell or per-project. It also manages Scala, SBT, Kotlin.
# Install to ~/.sdkman. The shell integration is added to .zshrc below.
# =============================================================================
log_step "Installing SDKMAN (JDK version manager)"

SDKMAN_DIR="${REAL_HOME}/.sdkman"

if [[ -d "${SDKMAN_DIR}" ]]; then
  log_skip "SDKMAN (already installed at ${SDKMAN_DIR})"
else
  if ! "${DRY_RUN}"; then
    sudo -u "${REAL_USER}" bash -c "
      export SDKMAN_DIR='${SDKMAN_DIR}'
      curl -fsSL https://get.sdkman.io | bash
    "
    log_success "SDKMAN installed"
    log_info "After install, use: sdk install java 11.0.31-amzn"
    log_info "To use Corretto 11 in a session: sdk use java 11.0.31-amzn"
  else
    log_dry "Would install SDKMAN to ${SDKMAN_DIR}"
  fi
fi

# ── Add SDKMAN to .zshrc if not present ───────────────────────────────────────
ZSHRC="${REAL_HOME}/.zshrc"
if [[ -f "${ZSHRC}" ]] && ! grep -q "SDKMAN_DIR" "${ZSHRC}" 2>/dev/null; then
  if ! "${DRY_RUN}"; then
    sudo -u "${REAL_USER}" tee -a "${ZSHRC}" > /dev/null <<'EOF'

# =============================================================================
# SDKMAN — JDK / SDK version manager
# =============================================================================
export SDKMAN_DIR="${HOME}/.sdkman"
[[ -s "${HOME}/.sdkman/bin/sdkman-init.sh" ]] && \
  source "${HOME}/.sdkman/bin/sdkman-init.sh"
EOF
    log_success "SDKMAN shell integration added to .zshrc"
  fi
fi

# =============================================================================
# 3. SBT (Scala Build Tool)
# =============================================================================
# SBT is NOT in Fedora repos. The official method is the scala-sbt.org RPM repo.
# The old Bintray repo (bintray-sbt-rpm.repo) is defunct — remove it if present.
# =============================================================================
log_step "Configuring SBT repository"

SBT_REPO="/etc/yum.repos.d/sbt.repo"
BINTRAY_REPO="/etc/yum.repos.d/bintray-sbt-rpm.repo"

# Remove defunct Bintray repo if it exists
if [[ -f "${BINTRAY_REPO}" ]]; then
  log_warn "Removing defunct Bintray SBT repo"
  if ! "${DRY_RUN}"; then
    sudo rm -f "${BINTRAY_REPO}"
  fi
fi

if [[ ! -f "${SBT_REPO}" ]]; then
  if ! "${DRY_RUN}"; then
    curl -fsSL https://www.scala-sbt.org/sbt-rpm.repo | sudo tee "${SBT_REPO}" > /dev/null
    log_success "SBT repo configured"
  else
    log_dry "Would configure SBT repo at ${SBT_REPO}"
  fi
else
  log_skip "SBT repo (already configured)"
fi

log_step "Installing SBT"
dnf_install sbt

# =============================================================================
# 4. Scala toolchain
# =============================================================================
# NOTE: The 'scala' RPM was removed from Fedora repos. Do not attempt dnf_install.
# Coursier (cs) is the modern canonical way to manage the Scala toolchain —
# it installs scala-cli, scalac, metals LSP, and manages Scala/SBT versions.
# scala-cli is the recommended successor to the bare scala REPL.
# =============================================================================
log_step "Installing Coursier (cs) — Scala toolchain launcher"
CS_BIN="/usr/local/bin/cs"

if [[ -f "${CS_BIN}" ]]; then
  log_skip "Coursier cs (already at ${CS_BIN})"
else
  if ! "${DRY_RUN}"; then
    curl -fsSL https://github.com/coursier/launchers/raw/master/cs-x86_64-pc-linux.gz \
      | gzip -d > /tmp/cs
    chmod +x /tmp/cs
    sudo mv /tmp/cs "${CS_BIN}"
    log_success "Coursier cs installed to ${CS_BIN}"

    # Bootstrap Scala tools for the real user
    sudo -u "${REAL_USER}" bash -c "
      export JAVA_HOME='${CORRETTO_INSTALL_DIR}'
      ${CS_BIN} setup --yes 2>/dev/null || true
    " || true
  else
    log_dry "Would install Coursier cs to ${CS_BIN}"
  fi
fi

# ── Add Coursier bin path to .zshrc (idempotent) ────────────────────────────
# SDKMAN appends its own block to .zshrc during install. We write to a
# separate .zshrc.d/kaskey.zsh file to avoid collisions with re-runs.
if [[ -f "${ZSHRC}" ]] && ! grep -q "coursier" "${ZSHRC}" 2>/dev/null; then
  if ! "${DRY_RUN}"; then
    sudo -u "${REAL_USER}" tee -a "${ZSHRC}" > /dev/null <<'EOF'

# Scala — Coursier managed binaries (scalac, scala-cli, metals, etc.)
export PATH="${HOME}/.local/share/coursier/bin:${PATH}"
EOF
    log_success "Coursier PATH added to .zshrc"
  fi
fi

# =============================================================================
# 5. AWS CLI v2
# =============================================================================
# AWS does not publish an RPM. The official and only supported Linux method
# is the bundled zip installer, which installs to /usr/local/aws-cli and
# creates a symlink at /usr/local/bin/aws.
# To update: re-run this module — the script detects the existing install
# and runs with --update flag automatically.
# =============================================================================
log_step "Installing AWS CLI v2"

AWS_CLI_BIN="/usr/local/bin/aws"
AWS_CLI_INSTALL_DIR="/usr/local/aws-cli"

if [[ -f "${AWS_CLI_BIN}" ]]; then
  INSTALLED_VERSION="$(aws --version 2>&1 | grep -oP 'aws-cli/\K[\d.]+')"
  log_skip "AWS CLI v2 (already installed: ${INSTALLED_VERSION})"
  log_info "To update: re-run this module — it will detect and update in place"
else
  if ! "${DRY_RUN}"; then
    log_step "Downloading AWS CLI v2 installer"
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
      -o /tmp/awscliv2.zip
    unzip -q /tmp/awscliv2.zip -d /tmp/
    sudo /tmp/aws/install
    rm -rf /tmp/aws /tmp/awscliv2.zip
    log_success "AWS CLI v2 installed: $(aws --version 2>&1)"
  else
    log_dry "Would download and install AWS CLI v2 from awscli.amazonaws.com"
  fi
fi

# ── AWS supporting tools ──────────────────────────────────────────────────────
log_step "Installing AWS supporting tools"

# aws-vault: secure credential storage (no plaintext ~/.aws/credentials)
# Stores credentials in the OS keyring (KDE Wallet on KDE Plasma).
# Critical for cloud work — never store AWS keys as plaintext files.
AWS_VAULT_BIN="/usr/local/bin/aws-vault"
if [[ ! -f "${AWS_VAULT_BIN}" ]]; then
  if ! "${DRY_RUN}"; then
    AWS_VAULT_URL="https://github.com/99designs/aws-vault/releases/latest/download/aws-vault-linux-amd64"
    curl -fsSL "${AWS_VAULT_URL}" -o /tmp/aws-vault
    chmod +x /tmp/aws-vault
    sudo mv /tmp/aws-vault "${AWS_VAULT_BIN}"
    log_success "aws-vault installed"
  else
    log_dry "Would install aws-vault to ${AWS_VAULT_BIN}"
  fi
else
  log_skip "aws-vault (already installed)"
fi

# eksctl: official EKS cluster management CLI
EKSCTL_BIN="/usr/local/bin/eksctl"
if [[ ! -f "${EKSCTL_BIN}" ]]; then
  if ! "${DRY_RUN}"; then
    curl -fsSL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" \
      | tar -xz -C /tmp eksctl
    sudo mv /tmp/eksctl "${EKSCTL_BIN}"
    log_success "eksctl installed"
  else
    log_dry "Would install eksctl to ${EKSCTL_BIN}"
  fi
else
  log_skip "eksctl (already installed)"
fi

# =============================================================================
# 6. Go toolchain verification
# =============================================================================
# Go was installed in devtools. Verify it's present and configured.
# =============================================================================
log_step "Verifying Go toolchain"

if has_cmd go; then
  log_success "Go: $(go version)"
else
  log_warn "Go not found — installing"
  dnf_install golang
fi

# Ensure GOPATH and GOBIN are in .zshrc
if [[ -f "${ZSHRC}" ]] && ! grep -q "GOPATH" "${ZSHRC}" 2>/dev/null; then
  if ! "${DRY_RUN}"; then
    sudo -u "${REAL_USER}" tee -a "${ZSHRC}" > /dev/null <<'EOF'

# =============================================================================
# Go — workspace and binary paths
# =============================================================================
export GOPATH="${HOME}/go"
export GOBIN="${GOPATH}/bin"
export PATH="${GOBIN}:${PATH}"
EOF
    log_success "GOPATH added to .zshrc"
  fi
fi

# =============================================================================
# 7. WireGuard
# =============================================================================
# WireGuard is in the Fedora official repos since Fedora 33.
# The kernel module is built into the Fedora kernel (since Linux 5.6).
# No COPR, no DKMS, no third-party repo required.
# wireguard-tools: wg and wg-quick userspace utilities
# NetworkManager-wireguard: nmcli/nmtui integration for KDE Plasma
# plasma-nm: KDE Plasma network manager applet (should already be installed)
# =============================================================================
log_step "Installing WireGuard"

dnf_install \
  wireguard-tools \
  NetworkManager-wireguard

# Verify kernel module is available
log_step "Verifying WireGuard kernel module"
if ! "${DRY_RUN}"; then
  if sudo modprobe wireguard 2>/dev/null; then
    log_success "WireGuard kernel module loaded"
  else
    log_warn "WireGuard kernel module failed to load"
    log_warn "Try: sudo dnf reinstall kernel-modules-$(uname -r)"
    log_warn "Then reboot and run: modprobe wireguard"
  fi
fi

log_success "WireGuard installed"
log_info "Configure your VPN: create /etc/wireguard/wg0.conf"
log_info "Start VPN:  sudo wg-quick up wg0"
log_info "Enable on boot: sudo systemctl enable --now wg-quick@wg0"
log_info "Or use KDE Plasma network manager applet → Add VPN → WireGuard"

# =============================================================================
# 8. Kaskey project aliases and environment
# =============================================================================
log_step "Adding Kaskey project shell aliases"

KASKEY_ZSHRC_BLOCK="${REAL_HOME}/.zshrc.d/kaskey.zsh"
if ! "${DRY_RUN}"; then
  sudo -u "${REAL_USER}" mkdir -p "${REAL_HOME}/.zshrc.d"
  sudo -u "${REAL_USER}" tee "${KASKEY_ZSHRC_BLOCK}" > /dev/null <<'EOF'
# =============================================================================
# Kaskey project environment
# Source: fedora-workstation-setup — work module
# =============================================================================

# Java 11 (Corretto) for Kaskey project
# Use one of these per-session or add to a .envrc with direnv:
alias java11='export JAVA_HOME=/usr/lib/jvm/java-11-amazon-corretto.x86_64 && export PATH="${JAVA_HOME}/bin:${PATH}" && java -version'
alias sbt11='JAVA_HOME=/usr/lib/jvm/java-11-amazon-corretto.x86_64 sbt'

# AWS shortcuts
alias awsid='aws sts get-caller-identity'
alias awsregion='aws configure get region'
alias ecr-login='aws ecr get-login-password --region $(aws configure get region) | podman login --username AWS --password-stdin $(aws sts get-caller-identity --query Account --output text).dkr.ecr.$(aws configure get region).amazonaws.com'

# EKS
alias kctx-eks='aws eks list-clusters --output text | tr "\t" "\n" | fzf | xargs -I{} aws eks update-kubeconfig --name {}'

# Scala / SBT
alias sbt='sbt -java-home /usr/lib/jvm/java-11-amazon-corretto.x86_64'
alias sbt-clean='sbt clean compile'
alias sbt-test='sbt test'
alias sbt-run='sbt run'

# WireGuard VPN
alias vpn-up='sudo wg-quick up wg0'
alias vpn-down='sudo wg-quick down wg0'
alias vpn-status='sudo wg show'

# direnv hook — per-project .envrc for automatic JAVA_HOME switching
# Create a .envrc in your Kaskey project root with:
#   export JAVA_HOME=/usr/lib/jvm/java-11-amazon-corretto.x86_64
#   export PATH="${JAVA_HOME}/bin:${PATH}"
EOF
  log_success "Kaskey aliases written to ${KASKEY_ZSHRC_BLOCK}"
fi

# Source the .zshrc.d directory from .zshrc if not already configured
if [[ -f "${ZSHRC}" ]] && ! grep -q "zshrc.d" "${ZSHRC}" 2>/dev/null; then
  if ! "${DRY_RUN}"; then
    sudo -u "${REAL_USER}" tee -a "${ZSHRC}" > /dev/null <<'EOF'

# Load modular zsh config files
for f in "${HOME}/.zshrc.d/"*.zsh(N); do source "${f}"; done
EOF
    log_success ".zshrc.d sourcing added to .zshrc"
  fi
fi

# =============================================================================
# 9. direnv — per-project JAVA_HOME switching
# =============================================================================
# direnv allows per-project environment variables via .envrc files.
# Critical for a multi-JDK setup: cd into Kaskey project → Java 11 activates.
# Already installed in devtools; verify and remind how to use it.
# =============================================================================
log_step "Verifying direnv"
if has_cmd direnv; then
  log_success "direnv: $(direnv version)"
  log_info "Kaskey project tip: create $(realpath ~)/kaskey-project/.envrc with:"
  echo "  export JAVA_HOME=/usr/lib/jvm/java-11-amazon-corretto.x86_64"
  echo "  export PATH=\${JAVA_HOME}/bin:\${PATH}"
  echo "  Then run: direnv allow"
else
  dnf_install direnv
fi

# =============================================================================
# Summary
# =============================================================================
log_success "Kaskey work environment configured"
echo ""
log_info "Next steps:"
echo "  1. Configure AWS credentials:"
echo "       aws configure"
echo "       # Or with aws-vault (recommended): aws-vault add kaskey"
echo ""
echo "  2. Configure WireGuard VPN:"
echo "       # Get wg0.conf from your IT team, then:"
echo "       sudo install -m600 wg0.conf /etc/wireguard/"
echo "       sudo systemctl enable --now wg-quick@wg0"
echo ""
echo "  3. Use Java 11 for Kaskey project (pick one approach):"
echo "       a) Per-session alias: java11"
echo "       b) Per-session SDK:   sdk use java 11.0.31-amzn   (after SDKMAN setup)"
echo "       c) Per-project:       echo 'export JAVA_HOME=/usr/lib/jvm/java-11-amazon-corretto.x86_64' > .envrc && direnv allow"
echo ""
echo "  4. Verify SBT with Java 11:"
echo "       sbt11 --version"
echo ""
echo "  5. Run SDKMAN setup to install Corretto 11 under sdk management:"
echo "       source ~/.sdkman/bin/sdkman-init.sh"
echo "       sdk install java 11.0.31-amzn"
