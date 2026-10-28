#!/usr/bin/env bash
set -euo pipefail

REPO="recepysl/kubernetes-status"
APP="KubernetesStatus.app"
ASSET_PREFIX="KubernetesStatus-"
DEST="/Applications"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This app only runs on macOS." >&2
  exit 1
fi

tag="${1:-$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)}"
if [[ -z "$tag" ]]; then
  echo "Could not determine the latest release of $REPO." >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "Downloading ${APP} ${tag}..."
curl -fsSL -o "$work/app.zip" "https://github.com/$REPO/releases/download/$tag/$ASSET_PREFIX${tag#v}.zip"
ditto -x -k "$work/app.zip" "$work"

process="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$work/$APP/Contents/Info.plist")"
pkill -x "$process" 2>/dev/null || true

rm -rf "${DEST:?}/$APP"
ditto "$work/$APP" "$DEST/$APP"
xattr -dr com.apple.quarantine "$DEST/$APP" 2>/dev/null || true

open "$DEST/$APP"
echo "Installed $DEST/$APP ($tag) and launched it."
