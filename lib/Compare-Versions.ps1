param(
    [Parameter(Mandatory=$true, HelpMessage="Path to previous versions.txt file")]
    [string]$PreviousVersionsFile,

    [Parameter(Mandatory=$true, HelpMessage="Path to current versions.txt file")]
    [string]$CurrentVersionsFile
)

<#
.SYNOPSIS
    Compares two versions.txt files to identify changes.

.DESCRIPTION
    Parses scoop list output format and identifies:
    - New apps (in current but not in previous)
    - Updated apps (different versions)
    - Removed apps (in previous but not in current)

.OUTPUTS
    Returns a hashtable with:
    - NewApps: array of app names
    - UpdatedApps: array of hashtables {Name, OldVersion, NewVersion}
    - RemovedApps: array of app names
    - UnchangedApps: array of app names
#>

Set-StrictMode -Version Latest

function Parse-VersionsFile {
    param([string]$FilePath)

    $apps = @{}

    if (!(Test-Path $FilePath)) {
        Write-Warning "Versions file not found: $FilePath"
        return $apps
    }

    $content = Get-Content $FilePath | Out-String
    $content -split "`n" | ForEach-Object {
        $line = $_.Trim()
        # Match: AppName Version (ignoring header/footer lines)
        if ($line -match '^\s*(\S+)\s+(\S+)\s*$') {
            $appName = $matches[1]
            $version = $matches[2]

            # Skip header lines
            if ($appName -ne "Name" -and $appName -ne "---") {
                $apps[$appName] = $version
            }
        }
    }

    return $apps
}

# Parse both files
$prevApps = Parse-VersionsFile -FilePath $PreviousVersionsFile
$currApps = Parse-VersionsFile -FilePath $CurrentVersionsFile

# Initialize result arrays
$newApps = @()
$updatedApps = @()
$removedApps = @()
$unchangedApps = @()

# Find new and updated apps
foreach ($appName in $currApps.Keys) {
    if (-not $prevApps.ContainsKey($appName)) {
        # New app
        $newApps += $appName
    } elseif ($prevApps[$appName] -ne $currApps[$appName]) {
        # Updated app
        $updatedApps += @{
            Name = $appName
            OldVersion = $prevApps[$appName]
            NewVersion = $currApps[$appName]
        }
    } else {
        # Unchanged
        $unchangedApps += $appName
    }
}

# Find removed apps
foreach ($appName in $prevApps.Keys) {
    if (-not $currApps.ContainsKey($appName)) {
        $removedApps += $appName
    }
}

# Return results
$result = @{
    NewApps = $newApps
    UpdatedApps = $updatedApps
    RemovedApps = $removedApps
    UnchangedApps = $unchangedApps
    TotalChanges = $newApps.Count + $updatedApps.Count + $removedApps.Count
}

return $result
