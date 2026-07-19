#!/usr/bin/env bash
#
# home_sizes.sh — Report the size of your home folder and each sub-folder.
#
# Prints the total size of $HOME, then lists every immediate sub-folder
# (including hidden ones) sorted largest-first, with human-readable sizes.
#
# Usage:
#   ./home_sizes.sh            # report on $HOME
#   ./home_sizes.sh /some/dir  # report on another directory
#
set -euo pipefail

target="${1:-$HOME}"

if [[ ! -d "$target" ]]; then
  echo "Not a directory: $target" >&2
  exit 1
fi

echo "Sizes under: $target"
echo

# --- Total size of the whole folder ---------------------------------------
total="$(du -sh "$target" 2>/dev/null | cut -f1)"
echo "Total: ${total}    $target"
echo "-----------------------------------------"

# --- Each immediate sub-folder, largest first -----------------------------
# du -h ...: human-readable size of every immediate sub-directory
# grep -v : drop the summary line for the target itself
# sort -rh: sort by human-readable size, descending
found=0
while IFS=$'\t' read -r size path; do
  [[ "$path" == "$target" ]] && continue   # skip the target's own total
  printf '%8s    %s\n' "$size" "$path"
  found=1
done < <(du -h --max-depth=1 "$target" 2>/dev/null | sort -rh)

if [[ "$found" -eq 0 ]]; then
  echo "(no sub-folders found)"
fi
