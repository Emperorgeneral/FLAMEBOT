param(
  [string]$Python = "python"
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

Write-Host "[1/4] Installing deps" -ForegroundColor Cyan
& $Python -m pip install --upgrade pip
& $Python -m pip install -r requirements.txt

Write-Host "[2/4] Building with PyInstaller" -ForegroundColor Cyan
$entry = Join-Path $root 'app\flamebot_entry.py'

# Add bundled EA binaries into the dist folder under "eas/".
& $Python -m PyInstaller --noconfirm --clean --name FlameBot --windowed `
  --add-data "eas;eas" `
  $entry

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
Compress-Archive -Path .\dist\FlameBot\* -DestinationPath $zipPath

Write-Host "Done: $zipPath" -ForegroundColor Green
