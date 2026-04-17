#Requires -Version 5.1
<#
.SYNOPSIS
    Cloudwave Horizon AIO Refresh & ISO Build Tool
.DESCRIPTION
    Refreshes automatable components of the CW Horizon AIO folder,
    updates VERSION.txt build log, builds ISO, and copies to DFS.
.NOTES
    oscdimg.exe must exist at C:\cwave\tools\oscdimg.exe
    Run as Administrator.
#>

# ============================================================
# CONFIGURATION
# ============================================================
$AIORoot    = "C:\Users\dstark\Desktop\CW_HRZN_2503_1_ESB_AIO"
$ISOOutput  = "C:\Users\dstark\Desktop\ISOs\CW_HRZN_2503_1_ESB_AIO.iso"
$DFSPath    = "\\ohos-dc01\OpSusDFS\OpSusData\EUC\ISOs\CW_HRZN_2503_1_ESB_AIO.iso"
$OscdimgExe = "C:\cwave\tools\oscdimg.exe"
$VersionTxt = "$AIORoot\VERSION.txt"

# Browser paths
$BrowserDir   = "$AIORoot\Installs\Browsers"
$BrowserDir64 = "$AIORoot\Installs\Browsers\64bit_versions"

# Script paths
$CwaveScriptDir = "$AIORoot\cwave\scripts"
$CwaveBatDir    = "$AIORoot\cwave"

# cw_patching repo raw URLs
$RepoBase = "https://raw.githubusercontent.com/DanStarkTX/cw_patching/main"

$Scripts = @(
    @{ Url = "$RepoBase/scripts/do_updates.ps1"; Out = "$CwaveScriptDir\do_updates.ps1";  Label = "do_updates.ps1" }
    @{ Url = "$RepoBase/scripts/do_cleanup.ps1"; Out = "$CwaveScriptDir\do_cleanup.ps1";  Label = "do_cleanup.ps1" }
    @{ Url = "$RepoBase/run_updates.bat";         Out = "$CwaveBatDir\run_updates.bat";    Label = "run_updates.bat" }
    @{ Url = "$RepoBase/run_cleanup.bat";         Out = "$CwaveBatDir\run_cleanup.bat";    Label = "run_cleanup.bat" }
)

# ============================================================
# HELPERS
# ============================================================
function Write-Banner {
    Write-Host ""
    Write-Host ("=" * 63) -ForegroundColor Cyan
    Write-Host "  Cloudwave Horizon AIO Refresh & ISO Build Tool" -ForegroundColor Yellow
    Write-Host ("=" * 63) -ForegroundColor Cyan
    Write-Host ""
}

function Write-Section ($title) {
    Write-Host ""
    Write-Host "=== $title ===" -ForegroundColor White
    Write-Host ""
}

function Get-FileViaWeb ($url, $out, $label) {
    try {
        Write-Host "  Downloading $label..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing -ErrorAction Stop
        Write-Host "  Done." -ForegroundColor Green
        return $true
    } catch {
        Write-Host "  FAILED: $label - $_" -ForegroundColor Red
        return $false
    }
}

function Get-EdgeUrl {
    try {
        $catalog = Invoke-RestMethod -Uri "https://edgeupdates.microsoft.com/api/products?view=enterprise" -UseBasicParsing
        $url = (($catalog | Where-Object { $_.Product -eq "Stable" } | Select-Object -First 1).Releases |
            Where-Object { $_.Platform -eq "Windows" -and $_.Architecture -eq $args[0] } |
            Select-Object -ExpandProperty Artifacts |
            Where-Object { $_.ArtifactName -eq "msi" } |
            Select-Object -ExpandProperty Location |
            Select-Object -First 1)
        return $url
    } catch {
        return $null
    }
}

# ============================================================
# REFRESH FUNCTIONS
# ============================================================
function Update-Browsers {
    Write-Section "Refreshing Browsers"
    $changes = @()

    # 32-bit
    if (Get-FileViaWeb "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise.msi" "$BrowserDir\ChromeEnterprise32.msi" "Chrome Enterprise 32-bit") {
        $changes += "Chrome Enterprise 32-bit updated"
    }

    $edgeUrl32 = Get-EdgeUrl "X86"
    if ($edgeUrl32 -and (Get-FileViaWeb $edgeUrl32 "$BrowserDir\EdgeEnterprise32.msi" "Edge Enterprise 32-bit")) {
        $changes += "Edge Enterprise 32-bit updated"
    }

    if (Get-FileViaWeb "https://download.mozilla.org/?product=firefox-esr-msi-latest-ssl&os=win&lang=en-US" "$BrowserDir\FirefoxESR32.msi" "Firefox ESR 32-bit") {
        $changes += "Firefox ESR 32-bit updated"
    }

    # 64-bit
    if (-not (Test-Path $BrowserDir64)) { New-Item -ItemType Directory -Path $BrowserDir64 -Force | Out-Null }

    if (Get-FileViaWeb "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi" "$BrowserDir64\ChromeEnterprise64.msi" "Chrome Enterprise 64-bit") {
        $changes += "Chrome Enterprise 64-bit updated"
    }

    $edgeUrl64 = Get-EdgeUrl "X64"
    if ($edgeUrl64 -and (Get-FileViaWeb $edgeUrl64 "$BrowserDir64\EdgeEnterprise64.msi" "Edge Enterprise 64-bit")) {
        $changes += "Edge Enterprise 64-bit updated"
    }

    if (Get-FileViaWeb "https://download.mozilla.org/?product=firefox-esr-msi-latest-ssl&os=win64&lang=en-US" "$BrowserDir64\FirefoxESR64.msi" "Firefox ESR 64-bit") {
        $changes += "Firefox ESR 64-bit updated"
    }

    return $changes
}

