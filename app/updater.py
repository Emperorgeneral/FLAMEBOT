"""GitHub Releases updater (Windows).

Design goals:
- No third-party deps.
- Uses GitHub Releases "latest" as the update source.
- Applies updates via a PowerShell helper so the running EXE can be replaced.

Security guarantees enforced here (in addition to HTTPS):
- The downloaded ZIP must match a SHA-256 advertised in the release body
  (line "SHA256: <hex>") or in a sibling "<asset>.sha256" asset.
  If no hash is published, the update is REFUSED.
- ZIP entries are validated before extraction to block path traversal
  (".." segments, absolute paths, drive letters, NTFS streams).
- A persistent "version floor" is kept on disk; updates strictly below it
  are refused (downgrade protection / rollback attack mitigation).

Configuration (env vars):
- FLAMEBOT_GITHUB_OWNER
- FLAMEBOT_GITHUB_REPO
- FLAMEBOT_UPDATE_ASSET (optional; defaults to WINDOWS_UPDATE_ASSET_NAME)
- FLAMEBOT_UPDATE_ALLOW_UNSIGNED (default 0; set to 1 ONLY in dev/CI to
  skip the hash check — never in production builds).
"""

from __future__ import annotations

import json
import os
import re
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
    # Lower-case hex SHA-256 of the asset, parsed from the release body or
    # from a sibling "<asset>.sha256" asset. Empty string if not published.
    asset_sha256: str = ""


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


# ---------------------------------------------------------------------------
# Persistent "version floor" — downgrade protection.
#
# The updater records the highest version it has ever seen successfully
# installed, in a small JSON file inside the install directory. Any update
# whose advertised "latest_version" is strictly below this floor is REFUSED,
# even if the server (or an attacker) advertises it as "latest".
# ---------------------------------------------------------------------------

_VERSION_FLOOR_FILENAME = ".flamebot_version_floor.json"


def _version_floor_path(install_dir: Path) -> Path:
    return Path(install_dir) / _VERSION_FLOOR_FILENAME


def get_recorded_version_floor(install_dir: Path) -> str:
    try:
        p = _version_floor_path(install_dir)
        if not p.is_file():
            return ""
        data = json.loads(p.read_text(encoding="utf-8") or "{}")
        return str((data or {}).get("min_version") or "").strip()
    except Exception:
        return ""


def record_installed_version(install_dir: Path, version: str) -> bool:
    """Persist the highest-ever-installed version. Never lowers the floor."""
    try:
        p = _version_floor_path(install_dir)
        current_floor = get_recorded_version_floor(install_dir)
        new_v = str(version or "").strip()
        if not new_v:
            return False
        if current_floor and _normalize_version(new_v) <= _normalize_version(current_floor):
            return True  # nothing to do; floor already >=
        try:
            p.parent.mkdir(parents=True, exist_ok=True)
        except Exception:
            pass
        payload = json.dumps({"min_version": new_v, "recorded_at": int(time.time())})
        p.write_text(payload, encoding="utf-8")
        return True
    except Exception:
        return False


def is_safe_upgrade(current: str, latest: str, *, install_dir: Optional[Path] = None) -> bool:
    """Strict upgrade gate.

    Returns True only if BOTH:
      - latest > current (strictly newer)
      - latest >= recorded version floor (no rollback below highest-ever seen)
    """
    try:
        if not is_newer_version(current, latest):
            return False
        if install_dir is not None:
            floor = get_recorded_version_floor(install_dir)
            if floor and _normalize_version(latest) < _normalize_version(floor):
                return False
        return True
    except Exception:
        return False


_SHA256_RE = re.compile(r"\b([A-Fa-f0-9]{64})\b")


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


def _http_get_text(url: str, *, timeout: float = 10.0) -> str:
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "text/plain, application/octet-stream",
            "User-Agent": "FlameBot-Updater",
        },
        method="GET",
    )
    with urllib.request.urlopen(req, timeout=float(timeout)) as resp:
        raw = resp.read()
    try:
        return raw.decode("utf-8", errors="ignore")
    except Exception:
        return ""


