param(
  [string]$Python = "python",
  [switch]$SkipDeps
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

if ($SkipDeps) {
  Write-Host "[1/4] Skipping deps" -ForegroundColor Cyan
} else {
  Write-Host "[1/4] Installing deps" -ForegroundColor Cyan
  & $Python -m pip install --upgrade pip
  & $Python -m pip install -r requirements.txt
}

Write-Host "[2/4] Building with PyInstaller" -ForegroundColor Cyan
$entry = Join-Path $root 'app\flamebot_entry.py'

$pyiArgs = @(
  '--noconfirm',
  '--clean',
  '--name', 'FlameBot',
  '--windowed',
  '--icon', 'app\icon.ico',
  '--add-data', 'eas;eas',
  '--add-data', 'app\country.json;.',
  '--add-data', 'app\splash.png;.',
  '--add-data', 'app\icon.ico;.'
)

# Managed Telegram API app config is now embedded in code by default.
# We no longer bundle app\telegram_app.json to keep creds out of the unpacked tree.
if (Test-Path -LiteralPath (Join-Path $root 'app\telegram_app.json')) {
  Write-Host "NOTE: Skipping bundling app\\telegram_app.json (using embedded creds)." -ForegroundColor Yellow
}

# Add bundled EA binaries into the dist folder under "eas/".
& $Python -m PyInstaller @pyiArgs $entry
if ($LASTEXITCODE -ne 0) { throw "PyInstaller failed with exit code $LASTEXITCODE" }

Write-Host "[3/4] Copying helper installer script" -ForegroundColor Cyan
Copy-Item -Force .\Install_EAs.ps1 .\dist\FlameBot\Install_EAs.ps1
Copy-Item -Force .\README-Install.txt .\dist\FlameBot\README-Install.txt

# Ensure EA binaries are shipped as visible files alongside the EXE.
# (PyInstaller may tuck --add-data under _internal/, but we want eas/ at the bundle root
# so both the PowerShell installer and the in-app installer can find it.)
Write-Host "[3/4] Copying EA files" -ForegroundColor Cyan
if (Test-Path .\dist\FlameBot\eas) { Remove-Item -Recurse -Force .\dist\FlameBot\eas }
Copy-Item -Recurse -Force .\eas .\dist\FlameBot\eas

Write-Host "[4/4] Creating zip" -ForegroundColor Cyan
$zipPath = Join-Path $root 'dist\FlameBot-Windows.zip'
if (Test-Path $zipPath) { Remove-Item -Force $zipPath }

# Safety: don't ship local runtime state (can contain developer phone/session).
$stateFiles = @(
  'settings.json',
  'settings_outbox.json',
  'auth.json',
  'desktop_state.json',
  'signals.json',
  'backend_outbox.json'
)
foreach ($name in $stateFiles) {
  $p = Join-Path $root ("dist\FlameBot\" + $name)
  if (Test-Path -LiteralPath $p) {
    try { Remove-Item -Force -LiteralPath $p } catch { }
  }
}
Compress-Archive -Path .\dist\FlameBot\* -DestinationPath $zipPath

Write-Host "Done: $zipPath" -ForegroundColor Green
