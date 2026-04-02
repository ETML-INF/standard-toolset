<#
.SYNOPSIS
    Runs all local checks before committing or pushing.

.DESCRIPTION
    Single entry point for pre-commit/pre-push validation.  Executes in order:

      1. Static checks (PSScriptAnalyzer, ASCII-only, apps.json schema)
         -- via tests\Test-StaticChecks.ps1, fails fast before touching Docker.
      2. Every Run-*.ps1 found in the tests\ directory, sorted alphabetically.
         Static checks are skipped inside those runners (already done in step 1).

    Build-pipeline tests (Run-BuildTests.ps1) require a separately built base image;
    they are discovered automatically but will fail gracefully if the image is absent.

    Exits 0 only when every step passes.

.PARAMETER BaseImage
    Override the container base image forwarded to Run-ToolsetTests.ps1.

.PARAMETER NoCleanup
    Keep Docker test images after the run (useful for debugging).

.PARAMETER SkipStaticChecks
    Skip the initial static-checks step (PSScriptAnalyzer, ASCII, apps.json).
#>
param(
    [string]$BaseImage       = "",
    [switch]$NoCleanup,
    [switch]$SkipStaticChecks
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"
$repoRoot  = Split-Path $PSScriptRoot -Parent
$testsDir  = $PSScriptRoot
$totalFail = 0

function Invoke-Step {
    param([string]$Label, [string[]]$PwshArgs)
    Write-Host ""
    Write-Host "===== $Label =====" -ForegroundColor Cyan
    pwsh @PwshArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  FAILED: $Label" -ForegroundColor Red
        $script:totalFail++
    } else {
        Write-Host "  PASSED: $Label" -ForegroundColor Green
    }
}

# ── Step 1: static checks ────────────────────────────────────────────────
if (-not $SkipStaticChecks) {
    Invoke-Step "Static checks" @("-File", (Join-Path $testsDir "Test-StaticChecks.ps1"), "-RepoRoot", $repoRoot)
    if ($totalFail -gt 0) {
        Write-Host ""
        Write-Host "Static checks failed -- fix issues before running container tests." -ForegroundColor Red
        exit 1
    }
}

# ── Step 2+: auto-discover Run-*.ps1 ────────────────────────────────────
$runners = Get-ChildItem -Path $testsDir -Filter "Run-*.ps1" | Sort-Object Name
foreach ($runner in $runners) {
    $label = $runner.BaseName

    # Build argument list — always skip static checks (already run in step 1).
    # Forward optional parameters to runners that accept them.
    $runnerArgs = [System.Collections.Generic.List[string]]@("-File", $runner.FullName, "-SkipStaticChecks")
    if ($BaseImage -and (Select-String -Path $runner.FullName -Pattern 'BaseImage' -Quiet)) {
        $runnerArgs.AddRange([string[]]@("-BaseImage", $BaseImage))
    }
    if ($NoCleanup -and (Select-String -Path $runner.FullName -Pattern 'NoCleanup' -Quiet)) {
        $runnerArgs.Add("-NoCleanup")
    }

    Invoke-Step $label $runnerArgs
}

# ── Summary ──────────────────────────────────────────────────────────────
Write-Host ""
if ($totalFail -gt 0) {
    Write-Host "$totalFail step(s) FAILED." -ForegroundColor Red
    exit 1
}
Write-Host "All checks passed." -ForegroundColor Green
exit 0
