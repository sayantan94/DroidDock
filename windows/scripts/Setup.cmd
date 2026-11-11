@echo off
setlocal
title DroidDock Setup
set "DROIDDOCK_SOURCE=%~dp0"
set "DROIDDOCK_INSTALL=%LOCALAPPDATA%\DroidDock"
set "DROIDDOCK_SETUP_TEST="
if /I "%~1"=="--smoke-test" (
  if "%~2"=="" exit /b 2
  set "DROIDDOCK_INSTALL=%~f2"
  set "DROIDDOCK_SETUP_TEST=1"
)

echo Installing DroidDock for your Windows account...
echo.
if not exist "%DROIDDOCK_SOURCE%DroidDock.exe" (
  echo The app is missing. Extract the complete downloaded ZIP, then run Setup.cmd.
  goto failed
)
if not exist "%DROIDDOCK_SOURCE%Launch.cmd" goto failed
if /I "%DROIDDOCK_SOURCE%"=="%DROIDDOCK_INSTALL%\" goto shortcuts

powershell.exe -NoProfile -Command "if (Get-Process -Name DroidDock -ErrorAction SilentlyContinue) { Write-Host 'DroidDock is running. Finish any transfers, close it, then run Setup again.'; exit 1 }"
if errorlevel 1 goto failed
if not exist "%DROIDDOCK_INSTALL%" mkdir "%DROIDDOCK_INSTALL%"
if errorlevel 1 goto failed
for %%F in (DroidDock.exe Launch.cmd Setup.cmd LICENSE THIRD_PARTY_NOTICES.md) do (
  copy /Y "%DROIDDOCK_SOURCE%%%F" "%DROIDDOCK_INSTALL%\%%F" >nul
  if errorlevel 1 goto failed
)
if exist "%DROIDDOCK_SOURCE%licenses" (
  robocopy "%DROIDDOCK_SOURCE%licenses" "%DROIDDOCK_INSTALL%\licenses" /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP >nul
  if errorlevel 8 goto failed
)

:shortcuts
powershell.exe -NoProfile -Command "try { $appPath = Join-Path $env:DROIDDOCK_INSTALL 'DroidDock.exe'; if ($env:DROIDDOCK_SETUP_TEST -eq '1') { $desktopPath = Join-Path $env:DROIDDOCK_INSTALL 'test-shortcuts\Desktop'; $menuPath = Join-Path $env:DROIDDOCK_INSTALL 'test-shortcuts\Start Menu' } else { $desktopPath = [Environment]::GetFolderPath('DesktopDirectory'); $menuPath = [Environment]::GetFolderPath('Programs') }; $shell = New-Object -ComObject WScript.Shell; foreach ($directory in @($desktopPath, $menuPath)) { [IO.Directory]::CreateDirectory($directory) | Out-Null; $shortcut = $shell.CreateShortcut((Join-Path $directory 'DroidDock.lnk')); $shortcut.TargetPath = $appPath; $shortcut.WorkingDirectory = $env:DROIDDOCK_INSTALL; $shortcut.Description = 'Android USB file transfer'; $shortcut.Save() } } catch { Write-Error $_; exit 1 }"
if errorlevel 1 goto failed
if defined DROIDDOCK_SETUP_TEST goto smoke
echo Installed. Opening DroidDock...
call "%DROIDDOCK_INSTALL%\Launch.cmd"
exit /b %errorlevel%

:smoke
call "%DROIDDOCK_INSTALL%\Launch.cmd" --screenshot "%DROIDDOCK_INSTALL%\setup-smoke.png"
if errorlevel 1 goto failed
if not exist "%DROIDDOCK_INSTALL%\setup-smoke.png" goto failed
if not exist "%DROIDDOCK_INSTALL%\test-shortcuts\Desktop\DroidDock.lnk" goto failed
if not exist "%DROIDDOCK_INSTALL%\test-shortcuts\Start Menu\DroidDock.lnk" goto failed
echo PASS: installation, Desktop and Start menu shortcuts, launcher, and app startup.
exit /b 0

:failed
echo.
echo Setup could not finish. Your phone files have not been changed.
echo Check the message above, then run Setup.cmd again.
if not defined DROIDDOCK_SETUP_TEST pause
exit /b 1
