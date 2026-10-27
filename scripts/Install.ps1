[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$packageRoot = $PSScriptRoot
$taskName = 'TimeSync6h'
$installRoot = Join-Path $env:ProgramData 'TimeSync6h'
$installResult = Join-Path $packageRoot 'install-result.json'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $PSCommandPath
    try {
        $process = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -Wait -PassThru
        if ($process.ExitCode -ne 0) { throw 'Installation failed. Read scripts/install-result.json for details.' }
        Write-Host 'Installed. Check the local last-result.json file to verify synchronization.'
        exit 0
    } catch {
        Write-Error $_ -ErrorAction Continue
        exit 1
    }
}

try {
    foreach ($sourceFile in @('Sync-Time.ps1', 'Uninstall.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $packageRoot $sourceFile) -PathType Leaf)) { throw ('Missing package file: ' + $sourceFile) }
    }
    $existingTask = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction SilentlyContinue
    if ($existingTask -and $existingTask.Description -notlike '[[]TimeSync6h[]]*') {
        throw 'A different scheduled task already uses this name; nothing was replaced.'
    }
    if ((Test-Path -LiteralPath $installRoot) -and -not (Test-Path -LiteralPath (Join-Path $installRoot 'installed-by-timesync6h.txt'))) {
        throw 'The installation directory already exists without this program marker; nothing was replaced.'
    }
    if (Test-Path -LiteralPath $installRoot) {
        $existingItems = @((Get-Item -LiteralPath $installRoot -Force)) + @(Get-ChildItem -LiteralPath $installRoot -Force)
        foreach ($item in $existingItems) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Installation paths must not contain reparse points.' }
        }
    }
    New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
    # The SYSTEM task executes only from an administrator-controlled directory.
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    $inheritance = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    $propagation = [Security.AccessControl.PropagationFlags]::None
    $allow = [Security.AccessControl.AccessControlType]::Allow
    foreach ($sid in @('S-1-5-18', 'S-1-5-32-544')) {
        $rule = New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)), 'FullControl', $inheritance, $propagation, $allow)
        $acl.AddAccessRule($rule)
    }
    $readRule = New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-545')), 'ReadAndExecute', $inheritance, $propagation, $allow)
    $acl.AddAccessRule($readRule)
    $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
    Set-Acl -LiteralPath $installRoot -AclObject $acl
    Copy-Item -LiteralPath (Join-Path $packageRoot 'Sync-Time.ps1') -Destination (Join-Path $installRoot 'Sync-Time.ps1') -Force
    Copy-Item -LiteralPath (Join-Path $packageRoot 'Uninstall.ps1') -Destination (Join-Path $installRoot 'Uninstall.ps1') -Force
    Set-Content -LiteralPath (Join-Path $installRoot 'installed-by-timesync6h.txt') -Value 'TimeSync6h v1 - Windows Time scheduled synchronization' -Encoding UTF8
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $actionArgs = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $installRoot 'Sync-Time.ps1')
    $action = New-ScheduledTaskAction -Execute $powershell -Argument $actionArgs -WorkingDirectory $installRoot
    $triggers = @('00:05', '06:05', '12:05', '18:05') | ForEach-Object { New-ScheduledTaskTrigger -Daily -At $_ }
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -RestartCount 2 -RestartInterval (New-TimeSpan -Minutes 5)
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $taskName -TaskPath '\' -Description '[TimeSync6h] Synchronize Windows time every six hours; retry failures and log results.' -Action $action -Trigger $triggers -Settings $settings -Principal $principal -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName -TaskPath '\'
    $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName -TaskPath '\'
    [ordered]@{ Success = $true; Task = $taskName; InstallRoot = $installRoot; Times = @('00:05','06:05','12:05','18:05'); NextRunTime = $taskInfo.NextRunTime.ToString('o'); InstalledAt = (Get-Date).ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath $installResult -Encoding UTF8
} catch {
    [ordered]@{ Success = $false; Error = $_.Exception.Message; RecordedAt = (Get-Date).ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath $installResult -Encoding UTF8
    exit 1
}
