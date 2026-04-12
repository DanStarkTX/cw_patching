# cw_patching

Cloudwave EUC patching tools for Windows 10/11 gold images and operator desktops.

## What's included

- `do_updates.ps1` — Windows Update workflow with service restoration, localized PSWindowsUpdate module, and verified install confirmation
- `do_cleanup.ps1` — Post-update cleanup and image sealing workflow
- `Check-SystemHealth.ps1` — Independent health check and triage tool

## How to use

Open **Windows PowerShell as Administrator** and run:

```powershell
irm "https://raw.githubusercontent.com/DanStarkTX/cw_patching/main/Get-CWPatching.ps1" | iex
```

This imports the full toolset to `C:\cwave\` automatically.

## Requirements

- Windows PowerShell 5.1 (Desktop edition)
- Run as Administrator
- Internet access to GitHub

## Workflow

1. Run the import command above
2. Run updates: `C:\cwave\run_updates.bat`
3. Reboot if required, then rerun updates to confirm clean state
4. Run cleanup: `C:\cwave\run_cleanup.bat`
5. Run health check if needed: `C:\cwave\scripts\Check-SystemHealth.ps1`
6. Seal image

## Issues / Contact

For questions or issues, contact Dan Stark / Cloudwave EUC.
