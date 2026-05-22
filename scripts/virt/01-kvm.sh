#!/usr/bin/env bash
# =============================================================================
# scripts/virt/01-kvm.sh — KVM/libvirt virtualization setup
# =============================================================================
#
# ARCHITECTURE DECISIONS:
#
# WAYLAND + KVM:
#   virt-manager uses GTK3 which has good Wayland support via XDG_SESSION_TYPE.
#   On Fedora 44 with Plasma 6/Wayland, virt-manager runs fine via XWayland
#   if native Wayland support is missing, but modern GTK3 apps use ozone.
#   virt-viewer (for VM display) supports Spice/VNC which works on Wayland.
#   No special workarounds are needed on Fedora 44.
#
# GNOME BOXES vs virt-manager:
#   GNOME Boxes — simpler UI, good for casual VM use, limited configuration.
#   virt-manager — full control over CPU topology, network, storage, PCIe passthrough.
#   For a DevOps/systems engineering workstation, virt-manager is unambiguously better.
#   We install virt-manager; Boxes is NOT installed (different GNOME stack, KDE conflict).
#
# bridge-utils:
#   Not required for basic KVM usage. libvirt creates its own virbr0 NAT bridge
#   automatically. bridge-utils is only needed if you want to create a host bridge
#   manually (for bridged networking). We include it as it's lightweight.
#
# NESTED VIRTUALIZATION:
#   Relevant if you plan to run VMs inside VMs (e.g., testing Kubernetes clusters
#   with kubeadm inside a VM). Check with: cat /sys/module/kvm_intel/parameters/nested
#   Enable with: options kvm_intel nested=1 in /etc/modprobe.d/kvm.conf
#   We enable it if hardware supports it.
#
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

source "${LIB_DIR}/helpers.sh"
source "${LIB_DIR}/checks.sh"
source "${LIB_DIR}/pkg.sh"

log_section "KVM / libvirt Virtualization"

REAL_USER="${SUDO_USER:-${USER}}"

# =============================================================================
# 1. Verify hardware virtualization
# =============================================================================
log_step "Checking hardware virtualization support"

if ! check_virt_support; then
  log_warn "Hardware virtualization not supported or not enabled."
  log_warn "KVM packages will be installed but KVM will not function."
  log_warn "Enable VT-x/AMD-V in your BIOS/UEFI to use KVM."
  confirm "Continue installing KVM packages anyway?" || return 0
fi

# Detect CPU vendor for module-specific config
CPU_VENDOR=""
if grep -q "Intel" /proc/cpuinfo 2>/dev/null; then
  CPU_VENDOR="intel"
elif grep -q "AMD" /proc/cpuinfo 2>/dev/null; then
  CPU_VENDOR="amd"
fi
log_info "CPU vendor: ${CPU_VENDOR:-unknown}"

# =============================================================================
# 2. Install KVM/QEMU and libvirt
# =============================================================================
log_step "Installing KVM/QEMU/libvirt stack"

# qemu-kvm: KVM-enabled QEMU binary
# libvirt: virtualization API/daemon
# virt-manager: GTK GUI for libvirt
# virt-install: CLI VM installation tool
# virt-viewer: Spice/VNC display client
# libvirt-client: virsh and related tools
# libguestfs-tools: VM disk inspection tools
# bridge-utils: brctl for manual bridge configuration
# edk2-ovmf: UEFI firmware for VMs (required for Secure Boot, modern OSes)

dnf_install \
  qemu-kvm \
  libvirt \
  libvirt-client \
  libvirt-daemon-config-network \
  libvirt-daemon-kvm \
  virt-manager \
  virt-install \
  virt-viewer \
  bridge-utils \
  edk2-ovmf \
  libguestfs-tools-c \
  python3-libvirt

# =============================================================================
# 3. Enable and start libvirtd
# =============================================================================
log_step "Enabling libvirtd service"

