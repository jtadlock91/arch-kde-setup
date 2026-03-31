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
if command -v paru &>/dev/null; then
    paru -S --needed --noconfirm ananicy-cpp
    sudo systemctl enable ananicy-cpp
elif command -v yay &>/dev/null; then
    yay -S --needed --noconfirm ananicy-cpp
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

echo ""
echo "=============================================="
echo " Personal setup complete!"
echo ""
echo " Next steps:"
echo "  - Reboot into CachyOS RC kernel"
echo "  - Set Curve Optimizer to -40 all core in BIOS"
echo "  - Enable PBO in BIOS"
echo "  - Steam launch option: gamemoderun %command%"
echo "  - Verify AV1: vainfo | grep AV1"
echo "=============================================="
