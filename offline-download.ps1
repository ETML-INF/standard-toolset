<#
.SYNOPSIS
    Downloads a toolset release from GitHub for offline deployment.

.PARAMETER Version
    Release version without 'v' prefix (default: latest).

.PARAMETER DestinationPath
    Target folder. If omitted, the script prompts interactively.
#>
param(
    [string]$Version         = "",
    [string]$DestinationPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$repoBase = "https://github.com/ETML-INF/standard-toolset/releases"

Write-Host "+------------------------------------------+" -ForegroundColor Cyan
Write-Host "|   TOOLSET OFFLINE DOWNLOAD UTILITY       |" -ForegroundColor White
Write-Host "+------------------------------------------+" -ForegroundColor Cyan
Write-Host ""

try {
    # Fetch manifest via plain HTTP — no GitHub API token needed
    $manifestUrl = if ([string]::IsNullOrEmpty($Version)) {
        "$repoBase/latest/download/release-manifest.json"
    } else {
        "$repoBase/download/v$Version/release-manifest.json"
    }
    $manifestJson = Invoke-RestMethod $manifestUrl -ErrorAction Stop
    if ([string]::IsNullOrEmpty($Version)) { $Version = $manifestJson.version }
    Write-Host "Release: v$Version ($($manifestJson.apps.Count) apps)" -ForegroundColor Green
} catch {
    Write-Error "Failed to fetch release manifest: $_"; exit 1
}

# --- Destination selection (only when not passed as parameter) ---
if ([string]::IsNullOrEmpty($DestinationPath)) {
    $choices = [System.Collections.Generic.List[hashtable]]::new()
    if (Test-Path "L:\") {
        $choices.Add(@{ Label = "L:\toolset  (réseau partagé)"; Path = "L:\toolset" })
    } else {
        $choices.Add(@{ Label = "L:\toolset  (réseau partagé) — L: non mappé, sera créé si accessible"; Path = "L:\toolset" })
    }
    $choices.Add(@{ Label = "$PWD\toolset  (dossier courant)"; Path = "$PWD\toolset" })
    $choices.Add(@{ Label = "$env:TEMP\toolset  (temp)";       Path = "$env:TEMP\toolset" })
    $choices.Add(@{ Label = "Autre chemin…";                   Path = $null })

    Write-Host "Choisir le dossier de destination :" -ForegroundColor Cyan
    for ($i = 0; $i -lt $choices.Count; $i++) {
        Write-Host "  [$($i+1)] $($choices[$i].Label)"
    }
    Write-Host ""

    do {
        $raw = Read-Host "Choix [1]"
        if ([string]::IsNullOrEmpty($raw)) { $raw = "1" }
    } while ($raw -notmatch '^\d+$' -or [int]$raw -lt 1 -or [int]$raw -gt $choices.Count)

    $selected = $choices[[int]$raw - 1]
    if ($null -eq $selected.Path) {
        $DestinationPath = Read-Host "Entrer le chemin complet"
        if ([string]::IsNullOrEmpty($DestinationPath)) { Write-Warning "Aucun chemin saisi, abandon."; exit 1 }
    } else {
        $DestinationPath = $selected.Path
    }

    Write-Host ""
    Write-Host "Destination : $DestinationPath" -ForegroundColor Green
    Write-Host ""
}

# Create parent before child (New-Item requires parent to exist)
New-Item -ItemType Directory -Force -Path $DestinationPath | Out-Null
$verDir = "$DestinationPath\$Version"
New-Item -ItemType Directory -Force -Path $verDir | Out-Null

$manifestJson | ConvertTo-Json -Depth 5 | Set-Content "$verDir\release-manifest.json" -Encoding UTF8
$manifestJson | ConvertTo-Json -Depth 5 | Set-Content "$DestinationPath\release-manifest.json" -Encoding UTF8

foreach ($app in $manifestJson.apps) {
    $packUrl = "$repoBase/download/v$Version/$($app.pack)"
    Write-Host "  $($app.pack)..." -ForegroundColor Yellow -NoNewline
    Invoke-WebRequest $packUrl -OutFile "$verDir\$($app.pack)" -ErrorAction Stop
    Copy-Item "$verDir\$($app.pack)" "$DestinationPath\$($app.pack)" -Force
    Write-Host " done" -ForegroundColor Green
}

foreach ($scriptName in @("toolset.ps1", "setup.ps1", "gitconfig.ps1")) {
    $scriptUrl = "$repoBase/download/v$Version/$scriptName"
    try {
        Invoke-WebRequest $scriptUrl -OutFile "$verDir\$scriptName" -ErrorAction Stop
        Copy-Item "$verDir\$scriptName" "$DestinationPath\$scriptName" -Force
        Write-Host "$scriptName downloaded" -ForegroundColor Green
    } catch {
        Write-Warning "$scriptName not found in release v$Version : $_"
    }
}

Write-Host ""
Write-Host "Done. Deploy offline:" -ForegroundColor Cyan
Write-Host "  toolset.ps1 update -PackSource $DestinationPath -ManifestSource $DestinationPath\release-manifest.json -NoInteraction" -ForegroundColor White
