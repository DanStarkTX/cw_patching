function Import-LocalizedUpdateDependencies {
    param (
        [Parameter(Mandatory = $true)]
        [string] $ModulesRoot
    )

    $result = [PSCustomObject]@{
        PSWindowsUpdateAvailable = $false
        ImportedFromLocalizedPath = $false
        ErrorMessage = $null
    }

    $localizedPSWindowsUpdate = Get-ChildItem -Path $ModulesRoot -Filter PSWindowsUpdate.psd1 -Recurse -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Select-Object -First 1

    if ($localizedPSWindowsUpdate) {
        try {
            Import-Module $localizedPSWindowsUpdate.FullName -Force -ExecutionPolicy Bypass -ErrorAction Stop
            $result.PSWindowsUpdateAvailable = $true
            $result.ImportedFromLocalizedPath = $true
            return $result
        } catch {
            $result.ErrorMessage = "Failed to import localized module from '$($localizedPSWindowsUpdate.FullName)': $($_.Exception.Message)"
            return $result
        }
    }

    try {
        $existingModule = Get-Module -Name PSWindowsUpdate -ListAvailable -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($existingModule) {
            Import-Module -Name PSWindowsUpdate -Force -ExecutionPolicy Bypass -ErrorAction Stop
            $result.PSWindowsUpdateAvailable = $true
        } else {
            $result.ErrorMessage = "PSWindowsUpdate module not found in localized payload ($ModulesRoot) or installed modules."
        }
    } catch {
        $result.ErrorMessage = "Failed to import installed module: $($_.Exception.Message)"
    }

    return $result
}
