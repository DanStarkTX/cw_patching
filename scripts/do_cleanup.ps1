<#
.SYNOPSIS
Performs system cleanup tasks such as disabling services, cleaning folders, and removing tasks.

.NOTES
Version: 1.08
Author: Dan Stark
Changes: 
- Added setting Services to Log on as Guest.
- Added scheduled task removal.
- Added improved validation and reporting.
- Cleaned up comments for Brevity and Clarity.
- Added protection for Windows Installer service (msiserver).
- Added protection for Windows Modules Installer service (TrustedInstaller).
- Enforces Manual startup type for protected servicing services.
- Reads service configuration from services.json.
- Uses shared helper functions.
- Normalizes displayed account names for operator clarity.
#>

param (
 [string[]] $FoldersToClean = @("C:\Windows\SoftwareDistribution\Download"),
 [string[]] $TaskFoldersToRemove = @("Defrag", "SystemRestore", "UpdateOrchestrator", "UPnP", "WaaSMedic", "Windows Defender"),
 [string] $StateFilePath = "C:\cwave\state_cleanup.txt"
)

$ScriptRootPath = $PSScriptRoot
$LauncherWarningsPath = Join-Path $ScriptRootPath "config\launcher-warnings.json"

. "$ScriptRootPath\functions\Helper-Get-RandomLauncherWarning.ps1"

if ($PSVersionTable.PSEdition -ne "Desktop") {
 Write-Host (Get-RandomLauncherWarning -Path $LauncherWarningsPath) -ForegroundColor Red
 Write-Host "Please use C:\cwave\run_cleanup.bat for a better experience." -ForegroundColor Yellow
 exit 1
}

. "$ScriptRootPath\functions\Helper-Init-EventLog.ps1"
. "$ScriptRootPath\functions\Helper-Write-EventLog.ps1"
. "$ScriptRootPath\functions\Helper-Get-SVCDetails.ps1"
. "$ScriptRootPath\functions\Helper-Invoke-ScConfig.ps1"
. "$ScriptRootPath\functions\Helper-Set-SvcStartupType.ps1"
. "$ScriptRootPath\functions\Helper-Set-LogonAs.ps1"
. "$ScriptRootPath\functions\Helper-Format-AccountName.ps1"

$EventSource = "CleanupScript"
$LogName = "Application"
$EventIDStart = 1000
$EventIDError = 1001
$EventIDEnd = 1002
$ConfigPath = Join-Path $ScriptRootPath "config\services.json"

if (-not (Test-Path $ConfigPath)) {
 Write-Host "Required config file not found: $ConfigPath" -ForegroundColor Red
 exit 1
}

$ServiceConfig = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
$ServicesToDisable = @($ServiceConfig.servicesToDisable)
$ProtectedServices = @($ServiceConfig.protectedServices)

function Initialize-Logging {
 Init-EventLog -EventSource $EventSource -LogName $LogName
}

function Write-ErrorLog {
 param (
 [string] $Message
 )
 Write-EventLog -EventSource $EventSource -LogName $LogName -EntryType Error -EventId $EventIDError -Message $Message
}

function Set-RegistryKeyOwnership {
 param (
 [string] $RegistryPath
 )
 try {
 $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($RegistryPath, $true)
 $acl = $key.GetAccessControl()
 $owner = [System.Security.Principal.NTAccount]"Administrators"
 $acl.SetOwner($owner)
 $acl.AddAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule("Administrators", "FullControl", "ContainerInherit, ObjectInherit", "None", "Allow")))
 $key.SetAccessControl($acl)
 Write-Host "Ownership of registry key $RegistryPath has been updated." -ForegroundColor Green
 } catch {
 Write-ErrorLog -Message "Failed to take ownership of registry key $RegistryPath. Error: $($_.Exception.Message)"
 }
}

function Restore-ProtectedServiceStartup {
 param (
 [string] $ServiceName
 )

 try {
 $service = Get-SVCDetails -ServiceName $ServiceName
 if (-not $service) {
 Write-Host "Service '$ServiceName' does not exist. Skipping startup restore..." -ForegroundColor Yellow
 return
 }

 if ($service.StartMode -ne "Manual") {
 Write-Host "Setting $ServiceName startup type to Manual..." -ForegroundColor Yellow
 Set-SvcStartupType -ServiceName $ServiceName -StartupType Manual | Out-Null

 $updatedService = Get-SVCDetails -ServiceName $ServiceName
 if ($updatedService -and $updatedService.StartMode -eq "Manual") {
 Write-Host "$ServiceName startup type set to Manual." -ForegroundColor Green
 } else {
 Write-Host "Failed to confirm Manual startup type for $ServiceName." -ForegroundColor Red
 Write-ErrorLog -Message "Failed to confirm Manual startup type for $ServiceName."
 }
 } else {
 Write-Host "$ServiceName is already set to Manual." -ForegroundColor Green
 }
 } catch {
 Write-ErrorLog -Message "Failed to restore startup type for $ServiceName. Error: $($_.Exception.Message)"
 }
}

