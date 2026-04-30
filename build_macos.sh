#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

PYTHON_BIN="${PYTHON_BIN:-python3}"

echo "[1/4] Installing deps"
"$PYTHON_BIN" -m pip install --upgrade pip
"$PYTHON_BIN" -m pip install -r requirements.txt
echo "[1/4] Verifying critical runtime modules"
"$PYTHON_BIN" -c "import PyQt5, PyQt5.QtWebEngineWidgets, PyQt5.QtWebChannel, telethon; print('Dependency check OK')"

echo "[2/4] Building with PyInstaller (macOS)"
ENTRY="app/flamebot_entry.py"

rm -rf build dist

# ---------------------------------------------------------------------------
# Inject the production fetch bearer for /v1/telegram_app_credentials so the
# shipped .app can request the managed Telegram api_id/api_hash from the
# backend without users having to set FLAMEBOT_TG_APP_FETCH_TOKEN themselves.
#
# Required: FLAMEBOT_TG_APP_FETCH_TOKEN must be set in the build shell.
# We always restore app/text5.py to its pre-build state, so the token is
# never left in the source tree on disk (success or failure).
# ---------------------------------------------------------------------------
TEXT5_PATH="app/text5.py"
TEXT5_BACKUP="${TEXT5_PATH}.buildbak"
TEXT5_PATCHED=0

restore_text5() {
  if [[ "${TEXT5_PATCHED}" == "1" && -f "${TEXT5_BACKUP}" ]]; then
    mv -f "${TEXT5_BACKUP}" "${TEXT5_PATH}"
    echo "Restored ${TEXT5_PATH} to its pre-build state."
  fi
}
trap restore_text5 EXIT

if [[ -z "${FLAMEBOT_TG_APP_FETCH_TOKEN:-}" ]]; then
  echo "ERROR: FLAMEBOT_TG_APP_FETCH_TOKEN is not set in this shell."
  echo "       The built .app would NOT be able to fetch managed Telegram"
  echo "       credentials from the backend on first launch. Aborting."
  exit 1
fi
case "${FLAMEBOT_TG_APP_FETCH_TOKEN}" in
  *\"*) echo "ERROR: FLAMEBOT_TG_APP_FETCH_TOKEN must not contain double-quote characters."; exit 1 ;;
esac

cp -f "${TEXT5_PATH}" "${TEXT5_BACKUP}"
TEXT5_PATCHED=1
PLACEHOLDER='_BUILD_TG_APP_FETCH_TOKEN: str = ""'
if ! grep -F -q -- "${PLACEHOLDER}" "${TEXT5_PATH}"; then
  echo "ERROR: Could not find _BUILD_TG_APP_FETCH_TOKEN placeholder in ${TEXT5_PATH}."
  exit 1
fi
# Use python for a literal, single replacement so we don't have to escape sed
# regex metacharacters present in URL-safe base64 tokens.
TEXT5_PATH="${TEXT5_PATH}" FLAMEBOT_TG_APP_FETCH_TOKEN="${FLAMEBOT_TG_APP_FETCH_TOKEN}" "$PYTHON_BIN" - <<'PY'
import os, sys
p = os.environ["TEXT5_PATH"]
tok = os.environ["FLAMEBOT_TG_APP_FETCH_TOKEN"]
placeholder = '_BUILD_TG_APP_FETCH_TOKEN: str = ""'
replacement = f'_BUILD_TG_APP_FETCH_TOKEN: str = "{tok}"'
with open(p, "r", encoding="utf-8") as f:
    s = f.read()
if s.count(placeholder) != 1:
    sys.stderr.write("placeholder not found exactly once\n")
    sys.exit(1)
with open(p, "w", encoding="utf-8") as f:
    f.write(s.replace(placeholder, replacement))
PY
echo "Injected build-time fetch token into ${TEXT5_PATH} (will be reverted after build)."

PYI_ARGS=(
  --noconfirm
  --clean
  --name FlameBot
  --windowed
  --hidden-import PyQt5.QtWebEngineWidgets
  --hidden-import PyQt5.QtWebEngineCore
  --hidden-import PyQt5.QtWebChannel
  --collect-all PyQt5.QtWebEngineWidgets
  --collect-all PyQt5.QtWebEngineCore
  --collect-all PyQt5.QtWebChannel
  --add-data "eas:eas"
  --add-data "app/country.json:."
  --add-data "app/splash.png:."
  --add-data "app/icon.ico:."
)

# Managed Telegram API creds are embedded in code now; don't bundle telegram_app.json.
if [[ -f "app/telegram_app.json" ]]; then
  echo "NOTE: Skipping bundling app/telegram_app.json (using embedded creds)."
fi

"$PYTHON_BIN" -m PyInstaller "${PYI_ARGS[@]}" "$ENTRY"

echo "[3/4] Staging bundle extras"
# Put EA files beside the app too (easier for users + works with in-app installer fallback).
rm -rf "dist/FlameBot-macOS"
mkdir -p "dist/FlameBot-macOS"
cp -R "dist/FlameBot.app" "dist/FlameBot-macOS/FlameBot.app"
cp -R "eas" "dist/FlameBot-macOS/eas"
cp -f "README-Install-mac.txt" "dist/FlameBot-macOS/README-Install-mac.txt"

echo "[4/4] Creating zip and DMG"
cd dist
rm -f "FlameBot-macOS.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "FlameBot-macOS" "FlameBot-macOS.zip"

rm -f "FlameBot-macOS.dmg" "tmp.dmg"
/usr/bin/hdiutil create -volname "FlameBot" -srcfolder "FlameBot-macOS" -fs HFS+ -format UDRW tmp.dmg
/usr/bin/hdiutil convert tmp.dmg -format UDZO -imagekey zlib-level=9 -o "FlameBot-macOS.dmg"
rm -f "tmp.dmg"

echo "Done: dist/FlameBot-macOS.zip"
echo "Done: dist/FlameBot-macOS.dmg"