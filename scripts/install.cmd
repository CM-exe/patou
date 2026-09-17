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
::   PATOU_SKIP_BASH_HERE  set to skip patou-bash.exe and the bundled Git
::                         for Windows download (~60 MB) entirely - only
::                         patou.exe gets installed
::   PATOU_GIT_TAG      Git for Windows release tag to bundle
::                      (default: v2.55.0.windows.5)
::   PATOU_GIT_ASSET    PortableGit asset filename from that release
::                      (default: PortableGit-2.55.0.5-64-bit.7z.exe)

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
  call :install_bundled_git
  call :add_patou_bash_here
)

endlocal
exit /b 0

:: patou-bash.exe (built from patou-bash/src/main.rs) is a self-contained
:: "Open Patou bash here" launcher: it doesn't depend on a system-wide
:: Git for Windows install, because this gives it its own private copy -
:: Git for Windows' official "PortableGit" distribution, extracted into a
:: `git\` folder right next to patou-bash.exe. See scripts/uninstall.cmd
:: to remove what this adds.
:install_bundled_git
setlocal

set "git_dir=%install_dir%\git"
if exist "%git_dir%\usr\bin\mintty.exe" (
  endlocal
  goto :eof
)

if "%PATOU_GIT_TAG%"=="" (set "git_tag=v2.55.0.windows.5") else (set "git_tag=%PATOU_GIT_TAG%")
if "%PATOU_GIT_ASSET%"=="" (set "git_asset=PortableGit-2.55.0.5-64-bit.7z.exe") else (set "git_asset=%PATOU_GIT_ASSET%")
set "git_url=https://github.com/git-for-windows/git/releases/download/%git_tag%/%git_asset%"
set "git_tmp=%TEMP%\patou-portablegit-%RANDOM%.7z.exe"

echo Downloading %git_url% (bundled Git for Windows, ~60 MB, one-time)
curl -fsSL "%git_url%" -o "%git_tmp%"
if errorlevel 1 (
  echo note: could not download bundled Git for Windows - 'Open Patou bash here' will do nothing until Git for Windows is available
  del /f /q "%git_tmp%" >nul 2>&1
  endlocal
  goto :eof
)

if not exist "%git_dir%" mkdir "%git_dir%"
:: The download is a self-extracting 7-Zip archive: -y accepts the
:: license/skips prompts, -o<dir> (no space) sets the destination.
"%git_tmp%" -y "-o%git_dir%" >nul
del /f /q "%git_tmp%" >nul 2>&1

if not exist "%git_dir%\usr\bin\mintty.exe" (
  echo note: extracting bundled Git for Windows failed - 'Open Patou bash here' will do nothing until Git for Windows is available
  rmdir /s /q "%git_dir%" >nul 2>&1
  endlocal
  goto :eof
)

echo Installed bundled Git for Windows to %git_dir%

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
