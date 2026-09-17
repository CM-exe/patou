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
::                           patou-msys2-x86_64.zip asset on the same
::                           release as patou.exe, built by
::                           .github/workflows/msys2-bundle.yml)
::   PATOU_SKIP_VSCODE_PROFILE  set to skip adding the "Patou Bash" VS Code
::                              integrated-terminal profile (see
::                              :add_vscode_terminal_profile)

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
:: -fL (fail on HTTP errors, follow redirects) rather than -fsSL: dropping
:: -s (silent) lets curl show its default progress meter.
curl -fL "%url%" -o "%tmp_dir%\%asset%"
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
  call :add_start_menu_shortcut
  if not defined PATOU_SKIP_VSCODE_PROFILE call :add_vscode_terminal_profile
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
:: every install - here, it's just a download and an extract. It's an
:: asset on the *same* patou release as patou.exe (attached there after
:: the fact, once that release exists - see msys2-bundle.yml), so it
:: uses the exact same %repo%/%version% patou.exe itself came from.
:install_bundled_msys2
setlocal

set "msys_dir=%install_dir%\msys64"
if exist "%msys_dir%\usr\bin\git.exe" (
  endlocal
  goto :eof
)

if not "%PATOU_MSYS2_BUNDLE_URL%"=="" (
  set "bundle_url=%PATOU_MSYS2_BUNDLE_URL%"
) else (
  if "%version%"=="latest" (
    set "bundle_url=https://github.com/%repo%/releases/latest/download/patou-msys2-x86_64.zip"
  ) else (
    set "bundle_url=https://github.com/%repo%/releases/download/%version%/patou-msys2-x86_64.zip"
  )
)
set "bundle_tmp=%TEMP%\patou-msys2-bundle-%RANDOM%.zip"

echo Downloading %bundle_url% (bundled MSYS2 + git, prebuilt, one-time - this is a large download, curl's progress meter below shows how it's going)
:: -fL, not -fsSL: dropping -s (silent) lets curl show its default
:: progress meter, worth having for a download this size.
curl -fL "%bundle_url%" -o "%bundle_tmp%"
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
:: runs patou-bash.exe. Also sets the "Icon" value on each verb key
:: (separate from the icon of the mintty window it opens - see
:: patou-bash/src/main.rs - this is what Explorer shows next to the
:: entry in the right-click menu itself) using patou-bash.exe's own icon
:: (index 0, from build.rs).
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
echo "Icon"="%exe_path_reg%,0">>"%reg_file%"
echo.>>"%reg_file%"
echo [HKEY_CURRENT_USER\Software\Classes\Directory\Background\shell\PatouBashHere\command]>>"%reg_file%"
echo @="\"%exe_path_reg%\" \"%%V\"">>"%reg_file%"
echo.>>"%reg_file%"
echo [HKEY_CURRENT_USER\Software\Classes\Directory\shell\PatouBashHere]>>"%reg_file%"
echo @="Open Patou bash here">>"%reg_file%"
echo "Icon"="%exe_path_reg%,0">>"%reg_file%"
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

:: Adds a "Patou Bash" shortcut to the current user's Start Menu, so it
:: shows up when searching the Start Menu like any other installed app -
:: per-user (%APPDATA%\...), matching the rest of this no-admin install.
:: Uses a small generated VBScript (cscript, built into every Windows
:: version) to create the .lnk file - no PowerShell needed.
:add_start_menu_shortcut
setlocal

set "exe_path=%install_dir%\patou-bash.exe"
set "start_menu_dir=%APPDATA%\Microsoft\Windows\Start Menu\Programs"
if not exist "%start_menu_dir%" mkdir "%start_menu_dir%"
set "shortcut_path=%start_menu_dir%\Patou Bash.lnk"
set "vbs_file=%TEMP%\patou-shortcut-%RANDOM%.vbs"

echo Set oWS = WScript.CreateObject("WScript.Shell")>"%vbs_file%"
echo Set oLink = oWS.CreateShortcut("%shortcut_path%")>>"%vbs_file%"
echo oLink.TargetPath = "%exe_path%">>"%vbs_file%"
echo oLink.IconLocation = "%exe_path%,0">>"%vbs_file%"
echo oLink.WorkingDirectory = "%USERPROFILE%">>"%vbs_file%"
echo oLink.Description = "Open a Patou-branded Git Bash session">>"%vbs_file%"
echo oLink.Save>>"%vbs_file%"

cscript //nologo //b "%vbs_file%"
del /f /q "%vbs_file%" >nul 2>&1