def _extract_sha256_for_asset(release_body: str, asset_name: str) -> str:
    """Find a published SHA-256 for the named asset inside a GitHub release body.

    Recognised forms (case-insensitive, on any line):
      <asset_name> <hex>
      <asset_name>: <hex>
      sha256(<asset_name>) = <hex>
      SHA256: <hex>            (used only when there is exactly one such line)
    """
    if not release_body:
        return ""
    body = str(release_body)
    name_lc = str(asset_name or "").lower()

    # Pass 1: a line that mentions the asset name AND a 64-hex token.
    for line in body.splitlines():
        line_lc = line.lower()
        if name_lc and name_lc in line_lc:
            m = _SHA256_RE.search(line)
            if m:
                return m.group(1).lower()

    # Pass 2: a single global "SHA256: <hex>" line is acceptable.
    matches = _SHA256_RE.findall(body)
    if len(matches) == 1:
        return matches[0].lower()

    return ""


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
    sha_sidecar_url = ""
    chosen_name = ""
    for a in assets:
        if str(a.get("name") or "") == asset_name:
            asset_url = str(a.get("browser_download_url") or "")
            chosen_name = str(a.get("name") or "")
            break

    if not asset_url:
        # Fallback: first .zip asset
        for a in assets:
            name = str(a.get("name") or "")
            if name.lower().endswith(".zip"):
                asset_url = str(a.get("browser_download_url") or "")
                chosen_name = name
                break

    if not asset_url:
        return None

    # Look for a sibling "<asset>.sha256" asset published alongside the ZIP.
    for a in assets:
        n = str(a.get("name") or "")
        if chosen_name and n.lower() == (chosen_name + ".sha256").lower():
            sha_sidecar_url = str(a.get("browser_download_url") or "")
            break

    asset_sha256 = ""
    # 1) Prefer a sidecar file.
    if sha_sidecar_url:
        try:
            txt = _http_get_text(sha_sidecar_url, timeout=timeout)
            m = _SHA256_RE.search(txt or "")
            if m:
                asset_sha256 = m.group(1).lower()
        except Exception:
            asset_sha256 = ""
    # 2) Else parse the release body.
    if not asset_sha256:
        try:
            asset_sha256 = _extract_sha256_for_asset(str(data.get("body") or ""), chosen_name or asset_name)
        except Exception:
            asset_sha256 = ""

    return UpdateInfo(latest_version=tag, asset_url=asset_url, asset_sha256=asset_sha256)


