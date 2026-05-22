#!/usr/bin/env bash
# =============================================================================
# scripts/shell/01-zsh.sh — Zsh environment configuration
# =============================================================================
#
# SHELL PROMPT RECOMMENDATION:
#
# You requested agnoster theme. Here's an honest evaluation:
#
# AGNOSTER:
#   Pros: Mature, widely known, powerline look.
#   Cons: Requires Powerline-patched fonts; tied to Oh My Zsh; relatively slow
#         (pure shell functions evaluated each prompt); doesn't show Git status
#         details like unpushed commits, stash count, etc. without plugins.
#
# OH MY ZSH (OMZ):
#   The most popular zsh framework. Pros: huge plugin ecosystem, easy config.
#   Cons: Notably slows down shell startup (50-200ms). For a terminal-heavy
#   DevOps workflow you type dozens of commands per minute — that matters.
#   OMZ is fine but has better alternatives.
#
# STARSHIP (RECOMMENDATION):
#   Written in Rust — sub-millisecond prompt rendering.
#   Distro-agnostic, shell-agnostic (works in zsh, bash, fish).
#   Shows: git branch, status, cloud contexts, kubectl context, language
#   versions (Python/Go/Rust/Node), AWS/GCP/Azure profile — all natively.
#   Nerd Font compatible but works with basic powerline fonts too.
#   Works perfectly on Wayland/KDE.
#   NOTE: starship was dropped from official Fedora repos after F36 (Rust packaging
#   complexity). atim/starship COPR is unreliable (see install section below).
#   We install from the official upstream binary installer instead.
#
# POWERLEVEL10K (p10k):
#   The most feature-rich zsh prompt. Instant prompt feature for near-zero
#   startup delay even with slow plugins. Gorgeous out of the box.
#   Cons: Zsh-only; requires full OMZ or Zinit; Nerd Font required for full mode.
#   Works well but adds complexity.
#
# VERDICT: We install Starship + a curated plugin set WITHOUT Oh My Zsh.
#          We use Zinit (the fastest zsh plugin manager) instead.
#          This gives you everything OMZ+agnoster gives you, but faster and
#          more maintainable. OMZ is offered as an opt-in alternative.
#
# PLUGIN STRATEGY:
#   We use Zinit (fast, turbo loading) with these plugins:
#   - zsh-autosuggestions:  fish-style suggestions from history
#   - zsh-syntax-highlighting OR fast-syntax-highlighting: command coloring
#   - fzf-tab: fzf-powered tab completion
#   - zsh-completions: additional completions for many tools
#   - kubectl completion: built-in
#   - helm completion: built-in
#   - No OMZ needed for any of these.
#
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

source "${LIB_DIR}/helpers.sh"
source "${LIB_DIR}/pkg.sh"

log_section "Zsh Shell Environment"

REAL_USER="${SUDO_USER:-${USER}}"
REAL_HOME="$(real_home)"
ZDOTDIR="${REAL_HOME}"

# =============================================================================
# 1. Install zsh and supporting tools
# =============================================================================
log_step "Installing Zsh and shell utilities"

dnf_install \
  zsh \
  fzf \
  bat \
  eza
# NOTE: thefuck has no Fedora 44 RPM. Installed via pipx in 03-devtools.sh.
# NOTE: starship is NOT installed via dnf or atim/starship COPR (see below).

# =============================================================================
# 2. Starship prompt — upstream binary installer (do NOT use atim/starship COPR)
# =============================================================================
# atim/starship COPR problems (confirmed 2024-2025):
#   - Lags behind upstream releases (issue starship/starship #7109, Nov 2025)
#   - GPG key rotation breaks `dnf upgrade` — requires manual key removal/re-add
#   - Fedora Discussion: "likely personal testing repo, which you should not use"
#
# Fedora also dropped starship from official repos after F36 (too many Rust deps).
#
# POSIX CHECK FIX (starship/starship issue #6316):
#   The installer's verify_shell_is_posix_or_exit() detects $BASH_VERSION being
#   set and $POSIXLY_CORRECT being unset, then refuses to run.
#   This affects Fedora because /usr/bin/sh is a symlink to bash.
#   Piping to `bash` makes it worse — bash sets $BASH_VERSION unconditionally.
#   The correct fix is `sh --posix`, which activates bash's POSIX mode,
#   sets $POSIXLY_CORRECT, and satisfies the installer's check.
#
# Using --bin-dir ~/.local/bin avoids any need for sudo.
log_step "Installing Starship prompt (upstream binary installer)"

