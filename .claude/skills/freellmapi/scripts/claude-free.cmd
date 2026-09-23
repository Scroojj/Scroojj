@echo off
rem Double-click to start Claude Code on free models via FreeLLMAPI.
powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0claude-free.ps1" %*
