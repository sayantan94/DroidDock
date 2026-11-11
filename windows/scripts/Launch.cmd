@echo off
setlocal
if not exist "%~dp0DroidDock.exe" (
  echo DroidDock.exe is missing. Extract the complete downloaded ZIP first.
  if /I not "%~1"=="--screenshot" pause
  exit /b 1
)
if /I "%~1"=="--screenshot" (
  start "" /wait "%~dp0DroidDock.exe" --screenshot "%~2"
  exit /b
)
start "" /D "%~dp0" "%~dp0DroidDock.exe"
exit /b 0
