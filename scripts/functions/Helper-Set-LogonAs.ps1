function Set-LogonAs {
    param (
        [Parameter(Mandatory = $true)]
        [string] $ServiceName,

        [Parameter(Mandatory = $true)]
        [ValidateSet("LocalSystem", "Guest")]
        [string] $Account
    )

    $service = Get-CimInstance -Class Win32_Service -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue
    if (-not $service) {
        return [pscustomobject]@{
            ServiceName = $ServiceName
            Arguments   = "obj=$Account"
            ExitCode    = 1
            StdOut      = ""
            StdErr      = "Service not found"
            Success     = $false
        }
    }

    $startName = if ($Account -eq "LocalSystem") { "LocalSystem" } else { ".\Guest" }
    $password = if ($Account -eq "LocalSystem") { $null } else { "" }

    try {
        $result = $service | Invoke-CimMethod -MethodName Change -Arguments @{
            StartName = $startName
            StartPassword = $password
        }

        [pscustomobject]@{
            ServiceName = $ServiceName
            Arguments   = "obj=$startName"
            ExitCode    = $result.ReturnValue
            StdOut      = "Service logon account updated"
            StdErr      = ""
            Success     = ($result.ReturnValue -eq 0)
        }
    } catch {
        [pscustomobject]@{
            ServiceName = $ServiceName
            Arguments   = "obj=$startName"
            ExitCode    = 1
            StdOut      = ""
            StdErr      = $_.Exception.Message
            Success     = $false
        }
    }
}
