#!/usr/bin/env bash
set -euo pipefail

# Persistence intentionally uses system SQLite from the isolated Swift package.
# This avoids a second static Rust/bundled-SQLite copy in the final iOS link.
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
./build-xcframework.sh
swift package --package-path app/Packages/PinkhaTorah resolve
