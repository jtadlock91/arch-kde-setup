#!/bin/bash
# ============================================================
# system-clean.sh — Daily System Cleanup & Organizer
# ============================================================
# Manages:
#   - Downloads: sort by type + date, flag old files, flag dupes
#   - Documents: flag duplicates, organize loose files
#   - Screenshots: sort into monthly subfolders, rename by date
#   - Dotfiles: check for untracked configs
#   - Packages: orphans, pacman cache, large unused packages
#
# Modes:
#   --auto     Run automatically (called by systemd timer)
#   --manual   Interactive mode, prompts for ambiguous actions
#   --dry-run  Show what would happen, touch nothing
#   --report   Print last run log and exit
#
# Log: ~/.local/share/system-clean/system-clean.log
# Review file: ~/.local/share/system-clean/review.txt
# ============================================================

set -euo pipefail

# -------------------------------------------------------
# CONFIG — edit these to match your paths
# -------------------------------------------------------
DOWNLOADS="$HOME/Downloads"
DOCUMENTS="$HOME/Documents"
SCREENSHOTS="$HOME/Pictures/Screenshots"
DOTFILES="$HOME/.dotfiles"             # your dotfiles git repo, or leave blank
OLD_FILE_DAYS=90                       # flag files older than this many days
PACMAN_KEEP_VERSIONS=2                 # keep this many versions in pacman cache
LARGE_PKG_MB=200                       # flag explicitly installed packages larger than this

# -------------------------------------------------------
# INTERNALS
# -------------------------------------------------------
LOG_DIR="$HOME/.local/share/system-clean"
LOG_FILE="$LOG_DIR/system-clean.log"
REVIEW_FILE="$LOG_DIR/review.txt"
MODE="${1:---auto}"
DRY_RUN=false
INTERACTIVE=false

mkdir -p "$LOG_DIR"

case "$MODE" in
    --dry-run) DRY_RUN=true ;;
    --manual)  INTERACTIVE=true ;;
    --report)
        if [ -f "$LOG_FILE" ]; then
            echo "=== Last 100 log lines ==="
            tail -100 "$LOG_FILE"
            echo ""
            if [ -f "$REVIEW_FILE" ] && [ -s "$REVIEW_FILE" ]; then
                echo "=== Items needing your review ==="
                cat "$REVIEW_FILE"
            else
                echo "=== No items pending review ==="
            fi
        else
            echo "No log file found yet. Run system-clean.sh first."
        fi
        exit 0
        ;;
    --auto) ;;
    *)
        echo "Usage: system-clean.sh [--auto|--manual|--dry-run|--report]"
        exit 1
        ;;
esac

# -------------------------------------------------------
# LOGGING
# -------------------------------------------------------
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" | tee -a "$LOG_FILE"
}

log_review() {
    echo "[$(date '+%Y-%m-%d')] $*" >> "$REVIEW_FILE"
}

# -------------------------------------------------------
# HELPERS
# -------------------------------------------------------
move_file() {
    local src="$1"
    local dest_dir="$2"
    local filename
    filename=$(basename "$src")

    if $DRY_RUN; then
        log "  [DRY-RUN] Would move: $filename → $dest_dir/"
        return
    fi

    mkdir -p "$dest_dir"

    # Handle filename collisions
    if [ -f "$dest_dir/$filename" ]; then
        local base="${filename%.*}"
        local ext="${filename##*.}"
        local counter=1
        while [ -f "$dest_dir/${base}_${counter}.${ext}" ]; do
            ((counter++))
        done
        filename="${base}_${counter}.${ext}"
    fi

    mv "$src" "$dest_dir/$filename"
    log "  [MOVED] $(basename "$src") → $dest_dir/"
}

ask_user() {
    # In auto mode, send to review file instead of prompting
    local question="$1"
    local file="$2"
    if $INTERACTIVE; then
        echo ""
        echo "  [?] $question"
        echo "      File: $file"
        read -rp "      Action? [m=move/d=delete/s=skip] " answer
        echo "$answer"
    else
        log_review "REVIEW NEEDED: $question — $file"
        echo "skip"
    fi
}

