#!/bin/bash
# ============================================================
# Universal KDE Setup - Works on any x86_64 hardware
# Run after a fresh EndeavourOS KDE install
# ============================================================

set -e

echo "==> Updating system..."
sudo pacman -Syu --noconfirm

# -------------------------------------------------------
# 1. KDE Plasma barebones
# -------------------------------------------------------
echo "==> Installing barebones KDE..."
sudo pacman -S --needed --noconfirm \
    plasma-desktop \
    kwin \
    kscreen \
    plasma-nm \
    plasma-pa \
    powerdevil \
    bluedevil \
    kde-gtk-config \
    breeze \
    breeze-gtk \
    breeze-icons \
    oxygen-sounds \
    xdg-desktop-portal \
    xdg-desktop-portal-kde \
    xdg-user-dirs \
    polkit-kde-agent \
    kwallet-pam \
    krunner \
    sddm \
    sddm-kcm

# -------------------------------------------------------
# 2. Apps
# -------------------------------------------------------
echo "==> Installing apps..."
sudo pacman -S --needed --noconfirm \
    kitty \
    dolphin \
    dolphin-plugins \
    spectacle

# -------------------------------------------------------
# 3. Audio
# -------------------------------------------------------
echo "==> Installing PipeWire..."
sudo pacman -S --needed --noconfirm \
    pipewire \
    pipewire-alsa \
    pipewire-pulse \
    pipewire-jack \
    wireplumber \
    gst-plugin-pipewire \
    libpulse

systemctl --user enable pipewire pipewire-pulse wireplumber || true

# -------------------------------------------------------
# 4. Networking
# -------------------------------------------------------
echo "==> Setting up networking..."
sudo pacman -S --needed --noconfirm \
    networkmanager \
    network-manager-applet \
    firewalld

sudo systemctl enable NetworkManager
sudo systemctl enable firewalld
sudo systemctl disable NetworkManager-wait-online.service || true

# -------------------------------------------------------
# 5. Fonts
# -------------------------------------------------------
echo "==> Installing fonts..."
sudo pacman -S --needed --noconfirm \
    noto-fonts \
    ttf-liberation \
    ttf-jetbrains-mono-nerd \
    cantarell-fonts

# -------------------------------------------------------
# 6. GPU drivers — auto-detected
# -------------------------------------------------------
echo "==> Detecting GPU..."

HAS_AMD_HW=false
HAS_NVIDIA_HW=false
HAS_INTEL_HW=false

lspci | grep -E "VGA|3D|Display" | grep -qiE "\bAMD\b|\bATI\b|Radeon" && HAS_AMD_HW=true
lspci | grep -E "VGA|3D|Display" | grep -qiE "\bNVIDIA\b" && HAS_NVIDIA_HW=true
lspci | grep -E "VGA|3D|Display" | grep -qiE "\bIntel\b" && HAS_INTEL_HW=true

GPU_VENDOR="unknown"
if [ "$HAS_AMD_HW" = "true" ] && [ "$HAS_NVIDIA_HW" = "false" ]; then
    GPU_VENDOR="amd"
elif [ "$HAS_NVIDIA_HW" = "true" ] && [ "$HAS_INTEL_HW" = "true" ] && [ "$HAS_AMD_HW" = "false" ]; then
    GPU_VENDOR="nvidia_hybrid"
elif [ "$HAS_NVIDIA_HW" = "true" ] && [ "$HAS_INTEL_HW" = "false" ] && [ "$HAS_AMD_HW" = "false" ]; then
    GPU_VENDOR="nvidia"
elif [ "$HAS_INTEL_HW" = "true" ] && [ "$HAS_NVIDIA_HW" = "false" ] && [ "$HAS_AMD_HW" = "false" ]; then
    GPU_VENDOR="intel"
elif [ "$HAS_AMD_HW" = "true" ] && [ "$HAS_NVIDIA_HW" = "true" ]; then
    GPU_VENDOR="amd"
fi

echo "    [DETECTED] $GPU_VENDOR"
echo "==> Installing GPU drivers..."

# Always install mesa base
sudo pacman -S --needed --noconfirm mesa libva-utils

