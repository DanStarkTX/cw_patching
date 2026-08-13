function Format-SvcReturnCode {
    <#
    .SYNOPSIS
    Translates a Win32_Service method return code into readable text.

    .DESCRIPTION
    Win32_Service methods (Change, ChangeStartMode, StartService, StopService)
    return a numeric code rather than throwing. Codes are documented by Microsoft
    for the Win32_Service class. Anything not listed is surfaced as-is so an
    unexpected code is still actionable.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object] $ReturnValue
    )

    if ($null -eq $ReturnValue) {
        return "No return value"
    }

    switch ([int]$ReturnValue) {
        0  { "Success" }
        1  { "Not supported" }
        2  { "Access denied" }
        3  { "Dependent services running" }
        4  { "Invalid service control" }
        5  { "Service cannot accept control" }
        6  { "Service not active" }
        7  { "Service request timeout" }
        8  { "Unknown failure" }
        9  { "Path not found" }
        10 { "Service already running" }
        11 { "Service database locked" }
        12 { "Service dependency deleted" }
        13 { "Service dependency failure" }
        14 { "Service disabled" }
        15 { "Service logon failed" }
        16 { "Service marked for deletion" }
        17 { "Service has no execution thread" }
        18 { "Status circular dependency" }
        19 { "Status duplicate name" }
        20 { "Status invalid name" }
        21 { "Status invalid parameter" }
        22 { "Status invalid service account" }
        23 { "Status service exists" }
        24 { "Service already paused" }
        default { "Unrecognized return code $ReturnValue" }
    }
}