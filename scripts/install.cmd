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

setlocal EnableExtensions

where curl >nul 2>&1
if errorlevel 1 (
  echo error: curl not found - it ships with Windows 10 1803+ / Windows 11 1>&2
  exit /b 1
)
where tar >nul 2>&1
if errorlevel 1 (
  echo error: tar not found - it ships with Windows 10 1803+ / Windows 11 1>&2
  exit /b 1
)

set "repo=CM-exe/patou"
if "%PATOU_VERSION%"=="" (set "version=latest") else (set "version=%PATOU_VERSION%")
if "%PATOU_INSTALL_DIR%"=="" (set "install_dir=%LOCALAPPDATA%\Patou\bin") else (set "install_dir=%PATOU_INSTALL_DIR%")
:: A trailing backslash would break the quoting of every "%install_dir%" below.
if "%install_dir:~-1%"=="\" set "install_dir=%install_dir:~0,-1%"

set "target=x86_64-pc-windows-msvc"
set "asset=patou-%target%.zip"

if "%version%"=="latest" (
  set "url=https://github.com/%repo%/releases/latest/download/%asset%"
) else (
  set "url=https://github.com/%repo%/releases/download/%version%/%asset%"
)

set "tmp_dir=%TEMP%\patou-install-%RANDOM%%RANDOM%"
mkdir "%tmp_dir%" >nul 2>&1
if not exist "%tmp_dir%" (
  echo error: could not create temporary directory %tmp_dir% 1>&2
  exit /b 1
)

echo Downloading %url%
:: -fL (fail on HTTP errors, follow redirects) rather than -fsSL: dropping
:: -s (silent) lets curl show its default progress meter.
curl -fL --retry 3 "%url%" -o "%tmp_dir%\%asset%"
if errorlevel 1 (
  echo error: could not download %url% - see https://github.com/%repo% for other install options 1>&2
  rmdir /s /q "%tmp_dir%"
  exit /b 1
)

tar -xf "%tmp_dir%\%asset%" -C "%tmp_dir%"
if errorlevel 1 (
  echo error: failed to extract %asset% 1>&2
  rmdir /s /q "%tmp_dir%"
  exit /b 1
)

if not exist "%tmp_dir%\patou.exe" (
  echo error: %asset% does not contain patou.exe 1>&2
  rmdir /s /q "%tmp_dir%"
  exit /b 1
)

if not exist "%install_dir%" mkdir "%install_dir%"
move /y "%tmp_dir%\patou.exe" "%install_dir%\patou.exe" >nul
if errorlevel 1 (
  echo error: could not write %install_dir%\patou.exe - is patou currently running? 1>&2
  rmdir /s /q "%tmp_dir%"
  exit /b 1
)

:: patou-bash.exe is optional: older releases only shipped patou.exe.
if exist "%tmp_dir%\patou-bash.exe" (
  move /y "%tmp_dir%\patou-bash.exe" "%install_dir%\patou-bash.exe" >nul
  if errorlevel 1 echo note: could not overwrite patou-bash.exe - is it running? Close it and re-run to update it.
)

rmdir /s /q "%tmp_dir%"

echo Installed patou to %install_dir%\patou.exe

call :add_to_path

if defined PATOU_SKIP_BASH_HERE goto :done
if not exist "%install_dir%\patou-bash.exe" goto :done

call :install_bundled_msys2

:: Writes patou-banner.sh/patou-prompt.sh/minttyrc into the bundled MSYS2
:: install right away (patou-bash.exe's own --customize-only flag - see
:: try_run in patou-bash/src/main.rs), rather than waiting for "Open Patou
:: bash here" to be used for the first time: most importantly, that's what
:: puts `patou` itself on PATH inside a bundled-bash session, which the VS
:: Code terminal profile needs from its very first use too, since it runs
:: bash.exe directly and never goes through patou-bash.exe at all.
if exist "%install_dir%\msys64\usr\bin\bash.exe" "%install_dir%\patou-bash.exe" --customize-only

