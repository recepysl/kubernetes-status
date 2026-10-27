#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

swift test "$@"
