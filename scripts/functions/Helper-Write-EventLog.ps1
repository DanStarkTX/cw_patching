function Write-EventLog {
    param (
        [Parameter(Mandatory = $true)]
        [string] $EventSource,

        [string] $LogName = "Application",

        [Parameter(Mandatory = $true)]
        [ValidateSet("Information", "Warning", "Error")]
        [string] $EntryType,

        [Parameter(Mandatory = $true)]
        [int] $EventId,

        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    try {
        if (Get-Command -Name Write-EventLog -CommandType Cmdlet -ErrorAction SilentlyContinue) {
            Microsoft.PowerShell.Management\Write-EventLog -LogName $LogName -Source $EventSource -EntryType $EntryType -EventId $EventId -Message $Message
            return
        }

        if ([System.Diagnostics.EventLog]::SourceExists($EventSource)) {
            $eventLog = New-Object System.Diagnostics.EventLog($LogName)
            $eventLog.Source = $EventSource
            $eventLog.WriteEntry($Message, [System.Diagnostics.EventLogEntryType]::$EntryType, $EventId)
            return
        }

        Write-Host "Event source '$EventSource' does not exist. Skipping Event Log write." -ForegroundColor Yellow
    } catch {
        Write-Host "Failed to write to Event Log. Error: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
