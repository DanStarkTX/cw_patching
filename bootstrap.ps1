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

$ErrorActionPreference = "Stop"
$apiBase = "https://api.github.com/repos/DanStarkTX/cw_patching/contents"
$outDir         = "C:\cwave"
$scriptOutDir   = "$outDir\scripts"
$functionsOutDir = "$outDir\scripts\functions"
$configOutDir   = "$outDir\scripts\config"
$modulesOutDir  = "$outDir\scripts\modules"

Write-Host ""
Write-Host "=== Cloudwave EUC Patching Bootstrap ===" -ForegroundColor Cyan
Write-Host "Staging payload to $outDir..." -ForegroundColor Yellow
Write-Host ""

foreach ($dir in @($outDir, $scriptOutDir, $functionsOutDir, $configOutDir, $modulesOutDir)) {
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

function Get-RepoItems {
    param ([string] $Path)
    $uri = if ($Path) { "$apiBase/$Path" } else { $apiBase }
    try {
        @(Invoke-RestMethod -Uri $uri -UseBasicParsing -ErrorAction Stop)
    } catch {
        Write-Host "Failed to query '$Path'. Error: $($_.Exception.Message)" -ForegroundColor Red
        @()
    }
}

function Get-RepoFilesRecursive {
    param ([string] $Path)
    $results = @()
    $items = @(Get-RepoItems -Path $Path)
    foreach ($item in $items) {
        if ($item.type -eq 'file' -and $item.download_url) {
            $results += $item
        } elseif ($item.type -eq 'dir' -and $item.path) {
            $results += @(Get-RepoFilesRecursive -Path $item.path)
        }
    }
    return $results
}

function Save-RepoFile {
    param ([string] $Url, [string] $OutPath)
    $parent = Split-Path -Path $OutPath -Parent
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Invoke-WebRequest -Uri $Url -OutFile $OutPath -UseBasicParsing
}

$updatedCount = 0

# Root BAT files
$rootItems = @(Get-RepoItems -Path "")
foreach ($item in ($rootItems | Where-Object { $_.type -eq 'file' -and $_.name -match '\.bat$' -and $_.download_url })) {
    $outPath = "$outDir\$($item.name)"
    Save-RepoFile -Url $item.download_url -OutPath $outPath
    Write-Host "Staged: $($item.name)" -ForegroundColor Green
    $updatedCount++
}

# Scripts (root ps1 files, not bootstrap)
foreach ($item in ($rootItems | Where-Object { $_.type -eq 'file' -and $_.name -match '\.ps1$' -and $_.name -ne 'bootstrap.ps1' -and $_.download_url })) {
    $outPath = "$outDir\$($item.name)"
    Save-RepoFile -Url $item.download_url -OutPath $outPath
    Write-Host "Staged: $($item.name)" -ForegroundColor Green
    $updatedCount++
}

# scripts/ folder PS1s
$scriptItems = @(Get-RepoItems -Path "scripts" | Where-Object { $_.type -eq 'file' -and $_.download_url })
foreach ($item in $scriptItems) {
    $outPath = "$scriptOutDir\$($item.name)"
    Save-RepoFile -Url $item.download_url -OutPath $outPath
    Write-Host "Staged: scripts/$($item.name)" -ForegroundColor Green
    $updatedCount++
}

# functions/
$functionItems = @(Get-RepoItems -Path "scripts/functions" | Where-Object { $_.type -eq 'file' -and $_.download_url })
foreach ($item in $functionItems) {
    $outPath = "$functionsOutDir\$($item.name)"
    Save-RepoFile -Url $item.download_url -OutPath $outPath
    Write-Host "Staged: scripts/functions/$($item.name)" -ForegroundColor Green
    $updatedCount++
}

# config/
$configItems = @(Get-RepoItems -Path "scripts/config" | Where-Object { $_.type -eq 'file' -and $_.download_url })
foreach ($item in $configItems) {
    $outPath = "$configOutDir\$($item.name)"
    Save-RepoFile -Url $item.download_url -OutPath $outPath
    Write-Host "Staged: scripts/config/$($item.name)" -ForegroundColor Green
    $updatedCount++
}

# modules/ recursive
$moduleFiles = @(Get-RepoFilesRecursive -Path "scripts/modules" | Where-Object { $_.type -eq 'file' -and $_.download_url })
foreach ($item in $moduleFiles) {
    $relativePath = $item.path -replace '^scripts/modules/', ''
    $outPath = "$modulesOutDir\$($relativePath -replace '/', '\')"
    Save-RepoFile -Url $item.download_url -OutPath $outPath
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
