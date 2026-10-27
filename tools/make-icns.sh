#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="Resources/AppIcon.icns"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

MASTER="$WORK/icon-1024.png"
swift tools/make-icon.swift "$MASTER"

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for spec in "16:16x16" "32:16x16@2x" "32:32x32" "64:32x32@2x" \
            "128:128x128" "256:128x128@2x" "256:256x256" "512:256x256@2x" \
            "512:512x512" "1024:512x512@2x"; do
    px="${spec%%:*}"; name="${spec##*:}"
    sips -z "$px" "$px" "$MASTER" --out "$ICONSET/icon_${name}.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$OUT"
echo "✓ Built $OUT"
