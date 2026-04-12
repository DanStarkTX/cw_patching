<#
.SYNOPSIS
Script for managing prerequisites and Windows Updates.

.DESCRIPTION
Ensures prerequisites (NuGet provider and PSWindowsUpdate module) are installed and imported, ensures necessary services for Windows Updates are running, checks for updates, installs them, and reboots if necessary. Logs all actions and outcomes.

.NOTES
Version: 1.10
Author: Dan Stark
Changes: 
- Fixed variable scope issues.
- Fixed reboot detection logic.
- Removed redundant service validation.
- Added Windows Installer and TrustedInstaller protection and restoration.
- Removed unnecessary Explorer shell restart logic.
- Reads protected service configuration from services.json.
- Uses shared helper functions for logging and service configuration.
- Corrected helper loading and shared path handling.
- Normalizes displayed account names for operator clarity.
- Verifies successful installs against Windows Update history before reporting success.
- Improves post-install summary with clearer operator-facing verification details.
- Adds reusable recent-install summary helpers.
- Saves last confirmed install results to config\last_installed.json.
- Improves per-update event logging for operator review.
#>

. "$PSScriptRoot\functions\Helper-Init-EventLog.ps1"
. "$PSScriptRoot\functions\Helper-Write-EventLog.ps1"
. "$PSScriptRoot\functions\Helper-Get-SVCDetails.ps1"
. "$PSScriptRoot\functions\Helper-Invoke-ScConfig.ps1"
. "$PSScriptRoot\functions\Helper-Set-SvcStartupType.ps1"
. "$PSScriptRoot\functions\Helper-Set-LogonAs.ps1"
. "$PSScriptRoot\functions\Helper-Format-AccountName.ps1"
. "$PSScriptRoot\functions\Helper-Get-RecentWUInstallSummary.ps1"
. "$PSScriptRoot\functions\Helper-Save-LastInstalledJson.ps1"
. "$PSScriptRoot\functions\Helper-Get-RandomLauncherWarning.ps1"
. "$PSScriptRoot\functions\Helper-Import-LocalizedUpdateDependencies.ps1"

$ScriptRootPath = $PSScriptRoot
$potentialServices = @("winmgmt", "waasmedicsvc", "UsoSvc")
$ConfigPath = Join-Path $ScriptRootPath "config\services.json"
$LauncherWarningsPath = Join-Path $ScriptRootPath "config\launcher-warnings.json"
$ModulesRootPath = Join-Path $ScriptRootPath "modules"
$LastInstalledJsonPath = Join-Path $ScriptRootPath "config\last_installed.json"
$script:RunStartTime = Get-Date

if ($PSVersionTable.PSEdition -ne "Desktop") {
 Write-Host (Get-RandomLauncherWarning -Path $LauncherWarningsPath) -ForegroundColor Red
 Write-Host "Please use C:\cwave\run_updates.bat for a better experience." -ForegroundColor Yellow
 exit 1
}

if (-not (Test-Path $ConfigPath)) {
 Write-Host "Required config file not found: $ConfigPath" -ForegroundColor Red
 exit 1
}

$ServiceConfig = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
$protectedServices = @($ServiceConfig.protectedServices)
$requiredServices = @("wuauserv", "bits", "cryptsvc") + $protectedServices

$EventSource = "WindowsUpdateScript"
$LogName = "Application"
$script:UpdatesList = @()
$script:InstalledUpdates = @()
$script:SuccessfulInstallHistory = @()
$script:PendingRebootBlocked = $false

Init-EventLog -EventSource $EventSource -LogName $LogName
Write-EventLog -EventSource $EventSource -LogName $LogName -EntryType Information -EventId 1001 -Message "Windows Update script started."
$border = '=' * 80

Write-Host ""
Write-Host $border -ForegroundColor DarkBlue
Write-Host "-- Windows Update Script ---" -ForegroundColor Yellow
Write-Host $border -ForegroundColor DarkBlue

