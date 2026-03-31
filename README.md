# Arch KDE Setup

A set of scripts to turn a fresh EndeavourOS KDE install into a clean,
debloated, and optimized KDE Plasma 6 desktop on Wayland.

---

## Who is this for

- Anyone who wants a fast, minimal KDE desktop on Arch Linux
- Friends and family who want a clean setup without the bloat
- AMD GPU users (RX 5000 series and newer recommended)

---

## Requirements

- Fresh EndeavourOS install with KDE Plasma selected
- Internet connection
- AMD or Intel GPU (Nvidia untested)

---

## Scripts

### kde-setup-universal.sh
The main setup script. Run this first after a fresh EndeavourOS KDE install.

What it does:
- Installs barebones KDE Plasma 6 on Wayland
- Sets up PipeWire audio stack
- Configures NetworkManager and Firewalld
- Installs JetBrains Mono Nerd Font
- Sets up Btrfs snapshots with snapper
- Applies performance tweaks (ZRAM, swappiness, THP)
- Disables Baloo file indexer
- Runs the debloat script automatically at the end

### kde-debloat.sh
Removes all KDE bloat apps while keeping the core desktop intact.

What gets removed:
- All KDE games
- KDE PIM and Akonadi email stack
- KDE education apps
- Unused multimedia apps
- Unused network apps
- EndeavourOS specific packages

What stays:
- Plasma desktop, KWin, KRunner
- Dolphin, Kitty, Spectacle
- PipeWire audio
- NetworkManager
- SDDM login manager
- Mesa/Vulkan GPU drivers

### kde-setup-personal.sh
For AMD Ryzen 9000 series (Zen 5) machines only. Run this after
kde-setup-universal.sh on supported hardware.

What it does:
- Adds CachyOS znver4 optimized repos
- Installs CachyOS RC kernel with BORE scheduler
- Applies AMD RDNA4 GPU tweaks
- Configures auto-cpufreq and ananicy-cpp
- Tunes BORE scheduler

---

## How to use

### For everyone (any x86_64 machine)

Download EndeavourOS from https://endeavouros.com and install it with
KDE Plasma selected in the Calamares installer. Then open a terminal and run:
```bash
curl -O https://raw.githubusercontent.com/jtadlock91/arch-kde-setup/main/kde-setup-universal.sh
curl -O https://raw.githubusercontent.com/jtadlock91/arch-kde-setup/main/kde-debloat.sh
chmod +x kde-setup-universal.sh
bash kde-setup-universal.sh
```

That is all. The script handles everything and calls the debloat script
automatically at the end. Reboot when it finishes.

### For Zen 4/5 AMD machines (additional step)

After running kde-setup-universal.sh, run:
```bash
curl -O https://raw.githubusercontent.com/jtadlock91/arch-kde-setup/main/kde-setup-personal.sh
chmod +x kde-setup-personal.sh
bash kde-setup-personal.sh
```

Then reboot into the CachyOS kernel and set your Curve Optimizer in BIOS.

---

## After install

- Open Kitty terminal with the applications menu or KRunner (Alt+Space)
- Dolphin is your file manager
- Spectacle is your screenshot tool
- Audio works out of the box via PipeWire
- Snapshots happen automatically before and after every pacman update

---

## Notes

- These scripts are built and tested on EndeavourOS with an AMD RX 9060 XT
- Nvidia GPU users may need additional driver steps not covered here
- The personal script will abort automatically if your CPU does not support
  x86-64-v4 (Zen 4/5 requirement)
