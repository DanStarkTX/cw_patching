function Set-LogonAs {
    param (
        [Parameter(Mandatory = $true)]
        [string] $ServiceName,

        [Parameter(Mandatory = $true)]
        [ValidateSet("LocalSystem", "Guest")]
        [string] $Account
    )

    $arguments = switch ($Account) {
        "LocalSystem" { 'obj= "LocalSystem"' }
        "Guest"       { 'obj= ".\Guest" password= ""' }
    }

    Invoke-ScConfig -ServiceName $ServiceName -Arguments $arguments
}
