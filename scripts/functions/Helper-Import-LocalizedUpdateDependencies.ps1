function Import-LocalizedUpdateDependencies {
    param (
        [Parameter(Mandatory = $true)]
        [string] $ModulesRoot
    )

    $result = [PSCustomObject]@{
        PSWindowsUpdateAvailable = $false
        ImportedFromLocalizedPath = $false
    }

    $localizedPSWindowsUpdate = Get-ChildItem -Path $ModulesRoot -Filter PSWindowsUpdate.psd1 -Recurse -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Select-Object -First 1

    if ($localizedPSWindowsUpdate) {
        try {
            Import-Module $localizedPSWindowsUpdate.FullName -Force -ErrorAction Stop
            $result.PSWindowsUpdateAvailable = $true
            $result.ImportedFromLocalizedPath = $true
            return $result
        } catch {
        }
    }

    try {
        $existingModule = Get-Module -Name PSWindowsUpdate -ListAvailable -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($existingModule) {
            Import-Module -Name PSWindowsUpdate -Force -ErrorAction Stop
            $result.PSWindowsUpdateAvailable = $true
        }
    } catch {
    }

    return $result
}
