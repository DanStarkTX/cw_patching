<#
.SYNOPSIS
Cloudwave EUC toolset import.
For questions, contact Dan Stark / Cloudwave EUC
#>

if ($PSVersionTable.PSEdition -ne "Desktop") {
    Write-Host "Run this from Windows PowerShell 5.1, not PowerShell 7." -ForegroundColor Red
    exit 1
}

$api = "https://api.github.com/repos/DanStarkTX/cw_patching/contents"

$EventSource = "EUC Script Import"
$LogName = "Application"

function Write-ImportEventLog {
    param(
        [string]$Message,
        [ValidateSet('Information','Warning','Error')]
        [string]$EntryType = 'Information',
        [int]$EventId = 1030
    )
    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
            [System.Diagnostics.EventLog]::CreateEventSource($EventSource, $LogName)
        }
        $log = New-Object System.Diagnostics.EventLog($LogName)
        $log.Source = $EventSource
        $log.WriteEntry($Message, [System.Diagnostics.EventLogEntryType]::$EntryType, $EventId)
    } catch {
        try {
            $log = New-Object System.Diagnostics.EventLog($LogName)
            $log.Source = "WindowsUpdateScript"
            $log.WriteEntry("[EUC Script Import] $Message", [System.Diagnostics.EventLogEntryType]::$EntryType, $EventId)
        } catch { }
    }
}

Write-Host ""
Write-Host "=== Cloudwave EUC Toolset Import ===" -ForegroundColor Cyan
Write-Host ""

Write-ImportEventLog -Message "Cloudwave EUC Toolset Import started on $env:COMPUTERNAME." -EventId 1030

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

function Get-GitBlobSHA {
    param([string]$Path)
    try {
        $content = [System.IO.File]::ReadAllBytes($Path)
        $header = [System.Text.Encoding]::ASCII.GetBytes("blob $($content.Length)`0")
        $combined = $header + $content
        $sha1 = [System.Security.Cryptography.SHA1]::Create()
        $hashBytes = $sha1.ComputeHash($combined)
        ($hashBytes | ForEach-Object { $_.ToString("x2") }) -join ""
    } catch {
        $null
    }
}

$fileList = @()

# Root files
foreach ($f in @(cwGet "" | Where-Object { $_.name -match '\.bat$|\.ps1$' -and $_.name -ne 'Get-CWPatching.ps1' })) {
    $fileList += [PSCustomObject]@{ Url = $f.download_url; Out = "C:\cwave\$($f.name)"; SHA = $f.sha }
}

# Scripts
foreach ($f in cwGet "scripts") {
    $fileList += [PSCustomObject]@{ Url = $f.download_url; Out = "C:\cwave\scripts\$($f.name)"; SHA = $f.sha }
}

# Functions
foreach ($f in cwGet "scripts/functions") {
    $fileList += [PSCustomObject]@{ Url = $f.download_url; Out = "C:\cwave\scripts\functions\$($f.name)"; SHA = $f.sha }
}

# Config
foreach ($f in cwGet "scripts/config") {
    $fileList += [PSCustomObject]@{ Url = $f.download_url; Out = "C:\cwave\scripts\config\$($f.name)"; SHA = $f.sha }
}

# PSWindowsUpdate module
foreach ($f in cwGet "scripts/modules/PSWindowsUpdate/2.2.1.5") {
    $fileList += [PSCustomObject]@{ Url = $f.download_url; Out = "C:\cwave\scripts\modules\PSWindowsUpdate\2.2.1.5\$($f.name)"; SHA = $f.sha }
}

$total = $fileList.Count
$imported = 0
$skipped = 0

for ($i = 0; $i -lt $total; $i++) {
    $file = $fileList[$i]
    $fileName = Split-Path $file.Out -Leaf
    Write-Progress -Activity "Cloudwave EUC Toolset Import" -Status "Checking $fileName" -PercentComplete (($i / $total) * 100)

    $needsUpdate = $true

    if ($file.SHA -and (Test-Path -LiteralPath $file.Out)) {
        $localSHA = Get-GitBlobSHA -Path $file.Out
        if ($localSHA -and $localSHA -eq $file.SHA) {
            $needsUpdate = $false
        }
    }

    if ($needsUpdate) {
        Write-Progress -Activity "Cloudwave EUC Toolset Import" -Status "Importing $fileName" -PercentComplete (($i / $total) * 100)
        if (cwSave $file.Url $file.Out) {
            $imported++
            Write-ImportEventLog -Message "Imported: $fileName" -EventId 1031
        }
    } else {
        $skipped++
    }
}

Write-Progress -Activity "Cloudwave EUC Toolset Import" -Completed

Write-Host ""
if ($skipped -gt 0) {
    $summary = "Import complete: $imported file(s) downloaded, $skipped already up to date."
} else {
    $summary = "Import complete: $imported files downloaded."
}

Write-Host $summary -ForegroundColor Cyan
Write-ImportEventLog -Message $summary -EventId 1032
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  Run updates:  C:\cwave\run_updates.bat" -ForegroundColor White
Write-Host "  Run cleanup:  C:\cwave\run_cleanup.bat" -ForegroundColor White
Write-Host ""
