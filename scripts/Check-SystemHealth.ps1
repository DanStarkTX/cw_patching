<#
.SYNOPSIS
Performs a system health check on a Windows base image or operator desktop.

.DESCRIPTION
Checks for pending reboots, DISM image health, free disk space, service state,
Event Viewer errors, and basic resource signals. Reports a final health verdict.
This is an independent troubleshooting tool - not part of the update/cleanup sealing workflow.

.NOTES
Version: 0.1 (Alpha)
Author: Dan Stark
#>

$ScriptRootPath = $PSScriptRoot
$LauncherWarningsPath = Join-Path $ScriptRootPath "config\launcher-warnings.json"

. "$ScriptRootPath\functions\Helper-Get-RandomLauncherWarning.ps1"

if ($PSVersionTable.PSEdition -ne "Desktop") {
    Write-Host (Get-RandomLauncherWarning -Path $LauncherWarningsPath) -ForegroundColor Red
    Write-Host "Please use the appropriate launcher or Windows PowerShell 5.1 to run this script." -ForegroundColor Yellow
    exit 1
}

$script:Warnings = @()
$script:Errors = @()
$DismThresholdGB = 10

function Write-Section {
    param ([string] $Title)
    Write-Host ""
    Write-Host "=== $Title ===" -ForegroundColor Cyan
}