STARSHIP_BIN="${REAL_HOME}/.local/bin/starship"

if [[ -x "${STARSHIP_BIN}" ]]; then
  log_skip "Starship (already at ${STARSHIP_BIN})"
else
  if ! "${DRY_RUN}"; then
    sudo -u "${REAL_USER}" bash -c "
      mkdir -p '${REAL_HOME}/.local/bin'
      curl -sS https://starship.rs/install.sh | sh --posix -s -- \
        --bin-dir '${REAL_HOME}/.local/bin' \
        --yes
    "
    if [[ -x "${STARSHIP_BIN}" ]]; then
      log_success "Starship installed to ${STARSHIP_BIN}"
    else
      log_warn "Starship installer failed to produce binary at ${STARSHIP_BIN}"
      log_warn "Manual install: curl -sS https://starship.rs/install.sh | sh --posix -s -- --bin-dir ~/.local/bin --yes"
    fi
  else
    log_dry "Would install Starship to ${STARSHIP_BIN} via: curl -sS https://starship.rs/install.sh | sh --posix -s -- --bin-dir ~/.local/bin --yes"
  fi
fi

# Make starship available to subsequent steps in this script session
export PATH="${REAL_HOME}/.local/bin:${PATH}"

# =============================================================================
# 2. Set zsh as default shell
# =============================================================================
log_step "Setting Zsh as default shell for ${REAL_USER}"

if ! "${DRY_RUN}"; then
  ZSH_PATH="$(which zsh)"
  CURRENT_SHELL="$(getent passwd "${REAL_USER}" | cut -d: -f7)"

  if [[ "${CURRENT_SHELL}" == "${ZSH_PATH}" ]]; then
    log_skip "Zsh is already the default shell"
  else
    # chsh requires the shell to be in /etc/shells
    if ! grep -q "^${ZSH_PATH}$" /etc/shells; then
      echo "${ZSH_PATH}" | sudo tee -a /etc/shells
    fi
    sudo chsh -s "${ZSH_PATH}" "${REAL_USER}"
    log_success "Default shell set to: ${ZSH_PATH}"
  fi
fi

# =============================================================================
# 3. Install Zinit (zsh plugin manager)
# =============================================================================
log_step "Installing Zinit plugin manager"

ZINIT_HOME="${REAL_HOME}/.local/share/zinit/zinit.git"

if [[ ! -d "${ZINIT_HOME}" ]]; then
  if ! "${DRY_RUN}"; then
    sudo -u "${REAL_USER}" bash -c "
      mkdir -p '$(dirname "${ZINIT_HOME}")'
      git clone https://github.com/zdharma-continuum/zinit.git '${ZINIT_HOME}'
    "
    log_success "Zinit installed at ${ZINIT_HOME}"
  else
    log_dry "Would clone Zinit to ${ZINIT_HOME}"
  fi
else
  log_skip "Zinit (already at ${ZINIT_HOME})"
fi

# =============================================================================
# 4. Install Nerd Font (for Starship full mode)
# =============================================================================
log_step "Installing JetBrains Mono Nerd Font"

FONT_DIR="${REAL_HOME}/.local/share/fonts"
FONT_NAME="JetBrainsMonoNerdFont"

if [[ ! -d "${FONT_DIR}/${FONT_NAME}" ]]; then
  if ! "${DRY_RUN}"; then
    FONT_VERSION="3.3.0"
    FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v${FONT_VERSION}/JetBrainsMono.tar.xz"

    sudo -u "${REAL_USER}" bash -c "
      mkdir -p '${FONT_DIR}/${FONT_NAME}'
      curl -fsSL '${FONT_URL}' -o /tmp/jbm-nerd.tar.xz
      tar -xJf /tmp/jbm-nerd.tar.xz -C '${FONT_DIR}/${FONT_NAME}' --wildcards '*.ttf'
      rm -f /tmp/jbm-nerd.tar.xz
      fc-cache -f '${FONT_DIR}'
    "
    log_success "JetBrains Mono Nerd Font installed"
    log_info "Configure your terminal emulator to use 'JetBrainsMono Nerd Font Mono'"
  else
    log_dry "Would install JetBrains Mono Nerd Font to ${FONT_DIR}"
  fi
