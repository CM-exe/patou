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

endlocal
