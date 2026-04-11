<#
.SYNOPSIS
Cloudwave EUC patching toolkit bootstrap.
For questions, contact Dan Stark / Cloudwave EUC
#>

if ($PSVersionTable.PSEdition -ne "Desktop") {
    Write-Host "Run this from Windows PowerShell 5.1, not PowerShell 7." -ForegroundColor Red
    exit 1
}

$apiBase = "https://api.github.com/repos/DanStarkTX/cw_patching/contents"

Write-Host ""
Write-Host "=== Cloudwave EUC Patching Bootstrap ===" -ForegroundColor Cyan
Write-Host "Staging payload to C:\cwave..." -ForegroundColor Yellow
Write-Host ""

$null = cmd /c "mkdir C:\cwave 2>nul"
$null = cmd /c "mkdir C:\cwave\scripts 2>nul"
$null = cmd /c "mkdir C:\cwave\scripts\functions 2>nul"
$null = cmd /c "mkdir C:\cwave\scripts\config 2>nul"
$null = cmd /c "mkdir C:\cwave\scripts\modules 2>nul"

function cwGet {
    param([string]$p)
    $uri = if ($p) { "$apiBase/$p" } else { $apiBase }
    try {
        @(Invoke-RestMethod -Uri $uri -UseBasicParsing -ErrorAction Stop)
    } catch {
        Write-Host "Failed to query '$p'. Error: $($_.Exception.Message)" -ForegroundColor Red
        @()
    }
}

function cwGetRecurse {
    param([string]$p)
    $r = @()
    foreach ($i in @(cwGet $p)) {
        if ($i.type -eq 'file' -and $i.download_url -and $i.name -is [string]) {
            $r += $i
        } elseif ($i.type -eq 'dir' -and $i.path -is [string]) {
            $r += @(cwGetRecurse $i.path)
        }
    }
    $r
}

function cwSave {
    param([string]$url, [string]$out)
    $null = cmd /c "mkdir `"$(Split-Path $out)`" 2>nul"
    Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing
}

$n = 0

# Root BAT files only
foreach ($f in @(cwGet "" | Where-Object { $_.type -eq 'file' -and $_.name -is [string] -and $_.name -match '\.bat$' -and $_.download_url })) {
    cwSave ([string]$f.download_url) "C:\cwave\$([string]$f.name)"
    Write-Host "Staged: $($f.name)" -ForegroundColor Green
    $n++
}

# Root PS1 files excluding bootstrap
foreach ($f in @(cwGet "" | Where-Object { $_.type -eq 'file' -and $_.name -is [string] -and $_.name -match '\.ps1$' -and $_.name -ne 'bootstrap.ps1' -and $_.download_url })) {
    cwSave ([string]$f.download_url) "C:\cwave\$([string]$f.name)"
    Write-Host "Staged: $($f.name)" -ForegroundColor Green
    $n++
}

# scripts/ PS1s
foreach ($f in @(cwGet "scripts" | Where-Object { $_.type -eq 'file' -and $_.name -is [string] -and $_.download_url })) {
    cwSave ([string]$f.download_url) "C:\cwave\scripts\$([string]$f.name)"
    Write-Host "Staged: scripts/$($f.name)" -ForegroundColor Green
    $n++
}

# functions/
foreach ($f in @(cwGet "scripts/functions" | Where-Object { $_.type -eq 'file' -and $_.name -is [string] -and $_.download_url })) {
    cwSave ([string]$f.download_url) "C:\cwave\scripts\functions\$([string]$f.name)"
    Write-Host "Staged: scripts/functions/$($f.name)" -ForegroundColor Green
    $n++
}

# config/
foreach ($f in @(cwGet "scripts/config" | Where-Object { $_.type -eq 'file' -and $_.name -is [string] -and $_.download_url })) {
    cwSave ([string]$f.download_url) "C:\cwave\scripts\config\$([string]$f.name)"
    Write-Host "Staged: scripts/config/$($f.name)" -ForegroundColor Green
    $n++
}

# modules/ recursive
foreach ($f in @(cwGetRecurse "scripts/modules")) {
    $rel = ([string]$f.path) -replace '^scripts/modules/', ''
    $relWin = $rel -replace '/', '\'
    cwSave ([string]$f.download_url) "C:\cwave\scripts\modules\$relWin"
    Write-Host "Staged: scripts/modules/$rel" -ForegroundColor Green
    $n++
}

Write-Host ""
Write-Host "Bootstrap complete. $n file(s) staged." -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  Run updates:  C:\cwave\run_updates.bat" -ForegroundColor White
Write-Host "  Run cleanup:  C:\cwave\run_cleanup.bat" -ForegroundColor White
Write-Host "  Health check: C:\cwave\scripts\Check-SystemHealth.ps1" -ForegroundColor White
Write-Host ""
