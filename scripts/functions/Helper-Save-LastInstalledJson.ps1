function Save-LastInstalledJson {
    param (
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [datetime] $RunStartTime,

        [Parameter(Mandatory = $true)]
        [int] $UpdatesFound,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $InstalledUpdates,

        [string] $ComputerName = $env:COMPUTERNAME
    )

    $parent = Split-Path -Path $Path -Parent
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -Path $parent -ItemType Directory -Force | Out-Null
    }

    $normalizedInstalledUpdates = @($InstalledUpdates)

    $payload = [PSCustomObject]@{
        LastRunTime      = (Get-Date).ToString("o")
        RunStartTime     = $RunStartTime.ToString("o")
        ComputerName     = $ComputerName
        UpdatesFound     = $UpdatesFound
        UpdatesInstalled = $normalizedInstalledUpdates.Count
        Status           = if ($normalizedInstalledUpdates.Count -gt 0) { "Succeeded" } else { "NoConfirmedInstalls" }
        Updates          = @(
            foreach ($update in $normalizedInstalledUpdates) {
                $updateDate = $null
                if ($null -ne $update.Date) {
                    try {
                        $updateDate = (Get-Date $update.Date).ToString("o")
                    } catch {
                        $updateDate = $null
                    }
                }

                [PSCustomObject]@{
                    Date     = $updateDate
                    Title    = $update.Title
                    KB       = $update.KB
                    Result   = $update.Result
                    Category = $update.Category
                }
            }
        )
    }

    $payload | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Encoding UTF8
}