# -------------------------------------------------------
# FILE TYPE MAP
# Maps extensions to subfolder names under Downloads
# -------------------------------------------------------
get_file_type_folder() {
    local ext="${1,,}"  # lowercase
    case "$ext" in
        # Images
        jpg|jpeg|png|gif|webp|bmp|tiff|tif|heic|avif|svg)
            echo "Images" ;;
        # Video
        mp4|mkv|avi|mov|wmv|flv|webm|m4v|mpg|mpeg)
            echo "Video" ;;
        # Audio
        mp3|flac|wav|ogg|aac|m4a|opus|wma)
            echo "Audio" ;;
        # Documents
        pdf|doc|docx|odt|xls|xlsx|ods|ppt|pptx|odp|txt|md|rtf|csv)
            echo "Documents" ;;
        # Archives
        zip|tar|gz|xz|bz2|7z|rar|zst|tar.gz|tar.xz|tar.zst)
            echo "Archives" ;;
        # Disk images
        iso|img|bin|dmg)
            echo "DiskImages" ;;
        # Code / scripts
        sh|py|js|ts|html|css|json|yaml|yml|toml|conf|cfg|xml|lua|rs|go|cpp|c|h)
            echo "Code" ;;
        # Torrents
        torrent)
            echo "Torrents" ;;
        # Packages
        pkg.tar.zst|pkg.tar.xz|deb|rpm|appimage)
            echo "Packages" ;;
        # Fonts
        ttf|otf|woff|woff2)
            echo "Fonts" ;;
        *)
            echo "" ;;  # unknown — goes to review
    esac
}

# -------------------------------------------------------
# DUPLICATE DETECTION
# Uses MD5 hash to find identical files in a directory
# -------------------------------------------------------
find_duplicates() {
    local dir="$1"
    log "  Scanning for duplicates in $dir..."

    declare -A seen_hashes
    local dupe_count=0

    while IFS= read -r -d '' file; do
        local hash
        hash=$(md5sum "$file" | cut -d' ' -f1)
        if [[ -n "${seen_hashes[$hash]+_}" ]]; then
            log "  [DUPE] $file is identical to ${seen_hashes[$hash]}"
            log_review "DUPLICATE: $file (same as ${seen_hashes[$hash]})"
            ((dupe_count++)) || true
        else
            seen_hashes[$hash]="$file"
        fi
    done < <(find "$dir" -maxdepth 2 -type f -print0 2>/dev/null)

    if [ "$dupe_count" -eq 0 ]; then
        log "  No duplicates found."
    else
        log "  Found $dupe_count duplicate(s) — added to review file."
    fi
}

# -------------------------------------------------------
# 1. DOWNLOADS
# -------------------------------------------------------
clean_downloads() {
    log ""
    log "==> [1/5] Cleaning Downloads..."

    [ -d "$DOWNLOADS" ] || { log "  Downloads folder not found, skipping."; return; }

    local moved=0
    local flagged_old=0
    local unknown=0

    # Process only top-level files (not already-sorted subfolders)
    while IFS= read -r -d '' file; do
        local filename
        filename=$(basename "$file")
        local ext="${filename##*.}"
        local type_folder
        type_folder=$(get_file_type_folder "$ext")

        # Get file modification date for monthly subfolder
        local file_date
        file_date=$(date -r "$file" '+%Y-%m' 2>/dev/null || echo "unknown-date")

        # Flag files older than threshold
        local file_age
        file_age=$(( ( $(date +%s) - $(date -r "$file" +%s) ) / 86400 ))
        if [ "$file_age" -gt "$OLD_FILE_DAYS" ]; then
            log "  [OLD] $filename is ${file_age} days old"
            log_review "OLD FILE ($file_age days): $file"
            ((flagged_old++)) || true
        fi

        if [ -n "$type_folder" ]; then
            # Known type — move to type/YYYY-MM subfolder
            move_file "$file" "$DOWNLOADS/$type_folder/$file_date"
            ((moved++)) || true
        else
            # Unknown type — ask or flag for review
            log "  [UNKNOWN TYPE] $filename (.$ext)"
            if $INTERACTIVE; then
                answer=$(ask_user "Unknown file type .$ext — what to do with $filename?" "$file")
                case "$answer" in
                    d) $DRY_RUN || rm "$file"; log "  [DELETED] $filename" ;;
                    m) move_file "$file" "$DOWNLOADS/Unsorted/$file_date" ;;
                    *) log "  [SKIPPED] $filename" ;;
                esac
            else
                log_review "UNKNOWN TYPE (.${ext}): $file"
                ((unknown++)) || true
            fi
        fi
    done < <(find "$DOWNLOADS" -maxdepth 1 -type f -print0 2>/dev/null)

    log "  Done — moved: $moved, flagged old: $flagged_old, unknown types: $unknown"

    # Duplicate check across Downloads
    find_duplicates "$DOWNLOADS"
}

