function Format-AccountName {
    param (
        [string] $AccountName
    )

    if ([string]::IsNullOrWhiteSpace($AccountName)) {
        return "Unknown"
    }

    return $AccountName -replace '\\\\', '\'
}
