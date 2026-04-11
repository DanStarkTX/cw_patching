function Get-RandomLauncherWarning {
    param (
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $defaultMessage = "The number cannot be completed as dialed, please try again."

    try {
        if (-not (Test-Path $Path)) {
            return $defaultMessage
        }

        $warningConfig = Get-Content -Path $Path -Raw | ConvertFrom-Json
        $messages = @($warningConfig.messages)

        if ($messages.Count -eq 0) {
            return $defaultMessage
        }

        return Get-Random -InputObject $messages
    } catch {
        return $defaultMessage
    }
}
