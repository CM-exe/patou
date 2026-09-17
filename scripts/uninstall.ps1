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

# Undo what scripts/install.ps1's Add-PatouBashHere added, if anything.
foreach ($key in 'HKCU:\Software\Classes\Directory\Background\shell\PatouBashHere', 'HKCU:\Software\Classes\Directory\shell\PatouBashHere') {
    if (Test-Path $key) {
        Remove-Item -Recurse -Force $key
        Write-Host "Removed $key"
    }
}

# patou-bash.exe itself, and the helper files it writes next to itself
# on each launch (patou-shell.sh, patou-bash.minttyrc).
foreach ($name in 'patou-bash.exe', 'patou-shell.sh', 'patou-bash.minttyrc', 'patou-bash-error.log') {
    $path = Join-Path $installDir $name
    if (Test-Path $path) {
        Remove-Item -Force $path
        Write-Host "Removed $path"
    }
}

# The bundled Git for Windows copy scripts/install.ps1 extracted for
# patou-bash.exe (~60 MB - the main reason to clean this up specifically
# rather than leaving it behind).
$gitDir = Join-Path $installDir 'git'
if (Test-Path $gitDir) {
    Remove-Item -Recurse -Force $gitDir
    Write-Host "Removed $gitDir"
}
