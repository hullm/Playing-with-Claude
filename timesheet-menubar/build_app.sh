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

# Code signature. A STABLE identity lets the Keychain remember "Always Allow"
# across launches/rebuilds; ad-hoc signatures change every build and re-prompt.
#
# Preference order:
#   1) $TIMESHEETS_SIGN_ID if you export one
#   2) a self-signed cert named "Time Sheets Signing" (see README to create one)
#   3) ad-hoc (the "-" identity) as a fallback
if command -v codesign >/dev/null 2>&1; then
    SIGN_ID="${TIMESHEETS_SIGN_ID:-}"
    if [[ -z "${SIGN_ID}" ]] && \
       security find-identity -v -p codesigning 2>/dev/null | grep -q "Time Sheets Signing"; then
        SIGN_ID="Time Sheets Signing"
    fi

    if [[ -n "${SIGN_ID}" ]]; then
        echo "▸ Signing with '${SIGN_ID}'…"
        codesign --force --deep --sign "${SIGN_ID}" "${APP_DIR}" || \
            echo "  (signing with '${SIGN_ID}' failed)"
    else
        echo "▸ Ad-hoc signing (Keychain will re-prompt each launch — see README to fix)…"
        codesign --force --deep --sign - "${APP_DIR}" || \
            echo "  (ad-hoc signing failed; the app will still run but may prompt)"
    fi
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
