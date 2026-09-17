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

:: patou-bash.exe itself, its error log, and patou-shell.sh/patou-bash.minttyrc
:: left behind by older patou-bash.exe versions (now written inside the
:: bundled git\ folder below instead, so removing that covers current ones).
for %%N in (patou-bash.exe patou-shell.sh patou-bash.minttyrc patou-bash-error.log) do (
  if exist "%install_dir%\%%N" (
    del /f /q "%install_dir%\%%N"
    echo Removed %install_dir%\%%N
  )
)

:: The bundled Git for Windows copy scripts/install.cmd extracted for
:: patou-bash.exe (~60 MB - the main reason to clean this up specifically
:: rather than leaving it behind).
if exist "%install_dir%\git" (
  rmdir /s /q "%install_dir%\git"
  echo Removed %install_dir%\git
)

endlocal
