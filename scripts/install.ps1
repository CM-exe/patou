# Installs the patou CLI by downloading a prebuilt binary from the
# project's GitHub Releases. No Rust toolchain required.
#
# Usage:
#   irm https://raw.githubusercontent.com/CM-exe/patou/main/scripts/install.ps1 | iex
#
# Env vars:
#   PATOU_VERSION      release tag to install, e.g. v0.2.0 (default: latest)
#   PATOU_INSTALL_DIR  directory to install the binary into
#                      (default: $env:LOCALAPPDATA\Patou\bin)

$ErrorActionPreference = 'Stop'

# Best-effort: wires up an "Open Patou bash here" folder context menu
# entry that runs patou-bash.exe (built from src/bin/patou-bash.rs). That
# binary finds Git for Windows and opens a themed Git Bash session itself
# - this just points the menu at it. See scripts/uninstall.ps1 to remove
# what this adds.
function Add-PatouBashHere {
    param([string]$InstallDir)

    $exePath = Join-Path $InstallDir 'patou-bash.exe'
    $commandBase = '"' + $exePath + '"'

    New-Item -Path 'HKCU:\Software\Classes\Directory\Background\shell\PatouBashHere\command' -Force | Out-Null
    Set-Item -Path 'HKCU:\Software\Classes\Directory\Background\shell\PatouBashHere' -Value 'Open Patou bash here'
    Set-Item -Path 'HKCU:\Software\Classes\Directory\Background\shell\PatouBashHere\command' -Value ($commandBase + ' "%V"')

    New-Item -Path 'HKCU:\Software\Classes\Directory\shell\PatouBashHere\command' -Force | Out-Null
    Set-Item -Path 'HKCU:\Software\Classes\Directory\shell\PatouBashHere' -Value 'Open Patou bash here'
    Set-Item -Path 'HKCU:\Software\Classes\Directory\shell\PatouBashHere\command' -Value ($commandBase + ' "%1"')

    Write-Host "Added 'Open Patou bash here' to the folder right-click menu"

    $gitFound = $false
    foreach ($regPath in 'HKCU:\SOFTWARE\GitForWindows', 'HKLM:\SOFTWARE\GitForWindows') {
        if (Test-Path $regPath) { $gitFound = $true; break }
    }
    if (-not $gitFound) {
        Write-Host "note: Git for Windows wasn't found - the menu entry will do nothing until it's installed"
    }
}

$repo = 'CM-exe/patou'
$version = if ($env:PATOU_VERSION) { $env:PATOU_VERSION } else { 'latest' }
$installDir = if ($env:PATOU_INSTALL_DIR) { $env:PATOU_INSTALL_DIR } else { "$env:LOCALAPPDATA\Patou\bin" }
$target = 'x86_64-pc-windows-msvc'
$asset = "patou-$target.zip"

if ($version -eq 'latest') {
    $url = "https://github.com/$repo/releases/latest/download/$asset"
} else {
    $url = "https://github.com/$repo/releases/download/$version/$asset"
}

$tmpDir = Join-Path $env:TEMP ([System.Guid]::NewGuid())
New-Item -ItemType Directory -Path $tmpDir | Out-Null

try {
    $zipPath = Join-Path $tmpDir $asset
    Write-Host "Downloading $url"
    Invoke-WebRequest -Uri $url -OutFile $zipPath

    Expand-Archive -Path $zipPath -DestinationPath $tmpDir -Force

    New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    Move-Item -Force (Join-Path $tmpDir 'patou.exe') (Join-Path $installDir 'patou.exe')
    Move-Item -Force (Join-Path $tmpDir 'patou-bash.exe') (Join-Path $installDir 'patou-bash.exe')

    Write-Host "Installed patou to $installDir\patou.exe"

    $pathEntries = $env:Path -split ';'
    if ($pathEntries -notcontains $installDir) {
        Write-Host "note: $installDir is not on your PATH. Add it, e.g.:"
        Write-Host "  [Environment]::SetEnvironmentVariable('Path', ""`$env:Path;$installDir"", 'User')"
    }
} finally {
    Remove-Item -Recurse -Force $tmpDir
}

try {
    Add-PatouBashHere -InstallDir $installDir
} catch {
    Write-Host "note: could not add the 'Open Patou bash here' context menu ($($_.Exception.Message))"
}