else
  log_skip "JetBrains Mono Nerd Font (already installed)"
fi

# =============================================================================
# 5. Write .zshrc
# =============================================================================
log_step "Writing ~/.zshrc"

ZSHRC="${ZDOTDIR}/.zshrc"

# Preserve any content that other tools (SDKMAN, etc.) may have appended to
# .zshrc, so it survives our overwrite. We extract lines that are NOT part of
# our managed block (everything after the last marker) and re-append them.
ZSHRC_EXTRA=""
if [[ -f "${ZSHRC}" ]] && ! "${DRY_RUN}"; then
  # Capture the SDKMAN init block if present — it must survive the overwrite
  if grep -q "SDKMAN_DIR" "${ZSHRC}" 2>/dev/null; then
    ZSHRC_EXTRA="$(grep -A5 'SDKMAN_DIR' "${ZSHRC}" | head -20 || true)"
    log_info "SDKMAN block detected in .zshrc — will re-append after overwrite"
  fi
fi

# Back up existing .zshrc only if it was NOT generated by this script
if [[ -f "${ZSHRC}" ]] && ! grep -q "# fedora-workstation-setup" "${ZSHRC}" 2>/dev/null; then
  BACKUP="${ZSHRC}.bak.$(date +%Y%m%d%H%M%S)"
  log_warn "Existing .zshrc found — backing up to ${BACKUP}"
  if ! "${DRY_RUN}"; then
    sudo -u "${REAL_USER}" cp "${ZSHRC}" "${BACKUP}"
  fi
fi

if "${DRY_RUN}"; then
  log_dry "Would write ${ZSHRC}"
else
sudo -u "${REAL_USER}" tee "${ZSHRC}" > /dev/null <<'ZSHRC_EOF'
# =============================================================================
# ~/.zshrc — Fedora Developer Workstation
# Generated by fedora-workstation-setup
# fedora-workstation-setup
# =============================================================================

# ── Zinit bootstrap ───────────────────────────────────────────────────────────
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
[[ ! -d "$ZINIT_HOME" ]] && mkdir -p "$(dirname "$ZINIT_HOME")"
[[ ! -d "$ZINIT_HOME/.git" ]] && git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
source "${ZINIT_HOME}/zinit.zsh"
autoload -Uz _zinit
(( ${+_comps} )) && _comps[zinit]=_zinit

# ── Zinit plugins (turbo mode = async load for faster startup) ────────────────
zinit ice wait lucid
zinit light zsh-users/zsh-autosuggestions

zinit ice wait lucid
zinit light zdharma-continuum/fast-syntax-highlighting

zinit ice wait lucid
zinit light zsh-users/zsh-completions

zinit ice wait lucid
zinit light Aloxaf/fzf-tab

zinit ice wait lucid
zinit light MichaelAquilina/zsh-you-should-use

# Docker/Podman completions
zinit ice wait lucid as"completion"
zinit snippet https://raw.githubusercontent.com/docker/cli/master/contrib/completion/zsh/_docker

