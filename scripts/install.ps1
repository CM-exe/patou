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
#                         MSYS2 install (~150-300 MB, downloaded from
#                         MSYS2's own package mirrors) entirely - only
#                         patou.exe gets installed
#   PATOU_MSYS2_ASSET_URL  MSYS2 base sfx archive to bundle (default: the
#                          latest from msys2/msys2-installer - MSYS2 only
#                          keeps the latest nightly base archive, so
#                          there isn't an older release to pin to)

$ErrorActionPreference = 'Stop'

# patou-bash.exe (built from patou-bash/src/main.rs) is a self-contained
# "Open Patou bash here" launcher: it doesn't depend on a system-wide Git
# for Windows install, because this function gives it its own private
# copy - a standalone MSYS2 install (https://www.msys2.org/), extracted
# and bootstrapped into a `msys64\` folder right next to patou-bash.exe,
# with `git` installed into it via `pacman`. See scripts/uninstall.ps1 to
# remove what this adds.
#
# The bootstrap (first bash run, then a two-pass `pacman -Syuu` with a
# `taskkill` in between) mirrors the sequence the official
# github.com/msys2/setup-msys2 GitHub Action uses: the base archive's
# own runtime is stale relative to MSYS2's live package repos, and the
# first update pass commonly can't finish because it needs to replace
# usr\bin\msys-2.0.dll itself while some helper process (spawned by
# pacman for package signature verification) still has it open - the
# taskkill clears that before the second pass, which then completes.
function Install-BundledMsys2 {
    param([string]$InstallDir)

    $msysDir = Join-Path $InstallDir 'msys64'
    $bashPath = Join-Path $msysDir 'usr\bin\bash.exe'
    $gitPath = Join-Path $msysDir 'usr\bin\git.exe'
    if ((Test-Path $bashPath) -and (Test-Path $gitPath)) {
        return
    }

    $msys2Url = if ($env:PATOU_MSYS2_ASSET_URL) {
        $env:PATOU_MSYS2_ASSET_URL
    } else {
        'https://github.com/msys2/msys2-installer/releases/download/nightly-x86_64/msys2-base-x86_64-latest.sfx.exe'
    }

    $tmpFile = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString() + '.sfx.exe')
    try {
        if (-not (Test-Path $bashPath)) {
            Write-Host "Downloading $msys2Url (bundled MSYS2 base, ~45 MB, one-time)"
            Invoke-WebRequest -Uri $msys2Url -OutFile $tmpFile

            # The download is a self-extracting 7-Zip archive containing
            # a top-level msys64\ folder: -y accepts the license/skips
            # prompts, -o<dir> (no space) sets the *parent* directory.
            & $tmpFile -y "-o$InstallDir" | Out-Null
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path $bashPath)) {
                throw "extraction did not produce $bashPath (exit code $LASTEXITCODE)"
            }
        }

        Write-Host "Bootstrapping bundled MSYS2 (this can take a few minutes)..."
        & $bashPath '-lc' 'uname -a' | Out-Null

        & $bashPath '-lc' "sed -i 's/^CheckSpace/#CheckSpace/g' /etc/pacman.conf" | Out-Null
        & $bashPath '-lc' "pacman -Syuu --noconfirm --overwrite '*'" 2>&1 | Out-Null
        & taskkill /F /FI "MODULES eq msys-2.0.dll" 2>&1 | Out-Null
        & $bashPath '-lc' "pacman -Syuu --noconfirm --overwrite '*'" | Out-Null

        Write-Host "Installing git into the bundled MSYS2..."
        & $bashPath '-lc' "pacman -S --needed --noconfirm --overwrite '*' git" | Out-Null
        if (-not (Test-Path $gitPath)) {
            throw "pacman did not install $gitPath"
        }

        Write-Host "Installed bundled MSYS2 + git to $msysDir"
    } catch {
        Write-Host "note: could not set up bundled MSYS2 ($($_.Exception.Message)) - 'Open Patou bash here' will fall back to a system-wide Git for Windows install if one is found, or do nothing otherwise"
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
