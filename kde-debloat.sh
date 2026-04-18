#!/bin/bash
# ============================================================
# KDE Debloat Script
# Arch Linux / EndeavourOS / CachyOS
# ============================================================
# Strips the full KDE app suite down to a clean barebones
# Plasma 6 desktop on Wayland. Works on any Arch-based distro
# with a standard KDE Plasma install.
#
# Keeps:
#   - KDE Plasma desktop (core only)
#   - Dolphin, KRunner, Kitty, Spectacle, Klipper
#   - Steam, Vivaldi (untouched if installed)
#   - PipeWire audio stack
#   - NetworkManager + firewalld
#   - SDDM login manager
#   - Mesa/Vulkan GPU drivers
#   - Performance tools (gamemode, auto-cpufreq, ananicy-cpp)
#   - Snapshot tools (snapper, snap-pac, grub-btrfs)
#
# Removes:
#   - All KDE bloat apps (games, PIM/Akonadi, education, etc.)
#   - All EndeavourOS-specific packages if present
#   - Unused X11/Xorg packages not needed on Wayland
#
# Also removes EndeavourOS-specific packages if present
# (safe to run even if already removed or on plain Arch)
#
# SAFETY FEATURES:
#   - Pre-flight check before touching anything
#   - Protected package list (never removed, ever)
#   - Orphan cleanup skips protected packages
#   - Post-removal verification with auto-reinstall
#   - Aborts immediately if anything critical is missing
#
# REQUIREMENTS:
#   - Arch Linux, EndeavourOS, CachyOS or any Arch-based distro
#   - KDE Plasma 6 already installed
#   - Wayland session (X11 users: remove xorg packages from
#     the BLOAT list before running)
#   - AMD GPU (Nvidia users: replace vulkan-radeon/mesa entries
#     in PROTECTED list with your driver packages)
#
# USAGE:
#   chmod +x kde-debloat.sh
#   ./kde-debloat.sh
#
# Run the barebones install script first if starting fresh,
# then reboot before running this script.
# ============================================================

set -e

# -------------------------------------------------------
# GPU DETECTION
# Uses lspci as ground truth for hardware, then checks
# installed packages to build the protected list.
# -------------------------------------------------------
echo "==> [GPU DETECT] Identifying GPU hardware..."

HAS_AMD_HW=false
HAS_NVIDIA_HW=false
HAS_INTEL_HW=false

# Detect hardware via lspci — ground truth
lspci | grep -E "VGA|3D|Display" | grep -qiE "\bAMD\b|\bATI\b|Radeon" && HAS_AMD_HW=true
lspci | grep -E "VGA|3D|Display" | grep -qiE "\bNVIDIA\b" && HAS_NVIDIA_HW=true
lspci | grep -E "VGA|3D|Display" | grep -qiE "\bIntel\b" && HAS_INTEL_HW=true

echo "    Hardware detected:"
$HAS_AMD_HW   && echo "      - AMD/ATI GPU"
$HAS_NVIDIA_HW && echo "      - Nvidia GPU"
$HAS_INTEL_HW  && echo "      - Intel GPU"

# Determine GPU vendor based purely on hardware
GPU_VENDOR="unknown"
if [ "$HAS_AMD_HW" = "true" ] && [ "$HAS_NVIDIA_HW" = "false" ]; then
    GPU_VENDOR="amd"
    echo "    [GPU] AMD (dedicated)"
elif [ "$HAS_NVIDIA_HW" = "true" ] && [ "$HAS_INTEL_HW" = "true" ] && [ "$HAS_AMD_HW" = "false" ]; then
    GPU_VENDOR="nvidia_hybrid"
    echo "    [GPU] Nvidia + Intel hybrid"
elif [ "$HAS_NVIDIA_HW" = "true" ] && [ "$HAS_INTEL_HW" = "false" ] && [ "$HAS_AMD_HW" = "false" ]; then
    GPU_VENDOR="nvidia"
    echo "    [GPU] Nvidia (dedicated)"
elif [ "$HAS_INTEL_HW" = "true" ] && [ "$HAS_NVIDIA_HW" = "false" ] && [ "$HAS_AMD_HW" = "false" ]; then
    GPU_VENDOR="intel"
    echo "    [GPU] Intel (integrated only)"
elif [ "$HAS_AMD_HW" = "true" ] && [ "$HAS_NVIDIA_HW" = "true" ]; then
    GPU_VENDOR="amd"
    echo "    [GPU] AMD + Nvidia hybrid — protecting AMD drivers"