Write-Host ""
Write-Host $border -ForegroundColor DarkBlue
Write-Host "-- Checking and Restoring Service Accounts ---" -ForegroundColor Yellow
Write-Host $border -ForegroundColor DarkBlue
foreach ($service in $requiredServices + $potentialServices) {
 try {
 $serviceObj = Get-SVCDetails -ServiceName $service
 if (-not $serviceObj) {
 continue
 }

 $displayStartName = Format-AccountName -AccountName $serviceObj.StartName
 
 if ($serviceObj.StartName -like "*Guest*") {
 Write-Host "[FOUND] Service '$($serviceObj.DisplayName)' is set to log on as '$displayStartName'" -ForegroundColor Yellow
 Write-Host " Restoring to 'Local System'..." -ForegroundColor Yellow
 
 $result = Set-LogonAs -ServiceName $service -Account LocalSystem
 
 if ($result.ExitCode -eq 0) {
 Write-Host " Service '$($serviceObj.DisplayName)' restored to Local System." -ForegroundColor Green
 Write-EventLog -EventSource $EventSource -LogName $LogName -EntryType Information -EventId 1019 -Message "Service '$($serviceObj.DisplayName)' logon account restored to Local System."
 } else {
 Write-Host " Failed to restore service account. Exit code: $($result.ExitCode)" -ForegroundColor Red
 Write-EventLog -EventSource $EventSource -LogName $LogName -EntryType Error -EventId 1020 -Message "Failed to restore service '$($serviceObj.DisplayName)' to Local System. Exit code: $($result.ExitCode)"
 }
 $LASTEXITCODE = 0
 } else {
 Write-Host "[OK] Service '$($serviceObj.DisplayName)' is correctly set to '$displayStartName'" -ForegroundColor Green
 }
 } catch {
 Write-Host "Error checking/restoring service ${service}: $($_.Exception.Message)" -ForegroundColor Red
 }
}

function Start-WUServices {
 param (
 [string]$ServiceName
 )
 try {
 if ($ServiceName -eq "wuauserv") {
 $dependencies = @("bits", "cryptsvc")
 foreach ($dependency in $dependencies) {
 $depService = Get-SVCDetails -ServiceName $dependency
 if ($depService) {
 if ($depService.StartMode -eq "Disabled") {
 Write-Host "Re-enabling dependency service $($depService.DisplayName)..." -ForegroundColor Yellow
 Set-SvcStartupType -ServiceName $dependency -StartupType Automatic | Out-Null
 } elseif ($depService.StartMode -ne "Auto") {
 Write-Host "Setting dependency service $($depService.DisplayName) to Automatic..." -ForegroundColor Yellow
 Set-SvcStartupType -ServiceName $dependency -StartupType Automatic | Out-Null
 }
 
 if ($depService.State -ne "Running") {
 Write-Host "Starting dependency service: $($depService.DisplayName)" -ForegroundColor Yellow
 Start-Service -Name $dependency -ErrorAction Stop
 Write-Host "Dependency service $($depService.DisplayName) started successfully." -ForegroundColor Green
 }
 }
 }
 }

 $service = Get-SVCDetails -ServiceName $ServiceName
 if (-not $service) {
 throw "Service $ServiceName not found."
 }
 
 if ($protectedServices -contains $ServiceName) {
 if ($service.StartMode -eq "Disabled") {
 Write-Host "Re-enabling service $($service.DisplayName) to Manual..." -ForegroundColor Yellow
 Set-SvcStartupType -ServiceName $ServiceName -StartupType Manual | Out-Null
 } elseif ($service.StartMode -ne "Manual") {
 Write-Host "Setting service $($service.DisplayName) to Manual..." -ForegroundColor Yellow
 Set-SvcStartupType -ServiceName $ServiceName -StartupType Manual | Out-Null
 }
 } else {
 if ($service.StartMode -eq "Disabled") {
 Write-Host "Re-enabling service $($service.DisplayName)..." -ForegroundColor Yellow
 Set-SvcStartupType -ServiceName $ServiceName -StartupType Automatic | Out-Null
 } elseif ($service.StartMode -ne "Auto") {
 Write-Host "Setting service $($service.DisplayName) to Automatic..." -ForegroundColor Yellow
 Set-SvcStartupType -ServiceName $ServiceName -StartupType Automatic | Out-Null
 }
 }
 
 if ($service.State -ne "Running") {
 Write-Host "Starting service: $($service.DisplayName)" -ForegroundColor Yellow
 Start-Service -Name $ServiceName -ErrorAction Stop
 if ((Get-Service -Name $ServiceName).Status -eq "Running") {
 Write-Host "Service $($service.DisplayName) started successfully." -ForegroundColor Green
 } else {
 Write-Host "Failed to start service: $($service.DisplayName). Retrying with reset..." -ForegroundColor Red
 if ($protectedServices -contains $ServiceName) {
 Set-SvcStartupType -ServiceName $ServiceName -StartupType Manual | Out-Null
 } else {
 Set-SvcStartupType -ServiceName $ServiceName -StartupType Automatic | Out-Null
 }
 net.exe stop $ServiceName
 net.exe start $ServiceName
 if ((Get-Service -Name $ServiceName).Status -eq "Running") {
 Write-Host "Service $($service.DisplayName) reset and started successfully." -ForegroundColor Green
 } else {
 throw "Unable to start service $ServiceName after reset."
 }
 }
 }
 } catch {
 Write-Host "Critical failure: Unable to start $ServiceName. Error: $($_.Exception.Message)" -ForegroundColor Red
 Write-EventLog -EventSource $EventSource -LogName $LogName -EntryType Error -EventId 2003 -Message "Critical failure: Unable to start $ServiceName. Error: $($_.Exception.Message)"
 exit 1
 }
}

