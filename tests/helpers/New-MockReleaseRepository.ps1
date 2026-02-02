param(
    [Parameter(Mandatory=$true, HelpMessage="Array of release configurations")]
    [array]$Releases,

    [Parameter(Mandatory=$false, HelpMessage="Output path for mock repository")]
    [string]$OutputPath
)

<#
.SYNOPSIS
    Creates a complete mock GitHub release repository.

.DESCRIPTION
    Generates multiple releases with proper delta chains for testing.

.EXAMPLE
    $repo = New-MockReleaseRepository -Releases @(
        @{Tag = "v1.9.0"; Apps = @{git="2.40.0"; node="18.0.0"}},
        @{Tag = "v1.9.1"; Apps = @{git="2.40.0"; node="20.0.0"}; Delta = $true}
    )
#>

Set-StrictMode -Version Latest

if (-not $OutputPath) {
    $OutputPath = Join-Path $env:TEMP "mock-releases-$PID"
}

New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

Write-Host "Creating mock release repository at: $OutputPath" -ForegroundColor Cyan
Write-Host ""

# Import helper
$helperPath = Join-Path $PSScriptRoot "New-MockRelease.ps1"

# Create each release
$previousTag = $null
foreach ($release in $Releases) {
    $tag = $release.Tag
    $apps = $release.Apps
    $createDelta = $release.Delta -and $previousTag

    $deltaFromTag = if ($createDelta) { $previousTag } else { $null }

    & $helperPath -Tag $tag -Apps $apps -DeltaFromTag $deltaFromTag -OutputPath $OutputPath

    $previousTag = $tag
}

# Create 'latest' link (pointing to last release)
if ($Releases.Count -gt 0) {
    $latestTag = $Releases[-1].Tag
    $latestTag | Out-File "$OutputPath\latest" -Encoding utf8 -NoNewline
    Write-Host ""
    Write-Host "Set latest -> $latestTag" -ForegroundColor Green
}

Write-Host ""
Write-Host "Mock release repository created with $($Releases.Count) release(s)" -ForegroundColor Green

return $OutputPath
