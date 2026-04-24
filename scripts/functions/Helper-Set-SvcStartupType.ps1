function Set-SvcStartupType {
    param (
        [Parameter(Mandatory = $true)]
        [string] $ServiceName,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Automatic", "Manual", "Disabled")]
        [string] $StartupType
    )

    $service = Get-CimInstance -Class Win32_Service -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue
    if (-not $service) {
        return [pscustomobject]@{
            ServiceName = $ServiceName
            Arguments   = "start=$StartupType"
            ExitCode    = 1
            StdOut      = ""
            StdErr      = "Service not found"
            Success     = $false
        }
    }

    $startMode = switch ($StartupType) {
        "Automatic" { "Automatic" }
        "Manual"    { "Manual" }
        "Disabled"  { "Disabled" }
    }

    try {
        $result = $service | Invoke-CimMethod -MethodName ChangeStartMode -Arguments @{
            StartMode = $startMode
        }

        [pscustomobject]@{
            ServiceName = $ServiceName
            Arguments   = "start=$startMode"
            ExitCode    = $result.ReturnValue
            StdOut      = "Service startup type updated"
            StdErr      = ""
            Success     = ($result.ReturnValue -eq 0)
        }
    } catch {
        [pscustomobject]@{
            ServiceName = $ServiceName
            Arguments   = "start=$startMode"
            ExitCode    = 1
            StdOut      = ""
            StdErr      = $_.Exception.Message
            Success     = $false
        }
    }
}