function Set-ServiceLogonAccount {
 param (
 [string] $ServiceName
 )
 
 if ($ServiceName -eq "WaaSMedicSvc") {
 Write-Host "Skipping logon account change for $ServiceName (disable only)" -ForegroundColor Yellow
 return
 }

 if ($ProtectedServices -contains $ServiceName) {
 Write-Host "Skipping logon account change for protected service $ServiceName" -ForegroundColor Yellow
 return
 }
 
 try {
 $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
 if (-not $service) {
 Write-Host "Service '$ServiceName' does not exist. Skipping logon account change..." -ForegroundColor Yellow
 return
 }

 Write-Host "Attempting to change $ServiceName logon account..." -ForegroundColor Gray
 
 $result = Set-LogonAs -ServiceName $ServiceName -Account Guest
 
 Write-Host "sc.exe output: $($result.StdOut)" -ForegroundColor Gray
 if ($result.StdErr) { Write-Host "sc.exe error: $($result.StdErr)" -ForegroundColor Gray }
 Write-Host "Exit code: $($result.ExitCode)" -ForegroundColor Gray
 
 if ($result.ExitCode -eq 0) {
 Write-Host "$ServiceName logon account changed to .\Guest." -ForegroundColor Green
 } else {
 Write-Host "Failed to change logon account for $ServiceName. Exit code: $($result.ExitCode)" -ForegroundColor Red
 Write-ErrorLog -Message "Failed to change logon account for $ServiceName. Exit code: $($result.ExitCode), Output: $($result.StdOut)"
 }
 } catch {
 Write-Host "Exception occurred: $($_.Exception.Message)" -ForegroundColor Red
 Write-ErrorLog -Message "Failed to change logon account for $ServiceName. Error: $($_.Exception.Message)"
 }
}

function Disable-ServiceViaRegistry {
 param (
 [string] $ServiceName
 )

 if ($ProtectedServices -contains $ServiceName) {
 Write-Host "Skipping protected service '$ServiceName'. It must remain available." -ForegroundColor Yellow
 return
 }

 $RegistryPath = "SYSTEM\CurrentControlSet\Services\$ServiceName"

 $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
 if (-not $service) {
 Write-Host "Service '$ServiceName' does not exist. Skipping..." -ForegroundColor Yellow
 Write-EventLog -EventSource $EventSource -LogName $LogName -EntryType Information -EventId 1003 -Message "Service '$ServiceName' not found during cleanup. This is expected if the service does not exist on this OS. Skipping."
 return
 }

 try {
 if ($service.Status -eq 'Running') {
 Stop-Service -Name $ServiceName -Force -ErrorAction Stop
 Write-Host "$ServiceName has been stopped." -ForegroundColor Green
 }

 $regKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($RegistryPath, $true)
 if (-not $regKey) {
 Set-RegistryKeyOwnership -RegistryPath $RegistryPath
 $regKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($RegistryPath, $true)
 }

 if ($regKey) {
 $regKey.SetValue("Start", 4, [Microsoft.Win32.RegistryValueKind]::DWord)
 $regKey.Close()
 Write-Host "$ServiceName has been disabled via the registry." -ForegroundColor Green
 } else {
 Write-ErrorLog -Message "Registry path for $ServiceName not found or accessible. Cannot disable the service."
 }

 Set-Service -Name $ServiceName -StartupType Disabled -ErrorAction SilentlyContinue
 Write-Host "$ServiceName has been set to Disabled." -ForegroundColor Green

 } catch {
 Write-ErrorLog -Message "Failed to stop, disable, or set $ServiceName to Disabled. Error: $($_.Exception.Message)"
 }
}

function Remove-TaskFolders {
 param (
 [string[]] $TaskFolders
 )
 foreach ($taskFolder in $TaskFolders) {
 try {
 $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -like "*\$taskFolder\*" }
 foreach ($task in $tasks) {
 Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false -ErrorAction SilentlyContinue
 Write-Host "Unregistered scheduled task: $($task.TaskPath)$($task.TaskName)" -ForegroundColor Green
 }

 $TaskPath = "C:\Windows\System32\Tasks\$taskFolder"
 if (Test-Path $TaskPath) {
 Get-ChildItem -Path $TaskPath -Recurse -Force | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
 Remove-Item -Path $TaskPath -Force -ErrorAction SilentlyContinue
 Write-Host "Removed task folder: $TaskPath" -ForegroundColor Green
 }
 } catch {
 Write-ErrorLog -Message "Failed to clean tasks in folder $taskFolder. Error: $($_.Exception.Message)"
 }
 }
}

