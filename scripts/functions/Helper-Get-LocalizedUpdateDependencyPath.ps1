function Get-LocalizedUpdateDependencyPath {
    param (
        [Parameter(Mandatory = $true)]
        [string] $ModulesRoot
    )

    $result = [PSCustomObject]@{
        ModulePath = $null
        Source = $null
    }

    $localizedPSWindowsUpdate = Get-ChildItem -Path $ModulesRoot -Filter PSWindowsUpdate.psd1 -Recurse -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Select-Object -First 1

    if ($localizedPSWindowsUpdate) {
        $result.ModulePath = $localizedPSWindowsUpdate.FullName
        $result.Source = "Localized"
        return $result
    }

    $existingModule = Get-Module -Name PSWindowsUpdate -ListAvailable -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($existingModule) {
        $result.ModulePath = $existingModule.Path
        $result.Source = "Installed"
    }

    return $result
}
