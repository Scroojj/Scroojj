@echo off
powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0backup-for-move.ps1" %*
