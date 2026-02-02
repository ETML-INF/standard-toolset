param(
    [Parameter(Mandatory=$false, HelpMessage="Specific test file to run")]
    [string]$TestFile,

    [Parameter(Mandatory=$false, HelpMessage="Test output format")]
    [ValidateSet("Normal", "Detailed", "Diagnostic")]
    [string]$Verbosity = "Detailed",

    [Parameter(Mandatory=$false, HelpMessage="Generate test results XML")]
    [switch]$GenerateResults
)

<#
.SYNOPSIS
    Runs integration tests for the delta update mechanism.

.DESCRIPTION
    Executes Pester tests with proper configuration.
    Does not require activation or system modification.
#>

Set-StrictMode -Version Latest

# Check if Pester is installed
$pesterModule = Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge "5.0.0" }
if (-not $pesterModule) {
    Write-Host "Pester 5.0+ not found. Installing..." -ForegroundColor Yellow
    Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -SkipPublisherCheck -Scope CurrentUser
}

# Import Pester
Import-Module Pester -MinimumVersion 5.0.0

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DELTA UPDATE INTEGRATION TESTS" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Configure Pester
$config = New-PesterConfiguration

if ($TestFile) {
    $config.Run.Path = $TestFile
} else {
    $config.Run.Path = "$PSScriptRoot\integration"
}

$config.Output.Verbosity = $Verbosity
$config.Should.ErrorAction = "Continue"

if ($GenerateResults) {
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputPath = "$PSScriptRoot\..\test-results.xml"
    $config.TestResult.OutputFormat = "NUnitXml"
}

# Run tests
Write-Host "Running tests from: $($config.Run.Path)" -ForegroundColor Gray
Write-Host ""

try {
    $result = Invoke-Pester -Configuration $config

    # Display summary
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  TEST SUMMARY" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Total:   $($result.TotalCount)" -ForegroundColor Gray
    Write-Host "Passed:  $($result.PassedCount)" -ForegroundColor Green
    Write-Host "Failed:  $($result.FailedCount)" -ForegroundColor $(if ($result.FailedCount -gt 0) { "Red" } else { "Gray" })
    Write-Host "Skipped: $($result.SkippedCount)" -ForegroundColor Yellow
    Write-Host ""

    if ($GenerateResults) {
        Write-Host "Test results saved to: $($config.TestResult.OutputPath)" -ForegroundColor Cyan
    }

    # Exit with appropriate code
    if ($result.FailedCount -gt 0) {
        exit 1
    }

    exit 0
} catch {
    Write-Error "Test execution failed: $_"
    exit 1
}
