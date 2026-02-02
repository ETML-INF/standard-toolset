param(
    [Parameter(Mandatory=$true, HelpMessage="Version tag (e.g., v1.9.0)")]
    [string]$Version,

    [Parameter(Mandatory=$true, HelpMessage="Hashtable of apps with versions")]
    [hashtable]$Apps,

    [Parameter(Mandatory=$false, HelpMessage="Output path (default: temp directory)")]
    [string]$OutputPath
)

<#
.SYNOPSIS
    Creates a mock toolset installation for testing.

.DESCRIPTION
    Generates a minimal toolset installation structure that mimics
    a real installation without requiring activation.
#>

Set-StrictMode -Version Latest

# Create installation path if not specified
if (-not $OutputPath) {
    $OutputPath = Join-Path $env:TEMP "mock-install-$Version-$PID"
}

Write-Host "Creating mock installation: $Version at $OutputPath" -ForegroundColor Cyan

# Create directory structure
New-Item -ItemType Directory "$OutputPath\scoop\apps" -Force | Out-Null
New-Item -ItemType Directory "$OutputPath\scoop\shims" -Force | Out-Null
New-Item -ItemType Directory "$OutputPath\scoop\persist" -Force | Out-Null

# Create VERSION.txt
"$Version" | Out-File "$OutputPath\VERSION.txt" -Encoding utf8
Write-Host "  Created VERSION.txt" -ForegroundColor Gray

# Create versions.txt
$versionsContent = "Name Version`n---- -------`n"
$versionsContent += ($Apps.GetEnumerator() | ForEach-Object { "$($_.Key) $($_.Value)" }) -join "`n"
$versionsContent | Out-File "$OutputPath\versions.txt" -Encoding utf8
Write-Host "  Created versions.txt" -ForegroundColor Gray

# Create mock app installations
foreach ($app in $Apps.GetEnumerator()) {
    $appName = $app.Key
    $appVersion = $app.Value

    # Create version-specific directory
    $appVersionPath = Join-Path $OutputPath "scoop\apps\$appName\$appVersion"
    New-Item -ItemType Directory $appVersionPath -Force | Out-Null

    # Create some mock files
    "Mock $appName v$appVersion" | Out-File "$appVersionPath\VERSION.txt"
    "#!/bin/sh`necho 'Mock $appName'" | Out-File "$appVersionPath\$appName.sh"

    # Create 'current' directory (simulating junction)
    $currentPath = Join-Path $OutputPath "scoop\apps\$appName\current"
    New-Item -ItemType Directory $currentPath -Force | Out-Null
    "Link to $appVersion" | Out-File "$currentPath\VERSION.txt"

    Write-Host "  Created app: $appName v$appVersion" -ForegroundColor Gray

    # Create persist directory if needed
    $persistPath = Join-Path $OutputPath "scoop\persist\$appName"
    New-Item -ItemType Directory $persistPath -Force | Out-Null
    "Persist data for $appName" | Out-File "$persistPath\config.txt"
}

# Create mock rclone (needed for update.ps1)
$rclonePath = Join-Path $OutputPath "scoop\apps\rclone\current"
New-Item -ItemType Directory $rclonePath -Force | Out-Null
"Mock rclone" | Out-File "$rclonePath\rclone.exe"

# Create mock shims
foreach ($appName in $Apps.Keys) {
    "$appName shim" | Out-File "$OutputPath\scoop\shims\$appName.exe"
}

Write-Host "Mock installation created successfully!" -ForegroundColor Green

return @{
    Version = $Version
    Path = $OutputPath
    Apps = $Apps
}
