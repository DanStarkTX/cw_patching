@echo off
set "PS_EXE=C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"

net session >nul 2>&1
if %errorlevel% neq 0 (
    "%PS_EXE%" -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

"%PS_EXE%" -NoLogo -ExecutionPolicy Bypass -NoExit -File "C:\cwave\scripts\do_updates.ps1"
