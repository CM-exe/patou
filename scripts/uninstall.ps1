# Uninstalls the patou CLI previously installed with scripts/install.ps1.
#
# Usage:
#   irm https://raw.githubusercontent.com/CM-exe/patou/main/scripts/uninstall.ps1 | iex
#
# Env vars:
#   PATOU_INSTALL_DIR  directory patou was installed into
#                      (default: $env:LOCALAPPDATA\Patou\bin)

$ErrorActionPreference = 'Stop'

$installDir = if ($env:PATOU_INSTALL_DIR) { $env:PATOU_INSTALL_DIR } else { "$env:LOCALAPPDATA\Patou\bin" }
$binPath = Join-Path $installDir 'patou.exe'

if (-not (Test-Path $binPath)) {
    Write-Error "patou not found at $binPath - nothing to uninstall (installed with cargo instead? run 'cargo uninstall patou')"
    exit 1
}

Remove-Item -Force $binPath
Write-Host "Removed $binPath"