case "$GPU_VENDOR" in
    amd)
        sudo pacman -S --needed --noconfirm \
            vulkan-radeon libva-mesa-driver mesa-vdpau radeontop
        ;;
    nvidia)
        KERNEL=$(uname -r)
        # Check if CachyOS repos are present — they use versioned nvidia packages
        if pacman -Sl cachyos &>/dev/null 2>&1; then
            echo "    [INFO] CachyOS repos detected — using versioned Nvidia packages."
            echo "    Available Nvidia versions:"
            pacman -Ss "^nvidia-[0-9]" 2>/dev/null | grep -E "cachyos.*nvidia-[0-9]" | \
                awk '{print "      " $1}' | head -6
            echo "    Installing latest available CachyOS Nvidia series..."
            # Try 580xx first, fall back to 550xx, then 535xx
            if pacman -Si cachyos/nvidia-580xx-dkms &>/dev/null 2>&1; then
                sudo pacman -S --needed --noconfirm \
                    nvidia-580xx-dkms nvidia-580xx-utils \
                    lib32-nvidia-580xx-utils opencl-nvidia-580xx nvidia-settings
            elif pacman -Si cachyos/nvidia-550xx-dkms &>/dev/null 2>&1; then
                sudo pacman -S --needed --noconfirm \
                    nvidia-550xx-dkms nvidia-550xx-utils \
                    lib32-nvidia-550xx-utils opencl-nvidia-550xx nvidia-settings
            else
                sudo pacman -S --needed --noconfirm \
                    nvidia-535xx-dkms nvidia-535xx-utils \
                    lib32-nvidia-535xx-utils opencl-nvidia-535xx nvidia-settings
            fi
        else
            # Standard Arch repos — use generic nvidia package
            if echo "$KERNEL" | grep -qE "cachyos|zen|tkg"; then
                sudo pacman -S --needed --noconfirm nvidia-dkms nvidia-utils lib32-nvidia-utils opencl-nvidia nvidia-settings
            else
                sudo pacman -S --needed --noconfirm nvidia nvidia-utils lib32-nvidia-utils opencl-nvidia nvidia-settings
            fi
        fi
        echo "    [INFO] Add nvidia_drm.modeset=1 to GRUB_CMDLINE_LINUX_DEFAULT for Wayland."
        ;;
    nvidia_hybrid)
        KERNEL=$(uname -r)
        sudo pacman -S --needed --noconfirm vulkan-intel intel-media-driver
        if pacman -Sl cachyos &>/dev/null 2>&1; then
            echo "    [INFO] CachyOS repos detected — using versioned Nvidia packages."
            if pacman -Si cachyos/nvidia-580xx-dkms &>/dev/null 2>&1; then
                sudo pacman -S --needed --noconfirm \
                    nvidia-580xx-dkms nvidia-580xx-utils \
                    lib32-nvidia-580xx-utils opencl-nvidia-580xx nvidia-settings
            elif pacman -Si cachyos/nvidia-550xx-dkms &>/dev/null 2>&1; then
                sudo pacman -S --needed --noconfirm \
                    nvidia-550xx-dkms nvidia-550xx-utils \
                    lib32-nvidia-550xx-utils opencl-nvidia-550xx nvidia-settings
            else
                sudo pacman -S --needed --noconfirm \
                    nvidia-535xx-dkms nvidia-535xx-utils \
                    lib32-nvidia-535xx-utils opencl-nvidia-535xx nvidia-settings
            fi
        else
            if echo "$KERNEL" | grep -qE "cachyos|zen|tkg"; then
                sudo pacman -S --needed --noconfirm nvidia-dkms nvidia-utils lib32-nvidia-utils opencl-nvidia nvidia-settings
            else
                sudo pacman -S --needed --noconfirm nvidia nvidia-utils lib32-nvidia-utils opencl-nvidia nvidia-settings
            fi
        fi
        if command -v yay &>/dev/null; then
            yay -S --needed --noconfirm envycontrol
        elif command -v paru &>/dev/null; then
            paru -S --needed --noconfirm envycontrol
        else
            echo "    [WARN] Install envycontrol manually: yay -S envycontrol && sudo envycontrol -s hybrid"
        fi
        if command -v envycontrol &>/dev/null; then
            # envycontrol looks for dracut-rebuild which doesn't exist on EndeavourOS
            # run it ignoring the initramfs error then rebuild manually
            sudo envycontrol -s hybrid 2>/dev/null || true
            sudo dracut --force 2>/dev/null || true
            echo "    [OK] envycontrol set to hybrid mode."
        fi
        ;;
    intel)
        sudo pacman -S --needed --noconfirm vulkan-intel intel-media-driver libva-intel-driver
        ;;
    *)
        echo "    [WARN] GPU not detected — only mesa installed."
        ;;
