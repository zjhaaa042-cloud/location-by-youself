@echo off
setlocal
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" (
  python -m venv .venv
  if errorlevel 1 goto failed
)
".venv\Scripts\python.exe" -m pip install -r windows\requirements.txt
if errorlevel 1 goto failed
".venv\Scripts\python.exe" windows\preflight.py
pause
exit /b 0
:failed
echo Setup failed. Check Python and network, then run this file again.
pause
exit /b 1