else
    echo "    [WARN] Could not detect GPU — defaulting to mesa only"
    GPU_VENDOR="unknown"
fi

# Build GPU-specific protected packages
GPU_PROTECTED=()
case "$GPU_VENDOR" in
    amd)
        GPU_PROTECTED=(
            mesa
            vulkan-radeon
            libva-mesa-driver
            mesa-vdpau
            libva-utils
        )
        ;;
    nvidia|nvidia_hybrid)
        # Protect whichever Nvidia driver series is installed
        for pkg in nvidia nvidia-dkms nvidia-open nvidia-open-dkms \
                   nvidia-utils lib32-nvidia-utils nvidia-settings \
                   libva-nvidia-driver envycontrol; do
            if pacman -Qi "$pkg" &>/dev/null; then
                GPU_PROTECTED+=("$pkg")
            fi
        done
        # Always protect mesa for Wayland compatibility layer
        GPU_PROTECTED+=(mesa libva-utils)
        # Protect Intel drivers on hybrid systems
        if [ "$GPU_VENDOR" = "nvidia_hybrid" ]; then
            for pkg in vulkan-intel intel-media-driver libva-intel-driver; do
                if pacman -Qi "$pkg" &>/dev/null; then
                    GPU_PROTECTED+=("$pkg")
                fi
            done
        fi
        ;;
    intel)
        GPU_PROTECTED=(
            mesa
            vulkan-intel
            intel-media-driver
            libva-intel-driver
            libva-utils
        )
        ;;
    *)
        GPU_PROTECTED=(mesa libva-utils)
        ;;
esac

echo "    [GPU PACKAGES PROTECTED] ${GPU_PROTECTED[*]}"
echo ""

# -------------------------------------------------------
# PROTECTED PACKAGES — these will NEVER be removed
# even if pacman or orphan cleanup wants to touch them
# -------------------------------------------------------
PROTECTED=(
    # Plasma core
    plasma-desktop
    plasma-nm
    plasma-pa
    kwin
    kscreen
    krunner
    powerdevil
    bluedevil
    kde-gtk-config
    breeze
    breeze-gtk
    breeze-icons
    polkit-kde-agent
    kwallet-pam
    xdg-desktop-portal
    xdg-desktop-portal-kde
    xdg-user-dirs
    oxygen-sounds
    sddm
    sddm-kcm

    # Apps to keep
    dolphin
    kitty
    spectacle
    klipper

    # Audio — every component needed
    pipewire
    pipewire-alsa
    pipewire-pulse
    pipewire-jack
    wireplumber
    gst-plugin-pipewire
    libpulse

    # Networking
    networkmanager
    network-manager-applet
    firewalld

    # Fonts / icons (losing these breaks the desktop visually)
    noto-fonts
    ttf-liberation
    ttf-jetbrains-mono-nerd
    hicolor-icon-theme

    # GPU packages — dynamically added based on detected GPU
    "${GPU_PROTECTED[@]}"

    # Wayland essentials
    wayland
    qt6-wayland
    qt5-wayland

    # Performance tools
    gamemode
    lib32-gamemode
    auto-cpufreq
    irqbalance
    ananicy-cpp

    # Snapshot tools
    snapper
    snap-pac
    grub-btrfs
    inotify-tools

    # Base system libs that orphan cleanup sometimes grabs
    dbus
    systemd
    glibc
    gcc-libs
    libx11
    libxcb
)

# -------------------------------------------------------
# Helper: check if a package is protected
# -------------------------------------------------------
is_protected() {
    local pkg="$1"
    printf "%s\n" "${PROTECTED[@]}" | grep -qx "$pkg"
}

# -------------------------------------------------------
# PRE-FLIGHT: abort if any critical package is missing
# -------------------------------------------------------
echo "==> [PRE-FLIGHT] Checking critical packages are installed..."
PREFLIGHT_OK=true
for pkg in \
    plasma-desktop kwin krunner dolphin kitty \
    pipewire wireplumber networkmanager sddm \
    wayland dbus systemd glibc; do
    if ! pacman -Qi "$pkg" &>/dev/null; then
        echo "    [ABORT] $pkg is not installed — run the barebones install script first!"
        PREFLIGHT_OK=false
    else
        echo "    [OK] $pkg"
    fi
done

if ! $PREFLIGHT_OK; then
    echo ""
    echo "ERROR: Pre-flight check failed. Aborting — nothing has been removed."
    echo "Run kde-barebones-install.sh first, reboot, then run this script."
    exit 1
