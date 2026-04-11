<#
.SYNOPSIS
Cloudwave EUC patching toolkit bootstrap.

.DESCRIPTION
Stages the full patching payload under C:\cwave\scripts\ including
scripts, helpers, config, and localized modules.
Run as Administrator from Windows PowerShell 5.1.

.NOTES
Author: Dan Stark / Cloudwave EUC
#>

if ($PSVersionTable.PSEdition -ne "Desktop") {
    Write-Host "This bootstrap must be run in Windows PowerShell 5.1." -ForegroundColor Red
    Write-Host "Open Windows PowerShell (not PowerShell 7) and run:" -ForegroundColor Yellow
    Write-Host "  irm 'https://raw.githubusercontent.com/DanStarkTX/cw_patching/main/bootstrap.ps1' | iex" -ForegroundColor Yellow
    exit 1
}

$ErrorActionPreference = "Stop"
$repoBase = "https://raw.githubusercontent.com/DanStarkTX/cw_patching/main"
$apiBase = "https://api.github.com/repos/DanStarkTX/cw_patching/contents"
$outDir = "C:\cwave"
$scriptOutDir = Join-Path $outDir "scripts"
$functionsOutDir = Join-Path $scriptOutDir "functions"
$configOutDir = Join-Path $scriptOutDir "config"
$modulesOutDir = Join-Path $scriptOutDir "modules"

Write-Host ""
Write-Host "=== Cloudwave EUC Patching Bootstrap ===" -ForegroundColor Cyan
Write-Host "Staging payload to $outDir..." -ForegroundColor Yellow
Write-Host ""

foreach ($dir in @($outDir, $scriptOutDir, $functionsOutDir, $configOutDir, $modulesOutDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

function Get-RepoFiles {
    param ([string] $Path)
    try {
        @(Invoke-RestMethod -Uri "$apiBase/$Path" -ErrorAction Stop)
    } catch {
        Write-Host "Failed to query $Path. Error: $($_.Exception.Message)" -ForegroundColor Red
        @()
    }
}

function Get-RepoFilesRecursive {
    param ([string] $Path)
    $results = @()
    $items = @(Get-RepoFiles -Path $Path)
    foreach ($item in $items) {
        if ($item.type -eq 'file' -and $item.download_url) {
            $results += $item
        } elseif ($item.type -eq 'dir' -and $item.path) {
            $results += @(Get-RepoFilesRecursive -Path $item.path)
        }
    }
    return $results
}

$updatedCount = 0

$rootFiles = @(Get-RepoFiles -Path "" | Where-Object { $_.type -eq 'file' -and $_.name -match '\.bat$|\.ps1$' -and $_.name -ne 'bootstrap.ps1' })
foreach ($file in $rootFiles) {
    $outPath = Join-Path $outDir $file.name
    Invoke-WebRequest -Uri $file.download_url -OutFile $outPath -UseBasicParsing
    Write-Host "Staged: $($file.name)" -ForegroundColor Green
    $updatedCount++
}

$scriptFiles = @(Get-RepoFiles -Path "scripts" | Where-Object { $_.type -eq 'file' -and $_.download_url })
foreach ($file in $scriptFiles) {
    $outPath = Join-Path $scriptOutDir $file.name
    Invoke-WebRequest -Uri $file.download_url -OutFile $outPath -UseBasicParsing
    Write-Host "Staged: scripts/$($file.name)" -ForegroundColor Green
    $updatedCount++
}

$functionFiles = @(Get-RepoFiles -Path "scripts/functions" | Where-Object { $_.type -eq 'file' -and $_.download_url })
foreach ($file in $functionFiles) {
    $outPath = Join-Path $functionsOutDir $file.name
    Invoke-WebRequest -Uri $file.download_url -OutFile $outPath -UseBasicParsing
    Write-Host "Staged: scripts/functions/$($file.name)" -ForegroundColor Green
    $updatedCount++
}

$configFiles = @(Get-RepoFiles -Path "scripts/config" | Where-Object { $_.type -eq 'file' -and $_.download_url })
foreach ($file in $configFiles) {
    $outPath = Join-Path $configOutDir $file.name
    Invoke-WebRequest -Uri $file.download_url -OutFile $outPath -UseBasicParsing
    Write-Host "Staged: scripts/config/$($file.name)" -ForegroundColor Green
    $updatedCount++
}

$moduleFiles = @(Get-RepoFilesRecursive -Path "scripts/modules" | Where-Object { $_.type -eq 'file' -and $_.download_url })
foreach ($file in $moduleFiles) {
    $relativePath = $file.path -replace '^scripts/modules/', ''
    $outPath = Join-Path $modulesOutDir $relativePath
    $outParent = Split-Path -Path $outPath -Parent
    if (-not (Test-Path $outParent)) {
        New-Item -ItemType Directory -Path $outParent -Force | Out-Null
    }
    Invoke-WebRequest -Uri $file.download_url -OutFile $outPath -UseBasicParsing
    Write-Host "Staged: scripts/modules/$relativePath" -ForegroundColor Green
    $updatedCount++
}

Write-Host ""
Write-Host "Bootstrap complete. $updatedCount file(s) staged to $outDir." -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  Run updates:  C:\cwave\run_updates.bat" -ForegroundColor White
Write-Host "  Run cleanup:  C:\cwave\run_cleanup.bat" -ForegroundColor White
Write-Host "  Health check: C:\cwave\scripts\Check-SystemHealth.ps1" -ForegroundColor White
Write-Host ""
