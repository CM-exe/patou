@echo off
:: Uninstalls the patou CLI previously installed with scripts/install.cmd.
::
:: Usage:
::   curl -fsSL https://raw.githubusercontent.com/CM-exe/patou/main/scripts/uninstall.cmd -o uninstall.cmd && uninstall.cmd
::
:: Env vars:
::   PATOU_INSTALL_DIR  directory patou was installed into
::                      (default: %LOCALAPPDATA%\Patou\bin)

setlocal

if "%PATOU_INSTALL_DIR%"=="" (set "install_dir=%LOCALAPPDATA%\Patou\bin") else (set "install_dir=%PATOU_INSTALL_DIR%")
if "%install_dir:~-1%"=="\" set "install_dir=%install_dir:~0,-1%"
set "bin_path=%install_dir%\patou.exe"

if not exist "%bin_path%" (
  echo patou not found at %bin_path% - nothing to uninstall 1>&2
  echo ^(installed with cargo instead? run 'cargo uninstall patou'^) 1>&2
  exit /b 1
)

del /f /q "%bin_path%"
echo Removed %bin_path%

:: Undo what scripts/install.cmd's add_patou_bash_here added, if anything.
for %%K in (
  "Directory\Background\shell\PatouBashHere"
  "Directory\shell\PatouBashHere"
) do (
  reg query "HKCU\Software\Classes\%%~K" >nul 2>&1
  if not errorlevel 1 (
    reg delete "HKCU\Software\Classes\%%~K" /f >nul
    echo Removed HKCU\Software\Classes\%%~K
  )
)

:: Undo what scripts/install.cmd's add_vscode_terminal_profile added, if
:: anything - see remove_vscode_terminal_profile below.
call :remove_vscode_terminal_profile

:: The "Patou Bash" Start Menu shortcut scripts/install.cmd's
:: add_start_menu_shortcut added, if present.
set "shortcut_path=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Patou Bash.lnk"
if exist "%shortcut_path%" (
  del /f /q "%shortcut_path%"
  echo Removed %shortcut_path%
)

:: patou-bash.exe itself, its error log, and patou-shell.sh/patou-bash.minttyrc
:: left behind by older patou-bash.exe versions (now written inside the
:: bundled msys64\ folder below instead, so removing that covers current ones).
for %%N in (patou-bash.exe patou-shell.sh patou-bash.minttyrc patou-bash-error.log) do (
  if exist "%install_dir%\%%N" (
    del /f /q "%install_dir%\%%N"
    echo Removed %install_dir%\%%N
  )
)

:: The bundled MSYS2 install scripts/install.cmd extracted (and installed
:: git into) for patou-bash.exe - large enough (150-300 MB) to be worth
:: cleaning up specifically rather than leaving it behind. `git` is the
:: older, now-unused bundle location from before patou-bash.exe switched
:: from Git for Windows' PortableGit to standalone MSYS2 - removed too,
:: for anyone upgrading from that version.
for %%N in (msys64 git) do (
  if exist "%install_dir%\%%N" (
    rmdir /s /q "%install_dir%\%%N"
    echo Removed %install_dir%\%%N
  )
)

call :remove_from_path

endlocal
exit /b 0

:: Removes %install_dir% from the *user* PATH again (undoing install.cmd's
:add_to_path) and deletes the PATOU_INSTALL_DIR variable it set. Same
:: caution as there: a PATH holding non-ASCII characters (checked with an
:: allow-list, since `reg query` output goes through the console codepage)
:: is left untouched and the user is told to edit it by hand.
:remove_from_path
setlocal
set "user_path="
for /f "tokens=2,*" %%A in ('reg query "HKCU\Environment" /v Path 2^>nul ^| findstr /i /r /c:"^ *Path  *REG_"') do set "user_path=%%B"
setlocal EnableDelayedExpansion

if not defined user_path goto :remove_from_path_var

set "chk=;!user_path!;"
if /i "!chk:;%install_dir%;=!"=="!chk!" goto :remove_from_path_var