fi
echo "    Pre-flight passed. Proceeding with removal."
echo ""

# -------------------------------------------------------
# REMOVAL FUNCTION
# Removes a package only if it is NOT protected
# -------------------------------------------------------
safe_remove() {
    local pkg="$1"
    if is_protected "$pkg"; then
        echo "    [SKIP - protected] $pkg"
        return
    fi
    if pacman -Qi "$pkg" &>/dev/null; then
        echo "    [REMOVING] $pkg"
        sudo pacman -Rns --noconfirm "$pkg" 2>/dev/null || \
            echo "    [WARN] Could not remove $pkg (likely has dependents, skipping)"
    fi
}

# -------------------------------------------------------
# 1. Remove KDE bloat — one package at a time so a
#    single failure never aborts the whole sweep
# -------------------------------------------------------
echo "==> [1/5] Removing KDE application packages..."

BLOAT=(
    # PIM / Akonadi stack
    akregator akonadi akonadi-calendar akonadi-contacts
    akonadi-mime akonadi-search akonadiconsole
    kalarm kmail korganizer kontact kaddressbook
    knotes ktnef mbox-importer pim-data-exporter
    pim-sieve-editor kdepim-addons kdepim-runtime
    kwalletmanager

    # Utilities
    ark gwenview okular kate kwrite
    kcalc kcharselect kfind print-manager
    skanlite skanpage kruler kcolorchooser
    kolourpaint kgpg ktimer kmouth kmag kontrast
    kdialog keditbookmarks khelpcenter konsole

    # Multimedia
    dragon juk kamoso kdenlive kwave elisa

    # Network apps (NOT networkmanager itself)
    konqueror kget krdc krfb kdeconnect
    signon-kwallet-extension

    # Education
    marble kdeedu-data cantor kalgebra kbruch
    kgeography khangman kig kiten klettres
    kmplot kqtquickcharts ktouch kturtle
    kwordquiz parley blinken

    # Games
    bomber bovo granatier kajongg kapman katomic
    kblackbox kblocks kbounce kbreakout kdiamond
    kfourinline kgoldrunner kigo killbots kiriki
    kjumpingcube klickety klines kmahjongg kmines
    knavalbattle knetwalk knights kolf kollision
    konquest kpat kreversi kshizen ksirk ksnakeduel
    ksquares ksudoku ktuberling kubrick lskat
    palapeli picmi

    # Meta-packages (safe to remove, they're just groups)
    kde-applications kdegames kdeutils
    kdeaccessibility kdeedu kdegraphics
    kdemultimedia kdenetwork kdepim kdesdk kdewebdev

    # X11/Xorg — not needed on Wayland
    # AMD-specific X11 drivers removed only on AMD systems
    xterm
    xorg-xinit
    xorg-xinput
    xorg-xkill
    plasma-x11-session

    # Misc bloat
    meld
    haruna
    pavucontrol
    plasma-systemmonitor
    kgamma
    plasma-keyboard
)

for pkg in "${BLOAT[@]}"; do
    safe_remove "$pkg"
done

# Remove AMD-specific X11 drivers only on AMD systems
if [ "$GPU_VENDOR" = "amd" ]; then
    echo "    [AMD] Removing AMD X11 drivers (not needed on Wayland)..."
    safe_remove "xf86-video-amdgpu"
    safe_remove "xf86-video-ati"
fi

# -------------------------------------------------------
# 2. Remove EndeavourOS-specific packages if present
# -------------------------------------------------------
echo ""
echo "==> [2/5] Removing EndeavourOS packages if present..."

EOS_PACKAGES=(
    reflector-simple
    eos-bash-shared
    eos-hooks
    eos-update
    eos-rankmirrors
    eos-packagelist
    eos-log-tool
    eos-breeze-sddm
    eos-settings-plasma
    eos-translations
    eos-apps-info
    eos-quickstart
    endeavouros-branding
    endeavouros-keyring
    endeavouros-mirrorlist
    endeavouros-konsole-colors
    eos-dracut
    welcome
    fluxer-git
)

for pkg in "${EOS_PACKAGES[@]}"; do
    safe_remove "$pkg"
done

# Replace eos-dracut with standard dracut if needed
if ! pacman -Qi dracut &>/dev/null; then
    echo "    [FIX] Installing standard dracut..."
    sudo pacman -S --needed --noconfirm dracut
fi

