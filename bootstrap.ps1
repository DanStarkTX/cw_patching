<#
.SYNOPSIS
Cloudwave EUC patching toolkit bootstrap.
For questions, contact Dan Stark / Cloudwave EUC
#>

if ($PSVersionTable.PSEdition -ne "Desktop") {
    Write-Host "Run this from Windows PowerShell 5.1, not PowerShell 7." -ForegroundColor Red
    exit 1
}

$raw = "https://raw.githubusercontent.com/DanStarkTX/cw_patching/main"
$api = "https://api.github.com/repos/DanStarkTX/cw_patching/contents"

Write-Host ""
Write-Host "=== Cloudwave EUC Patching Bootstrap ===" -ForegroundColor Cyan
Write-Host "Staging payload to C:\cwave..." -ForegroundColor Yellow
Write-Host ""

$null = cmd /c "mkdir C:\cwave 2>nul"
$null = cmd /c "mkdir C:\cwave\scripts 2>nul"
$null = cmd /c "mkdir C:\cwave\scripts\functions 2>nul"
$null = cmd /c "mkdir C:\cwave\scripts\config 2>nul"
$null = cmd /c "mkdir C:\cwave\scripts\modules 2>nul"
$null = cmd /c "mkdir C:\cwave\scripts\modules\PSWindowsUpdate 2>nul"
$null = cmd /c "mkdir C:\cwave\scripts\modules\PSWindowsUpdate\2.2.1.5 2>nul"

$n = 0

function cwGet {
    param([string]$p)
    try {
        @(Invoke-RestMethod -Uri "$api/$p" -UseBasicParsing -ErrorAction Stop |
            Where-Object { $_.type -eq 'file' -and ($_.name -is [string]) -and $_.download_url })
    } catch {
        Write-Host "Failed to query '$p'. Error: $($_.Exception.Message)" -ForegroundColor Red
        @()
    }
}

function cwSave {
    param([string]$url, [string]$out)
    try {
        Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing
        $true
    } catch {
        Write-Host "Failed to download $url. Error: $($_.Exception.Message)" -ForegroundColor Red
        $false
    }
}

# Root BAT launchers - known filenames
foreach ($name in @("run_updates.bat", "run_cleanup.bat")) {
    if (cwSave "$raw/$name" "C:\cwave\$name") {
        Write-Host "Staged: $name" -ForegroundColor Green
        $n++
    }
}

# Scripts - known filenames
foreach ($name in @("do_updates.ps1", "do_cleanup.ps1", "Check-SystemHealth.ps1", "Invoke-DoUpdates.ps1", "Invoke-DoCleanup.ps1")) {
    if (cwSave "$raw/scripts/$name" "C:\cwave\scripts\$name") {
        Write-Host "Staged: scripts/$name" -ForegroundColor Green
        $n++
    }
}

# Helpers
foreach ($f in @(cwGet "scripts/functions")) {
    if (cwSave ([string]$f.download_url) "C:\cwave\scripts\functions\$([string]$f.name)") {
        Write-Host "Staged: scripts/functions/$($f.name)" -ForegroundColor Green
        $n++
    }
}

# Config
foreach ($f in @(cwGet "scripts/config")) {
    if (cwSave ([string]$f.download_url) "C:\cwave\scripts\config\$([string]$f.name)") {
        Write-Host "Staged: scripts/config/$($f.name)" -ForegroundColor Green
        $n++
    }
}

# PSWindowsUpdate module
foreach ($f in @(cwGet "scripts/modules/PSWindowsUpdate/2.2.1.5")) {
    if (cwSave ([string]$f.download_url) "C:\cwave\scripts\modules\PSWindowsUpdate\2.2.1.5\$([string]$f.name)") {
        Write-Host "Staged: scripts/modules/PSWindowsUpdate/2.2.1.5/$($f.name)" -ForegroundColor Green
        $n++
    }
}

Write-Host ""
Write-Host "Bootstrap complete. $n file(s) staged." -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  Run updates:  C:\cwave\run_updates.bat" -ForegroundColor White
Write-Host "  Run cleanup:  C:\cwave\run_cleanup.bat" -ForegroundColor White
Write-Host "  Health check: C:\cwave\scripts\Check-SystemHealth.ps1" -ForegroundColor White
Write-Host ""
