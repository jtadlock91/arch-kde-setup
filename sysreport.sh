#!/bin/bash
# ============================================================
# sysreport.sh — System Snapshot for Claude
# ============================================================
# Generates a clean system report you can paste into Claude
# for help, diagnosis, or general system health checks.
#
# Usage:
#   sysreport          Print report to terminal (paste into Claude)
#   sysreport --save   Save to ~/sysreport.txt and print path
#   sysreport --short  Quick summary only, no deep scans
# ============================================================

MODE="${1:---print}"

# -------------------------------------------------------
# HELPERS
# -------------------------------------------------------
section() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " $*"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# -------------------------------------------------------
# BUILD REPORT
# -------------------------------------------------------
generate_report() {

echo "============================================================"
echo " SYSTEM REPORT — $(date '+%Y-%m-%d %H:%M:%S')"
echo " Host: $(hostname)"
echo "============================================================"

# -------------------------------------------------------
section "SYSTEM"
# -------------------------------------------------------
echo "OS:        $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"
echo "Kernel:    $(uname -r)"
echo "Uptime:    $(uptime -p)"
echo "Last boot: $(who -b | awk '{print $3, $4}')"

# -------------------------------------------------------
section "CPU"
# -------------------------------------------------------
echo "CPU:       $(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)"
echo "Cores:     $(nproc) threads"
echo "Governor:  $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo 'unknown')"

# CPU temps via sensors
if command -v sensors &>/dev/null; then
    echo ""
    echo "Temperatures:"
    sensors 2>/dev/null | grep -E 'Tctl|Tdie|Package|Core 0|CPU' | head -8 | sed 's/^/  /'
else
    echo "Temps:     install lm_sensors for temperature readings"
fi

# BORE scheduler
if sysctl kernel.sched_bore &>/dev/null 2>&1; then
    echo ""
    echo "BORE:      $(sysctl -n kernel.sched_bore) (enabled)"
    echo "Slice:     $(sysctl -n kernel.sched_min_base_slice_ns 2>/dev/null || echo 'unknown')ns"
fi

# auto-cpufreq status
if systemctl is-active auto-cpufreq &>/dev/null; then
    echo "auto-cpufreq: active"
else
    echo "auto-cpufreq: NOT running"
fi

# -------------------------------------------------------
section "MEMORY"
# -------------------------------------------------------
free -h | sed 's/^/  /'

echo ""
# ZRAM
if [ -d /dev/zram0 ] || lsblk | grep -q zram; then
    echo "ZRAM:"
    zramctl 2>/dev/null | sed 's/^/  /' || echo "  zramctl not available"
fi

echo ""
echo "Swappiness: $(sysctl -n vm.swappiness)"

# -------------------------------------------------------
section "STORAGE"
# -------------------------------------------------------
echo "Disk usage:"
df -h --output=source,size,used,avail,pcent,target | grep -v tmpfs | grep -v devtmpfs | grep -v efivarfs | sed 's/^/  /'

echo ""
echo "NVMe health:"
if command -v nvme &>/dev/null; then
    for dev in /dev/nvme*n1; do
        [ -e "$dev" ] || continue
        echo "  $dev:"
        sudo nvme smart-log "$dev" 2>/dev/null | grep -E 'temperature|percentage_used|data_units|power_on' | sed 's/^/    /' || \
            echo "    (run as root for SMART data)"
    done
else
    echo "  install nvme-cli for NVMe health data"
fi

echo ""
echo "Btrfs usage:"
if command -v btrfs &>/dev/null; then
    sudo btrfs filesystem usage / 2>/dev/null | grep -E 'Device size|Used|Free' | sed 's/^/  /' || \
        echo "  (run as root for Btrfs data)"
fi

# -------------------------------------------------------
section "GPU"
# -------------------------------------------------------
if command -v radeontop &>/dev/null; then
    echo "GPU:       $(lspci | grep -i vga | cut -d: -f3 | xargs)"
fi

echo "GPU driver info:"
if [ -f /sys/class/drm/card*/device/power_dpm_force_performance_level ]; then
    for f in /sys/class/drm/card*/device/power_dpm_force_performance_level; do
        echo "  Performance level: $(cat $f)"
    done
fi

# RADV env vars
echo ""
echo "Environment vars:"
grep -E 'RADV|mesa|MESA|GPU|LIBVA' /etc/environment 2>/dev/null | sed 's/^/  /' || echo "  none found in /etc/environment"

# vainfo for AV1
echo ""
echo "Hardware decode:"
if command -v vainfo &>/dev/null; then
    vainfo 2>/dev/null | grep -E 'AV1|H264|H265|HEVC|driver' | head -10 | sed 's/^/  /' || \
        echo "  vainfo failed — check GPU driver"
else
    echo "  install libva-utils for decode info"
fi

# -------------------------------------------------------
section "PACKAGES"
# -------------------------------------------------------
echo "Total installed: $(pacman -Q | wc -l) packages"
echo "Explicitly installed: $(pacman -Qe | wc -l) packages"

echo ""
echo "Orphans:"
ORPHANS=$(pacman -Qdtq 2>/dev/null || true)
if [ -n "$ORPHANS" ]; then
    echo "$ORPHANS" | sed 's/^/  /'
else
    echo "  None"
fi

echo ""
echo "Updates available:"
if command -v checkupdates &>/dev/null; then
    UPDATES=$(checkupdates 2>/dev/null || true)
    if [ -n "$UPDATES" ]; then
        echo "$UPDATES" | wc -l | xargs -I{} echo "  {} package(s) available:"
        echo "$UPDATES" | sed 's/^/  /'
    else
        echo "  System is up to date"
    fi
else
    echo "  install pacman-contrib for update checking"
fi

echo ""
echo "AUR updates:"
if command -v yay &>/dev/null; then
    AUR_UPDATES=$(yay -Qua 2>/dev/null || true)
    if [ -n "$AUR_UPDATES" ]; then
        echo "$AUR_UPDATES" | sed 's/^/  /'
    else
        echo "  AUR packages up to date"
    fi
fi

echo ""
echo "Pacman cache size:"
du -sh /var/cache/pacman/pkg/ 2>/dev/null | sed 's/^/  /' || echo "  unknown"

# -------------------------------------------------------
section "SYSTEMD SERVICES"
# -------------------------------------------------------
echo "Failed services:"
FAILED=$(systemctl --failed --no-legend 2>/dev/null | head -20)
if [ -n "$FAILED" ]; then
    echo "$FAILED" | sed 's/^/  /'
else
    echo "  None"
fi

echo ""
echo "Failed user services:"
FAILED_USER=$(systemctl --user --failed --no-legend 2>/dev/null | head -20)
if [ -n "$FAILED_USER" ]; then
    echo "$FAILED_USER" | sed 's/^/  /'
else
    echo "  None"
fi

echo ""
echo "Key service status:"
for svc in sddm NetworkManager firewalld auto-cpufreq irqbalance ananicy-cpp snapper-timeline.timer snapper-cleanup.timer grub-btrfsd system-clean.timer; do
    status=$(systemctl is-active "$svc" 2>/dev/null || echo "not-found")
    printf "  %-35s %s\n" "$svc" "$status"
done

echo ""
echo "Key user service status:"
for svc in pipewire pipewire-pulse wireplumber system-clean.timer; do
    status=$(systemctl --user is-active "$svc" 2>/dev/null || echo "not-found")
    printf "  %-35s %s\n" "$svc" "$status"
done

# -------------------------------------------------------
section "BTRFS SNAPSHOTS"
# -------------------------------------------------------
if command -v snapper &>/dev/null; then
    echo "Recent snapshots (last 10):"
    sudo snapper -c root list 2>/dev/null | tail -10 | sed 's/^/  /' || \
        echo "  (run as root for snapshot list)"
else
    echo "  snapper not installed"
fi

# -------------------------------------------------------
section "BOOT PERFORMANCE"
# -------------------------------------------------------
echo "Last boot times:"
systemd-analyze 2>/dev/null | sed 's/^/  /'
echo ""
echo "Slowest units:"
systemd-analyze blame 2>/dev/null | head -10 | sed 's/^/  /'

# -------------------------------------------------------
section "NETWORK"
# -------------------------------------------------------
echo "Interfaces:"
ip -brief addr show 2>/dev/null | grep -v '^lo' | sed 's/^/  /'

echo ""
echo "DNS:"
resolvectl status 2>/dev/null | grep -E 'DNS Server|DNS Domain' | head -6 | sed 's/^/  /' || \
    cat /etc/resolv.conf | grep nameserver | sed 's/^/  /'

# -------------------------------------------------------
section "SYSTEM-CLEAN STATUS"
# -------------------------------------------------------
REVIEW_FILE="$HOME/.local/share/system-clean/review.txt"
LOG_FILE="$HOME/.local/share/system-clean/system-clean.log"

echo "Last clean run:"
if [ -f "$LOG_FILE" ]; then
    grep "starting\|Run complete\|MOVED\|REMOVED\|ORPHAN\|error" "$LOG_FILE" | tail -20 | sed 's/^/  /'
else
    echo "  No runs yet"
fi

echo ""
echo "Pending review items:"
if [ -f "$REVIEW_FILE" ] && [ -s "$REVIEW_FILE" ]; then
    cat "$REVIEW_FILE" | sed 's/^/  /'
else
    echo "  Nothing pending"
fi

# -------------------------------------------------------
echo ""
echo "============================================================"
echo " END OF REPORT — paste this into Claude for assistance"
echo "============================================================"

}

# -------------------------------------------------------
# OUTPUT
# -------------------------------------------------------
case "$MODE" in
    --save)
        OUTFILE="$HOME/sysreport.txt"
        generate_report | tee "$OUTFILE"
        echo ""
        echo "Saved to: $OUTFILE"
        ;;
    --short)
        echo "=== QUICK REPORT === $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Kernel:   $(uname -r)"
        echo "Uptime:   $(uptime -p)"
        echo "Memory:   $(free -h | awk '/^Mem:/ {print $3 " used / " $2 " total"}')"
        echo "Disk:     $(df -h / | awk 'NR==2 {print $3 " used / " $2 " total (" $5 ")"}')"
        echo "Orphans:  $(pacman -Qdtq 2>/dev/null | wc -l)"
        echo "Failed:   $(systemctl --failed --no-legend 2>/dev/null | wc -l) service(s)"
        UPDATES=$(checkupdates 2>/dev/null | wc -l || echo 0)
        echo "Updates:  $UPDATES available"
        ;;
    *)
        generate_report
        ;;
esac
