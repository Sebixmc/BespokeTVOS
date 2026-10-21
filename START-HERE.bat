@echo off
title Fire TV Clean-Up Kit
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows\firetv-kit.ps1"
pause
