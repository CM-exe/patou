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

call :add_patou_bash_here

endlocal
exit /b 0

:: Best-effort: wires up an "Open Patou bash here" folder context menu
:: entry that runs patou-bash.exe (built from src/bin/patou-bash.rs). That
:: binary finds Git for Windows and opens a themed Git Bash session itself
:: - this just points the menu at it. See scripts/uninstall.cmd to remove
:: what this adds.
:add_patou_bash_here
setlocal

set "exe_path=%install_dir%\patou-bash.exe"
set "reg_file=%TEMP%\patou-bash-here-%RANDOM%.reg"

echo Windows Registry Editor Version 5.00>"%reg_file%"
echo.>>"%reg_file%"
echo [HKEY_CURRENT_USER\Software\Classes\Directory\Background\shell\PatouBashHere]>>"%reg_file%"
echo @="Open Patou bash here">>"%reg_file%"
echo.>>"%reg_file%"
echo [HKEY_CURRENT_USER\Software\Classes\Directory\Background\shell\PatouBashHere\command]>>"%reg_file%"
echo @="\"%exe_path%\" \"%%V\"">>"%reg_file%"
echo.>>"%reg_file%"
echo [HKEY_CURRENT_USER\Software\Classes\Directory\shell\PatouBashHere]>>"%reg_file%"
echo @="Open Patou bash here">>"%reg_file%"
echo.>>"%reg_file%"
echo [HKEY_CURRENT_USER\Software\Classes\Directory\shell\PatouBashHere\command]>>"%reg_file%"
echo @="\"%exe_path%\" \"%%1\"">>"%reg_file%"

reg import "%reg_file%" >nul 2>&1
if errorlevel 1 (
  echo note: failed to register the 'Open Patou bash here' context menu
  del /f /q "%reg_file%" >nul 2>&1
  endlocal
  goto :eof
)
del /f /q "%reg_file%" >nul 2>&1
echo Added 'Open Patou bash here' to the folder right-click menu

set "git_found="
reg query "HKCU\SOFTWARE\GitForWindows" >nul 2>&1 && set "git_found=1"
if not defined git_found (
  reg query "HKLM\SOFTWARE\GitForWindows" >nul 2>&1 && set "git_found=1"
)
if not defined git_found (
  echo note: Git for Windows wasn't found - the menu entry will do nothing until it's installed
)

endlocal
goto :eof
