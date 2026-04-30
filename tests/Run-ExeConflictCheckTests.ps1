<#
.SYNOPSIS
    Runs local ExeConflictCheck tests (no Docker required).
.PARAMETER SkipStaticChecks
    Accepted for compatibility with Test-All.ps1 auto-discovery; unused here.
#>
param([switch]$SkipStaticChecks)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$testScript = Join-Path $PSScriptRoot "Test-ExeConflictCheck.ps1"
pwsh -File $testScript
exit $LASTEXITCODE
