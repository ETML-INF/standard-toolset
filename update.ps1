param(
    [Parameter(Mandatory=$false, HelpMessage="Path to installed toolset")]
    [string]$InstallPath = "C:\inf-toolset",
    [Parameter(Mandatory=$false, HelpMessage="Force full download instead of delta")]
    [switch]$ForceFull,
    [Parameter(Mandatory=$false, HelpMessage="Target version to update to (default: latest)")]
    [string]$TargetVersion = "latest",
    [Parameter(Mandatory=$false, HelpMessage="Maximum number of deltas to apply before falling back to full")]
    [int]$MaxDeltas = 3,
    [Parameter(Mandatory=$false)]
    [bool]$ConsoleOutput = $true
)

<#
.SYNOPSIS
    Updates an existing toolset installation using delta packages.

.DESCRIPTION
    Detects the current version and downloads only changed applications via delta packages.
    Falls back to full download if delta chain is unavailable or too long.

.PARAMETER InstallPath
    Path to the installed toolset directory (default: C:\inf-toolset)

.PARAMETER ForceFull
    Skip delta updates and download the full toolset package

.PARAMETER TargetVersion
    Specific version to update to (default: latest)

.PARAMETER MaxDeltas
    Maximum number of delta packages to chain before falling back to full download (default: 3)
#>

Set-StrictMode -Version Latest

# Start transcript for logging
if (-not $ConsoleOutput) {
    $logFile = "$PSScriptRoot\update-$PID.log"
    Start-Transcript -Path $logFile -Append -Force
}

