param(
    [Parameter(Mandatory=$true, HelpMessage="Repository in format 'owner/repo'")]
    [string]$Repo,

    [Parameter(Mandatory=$false, HelpMessage="Release tag or 'latest'")]
    [string]$Tag = "latest",

    [Parameter(Mandatory=$false, HelpMessage="Specific asset name to download")]
    [string]$AssetName,

    [Parameter(Mandatory=$false, HelpMessage="Output path for downloaded asset")]
    [string]$OutputPath,

    [Parameter(Mandatory=$false, HelpMessage="Path to mock data directory (for testing)")]
    [string]$MockDataPath = $env:GITHUB_MOCK_PATH,

    [Parameter(Mandatory=$false, HelpMessage="Return all releases instead of single")]
    [switch]$ListReleases
)

<#
.SYNOPSIS
    Retrieves GitHub release information with optional filesystem mocking.

.DESCRIPTION
    Abstracts GitHub API calls to enable testing without network access.
    When MockDataPath is set, reads from filesystem instead of API.

.OUTPUTS
    Returns GitHub release object(s) or downloads asset to OutputPath
#>

Set-StrictMode -Version Latest

function Get-MockedRelease {
    param(
        [string]$MockPath,
        [string]$Tag,
        [switch]$ListAll
    )

    if ($ListAll) {
        # Return all releases
        $releases = @()
        $releaseDirs = Get-ChildItem $MockPath -Directory | Where-Object { $_.Name -match '^v\d+\.' }

        foreach ($dir in $releaseDirs) {
            $releaseJson = Join-Path $dir.FullName "release.json"
            if (Test-Path $releaseJson) {
                $release = Get-Content $releaseJson | ConvertFrom-Json
                $releases += $release
            }
        }

        # Sort by tag name (descending)
        return $releases | Sort-Object { $_.tag_name } -Descending
    }

    # Get specific release
    if ($Tag -eq "latest") {
        $latestLink = Join-Path $MockPath "latest"
        if (Test-Path $latestLink) {
            $Tag = Get-Content $latestLink -Raw | ForEach-Object Trim
        } else {
            # Find highest version
            $versions = Get-ChildItem $MockPath -Directory |
                Where-Object { $_.Name -match '^v\d+\.' } |
                Sort-Object Name -Descending |
                Select-Object -First 1

            if ($versions) {
                $Tag = $versions.Name
            } else {
                throw "No releases found in mock data path"
            }
        }
    }

    $releasePath = Join-Path $MockPath $Tag
    $releaseJson = Join-Path $releasePath "release.json"

    if (Test-Path $releaseJson) {
        return Get-Content $releaseJson | ConvertFrom-Json
    }

    throw "Release not found in mock data: $Tag"
}

# Main logic
if ($MockDataPath -and (Test-Path $MockDataPath)) {
    # MOCK MODE - Read from filesystem
    Write-Verbose "Using mock GitHub data from: $MockDataPath"

    if ($ListReleases) {
        $releases = Get-MockedRelease -MockPath $MockDataPath -ListAll
        return $releases
    }

    $release = Get-MockedRelease -MockPath $MockDataPath -Tag $Tag

    # Download asset if requested
    if ($AssetName) {
        if (-not $OutputPath) {
            throw "OutputPath is required when downloading an asset"
        }

        $releasePath = Join-Path $MockDataPath $release.tag_name
        $assetPath = Join-Path $releasePath $AssetName

        if (Test-Path $assetPath) {
            Write-Verbose "Copying mock asset: $assetPath -> $OutputPath"
            Copy-Item $assetPath $OutputPath -Force
        } else {
            throw "Asset not found in mock data: $AssetName"
        }
    }

    return $release
} else {
    # REAL MODE - GitHub API
    Write-Verbose "Fetching from GitHub API: $Repo"

    $apiBase = "https://api.github.com/repos/$Repo"

    if ($ListReleases) {
        $apiUrl = "$apiBase/releases?per_page=20"
        $releases = Invoke-RestMethod -Uri $apiUrl -Method Get
        return $releases
    }

    # Get specific release
    if ($Tag -eq "latest") {
        $apiUrl = "$apiBase/releases/latest"
    } else {
        $apiUrl = "$apiBase/releases/tags/$Tag"
    }

    try {
        $release = Invoke-RestMethod -Uri $apiUrl -Method Get

        # Download asset if requested
        if ($AssetName) {
            if (-not $OutputPath) {
                throw "OutputPath is required when downloading an asset"
            }

            $asset = $release.assets | Where-Object { $_.name -eq $AssetName } | Select-Object -First 1

            if ($asset) {
                Write-Verbose "Downloading asset: $($asset.browser_download_url)"
                Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $OutputPath
            } else {
                throw "Asset not found: $AssetName"
            }
        }

        return $release
    } catch {
        Write-Error "Failed to fetch release from GitHub: $_"
        throw
    }
}
