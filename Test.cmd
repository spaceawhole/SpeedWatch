@echo off
title SpeedWatch tests
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tests\test-schedule.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tests\test-panel.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tests\test-worker.ps1"
echo.
pause
