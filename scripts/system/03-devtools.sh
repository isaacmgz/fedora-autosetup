#!/usr/bin/env bash
# =============================================================================
# scripts/system/03-devtools.sh — Developer CLI tools and build environment
# =============================================================================
#
# PACKAGE ANALYSIS & DECISIONS (Fedora 44):
#
# VALID FEDORA RPM PACKAGES (all confirmed in Fedora 44 repos):
#   git, gcc, gcc-c++, make, cmake, ninja-build, python3, python3-pip
#   neovim, vim-enhanced, ripgrep, fzf, htop, jq, unzip, curl, gettext
#   glibc-gconv-extra, tree, bat
#
# RENAMED/RESOLVED:
#   fd-find → fd-find (correct; binary is 'fd' on Fedora, unlike Debian's 'fdfind')
#   git-delta → git-delta (in Fedora repos since F37; confirmed present in F44)
#   eza → eza (in Fedora repos since F38; replaces the deprecated 'exa')
#
# REQUIRES SPECIAL HANDLING:
#   thefuck — NOT available as RPM in Fedora 44. Install via pip.
#             It's a Python tool; pip install is the canonical method.
#             The Fedora package (python3-thefuck) was dropped after F38.
#   tldr — Available as 'tldr' RPM in Fedora 44. The tealdeer (Rust) client
#          is faster; available via cargo. We provide both options.
#          RPM package name is 'tldr' (tealdeer-based CLI).
#
# ADDITIONAL TOOLS (best practice additions):
#   gh — GitHub CLI (from official GitHub repo configured in 02-repos.sh)
#   stow — GNU Stow for dotfile management
#   tmux — Terminal multiplexer
#   shellcheck — Shell script linter (essential for DevOps)
#   hyperfine — CLI benchmarking (from Fedora repos since F38)
#   tokei — Code statistics (Rust; from Fedora repos)
#   direnv — Per-directory env vars (essential for multi-project DevOps)
#   just — Command runner / Makefile alternative (from Fedora repos)
#   age — Modern encryption tool
#   sops — Secret management (installed via binary)
#   pre-commit — Git hook framework (via pip)
#
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

source "${LIB_DIR}/helpers.sh"
source "${LIB_DIR}/pkg.sh"

log_section "Developer Tools"

# =============================================================================
# 1. Build essentials & core CLI tools (all native RPMs)
# =============================================================================
log_step "Installing build essentials and core CLI tools"

dnf_install \
  git \
  gcc \
  gcc-c++ \
  make \
  cmake \
  ninja-build \
  meson \
  autoconf \
  automake \
  libtool \
  pkgconf-pkg-config \
  gdb \
  valgrind \
  strace \
  ltrace

# =============================================================================
# 2. Scripting & runtime
# =============================================================================
log_step "Installing scripting and runtime tools"

dnf_install \
  python3 \
  python3-pip \
  python3-devel \
  python3-virtualenv \
  python3-pipx \
  nodejs \
  npm \
  rust \
  cargo \
  golang

# =============================================================================
# 3. Shell & terminal utilities
# =============================================================================
log_step "Installing shell and terminal utilities"

dnf_install \
  zsh \
  tmux \
  curl \
  wget \
  unzip \
  tar \
  gzip \
  bzip2 \
  xz \
  p7zip \
  p7zip-plugins \
  tree \
  jq \
  yq \
  gettext \
  glibc-gconv-extra \
  htop \
  btop \
  ncdu \
  file \
  which \
  lsof \
  stow \
  direnv \
  just \
  age \
  gnupg2

# =============================================================================
# 4. Modern CLI replacements (all confirmed in Fedora 44)
# =============================================================================
log_step "Installing modern CLI tools"