function Set-WUServices {
 Write-Host ""
 Write-Host $border -ForegroundColor DarkBlue
 Write-Host "-- Configuring Windows Update Services ---" -ForegroundColor Yellow
 Write-Host $border -ForegroundColor DarkBlue
 foreach ($service in $requiredServices + $potentialServices) {
 $serviceObj = Get-Service -Name $service -ErrorAction SilentlyContinue
 if (-not $serviceObj) {
 continue
 }
 Start-WUServices -ServiceName $service
 }
}

function Install-WindowsUpdatePrerequisites {
 Write-Host ""
 Write-Host $border -ForegroundColor DarkBlue
 Write-Host "-- Installing Prerequisites ---" -ForegroundColor Yellow
 Write-Host $border -ForegroundColor DarkBlue
 Write-Host "Checking for localized or installed PSWindowsUpdate module..." -ForegroundColor Yellow

 $dependencyState = Import-LocalizedUpdateDependencies -ModulesRoot $ModulesRootPath

 if ($dependencyState.PSWindowsUpdateAvailable) {
 if ($dependencyState.ImportedFromLocalizedPath) {
 Write-Host "PSWindowsUpdate module imported from localized payload." -ForegroundColor Green
 Write-EventLog -EventSource $EventSource -LogName $LogName -EntryType Information -EventId 1008 -Message "PSWindowsUpdate module imported from localized payload."
 } else {
 Write-Host "PSWindowsUpdate module is already available." -ForegroundColor Green
 }
 return
 }

 Write-Host "PSWindowsUpdate module not found in localized payload or installed modules." -ForegroundColor Red
 Write-Host "Localize PSWindowsUpdate into C:\cwave\scripts\modules before using this workflow on restricted machines." -ForegroundColor Yellow
 Write-EventLog -EventSource $EventSource -LogName $LogName -EntryType Error -EventId 1009 -Message "PSWindowsUpdate module was not found in localized payload or installed modules."
 exit 1
}

function Test-PendingReboot {
 try {
 $rebootStatus = Get-WURebootStatus -Silent -ErrorAction SilentlyContinue
 if ($rebootStatus -eq $true) {
 return $true
 }
 } catch {
 }

 try {
 $rebootPending = $null -ne (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -ErrorAction SilentlyContinue)
 if ($rebootPending) {
 return $true
 }
 } catch {
 }

 return $false
}

