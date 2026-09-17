@echo off
:: Installs the patou CLI by downloading a prebuilt binary from GitHub
:: Releases, using curl and tar (built into Windows 10 1803+ / Windows 11).
:: No Rust toolchain, no PowerShell required.
::
:: Usage:
::   curl -fsSL https://raw.githubusercontent.com/CM-exe/patou/main/scripts/install.cmd -o install.cmd && install.cmd
::
:: Env vars:
::   PATOU_VERSION      release tag to install, e.g. v0.2.0 (default: latest)
::   PATOU_INSTALL_DIR  directory to install the binary into
::                      (default: %LOCALAPPDATA%\Patou\bin)
::   PATOU_SKIP_BASH_HERE  set to skip patou-bash.exe and the bundled
::                         MSYS2 + git download (~150-300 MB) entirely -
::                         only patou.exe gets installed
::   PATOU_MSYS2_BUNDLE_URL  MSYS2 + git bundle to download (default: the
::                           current asset from this repo's rolling
::                           `msys2-bundle` release, built by
::                           .github/workflows/msys2-bundle.yml)

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
:: a standalone MSYS2 install (https://www.msys2.org/) with `git` already
:: installed into it via `pacman`, extracted into a `msys64\` folder
:: right next to patou-bash.exe. See scripts/uninstall.cmd to remove what
:: this adds.
::
:: This is a single prebuilt archive, not a fresh MSYS2 setup on this
:: machine: the pacman-based bootstrap (extract, bootstrap, install git)
:: runs once in CI (.github/workflows/msys2-bundle.yml) rather than on
:: every install - here, it's just a download and an extract.
:install_bundled_msys2
setlocal

set "msys_dir=%install_dir%\msys64"
if exist "%msys_dir%\usr\bin\git.exe" (
  endlocal
  goto :eof
)

if "%PATOU_MSYS2_BUNDLE_URL%"=="" (
  set "bundle_url=https://github.com/CM-exe/patou/releases/download/msys2-bundle/patou-msys2-x86_64.zip"
) else (
  set "bundle_url=%PATOU_MSYS2_BUNDLE_URL%"
)
set "bundle_tmp=%TEMP%\patou-msys2-bundle-%RANDOM%.zip"

echo Downloading %bundle_url% (bundled MSYS2 + git, prebuilt, one-time)
curl -fsSL "%bundle_url%" -o "%bundle_tmp%"
if errorlevel 1 (
  echo note: could not download the bundled MSYS2 + git - 'Open Patou bash here' will fall back to a system-wide Git for Windows install if one is found, or do nothing otherwise
  del /f /q "%bundle_tmp%" >nul 2>&1
  endlocal
  goto :eof
)

if not exist "%install_dir%" mkdir "%install_dir%"
tar -xf "%bundle_tmp%" -C "%install_dir%"
del /f /q "%bundle_tmp%" >nul 2>&1

if not exist "%msys_dir%\usr\bin\git.exe" (
  echo note: extracting the bundled MSYS2 + git failed - 'Open Patou bash here' will fall back to a system-wide Git for Windows install if one is found, or do nothing otherwise
  rmdir /s /q "%msys_dir%" >nul 2>&1
  endlocal
  goto :eof
)

echo Installed bundled MSYS2 + git to %msys_dir%

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
