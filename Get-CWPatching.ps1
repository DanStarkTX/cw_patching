<#
.SYNOPSIS
Cloudwave EUC toolset import.
For questions, contact Dan Stark / Cloudwave EUC
#>

if ($PSVersionTable.PSEdition -ne "Desktop") {
    Write-Host "Run this from Windows PowerShell 5.1, not PowerShell 7." -ForegroundColor Red
    exit 1
}

$raw = "https://raw.githubusercontent.com/DanStarkTX/cw_patching/main"
$api = "https://api.github.com/repos/DanStarkTX/cw_patching/contents"

Write-Host ""
Write-Host "=== Cloudwave EUC Toolset Import ===" -ForegroundColor Cyan
Write-Host ""

$null = cmd /c "mkdir C:\cwave 2>nul"
$null = cmd /c "mkdir C:\cwave\scripts 2>nul"
$null = cmd /c "mkdir C:\cwave\scripts\functions 2>nul"
$null = cmd /c "mkdir C:\cwave\scripts\config 2>nul"
$null = cmd /c "mkdir C:\cwave\scripts\modules 2>nul"
$null = cmd /c "mkdir C:\cwave\scripts\modules\PSWindowsUpdate 2>nul"
$null = cmd /c "mkdir C:\cwave\scripts\modules\PSWindowsUpdate\2.2.1.5 2>nul"

function cwGet {
    param([string]$p)
    try {
        $result = Invoke-RestMethod -Uri "$api/$p" -ErrorAction Stop
        $items = @()
        foreach ($item in $result) {
            if ($item.type -eq 'file' -and $item.download_url -and $item.name) {
                $items += $item
            }
        }
        $items
    } catch {
        @()
    }
}

function cwSave {
    param([string]$url, [string]$out)
    try {
        Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing -ErrorAction Stop
        $true
    } catch {
        $false
    }
}

$fileList = @()

foreach ($name in @("run_updates.bat", "run_cleanup.bat")) {
    $fileList += [PSCustomObject]@{ Url = "$raw/$name"; Out = "C:\cwave\$name" }
}

foreach ($name in @("do_updates.ps1", "do_cleanup.ps1", "Check-SystemHealth.ps1", "Invoke-DoUpdates.ps1", "Invoke-DoCleanup.ps1")) {
    $fileList += [PSCustomObject]@{ Url = "$raw/scripts/$name"; Out = "C:\cwave\scripts\$name" }
}

foreach ($f in cwGet "scripts/functions") {
    $fileList += [PSCustomObject]@{ Url = $f.download_url; Out = "C:\cwave\scripts\functions\$($f.name)" }
}

foreach ($f in cwGet "scripts/config") {
    $fileList += [PSCustomObject]@{ Url = $f.download_url; Out = "C:\cwave\scripts\config\$($f.name)" }
}

foreach ($f in cwGet "scripts/modules/PSWindowsUpdate/2.2.1.5") {
    $fileList += [PSCustomObject]@{ Url = $f.download_url; Out = "C:\cwave\scripts\modules\PSWindowsUpdate\2.2.1.5\$($f.name)" }
}

$total = $fileList.Count
$imported = 0

for ($i = 0; $i -lt $total; $i++) {
    $file = $fileList[$i]
    $fileName = Split-Path $file.Out -Leaf
    Write-Progress -Activity "Cloudwave EUC Toolset Import" -Status "Importing $fileName" -PercentComplete (($i / $total) * 100)
    if (cwSave $file.Url $file.Out) {
        $imported++
    }
}

Write-Progress -Activity "Cloudwave EUC Toolset Import" -Completed

Write-Host ""
Write-Host "Import complete. $imported file(s) imported." -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  Run updates:  C:\cwave\run_updates.bat" -ForegroundColor White
Write-Host "  Run cleanup:  C:\cwave\run_cleanup.bat" -ForegroundColor White
Write-Host ""
