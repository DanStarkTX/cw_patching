function Set-LogonAs {
    <#
    .SYNOPSIS
    Sets a service logon account to LocalSystem or the local Guest account.

    .DESCRIPTION
    Uses the Win32_Service Change method. Note that this deliberately does NOT
    grant SeServiceLogonRight ("Log on as a service") to the target account.

    That omission is load-bearing for the cleanup workflow: pointing a disabled
    service at .\Guest, which is a disabled account holding no service logon
    right, means the service cannot start even if something later flips its
    Start value back to Auto. Adding an LSA rights grant here would defeat the
    seal. sc.exe behaves the same way; only the services.msc GUI grants the
    right implicitly.

    Returns a result object rather than throwing. ExitCode carries the raw
    Win32_Service return value and Message carries its decoded meaning.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string] $ServiceName,

        [Parameter(Mandatory = $true)]
        [ValidateSet("LocalSystem", "Guest")]
        [string] $Account
    )

    $escapedName = $ServiceName -replace "'", "''"
    $service = Get-CimInstance -Class Win32_Service -Filter "Name='$escapedName'" -ErrorAction SilentlyContinue

    if (-not $service) {
        return [pscustomobject]@{
            ServiceName = $ServiceName
            Arguments   = "obj=$Account"
            ExitCode    = 1
            Message     = "Service not found"
            StdOut      = ""
            StdErr      = "Service not found"
            Success     = $false
        }
    }

    $startName = if ($Account -eq "LocalSystem") { "LocalSystem" } else { ".\Guest" }
    $password = if ($Account -eq "LocalSystem") { $null } else { "" }

    try {
        $result = $service | Invoke-CimMethod -MethodName Change -Arguments @{
            StartName     = $startName
            StartPassword = $password
        }

        $message = Format-SvcReturnCode -ReturnValue $result.ReturnValue

        [pscustomobject]@{
            ServiceName = $ServiceName
            Arguments   = "obj=$startName"
            ExitCode    = $result.ReturnValue
            Message     = $message
            StdOut      = if ($result.ReturnValue -eq 0) { "Service logon account updated" } else { "" }
            StdErr      = if ($result.ReturnValue -eq 0) { "" } else { $message }
            Success     = ($result.ReturnValue -eq 0)
        }
    }
    catch {
        [pscustomobject]@{
            ServiceName = $ServiceName
            Arguments   = "obj=$startName"
            ExitCode    = 1
            Message     = $_.Exception.Message
            StdOut      = ""
            StdErr      = $_.Exception.Message
            Success     = $false
        }
    }
}