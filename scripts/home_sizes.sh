#!/usr/bin/env bash
#
# home_sizes.sh — Report the size of your home folder and what's inside it.
#
# Prints the total size of the target folder, then lists what it contains
# (sub-folders, and optionally large files too) sorted largest-first with
# human-readable sizes.
#
# Usage:
#   ./home_sizes.sh [options] [directory]
#
# Options:
#   -d, --depth N    How many levels deep to descend (default: 1).
#   -n, --top N      Show only the N largest entries (default: all).
#   -f, --files      Include individual files alongside folders.
#   -h, --help       Show this help and exit.
#
# Examples:
#   ./home_sizes.sh                 # top-level sub-folders of $HOME
#   ./home_sizes.sh -n 10           # the 10 biggest sub-folders
#   ./home_sizes.sh -d 2 -f ~/dev   # folders + files, two levels deep
#
set -euo pipefail

depth=1
top=0            # 0 means "no limit"
files=0
target=""

usage() {
  sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
}

# --- Parse arguments ------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--depth) depth="${2:-}"; shift 2 ;;
    -n|--top)   top="${2:-}";   shift 2 ;;
    -f|--files) files=1;        shift ;;
    -h|--help)  usage; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *)  target="$1"; shift ;;
  esac
done

target="${target:-$HOME}"

for n in depth top; do
  if ! [[ "${!n}" =~ ^[0-9]+$ ]]; then
    echo "--${n} needs a whole number, got: ${!n}" >&2
    exit 1
  fi
done

if [[ ! -d "$target" ]]; then
  echo "Not a directory: $target" >&2
  exit 1
fi

# --- Header ---------------------------------------------------------------
label="sub-folders"
[[ "$files" -eq 1 ]] && label="folders & files"
echo "Sizes under: $target   (${label}, depth ${depth})"
echo

total="$(du -sh "$target" 2>/dev/null | cut -f1)"
echo "Total: ${total}    $target"
echo "-----------------------------------------"

# --- Collect entries ------------------------------------------------------
# du gives directory sizes; with --files we also want individual files, so we
# gather those separately via find + du and merge the two lists.
collect() {
  du -h --max-depth="$depth" "$target" 2>/dev/null

  if [[ "$files" -eq 1 ]]; then
    # Files up to `depth` levels below target (a file at depth D lives under
    # find's -maxdepth D). Directories are already covered by du above.
    find "$target" -mindepth 1 -maxdepth "$depth" -type f -print0 2>/dev/null \
      | du -h --files0-from=- 2>/dev/null
  fi
}

found=0
while IFS=$'\t' read -r size path; do
  [[ "$path" == "$target" ]] && continue   # skip the target's own total
  printf '%8s    %s\n' "$size" "$path"
  found=$((found + 1))
  [[ "$top" -gt 0 && "$found" -ge "$top" ]] && break
done < <(collect | sort -rh)

if [[ "$found" -eq 0 ]]; then
  echo "(nothing found)"
fi
