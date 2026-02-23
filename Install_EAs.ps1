param(
  [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Get-TerminalRoots {
  $base = Join-Path $env:APPDATA 'MetaQuotes\Terminal'
  if (!(Test-Path $base)) { return @() }
  Get-ChildItem -Path $base -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
}

function Select-FromList {
  param(
    [Parameter(Mandatory=$true)] $items,
    [Parameter(Mandatory=$true)] [string] $title
  )
  if ($items.Count -eq 0) { return $null }
  if ($items.Count -eq 1) { return $items[0] }

  Write-Host $title -ForegroundColor Cyan
  for ($i=0; $i -lt $items.Count; $i++) {
    Write-Host ("[{0}] {1}" -f $i, $items[$i])
  }
  $choice = Read-Host "Pick index"
  if ($choice -match '^\d+$' -and [int]$choice -ge 0 -and [int]$choice -lt $items.Count) {
    return $items[[int]$choice]
  }
  return $null
}

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$eaMt4 = Join-Path $root 'eas\mt4\FLAMEBOTMT4 EA.ex4'
$eaMt5 = Join-Path $root 'eas\mt5\FLAMEBOT MT5 EA.ex5'

if (!(Test-Path $eaMt4)) { throw "Missing: $eaMt4" }
if (!(Test-Path $eaMt5)) { throw "Missing: $eaMt5" }

# Preferred explicit install targets (requested)
$PreferredMt4 = 'C:\Users\Michael Favour\AppData\Roaming\MetaQuotes\Terminal\2191F4A3D14D7B4B1EBB84F924777883\MQL4\Experts\Advisors'
$PreferredMt5 = 'C:\Users\Michael Favour\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Experts\Advisors'

$mt4Dest = $null
$mt5Dest = $null

if (Test-Path -LiteralPath $PreferredMt4) { $mt4Dest = $PreferredMt4 }
if (Test-Path -LiteralPath $PreferredMt5) { $mt5Dest = $PreferredMt5 }

# Fallback to auto-discovery + picker if preferred paths are missing
if (-not $mt4Dest -or -not $mt5Dest) {
  $terminalRoots = Get-TerminalRoots
  if ($terminalRoots.Count -eq 0) {
    throw "Could not find MetaQuotes Terminal folder under APPDATA. Is MT4/MT5 installed?"
  }

  # Candidate install targets
  $mt4Targets = @()
  $mt5Targets = @()
  foreach ($t in $terminalRoots) {
    $p4 = Join-Path $t 'MQL4\Experts\Advisors'
    if (Test-Path $p4) { $mt4Targets += $p4 }
    $p5 = Join-Path $t 'MQL5\Experts\Advisors'
    if (Test-Path $p5) { $mt5Targets += $p5 }
  }

  if (-not $mt4Dest) { $mt4Dest = Select-FromList -items $mt4Targets -title 'Multiple MT4 installs found. Choose where to install MT4 EA:' }
  if (-not $mt5Dest) { $mt5Dest = Select-FromList -items $mt5Targets -title 'Multiple MT5 installs found. Choose where to install MT5 EA:' }
}

if ($null -eq $mt4Dest) { Write-Host 'No MT4 target found (skipping MT4 EA).' -ForegroundColor Yellow }
if ($null -eq $mt5Dest) { Write-Host 'No MT5 target found (skipping MT5 EA).' -ForegroundColor Yellow }

if ($mt4Dest) {
  $dst = Join-Path $mt4Dest (Split-Path -Leaf $eaMt4)
  if ((Test-Path $dst) -and (-not $Force)) {
    Write-Host "MT4 EA already exists: $dst (use -Force to overwrite)" -ForegroundColor Yellow
  } else {
    Copy-Item -Force $eaMt4 $dst
    Write-Host "Installed MT4 EA -> $dst" -ForegroundColor Green
  }
}

if ($mt5Dest) {
  $dst = Join-Path $mt5Dest (Split-Path -Leaf $eaMt5)
  if ((Test-Path $dst) -and (-not $Force)) {
    Write-Host "MT5 EA already exists: $dst (use -Force to overwrite)" -ForegroundColor Yellow
  } else {
    Copy-Item -Force $eaMt5 $dst
    Write-Host "Installed MT5 EA -> $dst" -ForegroundColor Green
  }
}

Write-Host 'Done. Restart MT4/MT5 and attach the EA to a chart.' -ForegroundColor Cyan
