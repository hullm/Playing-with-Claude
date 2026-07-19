#!/usr/bin/env bash
#
# mac_system_data_report.sh
#
# Read-only diagnostic for macOS "System Data" bloat. It REPORTS the size of the
# usual space-hogging locations so you can decide what to clean up. It deletes
# NOTHING. Every command below is read-only (du / tmutil listlocalsnapshots).
#
# Usage:
#   bash scripts/mac_system_data_report.sh
#
# Some locations (e.g. /Library, /private/var) need root to read fully. If you
# see "Permission denied" noise or zero sizes for system paths, re-run with:
#   sudo bash scripts/mac_system_data_report.sh
#
set -uo pipefail

# --- pretty helpers ---------------------------------------------------------
bold=$(tput bold 2>/dev/null || true)
dim=$(tput dim 2>/dev/null || true)
reset=$(tput sgr0 2>/dev/null || true)

hr()      { printf '%s\n' "------------------------------------------------------------"; }
section() { printf '\n%s%s%s\n' "$bold" "$1" "$reset"; hr; }

# size <path> [label]
# Prints the human-readable size of a path if it exists, quietly skips if not.
size() {
  local path="$1"
  local label="${2:-$1}"
  if [ -e "$path" ]; then
    # -s summary, -h human; hide permission-denied chatter but keep the total.
    local s
    s=$(du -sh "$path" 2>/dev/null | awk '{print $1}')
    printf '  %-8s  %s\n' "${s:-?}" "$label"
  else
    printf '  %-8s  %s%s%s\n' "--" "$dim" "$label (not present)" "$reset"
  fi
}

# --- header -----------------------------------------------------------------
printf '%smacOS System Data report%s  —  %s\n' "$bold" "$reset" "$(date)"
if [ "$(uname)" != "Darwin" ]; then
  printf '\n%sWarning:%s this is not macOS (uname=%s). Sizes for macOS-specific paths will be empty.\n' \
    "$bold" "$reset" "$(uname)"
fi
if [ "$(id -u)" -ne 0 ]; then
  printf '\n%sTip:%s run with sudo to read system-owned paths fully (see header of this file).\n' "$dim" "$reset"
fi

# --- overall disk -----------------------------------------------------------
section "Overall disk usage"
df -h / 2>/dev/null

# --- Time Machine local snapshots ------------------------------------------
# Often the single biggest hidden chunk of "System Data".
section "Time Machine local snapshots (often the biggest culprit)"
if command -v tmutil >/dev/null 2>&1; then
  snaps=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c 'com.apple.TimeMachine' || true)
  printf '  %s local snapshot(s) on /\n' "${snaps:-0}"
  tmutil listlocalsnapshots / 2>/dev/null | sed 's/^/    /'
  printf '\n  %sThin them (frees space; keeps last 4h) with:%s\n' "$dim" "$reset"
  printf '    sudo tmutil thinlocalsnapshots / 999999999999 4\n'
else
  printf '  tmutil not available (not macOS?)\n'
fi

# --- Caches -----------------------------------------------------------------
section "Caches (safe to clear — apps rebuild them)"
size "$HOME/Library/Caches"            "User caches (~/Library/Caches)"
size "/Library/Caches"                 "System caches (/Library/Caches)"
size "$HOME/Library/Containers"        "App container data (~/Library/Containers)"

# --- Logs & diagnostics -----------------------------------------------------
section "Logs & diagnostic data"
size "$HOME/Library/Logs"              "User logs (~/Library/Logs)"
size "/Library/Logs"                   "System logs (/Library/Logs)"
size "/private/var/log"                "Unix logs (/private/var/log)"
size "/Library/Application Support/CrashReporter" "Crash reports"

# --- iOS device backups & software updates ----------------------------------
section "iOS/iPadOS backups & downloaded updates"
size "$HOME/Library/Application Support/MobileSync/Backup" "iOS device backups"
size "/Library/Updates"               "Downloaded macOS/software updates"

# --- Mail -------------------------------------------------------------------
section "Mail (cached messages & attachments)"
size "$HOME/Library/Mail"             "Mail data (~/Library/Mail)"

# --- Developer junk ---------------------------------------------------------
section "Developer caches (skip if you don't code)"
size "$HOME/Library/Developer/Xcode/DerivedData"  "Xcode DerivedData"
size "$HOME/Library/Developer/Xcode/iOS DeviceSupport" "Xcode iOS DeviceSupport"
size "$HOME/Library/Developer/CoreSimulator"      "iOS Simulators"
size "$HOME/Library/Caches/com.apple.dt.Xcode"    "Xcode cache"
size "$HOME/.npm"                     "npm cache (~/.npm)"
size "$HOME/.cache"                   "Generic ~/.cache"
size "$HOME/Library/Caches/Homebrew"  "Homebrew cache"
size "$HOME/Library/Caches/pip"       "pip cache"
size "$HOME/Library/Containers/com.docker.docker" "Docker data"

# --- Trash & Downloads ------------------------------------------------------
section "Trash & Downloads (obvious, often forgotten)"
size "$HOME/.Trash"                   "Trash"
size "$HOME/Downloads"                "Downloads"

# --- Swap / virtual memory --------------------------------------------------
section "Swap / virtual memory (cleared on restart)"
size "/private/var/vm"                "VM swap files (/private/var/vm)"

# --- footer -----------------------------------------------------------------
section "Next steps"
cat <<'EOF'
  * Biggest quick win is usually thinning Time Machine snapshots (command above).
  * Clear the CONTENTS of cache folders, not the folders themselves.
  * For a visual treemap of the whole disk, use GrandPerspective (free) or
    DaisyDisk. This script lists known hotspots; a treemap finds surprises.
  * A restart recalculates the Storage figures and clears swap.
  * This script only reports sizes. Review each item before deleting anything.
EOF
