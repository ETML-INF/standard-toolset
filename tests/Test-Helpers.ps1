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

function New-FakeScoopStub {
    # Creates a minimal scoop.ps1 so Invoke-Activate finds it and doesn't fall
    # back to "broken install" mode.  Used by activation tests that don't need a real scoop install.
    param([string]$ScoopDir)
    New-Item -Force -ItemType Directory "$ScoopDir\apps\scoop\current\bin" | Out-Null
    Set-Content "$ScoopDir\apps\scoop\current\bin\scoop.ps1" "# fake scoop stub" -Encoding UTF8
}

function New-TestShims {
    # Creates the three scoop shim files with content rooted at OldBase so activation
    # tests can verify the path-rewrite logic in Invoke-Activate.
    # For tests that need a current-path baseline (no rewrite expected), pass the
    # scoopdir itself as OldBase.
    param([string]$ScoopDir, [string]$OldBase)
    New-Item -Force -ItemType Directory "$ScoopDir\shims" | Out-Null
    Set-Content "$ScoopDir\shims\scoop"     "${OldBase}shims\scoop"     -Encoding UTF8
    Set-Content "$ScoopDir\shims\scoop.cmd" "${OldBase}shims\scoop.cmd" -Encoding UTF8
    Set-Content "$ScoopDir\shims\scoop.ps1" "${OldBase}shims\scoop.ps1" -Encoding UTF8
}

function Install-FreshApp {
    # Installs app1 v1.0.0 into a fresh toolset directory via the standard update flow.
    # Used as the shared first step by tests that need a healthy baseline before
    # introducing corruption, special flags, or a second update run ([22]-[25]).
    param([string]$PackDir, [string]$InstallDir)
    & $script:helper -OutputDir $PackDir -Apps @(@{Name="app1"; Version="1.0.0"})
    New-Item -Force -ItemType Directory $InstallDir | Out-Null
    pwsh -File $script:toolkit update -Path $InstallDir `
        -ManifestSource "$PackDir\release-manifest.json" -PackSource $PackDir -NoInteraction
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
