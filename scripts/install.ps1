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
#   PATOU_SKIP_BASH_HERE  set to skip patou-bash.exe and the bundled Git
#                         for Windows download (~60 MB) entirely - only
#                         patou.exe gets installed
#   PATOU_GIT_TAG      Git for Windows release tag to bundle
#                      (default: v2.55.0.windows.5)
#   PATOU_GIT_ASSET    PortableGit asset filename from that release
#                      (default: PortableGit-2.55.0.5-64-bit.7z.exe)

$ErrorActionPreference = 'Stop'

# patou-bash.exe (built from patou-bash/src/main.rs) is a self-contained
# "Open Patou bash here" launcher: it doesn't depend on a system-wide Git
# for Windows install, because this function gives it its own private
# copy - Git for Windows' official "PortableGit" distribution, extracted
# into a `git\` folder right next to patou-bash.exe. See
# scripts/uninstall.ps1 to remove what this adds.
function Install-BundledGit {
    param([string]$InstallDir)

    $gitDir = Join-Path $InstallDir 'git'
    $minttyPath = Join-Path $gitDir 'usr\bin\mintty.exe'
    if (Test-Path $minttyPath) {
        return
    }

    $gitTag = if ($env:PATOU_GIT_TAG) { $env:PATOU_GIT_TAG } else { 'v2.55.0.windows.5' }
    $gitAsset = if ($env:PATOU_GIT_ASSET) { $env:PATOU_GIT_ASSET } else { 'PortableGit-2.55.0.5-64-bit.7z.exe' }
    $gitUrl = "https://github.com/git-for-windows/git/releases/download/$gitTag/$gitAsset"

    $tmpFile = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString() + '.7z.exe')
    try {
        Write-Host "Downloading $gitUrl (bundled Git for Windows, ~60 MB, one-time)"
        Invoke-WebRequest -Uri $gitUrl -OutFile $tmpFile

        New-Item -ItemType Directory -Force -Path $gitDir | Out-Null
        # The download is a self-extracting 7-Zip archive: -y accepts the
        # license/skips prompts, -o<dir> (no space) sets the destination.
        & $tmpFile -y "-o$gitDir" | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $minttyPath)) {
            throw "extraction did not produce $minttyPath (exit code $LASTEXITCODE)"
        }
        Write-Host "Installed bundled Git for Windows to $gitDir"
    } catch {
        Write-Host "note: could not install bundled Git for Windows ($($_.Exception.Message)) - 'Open Patou bash here' will do nothing until Git for Windows is available"
        Remove-Item -Recurse -Force $gitDir -ErrorAction SilentlyContinue
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
        Install-BundledGit -InstallDir $installDir
        Add-PatouBashHere -InstallDir $installDir
    } catch {
        Write-Host "note: could not set up the 'Open Patou bash here' context menu ($($_.Exception.Message))"
    }
}
