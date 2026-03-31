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
# 6. GPU drivers (covers AMD, Intel, basic Nvidia)
# -------------------------------------------------------
echo "==> Installing GPU drivers..."
sudo pacman -S --needed --noconfirm \
    mesa \
    vulkan-radeon \
    libva-mesa-driver \
    libva-utils

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
# 11. Run debloat
# -------------------------------------------------------
echo "==> Running debloat..."
bash ~/kde-debloat.sh

echo ""
echo "=============================================="
echo " Universal setup complete! Reboot when ready."
echo "=============================================="