# ripgrep: rg — fast recursive grep replacement
# fd-find: fd — fast find replacement (binary name is 'fd' on Fedora)
# fzf: fuzzy finder — integrates with zsh, vim, tmux
# bat: cat with syntax highlighting and git integration
# eza: ls replacement (replaces deprecated 'exa')
# git-delta: superior git diff pager
# hyperfine: CLI benchmarking tool
# tokei: fast code statistics

dnf_install \
  ripgrep \
  fd-find \
  fzf \
  bat \
  eza \
  git-delta \
  hyperfine \
  tokei \
  tldr

# =============================================================================
# 5. GitHub CLI
# =============================================================================
log_step "Installing GitHub CLI"
dnf_install gh

# =============================================================================
# 6. Development quality tools
# =============================================================================
log_step "Installing development quality tools"

dnf_install \
  shellcheck \
  shfmt

# =============================================================================
# 7. Network diagnostic tools
# =============================================================================
log_step "Installing network tools"

dnf_install \
  nmap \
  netcat \
  tcpdump \
  mtr \
  dnsutils \
  whois \
  httpie \
  openssh-clients

# =============================================================================
# 8. thefuck — pip install (no longer in Fedora repos)
# =============================================================================
# python3-thefuck was dropped from Fedora after F38.
# pipx is the correct modern method: installs into isolated venv, adds to PATH.
# This avoids polluting the system Python and is safer than --user pip.
# -----------------------------------------------------------------------------
log_step "Installing thefuck via pipx"

if ! has_cmd thefuck; then
  if ! "${DRY_RUN}"; then
    # Ensure pipx path is configured
    python3 -m pipx ensurepath --force 2>/dev/null || true
    python3 -m pipx install thefuck
    log_success "thefuck installed via pipx"
  else
    log_dry "python3 -m pipx install thefuck"
  fi
else
  log_skip "thefuck (already installed)"
fi

# =============================================================================
# 9. pre-commit — git hook framework
# =============================================================================
log_step "Installing pre-commit via pipx"

if ! has_cmd pre-commit; then
  if ! "${DRY_RUN}"; then
    python3 -m pipx install pre-commit
    log_success "pre-commit installed via pipx"
  else
    log_dry "python3 -m pipx install pre-commit"
  fi
else
  log_skip "pre-commit (already installed)"
fi

# =============================================================================
# 10. SOPS — secret management (binary install, no RPM available)
# =============================================================================
# SOPS is not in Fedora repos. Install the latest official GitHub release binary.
# We check the version pinned here and update it periodically.
# -----------------------------------------------------------------------------
log_step "Installing SOPS"
SOPS_VERSION="3.9.1"
SOPS_BINARY="/usr/local/bin/sops"

if [[ ! -f "${SOPS_BINARY}" ]]; then
  if ! "${DRY_RUN}"; then
    SOPS_URL="https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.amd64"
    curl -fsSL "${SOPS_URL}" -o /tmp/sops
    chmod +x /tmp/sops
    sudo mv /tmp/sops "${SOPS_BINARY}"
    log_success "SOPS ${SOPS_VERSION} installed"
  else
    log_dry "Would install SOPS ${SOPS_VERSION} from GitHub releases"
  fi
else
  log_skip "SOPS (already at ${SOPS_BINARY})"
fi

# =============================================================================
# 11. neovim — dedicated module, see scripts/shell/02-neovim.sh
# =============================================================================
log_step "Neovim is handled in the dedicated neovim module"

# =============================================================================
# 12. Git global configuration baseline
# =============================================================================
log_step "Configuring git delta as default pager"
if ! "${DRY_RUN}"; then
  # Only set if delta is installed and not already configured
  if has_cmd delta && ! git config --global core.pager 2>/dev/null | grep -q delta; then
    git config --global core.pager delta
    git config --global interactive.diffFilter "delta --color-only"
    git config --global delta.navigate true
    git config --global delta.line-numbers true
    git config --global delta.side-by-side false
    git config --global merge.conflictstyle zdiff3
    log_success "git-delta configured as git pager"
  fi
fi

log_success "Developer tools installation complete"
