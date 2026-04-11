function Set-SvcStartupType {
    param (
        [Parameter(Mandatory = $true)]
        [string] $ServiceName,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Automatic", "Manual", "Disabled")]
        [string] $StartupType
    )

    $arguments = switch ($StartupType) {
        "Automatic" { "start= auto" }
        "Manual"    { "start= demand" }
        "Disabled"  { "start= disabled" }
    }

    Invoke-ScConfig -ServiceName $ServiceName -Arguments $arguments
}