function Clear-Folders {
 param (
 [string[]] $Folders
 )
 foreach ($folder in $Folders) {
 if (Test-Path $folder) {
 try {
 Get-ChildItem -Path $folder -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
 Write-Host "Cleared folder: $folder" -ForegroundColor Green
 } catch {
 Write-ErrorLog -Message "Failed to clear folder $folder. Error: $($_.Exception.Message)"
 }
 } else {
 Write-Host "Folder not found: $folder" -ForegroundColor Yellow
 }
 }
}

Initialize-Logging
Write-EventLog -EventSource $EventSource -LogName $LogName -EntryType Information -EventId $EventIDStart -Message "Starting cleanup script."

$border = '=' * 80

function Write-Banner {
    param([string]$Text, [string]$Color = 'Yellow')
    $centered = $Text.PadLeft([Math]::Floor(($border.Length + $Text.Length) / 2)).PadRight($border.Length)
    Write-Host $border -ForegroundColor Cyan
    Write-Host $centered -ForegroundColor $Color
    Write-Host $border -ForegroundColor Cyan
}

Write-Host ""
Write-Banner "Cleanup Script"

try {
 Write-Host ""
 Write-Host "=== Removing Scheduled Task Folders ===" -ForegroundColor Cyan
 Remove-TaskFolders -TaskFolders $TaskFoldersToRemove

 Write-Host ""
 Write-Host "=== Clearing Folders ===" -ForegroundColor Cyan
 Clear-Folders -Folders $FoldersToClean

 Write-Host ""
 Write-Host "=== Disabling Services ===" -ForegroundColor Cyan
 foreach ($serviceName in $ServicesToDisable) {
 Disable-ServiceViaRegistry -ServiceName $serviceName
 $LASTEXITCODE = 0
 }

 Write-Host ""
 Write-Host "=== Changing Service Logon Accounts ===" -ForegroundColor Cyan
 foreach ($serviceName in $ServicesToDisable) {
 Set-ServiceLogonAccount -ServiceName $serviceName
 $LASTEXITCODE = 0
 }

 Write-Host ""
 Write-Host "=== Restoring Protected Services ===" -ForegroundColor Cyan
 foreach ($serviceName in $ProtectedServices) {
 Restore-ProtectedServiceStartup -ServiceName $serviceName
 $LASTEXITCODE = 0
 }

 Write-Host ""
 Write-Host "=== Final Service Status ===" -ForegroundColor Cyan
 foreach ($serviceName in ($ServicesToDisable + $ProtectedServices)) {
 $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
 if ($service) {
 $wmiService = Get-SVCDetails -ServiceName $serviceName
 $logonAccount = if ($wmiService) { Format-AccountName -AccountName $wmiService.StartName } else { "Unknown" }
 $startMode = if ($wmiService) { $wmiService.StartMode } else { "Unknown" }
 
 Write-Host "Service: $serviceName" -ForegroundColor White
 Write-Host " Status: $($service.Status)" -ForegroundColor $(if ($serviceName -in $ProtectedServices) { 'Yellow' } elseif ($service.Status -eq 'Stopped') { 'Green' } else { 'Red' })
 Write-Host " StartType: $startMode" -ForegroundColor $(if ($serviceName -in $ProtectedServices) { if ($startMode -eq 'Manual') { 'Green' } else { 'Red' } } elseif ($startMode -eq 'Disabled') { 'Green' } else { 'Red' })
 Write-Host " LogonAs: $logonAccount" -ForegroundColor $(if ($serviceName -in $ProtectedServices) { if ($logonAccount -like '*LocalSystem*') { 'Green' } else { 'Yellow' } } elseif ($logonAccount -eq '.\Guest') { 'Green' } else { 'Yellow' })
 Write-Host ""
 }
 }

 Write-Host ""
 Write-Banner "Cleanup Complete"
 Write-Host ""
 Write-Host "[DONE] Services sealed, tasks removed." -ForegroundColor Green
 Write-Host "[ACTION] Shutdown and take your snapshot." -ForegroundColor Yellow
 Write-Host ""

} catch {
 Write-ErrorLog -Message "Unexpected error in cleanup script. Error: $($_.Exception.Message)"
 exit 1
}

Write-EventLog -EventSource $EventSource -LogName $LogName -EntryType Information -EventId $EventIDEnd -Message "Cleanup script completed successfully."
Start-Process "services.msc"
exit 0
