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

# Undo what scripts/install.ps1's Add-VsCodeTerminalProfile added, if
# anything: the "Patou Bash" entry under `terminal.integrated.profiles.windows`
# in every VS Code / VS Code Insiders user settings.json found, leaving the
# rest of each file untouched. Skips (with a note) any settings.json that
# doesn't parse as JSON, rather than risk mangling it.
foreach ($edition in 'Code', 'Code - Insiders') {
    $settingsPath = Join-Path $env:APPDATA "$edition\User\settings.json"
    if (-not (Test-Path $settingsPath)) {
        continue
    }
    try {
        $raw = Get-Content -Raw -Path $settingsPath
        if (-not $raw -or -not $raw.Trim()) {
            continue
        }
        $settings = $raw | ConvertFrom-Json
        $profiles = $settings.'terminal.integrated.profiles.windows'
        if ($null -eq $profiles -or $profiles.PSObject.Properties.Name -notcontains 'Patou Bash') {
            continue
        }
        $profiles.PSObject.Properties.Remove('Patou Bash')
        if (-not $profiles.PSObject.Properties.Name) {
            $settings.PSObject.Properties.Remove('terminal.integrated.profiles.windows')
        }
        ($settings | ConvertTo-Json -Depth 100) | Set-Content -Path $settingsPath -Encoding utf8
        Write-Host "Removed the 'Patou Bash' terminal profile from $settingsPath"
    } catch {
        Write-Host "note: could not clean up $settingsPath ($($_.Exception.Message)) - remove the 'Patou Bash' VS Code terminal profile manually if present"
    }
}

# The "Patou Bash" Start Menu shortcut scripts/install.ps1's
# Add-StartMenuShortcut added, if present.
$shortcutPath = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Patou Bash.lnk'
if (Test-Path $shortcutPath) {
    Remove-Item -Force $shortcutPath
    Write-Host "Removed $shortcutPath"
}

# patou-bash.exe itself, its error log, and patou-shell.sh/patou-bash.minttyrc
# left behind by older patou-bash.exe versions (now written inside the
# bundled msys64\ folder below instead, so removing that covers current ones).
foreach ($name in 'patou-bash.exe', 'patou-shell.sh', 'patou-bash.minttyrc', 'patou-bash-error.log') {
    $path = Join-Path $installDir $name
    if (Test-Path $path) {
        Remove-Item -Force $path
        Write-Host "Removed $path"
    }
}

# The bundled MSYS2 install scripts/install.ps1 extracted (and installed
# git into) for patou-bash.exe - large enough (150-300 MB) to be worth
# cleaning up specifically rather than leaving it behind. `git\` is the
# older, now-unused bundle location from before patou-bash.exe switched
# from Git for Windows' PortableGit to standalone MSYS2 - removed too,
# for anyone upgrading from that version.
foreach ($name in 'msys64', 'git') {
    $dir = Join-Path $installDir $name
    if (Test-Path $dir) {
        Remove-Item -Recurse -Force $dir
        Write-Host "Removed $dir"
    }
}
