param(
    [Parameter(Mandatory=$true, HelpMessage="Path to build directory")]
    [string]$BuildPath,

    [Parameter(Mandatory=$true, HelpMessage="Current release tag")]
    [string]$CurrentTag,

    [Parameter(Mandatory=$true, HelpMessage="Previous release tag")]
    [string]$PreviousTag,

    [Parameter(Mandatory=$true, HelpMessage="Path to previous versions.txt")]
    [string]$PreviousVersionsFile,

    [Parameter(Mandatory=$false, HelpMessage="Output directory for delta package")]
    [string]$OutputPath = "delta",

    [Parameter(Mandatory=$false)]
    [bool]$ConsoleOutput = $true
)

<#
.SYNOPSIS
    Generates a delta package containing only changed applications.

.DESCRIPTION
    Compares current build with previous release and creates a minimal
    delta package containing only new/updated applications.

.OUTPUTS
    Returns a hashtable with:
    - Created: bool (whether delta was created)
    - DeltaFileName: string
    - ChangedApps: array
    - RemovedApps: array
    - Metrics: hashtable (sizes, savings)
#>

Set-StrictMode -Version Latest

# Import dependencies
. "$PSScriptRoot\Compare-Versions.ps1"

try {
    # Verify build path exists
    if (!(Test-Path $BuildPath)) {
        throw "Build path not found: $BuildPath"
    }

    # Get current versions
    $currentVersionsFile = Join-Path $BuildPath "versions.txt"
    if (!(Test-Path $currentVersionsFile)) {
        # Try parent directory (for build/versions.txt case)
        $currentVersionsFile = Join-Path (Split-Path $BuildPath -Parent) "versions.txt"
        if (!(Test-Path $currentVersionsFile)) {
            throw "Current versions.txt not found"
        }
    }

    # Compare versions
    Write-Host "Analyzing package changes..." -ForegroundColor Yellow
    $comparison = & "$PSScriptRoot\Compare-Versions.ps1" `
        -PreviousVersionsFile $PreviousVersionsFile `
        -CurrentVersionsFile $currentVersionsFile

    # Collect all changed apps (new + updated)
    $changedApps = @()
    $changedApps += $comparison.NewApps
    $changedApps += $comparison.UpdatedApps | ForEach-Object { $_.Name }

    # Display changes
    foreach ($app in $comparison.NewApps) {
        Write-Host "  + New: $app" -ForegroundColor Green
    }
    foreach ($update in $comparison.UpdatedApps) {
        Write-Host "  ↑ Updated: $($update.Name) ($($update.OldVersion) -> $($update.NewVersion))" -ForegroundColor Yellow
    }
    foreach ($app in $comparison.RemovedApps) {
        Write-Host "  - Removed: $app" -ForegroundColor Red
    }

    # Check if there are changes worth creating delta for
    if ($changedApps.Count -eq 0) {
        Write-Host "No application changes detected, skipping delta generation" -ForegroundColor Yellow
        return @{
            Created = $false
            Reason = "No changes detected"
            ChangedApps = @()
            RemovedApps = $comparison.RemovedApps
        }
    }

    Write-Host ""
    Write-Host "Creating delta package with $($changedApps.Count) changed app(s)..." -ForegroundColor Cyan

    # Create delta directory structure
    $deltaAppsPath = Join-Path $OutputPath "scoop\apps"
    New-Item -ItemType Directory -Path $deltaAppsPath -Force | Out-Null

    # Copy ONLY changed apps from build directory
    $copiedApps = @()
    foreach ($appName in $changedApps) {
        $appPath = Join-Path $BuildPath "scoop\apps\$appName"
        if (Test-Path $appPath) {
            Write-Host "  Copying $appName..." -ForegroundColor Gray
            Copy-Item -Recurse -Force $appPath $deltaAppsPath
            $copiedApps += $appName
        } else {
            Write-Warning "  App path not found: $appPath"
        }
    }

    # Copy necessary scoop infrastructure (shims for new/updated apps)
    Write-Host "Copying scoop shims..." -ForegroundColor Gray
    $shimsPath = Join-Path $BuildPath "scoop\shims"
    if (Test-Path $shimsPath) {
        $deltaShimsPath = Join-Path $OutputPath "scoop\shims"
        Copy-Item -Recurse -Force $shimsPath $deltaShimsPath
    }

    # Copy metadata and scripts
    $filesToCopy = @(
        "VERSION.txt",
        "versions.txt",
        "install.ps1",
        "activate.ps1",
        "README.md",
        "LICENSE"
    )

    foreach ($file in $filesToCopy) {
        $sourcePath = Join-Path $BuildPath $file
        if (Test-Path $sourcePath) {
            Copy-Item $sourcePath $OutputPath -Force -ErrorAction SilentlyContinue
        }
    }

    # Create delta manifest
    Write-Host "Generating DELTA-MANIFEST.json..." -ForegroundColor Gray
    $manifest = @{
        from_version = $PreviousTag
        to_version = $CurrentTag
        changed_apps = $copiedApps
        removed_apps = $comparison.RemovedApps
        app_count = $copiedApps.Count
        type = "delta"
        generated_at = (Get-Date -Format "o")
    }

    $manifestPath = Join-Path $OutputPath "DELTA-MANIFEST.json"
    $manifest | ConvertTo-Json | Out-File $manifestPath -Encoding utf8

    # Compress delta
    $deltaFileName = "delta-from-$PreviousTag.zip"
    Write-Host "Compressing delta archive: $deltaFileName" -ForegroundColor Cyan

    # Get all items in delta directory
    $deltaItems = Get-ChildItem $OutputPath
    if ($deltaItems) {
        Compress-Archive -Path $deltaItems.FullName -DestinationPath $deltaFileName -Force
    } else {
        throw "Delta directory is empty, cannot create archive"
    }

    # Calculate metrics
    $metrics = @{
        DeltaSize = 0
        FullSize = 0
        Savings = 0
        SavingsPercent = 0
    }

    if (Test-Path $deltaFileName) {
        $metrics.DeltaSize = (Get-Item $deltaFileName).Length / 1MB

        # Try to find full package for comparison
        $fullPackagePath = Join-Path (Split-Path $BuildPath -Parent) "toolset.zip"
        if (Test-Path $fullPackagePath) {
            $metrics.FullSize = (Get-Item $fullPackagePath).Length / 1MB
            $metrics.Savings = $metrics.FullSize - $metrics.DeltaSize
            if ($metrics.FullSize -gt 0) {
                $metrics.SavingsPercent = [math]::Round(($metrics.Savings / $metrics.FullSize) * 100, 1)
            }

            Write-Host ""
            Write-Host "  Delta package created successfully!" -ForegroundColor Green
            Write-Host "  Delta size: $([math]::Round($metrics.DeltaSize, 1)) MB" -ForegroundColor Cyan
            Write-Host "  Full size: $([math]::Round($metrics.FullSize, 1)) MB" -ForegroundColor Cyan
            Write-Host "  Bandwidth savings: $($metrics.SavingsPercent)%" -ForegroundColor Green
        } else {
            Write-Host ""
            Write-Host "  Delta package created successfully!" -ForegroundColor Green
            Write-Host "  Delta size: $([math]::Round($metrics.DeltaSize, 1)) MB" -ForegroundColor Cyan
        }
    }

    # Return result
    return @{
        Created = $true
        DeltaFileName = $deltaFileName
        ChangedApps = $copiedApps
        RemovedApps = $comparison.RemovedApps
        Metrics = $metrics
    }

} catch {
    Write-Error "Failed to generate delta package: $_"
    throw
}
