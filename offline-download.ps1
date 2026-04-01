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

# Load Invoke-Download from toolset.ps1 — single source of truth, no duplication.
# Uses the PowerShell AST parser to extract the function definition without executing
# the rest of toolset.ps1 (which would trigger activation/update logic).
$toolsetPs1 = Join-Path $PSScriptRoot "toolset.ps1"
if (-not (Test-Path $toolsetPs1)) { throw "toolset.ps1 not found at $PSScriptRoot" }
$ast = [System.Management.Automation.Language.Parser]::ParseFile($toolsetPs1, [ref]$null, [ref]$null)
$fnNode = $ast.Find({
    param($n)
    $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-Download'
}, $true)
if (-not $fnNode) { throw "Invoke-Download not found in toolset.ps1" }
. ([scriptblock]::Create($fnNode.Extent.Text))

function Get-RemoteFileSize {
    param([string]$Url)
    # Uses HttpWebRequest directly: reliable redirect-following HEAD across PS 5.1 and 7+.
    # Returns -1 when the server doesn't provide Content-Length or on any error.
    try {
        $req = [System.Net.HttpWebRequest]::Create($Url)
        $req.Method = 'HEAD'
        $req.AllowAutoRedirect = $true
        $resp = $req.GetResponse()
        $size = $resp.ContentLength
        $resp.Close()
        return $size
    } catch { return -1 }
}

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
    # Local packs (L:\ or UNC path in packUrl) are private — not on GitHub.
    # Cannot be bundled here; deployer must copy them manually to $DestinationPath.
    if ($app.PSObject.Properties['packUrl'] -and $app.packUrl -and
        ($app.packUrl -match '^[A-Za-z]:\\' -or $app.packUrl -match '^\\\\')) {
        Write-Warning "$($app.pack): private local pack ($($app.packUrl)) - copy manually to $DestinationPath"
        continue
    }

    # Unchanged packs are not re-uploaded to each release — the manifest carries packUrl
    # pointing to the release where the pack was originally built.  Fall back to the
    # version-constructed URL only for packs that were actually built in this release.
    $packUrl = if ($app.PSObject.Properties['packUrl'] -and $app.packUrl) {
        $app.packUrl
    } else {
        "$repoBase/download/v$Version/$($app.pack)"
    }
    $outFile = "$verDir\$($app.pack)"
    $needsDownload = $true
    $remoteSize = -2   # sentinel: not yet fetched (-1 = fetched but unavailable)
    if ((Test-Path $outFile) -and (Get-Item $outFile).Length -gt 0) {
        $localSize  = (Get-Item $outFile).Length
        $remoteSize = Get-RemoteFileSize $packUrl
        if ($remoteSize -le 0) {
            Write-Host "  $($app.pack)... present (size unverifiable), skipping" -ForegroundColor DarkGray
            $needsDownload = $false
        } elseif ($localSize -eq $remoteSize) {
            Write-Host "  $($app.pack)... present ($([math]::Round($localSize/1MB,1)) MB, size OK), skipping" -ForegroundColor DarkGray
            $needsDownload = $false
        } else {
            Write-Warning "$($app.pack): size mismatch (local $localSize B vs remote $remoteSize B) - re-downloading"
            Remove-Item $outFile -Force
        }
    }
    if ($needsDownload) {
        # Before hitting the network, look for the same pack in sibling version dirs.
        # Pack filenames encode the app version (e.g. jq-1.7.1.zip), so a same-named file
        # in another version folder is identical content — copy it instead of downloading.
        $cached = Get-ChildItem $DestinationPath -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne $Version } |
            ForEach-Object { "$($_.FullName)\$($app.pack)" } |
            Where-Object { (Test-Path $_) -and (Get-Item $_).Length -gt 0 } |
            Select-Object -First 1
        if ($cached) {
            $cachedSize = (Get-Item $cached).Length
            if ($remoteSize -eq -2) { $remoteSize = Get-RemoteFileSize $packUrl }
            if ($remoteSize -le 0 -or $cachedSize -eq $remoteSize) {
                Write-Host "  $($app.pack)... copied from $(Split-Path (Split-Path $cached -Parent) -Leaf) ($([math]::Round($cachedSize/1MB,1)) MB)" -ForegroundColor DarkGray
                Copy-Item $cached $outFile -Force
                $needsDownload = $false
            }
        }
    }
    if ($needsDownload) {
        Write-Host "  $($app.pack)..." -ForegroundColor Yellow -NoNewline
        Invoke-Download -Url $packUrl -OutFile $outFile -Description $app.pack
        Write-Host " done" -ForegroundColor Green
    }
}

foreach ($scriptName in @("toolset.ps1", "setup.ps1")) {
    $scriptUrl = "$repoBase/download/v$Version/$scriptName"
    try {
        Write-Host "  $scriptName..." -ForegroundColor Yellow -NoNewline
        Invoke-Download -Url $scriptUrl -OutFile "$verDir\$scriptName" -Description $scriptName
        Write-Host " done" -ForegroundColor Green
        Copy-Item "$verDir\$scriptName" "$DestinationPath\$scriptName" -Force
    } catch {
        Write-Warning "$scriptName not found in release v$Version : $_"
    }
}

Write-Host ""
Write-Host "Done. Deploy offline:" -ForegroundColor Cyan
Write-Host "  toolset.ps1 update -PackSource $DestinationPath -ManifestSource $DestinationPath\release-manifest.json -NoInteraction" -ForegroundColor White