function Update-Scripts {
    Write-Section "Refreshing Scripts"
    $changes = @()

    foreach ($s in $Scripts) {
        if (Get-FileViaWeb $s.Url $s.Out $s.Label) {
            $changes += "$($s.Label) synced from repo"
        }
    }

    return $changes
}

# ============================================================
# VERSION.TXT
# ============================================================
function Update-VersionFile ($changes) {
    $date    = Get-Date -Format "MM/dd/yy"
    $builder = New-Object System.Text.StringBuilder

    [void]$builder.AppendLine("Cloudwave Horizon AIO - Build Log")
    [void]$builder.AppendLine("==================================")
    [void]$builder.AppendLine("")
    [void]$builder.AppendLine("Build: $date")
    [void]$builder.AppendLine("Updated By: Dan Stark")
    [void]$builder.AppendLine("Changes:")
    foreach ($c in $changes) {
        [void]$builder.AppendLine("  - $c")
    }
    [void]$builder.AppendLine("")
    [void]$builder.AppendLine("----------------------------------")
    [void]$builder.AppendLine("")

    # Prepend to existing content
    $existing = ""
    if (Test-Path $VersionTxt) {
        $existing = Get-Content $VersionTxt -Raw
        # Strip the header if it already exists so we don't duplicate it
        $existing = $existing -replace "^Cloudwave Horizon AIO - Build Log\r?\n==================================\r?\n\r?\n", ""
    }

    $newContent = $builder.ToString() + $existing
    Set-Content -Path $VersionTxt -Value $newContent -Encoding UTF8
    Write-Host "  VERSION.txt updated." -ForegroundColor Green
}

# ============================================================
# ISO BUILD
# ============================================================
function Build-ISO {
    Write-Section "Building ISO"

    if (-not (Test-Path $OscdimgExe)) {
        Write-Host "  ERROR: oscdimg.exe not found at $OscdimgExe" -ForegroundColor Red
        return $false
    }

    $isoDir = Split-Path $ISOOutput -Parent
    if (-not (Test-Path $isoDir)) { New-Item -ItemType Directory -Path $isoDir -Force | Out-Null }

    Write-Host "  Building: $ISOOutput" -ForegroundColor Cyan
    Write-Host "  Source:   $AIORoot" -ForegroundColor Cyan
    Write-Host ""

    $args = @("-lCW_HRZN_AIO", "-m", "-o", "-u2", "-udfver102", $AIORoot, $ISOOutput)
    $result = & $OscdimgExe @args

    if ($LASTEXITCODE -eq 0) {
        $sizeMB = [math]::Round((Get-Item $ISOOutput).Length / 1MB, 1)
        Write-Host "  ISO built successfully. Size: $sizeMB MB" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  ERROR: oscdimg exited with code $LASTEXITCODE" -ForegroundColor Red
        return $false
    }
}

# ============================================================
# DFS COPY
# ============================================================
function Copy-ToDFS {
    Write-Section "Copying to DFS"
    Write-Host "  Destination: $DFSPath" -ForegroundColor Cyan

    try {
        $dfsDir = Split-Path $DFSPath -Parent
        if (-not (Test-Path $dfsDir)) {
            Write-Host "  ERROR: DFS path not reachable: $dfsDir" -ForegroundColor Red
            return $false
        }
        Copy-Item -Path $ISOOutput -Destination $DFSPath -Force
        Write-Host "  Copy complete. DFS will replicate to Texas automatically." -ForegroundColor Green
        return $true
    } catch {
        Write-Host "  ERROR copying to DFS: $_" -ForegroundColor Red
        return $false
    }
}