function Add-Warning {
    param ([string] $Message)
    $script:Warnings += $Message
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Add-Error {
    param ([string] $Message)
    $script:Errors += $Message
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Add-OK {
    param ([string] $Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

# ============================================================
# CHECK 1: Reboot Pending
# ============================================================
function Test-PendingReboot {
    Write-Section "Check 1: Reboot Pending"

    $rebootPending = $false

    try {
        $rebootStatus = Get-WURebootStatus -Silent -ErrorAction SilentlyContinue
        if ($rebootStatus -eq $true) {
            $rebootPending = $true
        }
    } catch { }

    if (-not $rebootPending) {
        try {
            $key = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -ErrorAction SilentlyContinue
            if ($null -ne $key) {
                $rebootPending = $true
            }
        } catch { }
    }

    if (-not $rebootPending) {
        try {
            $cbsKey = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" -ErrorAction SilentlyContinue
            if ($null -ne $cbsKey) {
                $rebootPending = $true
            }
        } catch { }
    }

    if ($rebootPending) {
        Add-Warning "A reboot is pending. Some health checks may not reflect the true post-reboot state."
    } else {
        Add-OK "No reboot is pending."
    }
}

# ============================================================
# CHECK 2: DISM Image Health
# ============================================================
function Test-DismHealth {
    Write-Section "Check 2: DISM Image Health"

    Write-Host "Running DISM CheckHealth..." -ForegroundColor Yellow
    Write-Host "This may take a few minutes." -ForegroundColor DarkYellow

    try {
        $dismCheck = & DISM.exe /Online /Cleanup-Image /CheckHealth 2>&1
        $dismOutput = $dismCheck | Out-String

        if ($dismOutput -match "No component store corruption detected") {
            Add-OK "DISM reports image is healthy."
        } elseif ($dismOutput -match "The component store is repairable") {
            Add-Warning "DISM reports image is repairable. Starting RestoreHealth..."
            Write-Host ""
            Write-Host "NOTE: RestoreHealth can take up to 12 hours on older machines." -ForegroundColor Yellow
            Write-Host "Do not interrupt this process." -ForegroundColor Yellow
            Write-Host ""

            $dismRestore = & DISM.exe /Online /Cleanup-Image /RestoreHealth 2>&1
            $restoreOutput = $dismRestore | Out-String

            if ($restoreOutput -match "The restore operation completed successfully") {
                Add-OK "DISM RestoreHealth completed successfully."
            } else {
                Add-Error "DISM RestoreHealth completed but result could not be confirmed. Review manually."
                Write-Host $restoreOutput -ForegroundColor DarkYellow
            }
        } elseif ($dismOutput -match "The component store is irreparable") {
            Add-Error "DISM reports image is non-repairable. This image may need to be rebuilt."
        } else {
            Add-Warning "DISM CheckHealth returned an unrecognized result. Review output manually:"
            Write-Host $dismOutput -ForegroundColor DarkYellow
        }
    } catch {
        Add-Error "DISM check failed with an exception: $($_.Exception.Message)"
    }
}

# ============================================================
# CHECK 3: Free Disk Space
# ============================================================
function Test-DiskSpace {
    Write-Section "Check 3: Free Disk Space"

    try {
        $systemDrive = $env:SystemDrive
        $disk = Get-PSDrive -Name ($systemDrive.TrimEnd(':')) -ErrorAction Stop
        $freeGB = [math]::Round($disk.Free / 1GB, 2)
        $usedGB = [math]::Round($disk.Used / 1GB, 2)
        $totalGB = [math]::Round(($disk.Free + $disk.Used) / 1GB, 2)

        Write-Host "Drive $systemDrive - Total: ${totalGB}GB  Used: ${usedGB}GB  Free: ${freeGB}GB" -ForegroundColor Cyan

        if ($freeGB -lt $DismThresholdGB) {
            Add-Warning "Free disk space is below ${DismThresholdGB}GB ($freeGB GB free). Running DISM component cleanup..."
            Write-Host "Running DISM StartComponentCleanup..." -ForegroundColor Yellow

            $dismCleanup = & DISM.exe /Online /Cleanup-Image /StartComponentCleanup 2>&1
            $cleanupOutput = $dismCleanup | Out-String

            if ($cleanupOutput -match "The operation completed successfully") {
                Add-OK "DISM component cleanup completed."
                $diskAfter = Get-PSDrive -Name ($systemDrive.TrimEnd(':')) -ErrorAction SilentlyContinue
                if ($diskAfter) {
                    $freeAfterGB = [math]::Round($diskAfter.Free / 1GB, 2)
                    Write-Host "Free space after cleanup: ${freeAfterGB}GB" -ForegroundColor Green
                }
            } else {
                Add-Warning "DISM component cleanup completed but result could not be confirmed. Review manually."
            }
        } else {
            Add-OK "Free disk space is acceptable ($freeGB GB free)."
        }
    } catch {
        Add-Error "Disk space check failed: $($_.Exception.Message)"
    }
}

# ============================================================
# CHECK 4: Service Sanity
# ============================================================
function Test-ServiceSanity {
    Write-Section "Check 4: Service Sanity"

    $servicesToCheck = @(
        @{ Name = "msiserver"; ExpectedStartType = "Manual"; FriendlyName = "Windows Installer" },
        @{ Name = "TrustedInstaller"; ExpectedStartType = "Manual"; FriendlyName = "Windows Modules Installer" }
    )

    foreach ($svc in $servicesToCheck) {
        try {
            $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
            if (-not $service) {
                Add-Warning "Service '$($svc.FriendlyName)' not found."
                continue
            }

            $wmiSvc = Get-WmiObject -Class Win32_Service -Filter "Name='$($svc.Name)'" -ErrorAction SilentlyContinue
            $startMode = if ($wmiSvc) { $wmiSvc.StartMode } else { "Unknown" }

            if ($startMode -eq $svc.ExpectedStartType) {
                Add-OK "$($svc.FriendlyName) startup type is $startMode as expected."
            } else {
                Add-Warning "$($svc.FriendlyName) startup type is $startMode, expected $($svc.ExpectedStartType)."
            }
        } catch {
            Add-Error "Failed to check service $($svc.FriendlyName): $($_.Exception.Message)"
        }
    }
}

# ============================================================
# CHECK 5: Event Viewer Triage
# ============================================================
function Test-EventViewerTriage {
    param (
        [int] $LookbackHours = 24
    )

    Write-Section "Check 5: Event Viewer Triage (Last ${LookbackHours}h)"

    $since = (Get-Date).AddHours(-$LookbackHours)
    $logs = @("System", "Application")
    $excludedSources = @("CleanupScript", "WindowsUpdateScript", "VSS")

    foreach ($log in $logs) {
        try {
            $errors = @(Get-EventLog -LogName $log -EntryType Error -After $since -ErrorAction SilentlyContinue |
                Where-Object { $excludedSources -notcontains $_.Source } |
                Select-Object -First 5)

            if ($errors.Count -eq 0) {
                Add-OK "$log log: No errors in the last ${LookbackHours}h."
            } else {
                Add-Warning "$log log: $($errors.Count) error(s) found in the last ${LookbackHours}h (showing top $($errors.Count)):"
                foreach ($event in $errors) {
                    Write-Host "  [$($event.TimeGenerated.ToString('MM/dd/yy HH:mm'))] Source: $($event.Source) - $($event.Message.Split("`n")[0])" -ForegroundColor DarkYellow
                }
            }
        } catch {
            Add-Warning "Could not read $log event log: $($_.Exception.Message)"
        }
    }
}

# ============================================================
# CHECK 6: Resource Signals
# ============================================================
function Test-ResourceSignals {
    Write-Section "Check 6: Basic Resource Signals"

    try {
        $os = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop
        $totalMemGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        $freeMemGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        $usedMemGB = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 2)
        $memPct = [math]::Round(($usedMemGB / $totalMemGB) * 100, 1)

        Write-Host "Memory: Total ${totalMemGB}GB  Used ${usedMemGB}GB  Free ${freeMemGB}GB ($memPct% used)" -ForegroundColor Cyan

        if ($memPct -gt 90) {
            Add-Warning "Memory usage is critically high ($memPct% used)."
        } elseif ($memPct -gt 75) {
            Add-Warning "Memory usage is elevated ($memPct% used)."
        } else {
            Add-OK "Memory usage is acceptable ($memPct% used)."
        }
    } catch {
        Add-Warning "Could not retrieve memory usage: $($_.Exception.Message)"
    }

    try {
        $cpuLoad = (Get-WmiObject -Class Win32_Processor -ErrorAction Stop | Measure-Object -Property LoadPercentage -Average).Average
        Write-Host "CPU load: $cpuLoad%" -ForegroundColor Cyan

        if ($cpuLoad -gt 90) {
            Add-Warning "CPU load is critically high ($cpuLoad%). Something may be consuming the processor."
        } elseif ($cpuLoad -gt 75) {
            Add-Warning "CPU load is elevated ($cpuLoad%)."
        } else {
            Add-OK "CPU load is acceptable ($cpuLoad%)."
        }
    } catch {
        Add-Warning "Could not retrieve CPU load: $($_.Exception.Message)"
    }
}

# ============================================================
# FINAL VERDICT
# ============================================================
function Write-HealthVerdict {
    Write-Host ""
    if ($script:Errors.Count -gt 0) {
        Write-Banner "Health Check Complete" "Red"
        Write-Host ""
        Write-Host "[NEEDS ATTENTION] $($script:Errors.Count) error(s) detected. Review output above." -ForegroundColor Red
    } elseif ($script:Warnings.Count -gt 0) {
        Write-Banner "Health Check Complete" "DarkYellow"
        Write-Host ""
        Write-Host "[HEALTHY WITH WARNINGS] $($script:Warnings.Count) warning(s) detected. Review output above." -ForegroundColor DarkYellow
    } else {
        Write-Banner "Health Check Complete"
        Write-Host ""
        Write-Host "[HEALTHY] No errors or warnings detected." -ForegroundColor Green
    }
    Write-Host ""
}

# ============================================================
# RUN ALL CHECKS
# ============================================================
Write-Host ""
$border = '=' * 80

function Write-Banner {
    param([string]$Text, [string]$Color = 'Yellow')
    $centered = $Text.PadLeft([Math]::Floor(($border.Length + $Text.Length) / 2)).PadRight($border.Length)
    Write-Host $border -ForegroundColor Cyan
    Write-Host $centered -ForegroundColor $Color
    Write-Host $border -ForegroundColor Cyan
}

Write-Banner "System Health Check"
Write-Host "Computer : $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host "Date/Time: $(Get-Date -Format 'MM/dd/yyyy hh:mm tt')" -ForegroundColor Cyan
Write-Host ""

Test-PendingReboot
Test-DismHealth
Test-DiskSpace
Test-ServiceSanity
Test-EventViewerTriage
Test-ResourceSignals
Write-HealthVerdict
