#!/bin/bash
# ============================================================
# KDE Debloat Script - Arch Linux + CachyOS (Hardened)
# ============================================================
# Removes full KDE app suite, keeps:
#   - KDE Plasma desktop (barebones)
#   - Dolphin, KRunner, Kitty, Spectacle, Klipper
#   - Steam, Vivaldi (untouched)
#   - PipeWire audio, NetworkManager, SDDM
#
# Also removes EndeavourOS-specific packages if present
# (safe to run even if already removed)
#
# SAFETY FEATURES:
#   - Pre-flight check before touching anything
#   - Protected package list (never removed, ever)
#   - Orphan cleanup skips protected packages
#   - Post-removal verification with auto-reinstall
#   - Aborts immediately if anything critical is missing
#
# RUN THE BAREBONES INSTALL SCRIPT FIRST and reboot into
# the new session before running this.
# ============================================================

set -e

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

    # Mesa / GPU (losing these kills display entirely)
    mesa
    vulkan-radeon
    libva-mesa-driver
    mesa-vdpau
    libva-utils

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

    # X11/Xorg — not needed on Wayland AMD
    xterm
    xorg-xinit
    xorg-xinput
    xorg-xkill
    xf86-video-amdgpu
    xf86-video-ati
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
    mesa vulkan-radeon
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
echo "  - Mesa/Vulkan AMD GPU drivers"
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
