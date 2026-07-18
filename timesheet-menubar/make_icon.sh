#!/usr/bin/env bash
#
# Build icon/AppIcon.icns from icon/AppIcon.png (macOS; uses sips + iconutil).
# Regenerate AppIcon.png first with: python3 icon/make_icon.py
#
set -euo pipefail
cd "$(dirname "$0")/icon"

SRC="AppIcon.png"
ICONSET="AppIcon.iconset"

if [[ ! -f "${SRC}" ]]; then
    echo "✗ ${SRC} not found — run: python3 icon/make_icon.py" >&2
    exit 1
fi

rm -rf "${ICONSET}"
mkdir "${ICONSET}"

for s in 16 32 128 256 512; do
    sips -z "$s" "$s"            "${SRC}" --out "${ICONSET}/icon_${s}x${s}.png"    >/dev/null
    sips -z "$((s*2))" "$((s*2))" "${SRC}" --out "${ICONSET}/icon_${s}x${s}@2x.png" >/dev/null
done

iconutil -c icns "${ICONSET}" -o AppIcon.icns
rm -rf "${ICONSET}"
echo "✓ wrote icon/AppIcon.icns"