esac

# -------------------------------------------------------
# 7. Performance
# -------------------------------------------------------
echo "==> Installing performance tools..."
sudo pacman -S --needed --noconfirm \
    gamemode \
    lib32-gamemode

# -------------------------------------------------------
# 8. Snapshots
# -------------------------------------------------------
echo "==> Setting up snapper..."
sudo pacman -S --needed --noconfirm \
    snapper \
    snap-pac \
    grub-btrfs \
    inotify-tools

sudo snapper -c root create-config / || true
sudo mkdir -p /.snapshots

SNAPPER_CONF="/etc/snapper/configs/root"
if [ -f "$SNAPPER_CONF" ]; then
    sudo sed -i 's/^TIMELINE_LIMIT_HOURLY=.*/TIMELINE_LIMIT_HOURLY="3"/' "$SNAPPER_CONF"
    sudo sed -i 's/^TIMELINE_LIMIT_DAILY=.*/TIMELINE_LIMIT_DAILY="5"/' "$SNAPPER_CONF"
    sudo sed -i 's/^TIMELINE_LIMIT_WEEKLY=.*/TIMELINE_LIMIT_WEEKLY="0"/' "$SNAPPER_CONF"
    sudo sed -i 's/^TIMELINE_LIMIT_MONTHLY=.*/TIMELINE_LIMIT_MONTHLY="0"/' "$SNAPPER_CONF"
    sudo sed -i 's/^TIMELINE_LIMIT_YEARLY=.*/TIMELINE_LIMIT_YEARLY="0"/' "$SNAPPER_CONF"
    sudo sed -i 's/^NUMBER_LIMIT=.*/NUMBER_LIMIT="10"/' "$SNAPPER_CONF"
    sudo sed -i 's/^NUMBER_LIMIT_IMPORTANT=.*/NUMBER_LIMIT_IMPORTANT="5"/' "$SNAPPER_CONF"
fi

sudo systemctl enable --now snapper-timeline.timer
sudo systemctl enable --now snapper-cleanup.timer
sudo systemctl enable --now grub-btrfsd.service

# -------------------------------------------------------
# 9. System tweaks
# -------------------------------------------------------
echo "==> Applying system tweaks..."

# ZRAM
sudo tee /etc/zram-generator.conf > /dev/null << EOF
[zram0]
zram-size = ram / 4
compression-algorithm = zstd
EOF

# Swappiness
echo "vm.swappiness=10" | sudo tee /etc/sysctl.d/99-swappiness.conf > /dev/null

# THP
sudo tee /etc/tmpfiles.d/thp.conf > /dev/null << EOF
w /sys/kernel/mm/transparent_hugepage/enabled - - - - madvise
w /sys/kernel/mm/transparent_hugepage/defrag  - - - - madvise
EOF

# Systemd timeout
sudo sed -i 's/^#DefaultTimeoutStartSec=.*/DefaultTimeoutStartSec=10s/' \
    /etc/systemd/system.conf

# Disable Baloo
balooctl6 disable 2>/dev/null || true

# Weekly fstrim
sudo systemctl enable fstrim.timer

# -------------------------------------------------------
# 10. Fastfetch
# -------------------------------------------------------
sudo pacman -S --needed --noconfirm fastfetch

# -------------------------------------------------------
# 11. Run debloat (optional)
# -------------------------------------------------------
# Look for kde-debloat.sh in same folder as this script,
# then fall back to ~/Downloads
DEBLOAT_SCRIPT="$(dirname "$0")/kde-debloat.sh"
if [ ! -f "$DEBLOAT_SCRIPT" ]; then
    DEBLOAT_SCRIPT="$HOME/Downloads/kde-debloat.sh"
fi

if [ -f "$DEBLOAT_SCRIPT" ]; then
    echo -n "==> kde-debloat.sh found. Run it now? [y/N]: "
    read -r RUN_DEBLOAT
    if [[ "$RUN_DEBLOAT" =~ ^[Yy]$ ]]; then
        bash "$DEBLOAT_SCRIPT"
    else
        echo "    [SKIP] Run kde-debloat.sh manually when ready."
    fi
else
    echo "==> kde-debloat.sh not found — run it manually after reboot."
    echo "    Expected locations:"
    echo "      Same folder as this script"
    echo "      ~/Downloads/kde-debloat.sh"
fi

echo ""
echo "=============================================="
echo " Universal setup complete! Reboot when ready."
echo "=============================================="