if exist "%shortcut_path%" (
  echo Added 'Patou Bash' to the Start Menu
) else (
  echo note: failed to add the 'Patou Bash' Start Menu shortcut
)

endlocal
goto :eof

:: Adds a "Patou Bash" entry to `terminal.integrated.profiles.windows` in
:: VS Code's (and VS Code Insiders') user settings.json, so the bundled
:: bash shows up as a selectable shell in VS Code's integrated-terminal
:: dropdown. Deliberately separate from add_patou_bash_here above: that
:: one runs patou-bash.exe, which opens mintty as its own standalone
:: window (see patou-bash/src/main.rs) - a different thing from an
:: *integrated* terminal, where VS Code hosts the pty itself. So this
:: points straight at the bundled bash.exe rather than at
:: patou-bash.exe/mintty.
::
:: Unlike install.ps1's Add-VsCodeTerminalProfile (a real read-modify-write
:: via ConvertFrom-Json/ConvertTo-Json), this script has no JSON parser
:: available without depending on PowerShell - which this installer
:: deliberately avoids. Editing arbitrary existing JSON correctly with
:: plain batch text commands isn't realistic, so this downloads a small
:: VBScript helper (scripts/patou-vscode-profile.vbs - cscript is built
:: into every Windows version) that does the actual read-modify-write: it
:: adds the "terminal.integrated.profiles.windows" key if missing, then
:: adds the "Patou Bash" entry under it if missing, leaving the rest of
:: the file untouched. See that file for the CHERE_INVOKING/icon/color
:: reasoning behind the entry it writes.
:add_vscode_terminal_profile
setlocal EnableDelayedExpansion

set "bash_path=%install_dir%\msys64\usr\bin\bash.exe"
if not exist "%bash_path%" (
  endlocal
  goto :eof
)

set "home_win=%USERPROFILE%"
if not defined home_win set "home_win=%HOMEDRIVE%%HOMEPATH%"
set "drive_letter=%home_win:~0,1%"
set "home_rest=%home_win:~2%"
set "home_rest=%home_rest:\=/%"
call :lower drive_letter
set "home_posix=/%drive_letter%%home_rest%"

set "vbs_url=https://raw.githubusercontent.com/%repo%/main/scripts/patou-vscode-profile.vbs"
set "vbs_file=%TEMP%\patou-vscode-profile-%RANDOM%.vbs"
curl -fsSL "%vbs_url%" -o "%vbs_file%"
if errorlevel 1 (
  echo note: could not download the VS Code terminal profile helper - add the 'Patou Bash' VS Code terminal profile manually if you'd like it
  del /f /q "%vbs_file%" >nul 2>&1
  endlocal
  goto :eof
)

set "PATOU_VSCODE_BASH_PATH=%bash_path%"
set "PATOU_VSCODE_HOME_POSIX=%home_posix%"

for %%E in ("Code" "Code - Insiders") do (
  set "user_dir=%APPDATA%\%%~E\User"
  if exist "!user_dir!" (
    set "settings_path=!user_dir!\settings.json"
    set "PATOU_VSCODE_SETTINGS=!settings_path!"
    set "vbs_result="
    for /f "usebackq delims=" %%R in (`cscript //nologo "%vbs_file%" 2^>^&1`) do set "vbs_result=%%R"
    if "!vbs_result!"=="OK" (
      echo Added a 'Patou Bash' terminal profile to !settings_path!
    ) else if "!vbs_result!"=="SKIP" (
      rem Already present - nothing to do.
    ) else (
      echo note: could not update !settings_path! ^(!vbs_result!^) - add the 'Patou Bash' VS Code terminal profile manually if you'd like it
    )
  )
)

set "PATOU_VSCODE_SETTINGS="
set "PATOU_VSCODE_BASH_PATH="
set "PATOU_VSCODE_HOME_POSIX="
del /f /q "%vbs_file%" >nul 2>&1

endlocal
goto :eof

:: Lowercases the single character held by the variable named %1 (used
:: above for a drive letter). Small inline A-Z lookup table rather than a
:: dependency, since batch has no built-in lowercasing.
:lower
setlocal EnableDelayedExpansion
set "s=!%~1!"
for %%A in (A=a B=b C=c D=d E=e F=f G=g H=h I=i J=j K=k L=l M=m N=n O=o P=p Q=q R=r S=s T=t U=u V=v W=w X=x Y=y Z=z) do (
  for /f "tokens=1,2 delims==" %%x in ("%%A") do set "s=!s:%%x=%%y!"
)
endlocal & set "%~1=%s%"
goto :eof
