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
#                           patou-msys2-x86_64.zip asset on the same
#                           release as patou.exe, built by
#                           .github/workflows/msys2-bundle.yml)
#   PATOU_SKIP_VSCODE_PROFILE  set to skip adding the "Patou Bash" VS Code
#                              integrated-terminal profile (see
#                              Add-VsCodeTerminalProfile)

$ErrorActionPreference = 'Stop'
# Invoke-WebRequest shows a download progress bar by default, but only
# when $ProgressPreference is 'Continue' - some hosts (certain CI
# runners, some non-interactive contexts) default it to
# 'SilentlyContinue' instead, which would silently drop it. Setting it
# explicitly guarantees a progress bar for every download below,
# regardless of what the calling context set beforehand.
$ProgressPreference = 'Continue'

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
# every install - here, it's just a download and an extract. It's an
# asset on the *same* patou release as patou.exe (attached there after
# the fact, once that release exists - see msys2-bundle.yml), so
# $Version/$Repo below are the exact same ones patou.exe itself came from.
function Install-BundledMsys2 {
    param([string]$InstallDir, [string]$Repo, [string]$Version)

    $msysDir = Join-Path $InstallDir 'msys64'
    $gitPath = Join-Path $msysDir 'usr\bin\git.exe'
    if (Test-Path $gitPath) {
        return
    }

    if ($env:PATOU_MSYS2_BUNDLE_URL) {
        $bundleUrl = $env:PATOU_MSYS2_BUNDLE_URL
    } elseif ($Version -eq 'latest') {
        $bundleUrl = "https://github.com/$Repo/releases/latest/download/patou-msys2-x86_64.zip"
    } else {
        $bundleUrl = "https://github.com/$Repo/releases/download/$Version/patou-msys2-x86_64.zip"
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
# patou-bash.exe. Also sets the "Icon" value on each verb key (separate
# from the icon of the mintty window it opens - see patou-bash/src/main.rs
# - this is what Explorer shows next to the entry in the right-click menu
# itself) using patou-bash.exe's own icon (index 0, from build.rs).
function Add-PatouBashHere {
    param([string]$InstallDir)

    $exePath = Join-Path $InstallDir 'patou-bash.exe'
    $commandBase = '"' + $exePath + '"'
    $iconValue = "$exePath,0"

    New-Item -Path 'HKCU:\Software\Classes\Directory\Background\shell\PatouBashHere\command' -Force | Out-Null
    Set-Item -Path 'HKCU:\Software\Classes\Directory\Background\shell\PatouBashHere' -Value 'Open Patou bash here'
    New-ItemProperty -Path 'HKCU:\Software\Classes\Directory\Background\shell\PatouBashHere' -Name 'Icon' -Value $iconValue -PropertyType String -Force | Out-Null
    Set-Item -Path 'HKCU:\Software\Classes\Directory\Background\shell\PatouBashHere\command' -Value ($commandBase + ' "%V"')

    New-Item -Path 'HKCU:\Software\Classes\Directory\shell\PatouBashHere\command' -Force | Out-Null
    Set-Item -Path 'HKCU:\Software\Classes\Directory\shell\PatouBashHere' -Value 'Open Patou bash here'
    New-ItemProperty -Path 'HKCU:\Software\Classes\Directory\shell\PatouBashHere' -Name 'Icon' -Value $iconValue -PropertyType String -Force | Out-Null
    Set-Item -Path 'HKCU:\Software\Classes\Directory\shell\PatouBashHere\command' -Value ($commandBase + ' "%1"')

    Write-Host "Added 'Open Patou bash here' to the folder right-click menu"
}

# Adds a "Patou Bash" shortcut to the current user's Start Menu, so it
# shows up when searching the Start Menu like any other installed app -
# per-user (%APPDATA%\...), matching the rest of this no-admin install.
function Add-StartMenuShortcut {
    param([string]$InstallDir)

    $exePath = Join-Path $InstallDir 'patou-bash.exe'
    $startMenuDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    New-Item -ItemType Directory -Force -Path $startMenuDir | Out-Null
    $shortcutPath = Join-Path $startMenuDir 'Patou Bash.lnk'

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $exePath
    $shortcut.IconLocation = "$exePath,0"
    $shortcut.WorkingDirectory = $env:USERPROFILE
    $shortcut.Description = 'Open a Patou-branded Git Bash session'
    $shortcut.Save()

    Write-Host "Added 'Patou Bash' to the Start Menu"
}

# "C:\Users\bob" -> "/c/Users/bob" - same conversion patou-bash.exe itself
# applies to HOME (see to_posix_path in patou-bash/src/main.rs): bash
# expects a POSIX-style HOME, not a native Windows path.
function ConvertTo-PosixPath {
    param([string]$Path)
    $slashed = $Path -replace '\\', '/'
    if ($slashed -match '^[A-Za-z]:') {
        return '/' + $slashed.Substring(0, 1).ToLower() + $slashed.Substring(2)
    }
    return $slashed
}

# Adds a "Patou Bash" entry to `terminal.integrated.profiles.windows` in
# every VS Code / VS Code Insiders user settings.json found under
# %APPDATA%, so the bundled bash shows up as a selectable shell in VS
# Code's integrated-terminal dropdown. This is deliberately separate from
# the "Open Patou bash here" context menu entry (Add-PatouBashHere): that
# one runs patou-bash.exe, which launches mintty as its own standalone
# window (see patou-bash/src/main.rs) - a different thing from an
# *integrated* terminal, where VS Code hosts the pty itself. So this
# profile points straight at the bundled bash.exe rather than at
# patou-bash.exe/mintty.
#
# CHERE_INVOKING=1 mirrors the same fix applied to the mintty-based
# launcher's login shell (see launch_branded_mintty in
# patou-bash/src/main.rs): without it, a `--login` bash unconditionally
# `cd`s to $HOME on startup, discarding the working directory VS Code
# actually opened the terminal in.
#
# `icon` is the closest built-in match rather than Patou's own logo: VS
# Code's terminal profile `icon` only accepts a built-in codicon ID for
# profiles defined this way in settings.json, not a path to a custom image
# (see microsoft/vscode issues #127607 and #119343 - there's no way around
# this short of shipping a VS Code extension). `color` at least tints it
# blue, in the spirit of the mintty theme's own grey/blue/light-blue
# palette (assets/patou-bash.minttyrc) - which otherwise has no equivalent
# here, since that palette only applies to mintty's own rendering and VS
# Code hosts this profile in its own terminal (xterm.js) instead. The
# ANSI-colored prompt/banner themselves (patou-prompt.sh/patou-banner.sh,
# sourced via the --login below) still render the same way regardless of
# which terminal is hosting bash, since those come from bash's own escape
# codes rather than from mintty.
#
# Safe to run repeatedly: each settings.json is read-modified-written
# through ConvertFrom-Json/ConvertTo-Json rather than text surgery, so
# unrelated settings and any existing "terminal.integrated.profiles.windows"
# entries survive untouched; a "Patou Bash" entry is replaced in place
# rather than duplicated. Failures (e.g. a settings.json VS Code itself
# would refuse to load) are reported per-edition rather than aborting the
# rest of the install.
function Add-VsCodeTerminalProfile {
    param([string]$MsysDir)

    $bashPath = Join-Path $MsysDir 'usr\bin\bash.exe'
    if (-not (Test-Path $bashPath)) {
        return
    }

    $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { "$env:HOMEDRIVE$env:HOMEPATH" }
    $profileDef = [PSCustomObject]@{
        path  = $bashPath
        args  = @('--login', '-i')
        icon  = 'terminal-bash'
        color = 'terminal.ansiBlue'
        env   = [PSCustomObject]@{
            CHERE_INVOKING = '1'
            HOME           = ConvertTo-PosixPath $homeDir
        }
    }

    foreach ($edition in 'Code', 'Code - Insiders') {
        $userDir = Join-Path $env:APPDATA "$edition\User"
        if (-not (Test-Path $userDir)) {
            continue
        }
        $settingsPath = Join-Path $userDir 'settings.json'

        try {
            $settings = [PSCustomObject]@{}
            if (Test-Path $settingsPath) {
                $raw = Get-Content -Raw -Path $settingsPath
                if ($raw -and $raw.Trim()) {
                    $settings = $raw | ConvertFrom-Json
                }
            }
            if ($settings -isnot [PSCustomObject]) {
                throw "its top-level JSON value isn't an object"
            }

            if ($settings.PSObject.Properties.Name -notcontains 'terminal.integrated.profiles.windows') {
                $settings | Add-Member -NotePropertyName 'terminal.integrated.profiles.windows' -NotePropertyValue ([PSCustomObject]@{})
            }
            $profiles = $settings.'terminal.integrated.profiles.windows'
            if ($profiles -isnot [PSCustomObject]) {
                throw "'terminal.integrated.profiles.windows' isn't a JSON object"
            }

            if ($profiles.PSObject.Properties.Name -contains 'Patou Bash') {
                $profiles.'Patou Bash' = $profileDef
            } else {
                $profiles | Add-Member -NotePropertyName 'Patou Bash' -NotePropertyValue $profileDef
            }

            ($settings | ConvertTo-Json -Depth 100) | Set-Content -Path $settingsPath -Encoding utf8
            Write-Host "Added a 'Patou Bash' terminal profile to $settingsPath"
        } catch {
            Write-Host "note: could not update $settingsPath ($($_.Exception.Message)) - add the 'Patou Bash' VS Code terminal profile manually if you'd like it"
        }
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

if (-not $env:PATOU_SKIP_BASH_HERE) {
    try {
        Install-BundledMsys2 -InstallDir $installDir -Repo $repo -Version $version
        Add-PatouBashHere -InstallDir $installDir
        Add-StartMenuShortcut -InstallDir $installDir
        if (-not $env:PATOU_SKIP_VSCODE_PROFILE) {
            Add-VsCodeTerminalProfile -MsysDir (Join-Path $installDir 'msys64')
        }
    } catch {
        Write-Host "note: could not set up the 'Open Patou bash here' context menu ($($_.Exception.Message))"
    }
}
