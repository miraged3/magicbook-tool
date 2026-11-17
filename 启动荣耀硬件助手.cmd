@echo off
set "HERE=%~dp0"
if exist "%HERE%HonorHardwareManager.exe" (
  start "" "%HERE%HonorHardwareManager.exe"
) else (
  start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%HERE%HonorHardwareManager.ps1"
)
