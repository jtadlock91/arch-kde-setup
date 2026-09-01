#!/bin/bash
# ============================================================
# install-system-clean.sh
# Sets up system-clean as a daily user-level systemd service
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Installing system-clean..."

# Install dependencies
echo "==> Checking dependencies..."
MISSING=()
command -v paccache &>/dev/null || MISSING+=("pacman-contrib")
command -v expac    &>/dev/null || MISSING+=("expac")
command -v md5sum   &>/dev/null || MISSING+=("coreutils")

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "    Installing missing tools: ${MISSING[*]}"
    sudo pacman -S --needed --noconfirm "${MISSING[@]}"
else
    echo "    All dependencies present."
fi

# Copy script to ~/.local/bin
echo "==> Installing script to ~/.local/bin/..."
mkdir -p "$HOME/.local/bin"
cp "$SCRIPT_DIR/system-clean.sh" "$HOME/.local/bin/system-clean.sh"
chmod +x "$HOME/.local/bin/system-clean.sh"

# Add ~/.local/bin to PATH if not already there
if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
    echo "==> Adding ~/.local/bin to PATH in ~/.bashrc and ~/.zshrc..."
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [ -f "$rc" ]; then
            grep -q '.local/bin' "$rc" || \
                echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc"
        fi
    done
fi

# Add shell alias
echo "==> Adding shell aliases..."
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$rc" ]; then
        grep -q 'alias clean=' "$rc" || cat >> "$rc" <<'EOF'

# system-clean aliases
alias clean='system-clean.sh --manual'
alias clean-dry='system-clean.sh --dry-run'
alias clean-report='system-clean.sh --report'
alias clean-auto='system-clean.sh --auto'
EOF
        echo "    Added aliases to $rc"
    fi
done

# Install systemd user service and timer
echo "==> Installing systemd user service and timer..."
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
mkdir -p "$SYSTEMD_USER_DIR"

cp "$SCRIPT_DIR/system-clean.service" "$SYSTEMD_USER_DIR/system-clean.service"
cp "$SCRIPT_DIR/system-clean.timer"   "$SYSTEMD_USER_DIR/system-clean.timer"

systemctl --user daemon-reload
systemctl --user enable --now system-clean.timer

echo "    Timer enabled and running."

# Create log directory
mkdir -p "$HOME/.local/share/system-clean"

# Done
echo ""
echo "=============================================="
echo " system-clean installed!"
echo ""
echo " Commands:"
echo "  clean           Interactive mode — prompts for ambiguous files"
echo "  clean-dry       Dry run — shows what would happen, touches nothing"
echo "  clean-report    Show last run log and items needing review"
echo "  clean-auto      Run automatically right now (same as timer)"
echo ""
echo " Schedule:"
echo "  Runs daily automatically via systemd user timer."
echo "  Check timer status: systemctl --user status system-clean.timer"
echo ""
echo " Review file:"
echo "  Items needing attention are written to:"
echo "  ~/.local/share/system-clean/review.txt"
echo "  Run 'clean-report' to see them."
echo ""
echo " Config:"
echo "  Edit paths and thresholds at the top of:"
echo "  ~/.local/bin/system-clean.sh"
echo "=============================================="
