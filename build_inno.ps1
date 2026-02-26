param(
  [string]$ISCCPath,
  [string]$PortableDir = "dist\FlameBot"
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

if (-not (Test-Path -LiteralPath $PortableDir)) {
  Write-Host "Portable dir '$PortableDir' not found; building it first..." -ForegroundColor Yellow
  ./build_windows.ps1 -Python python -SkipDeps:$false
}

# Extract version from app/version.py
$versionFile = Join-Path $root 'app/version.py'
if (-not (Test-Path $versionFile)) { throw "Missing $versionFile" }
$verMatch = Select-String -Path $versionFile -Pattern 'APP_VERSION\s*=\s*"([^"]+)' -AllMatches | Select-Object -First 1
$version = '1.0'
if ($verMatch -and $verMatch.Matches.Count -gt 0) {
  $version = $verMatch.Matches[0].Groups[1].Value
}
Write-Host "Using version: $version" -ForegroundColor Cyan

# Locate ISCC.exe
$possible = @()
if ($ISCCPath) { $possible += $ISCCPath }
$possible += @(
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles(x86)\Inno Setup 6\ISCC.exe"
)
$ISCC = $null
foreach ($p in $possible) {
  if ([string]::IsNullOrWhiteSpace($p)) { continue }
  if (Test-Path -LiteralPath $p) { $ISCC = $p; break }
}
if (-not $ISCC) {
  # Try PATH
  $which = (Get-Command ISCC.exe -ErrorAction SilentlyContinue)
  if ($which) { $ISCC = $which.Source }
}
if (-not $ISCC) {
  Write-Host "ISCC.exe not found. Please install Inno Setup 6 from https://jrsoftware.org/isdl.php and ensure ISCC.exe is in PATH." -ForegroundColor Red
  exit 2
}

$iss = Join-Path $root 'installer/FlameBot.iss'
if (-not (Test-Path -LiteralPath $iss)) { throw "Missing $iss" }

Write-Host "Compiling installer with: $ISCC" -ForegroundColor Cyan
& "$ISCC" "/DMyAppVersion=$version" $iss
if ($LASTEXITCODE -ne 0) { throw "ISCC failed with exit code $LASTEXITCODE" }

Write-Host "Installer build complete. See dist/FlameBot-Setup-v$version.exe" -ForegroundColor Green
