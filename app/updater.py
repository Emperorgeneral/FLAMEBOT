"""GitHub Releases updater (Windows).

Design goals:
- No third-party deps.
- Uses GitHub Releases "latest" as the update source.
- Applies updates via a PowerShell helper so the running EXE can be replaced.

Configuration (env vars):
- FLAMEBOT_GITHUB_OWNER
- FLAMEBOT_GITHUB_REPO
- FLAMEBOT_UPDATE_ASSET (optional; defaults to WINDOWS_UPDATE_ASSET_NAME)
"""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
import textwrap
import time
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Tuple


@dataclass(frozen=True)
class UpdateInfo:
    latest_version: str
    asset_url: str


def _normalize_version(v: str) -> Tuple[int, ...]:
    """Parse a loose semver-ish string into a tuple for comparison.

    Accepts: "v1.2.3", "1.2", "1".
    Non-numeric suffixes are ignored.
    """
    raw = str(v or "").strip()
    if raw.lower().startswith("v"):
        raw = raw[1:]
    parts = []
    for token in raw.split("."):
        num = ""
        for ch in token:
            if ch.isdigit():
                num += ch
            else:
                break
        if num == "":
            break
        try:
            parts.append(int(num))
        except Exception:
            break
    return tuple(parts) if parts else (0,)


def is_newer_version(current: str, latest: str) -> bool:
    return _normalize_version(latest) > _normalize_version(current)


def _http_get_json(url: str, *, timeout: float = 10.0) -> dict:
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "FlameBot-Updater",
        },
        method="GET",
    )
    with urllib.request.urlopen(req, timeout=float(timeout)) as resp:
        raw = resp.read().decode("utf-8", errors="ignore")
    return json.loads(raw)


def get_latest_github_release(owner: str, repo: str, *, asset_name: str, timeout: float = 10.0) -> Optional[UpdateInfo]:
    owner = str(owner or "").strip()
    repo = str(repo or "").strip()
    if not owner or not repo:
        return None

    data = _http_get_json(f"https://api.github.com/repos/{owner}/{repo}/releases/latest", timeout=timeout)

    tag = str(data.get("tag_name") or data.get("name") or "").strip()
    if not tag:
        return None

    assets = data.get("assets") or []
    asset_url = ""
    for a in assets:
        if str(a.get("name") or "") == asset_name:
            asset_url = str(a.get("browser_download_url") or "")
            break

    if not asset_url:
        # Fallback: first .zip asset
        for a in assets:
            name = str(a.get("name") or "")
            if name.lower().endswith(".zip"):
                asset_url = str(a.get("browser_download_url") or "")
                break

    if not asset_url:
        return None

    return UpdateInfo(latest_version=tag, asset_url=asset_url)


def _write_updater_ps1(path: Path) -> None:
    script = textwrap.dedent(
        r"""
        param(
          [Parameter(Mandatory=$true)][string]$ZipUrl,
          [Parameter(Mandatory=$true)][string]$InstallDir,
          [Parameter(Mandatory=$true)][string]$ExeName,
          [Parameter(Mandatory=$true)][string]$ProcessName
        )

        $ErrorActionPreference = 'Stop'

        function Show-Err([string]$msg) {
          try {
            Add-Type -AssemblyName PresentationFramework | Out-Null
            [System.Windows.MessageBox]::Show($msg, 'FlameBot Update', 'OK', 'Error') | Out-Null
          } catch { }
        }

        try {
          $install = [IO.Path]::GetFullPath($InstallDir)
          if (-not (Test-Path $install)) { New-Item -ItemType Directory -Force -Path $install | Out-Null }

          $tmpRoot = Join-Path $env:TEMP ('FlameBotUpdate_' + [guid]::NewGuid().ToString('N'))
          New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null

          $zipPath = Join-Path $tmpRoot 'update.zip'
          Invoke-WebRequest -UseBasicParsing -Uri $ZipUrl -OutFile $zipPath

          $extractDir = Join-Path $tmpRoot 'extract'
          New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
          Expand-Archive -Force -Path $zipPath -DestinationPath $extractDir

          # Wait for app to exit so files unlock.
          for ($i = 0; $i -lt 120; $i++) {
            $p = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
            if (-not $p) { break }
            Start-Sleep -Milliseconds 500
          }

          # Copy extracted payload into install dir.
          Copy-Item -Force -Recurse -Path (Join-Path $extractDir '*') -Destination $install

          $exePath = Join-Path $install $ExeName
          if (Test-Path $exePath) {
            Start-Process -FilePath $exePath
          } else {
            Show-Err ("Update applied, but could not find executable: " + $exePath)
          }
        } catch {
          Show-Err ("Update failed: " + $_.Exception.Message)
        } finally {
          try { if (Test-Path $tmpRoot) { Remove-Item -Recurse -Force $tmpRoot } } catch { }
        }
        """
    ).strip() + "\n"
    path.write_text(script, encoding="utf-8")


def launch_powershell_update(*, zip_url: str, install_dir: Path, exe_name: str, process_name: str) -> bool:
    """Launch update helper and return True if started."""
    try:
        install_dir = Path(install_dir)
    except Exception:
        return False

    try:
        tmp_dir = Path(tempfile.gettempdir())
        ps1_path = tmp_dir / f"flamebot_update_{int(time.time())}.ps1"
        _write_updater_ps1(ps1_path)
    except Exception:
        return False

    cmd = [
        "powershell",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(ps1_path),
        "-ZipUrl",
        str(zip_url),
        "-InstallDir",
        str(install_dir),
        "-ExeName",
        str(exe_name),
        "-ProcessName",
        str(process_name),
    ]

    creationflags = 0
    try:
        creationflags = subprocess.CREATE_NO_WINDOW  # type: ignore[attr-defined]
    except Exception:
        creationflags = 0

    try:
        subprocess.Popen(cmd, close_fds=True, creationflags=creationflags)
        return True
    except Exception:
        return False


def get_update_config_from_env(
    *,
    default_owner: str = "",
    default_repo: str = "",
    default_asset_name: str,
) -> Tuple[str, str, str]:
    owner = str(os.environ.get("FLAMEBOT_GITHUB_OWNER", "") or "").strip() or str(default_owner or "").strip()
    repo = str(os.environ.get("FLAMEBOT_GITHUB_REPO", "") or "").strip() or str(default_repo or "").strip()
    asset = str(os.environ.get("FLAMEBOT_UPDATE_ASSET", "") or "").strip() or str(default_asset_name)
    return owner, repo, asset
