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

:: patou-bash.exe itself, and the helper files it writes next to itself
:: on each launch (patou-shell.sh, patou-bash.minttyrc).
for %%N in (patou-bash.exe patou-shell.sh patou-bash.minttyrc patou-bash-error.log) do (
  if exist "%install_dir%\%%N" (
    del /f /q "%install_dir%\%%N"
    echo Removed %install_dir%\%%N
  )
)

endlocal
