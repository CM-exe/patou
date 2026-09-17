@echo off
:: Installs the patou CLI by downloading a prebuilt binary from GitHub
:: Releases, using curl and tar (built into Windows 10 1803+ / Windows 11).
:: No Rust toolchain, no PowerShell required to run this script itself
:: (though setting up the optional bundled MSYS2 below does use
:: PowerShell as an implementation detail - see :install_bundled_msys2).
::
:: Usage:
::   curl -fsSL https://raw.githubusercontent.com/CM-exe/patou/main/scripts/install.cmd -o install.cmd && install.cmd
::
:: Env vars:
::   PATOU_VERSION      release tag to install, e.g. v0.2.0 (default: latest)
::   PATOU_INSTALL_DIR  directory to install the binary into
::                      (default: %LOCALAPPDATA%\Patou\bin)
::   PATOU_SKIP_BASH_HERE  set to skip patou-bash.exe and the bundled
::                         MSYS2 install (~150-300 MB, downloaded from
::                         MSYS2's own package mirrors) entirely - only
::                         patou.exe gets installed
::   PATOU_MSYS2_ASSET_URL  MSYS2 base sfx archive to bundle (default:
::                          the latest from msys2/msys2-installer -
::                          MSYS2 only keeps the latest nightly base
::                          archive, so there isn't an older release to
::                          pin to)

setlocal

set "repo=CM-exe/patou"
if "%PATOU_VERSION%"=="" (set "version=latest") else (set "version=%PATOU_VERSION%")
if "%PATOU_INSTALL_DIR%"=="" (set "install_dir=%LOCALAPPDATA%\Patou\bin") else (set "install_dir=%PATOU_INSTALL_DIR%")

set "target=x86_64-pc-windows-msvc"
set "asset=patou-%target%.zip"

if "%version%"=="latest" (
  set "url=https://github.com/%repo%/releases/latest/download/%asset%"
) else (
  set "url=https://github.com/%repo%/releases/download/%version%/%asset%"
)

set "tmp_dir=%TEMP%\patou-install-%RANDOM%"
mkdir "%tmp_dir%" >nul 2>&1

echo Downloading %url%
curl -fsSL "%url%" -o "%tmp_dir%\%asset%"
if errorlevel 1 (
  echo error: no prebuilt binary for %target% - see https://github.com/%repo% for other install options 1>&2
  rmdir /s /q "%tmp_dir%"
  exit /b 1
)

tar -xf "%tmp_dir%\%asset%" -C "%tmp_dir%"
if errorlevel 1 (
  echo error: failed to extract %asset% 1>&2
  rmdir /s /q "%tmp_dir%"
  exit /b 1
)

if not exist "%install_dir%" mkdir "%install_dir%"
move /y "%tmp_dir%\patou.exe" "%install_dir%\patou.exe" >nul
move /y "%tmp_dir%\patou-bash.exe" "%install_dir%\patou-bash.exe" >nul

rmdir /s /q "%tmp_dir%"

echo Installed patou to %install_dir%\patou.exe

echo ;%PATH%; | find /i ";%install_dir%;" >nul
if errorlevel 1 (
  echo note: %install_dir% is not on your PATH. Add it, e.g.:
  echo   setx PATH "%%PATH%%;%install_dir%"
)

if not defined PATOU_SKIP_BASH_HERE (
  call :install_bundled_msys2
  call :add_patou_bash_here
)

endlocal
exit /b 0

:: patou-bash.exe (built from patou-bash/src/main.rs) is a self-contained
:: "Open Patou bash here" launcher: it doesn't depend on a system-wide
:: Git for Windows install, because this gives it its own private copy -
:: a standalone MSYS2 install (https://www.msys2.org/), extracted and
:: bootstrapped into a `msys64\` folder right next to patou-bash.exe,
:: with `git` installed into it via `pacman`. See scripts/uninstall.cmd
:: to remove what this adds.
::
:: The bootstrap itself (first bash run, a two-pass `pacman -Syuu` with
:: a `taskkill` in between, then installing `git`) needs more branching
:: logic than plain batch handles comfortably, so it's done by a small
:: generated PowerShell script instead - the one place these install
:: scripts use PowerShell as an implementation detail; the overall
:: install still needs no PowerShell to run install.cmd itself.
:install_bundled_msys2
setlocal

set "msys_dir=%install_dir%\msys64"
if exist "%msys_dir%\usr\bin\bash.exe" if exist "%msys_dir%\usr\bin\git.exe" (
  endlocal
  goto :eof
)

set "ps1_file=%TEMP%\patou-msys2-bootstrap-%RANDOM%.ps1"

echo $ErrorActionPreference = 'Stop'>"%ps1_file%"
echo $installDir = $env:install_dir>>"%ps1_file%"
echo $msysDir = Join-Path $installDir 'msys64'>>"%ps1_file%"
echo $bashPath = Join-Path $msysDir 'usr\bin\bash.exe'>>"%ps1_file%"
echo $gitPath = Join-Path $msysDir 'usr\bin\git.exe'>>"%ps1_file%"
echo if ((Test-Path $bashPath) -and (Test-Path $gitPath)) { exit 0 }>>"%ps1_file%"
echo $msys2Url = if ($env:PATOU_MSYS2_ASSET_URL) { $env:PATOU_MSYS2_ASSET_URL } else { 'https://github.com/msys2/msys2-installer/releases/download/nightly-x86_64/msys2-base-x86_64-latest.sfx.exe' }>>"%ps1_file%"
echo $tmpFile = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString() + '.sfx.exe')>>"%ps1_file%"
echo try {>>"%ps1_file%"
echo   if (-not (Test-Path $bashPath)) {>>"%ps1_file%"
echo Write-Host "Downloading $msys2Url (bundled MSYS2 base, ~45 MB, one-time)">>"%ps1_file%"
echo     Invoke-WebRequest -Uri $msys2Url -OutFile $tmpFile>>"%ps1_file%"
echo     ^& $tmpFile -y "-o$installDir" ^| Out-Null>>"%ps1_file%"
echo     if ($LASTEXITCODE -ne 0 -or -not (Test-Path $bashPath)) { throw "extraction did not produce $bashPath" }>>"%ps1_file%"
echo   }>>"%ps1_file%"
echo   Write-Host "Bootstrapping bundled MSYS2 (this can take a few minutes)...">>"%ps1_file%"
echo   ^& $bashPath '-lc' 'uname -a' ^| Out-Null>>"%ps1_file%"
echo   ^& $bashPath '-lc' "sed -i 's/^^CheckSpace/#CheckSpace/g' /etc/pacman.conf" ^| Out-Null>>"%ps1_file%"
echo   ^& $bashPath '-lc' "pacman -Syuu --noconfirm --overwrite '*'" 2^>^&1 ^| Out-Null>>"%ps1_file%"
echo   ^& taskkill /F /FI "MODULES eq msys-2.0.dll" 2^>^&1 ^| Out-Null>>"%ps1_file%"
echo   ^& $bashPath '-lc' "pacman -Syuu --noconfirm --overwrite '*'" ^| Out-Null>>"%ps1_file%"
echo   Write-Host "Installing git into the bundled MSYS2...">>"%ps1_file%"
echo   ^& $bashPath '-lc' "pacman -S --needed --noconfirm --overwrite '*' git" ^| Out-Null>>"%ps1_file%"
echo   if (-not (Test-Path $gitPath)) { throw "pacman did not install $gitPath" }>>"%ps1_file%"
echo   Write-Host "Installed bundled MSYS2 + git to $msysDir">>"%ps1_file%"
echo } catch {>>"%ps1_file%"
echo   Write-Host "note: could not set up bundled MSYS2 ($($_.Exception.Message)) - 'Open Patou bash here' will fall back to a system-wide Git for Windows install if one is found, or do nothing otherwise">>"%ps1_file%"
echo   Remove-Item -Recurse -Force $msysDir -ErrorAction SilentlyContinue>>"%ps1_file%"
echo } finally {>>"%ps1_file%"
echo   Remove-Item -Force $tmpFile -ErrorAction SilentlyContinue>>"%ps1_file%"
echo }>>"%ps1_file%"

echo Setting up bundled MSYS2 (this can take a few minutes)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ps1_file%"
del /f /q "%ps1_file%" >nul 2>&1

endlocal
goto :eof

:: Wires up an "Open Patou bash here" folder context menu entry that
:: runs patou-bash.exe.
:add_patou_bash_here
setlocal

set "exe_path=%install_dir%\patou-bash.exe"
:: .reg string values are backslash-escaped: a literal "\" must be
:: written as "\\", or reg import mangles/rejects the path.
set "exe_path_reg=%exe_path:\=\\%"
set "reg_file=%TEMP%\patou-bash-here-%RANDOM%.reg"

echo Windows Registry Editor Version 5.00>"%reg_file%"
echo.>>"%reg_file%"
echo [HKEY_CURRENT_USER\Software\Classes\Directory\Background\shell\PatouBashHere]>>"%reg_file%"
echo @="Open Patou bash here">>"%reg_file%"
echo.>>"%reg_file%"
echo [HKEY_CURRENT_USER\Software\Classes\Directory\Background\shell\PatouBashHere\command]>>"%reg_file%"
echo @="\"%exe_path_reg%\" \"%%V\"">>"%reg_file%"
echo.>>"%reg_file%"
echo [HKEY_CURRENT_USER\Software\Classes\Directory\shell\PatouBashHere]>>"%reg_file%"
echo @="Open Patou bash here">>"%reg_file%"
echo.>>"%reg_file%"
echo [HKEY_CURRENT_USER\Software\Classes\Directory\shell\PatouBashHere\command]>>"%reg_file%"
echo @="\"%exe_path_reg%\" \"%%1\"">>"%reg_file%"

reg import "%reg_file%" >nul 2>&1
if errorlevel 1 (
  echo note: failed to register the 'Open Patou bash here' context menu
  del /f /q "%reg_file%" >nul 2>&1
  endlocal
  goto :eof
)
del /f /q "%reg_file%" >nul 2>&1
echo Added 'Open Patou bash here' to the folder right-click menu

endlocal
goto :eof
