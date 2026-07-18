#!/usr/bin/env bash
#
# Build a distributable "Time Sheets.app" menu bar bundle from the SwiftPM
# executable. Run on a Mac with the Xcode command line tools installed.
#
#   ./build_app.sh            # release build → ./dist/Time Sheets.app
#   ./build_app.sh --run      # build, then launch it
#
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Time Sheets"
EXECUTABLE="TimesheetMenuBar"
CONFIG="release"
DIST_DIR="dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"

echo "▸ Building ${EXECUTABLE} (${CONFIG})…"
swift build -c "${CONFIG}"

BIN_PATH="$(swift build -c "${CONFIG}" --show-bin-path)/${EXECUTABLE}"
if [[ ! -f "${BIN_PATH}" ]]; then
    echo "✗ Executable not found at ${BIN_PATH}" >&2
    exit 1
fi

echo "▸ Assembling ${APP_DIR}…"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BIN_PATH}" "${APP_DIR}/Contents/MacOS/${EXECUTABLE}"
cp "Info.plist" "${APP_DIR}/Contents/Info.plist"

# App icon: build the .icns from the PNG if needed, then bundle it.
if [[ ! -f "icon/AppIcon.icns" && -f "icon/AppIcon.png" ]] && command -v iconutil >/dev/null 2>&1; then
    echo "▸ Building app icon…"
    ./make_icon.sh || echo "  (icon build failed; continuing without a custom icon)"
fi
if [[ -f "icon/AppIcon.icns" ]]; then
    cp "icon/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc code signature so macOS will run it locally without Gatekeeper fuss.
if command -v codesign >/dev/null 2>&1; then
    echo "▸ Ad-hoc signing…"
    codesign --force --deep --sign - "${APP_DIR}" || \
        echo "  (ad-hoc signing failed; the app will still run but may prompt on first launch)"
fi

echo "✓ Built ${APP_DIR}"

if [[ "${1:-}" == "--run" ]]; then
    echo "▸ Launching…"
    open "${APP_DIR}"
fi

cat <<EOF

Next steps:
  • Look for the clock icon in your menu bar.
  • To install: drag "${APP_DIR}" into /Applications.
  • To launch at login: System Settings → General → Login Items → add the app.
EOF