try {
    # Display header
    Write-Host "+--------------------------------+" -ForegroundColor Cyan
    Write-Host "|" -ForegroundColor Cyan -NoNewline
    Write-Host "   TOOLSET UPDATE UTILITY       " -ForegroundColor White -NoNewline
    Write-Host "|" -ForegroundColor Cyan
    Write-Host "+--------------------------------+" -ForegroundColor Cyan
    Write-Host ""

    # Validate installation path exists
    if (!(Test-Path $InstallPath)) {
        Write-Error "Installation path not found: $InstallPath"
        Write-Host "Please specify the correct path with -InstallPath parameter"
        exit 1
    }

    # Detect current version
    Write-Host "Detecting current version..." -ForegroundColor Yellow
    $versionFile = Join-Path $InstallPath "VERSION.txt"

    if (Test-Path $versionFile) {
        $currentVersion = (Get-Content $versionFile -Raw).Trim()
        Write-Host "  Current version: $currentVersion" -ForegroundColor Green
    } else {
        Write-Warning "No VERSION.txt found in installation"
        Write-Host "  This appears to be a pre-v1.9.0 installation" -ForegroundColor Yellow
        $currentVersion = "unknown"

        if (!$ForceFull) {
            Write-Host ""
            Write-Warning "Delta updates require version tracking (available from v1.9.0+)"
            $response = Read-Host "Recommend full reinstall. Continue with full download? (Y/n)"
            if ($response -eq "n") {
                Write-Host "Update cancelled."
                exit 0
            }
            $ForceFull = $true
        }
    }

    # GitHub API settings
    $repoOwner = "ETML-INF"
    $repoName = "standard-toolset"
    $githubApiBase = "https://api.github.com/repos/$repoOwner/$repoName"

    # Get latest release info
    Write-Host ""
    Write-Host "Fetching release information..." -ForegroundColor Yellow

    try {
        # Use GitHub API directly
        $releasesResponse = Invoke-RestMethod -Uri "$githubApiBase/releases?per_page=20" -Method Get
        $releases = $releasesResponse | ForEach-Object {
            [PSCustomObject]@{
                tagName = $_.tag_name
                isLatest = $_.prerelease -eq $false -and $_.draft -eq $false
            }
        } | Sort-Object { $_.tagName } -Descending

        if ($TargetVersion -eq "latest") {
            $latestRelease = $releases | Where-Object { $_.isLatest -eq $true } | Select-Object -First 1
            $latestVersion = $latestRelease.tagName
        } else {
            $latestVersion = $TargetVersion
            $found = $releases | Where-Object { $_.tagName -eq $TargetVersion }
            if (!$found) {
                Write-Error "Target version $TargetVersion not found in releases"
                exit 1
            }
        }

        Write-Host "  Target version: $latestVersion" -ForegroundColor Green
    } catch {
        Write-Error "Failed to fetch release information: $_"
        exit 1
    }

    # Check if already up to date
    if ($currentVersion -eq $latestVersion) {
        Write-Host ""
        Write-Host "Already at latest version: $latestVersion" -ForegroundColor Green
        exit 0
    }

    # Determine update strategy: delta or full
    $useDelta = $false
    $deltaChain = @()

    if (!$ForceFull -and $currentVersion -ne "unknown") {
        Write-Host ""
        Write-Host "Building delta chain..." -ForegroundColor Yellow

        # Get all tags in order
        $allTags = $releases | Select-Object -ExpandProperty tagName

        $currentIndex = $allTags.IndexOf($currentVersion)
        $targetIndex = $allTags.IndexOf($latestVersion)

        if ($currentIndex -ge 0 -and $targetIndex -ge 0 -and $currentIndex -gt $targetIndex) {
            # Build list of deltas needed
            for ($i = $currentIndex - 1; $i -ge $targetIndex; $i--) {
                $fromVer = $allTags[$i + 1]
                $toVer = $allTags[$i]
                $deltaChain += @{
                    FromVersion = $fromVer
                    ToVersion = $toVer
                    FileName = "delta-from-$fromVer.zip"
                }
            }

            Write-Host "  Delta chain: $($deltaChain.Count) step(s)" -ForegroundColor Cyan
            foreach ($delta in $deltaChain) {
                Write-Host "    - $($delta.FromVersion) → $($delta.ToVersion)" -ForegroundColor Gray
            }

            if ($deltaChain.Count -le $MaxDeltas) {
                # Check if all deltas exist
                $allDeltasExist = $true
                foreach ($delta in $deltaChain) {
                    $releaseInfo = Invoke-RestMethod -Uri "$githubApiBase/releases/tags/$($delta.ToVersion)" -Method Get
                    $hasDelta = $releaseInfo.assets | Where-Object { $_.name -eq $delta.FileName }
                    if (!$hasDelta) {
                        Write-Warning "Delta $($delta.FileName) not found in release $($delta.ToVersion)"
                        $allDeltasExist = $false
                        break
                    }
                }

                if ($allDeltasExist) {
                    $useDelta = $true
                    Write-Host "  Strategy: Delta update" -ForegroundColor Green
                } else {
                    Write-Warning "Not all deltas available, falling back to full download"
                }
            } else {
                Write-Warning "Delta chain too long ($($deltaChain.Count) > $MaxDeltas), falling back to full download"
            }
        } else {
            Write-Warning "Cannot build delta chain, falling back to full download"
        }
    }

    # Execute update strategy
    Write-Host ""

    if ($useDelta) {
        # DELTA UPDATE PATH
        Write-Host "Starting delta update..." -ForegroundColor Green

        $tempBase = "$env:TEMP\toolset-update-$PID"
        New-Item -ItemType Directory -Path $tempBase -Force | Out-Null

        try {
            foreach ($delta in $deltaChain) {
                Write-Host ""
                Write-Host "Applying delta: $($delta.FromVersion) → $($delta.ToVersion)" -ForegroundColor Cyan

                # Download delta
                $deltaPath = Join-Path $tempBase $delta.FileName
                Write-Host "  Downloading $($delta.FileName)..."

                # Get download URL from release assets
                $releaseInfo = Invoke-RestMethod -Uri "$githubApiBase/releases/tags/$($delta.ToVersion)" -Method Get
                $asset = $releaseInfo.assets | Where-Object { $_.name -eq $delta.FileName } | Select-Object -First 1

                if (!$asset) {
                    throw "Asset $($delta.FileName) not found in release $($delta.ToVersion)"
                }

                # Download the asset
                Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $deltaPath

                # Extract delta
                $deltaDir = Join-Path $tempBase "delta-$($delta.ToVersion)"
                Write-Host "  Extracting delta..."
                Expand-Archive -Path $deltaPath -DestinationPath $deltaDir -Force

                # Verify delta manifest
                $manifestPath = Join-Path $deltaDir "DELTA-MANIFEST.json"
                $changedApps = @()
                $removedApps = @()
                if (Test-Path $manifestPath) {
                    $manifest = Get-Content $manifestPath | ConvertFrom-Json
                    $changedApps = $manifest.changed_apps
                    if ($manifest.PSObject.Properties.Name -contains "removed_apps") {
                        $removedApps = $manifest.removed_apps
                    }
                    Write-Host "  Changed apps: $($changedApps -join ', ')" -ForegroundColor Gray
                    if ($removedApps.Count -gt 0) {
                        Write-Host "  Removed apps: $($removedApps -join ', ')" -ForegroundColor Gray
                    }
                } else {
                    Write-Warning "Delta manifest not found, will sync all apps in delta..."
                }

                # Apply delta - add missing files without overwriting or deleting
                Write-Host "  Applying delta changes..."
                $rclone = Get-ChildItem "$InstallPath\scoop\apps\rclone\*\rclone.exe" | Select-Object -First 1

                if (!$rclone) {
                    Write-Error "rclone not found in toolset installation"
                    throw "Cannot apply delta without rclone"
                }

                # Sync app directories (add missing, don't overwrite/delete)
                $deltaAppsPath = Join-Path $deltaDir "scoop\apps"
                if (Test-Path $deltaAppsPath) {
                    Write-Host "  Updating applications..."
                    $appDirs = Get-ChildItem -Path $deltaAppsPath -Directory
                    foreach ($appDir in $appDirs) {
                        $targetAppPath = Join-Path "$InstallPath\scoop\apps" $appDir.Name
                        Write-Host "    $($appDir.Name)..." -NoNewline
                        # Use copy with --ignore-existing to add missing files only
                        & $rclone.FullName copy --ignore-existing --recursive "$($appDir.FullName)" "$targetAppPath" 2>&1 | Out-Null
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host " ✓" -ForegroundColor Green
                        } else {
                            Write-Host " ⚠" -ForegroundColor Yellow
                            Write-Warning "Failed to update $($appDir.Name), continuing..."
                        }
                    }
                }

                # Sync persist directories (add missing, don't overwrite/delete)
                $deltaPersistPath = Join-Path $deltaDir "scoop\persist"
                if (Test-Path $deltaPersistPath) {
                    Write-Host "  Updating persist data..."
                    $persistDirs = Get-ChildItem -Path $deltaPersistPath -Directory
                    foreach ($persistDir in $persistDirs) {
                        $targetPersistPath = Join-Path "$InstallPath\scoop\persist" $persistDir.Name
                        Write-Host "    persist/$($persistDir.Name)..." -NoNewline
                        & $rclone.FullName copy --ignore-existing --recursive "$($persistDir.FullName)" "$targetPersistPath" 2>&1 | Out-Null
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host " ✓" -ForegroundColor Green
                        } else {
                            Write-Host " ⚠" -ForegroundColor Yellow
                            Write-Warning "Failed to update persist for $($persistDir.Name), continuing..."
                        }
                    }
                }

                # Copy other root files (VERSION.txt, versions.txt, etc.)
                $deltaRootFiles = Get-ChildItem -Path $deltaDir -File
                foreach ($file in $deltaRootFiles) {
                    if ($file.Name -ne "DELTA-MANIFEST.json") {
                        $targetFile = Join-Path $InstallPath $file.Name
                        Copy-Item $file.FullName $targetFile -Force
                    }
                }

                # Clean up delta files
                Remove-Item $deltaPath -Force
                Remove-Item $deltaDir -Recurse -Force

                Write-Host "  ✓ Delta applied successfully" -ForegroundColor Green
            }

            # Update VERSION.txt
            $newVersionPath = Join-Path $InstallPath "VERSION.txt"
            Set-Content -Path $newVersionPath -Value $latestVersion -Force

            # Check for removed packages and offer cleanup
            Write-Host ""
            Write-Host "Checking for removed packages..." -ForegroundColor Yellow

            $newVersionsFile = Join-Path $InstallPath "versions.txt"
            if (Test-Path $newVersionsFile) {
                # Parse versions.txt to get list of expected apps
                $expectedApps = @()
                Get-Content $newVersionsFile | ForEach-Object {
                    if ($_ -match '^([^:]+):') {
                        $expectedApps += $matches[1]
                    }
                }

                # Check installed apps against expected list
                $installedAppsPath = Join-Path $InstallPath "scoop\apps"
                if (Test-Path $installedAppsPath) {
                    $installedApps = Get-ChildItem -Path $installedAppsPath -Directory | Select-Object -ExpandProperty Name
                    $orphanedApps = $installedApps | Where-Object { $_ -notin $expectedApps }

                    if ($orphanedApps.Count -gt 0) {
                        Write-Host "  Found $($orphanedApps.Count) package(s) not in versions.txt:" -ForegroundColor Yellow
                        foreach ($app in $orphanedApps) {
                            Write-Host "    - $app" -ForegroundColor Gray
                        }
                        Write-Host ""
                        $response = Read-Host "Remove these packages? (y/N)"
                        if ($response -eq "y" -or $response -eq "Y") {
                            foreach ($app in $orphanedApps) {
                                Write-Host "  Removing $app..." -NoNewline
                                try {
                                    $appPath = Join-Path $installedAppsPath $app
                                    Remove-Item $appPath -Recurse -Force -ErrorAction Stop

                                    # Also remove persist if it exists
                                    $persistPath = Join-Path "$InstallPath\scoop\persist" $app
                                    if (Test-Path $persistPath) {
                                        Remove-Item $persistPath -Recurse -Force -ErrorAction SilentlyContinue
                                    }

                                    Write-Host " ✓" -ForegroundColor Green
                                } catch {
                                    Write-Host " ✗" -ForegroundColor Red
                                    Write-Warning "Failed to remove $app: $_"
                                }
                            }
                        } else {
                            Write-Host "  Skipped cleanup"
                        }
                    } else {
                        Write-Host "  No orphaned packages found" -ForegroundColor Green
                    }
                }
            }

        } finally {
            # Cleanup temp directory
            if (Test-Path $tempBase) {
                Remove-Item $tempBase -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

    } else {
        # FULL UPDATE PATH - delegate to setup.ps1 for BITS download and installation
        Write-Host "Starting full update..." -ForegroundColor Green
        Write-Host ""

        $setupScript = Join-Path $PSScriptRoot "setup.ps1"
        if (!(Test-Path $setupScript)) {
            Write-Error "setup.ps1 not found at $setupScript"
            Write-Host "Cannot perform full update without setup.ps1"
            exit 1
        }

        Write-Host "Using setup.ps1 to download and install version $latestVersion" -ForegroundColor Cyan
        Write-Host ""

        # Delegate to setup.ps1 (it will use BITS for intelligent downloading)
        & $setupScript -Version $latestVersion -Destination (Split-Path $InstallPath -Parent) -Nointeraction $true -ConsoleOutput $ConsoleOutput
    }

    # Success message
    Write-Host ""
    Write-Host "+--------------------------------+" -ForegroundColor Green
    Write-Host "|" -ForegroundColor Green -NoNewline
    Write-Host "   UPDATE COMPLETED SUCCESSFULLY!" -ForegroundColor White -NoNewline
    Write-Host "|" -ForegroundColor Green
    Write-Host "+--------------------------------+" -ForegroundColor Green
    Write-Host ""
    Write-Host "Updated to version: $latestVersion" -ForegroundColor Green
    Write-Host ""
    Write-Host "You may need to run activate.ps1 again to update shortcuts and PATH."

} catch {
    Write-Error "Update failed: $_"
    Write-Host ""
    Write-Host "If the error persists, try running with -ForceFull flag for a complete reinstall."
    exit 1
} finally {
    if (-not $ConsoleOutput) {
        Stop-Transcript
    }
}
