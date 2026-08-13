function Get-SVCDetails {
    param (
        [Parameter(Mandatory = $true)]
        [string] $ServiceName
    )

    $escapedName = $ServiceName -replace "'", "''"
    $cimService = Get-CimInstance -Class Win32_Service -Filter "Name='$escapedName'" -ErrorAction SilentlyContinue

    if ($cimService) {
        return $cimService
    }

    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $service) {
        return $null
    }

    $registryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
    $registryKey = Get-ItemProperty -Path $registryPath -ErrorAction SilentlyContinue

    $startMode = "Unknown"
    if ($null -ne $registryKey -and $null -ne $registryKey.Start) {
        $startMode = switch ([int]$registryKey.Start) {
            0 { "Boot" }
            1 { "System" }
            2 { "Auto" }
            3 { "Manual" }
            4 { "Disabled" }
            default { "Unknown" }
        }
    }

    $startName = "Unknown"
    if ($null -ne $registryKey -and $registryKey.ObjectName) {
        $startName = $registryKey.ObjectName
    }

    [PSCustomObject]@{
        Name        = $service.Name
        DisplayName = $service.DisplayName
        State       = $service.Status.ToString()
        StartMode   = $startMode
        StartName   = $startName
        Source      = "Registry"
    }
}