if ! "${DRY_RUN}"; then
  # Use socket-activated libvirtd (modern Fedora approach — not monolithic daemon)
  sudo systemctl enable --now libvirtd.socket
  sudo systemctl enable --now libvirtd-ro.socket
  sudo systemctl enable --now libvirtd-admin.socket

  # Ensure the default network is active
  if sudo virsh net-info default &>/dev/null; then
    if ! sudo virsh net-info default | grep -q "Active:.*yes"; then
      # Suppress "network is already active" — harmless race condition
      sudo virsh net-start default 2>/dev/null || true
    fi
    if ! sudo virsh net-info default | grep -q "Autostart:.*yes"; then
      sudo virsh net-autostart default 2>/dev/null || true
    fi
  else
    log_warn "Default libvirt network not found — run 'sudo virsh net-define /usr/share/libvirt/networks/default.xml'"
  fi
  log_success "libvirtd socket and default network configured"
fi

# =============================================================================
# 4. User group membership
# =============================================================================
log_step "Adding ${REAL_USER} to libvirt and kvm groups"

add_user_to_group libvirt
add_user_to_group kvm

# =============================================================================
# 5. libvirt polkit rules (allow user management without sudo)
# =============================================================================
# Modern libvirt uses polkit for authorization. Adding the user to the libvirt
# group is usually sufficient on Fedora, but we add an explicit rule for clarity.
log_step "Configuring polkit rules for libvirt"

POLKIT_RULE="/etc/polkit-1/rules.d/80-libvirt.rules"
if [[ ! -f "${POLKIT_RULE}" ]]; then
  if ! "${DRY_RUN}"; then
    sudo tee "${POLKIT_RULE}" > /dev/null <<'EOF'
/* Allow users in the libvirt group to manage VMs without password prompts */
polkit.addRule(function(action, subject) {
  if (action.id == "org.libvirt.unix.manage" &&
      subject.isInGroup("libvirt")) {
    return polkit.Result.YES;
  }
});
EOF
    log_success "polkit rule for libvirt created"
  else
    log_dry "Would create ${POLKIT_RULE}"
  fi
else
  log_skip "${POLKIT_RULE} (already exists)"
fi

# =============================================================================
# 6. Nested virtualization (optional but useful for K8s in VM)
# =============================================================================
log_step "Configuring nested virtualization"

if [[ -n "${CPU_VENDOR}" ]]; then
  KVM_MODULE="kvm_${CPU_VENDOR}"
  KVM_CONF="/etc/modprobe.d/kvm.conf"

  if [[ ! -f "${KVM_CONF}" ]]; then
    if ! "${DRY_RUN}"; then
      sudo tee "${KVM_CONF}" > /dev/null <<EOF
# Enable nested virtualization for KVM (${CPU_VENDOR} CPUs)
# Required for running VMs inside VMs (e.g. Kubernetes nodes in a VM)
options ${KVM_MODULE} nested=1
EOF
      log_success "Nested virtualization enabled in ${KVM_CONF}"
      log_warn "Reboot required for nested virtualization to take effect"
    else
      log_dry "Would create ${KVM_CONF} with nested=1 for ${KVM_MODULE}"
    fi
  else
    log_skip "${KVM_CONF} (already exists)"
  fi
else
  log_warn "Unknown CPU vendor — skipping nested virtualization config"
fi

# =============================================================================
# 7. Verification
# =============================================================================
log_step "Verifying KVM setup"
if ! "${DRY_RUN}"; then
  if [[ -e /dev/kvm ]]; then
    log_success "/dev/kvm exists — KVM is functional"
  else
    log_warn "/dev/kvm not found — KVM may not be available"
  fi

  if has_cmd virsh; then
    log_success "virsh: $(virsh --version)"
  fi
fi

log_success "KVM/libvirt setup complete"
log_warn "You must log out and back in for group memberships (libvirt, kvm) to take effect"
