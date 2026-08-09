#!/usr/bin/env bash
# Builds and runs the native transform tests on the host machine.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$HERE/build"

# cmake is often only available through the Android SDK rather than on PATH
CMAKE="$(command -v cmake || true)"
if [ -z "$CMAKE" ]; then
    SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
    CMAKE="$(ls -d "$SDK"/cmake/*/bin/cmake 2>/dev/null | sort -V | tail -1 || true)"
fi
if [ -z "$CMAKE" ]; then
    echo "cmake not found. Install it, or set ANDROID_HOME to an SDK that bundles it." >&2
    exit 1
fi

"$CMAKE" -S "$HERE" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release > /dev/null
"$CMAKE" --build "$BUILD_DIR"

exec "$BUILD_DIR/native_tests"
