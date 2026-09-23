@echo off
powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0restore-after-move.ps1" %*
