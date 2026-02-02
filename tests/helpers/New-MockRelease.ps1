param(
    [Parameter(Mandatory=$true, HelpMessage="Release tag (e.g., v1.9.0)")]
    [string]$Tag,

    [Parameter(Mandatory=$true, HelpMessage="Hashtable of apps with versions")]
    [hashtable]$Apps,

    [Parameter(Mandatory=$false, HelpMessage="Previous tag for delta generation")]
    [string]$DeltaFromTag,

    [Parameter(Mandatory=$true, HelpMessage="Output path for mock releases")]
    [string]$OutputPath
)

<#
.SYNOPSIS
    Creates a mock GitHub release structure for testing.

.DESCRIPTION
    Generates filesystem-based mock of GitHub release including:
    - release.json (GitHub API response)
    - versions.txt (scoop list output)
    - toolset.zip (minimal mock)
    - delta-from-*.zip (if DeltaFromTag specified)
#>

Set-StrictMode -Version Latest

# Create release directory
$releasePath = Join-Path $OutputPath $Tag
New-Item -ItemType Directory -Path $releasePath -Force | Out-Null

Write-Host "Creating mock release: $Tag" -ForegroundColor Cyan

# Create release.json (GitHub API response simulation)
$assets = @(
    @{
        name = "toolset.zip"
        browser_download_url = "file://$releasePath/toolset.zip"
        size = 1048576
    },
    @{
        name = "versions.txt"
        browser_download_url = "file://$releasePath/versions.txt"
        size = 1024
    }
)

if ($DeltaFromTag) {
    $assets += @{
        name = "delta-from-$DeltaFromTag.zip"
        browser_download_url = "file://$releasePath/delta-from-$DeltaFromTag.zip"
        size = 524288
    }
}

$releaseData = @{
    tag_name = $Tag
    name = "Release $Tag"
    draft = $false
    prerelease = $false
    created_at = (Get-Date -Format "o")
    assets = $assets
}

$releaseData | ConvertTo-Json -Depth 10 | Out-File "$releasePath\release.json" -Encoding utf8
Write-Host "  Created release.json" -ForegroundColor Gray

# Create versions.txt (scoop list format)
$versionsContent = "Name Version`n---- -------`n"
$versionsContent += ($Apps.GetEnumerator() | ForEach-Object { "$($_.Key) $($_.Value)" }) -join "`n"
$versionsContent | Out-File "$releasePath\versions.txt" -Encoding utf8
Write-Host "  Created versions.txt" -ForegroundColor Gray

# Create mock toolset.zip (minimal structure with actual app directories)
$buildPath = Join-Path $env:TEMP "mock-build-$Tag-$PID"
try {
    New-Item -ItemType Directory "$buildPath\scoop\apps" -Force | Out-Null
    New-Item -ItemType Directory "$buildPath\scoop\shims" -Force | Out-Null

    foreach ($app in $Apps.GetEnumerator()) {
        $appPath = Join-Path $buildPath "scoop\apps\$($app.Key)\$($app.Value)"
        New-Item -ItemType Directory $appPath -Force | Out-Null

        # Create a VERSION file for the app
        "Mock $($app.Key) v$($app.Value)" | Out-File "$appPath\VERSION.txt"

        # Create current junction simulation (just a marker file)
        $currentPath = Join-Path (Split-Path $appPath -Parent) "current"
        New-Item -ItemType Directory $currentPath -Force | Out-Null
        "Link to $($app.Value)" | Out-File "$currentPath\VERSION.txt"
    }

    # Add root files
    "$Tag" | Out-File "$buildPath\VERSION.txt"
    $versionsContent | Out-File "$buildPath\versions.txt"

    # Compress to toolset.zip
    $items = Get-ChildItem $buildPath
    Compress-Archive -Path $items.FullName -DestinationPath "$releasePath\toolset.zip" -Force
    Write-Host "  Created toolset.zip" -ForegroundColor Gray

    # Create delta package if requested
    if ($DeltaFromTag) {
        $deltaPath = Join-Path $env:TEMP "mock-delta-$Tag-$PID"
        New-Item -ItemType Directory "$deltaPath\scoop\apps" -Force | Out-Null

        # For simplicity, include all apps in delta (in real scenario, only changed ones)
        foreach ($app in $Apps.GetEnumerator()) {
            $appPath = Join-Path $buildPath "scoop\apps\$($app.Key)"
            $deltaAppPath = Join-Path $deltaPath "scoop\apps"
            Copy-Item -Recurse $appPath $deltaAppPath -Force
        }

        # Create manifest
        $manifest = @{
            from_version = $DeltaFromTag
            to_version = $Tag
            changed_apps = @($Apps.Keys)
            app_count = $Apps.Count
            type = "delta"
            generated_at = (Get-Date -Format "o")
        }
        $manifest | ConvertTo-Json | Out-File "$deltaPath\DELTA-MANIFEST.json" -Encoding utf8

        # Copy metadata
        Copy-Item "$buildPath\VERSION.txt" "$deltaPath\" -Force
        Copy-Item "$buildPath\versions.txt" "$deltaPath\" -Force

        # Compress delta
        $deltaItems = Get-ChildItem $deltaPath
        Compress-Archive -Path $deltaItems.FullName -DestinationPath "$releasePath\delta-from-$DeltaFromTag.zip" -Force
        Write-Host "  Created delta-from-$DeltaFromTag.zip" -ForegroundColor Gray

        Remove-Item $deltaPath -Recurse -Force
    }

} finally {
    if (Test-Path $buildPath) {
        Remove-Item $buildPath -Recurse -Force
    }
}

Write-Host "Mock release created successfully: $Tag" -ForegroundColor Green

return @{
    Tag = $Tag
    Path = $releasePath
    Apps = $Apps
}
