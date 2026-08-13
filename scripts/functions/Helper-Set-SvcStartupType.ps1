function Set-SvcStartupType {
    <#
    .SYNOPSIS
    Sets a service startup type to Automatic, Manual, or Disabled.

    .DESCRIPTION
    Uses the Win32_Service ChangeStartMode method.

    ChangeStartMode cannot express delayed autostart. If a service ever needs
    "Automatic (Delayed Start)", set the DelayedAutostart DWORD under
    HKLM\SYSTEM\CurrentControlSet\Services\<name> after setting Automatic here.

    Returns a result object rather than throwing. ExitCode carries the raw
    Win32_Service return value and Message carries its decoded meaning.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string] $ServiceName,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Automatic", "Manual", "Disabled")]
        [string] $StartupType
    )

    $escapedName = $ServiceName -replace "'", "''"
    $service = Get-CimInstance -Class Win32_Service -Filter "Name='$escapedName'" -ErrorAction SilentlyContinue

    if (-not $service) {
        return [pscustomobject]@{
            ServiceName = $ServiceName
            Arguments   = "start=$StartupType"
            ExitCode    = 1
            Message     = "Service not found"
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

        $message = Format-SvcReturnCode -ReturnValue $result.ReturnValue

        [pscustomobject]@{
            ServiceName = $ServiceName
            Arguments   = "start=$startMode"
            ExitCode    = $result.ReturnValue
            Message     = $message
            StdOut      = if ($result.ReturnValue -eq 0) { "Service startup type updated" } else { "" }
            StdErr      = if ($result.ReturnValue -eq 0) { "" } else { $message }
            Success     = ($result.ReturnValue -eq 0)
        }
    }
    catch {
        [pscustomobject]@{
            ServiceName = $ServiceName
            Arguments   = "start=$startMode"
            ExitCode    = 1
            Message     = $_.Exception.Message
            StdOut      = ""
            StdErr      = $_.Exception.Message
            Success     = $false
        }
    }
}