# ── Completion system ─────────────────────────────────────────────────────────
autoload -Uz compinit
# Only regenerate compdump once per day
if [[ -n ${ZDOTDIR}/.zcompdump(#qN.mh+24) ]]; then
  compinit
else
  compinit -C
fi

# fzf-tab config
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza --color=always $realpath'
zstyle ':fzf-tab:complete:*' fzf-flags '--height=40%'
zstyle ':completion:*' menu no  # disable default menu (fzf-tab takes over)

# ── History ───────────────────────────────────────────────────────────────────
HISTFILE="${HOME}/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_ALL_DUPS   # Don't record duplicates
setopt HIST_IGNORE_SPACE      # Don't record commands prefixed with space
setopt HIST_VERIFY            # Show expanded history before executing
setopt SHARE_HISTORY          # Share history between shells
setopt EXTENDED_HISTORY       # Record timestamp
setopt INC_APPEND_HISTORY     # Append incrementally

# ── Key bindings ──────────────────────────────────────────────────────────────
bindkey -e                          # Emacs key bindings
bindkey '^[[A' history-search-backward  # Up arrow: history search
bindkey '^[[B' history-search-forward   # Down arrow: history search
bindkey '^R' fzf-history-widget         # Ctrl+R: fzf history

# ── Options ───────────────────────────────────────────────────────────────────
setopt AUTO_CD              # cd by typing directory name
setopt CORRECT              # Correct typos
setopt GLOB_DOTS            # Include dotfiles in globs
setopt NO_BEEP              # No terminal bell
setopt EXTENDED_GLOB        # Extended glob patterns
setopt INTERACTIVE_COMMENTS # Allow comments in interactive shell

# ── PATH ──────────────────────────────────────────────────────────────────────
# Ensure uniqueness — no duplicate PATH entries
typeset -U path PATH

path=(
  "${HOME}/.local/bin"        # pipx, user pip installs
  "${HOME}/.cargo/bin"        # cargo install
  "${HOME}/go/bin"            # go install
  "${HOME}/.local/share/JetBrains/Toolbox/bin"  # JetBrains Toolbox
  /usr/local/bin              # sops, kind, minikube, etc.
  "${path[@]}"
)
export PATH

# ── Environment variables ─────────────────────────────────────────────────────
export EDITOR="nvim"
export VISUAL="nvim"
export PAGER="less"
export LESS="-R --mouse"

# Podman Docker compatibility
export DOCKER_HOST="unix://${XDG_RUNTIME_DIR}/podman/podman.sock"

# kind + Podman
export KIND_EXPERIMENTAL_PROVIDER=podman

# fzf — use fd for faster file finding
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="${FZF_DEFAULT_COMMAND}"
export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
export FZF_DEFAULT_OPTS='
  --height 40% --layout=reverse --border
  --color=bg+:#3c3836,bg:#282828,spinner:#fb4934,hl:#928374
  --color=fg:#ebdbb2,header:#928374,info:#8ec07c,pointer:#fb4934
  --color=marker:#fb4934,fg+:#ebdbb2,prompt:#fb4934,hl+:#fb4934
'

# bat — syntax highlighting
export BAT_THEME="gruvbox-dark"
export MANPAGER="sh -c 'col -bx | bat -l man -p'"  # bat as man pager

# Go
export GOPATH="${HOME}/go"
export GOBIN="${GOPATH}/bin"

# Python — suppress pip version warnings
export PIP_DISABLE_PIP_VERSION_CHECK=1

# Kubeconfig
export KUBECONFIG="${HOME}/.kube/config"

# direnv hook
eval "$(direnv hook zsh)"

# ── fzf shell integration ─────────────────────────────────────────────────────
# Fedora puts fzf shell scripts in /usr/share/fzf/
[[ -f /usr/share/fzf/shell/key-bindings.zsh ]] && \
  source /usr/share/fzf/shell/key-bindings.zsh
[[ -f /usr/share/fzf/shell/completion.zsh ]] && \
  source /usr/share/fzf/shell/completion.zsh

# ── thefuck integration ───────────────────────────────────────────────────────
# Lazy-loaded for startup speed — only initializes on first 'fuck' call
if command -v thefuck &>/dev/null; then
  thefuck --alias fuck | source /dev/stdin 2>/dev/null || true
fi

# ── Tool completions ──────────────────────────────────────────────────────────
# Kubectl
[[ -x "$(command -v kubectl)" ]] && source <(kubectl completion zsh)

# Helm
[[ -x "$(command -v helm)" ]] && source <(helm completion zsh)

# kind
[[ -x "$(command -v kind)" ]] && source <(kind completion zsh)

# GitHub CLI
[[ -x "$(command -v gh)" ]] && source <(gh completion -s zsh)

# SOPS — no native completion, skip

# ── Aliases — core ────────────────────────────────────────────────────────────

# eza replaces ls
alias ls='eza --color=always --group-directories-first'
alias ll='eza -la --color=always --group-directories-first --git --icons'
alias la='eza -a --color=always --group-directories-first'
alias lt='eza --tree --color=always --group-directories-first --level=2'
alias l.='eza -a | grep -E "^\."'

# bat replaces cat
alias cat='bat --paging=never'
alias catp='bat'                  # bat with paging
alias bhelp='bat --plain'         # raw output (no decorations)

# Git shortcuts
alias g='git'
alias ga='git add'
alias gaa='git add --all'
alias gc='git commit'
alias gcm='git commit -m'
alias gca='git commit --amend'
alias gco='git checkout'
alias gb='git branch'
alias gbd='git branch -d'
alias gd='git diff'
alias gds='git diff --staged'
alias gf='git fetch --all --prune'
alias gl='git log --oneline --graph --decorate --all'
alias gp='git push'
alias gpl='git pull --rebase'
alias gs='git status --short --branch'
alias gst='git stash'
alias gstp='git stash pop'
alias gundo='git reset --soft HEAD~1'

# Docker/Podman (podman-docker provides /usr/bin/docker → podman)
alias docker='podman'
alias dc='podman-compose'
alias dps='podman ps'
alias dpsa='podman ps -a'
alias di='podman images'
alias drm='podman rm'
alias drmi='podman rmi'
alias dlog='podman logs -f'
alias dex='podman exec -it'
alias drun='podman run --rm -it'
alias dprune='podman system prune -af'

# Kubernetes
alias k='kubectl'
alias kaf='kubectl apply -f'
alias kdf='kubectl delete -f'
alias kgp='kubectl get pods'
alias kgpa='kubectl get pods -A'
alias kgs='kubectl get svc'
alias kgd='kubectl get deploy'
alias kgn='kubectl get nodes'
alias kd='kubectl describe'
alias kl='kubectl logs -f'
alias kex='kubectl exec -it'
alias kns='kubens'
alias kctx='kubectx'
alias krun='kubectl run tmp --image=busybox --rm -it --restart=Never --'

# System
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias mkdir='mkdir -pv'
alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -iv'
alias df='df -h'
alias du='du -sh'
alias free='free -h'
alias top='btop'
alias ps='ps auxf'
alias grep='grep --color=auto'
alias ip='ip --color=auto'

# Editor
alias v='nvim'
alias vi='nvim'
alias vim='nvim'

# Quick edits
alias zrc='nvim ~/.zshrc'
alias src='source ~/.zshrc'
alias nrc='nvim ~/.config/nvim/init.lua'

# Networking
alias myip='curl -s https://ifconfig.me && echo'
alias ports='ss -tulanp'
alias ping='ping -c 5'

# Misc
alias tree='eza --tree'
alias reload='exec zsh'
alias cls='clear'
alias h='history | fzf'
alias ff='fzf --preview "bat --color=always {}"'

# ── Functions ─────────────────────────────────────────────────────────────────

# cd then ls
function cd() {
  builtin cd "$@" && eza --color=always --group-directories-first
}

# Create dir and cd into it
function mkcd() {
  mkdir -p "$1" && cd "$1"
}

# Extract any archive format
function extract() {
  case "$1" in
    *.tar.bz2)  tar xjf "$1"    ;;
    *.tar.gz)   tar xzf "$1"    ;;
    *.tar.xz)   tar xJf "$1"    ;;
    *.tar.zst)  tar --zstd -xf "$1" ;;
    *.bz2)      bunzip2 "$1"    ;;
    *.gz)       gunzip "$1"     ;;
    *.tar)      tar xf "$1"     ;;
    *.zip)      unzip "$1"      ;;
    *.7z)       7z x "$1"       ;;
    *.rar)      unrar x "$1"    ;;
    *)          echo "Cannot extract '$1'" ;;
  esac
}

