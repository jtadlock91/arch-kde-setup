#!/bin/bash
# ============================================================
# install-sysreport.sh
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Installing sysreport..."

# Dependencies
echo "==> Checking dependencies..."
MISSING=()
command -v sensors   &>/dev/null || MISSING+=("lm_sensors")
command -v nvme      &>/dev/null || MISSING+=("nvme-cli")
command -v vainfo    &>/dev/null || MISSING+=("libva-utils")

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "    Installing: ${MISSING[*]}"
    sudo pacman -S --needed --noconfirm "${MISSING[@]}"
else
    echo "    All dependencies present."
fi

# Copy script
echo "==> Installing to ~/.local/bin/..."
cp "$SCRIPT_DIR/sysreport.sh" "$HOME/.local/bin/sysreport.sh"
chmod +x "$HOME/.local/bin/sysreport.sh"

# Add alias
echo "==> Adding aliases..."
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$rc" ]; then
        grep -q 'alias sysreport=' "$rc" || cat >> "$rc" <<'EOF'

# sysreport aliases
alias sysreport='sysreport.sh'
alias sysreport-short='sysreport.sh --short'
alias sysreport-save='sysreport.sh --save'
EOF
        echo "    Added aliases to $rc"
    fi
done

echo ""
echo "=============================================="
echo " sysreport installed!"
echo ""
echo " Commands:"
echo "  sysreport          Full report — paste into Claude"
echo "  sysreport-short    Quick one-liner health check"
echo "  sysreport-save     Save report to ~/sysreport.txt"
echo "=============================================="
