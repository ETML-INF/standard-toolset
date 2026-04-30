<#
.SYNOPSIS
    Creates fake app pack zips and release-manifest.json for testing toolset.ps1.

.PARAMETER OutputDir
    Directory where pack zips will be written.

.PARAMETER Apps
    Array of hashtables: @{ Name="appname"; Version="1.0.0" }

.PARAMETER ManifestVersion
    The toolset release version to embed in the manifest (without 'v' prefix).
#>
param(
    [Parameter(Mandatory=$true)][string]$OutputDir,
    [Parameter(Mandatory=$true)][hashtable[]]$Apps,
    [string]$ManifestVersion = "99.0.0"
)

$null = New-Item -ItemType Directory -Force -Path $OutputDir

# Counts files under $Path without following junction (reparse) points — mirrors the
# measurement used by Test-AppIntegrity (Get-FilesNoJunction) in toolset.ps1.
# Fake packs have no junctions so the result is identical to a naive count, but using
# the same method ensures test counts stay consistent with production behaviour.
function Get-FakePackFileCount {
    param([string]$Path, [string[]]$ExcludePaths = @(), [string]$RootPath = '')
    if ($RootPath -eq '') { $RootPath = $Path }
    $count = 0; $size = [long]0
    Get-ChildItem $Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            # Stop at junctions -- never follow into persist targets.
        } elseif ($_.PSIsContainer) {
            $rel = $_.FullName.Substring($RootPath.Length).TrimStart('\').TrimStart('/')
            $excluded = $false
            foreach ($ex in $ExcludePaths) {
                if ($rel -like "$ex" -or $rel -like "$ex\*" -or $rel -like "$ex/*") {
                    $excluded = $true; break
                }
            }
            if (-not $excluded) {
                $sub = Get-FakePackFileCount $_.FullName $ExcludePaths $RootPath
                $count += $sub.Count; $size += $sub.TotalSize
            }
        } else {
            $count++; $size += $_.Length
        }
    }
    return @{ Count = $count; TotalSize = $size }
}

$manifestApps = @()

foreach ($app in $Apps) {
    $name     = $app.Name
    $version  = $app.Version
    $packName = "$name-$version.zip"

    # Build temp dir: <name>\<version>\manifest.json
    # Real packs use versioned subdirectories; activation creates the current\ junction.
    $tmpDir = Join-Path $env:TEMP "fakepck-$name-$(Get-Random)"
    $verDir = Join-Path $tmpDir "$name\$version"
    $null = New-Item -ItemType Directory -Force -Path $verDir
    @{ version = $version } | ConvertTo-Json | Set-Content (Join-Path $verDir "manifest.json") -Encoding UTF8

    # ExcludePaths mirrors integrityExcludePaths in the manifest so counts are consistent.
    $excludePaths = [string[]]@(if ($app.ContainsKey('IntegrityExcludePaths')) { $app.IntegrityExcludePaths })

    # Count source files before compression (without following junctions or excluded paths)
    # so the recorded fileCount/totalSize match what Test-AppIntegrity measures.
    $m = Get-FakePackFileCount (Join-Path $tmpDir $name) $excludePaths
    $fileCount = $m.Count
    $totalSize = $m.TotalSize

    $packPath = Join-Path $OutputDir $packName
    Compress-Archive -Path (Join-Path $tmpDir $name) -DestinationPath $packPath -Force
    $zipMd5 = (Get-FileHash -Algorithm MD5 $packPath).Hash.ToLower()
    # Strip read-only attributes before removal (Compress-Archive can leave them).
    # Include $tmpDir itself -- Get-ChildItem -Recurse does not return the root.
    @(Get-Item $tmpDir) + @(Get-ChildItem $tmpDir -Recurse -Force -ErrorAction SilentlyContinue) |
        ForEach-Object { try { $_.Attributes = 'Normal' } catch {} }
    try { Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue } catch { }

    $entry = [ordered]@{ name = $name; version = $version; pack = $packName; fileCount = $fileCount; totalSize = $totalSize; zipMd5 = $zipMd5 }
    if ($excludePaths.Count -gt 0) { $entry['integrityExcludePaths'] = $excludePaths }
    $manifestApps += $entry
}

@{
    version = $ManifestVersion
    built   = (Get-Date -Format "o")
    apps    = $manifestApps
} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $OutputDir "release-manifest.json") -Encoding UTF8

Write-Host "Fake packs written to $OutputDir" -ForegroundColor Green
