<#
.SYNOPSIS
Cloudwave EUC patching toolkit bootstrap.

.DESCRIPTION
Stages the full patching payload under C:\cwave\scripts\ including
scripts, helpers, config, and localized modules.
Run as Administrator from Windows PowerShell 5.1.

.NOTES
Author: Dan Stark / Cloudwave EUC
For questions, contact Dan Stark / Cloudwave EUC
#>

if ($PSVersionTable.PSEdition -ne "Desktop") {
    Write-Host "This bootstrap must be run in Windows PowerShell 5.1." -ForegroundColor Red
    Write-Host "Open Windows PowerShell (not PowerShell 7) and run:" -ForegroundColor Yellow
    Write-Host "  irm 'https://raw.githubusercontent.com/DanStarkTX/cw_patching/main/bootstrap.ps1' | iex" -ForegroundColor Yellow
    exit 1
}

[string]$ErrorActionPreference = "Stop"
[string]$apiBase        = "https://api.github.com/repos/DanStarkTX/cw_patching/contents"
[string]$outDir         = "C:\cwave"
[string]$scriptOutDir   = "C:\cwave\scripts"
[string]$functionsOutDir = "C:\cwave\scripts\functions"
[string]$configOutDir   = "C:\cwave\scripts\config"
[string]$modulesOutDir  = "C:\cwave\scripts\modules"

Write-Host ""
Write-Host "=== Cloudwave EUC Patching Bootstrap ===" -ForegroundColor Cyan
Write-Host "Staging payload to C:\cwave..." -ForegroundColor Yellow
Write-Host ""

foreach ($dir in @($outDir, $scriptOutDir, $functionsOutDir, $configOutDir, $modulesOutDir)) {
    [string]$d = $dir
    if (-not (Test-Path -LiteralPath $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
}

function Get-RepoItems {
    param ([string]$Path = "")
    [string]$uri = if ($Path) { "$apiBase/$Path" } else { $apiBase }
    try {
        @(Invoke-RestMethod -Uri $uri -UseBasicParsing -ErrorAction Stop)
    } catch {
        Write-Host "Failed to query '$Path'. Error: $($_.Exception.Message)" -ForegroundColor Red
        @()
    }
}

function Get-RepoFilesRecursive {
    param ([string]$Path)
    $results = [System.Collections.ArrayList]@()
    $items = @(Get-RepoItems -Path $Path)
    foreach ($item in $items) {
        if ($item.type -eq 'file' -and $item.download_url) {
            [void]$results.Add($item)
        } elseif ($item.type -eq 'dir' -and $item.path) {
            foreach ($child in @(Get-RepoFilesRecursive -Path $item.path)) {
                [void]$results.Add($child)
            }
        }
    }
    return $results
}

function Save-RepoFile {
    param ([string]$Url, [string]$OutPath)
    [string]$parent = [System.IO.Path]::GetDirectoryName($OutPath)
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Invoke-WebRequest -Uri $Url -OutFile $OutPath -UseBasicParsing
}

[int]$updatedCount = 0

$rootItems = @(Get-RepoItems -Path "")

foreach ($item in @($rootItems | Where-Object { $_.type -eq 'file' -and $_.name -match '\.bat$' -and $_.download_url })) {
    [string]$outPath = "C:\cwave\$($item.name)"
    Save-RepoFile -Url ([string]$item.download_url) -OutPath $outPath
    Write-Host "Staged: $($item.name)" -ForegroundColor Green
    $updatedCount++
}

foreach ($item in @($rootItems | Where-Object { $_.type -eq 'file' -and $_.name -match '\.ps1$' -and $_.name -ne 'bootstrap.ps1' -and $_.download_url })) {
    [string]$outPath = "C:\cwave\$($item.name)"
    Save-RepoFile -Url ([string]$item.download_url) -OutPath $outPath
    Write-Host "Staged: $($item.name)" -ForegroundColor Green
    $updatedCount++
}

foreach ($item in @(Get-RepoItems -Path "scripts" | Where-Object { $_.type -eq 'file' -and $_.download_url })) {
    [string]$outPath = "C:\cwave\scripts\$($item.name)"
    Save-RepoFile -Url ([string]$item.download_url) -OutPath $outPath
    Write-Host "Staged: scripts/$($item.name)" -ForegroundColor Green
    $updatedCount++
}

foreach ($item in @(Get-RepoItems -Path "scripts/functions" | Where-Object { $_.type -eq 'file' -and $_.download_url })) {
    [string]$outPath = "C:\cwave\scripts\functions\$($item.name)"
    Save-RepoFile -Url ([string]$item.download_url) -OutPath $outPath
    Write-Host "Staged: scripts/functions/$($item.name)" -ForegroundColor Green
    $updatedCount++
}

foreach ($item in @(Get-RepoItems -Path "scripts/config" | Where-Object { $_.type -eq 'file' -and $_.download_url })) {
    [string]$outPath = "C:\cwave\scripts\config\$($item.name)"
    Save-RepoFile -Url ([string]$item.download_url) -OutPath $outPath
    Write-Host "Staged: scripts/config/$($item.name)" -ForegroundColor Green
    $updatedCount++
}

foreach ($item in @(Get-RepoFilesRecursive -Path "scripts/modules" | Where-Object { $_.type -eq 'file' -and $_.download_url })) {
    [string]$itemPath = $item.path
    [string]$relativePath = $itemPath -replace '^scripts/modules/', ''
    [string]$relativePathWin = $relativePath -replace '/', '\'
    [string]$outPath = "C:\cwave\scripts\modules\$relativePathWin"
    Save-RepoFile -Url ([string]$item.download_url) -OutPath $outPath
    Write-Host "Staged: scripts/modules/$relativePath" -ForegroundColor Green
    $updatedCount++
}

Write-Host ""
Write-Host "Bootstrap complete. $updatedCount file(s) staged." -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  Run updates:  C:\cwave\run_updates.bat" -ForegroundColor White
Write-Host "  Run cleanup:  C:\cwave\run_cleanup.bat" -ForegroundColor White
Write-Host "  Health check: C:\cwave\scripts\Check-SystemHealth.ps1" -ForegroundColor White
Write-Host ""
