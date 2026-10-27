#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build.sh

APP="KubernetesStatus.app"
VOLUME="Kubernetes Status"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)"
mkdir -p dist
DMG="dist/KubernetesStatus-${VERSION}.dmg"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/$APP"
ln -s /Applications "$STAGE/Applications"
cp Resources/AppIcon.icns "$STAGE/.VolumeIcon.icns" 2>/dev/null || true

rm -f "$DMG"
hdiutil create -volname "$VOLUME" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null

echo "✓ Built $(pwd)/$DMG"
