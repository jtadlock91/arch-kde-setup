#!/bin/bash
# ============================================================
# Personal Setup - AMD Ryzen 9 9900X + RX 9060 XT only
# Run AFTER kde-setup-universal.sh
# Zen 4/5 CPU required
# ============================================================

set -e

# Verify Zen 4/5
if ! /lib/ld-linux-x86-64.so.2 --help | grep -q "x86-64-v4 (supported)"; then
    echo "[ABORT] This CPU does not support x86-64-v4. Do not run this on non-Zen4/5 hardware."
    exit 1
fi

# -------------------------------------------------------
# 1. CachyOS repos
# -------------------------------------------------------
echo "==> Adding CachyOS repos..."
cd /tmp
curl -O https://mirror.cachyos.org/cachyos-repo.tar.xz
tar xvf cachyos-repo.tar.xz && cd cachyos-repo
sudo ./cachyos-repo.sh
cd ~
sudo pacman -Syu --noconfirm

# -------------------------------------------------------
# 2. CachyOS RC kernel
# -------------------------------------------------------
echo "==> Installing CachyOS RC kernel..."
sudo pacman -S --needed --noconfirm \
    linux-cachyos-rc \
    linux-cachyos-rc-headers
sudo grub-mkconfig -o /boot/grub/grub.cfg

# -------------------------------------------------------
# 3. AMD RDNA4 specific
# -------------------------------------------------------
echo "==> Applying AMD RX 9060 XT tweaks..."

grep -q "RADV_PERFTEST" /etc/environment 2>/dev/null || \
    echo "RADV_PERFTEST=gpl,nggc" | sudo tee -a /etc/environment > /dev/null
grep -q "mesa_glthread" /etc/environment 2>/dev/null || \
    echo "mesa_glthread=true" | sudo tee -a /etc/environment > /dev/null

# Force performance power level
sudo tee /etc/udev/rules.d/30-amdgpu-pm.rules > /dev/null << EOF
ACTION=="add", SUBSYSTEM=="drm", KERNEL=="card*", \
  ATTR{device/power_dpm_force_performance_level}="high"
EOF

# -------------------------------------------------------
# 4. Performance daemons
# -------------------------------------------------------
echo "==> Installing performance daemons..."
sudo pacman -S --needed --noconfirm \
    auto-cpufreq \
    irqbalance \
    zram-generator

sudo systemctl enable auto-cpufreq
sudo systemctl enable irqbalance

# ananicy-cpp from AUR
# NOTE: no --noconfirm here on purpose. AUR had a large orphaned-package
# supply-chain compromise in June 2026 ("Atomic Arch", 1,500+ packages).
# Letting paru/yay show the PKGBUILD diff before building is the one
# practical check that actually catches this — review it before confirming.
echo "[INFO] Installing ananicy-cpp from AUR — review the PKGBUILD shown before confirming."
if command -v paru &>/dev/null; then
    paru -S --needed ananicy-cpp
    sudo systemctl enable ananicy-cpp
elif command -v yay &>/dev/null; then
    yay -S --needed ananicy-cpp
    sudo systemctl enable ananicy-cpp
else
    echo "[WARN] No AUR helper found — install ananicy-cpp manually"
fi

# -------------------------------------------------------
# 5. BORE scheduler
# -------------------------------------------------------
if sysctl kernel.sched_bore &>/dev/null; then
    sudo tee /etc/sysctl.d/99-bore.conf > /dev/null << EOF
kernel.sched_bore = 1
kernel.sched_min_base_slice_ns = 2000000
EOF
    echo "[OK] BORE configured."
else
    echo "[SKIP] BORE not available — reboot into CachyOS kernel first."
fi

# -------------------------------------------------------
# 6. Claude Desktop + Cowork VM prerequisites
# -------------------------------------------------------
# Anthropic shipped an official Linux beta (June 30, 2026) — Ubuntu/
# Debian only, officially. aaddrick/claude-desktop-debian repackages
# that same official .deb for Arch via AUR (claude-desktop),
# rather than reconstructing the app from scratch. Cowork on Linux
# runs on a KVM-backed VM; installing the same stack proven working
# on the NixOS side (KVM, QEMU, libvirt, OVMF, virtiofsd) up front
# avoids re-solving that from scratch like the NixOS Cowork setup did.
echo ""
echo "==> [6] Installing Cowork VM prerequisites (KVM/QEMU/libvirt/OVMF)..."
sudo pacman -S --needed --noconfirm \
    qemu-desktop \
    libvirt \
    edk2-ovmf \
    virtiofsd \
    dnsmasq

sudo systemctl enable --now libvirtd
sudo usermod -aG kvm,libvirt "$USER"

# vhost_vsock — needed for Cowork's host↔guest communication,
# not always auto-loaded on demand
if ! grep -q "^vhost_vsock$" /etc/modules-load.d/*.conf 2>/dev/null; then
    echo "vhost_vsock" | sudo tee /etc/modules-load.d/vhost-vsock.conf > /dev/null
    sudo modprobe vhost_vsock 2>/dev/null || true
    echo "    [OK] vhost_vsock set to load at boot."
fi

echo ""
echo "==> Installing Claude Desktop from AUR (official build, community-packaged)..."
echo "    [INFO] Review the PKGBUILD shown before confirming."
if command -v paru &>/dev/null; then
    paru -S --needed claude-desktop
elif command -v yay &>/dev/null; then
    yay -S --needed claude-desktop
else
    echo "    [WARN] No AUR helper found — install claude-desktop manually"
fi
echo "    [NOTE] Log out/in (or reboot) for the kvm/libvirt group membership"
echo "    to take effect before Cowork will work."

echo ""
echo "=============================================="
echo " Personal setup complete!"
echo ""
echo " Next steps:"
echo "  - Reboot into CachyOS RC kernel"
echo "  - Set Curve Optimizer to -20 all core in BIOS"
echo "    (-40 causes instability under sustained kernel"
echo "    compilation on this 9900X — confirmed via testing)"
echo "  - Enable PBO in BIOS"
echo "  - Steam launch option: gamemoderun %command%"
echo "  - Verify AV1: vainfo | grep AV1"
echo "=============================================="
