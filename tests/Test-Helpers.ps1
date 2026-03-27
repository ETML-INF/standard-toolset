# Shared test helpers — dot-source this file from both Invoke-ContainerTests.ps1 and Test-UpdateMode.ps1

function Assert {
    param([string]$Name, $Cond, [string]$Detail = "")
    if ($Cond) { Write-Host "  PASS: $Name" -ForegroundColor Green; $script:pass++ }
    else       { Write-Host "  FAIL: $Name $Detail" -ForegroundColor Red; $script:fail++ }
}

function Remove-TestDir {
    param([string[]]$Paths)
    foreach ($p in $Paths) {
        if (-not (Test-Path $p)) { continue }
        Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue |
            ForEach-Object { try { $_.Attributes = 'Normal' } catch {} }
        Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
    }
}
