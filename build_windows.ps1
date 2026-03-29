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
  Write-Host "[1/4] Verifying critical runtime modules" -ForegroundColor Cyan
  & $Python -c "import PyQt5, PyQt5.QtWebEngineWidgets, PyQt5.QtWebChannel, telethon; print('Dependency check OK')"
}

Write-Host "[2/4] Building with PyInstaller" -ForegroundColor Cyan
$entry = Join-Path $root 'app\flamebot_entry.py'

$pyiArgs = @(
  '--noconfirm',
  '--clean',
  '--name', 'FlameBot',
  '--windowed',
  '--hidden-import', 'PyQt5.QtWebEngineWidgets',
  '--hidden-import', 'PyQt5.QtWebEngineCore',
  '--hidden-import', 'PyQt5.QtWebChannel',
  '--collect-all', 'PyQt5.QtWebEngineWidgets',
  '--collect-all', 'PyQt5.QtWebEngineCore',
  '--collect-all', 'PyQt5.QtWebChannel',
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
Write-Host "[3/4] Copying EA files (flattened)" -ForegroundColor Cyan
if (Test-Path .\dist\FlameBot\eas) { Remove-Item -Recurse -Force .\dist\FlameBot\eas }
New-Item -ItemType Directory -Force -Path .\dist\FlameBot\eas | Out-Null
# Copy top-level EAs
Copy-Item -Force (Join-Path $root 'eas\*.ex4') .\dist\FlameBot\eas -ErrorAction SilentlyContinue
Copy-Item -Force (Join-Path $root 'eas\*.ex5') .\dist\FlameBot\eas -ErrorAction SilentlyContinue


Write-Host "[4/4] Building Inno Setup installer" -ForegroundColor Cyan
try {
  $iscc1 = "$env:ProgramFiles\\Inno Setup 6\\ISCC.exe"
  $iscc2 = "$env:ProgramFiles(x86)\\Inno Setup 6\\ISCC.exe"
  $ISCCPath = $null
  if (Test-Path -LiteralPath $iscc1) { $ISCCPath = $iscc1 }
  elseif (Test-Path -LiteralPath $iscc2) { $ISCCPath = $iscc2 }
  elseif (Get-Command ISCC.exe -ErrorAction SilentlyContinue) { $ISCCPath = (Get-Command ISCC.exe).Source }
  if ($ISCCPath) {
    ./build_inno.ps1 -ISCCPath $ISCCPath
  } else {
    Write-Host "ISCC.exe not found. Skipping installer build. Install Inno Setup 6 and re-run .\\build_inno.ps1" -ForegroundColor Yellow
  }
} catch {
  Write-Host "Installer build failed: $($_.Exception.Message)" -ForegroundColor Red
  throw
}

# Create a distributable ZIP that contains the installer EXE and EAs for manual use
Write-Host "[Final] Creating release ZIP (installer + EAs)" -ForegroundColor Cyan

# Read version from app/version.py to locate the installer file
$versionFile = Join-Path $root 'app/version.py'
$version = '1.0'
try {
  if (Test-Path $versionFile) {
    $m = Select-String -Path $versionFile -Pattern 'APP_VERSION\s*=\s*"([^"]+)' -AllMatches | Select-Object -First 1
    if ($m -and $m.Matches.Count -gt 0) { $version = $m.Matches[0].Groups[1].Value }
  }
} catch {}

$installerPath = Join-Path $root ("dist\\FlameBot-Setup-v$version.exe")
$stageDir = Join-Path $root 'dist\FlameBot-Package'
if (Test-Path $stageDir) { Remove-Item -Recurse -Force $stageDir }
New-Item -ItemType Directory -Path $stageDir | Out-Null

if (Test-Path $installerPath) {
  Copy-Item -Force $installerPath $stageDir
} else {
  Write-Host "WARNING: Installer not found at $installerPath. Falling back to portable bundle." -ForegroundColor Yellow
  # Fallback: include the onedir portable app so users can still run without the installer
  $portableSrc = Join-Path $root 'dist\FlameBot'
  if (Test-Path $portableSrc) {
    Copy-Item -Recurse -Force $portableSrc (Join-Path $stageDir 'FlameBot')
  } else {
    Write-Host "Portable folder not found at $portableSrc" -ForegroundColor Red
  }
}

# Include EAs and helper files so users can access them directly (flattened)
$stageEas = Join-Path $stageDir 'eas'
New-Item -ItemType Directory -Force -Path $stageEas | Out-Null
Copy-Item -Force (Join-Path $root 'eas\*.ex4') $stageEas -ErrorAction SilentlyContinue
Copy-Item -Force (Join-Path $root 'eas\*.ex5') $stageEas -ErrorAction SilentlyContinue
Copy-Item -Force .\Install_EAs.ps1 $stageDir
Copy-Item -Force .\README-Install.txt $stageDir

# Produce the Windows zip package
$zipPath = Join-Path $root 'dist\FlameBot-Windows.zip'
if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
Compress-Archive -Path (Join-Path $stageDir '*') -DestinationPath $zipPath

Write-Host "Done. Artifacts:" -ForegroundColor Green
Write-Host " - dist\\FlameBot (portable)" -ForegroundColor Green
Write-Host " - dist\\FlameBot-Setup-v$version.exe (installer if built)" -ForegroundColor Green
Write-Host " - dist\\FlameBot-Windows.zip (zip containing installer or portable + EAs)" -ForegroundColor Green
