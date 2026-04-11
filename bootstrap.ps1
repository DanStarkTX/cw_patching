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
    if ($p) {
        @(Invoke-RestMethod -Uri "$apiBase/$p" -UseBasicParsing)
    } else {
        @(Invoke-RestMethod -Uri $apiBase -UseBasicParsing)
    }
}

function cwGetRecurse {
    param([string]$p)
    $r = @()
    foreach ($i in @(cwGet $p)) {
        if ($i.type -eq 'file' -and $i.download_url) { $r += $i }
        elseif ($i.type -eq 'dir') { $r += @(cwGetRecurse $i.path) }
    }
    $r
}

function cwSave {
    param([string]$url, [string]$out)
    $par = [System.IO.Path]::GetDirectoryName($out)
    $null = cmd /c "mkdir `"$par`" 2>nul"
    Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing
}

$n = 0

foreach ($f in @(cwGet "" | Where-Object { $_.type -eq 'file' -and $_.name -match '\.bat$' -and $_.download_url })) {
    cwSave $f.download_url "C:\cwave\$($f.name)"
    Write-Host "Staged: $($f.name)" -ForegroundColor Green
    $n++
}

foreach ($f in @(cwGet "" | Where-Object { $_.type -eq 'file' -and $_.name -match '\.ps1$' -and $_.name -ne 'bootstrap.ps1' -and $_.download_url })) {
    cwSave $f.download_url "C:\cwave\$($f.name)"
    Write-Host "Staged: $($f.name)" -ForegroundColor Green
    $n++
}

foreach ($f in @(cwGet "scripts" | Where-Object { $_.type -eq 'file' -and $_.download_url })) {
    cwSave $f.download_url "C:\cwave\scripts\$($f.name)"
    Write-Host "Staged: scripts/$($f.name)" -ForegroundColor Green
    $n++
}

foreach ($f in @(cwGet "scripts/functions" | Where-Object { $_.type -eq 'file' -and $_.download_url })) {
    cwSave $f.download_url "C:\cwave\scripts\functions\$($f.name)"
    Write-Host "Staged: scripts/functions/$($f.name)" -ForegroundColor Green
    $n++
}

foreach ($f in @(cwGet "scripts/config" | Where-Object { $_.type -eq 'file' -and $_.download_url })) {
    cwSave $f.download_url "C:\cwave\scripts\config\$($f.name)"
    Write-Host "Staged: scripts/config/$($f.name)" -ForegroundColor Green
    $n++
}

foreach ($f in @(cwGetRecurse "scripts/modules" | Where-Object { $_.type -eq 'file' -and $_.download_url })) {
    $rel = ($f.path -replace '^scripts/modules/','') -replace '/',  '\'
    cwSave $f.download_url "C:\cwave\scripts\modules\$rel"
    Write-Host "Staged: scripts/modules/$($f.path -replace '^scripts/modules/','')" -ForegroundColor Green
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
