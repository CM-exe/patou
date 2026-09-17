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
#   PATOU_SKIP_BASH_HERE  set to skip patou-bash.exe and the bundled
#                         MSYS2 + git download (~150-300 MB) entirely -
#                         only patou.exe gets installed
#   PATOU_MSYS2_BUNDLE_URL  MSYS2 + git bundle to download (default: the
#                           current asset from this repo's rolling
#                           `msys2-bundle` release, built by
#                           .github/workflows/msys2-bundle.yml)

$ErrorActionPreference = 'Stop'

# patou-bash.exe (built from patou-bash/src/main.rs) is a self-contained
# "Open Patou bash here" launcher: it doesn't depend on a system-wide Git
# for Windows install, because this function gives it its own private
# copy - a standalone MSYS2 install (https://www.msys2.org/) with `git`
# already installed into it via `pacman`, extracted into a `msys64\`
# folder right next to patou-bash.exe. See scripts/uninstall.ps1 to
# remove what this adds.
#
# This is a single prebuilt archive, not a fresh MSYS2 setup on this
# machine: the pacman-based bootstrap (extract, bootstrap, install git)
# runs once in CI (.github/workflows/msys2-bundle.yml) rather than on
# every install - here, it's just a download and an extract.
function Install-BundledMsys2 {
    param([string]$InstallDir)

    $msysDir = Join-Path $InstallDir 'msys64'
    $gitPath = Join-Path $msysDir 'usr\bin\git.exe'
    if (Test-Path $gitPath) {
        return
    }

    $bundleUrl = if ($env:PATOU_MSYS2_BUNDLE_URL) {
        $env:PATOU_MSYS2_BUNDLE_URL
    } else {
        'https://github.com/CM-exe/patou/releases/download/msys2-bundle/patou-msys2-x86_64.zip'
    }

    $tmpFile = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString() + '.zip')
    try {
        Write-Host "Downloading $bundleUrl (bundled MSYS2 + git, prebuilt, one-time)"
        Invoke-WebRequest -Uri $bundleUrl -OutFile $tmpFile

        New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
        # tar (built into Windows 10 1803+/11) handles long MSYS2 paths
        # more reliably than Expand-Archive.
        tar -xf $tmpFile -C $InstallDir
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $gitPath)) {
            throw "extraction did not produce $gitPath (exit code $LASTEXITCODE)"
        }
        Write-Host "Installed bundled MSYS2 + git to $msysDir"
    } catch {
        Write-Host "note: could not install the bundled MSYS2 + git ($($_.Exception.Message)) - 'Open Patou bash here' will fall back to a system-wide Git for Windows install if one is found, or do nothing otherwise"
        Remove-Item -Recurse -Force $msysDir -ErrorAction SilentlyContinue
    } finally {
        Remove-Item -Force $tmpFile -ErrorAction SilentlyContinue
    }
}

# Wires up an "Open Patou bash here" folder context menu entry that runs
# patou-bash.exe.
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

if (-not $env:PATOU_SKIP_BASH_HERE) {
    try {
        Install-BundledMsys2 -InstallDir $installDir
        Add-PatouBashHere -InstallDir $installDir
    } catch {
        Write-Host "note: could not set up the 'Open Patou bash here' context menu ($($_.Exception.Message))"
    }
}
