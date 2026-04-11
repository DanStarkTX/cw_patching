function Init-EventLog {
    param (
        [Parameter(Mandatory = $true)]
        [string] $EventSource,

        [string] $LogName = "Application"
    )

    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
            [System.Diagnostics.EventLog]::CreateEventSource($EventSource, $LogName)
        }
    } catch {
        Write-Host "Failed to create event source. Event logging may not work. Error: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
