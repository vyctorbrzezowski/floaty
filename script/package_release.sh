#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-0.1.0}"
APP_NAME="LyricFloater"
ZIP_PATH="$ROOT/outputs/$APP_NAME-v$VERSION.zip"
SHA_PATH="$ROOT/outputs/$APP_NAME-v$VERSION.sha256"

"$ROOT/script/build_and_run.sh" --no-open --verify

rm -f "$ZIP_PATH" "$SHA_PATH"
/usr/bin/ditto -c -k --keepParent "$ROOT/outputs/$APP_NAME.app" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH" > "$SHA_PATH"

echo "$ZIP_PATH"
cat "$SHA_PATH"