# -------------------------------------------------------
# 3. Orphan cleanup — with protected package guard
# -------------------------------------------------------
echo ""
echo "==> [3/5] Cleaning orphaned packages (protected packages are safe)..."

for pass in 1 2 3; do
    ORPHANS=$(pacman -Qdtq 2>/dev/null || true)
    if [ -z "$ORPHANS" ]; then
        echo "    Pass $pass: No orphans found."
        break
    fi

    echo "    Pass $pass orphans found:"
    SAFE_ORPHANS=()
    for pkg in $ORPHANS; do
        if is_protected "$pkg"; then
            echo "      [SKIP - protected] $pkg"
        else
            echo "      [WILL REMOVE] $pkg"
            SAFE_ORPHANS+=("$pkg")
        fi
    done

    if [ ${#SAFE_ORPHANS[@]} -gt 0 ]; then
        sudo pacman -Rns --noconfirm "${SAFE_ORPHANS[@]}" 2>/dev/null || true
    else
        echo "    All remaining orphans are protected, skipping."
        break
    fi
done

# -------------------------------------------------------
# 4. Ensure systemd services are correct
# -------------------------------------------------------
echo ""
echo "==> [4/5] Verifying systemd services..."

# Display manager
if systemctl is-enabled sddm &>/dev/null; then
    echo "    [OK] sddm is enabled"
else
    echo "    [FIX] Enabling sddm..."
    sudo systemctl enable sddm
fi

# NetworkManager
if systemctl is-enabled NetworkManager &>/dev/null; then
    echo "    [OK] NetworkManager is enabled"
else
    echo "    [FIX] Enabling NetworkManager..."
    sudo systemctl enable NetworkManager
    sudo systemctl start NetworkManager
fi

# NM-wait-online disabled
if systemctl is-enabled NetworkManager-wait-online.service &>/dev/null; then
    echo "    [FIX] Disabling NetworkManager-wait-online..."
    sudo systemctl disable NetworkManager-wait-online.service
else
    echo "    [OK] NetworkManager-wait-online already disabled"
fi

# PipeWire user services
for svc in pipewire pipewire-pulse wireplumber; do
    if systemctl --user is-enabled "$svc" &>/dev/null; then
        echo "    [OK] $svc (user service) is enabled"
    else
        echo "    [FIX] Enabling $svc user service..."
        systemctl --user enable "$svc" 2>/dev/null || true
    fi
done

# -------------------------------------------------------
# 5. Post-removal verification — reinstall anything missing
# -------------------------------------------------------
echo ""
echo "==> [5/5] Post-removal verification..."
VERIFY=(
    plasma-desktop kwin krunner dolphin kitty
    pipewire pipewire-alsa pipewire-pulse wireplumber
    networkmanager plasma-nm plasma-pa
    sddm wayland qt6-wayland
    breeze breeze-icons polkit-kde-agent
    xdg-desktop-portal xdg-desktop-portal-kde
    mesa
    "${GPU_PROTECTED[@]}"
)

ALL_OK=true
for pkg in "${VERIFY[@]}"; do
    if pacman -Qi "$pkg" &>/dev/null; then
        echo "    [OK] $pkg"
    else
        echo "    [MISSING] $pkg — reinstalling..."
        sudo pacman -S --needed --noconfirm "$pkg"
        ALL_OK=false
    fi
done

# -------------------------------------------------------
# Done
# -------------------------------------------------------
echo ""
echo "=============================================="
echo " Debloat complete!"
if $ALL_OK; then
    echo " All critical packages intact. Safe to reboot."
else
    echo " Some packages were missing and have been"
    echo " reinstalled automatically. Safe to reboot."
fi
echo ""
echo " Kept:"
echo "  - Plasma desktop, KWin, KRunner"
echo "  - Dolphin, Kitty, Spectacle, Klipper"
echo "  - Steam, Vivaldi (never touched)"
echo "  - PipeWire full audio stack"
echo "  - NetworkManager + plasma-nm tray"
echo "  - Firewalld"
echo "  - SDDM login manager"
echo "  - GPU drivers (auto-detected: $GPU_VENDOR)"
echo "  - Wayland + Qt Wayland support"
echo "  - gamemode, auto-cpufreq, ananicy-cpp"
echo "  - snapper + snap-pac + grub-btrfs"
echo "  - JetBrains Mono Nerd Font"
echo ""
echo " Removed:"
echo "  - All KDE bloat apps and games"
echo "  - All EndeavourOS specific packages"
echo "  - Unused X11/Xorg packages"
echo ""
echo " Reboot when ready."
echo "=============================================="
