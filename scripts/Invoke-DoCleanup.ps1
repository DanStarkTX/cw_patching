$packageManagementModule = "C:\Program Files\WindowsPowerShell\Modules\PackageManagement\1.0.0.1\PackageManagement.psd1"
$powerShellGetModule = "C:\Program Files\WindowsPowerShell\Modules\PowerShellGet\1.0.0.1\PowerShellGet.psd1"

if (Test-Path $packageManagementModule) {
    Import-Module $packageManagementModule -ErrorAction SilentlyContinue
}

if (Test-Path $powerShellGetModule) {
    Import-Module $powerShellGetModule -ErrorAction SilentlyContinue
}

& "C:\cwave\scripts\do_cleanup.ps1"