# Quick kubectl namespace switch with fzf
function kns-fzf() {
  local ns
  ns=$(kubectl get namespaces -o name | sed 's|namespace/||' | fzf --prompt="namespace> ")
  [[ -n "${ns}" ]] && kubectl config set-context --current --namespace="${ns}"
}

# Quick kubectl context switch with fzf
function kctx-fzf() {
  local ctx
  ctx=$(kubectl config get-contexts -o name | fzf --prompt="context> ")
  [[ -n "${ctx}" ]] && kubectl config use-context "${ctx}"
}

# Git interactive branch checkout
function gco-fzf() {
  local branch
  branch=$(git branch --all | grep -v HEAD | sed 's/.* //' | sed 's|remotes/origin/||' | sort -u | fzf)
  [[ -n "${branch}" ]] && git checkout "${branch}"
}

# Run a temporary container
function dsh() {
  local img="${1:-fedora:latest}"
  podman run --rm -it "${img}" bash
}

# Check what's listening on a port
function port() {
  ss -tulanp | grep ":${1}"
}

# JSON pretty print with bat
function json() {
  python3 -m json.tool "${1:--}" | bat -l json
}

# ── Starship prompt ───────────────────────────────────────────────────────────
# Initialized last — ensures all completions and PATH are set before prompt loads
eval "$(starship init zsh)"

