#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP="KubernetesStatus.app"
BIN=".build/release/KubernetesStatus"

echo "▸ swift build -c release"
swift build -c release

if [ ! -f Resources/AppIcon.icns ]; then
    echo "▸ generating app icon"
    ./tools/make-icns.sh
fi

echo "▸ assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/KubernetesStatus"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "  (codesign skipped)"

echo "✓ Built $(pwd)/$APP"
