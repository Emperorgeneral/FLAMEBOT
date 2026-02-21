#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

PYTHON_BIN="${PYTHON_BIN:-python3}"

echo "[1/4] Installing deps"
"$PYTHON_BIN" -m pip install --upgrade pip
"$PYTHON_BIN" -m pip install -r requirements.txt

echo "[2/4] Building with PyInstaller (macOS)"
ENTRY="app/flamebot_entry.py"

rm -rf build dist

"$PYTHON_BIN" -m PyInstaller --noconfirm --clean --name FlameBot --windowed \
  --add-data "eas:eas" \
  "$ENTRY"

echo "[3/4] Staging bundle extras"
# Put EA files beside the app too (easier for users + works with in-app installer fallback).
rm -rf "dist/FlameBot-macOS"
mkdir -p "dist/FlameBot-macOS"
cp -R "dist/FlameBot.app" "dist/FlameBot-macOS/FlameBot.app"
cp -R "eas" "dist/FlameBot-macOS/eas"
cp -f "README-Install-mac.txt" "dist/FlameBot-macOS/README-Install-mac.txt"

echo "[4/4] Creating zip"
cd dist
rm -f "FlameBot-macOS.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "FlameBot-macOS" "FlameBot-macOS.zip"

echo "Done: dist/FlameBot-macOS.zip"