function Invoke-WindowsUpdate {
 Write-Host ""
 Write-Host $border -ForegroundColor DarkBlue
 Write-Host "-- Checking for Windows Updates ---" -ForegroundColor Yellow
 Write-Host $border -ForegroundColor DarkBlue
 Write-Host "Checking for available updates..." -ForegroundColor Yellow

 if (Test-PendingReboot) {
 $script:PendingRebootBlocked = $true
 Write-Host "A reboot is already pending from a prior update or install operation. Please reboot the system, then rerun do_updates.ps1." -ForegroundColor Yellow
 Write-EventLog -EventSource $EventSource -LogName $LogName -EntryType Warning -EventId 1025 -Message "A reboot was already pending before the update scan began. Operator should reboot and rerun do_updates.ps1."
 return
 }

 try {
 $script:UpdatesList = @(Get-WindowsUpdate -IgnoreReboot -ErrorAction Stop)
 if ($script:UpdatesList.Count -eq 0) {
 Write-Host "No updates found." -ForegroundColor Green
 Write-EventLog -EventSource $EventSource -LogName $LogName -EntryType Information -EventId 1012 -Message "No updates found."
 return
 }

 Write-Host "Updates found: $($script:UpdatesList.Count)" -ForegroundColor DarkBlue
 foreach ($update in $script:UpdatesList) {
 $kbValue = ($update.KBArticleID | Out-String).Trim()
 if (-not $kbValue) {
 $kbValue = "NoKB"
 }
 $updateMessage = "Update available: KB$kbValue - $($update.Title)"
 Write-Host $updateMessage -ForegroundColor DarkBlue
 Write-EventLog -EventSource $EventSource -LogName $LogName -EntryType Information -EventId 1013 -Message $updateMessage
 }

 Write-Host ""
 Write-Host $border -ForegroundColor DarkBlue
 Write-Host "-- Installing Windows Updates ---" -ForegroundColor Yellow
 Write-Host $border -ForegroundColor DarkBlue

 try {
 $script:InstalledUpdates = @(Install-WindowsUpdate -AcceptAll -IgnoreReboot -ErrorAction Stop -Verbose)
 } catch {
 Write-Host "Failed to install updates. Error: $($_.Exception.Message)" -ForegroundColor Red
 Write-EventLog -EventSource $EventSource -LogName $LogName -EntryType Error -EventId 1016 -Message "Failed to install updates. Error: $($_.Exception.Message)"
 exit 1
 }

 $script:SuccessfulInstallHistory = @(Get-RecentWUInstallSummary -Since $script:RunStartTime.AddMinutes(-5))
 try {
 Save-LastInstalledJson -Path $LastInstalledJsonPath -RunStartTime $script:RunStartTime -UpdatesFound $script:UpdatesList.Count -InstalledUpdates $script:SuccessfulInstallHistory
 } catch {
 Write-Host "Failed to save last_installed.json. Error: $($_.Exception.Message)" -ForegroundColor Yellow
 Write-EventLog -EventSource $EventSource -LogName $LogName -EntryType Warning -EventId 1024 -Message "Failed to save last_installed.json. Error: $($_.Exception.Message)"
 }

 $rebootPendingAfterInstall = Test-PendingReboot

 if ($script:SuccessfulInstallHistory.Count -gt 0) {
 Write-Host "Updates installed successfully." -ForegroundColor Green
 Write-EventLog -EventSource $EventSource -LogName $LogName -EntryType Information -EventId 1015 -Message "Updates installed successfully."
 foreach ($historyEntry in ($script:SuccessfulInstallHistory | Sort-Object Date)) {
 $kbDisplay = "No KB"
 if ($null -ne $historyEntry.KB) {
 $rawKbValue = ($historyEntry.KB | Out-String).Trim()
 if ($rawKbValue) {
 $kbDisplay = "KB$rawKbValue"
 }
 }
 $installedTime = "Unknown"
 if ($null -ne $historyEntry.Date) {
 try {
 $installedTime = ([datetime]$historyEntry.Date).ToString('MM/dd/yy hh:mm tt')
 } catch {
 $installedTime = "Unknown"
 }
 }
 $installedMessage = "Installed update confirmed: $kbDisplay - $($historyEntry.Title) | Installed: $installedTime | Category: $($historyEntry.Category)"
 Write-EventLog -EventSource $EventSource -LogName $LogName -EntryType Information -EventId 1023 -Message $installedMessage
 }
 } elseif ($script:InstalledUpdates.Count -gt 0 -and $rebootPendingAfterInstall) {
 Write-Host "PSWindowsUpdate reported installed updates, but Windows Update history has not confirmed them yet." -ForegroundColor Yellow
 Write-Host "A reboot is currently pending. Reboot the system, then rerun do_updates.ps1 to verify the post-reboot state." -ForegroundColor Yellow
 Write-EventLog -EventSource $EventSource -LogName $LogName -EntryType Warning -EventId 1026 -Message "PSWindowsUpdate reported installed updates, but Windows Update history had not confirmed them before reboot. Operator should reboot and rerun do_updates.ps1."
 } else {
 Write-Host "No successfully installed updates were confirmed in Windows Update history." -ForegroundColor Yellow
 Write-EventLog -EventSource $EventSource -LogName $LogName -EntryType Warning -EventId 1022 -Message "Install-WindowsUpdate completed, but no new successful installations were confirmed in Windows Update history."
 }

 if ($rebootPendingAfterInstall) {
 Write-Host "One or more updates require a reboot. Please reboot the system manually." -ForegroundColor Yellow
 Write-EventLog -EventSource $EventSource -LogName $LogName -EntryType Warning -EventId 1021 -Message "System reboot required after update installation."
 }

 Write-Host ""
 Write-Host $border -ForegroundColor DarkBlue
 Write-Host "-- Summary of Installed Updates ---" -ForegroundColor Yellow
 Write-Host $border -ForegroundColor DarkBlue
 if ($script:SuccessfulInstallHistory.Count -eq 0) {
 if ($script:InstalledUpdates.Count -gt 0 -and (Test-PendingReboot)) {
 Write-Host "Installed updates were reported, but confirmation in Get-WUHistory may not appear until after reboot." -ForegroundColor Yellow
 } else {
 Write-Host "No new successful installations were confirmed in Get-WUHistory." -ForegroundColor Yellow
 }
 Write-Host "Note: Control Panel 'Installed Updates' does not reliably show every update type, especially Defender/platform updates." -ForegroundColor DarkYellow
 Write-Host "last_installed.json updated with the latest run status." -ForegroundColor DarkYellow
 } else {
 Write-Host "Confirmed via Get-WUHistory:" -ForegroundColor Green
 foreach ($historyEntry in ($script:SuccessfulInstallHistory | Sort-Object Date)) {
 $kbDisplay = "No KB"
 if ($null -ne $historyEntry.KB) {
 $rawKbValue = ($historyEntry.KB | Out-String).Trim()
 if ($rawKbValue) {
 $kbDisplay = "KB$rawKbValue"
 }
 }
 $installedTime = "Unknown"
 if ($null -ne $historyEntry.Date) {
 try {
 $installedTime = ([datetime]$historyEntry.Date).ToString('MM/dd/yy hh:mm tt')
 } catch {
 $installedTime = "Unknown"
 }
 }
 Write-Host " - $kbDisplay | $($historyEntry.Title) | Installed: $installedTime | Category: $($historyEntry.Category)" -ForegroundColor Green
 }
 Write-Host "Saved run details to: $LastInstalledJsonPath" -ForegroundColor DarkBlue
 }
 } catch {
 Write-Host "Failed to check or install updates. Error: $($_.Exception.Message)" -ForegroundColor Red
 Write-EventLog -EventSource $EventSource -LogName $LogName -EntryType Error -EventId 1016 -Message "Failed to check or install updates. Error: $($_.Exception.Message)"
 exit 1
 }
}