call :add_patou_bash_here
call :add_start_menu_shortcut
if not defined PATOU_SKIP_VSCODE_PROFILE call :add_vscode_terminal_profile

:done
endlocal
exit /b 0

:: Adds %install_dir% to the *user* PATH (HKCU\Environment, no admin needed)
:: unless it's already there, then broadcasts the change so newly started
:: programs pick it up (setx is used purely for that broadcast, through the
:: harmless PATOU_INSTALL_DIR variable - `setx PATH` itself is avoided: it
:: truncates at 1024 characters, flattens %VARS% and merges the system PATH
:: into the user one). The existing value is read back through `reg query`,
:: whose output goes through the console codepage, so a PATH holding
:: non-ASCII characters (e.g. C:\Users\Clement) is left untouched rather
:: than risk corrupting it - the user is told to add the directory by hand.
:add_to_path
setlocal
set "user_path="
for /f "tokens=2,*" %%A in ('reg query "HKCU\Environment" /v Path 2^>nul ^| findstr /i /r /c:"^ *Path  *REG_"') do set "user_path=%%B"
setlocal EnableDelayedExpansion

set "chk=;!PATH!;"
if /i not "!chk:;%install_dir%;=!"=="!chk!" goto :add_to_path_end

:: Allow-list of plain ASCII characters, spelled out (no a-z ranges: findstr's
:: ranges follow the locale's collation and wrongly accept accented letters,
:: and the obvious [^ -~] negated range makes findstr hang).
if defined user_path >"%TEMP%\patou-path-check.txt" echo(!user_path!
if defined user_path findstr /r /c:"^[abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _.;:\\/%%()+,~=&#@$-]*$" "%TEMP%\patou-path-check.txt" >nul
if defined user_path if errorlevel 1 del /f /q "%TEMP%\patou-path-check.txt" & goto :add_to_path_manual
del /f /q "%TEMP%\patou-path-check.txt" >nul 2>&1

set "chk=;!user_path!;"
if /i not "!chk:;%install_dir%;=!"=="!chk!" goto :add_to_path_broadcast

set "new_path=!user_path!;%install_dir%"
if not defined user_path set "new_path=%install_dir%"
if "!user_path:~-1!"==";" set "new_path=!user_path!%install_dir%"

reg add "HKCU\Environment" /v Path /t REG_EXPAND_SZ /d "!new_path!" /f >nul
if errorlevel 1 goto :add_to_path_manual
echo Added %install_dir% to your user PATH

:add_to_path_broadcast
setx PATOU_INSTALL_DIR "%install_dir%" >nul 2>&1
echo note: open a new terminal for the PATH change to take effect

:add_to_path_end
endlocal & endlocal
goto :eof

:add_to_path_manual
echo note: %install_dir% is not on your PATH - add it manually ^(Win+R, sysdm.cpl, Advanced, Environment Variables^)
endlocal & endlocal
goto :eof

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
if exist "%msys_dir%\usr\bin\git.exe" goto :msys_done

if not "%PATOU_MSYS2_BUNDLE_URL%"=="" (
  set "bundle_url=%PATOU_MSYS2_BUNDLE_URL%"
) else if "%version%"=="latest" (
  set "bundle_url=https://github.com/%repo%/releases/latest/download/patou-msys2-x86_64.zip"
) else (
  set "bundle_url=https://github.com/%repo%/releases/download/%version%/patou-msys2-x86_64.zip"
)
set "bundle_tmp=%TEMP%\patou-msys2-bundle-%RANDOM%%RANDOM%.zip"

echo Downloading %bundle_url% ^(bundled MSYS2 + git, prebuilt, one-time - this is a large download, curl's progress meter below shows how it's going^)
curl -fL --retry 3 "%bundle_url%" -o "%bundle_tmp%"
if errorlevel 1 (
  echo note: could not download the bundled MSYS2 + git - 'Open Patou bash here' will fall back to a system-wide Git for Windows install if one is found, or do nothing otherwise
  del /f /q "%bundle_tmp%" >nul 2>&1
  goto :msys_done
)

if not exist "%install_dir%" mkdir "%install_dir%"
tar -xf "%bundle_tmp%" -C "%install_dir%"
del /f /q "%bundle_tmp%" >nul 2>&1

if not exist "%msys_dir%\usr\bin\git.exe" (
  echo note: extracting the bundled MSYS2 + git failed - 'Open Patou bash here' will fall back to a system-wide Git for Windows install if one is found, or do nothing otherwise
  rmdir /s /q "%msys_dir%" >nul 2>&1
  goto :msys_done
)

echo Installed bundled MSYS2 + git to %msys_dir%

:msys_done
endlocal
goto :eof

:: Wires up an "Open Patou bash here" folder context menu entry that
:: runs patou-bash.exe. Also sets the "Icon" value on each verb key
:: (separate from the icon of the mintty window it opens - see
:: patou-bash/src/main.rs - this is what Explorer shows next to the
:: entry in the right-click menu itself) using patou-bash.exe's own icon
:: (index 0, from build.rs).
::
:: `reg add` rather than a generated .reg file for `reg import`: a .reg
:: written by cmd.exe is in the console codepage, so a non-ASCII character
:: in the install path (e.g. C:\Users\Clement) would be misread on import,
:: whereas arguments handed straight to reg.exe stay Unicode.
:add_patou_bash_here
setlocal

set "exe_path=%install_dir%\patou-bash.exe"
set "bg_key=HKCU\Software\Classes\Directory\Background\shell\PatouBashHere"
set "dir_key=HKCU\Software\Classes\Directory\shell\PatouBashHere"

reg add "%bg_key%" /ve /d "Open Patou bash here" /f >nul
if errorlevel 1 goto :ctx_failed
reg add "%bg_key%" /v Icon /d "%exe_path%,0" /f >nul
if errorlevel 1 goto :ctx_failed
reg add "%bg_key%\command" /ve /d "\"%exe_path%\" \"%%V\"" /f >nul
if errorlevel 1 goto :ctx_failed
reg add "%dir_key%" /ve /d "Open Patou bash here" /f >nul
if errorlevel 1 goto :ctx_failed
reg add "%dir_key%" /v Icon /d "%exe_path%,0" /f >nul
if errorlevel 1 goto :ctx_failed
reg add "%dir_key%\command" /ve /d "\"%exe_path%\" \"%%1\"" /f >nul
if errorlevel 1 goto :ctx_failed

echo Added 'Open Patou bash here' to the folder right-click menu
endlocal
goto :eof

:ctx_failed
echo note: failed to register the 'Open Patou bash here' context menu
endlocal
goto :eof

:: Adds a "Patou Bash" shortcut to the current user's Start Menu, so it
:: shows up when searching the Start Menu like any other installed app -
:: per-user (%APPDATA%\...), matching the rest of this no-admin install.
:: Uses a small generated VBScript (cscript, built into every Windows
:: version) to create the .lnk file - no PowerShell needed. The script
:: itself is pure ASCII and reads the (possibly non-ASCII) paths from
:: environment variables: a file written by cmd.exe is read back by
:: cscript in the ANSI codepage, which would mangle them.
:add_start_menu_shortcut
setlocal

set "start_menu_dir=%APPDATA%\Microsoft\Windows\Start Menu\Programs"
if not exist "%start_menu_dir%" mkdir "%start_menu_dir%"
set "PATOU_LNK=%start_menu_dir%\Patou Bash.lnk"
set "PATOU_EXE=%install_dir%\patou-bash.exe"
set "vbs_file=%TEMP%\patou-shortcut-%RANDOM%%RANDOM%.vbs"

echo Set s = CreateObject("WScript.Shell")>"%vbs_file%"
echo Set e = s.Environment("Process")>>"%vbs_file%"
echo Set l = s.CreateShortcut(e("PATOU_LNK"))>>"%vbs_file%"
echo l.TargetPath = e("PATOU_EXE")>>"%vbs_file%"
echo l.IconLocation = e("PATOU_EXE") ^& ",0">>"%vbs_file%"
echo l.WorkingDirectory = e("USERPROFILE")>>"%vbs_file%"
echo l.Description = "Open a Patou-branded Git Bash session">>"%vbs_file%"
echo l.Save>>"%vbs_file%"

cscript //nologo "%vbs_file%" >nul 2>&1
del /f /q "%vbs_file%" >nul 2>&1

if exist "%PATOU_LNK%" (
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
:: deliberately avoids. So this downloads a small VBScript helper
:: (scripts/patou-vscode-profile.vbs - cscript is built into every Windows
:: version) that does the actual read-modify-write: it adds the
:: "terminal.integrated.profiles.windows" key if missing, then adds the
:: "Patou Bash" entry under it if missing, leaving the rest of the file
:: untouched. See that file for the CHERE_INVOKING/icon/color reasoning
:: behind the entry it writes, and for the "remove" mode
:: scripts/uninstall.cmd uses to undo this.
:add_vscode_terminal_profile
setlocal EnableDelayedExpansion

set "bash_path=%install_dir%\msys64\usr\bin\bash.exe"
if not exist "%bash_path%" goto :vscode_done

set "home_win=%USERPROFILE%"
if not defined home_win set "home_win=%HOMEDRIVE%%HOMEPATH%"
set "drive_letter=%home_win:~0,1%"
set "home_rest=%home_win:~2%"
set "home_rest=%home_rest:\=/%"
call :lower drive_letter
set "home_posix=/!drive_letter!!home_rest!"

set "vbs_url=https://raw.githubusercontent.com/%repo%/main/scripts/patou-vscode-profile.vbs"
set "vbs_file=%TEMP%\patou-vscode-profile-%RANDOM%%RANDOM%.vbs"
curl -fsSL --retry 3 "%vbs_url%" -o "%vbs_file%"
if errorlevel 1 (
  echo note: could not download the VS Code terminal profile helper - add the 'Patou Bash' VS Code terminal profile manually if you'd like it
  del /f /q "%vbs_file%" >nul 2>&1
  goto :vscode_done
)

set "PATOU_VSCODE_MODE=add"
set "PATOU_VSCODE_BASH_PATH=%bash_path%"
set "PATOU_VSCODE_HOME_POSIX=%home_posix%"

for %%E in ("Code" "Code - Insiders") do (
  set "user_dir=%APPDATA%\%%~E\User"
  if exist "!user_dir!" (
    set "PATOU_VSCODE_SETTINGS=!user_dir!\settings.json"
    set "vbs_result="
    for /f "usebackq delims=" %%R in (`cscript //nologo "%vbs_file%" 2^>^&1`) do set "vbs_result=%%R"
    if "!vbs_result!"=="OK" (
      echo Added a 'Patou Bash' terminal profile to !PATOU_VSCODE_SETTINGS!
    ) else if not "!vbs_result!"=="SKIP" (
      echo note: could not update !PATOU_VSCODE_SETTINGS! ^(!vbs_result!^) - add the 'Patou Bash' VS Code terminal profile manually if you'd like it
    )
  )
)

del /f /q "%vbs_file%" >nul 2>&1

:vscode_done
endlocal
goto :eof

:: Lowercases the single character held by the variable named %1 (used
:: above for a drive letter). `if /i` compares case-insensitively, so the
:: matching lowercase letter is the one picked.
:lower
setlocal EnableDelayedExpansion
set "s=!%~1!"
for %%L in (a b c d e f g h i j k l m n o p q r s t u v w x y z) do if /i "!s!"=="%%L" set "s=%%L"
endlocal & set "%~1=%s%"
goto :eof
