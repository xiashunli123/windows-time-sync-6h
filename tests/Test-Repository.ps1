[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$problems = New-Object 'System.Collections.Generic.List[string]'
$files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })
foreach ($file in $files) {
    if ($file.Extension -eq '.ps1') {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
        foreach ($parseError in $parseErrors) { $problems.Add($file.Name + ': ' + $parseError.Message) }
    }
    if ($file.Name -match '^(install-result|last-result|uninstall-result|auth|setup_error|setup_marker)\.json$' -or $file.Extension -in @('.log','.sqlite','.db','.png','.jpg','.jpeg','.webp','.zip')) {
        $problems.Add('Local runtime artifact is present: ' + $file.Name)
        continue
    }
    $content = [IO.File]::ReadAllText($file.FullName)
    # These are generic credential and identifier patterns, not a complete privacy audit.
    foreach ($pattern in @('gh[pousr]_[A-Za-z0-9]{20,}', 'github_pat_[A-Za-z0-9_]{20,}', 'sk-[A-Za-z0-9_-]{20,}', 'S-1-5-21-\d+-\d+-\d+-\d+', 'g-p-[a-f0-9]{20,}')) {
        if ($content -match $pattern) { $problems.Add('Potential secret or machine identifier in: ' + $file.Name) }
    }
}
if ($problems.Count -gt 0) {
    $problems | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    exit 1
}
Write-Output ('Validated {0} files. No administrative operations were performed.' -f $files.Count)
