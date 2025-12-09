param(
    [Parameter(Mandatory=$false, HelpMessage="Path to installed toolset")]
    [string]$InstallPath = "C:\inf-toolset"
)

<#
.SYNOPSIS
    Detects the version of an installed toolset.

.DESCRIPTION
    Attempts to determine the version of an installed toolset by checking VERSION.txt.
    Falls back to fingerprinting via scoop list if VERSION.txt is missing (legacy installations).

.PARAMETER InstallPath
    Path to the installed toolset directory (default: C:\inf-toolset)

.OUTPUTS
    Returns a hashtable with:
    - Version: The detected version string (e.g., "v1.8.0" or "unknown")
    - Source: How the version was detected ("VERSION.txt", "fingerprint", or "unknown")
    - Confidence: "high", "medium", or "low"
#>

Set-StrictMode -Version Latest

function Get-InstalledVersion {
    param([string]$Path)

    $result = @{
        Version = "unknown"
        Source = "unknown"
        Confidence = "low"
    }

    # Check for VERSION.txt (preferred method)
    $versionFile = Join-Path $Path "VERSION.txt"
    if (Test-Path $versionFile) {
        try {
            $version = (Get-Content $versionFile -Raw).Trim()
            if (![string]::IsNullOrEmpty($version)) {
                $result.Version = $version
                $result.Source = "VERSION.txt"
                $result.Confidence = "high"
                return $result
            }
        }
        catch {
            Write-Warning "Failed to read VERSION.txt: $_"
        }
    }

    # Check for versions.txt (scoop package list from installation)
    $versionsFile = Join-Path $Path "versions.txt"
    if (Test-Path $versionsFile) {
        try {
            $content = Get-Content $versionsFile -Raw
            $result.Source = "fingerprint"
            $result.Confidence = "medium"

            # Use content hash as fingerprint to potentially match known releases
            $hash = (Get-FileHash -InputStream ([System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($content))) -Algorithm SHA256).Hash.Substring(0, 8)

            Write-Verbose "Package list fingerprint: $hash"
            # Note: Could extend this to match against known release fingerprints
            # For now, we assume it's a pre-delta version
            $result.Version = "pre-v1.9.0"
            return $result
        }
        catch {
            Write-Warning "Failed to fingerprint via versions.txt: $_"
        }
    }

    # Try to detect via scoop itself (if available)
    $scoopExe = Join-Path $Path "scoop\apps\scoop\current\bin\scoop.ps1"
    if (Test-Path $scoopExe) {
        try {
            # If scoop exists but no version files, it's a legacy installation
            $result.Version = "legacy"
            $result.Source = "scoop-detection"
            $result.Confidence = "low"
            return $result
        }
        catch {
            Write-Warning "Failed to detect via scoop: $_"
        }
    }

    # No detection method worked
    Write-Warning "Could not detect installation version at: $Path"
    return $result
}

# Main execution
if (!(Test-Path $InstallPath)) {
    Write-Error "Installation path not found: $InstallPath"
    exit 1
}

$detection = Get-InstalledVersion -Path $InstallPath

# Output results
Write-Host "Version Detection Results:" -ForegroundColor Cyan
Write-Host "  Path:       $InstallPath"
Write-Host "  Version:    $($detection.Version)" -ForegroundColor $(if ($detection.Confidence -eq "high") { "Green" } else { "Yellow" })
Write-Host "  Source:     $($detection.Source)"
Write-Host "  Confidence: $($detection.Confidence)"

if ($detection.Confidence -ne "high") {
    Write-Host ""
    Write-Warning "Low confidence version detection. Consider full reinstall for best update experience."
}

# Return the detection object for script usage
return $detection
