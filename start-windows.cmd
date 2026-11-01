@echo off
setlocal
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" (
  echo Python environment missing. See windows\WIN11-NEXT-STEPS.md
  pause
  exit /b 1
)
".venv\Scripts\python.exe" windows\preflight.py
echo.
echo The GUI will open. Free Apple ID signing requires the helper EXE.
".venv\Scripts\python.exe" windows\gui.py
if errorlevel 1 pause
