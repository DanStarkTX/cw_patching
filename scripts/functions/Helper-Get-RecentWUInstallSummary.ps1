function Get-RecentWUInstallSummary {
    param (
        [Parameter(Mandatory = $true)]
        [datetime] $Since,

        [datetime] $Until = (Get-Date)
    )

    $history = @(Get-WUHistory | Where-Object {
        $_.Operation -eq "Installation" -and
        $_.Result -eq "Succeeded" -and
        $_.Date -ge $Since -and
        $_.Date -le $Until
    } | Sort-Object Date)

    foreach ($entry in $history) {
        $kbValue = ($entry.KB | Out-String).Trim()
        if (-not $kbValue) {
            $kbValue = $null
        }

        $category = "Other"
        if ($entry.Title -match "Defender|Security Intelligence") {
            $category = "Defender"
        } elseif ($entry.Title -match "Driver|Broadcom|Intel|Realtek|NVIDIA|AMD") {
            $category = "Driver"
        } elseif ($entry.Title -match "Cumulative Update|Security Update|Windows") {
            $category = "Windows"
        }

        [PSCustomObject]@{
            Date     = $entry.Date
            Title    = $entry.Title
            KB       = $kbValue
            Result   = $entry.Result
            Category = $category
        }
    }
}