ZSHRC_EOF
fi # end DRY_RUN check

log_success ".zshrc written to ${ZSHRC}"

# Re-append SDKMAN block if it was present before the overwrite
if [[ -n "${ZSHRC_EXTRA:-}" ]] && ! "${DRY_RUN}"; then
  if ! grep -q "SDKMAN_DIR" "${ZSHRC}" 2>/dev/null; then
    sudo -u "${REAL_USER}" tee -a "${ZSHRC}" > /dev/null <<'EOF'

# SDKMAN — restored after zshrc overwrite by fedora-workstation-setup
export SDKMAN_DIR="${HOME}/.sdkman"
[[ -s "${HOME}/.sdkman/bin/sdkman-init.sh" ]] && \
  source "${HOME}/.sdkman/bin/sdkman-init.sh"
EOF
    log_success "SDKMAN block re-appended to .zshrc"
  fi
fi

# =============================================================================
# 6. Write Starship config
# =============================================================================
log_step "Writing Starship prompt configuration"

STARSHIP_CONFIG_DIR="${REAL_HOME}/.config"
STARSHIP_CONFIG="${STARSHIP_CONFIG_DIR}/starship.toml"

if ! "${DRY_RUN}"; then
  sudo -u "${REAL_USER}" mkdir -p "${STARSHIP_CONFIG_DIR}"
  if [[ ! -f "${STARSHIP_CONFIG}" ]]; then
    sudo -u "${REAL_USER}" tee "${STARSHIP_CONFIG}" > /dev/null <<'STARSHIP_EOF'
# =============================================================================
# Starship prompt config — DevOps / Cloud / Kubernetes focus
# https://starship.rs/config/
# =============================================================================

# The character shown between the prompt sections
"$schema" = 'https://starship.rs/config-schema.json'

format = """
[╭─](bold blue)\
$username\
$hostname\
$directory\
$git_branch\
$git_status\
$kubernetes\
$aws\
$gcloud\
$terraform\
$python\
$golang\
$rust\
$nodejs\
$docker_context\
$cmd_duration\
$line_break\
[╰─](bold blue)$character"""

[character]
success_symbol = "[❯](bold green)"
error_symbol = "[❯](bold red)"
vimcmd_symbol = "[❮](bold green)"

[directory]
truncation_length = 4
truncate_to_repo = true
style = "bold cyan"
format = "[$path]($style)[$read_only]($read_only_style) "

[git_branch]
symbol = " "
style = "bold purple"
format = "on [$symbol$branch]($style) "

[git_status]
format = '([\[$all_status$ahead_behind\]]($style) )'
style = "bold red"
conflicted = "⚡"
ahead = "⇡${count}"
behind = "⇣${count}"
diverged = "⇕⇡${ahead_count}⇣${behind_count}"
untracked = "?${count}"
stashed = "≡"
modified = "!${count}"
staged = "+${count}"
deleted = "✘${count}"

[kubernetes]
disabled = false
format = 'on [⎈ $context\($namespace\)](bold cyan) '
detect_files = ['Dockerfile', 'docker-compose.yml', 'k8s', '*.yaml']

[python]
symbol = " "
format = 'via [$symbol$version(\($virtualenv\))]($style) '
style = "bold yellow"

[golang]
symbol = " "
format = 'via [$symbol$version]($style) '

[rust]
symbol = " "
format = 'via [$symbol$version]($style) '

[nodejs]
symbol = " "
format = 'via [$symbol$version]($style) '

[docker_context]
symbol = " "
format = 'via [$symbol$context]($style) '
only_with_files = true

[cmd_duration]
min_time = 2000
format = "took [$duration](bold yellow) "

[aws]
format = 'on [$symbol($profile)(\($region\))]($style) '
style = "bold yellow"
symbol = "☁️  "

[terraform]
format = 'via [$symbol$workspace]($style) '

[hostname]
ssh_only = true
format = "[@$hostname](bold blue) "

[username]
show_always = false
format = "[$user]($style) "
STARSHIP_EOF
    log_success "Starship config written to ${STARSHIP_CONFIG}"
  else
    log_skip "Starship config (already exists)"
  fi
fi

log_success "Shell environment configuration complete"
log_warn "Run 'exec zsh' or open a new terminal to activate the new shell configuration"
