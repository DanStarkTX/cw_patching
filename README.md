# cw_patching

Cloudwave EUC patching tools for Windows 10/11 gold images and operator desktops.

## What's included

- `do_updates.ps1` — Windows Update workflow with service restoration, localized PSWindowsUpdate module, and verified install confirmation
- `do_cleanup.ps1` — Post-update cleanup and image sealing workflow
- `Check-SystemHealth.ps1` — Independent health check and triage tool

## Launch Commands

**Stable Branch (Recommended)**

```powershell
$client = New-Object System.Net.WebClient; $client.CachePolicy = New-Object System.Net.Cache.RequestCachePolicy([System.Net.Cache.RequestCacheLevel]::NoCacheNoStore); $client.DownloadFile("https://raw.githubusercontent.com/DanStarkTX/cw_patching/main/Get-CWPatching.ps1", "$env:TEMP\Get-CWPatching.ps1"); powershell -ExecutionPolicy Bypass -File "$env:TEMP\Get-CWPatching.ps1"
```

**Dev Branch**

```powershell
$client = New-Object System.Net.WebClient; $client.CachePolicy = New-Object System.Net.Cache.RequestCachePolicy([System.Net.Cache.RequestCacheLevel]::NoCacheNoStore); $client.DownloadFile("https://raw.githubusercontent.com/DanStarkTX/cw_patching/dev/Get-CWPatching.ps1", "$env:TEMP\Get-CWPatching.ps1"); powershell -ExecutionPolicy Bypass -File "$env:TEMP\Get-CWPatching.ps1"
```

## Requirements

- Windows PowerShell 5.1 (Desktop edition)
- Run as Administrator
- Internet access to GitHub for initial payload delivery

## Workflow

1. Run bootstrap to stage payload under `C:\cwave\scripts\`
2. Run updates: `C:\cwave\run_updates.bat`
3. Reboot if required, then rerun updates to confirm clean state
4. Run cleanup: `C:\cwave\run_cleanup.bat`
5. Run health check if needed: `C:\cwave\scripts\Check-SystemHealth.ps1`
6. Seal image

## Issues / Contact

For questions or issues, contact Dan Stark / Cloudwave EUC.