# -------------------------------------------------------
# 2. DOCUMENTS
# -------------------------------------------------------
clean_documents() {
    log ""
    log "==> [2/5] Cleaning Documents..."

    [ -d "$DOCUMENTS" ] || { log "  Documents folder not found, skipping."; return; }

    # Flag loose files sitting in root of Documents
    local loose=0
    while IFS= read -r -d '' file; do
        local filename
        filename=$(basename "$file")
        log "  [LOOSE] $filename is sitting in Documents root"
        log_review "LOOSE FILE IN DOCUMENTS: $file"
        ((loose++)) || true
    done < <(find "$DOCUMENTS" -maxdepth 1 -type f -print0 2>/dev/null)

    if [ "$loose" -eq 0 ]; then
        log "  Documents root is clean."
    else
        log "  Found $loose loose file(s) in Documents root — added to review."
    fi

    # Duplicate check
    find_duplicates "$DOCUMENTS"
}

# -------------------------------------------------------
# 3. SCREENSHOTS
# -------------------------------------------------------
clean_screenshots() {
    log ""
    log "==> [3/5] Cleaning Screenshots..."

    [ -d "$SCREENSHOTS" ] || { log "  Screenshots folder not found at $SCREENSHOTS, skipping."; return; }

    local moved=0

    while IFS= read -r -d '' file; do
        local filename
        filename=$(basename "$file")
        local ext="${filename##*.}"

        # Only process image files sitting in root of Screenshots
        case "${ext,,}" in
            png|jpg|jpeg|webp) ;;
            *) continue ;;
        esac

        # Get date from file modification time
        local month_folder
        month_folder=$(date -r "$file" '+%Y-%m')

        move_file "$file" "$SCREENSHOTS/$month_folder"
        ((moved++)) || true
    done < <(find "$SCREENSHOTS" -maxdepth 1 -type f -print0 2>/dev/null)

    log "  Done — sorted $moved screenshot(s) into monthly folders."
}

