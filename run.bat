@echo off
chcp 65001 >nul
cd /d "%~dp0"
call flutter run -d windows
pause
