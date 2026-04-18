# Arch KDE Setup

A set of scripts to turn a fresh EndeavourOS KDE install into a clean,
debloated, and optimized KDE Plasma 6 desktop on Wayland.

---

## Who is this for

- Anyone who wants a fast, minimal KDE desktop on Arch Linux
- Friends and family who want a clean setup without the bloat
- Any x86_64 machine — AMD, Intel, or Nvidia GPU all supported

---

## Requirements

- Fresh EndeavourOS install with KDE Plasma selected in the Calamares installer
- Internet connection
- AMD, Intel, or Nvidia GPU (auto-detected — Nvidia hybrid supported via envycontrol)

---

## Scripts

### kde-setup-universal.sh
The main setup script. Run this first on any machine.

What it does:
- Installs barebones KDE Plasma 6 on Wayland
- Auto-detects your GPU and installs the correct drivers
  - AMD: mesa, vulkan-radeon, libva, radeontop
  - Nvidia: installs correct driver series (supports CachyOS versioned packages)
  - Nvidia + Intel hybrid: installs envycontrol and sets hybrid mode
  - Intel: mesa, vulkan-intel, intel-media-driver
- Sets up PipeWire audio stack
- Configures NetworkManager and Firewalld
- Installs JetBrains Mono Nerd Font
- Sets up Btrfs snapshots with snapper (auto-snapshots before/after every pacman update)
- Applies performance tweaks (ZRAM, swappiness=10, THP=madvise)
- Disables Baloo file indexer
- Asks if you want to run the debloat script at the end

### kde-debloat.sh
Removes all KDE bloat apps while keeping the core desktop intact.
Run this alongside kde-setup-universal.sh — the universal script will find and call it automatically.

What gets removed:
- All KDE games
- KDE PIM and Akonadi email stack
- KDE education apps
- Unused multimedia apps
- Unused network apps
- EndeavourOS specific packages
- Unused X11/Xorg packages (not needed on Wayland)

What stays:
- Plasma desktop, KWin, KRunner
- Dolphin, Kitty, Spectacle, Klipper
- PipeWire full audio stack
- NetworkManager + firewalld
- SDDM login manager
- GPU drivers (auto-detected)
- gamemode, snapper, snap-pac, grub-btrfs

### kde-setup-personal.sh
For Zen 4/5 AMD machines with RDNA4 GPU only. Run this after
kde-setup-universal.sh on supported hardware. The script will abort
automatically if your CPU does not support x86-64-v4.

What it does:
- Adds CachyOS repos (znver4 optimized packages for Zen 4/5)
- Installs CachyOS RC kernel with BORE scheduler, LTO, and AutoFDO
- Applies AMD RDNA4 GPU performance tweaks (RADV_PERFTEST, mesa_glthread, udev power rule)
- Installs and enables auto-cpufreq, irqbalance, ananicy-cpp
- Configures BORE scheduler sysctl

### system-clean.sh + install-system-clean.sh
Daily automated maintenance — organizes Downloads by type and date,
cleans orphaned packages, and prunes the pacman cache. Runs automatically
via a systemd user timer.

Install it by putting both files in the same folder and running:
```bash
chmod +x install-system-clean.sh
./install-system-clean.sh
```

Commands after install:
- `clean` — interactive mode, prompts before acting on ambiguous files
- `clean-dry` — dry run, shows what would happen without touching anything
- `clean-auto` — run immediately (same as the daily timer)
- `clean-report` — show last run log and items needing attention

### sysreport.sh + install-sysreport.sh
Generates a full system snapshot covering kernel, CPU temps, BORE status,
memory, ZRAM, NVMe health, Btrfs usage, GPU, packages, orphans, failed
services, snapshots, boot times, and DNS. Useful for diagnostics — paste
the output into Claude or a forum post for instant context.

Install it the same way as system-clean:
```bash
chmod +x install-sysreport.sh
./install-sysreport.sh
```

Commands after install:
- `sysreport` — full report output to terminal
- `sysreport-short` — quick one-liner health summary
- `sysreport-save` — saves full report to ~/sysreport.txt

---

## How to use

### For everyone (any x86_64 machine)

Download EndeavourOS from https://endeavouros.com and install it with
KDE Plasma selected in the Calamares installer.

Then open Kitty (or any terminal) and run:

```bash
curl -O https://raw.githubusercontent.com/jtadlock91/arch-kde-setup/main/kde-setup-universal.sh
curl -O https://raw.githubusercontent.com/jtadlock91/arch-kde-setup/main/kde-debloat.sh
chmod +x kde-setup-universal.sh kde-debloat.sh
bash kde-setup-universal.sh
```

The script handles everything. At the end it will ask if you want to run
the debloat script — say yes for a clean minimal desktop. Reboot when it finishes.

### For Zen 4/5 AMD machines (optional additional step)

After running kde-setup-universal.sh and rebooting, run:

```bash
curl -O https://raw.githubusercontent.com/jtadlock91/arch-kde-setup/main/kde-setup-personal.sh
chmod +x kde-setup-personal.sh
bash kde-setup-personal.sh
```

After it finishes:
- Reboot and select the CachyOS kernel in GRUB
- Set Curve Optimizer to -40 all core in BIOS
- Enable PBO in BIOS
- Add `gamemoderun %command%` to Steam launch options

### For the daily maintenance scripts (any machine)

```bash
curl -O https://raw.githubusercontent.com/jtadlock91/arch-kde-setup/main/system-clean.sh
curl -O https://raw.githubusercontent.com/jtadlock91/arch-kde-setup/main/install-system-clean.sh
chmod +x install-system-clean.sh system-clean.sh
./install-system-clean.sh
source ~/.bashrc
```

---

## After install

- Open Kitty terminal from the application menu or KRunner (`Alt+Space`)
- Dolphin is your file manager
- Spectacle is your screenshot tool
- Audio works out of the box via PipeWire
- Snapshots happen automatically before and after every pacman update via snap-pac
- Run `sysreport` any time to get a full picture of your system health

---

## Notes

- Built and tested on EndeavourOS with AMD Ryzen 9000 series and RDNA4 GPU
- Nvidia and Nvidia+Intel hybrid GPUs are fully supported — the script auto-detects and installs the correct drivers
- The personal script aborts automatically if your CPU does not support x86-64-v4 (Zen 4/5 only)
- These scripts are safe to re-run — pacman's `--needed` flag skips already installed packages
