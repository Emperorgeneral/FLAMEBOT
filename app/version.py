"""App metadata (single source of truth)."""

from __future__ import annotations

APP_NAME = "FlameBot Telegram Copier"

# Keep this in sync with your GitHub Release tag (e.g. v1.0 or 1.0).
APP_VERSION = "2.0.0"

# GitHub repo used for auto-updates (set these before building a release).
# You can still override via env vars at runtime.
GITHUB_OWNER = "Emperorgeneral"
GITHUB_REPO = "FLAMEBOT"

# Default expected GitHub Release asset for Windows updates.
# This matches the output of build_windows.ps1.
WINDOWS_UPDATE_ASSET_NAME = "FlameBot-Windows.zip"