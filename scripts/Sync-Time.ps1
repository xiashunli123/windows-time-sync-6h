[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$installRoot = Join-Path $env:ProgramData 'TimeSync6h'
$logPath = Join-Path $installRoot 'time-sync.log'
$statusPath = Join-Path $installRoot 'last-result.json'
$w32tmPath = Join-Path $env:SystemRoot 'System32\w32tm.exe'
$startedAt = (Get-Date).ToString('o')
$result = [ordered]@{ StartedAt = $startedAt; CompletedAt = $null; Success = $false; Attempts = 0; ExitCode = 1; Source = $null; Message = $null }

function Write-SyncLog([string]$Message) {
    Add-Content -LiteralPath $logPath -Value ('{0} {1}' -f (Get-Date).ToString('o'), $Message) -Encoding UTF8
}

try {
    if (-not (Test-Path -LiteralPath $installRoot -PathType Container)) {
        throw 'The program has not been installed. Run Install.cmd first.'
    }
    if ((Test-Path -LiteralPath $logPath) -and (Get-Item -LiteralPath $logPath).Length -gt 1MB) {
        $recentLines = @(Get-Content -LiteralPath $logPath -Tail 1000)
        Set-Content -LiteralPath $logPath -Value $recentLines -Encoding UTF8
    }
    Write-SyncLog 'Starting scheduled time synchronization.'
    $service = Get-Service -Name W32Time
    if ($service.Status -ne 'Running') {
        Start-Service -Name W32Time
        (Get-Service -Name W32Time).WaitForStatus('Running', [TimeSpan]::FromSeconds(20))
    }
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $result.Attempts = $attempt
        if ($attempt -gt 1) { Start-Sleep -Seconds 20 }
        if ($attempt -eq 2) {
            Write-SyncLog 'Retrying after restarting the Windows Time service.'
            Restart-Service -Name W32Time -ErrorAction Stop
            (Get-Service -Name W32Time).WaitForStatus('Running', [TimeSpan]::FromSeconds(20))
            Start-Sleep -Seconds 3
        }
        $nativeOutput = @(& $w32tmPath /resync /rediscover 2>&1)
        $nativeExitCode = $LASTEXITCODE
        $result.Message = ($nativeOutput | Out-String).Trim()
        Write-SyncLog ('Attempt {0}, exit {1}: {2}' -f $attempt, $nativeExitCode, ($result.Message -replace '[\r\n]+', ' | '))
        if ($nativeExitCode -eq 0) {
            $result.Success = $true
            $result.ExitCode = 0
            $result.Source = (@(& $w32tmPath /query /source 2>&1) | Out-String).Trim()
            break
        }
    }
    if (-not $result.Success) { Write-SyncLog 'All synchronization attempts failed. The scheduled task will retry later.' }
} catch {
    $result.Message = $_.Exception.Message
    try { Write-SyncLog ('ERROR: ' + $result.Message) } catch {}
} finally {
    $result.CompletedAt = (Get-Date).ToString('o')
    try { $result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $statusPath -Encoding UTF8 } catch {}
}
exit $result.ExitCode