def _write_updater_ps1(path: Path) -> None:
    script = textwrap.dedent(
        r"""
        param(
          [Parameter(Mandatory=$true)][string]$ZipUrl,
          [Parameter(Mandatory=$true)][string]$InstallDir,
          [Parameter(Mandatory=$true)][string]$ExeName,
          [Parameter(Mandatory=$true)][string]$ProcessName,
          [Parameter(Mandatory=$true)][string]$ExpectedSha256
        )

        $ErrorActionPreference = 'Stop'

        function Show-Err([string]$msg) {
          try {
            Add-Type -AssemblyName PresentationFramework | Out-Null
            [System.Windows.MessageBox]::Show($msg, 'FlameBot Update', 'OK', 'Error') | Out-Null
          } catch { }
        }

        function Test-SafeZipEntry([string]$entryName) {
          if ([string]::IsNullOrWhiteSpace($entryName)) { return $false }
          # Reject NUL and any control chars.
          foreach ($ch in $entryName.ToCharArray()) {
            if ([int]$ch -lt 32) { return $false }
          }
          # Normalise separators.
          $n = $entryName -replace '\\', '/'
          # Reject absolute paths and drive letters.
          if ($n.StartsWith('/')) { return $false }
          if ($n -match '^[A-Za-z]:') { return $false }
          # Reject UNC paths.
          if ($n.StartsWith('//')) { return $false }
          # Reject any ".." segment.
          foreach ($seg in ($n -split '/')) {
            if ($seg -eq '..') { return $false }
            # Reject NTFS alternate data streams.
            if ($seg -match ':') { return $false }
          }
          return $true
        }

        try {
          $install = [IO.Path]::GetFullPath($InstallDir)
          if (-not (Test-Path $install)) { New-Item -ItemType Directory -Force -Path $install | Out-Null }

          $tmpRoot = Join-Path $env:TEMP ('FlameBotUpdate_' + [guid]::NewGuid().ToString('N'))
          New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null

          # Lock down the temp directory ACL so only the current user can read/write it
          # (mitigates same-machine TOCTOU on the downloaded ZIP).
          try {
            $acl = Get-Acl -Path $tmpRoot
            $acl.SetAccessRuleProtection($true, $false)
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
              [System.Security.Principal.WindowsIdentity]::GetCurrent().User,
              'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
            $acl.AddAccessRule($rule)
            Set-Acl -Path $tmpRoot -AclObject $acl
          } catch { }

          $zipPath = Join-Path $tmpRoot 'update.zip'
          # Force TLS 1.2+ for older .NET defaults.
          try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13 } catch { }
          Invoke-WebRequest -UseBasicParsing -Uri $ZipUrl -OutFile $zipPath

          # --- Integrity check ---
          if ([string]::IsNullOrWhiteSpace($ExpectedSha256)) {
            throw "Refusing to install update: no SHA-256 was published for this release."
          }
          $actual = (Get-FileHash -Algorithm SHA256 -Path $zipPath).Hash
          if ($actual -ine $ExpectedSha256) {
            throw ("Update integrity check FAILED. Expected SHA256 " + $ExpectedSha256 + ", got " + $actual + ". Aborting.")
          }

          # --- Pre-extraction path-traversal validation ---
          Add-Type -AssemblyName System.IO.Compression.FileSystem
          $zipObj = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
          try {
            foreach ($entry in $zipObj.Entries) {
              if (-not (Test-SafeZipEntry $entry.FullName)) {
                throw ("Refusing to extract unsafe ZIP entry: " + $entry.FullName)
              }
            }
          } finally { $zipObj.Dispose() }

          $extractDir = Join-Path $tmpRoot 'extract'
          New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
          Expand-Archive -Force -Path $zipPath -DestinationPath $extractDir

          # Defence-in-depth: confirm every extracted file is still under $extractDir.
          $extractFull = [IO.Path]::GetFullPath($extractDir)
          Get-ChildItem -LiteralPath $extractDir -Recurse -Force | ForEach-Object {
            $full = [IO.Path]::GetFullPath($_.FullName)
            if (-not $full.StartsWith($extractFull, [System.StringComparison]::OrdinalIgnoreCase)) {
              throw ("Extracted file escaped extraction directory: " + $full)
            }
          }

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


def launch_powershell_update(
    *,
    zip_url: str,
    install_dir: Path,
    exe_name: str,
    process_name: str,
    expected_sha256: str,
    allow_unsigned: bool = False,
) -> bool:
    """Launch update helper and return True if started.

    ``expected_sha256`` is the lower-case hex SHA-256 of the ZIP asset, taken
    from the GitHub release metadata (sidecar ".sha256" file or release body).
    The update is REFUSED if it is empty, unless ``allow_unsigned`` is True
    (intended for local dev / CI smoke tests only).
    """
    try:
        install_dir = Path(install_dir)
    except Exception:
        return False

    expected = str(expected_sha256 or "").strip().lower()
    if not expected:
        if not allow_unsigned:
            return False
    else:
        # Validate format: 64 hex chars, nothing else.
        if not re.fullmatch(r"[0-9a-f]{64}", expected):
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
        "-ExpectedSha256",
        expected,
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