# -------------------------------------------------------
# 4. DOTFILES
# -------------------------------------------------------
clean_dotfiles() {
    log ""
    log "==> [4/5] Checking dotfiles..."

    if [ -z "$DOTFILES" ] || [ ! -d "$DOTFILES" ]; then
        log "  No dotfiles repo configured or found, skipping."
        log "  Tip: set DOTFILES= at the top of this script to enable."
        return
    fi

    if ! command -v git &>/dev/null; then
        log "  git not found, skipping dotfiles check."
        return
    fi

    cd "$DOTFILES"

    # Check for uncommitted changes
    local status
    status=$(git status --short 2>/dev/null || true)
    if [ -n "$status" ]; then
        log "  [UNTRACKED/MODIFIED] Dotfiles repo has uncommitted changes:"
        echo "$status" | while read -r line; do
            log "    $line"
        done
        log_review "DOTFILES: Uncommitted changes in $DOTFILES — run: cd $DOTFILES && git status"
    else
        log "  Dotfiles repo is clean."
    fi

    # List common config files not tracked in the repo
    local untracked_configs=()
    for cfg in \
        "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.config/kitty/kitty.conf" \
        "$HOME/.config/plasma-workspace" "$HOME/.config/kwinrc" \
        "$HOME/.config/fastfetch" "$HOME/.config/auto-cpufreq.conf"; do
        if [ -e "$cfg" ]; then
            # Check if it's tracked in the dotfiles repo
            local rel_path="${cfg#$HOME/}"
            if ! git ls-files --error-unmatch "$rel_path" &>/dev/null 2>&1; then
                untracked_configs+=("$cfg")
            fi
        fi
    done

    if [ ${#untracked_configs[@]} -gt 0 ]; then
        log "  [UNTRACKED CONFIGS] These exist but aren't in your dotfiles repo:"
        for cfg in "${untracked_configs[@]}"; do
            log "    $cfg"
            log_review "UNTRACKED CONFIG: $cfg not in dotfiles repo"
        done
    fi

    cd "$HOME"
}

# -------------------------------------------------------
# 5. PACKAGE MANAGEMENT
# -------------------------------------------------------
clean_packages() {
    log ""
    log "==> [5/5] Package management..."

    # Orphan check
    local orphans
    orphans=$(pacman -Qdtq 2>/dev/null || true)
    if [ -n "$orphans" ]; then
        log "  [ORPHANS FOUND]"
        echo "$orphans" | while read -r pkg; do
            log "    $pkg"
        done
        if $INTERACTIVE; then
            echo ""
            read -rp "  Remove orphans? [y/N] " answer
            if [[ "$answer" =~ ^[Yy]$ ]]; then
                $DRY_RUN || sudo pacman -Rns --noconfirm $orphans
                log "  [REMOVED] Orphans cleaned."
            else
                log "  [SKIPPED] Orphans left in place."
            fi
        else
            log_review "ORPHANS: Run 'sudo pacman -Rns $(echo $orphans | tr '\n' ' ')' to remove"
        fi
    else
        log "  No orphans found."
    fi

    # Pacman cache cleanup — keep last N versions
    log "  Clearing pacman cache (keeping $PACMAN_KEEP_VERSIONS versions per package)..."
    if $DRY_RUN; then
        log "  [DRY-RUN] Would run: paccache -r -k $PACMAN_KEEP_VERSIONS"
    else
        if command -v paccache &>/dev/null; then
            sudo paccache -r -k "$PACMAN_KEEP_VERSIONS" | tee -a "$LOG_FILE"
        else
            log "  [WARN] paccache not found — install pacman-contrib for cache cleanup."
            log_review "MISSING TOOL: Install pacman-contrib for pacman cache management"
        fi
    fi

    # Large explicitly installed packages
    log "  Checking for large explicitly installed packages (>${LARGE_PKG_MB}MB)..."
    local large_pkgs
    large_pkgs=$(expac -H M '%m\t%n' | sort -rh | awk -v threshold="$LARGE_PKG_MB" \
        'BEGIN{FS="\t"} {size=$1+0; if(size > threshold) print $0}' 2>/dev/null || true)

    if [ -n "$large_pkgs" ]; then
        log "  [LARGE PACKAGES] Explicitly installed packages over ${LARGE_PKG_MB}MB:"
        echo "$large_pkgs" | while read -r line; do
            log "    $line"
        done
        log_review "LARGE PACKAGES: Review these — some may no longer be needed:"$'\n'"$large_pkgs"
    else
        log "  No large packages flagged (expac may not be installed)."
        if ! command -v expac &>/dev/null; then
            log_review "MISSING TOOL: Install expac for large package detection"
        fi
    fi
}

# -------------------------------------------------------
# MAIN
# -------------------------------------------------------
log "=============================================="
log " system-clean.sh starting (mode: $MODE)"
log "=============================================="

# Clear review file at start of each run so it stays current
> "$REVIEW_FILE"

clean_downloads
clean_documents
clean_screenshots
clean_dotfiles
clean_packages

log ""
log "=============================================="
log " Run complete."
if [ -s "$REVIEW_FILE" ]; then
    log " Items need your attention — run:"
    log "   system-clean.sh --report"
fi
log "=============================================="
