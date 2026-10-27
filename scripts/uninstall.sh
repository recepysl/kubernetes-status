#!/usr/bin/env bash
set -euo pipefail

APP="/Applications/KubernetesStatus.app"
BUNDLE_ID="io.github.recepysl.kubernetes-status"

pkill -f "KubernetesStatus.app/Contents/MacOS/KubernetesStatus" 2>/dev/null || true
rm -rf "$APP"
defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true

echo "✓ Removed Kubernetes Status and its preferences."
echo "  If it still appears under System Settings → General → Login Items, remove it there."
