# Shared test helpers — dot-source this file from both Invoke-ToolsetTests.ps1 and Test-UpdateMode.ps1

# Collects names of every failed assertion so the summary can list them all at the end —
# avoids having to scroll through hundreds of lines of toolset output to find the one FAIL.
$failedAssertions = [System.Collections.Generic.List[string]]::new()

function Assert {
    param([string]$Name, $Cond, [string]$Detail = "")
    if ($Cond) {
        $script:pass++
        # PASS lines are suppressed — test-group headers (e.g. "[27] packUrl...") give enough
        # progress signal without flooding the log and burying failures.
    } else {
        Write-Host "  FAIL: $Name $Detail" -ForegroundColor Red
        $script:fail++
        $script:failedAssertions.Add($Name)
    }
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
