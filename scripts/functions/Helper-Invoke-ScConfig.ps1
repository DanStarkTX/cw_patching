function Invoke-ScConfig {
    param (
        [Parameter(Mandatory = $true)]
        [string] $ServiceName,

        [Parameter(Mandatory = $true)]
        [string] $Arguments
    )

    $output = & sc.exe config $ServiceName $Arguments 2>&1
    $exitCode = $LASTEXITCODE

    $stdout = ($output | Where-Object { $_ -is [string] }) -join "`n"
    $stderr = ($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { $_.Exception.Message }) -join "`n"

    [pscustomobject]@{
        ServiceName = $ServiceName
        Arguments   = $Arguments
        ExitCode    = $exitCode
        StdOut      = $stdout.Trim()
        StdErr      = $stderr.Trim()
        Success     = ($exitCode -eq 0)
    }
}