>"%TEMP%\patou-path-check.txt" echo(!user_path!
findstr /r /c:"^[abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _.;:\/%%()+,~=&#@$-]*$" "%TEMP%\patou-path-check.txt" >nul
if errorlevel 1 (
  del /f /q "%TEMP%\patou-path-check.txt" >nul 2>&1
  echo note: %install_dir% is still on your PATH - remove it manually ^(Win+R, sysdm.cpl, Advanced, Environment Variables^)
  goto :remove_from_path_var
)
del /f /q "%TEMP%\patou-path-check.txt" >nul 2>&1

:: Twice, so adjacent duplicates (";dir;dir;") are removed too.
set "new_path=;!user_path!;"
set "new_path=!new_path:;%install_dir%;=;!"
set "new_path=!new_path:;%install_dir%;=;!"
if "!new_path:~0,1!"==";" set "new_path=!new_path:~1!"
if "!new_path:~-1!"==";" set "new_path=!new_path:~0,-1!"

reg add "HKCU\Environment" /v Path /t REG_EXPAND_SZ /d "!new_path!" /f >nul
if errorlevel 1 (
  echo note: could not update your user PATH - remove %install_dir% from it manually
  goto :remove_from_path_var
)
echo Removed %install_dir% from your user PATH

:remove_from_path_var
reg query "HKCU\Environment" /v PATOU_INSTALL_DIR >nul 2>&1
if not errorlevel 1 (
  rem setx first, purely to broadcast the environment change.
  setx PATOU_INSTALL_DIR "%install_dir%" >nul 2>&1
  reg delete "HKCU\Environment" /v PATOU_INSTALL_DIR /f >nul 2>&1
)
endlocal & endlocal
goto :eof

:: Removes the "Patou Bash" entry from `terminal.integrated.profiles.windows`
:: in every VS Code / VS Code Insiders user settings.json found (and that
:: key itself too, if removing the entry leaves it empty), leaving the
:: rest of each file untouched. Like install.cmd's add_vscode_terminal_profile
:: (which this mirrors), this script has no JSON parser available without
:: depending on PowerShell, so it downloads the same VBScript helper
:: (scripts/patou-vscode-profile.vbs) that script uses to add the entry,
:: this time invoked in its "remove" mode.
:remove_vscode_terminal_profile
setlocal EnableDelayedExpansion

set "vbs_url=https://raw.githubusercontent.com/CM-exe/patou/main/scripts/patou-vscode-profile.vbs"
set "vbs_file=%TEMP%\patou-vscode-profile-%RANDOM%.vbs"
curl -fsSL "%vbs_url%" -o "%vbs_file%"
if errorlevel 1 (
  for %%E in ("Code" "Code - Insiders") do (
    set "settings_path=%APPDATA%\%%~E\User\settings.json"
    if exist "!settings_path!" (
      findstr /c:"Patou Bash" "!settings_path!" >nul 2>&1
      if not errorlevel 1 (
        echo note: could not download the VS Code terminal profile helper - remove the 'Patou Bash' entry from !settings_path! manually if present
      )
    )
  )
  del /f /q "%vbs_file%" >nul 2>&1
  endlocal
  goto :eof
)

set "PATOU_VSCODE_MODE=remove"

for %%E in ("Code" "Code - Insiders") do (
  set "settings_path=%APPDATA%\%%~E\User\settings.json"
  if exist "!settings_path!" (
    set "PATOU_VSCODE_SETTINGS=!settings_path!"
    set "vbs_result="
    for /f "usebackq delims=" %%R in (`cscript //nologo "%vbs_file%" 2^>^&1`) do set "vbs_result=%%R"
    if "!vbs_result!"=="OK" (
      echo Removed the 'Patou Bash' terminal profile from !settings_path!
    ) else if "!vbs_result!"=="SKIP" (
      rem Nothing to remove.
    ) else (
      echo note: could not update !settings_path! ^(!vbs_result!^) - remove the 'Patou Bash' entry manually if present
    )
  )
)

set "PATOU_VSCODE_MODE="
set "PATOU_VSCODE_SETTINGS="
del /f /q "%vbs_file%" >nul 2>&1

endlocal
goto :eof
