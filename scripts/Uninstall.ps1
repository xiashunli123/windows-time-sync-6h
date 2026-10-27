[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $PSCommandPath
    try {
        $process = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -Wait -PassThru
        exit $process.ExitCode
    } catch {
        Write-Error $_ -ErrorAction Continue
        exit 1
    }
}
$task = Get-ScheduledTask -TaskName 'TimeSync6h' -TaskPath '\' -ErrorAction SilentlyContinue
if ($task -and $task.Description -like '[[]TimeSync6h[]]*') {
    Stop-ScheduledTask -TaskName 'TimeSync6h' -TaskPath '\' -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName 'TimeSync6h' -TaskPath '\' -Confirm:$false
}
# Keep installed files and logs for inspection; removing the task stops the automation.