Set-WUServices
Install-WindowsUpdatePrerequisites
Invoke-WindowsUpdate

if ($script:PendingRebootBlocked) {
 Write-Host ""
 Write-Host "[REBOOT REQUIRED] A reboot is already pending. Reboot the system then rerun run_updates.bat." -ForegroundColor Red
 Write-EventLog -EventSource $EventSource -LogName $LogName -EntryType Warning -EventId 1027 -Message "Windows Update process stopped because a reboot was already pending."
 Write-Host ""
} elseif ($script:SuccessfulInstallHistory.Count -gt 0) {
 Write-Host ""
 Write-Host "[DONE] Updates installed successfully." -ForegroundColor Green
 Write-Host "[ACTION] Reboot the system, then run run_cleanup.bat." -ForegroundColor Yellow
 Write-EventLog -EventSource $EventSource -LogName $LogName -EntryType Information -EventId 1017 -Message "Windows Update process completed successfully."
 Write-Host ""
} elseif ($script:InstalledUpdates.Count -gt 0 -and (Test-PendingReboot)) {
 Write-Host ""
 Write-Host "[PENDING] Updates were reported installed but not yet confirmed. Reboot to verify." -ForegroundColor DarkYellow
 Write-EventLog -EventSource $EventSource -LogName $LogName -EntryType Warning -EventId 1028 -Message "Windows Update process reported installs and is awaiting reboot before final confirmation."
 Write-Host ""
} else {
 Write-Host ""
 Write-Host "[DONE] No new updates found. System is up to date." -ForegroundColor Green
 Write-EventLog -EventSource $EventSource -LogName $LogName -EntryType Information -EventId 1017 -Message "Windows Update process completed successfully."
 Write-EventLog -EventSource $EventSource -LogName $LogName -EntryType Information -EventId 1018 -Message "No updates were installed. The system is up to date."
 Write-Host ""
}
