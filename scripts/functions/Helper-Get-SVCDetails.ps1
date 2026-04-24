function Get-SVCDetails {
    param (
        [Parameter(Mandatory = $true)]
        [string] $ServiceName
    )

    Get-CimInstance -Class Win32_Service -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue
}