# ============================================================
# MANUAL COMPONENTS CHECK
# ============================================================
function Show-ManualComponents {
    Write-Section "Manual Components Check"
    Write-Host "  The following require manual updates from vendor portals:" -ForegroundColor Yellow
    Write-Host ""

    # Horizon Agents
    $agents = Get-ChildItem -Path "$AIORoot\Agents" -Filter "*.exe" -ErrorAction SilentlyContinue
    foreach ($f in $agents) { Write-Host "  [Omnissa] Agents\$($f.Name)" -ForegroundColor White }

    # Connection Server
    $cs = Get-ChildItem -Path "$AIORoot\Connection Server" -Filter "*.exe" -ErrorAction SilentlyContinue
    foreach ($f in $cs) { Write-Host "  [Omnissa] Connection Server\$($f.Name)" -ForegroundColor White }

    # Enrollment Server
    $es = Get-ChildItem -Path "$AIORoot\Enrollment Server" -Filter "*.exe" -ErrorAction SilentlyContinue
    foreach ($f in $es) { Write-Host "  [Omnissa] Enrollment Server\$($f.Name)" -ForegroundColor White }

    # UAG
    $uag = Get-ChildItem -Path "$AIORoot\Unified Access Gateway" -Filter "*.ova" -ErrorAction SilentlyContinue
    foreach ($f in $uag) { Write-Host "  [Omnissa] Unified Access Gateway\$($f.Name)" -ForegroundColor White }

    # SentinelOne
    $s1 = Get-ChildItem -Path "$AIORoot\Installs\SentinelOne" -Filter "*.msi" -ErrorAction SilentlyContinue
    foreach ($f in $s1) { Write-Host "  [SentinelOne] Installs\SentinelOne\$($f.Name)" -ForegroundColor White }

    Write-Host ""
    Write-Host "  NOTE: Only approved ESB releases are permitted." -ForegroundColor Yellow
    Write-Host "        Current approved Horizon version: 2503.1" -ForegroundColor Yellow
    Write-Host ""
}

# ============================================================
# MAIN MENU
# ============================================================
Write-Banner

# Admin check
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "  ERROR: This script must be run as Administrator." -ForegroundColor Red
    Write-Host ""
    exit 1
}

$allChanges = @()
$browsersDone = $false
$scriptsDone  = $false

:menu while ($true) {
    Write-Host "  Select what to do:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [1] Refresh Browsers" -ForegroundColor White
    Write-Host "  [2] Refresh Scripts" -ForegroundColor White
    Write-Host "  [3] Refresh Browsers + Scripts" -ForegroundColor White
    Write-Host "  [4] Build ISO only (no refresh)" -ForegroundColor White
    Write-Host "  [5] Full refresh + Build ISO" -ForegroundColor White
    Write-Host "  [Q] Quit" -ForegroundColor White
    Write-Host ""

    $choice = Read-Host "  Selection"

    switch ($choice.ToUpper()) {
        "1" {
            $allChanges += Update-Browsers
            $browsersDone = $true
            break menu
        }
        "2" {
            $allChanges += Update-Scripts
            $scriptsDone = $true
            break menu
        }
        "3" {
            $allChanges += Update-Browsers
            $allChanges += Update-Scripts
            $browsersDone = $true
            $scriptsDone  = $true
            break menu
        }
        "4" {
            # No refresh, go straight to ISO
            break menu
        }
        "5" {
            $allChanges += Update-Browsers
            $allChanges += Update-Scripts
            $browsersDone = $true
            $scriptsDone  = $true
            break menu
        }
        "Q" {
            Write-Host ""
            Write-Host "  Exiting." -ForegroundColor Yellow
            exit 0
        }
        default {
            Write-Host "  Invalid selection. Please try again." -ForegroundColor Red
            Write-Host ""
        }
    }
}

# Ask about ISO build if not already triggered by option 4/5
$buildISO = $false
if ($choice -in @("1","2","3")) {
    Write-Host ""
    $buildResp = Read-Host "  Build ISO now? [Y/N]"
    $buildISO = ($buildResp.ToUpper() -eq "Y")
} elseif ($choice -in @("4","5")) {
    $buildISO = $true
}

if ($buildISO) {
    # Show manual components and confirm before building
    Show-ManualComponents

    $confirm = Read-Host "  Are all manual components current? Proceed with ISO build? [Y/N]"
    if ($confirm.ToUpper() -ne "Y") {
        Write-Host ""
        Write-Host "  ISO build cancelled. Update manual components and re-run." -ForegroundColor Yellow
        Write-Host ""
        exit 0
    }

    # Add a note for manual components if no automated changes were made
    if ($allChanges.Count -eq 0) {
        $manualNote = Read-Host "  Enter a brief note for VERSION.txt (or press Enter to skip)"
        if ($manualNote) { $allChanges += $manualNote }
    }

    if ($allChanges.Count -gt 0) {
        Update-VersionFile $allChanges
    }

    $isoOK = Build-ISO

    if ($isoOK) {
        Write-Host ""
        $copyResp = Read-Host "  Copy ISO to DFS? [Y/N]"
        if ($copyResp.ToUpper() -eq "Y") {
            Copy-ToDFS
        }
    }
}

Write-Host ""
Write-Host ("=" * 63) -ForegroundColor Cyan
Write-Host "  Done." -ForegroundColor Green
Write-Host ("=" * 63) -ForegroundColor Cyan
Write-Host ""
