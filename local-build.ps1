<#
.SYNOPSIS
    Builds a local toolset release and deploys it to a local/network path.

.DESCRIPTION
    Wraps build.ps1 to produce a fully deployable release without GitHub CI/CD.
    Useful for adding or updating apps, testing changes, or deploying private apps
    that must never appear in a public GitHub release.

    By default the build runs inside a Windows Nano Server container (same image
    as CI) so the host machine's scoop installation, PATH, and registry are never
    touched.  Requires Docker Desktop in Windows containers mode and the build-base
    image (see tests/Build-BaseImage.ps1).

    Use -NoContainer to run build.ps1 directly on the host (legacy mode, not
    recommended — scoop modifies PATH, registry keys, and environment variables
    that may affect the current PowerShell session).

    Key features:
      - Version format: "local.YYYYMMDD" (or "local.YYYYMMDD.N" for multiple
        builds on the same day) — never clashes with GitHub semver releases.
      - Pack reuse: seeds the pack library from packs already present in $OutputDir
        so unchanged apps are not reinstalled or re-zipped.
      - Manifest patching: newly built packs get packUrl pointing to $OutputDir
        so toolset.ps1 clients resolve them without any GitHub involvement.
      - Output written to both $OutputDir (flat, "latest") and $OutputDir\<version>\
        (versioned subfolder for pinning).

.PARAMETER OutputDir
    Target directory.  Defaults to L:\toolset.  toolset.ps1 reads
    $OutputDir\release-manifest.json as the live manifest.

.PARAMETER Version
    Version string to embed in the manifest.  Leave empty to auto-generate
    "local.YYYYMMDD" (incrementing suffix on same-day repeats).

.PARAMETER AppJson
    App definitions file.  Defaults to apps.json next to this script.

.PARAMETER PrivateAppsPath
    Path to private-apps.json.  Defaults to L:\toolset\private-apps.json.
    When using container mode, the file is copied into the Docker build context
    so the container can read it; the actual private pack zips (localPack paths)
    are never downloaded — their L:\ paths are just recorded in the manifest.

.PARAMETER BaseImage
    Docker base image for the container build.  Defaults to the GHCR-hosted
    build-base image.  Override to use a locally built image:
      -BaseImage ghcr.io/etml-inf/standard-toolset/build-base:latest

.PARAMETER NoContainer
    Run build.ps1 directly on this machine instead of inside a container.
    Not recommended: scoop modifies PATH, registry, and env vars.

.PARAMETER NoCleanup
    Keep the Docker image after the build (useful for debugging).

.PARAMETER KeepBuildDir
    Skip cleaning build\packs before building (incremental rebuild after failure).

.PARAMETER Proxy
    HTTP/SOCKS5 proxy URL passed to scoop inside the build container (and host
    mode) so downloads succeed in restricted networks.  Supports any scheme
    that .NET 6+ / pwsh 7 accepts: http://, https://, or socks5://.
    Example: -Proxy socks5://proxyhost:1080

.EXAMPLE
    .\local-build.ps1
    # Builds inside a container, deploys to L:\toolset.

.EXAMPLE
    .\local-build.ps1 -OutputDir "\\server\share\toolset" -Version "local.test.1"
    # Deploys to a UNC path with a custom version.

.EXAMPLE
    .\local-build.ps1 -AppJson "apps-experimental.json" -OutputDir "L:\toolset-test"
    # Builds from an alternate app list.

.EXAMPLE
    .\local-build.ps1 -Proxy socks5://10.0.0.1:1080
    # Builds with a SOCKS5 proxy for scoop downloads; deploys to L:\toolset when available.

.EXAMPLE
    .\local-build.ps1 -OutputDir "C:\tmp\toolset-out"
    # Builds without L:\, deploys to a local path.
#>
param(
    [string]$OutputDir       = "L:\toolset",
    [string]$Version         = "",
    [string]$AppJson         = "",
    [string]$PrivateAppsPath = "L:\toolset\private-apps.json",
    [string]$BaseImage       = "ghcr.io/etml-inf/standard-toolset/build-base:latest",
    [string]$Proxy           = "",
    [switch]$NoContainer,
    [switch]$NoCleanup,
    [switch]$KeepBuildDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = $PSScriptRoot
if (-not $AppJson) { $AppJson = Join-Path $scriptDir "apps.json" }
$packsDir  = Join-Path $scriptDir "build\packs"

# Temp files written to repo root so they are picked up by "COPY . ." in the
# Docker image.  Named with a fixed prefix so they are excluded by .gitignore.
$seedManifestInRepo    = Join-Path $scriptDir "_local-build-seed.json"
$privateAppsInRepo     = Join-Path $scriptDir "_local-build-private.json"

# ---------------------------------------------------------------------------
# 1. Determine the local version string
# ---------------------------------------------------------------------------
function Get-LocalVersion {
    param([string]$Dir)
    $base      = "local." + (Get-Date -Format "yyyyMMdd")
    $lManifest = Join-Path $Dir "release-manifest.json"
    if (-not (Test-Path $lManifest -ErrorAction SilentlyContinue)) { return $base }
    try {
        $existing = Get-Content $lManifest -Raw | ConvertFrom-Json
        if ($existing.version -notlike "$base*") { return $base }
        $allVersions = @($existing.version)
        Get-ChildItem $Dir -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "$base*" } |
            ForEach-Object { $allVersions += $_.Name }
        $max = 1
        foreach ($v in $allVersions) {
            if ($v -match "^$([regex]::Escape($base))\.(\d+)$") {
                $n = [int]$Matches[1]; if ($n -ge $max) { $max = $n + 1 }
            } elseif ($v -eq $base -and $max -lt 2) { $max = 2 }
        }
        return "$base.$max"
    } catch { return $base }
}

if (-not $Version) {
    $null = New-Item -ItemType Directory -Force -Path $OutputDir -ErrorAction SilentlyContinue
    $Version = Get-LocalVersion $OutputDir
}
Write-Host "Local build version: $Version" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# 2. Seed manifest: reuse packs from $OutputDir so unchanged apps are skipped
#    The seed uses each pack's current URL (L:\ or GitHub) so build.ps1 can
#    recognise same-version apps and skip reinstalling them.
# ---------------------------------------------------------------------------
$lManifestPath = Join-Path $OutputDir "release-manifest.json"
$hasSeed       = $false
$seedAppNames  = @()   # remembered here; the file gets deleted after the container run

if (Test-Path $lManifestPath -ErrorAction SilentlyContinue) {
    try {
        $lManifest  = Get-Content $lManifestPath -Raw | ConvertFrom-Json
        $seedApps   = @()
        foreach ($app in $lManifest.apps) {
            $packFile = $app.pack
            # Resolve the best-available local path for this pack
            $versionedPath = Join-Path $OutputDir "$($lManifest.version)\$packFile"
            $flatPath      = Join-Path $OutputDir $packFile
            $localPackPath = if     (Test-Path $versionedPath) { $versionedPath }
                             elseif (Test-Path $flatPath)       { $flatPath }
                             else                               { $null }

            # Prefer a known local path; fall back to whatever packUrl is recorded.
            $packUrl = if ($localPackPath) { $localPackPath }
                       elseif ($app.PSObject.Properties['packUrl'] -and $app.packUrl) { $app.packUrl }
                       else { $null }

            if ($packUrl) {
                $entry = [ordered]@{ name = $app.name; version = $app.version; pack = $packFile; packUrl = $packUrl }
                if ($app.PSObject.Properties['fileCount'])             { $entry['fileCount']             = $app.fileCount }
                if ($app.PSObject.Properties['totalSize'])             { $entry['totalSize']             = $app.totalSize }
                if ($app.PSObject.Properties['integrityExcludePaths']) { $entry['integrityExcludePaths'] = $app.integrityExcludePaths }
                $seedApps += $entry
            }
        }
        if ($seedApps.Count -gt 0) {
            @{ version = $lManifest.version; apps = $seedApps } |
                ConvertTo-Json -Depth 5 | Set-Content $seedManifestInRepo -Encoding UTF8
            $hasSeed      = $true
            $seedAppNames = @($seedApps | ForEach-Object { $_.name })
            Write-Host "  Pack reuse: seeded $($seedApps.Count) entries from $lManifestPath" -ForegroundColor DarkGray
        }
    } catch {
        Write-Warning "Could not read existing manifest for pack reuse: $_"
    }
}

# ---------------------------------------------------------------------------
# 3. Private apps are NOT merged during build.
#    toolset.ps1's Merge-PrivateApps reads private-apps.json from L:\ at
#    update time, so private apps never need to be rebuilt here. The container
#    can't reach L:\ anyway, so passing them would only produce noisy warnings.
# ---------------------------------------------------------------------------
$hasPrivate = $false

# ---------------------------------------------------------------------------
# Helper: clean up temp files in repo root
# ---------------------------------------------------------------------------
function Remove-TempBuildFiles {
    foreach ($f in @($seedManifestInRepo, $privateAppsInRepo)) {
        if (Test-Path $f -ErrorAction SilentlyContinue) {
            Remove-Item $f -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
# 4a. CONTAINER MODE (default)
# ---------------------------------------------------------------------------
if (-not $NoContainer) {
    Write-Host ""
    Write-Host "Running build.ps1 in container..." -ForegroundColor Cyan

    # Docker context: same logic as Run-BuildTests.ps1 / Build-BaseImage.ps1
    $availableContexts = docker context ls --format "{{.Name}}" 2>$null
    $dockerCtx = if ($env:CI) { $null }
                 elseif ($availableContexts -contains "desktop-windows") { "desktop-windows" }
                 else {
                     Write-Warning "'desktop-windows' context not found — using current Docker context."
                     Write-Warning "Ensure Docker Desktop is in Windows containers mode."
                     $null
                 }
    $dockerArgs = if ($dockerCtx) { @("--context", $dockerCtx) } else { @() }
    Write-Host "  Docker context: $(if ($dockerCtx) { $dockerCtx } else { '(default)' })" -ForegroundColor DarkGray

    # Build the image
    $imageTag  = "toolset-local-build"
    $buildArgs = @("-f", "$scriptDir\tests\Dockerfile.local-build", "-t", $imageTag,
                   "--build-arg", "BASE_IMAGE=$BaseImage", $scriptDir)
    Write-Host "  Building image $imageTag..." -ForegroundColor DarkGray
    docker @dockerArgs build @buildArgs
    if ($LASTEXITCODE -ne 0) { Remove-TempBuildFiles; throw "docker build failed (exit $LASTEXITCODE)" }

    # Assemble the run command: build.ps1 arguments passed as docker run CMD override
    $containerName      = "local-build-$PID"
    $appJsonInContainer = "C:\toolset-repo\$(Split-Path $AppJson -Leaf)"
    $runCmd = @("run", "--name", $containerName,
                "-e", "RELEASE_VERSION=$Version")
    if ($Proxy) {
        # pwsh 7 / .NET 6+ SocketsHttpHandler natively supports socks5:// proxy URLs —
        # no extra relay needed.  HTTP_PROXY / HTTPS_PROXY are read by the runtime for
        # all HttpClient-based requests (Invoke-WebRequest, scoop downloads).
        # ALL_PROXY covers aria2 when scoop uses it as a downloader.
        $runCmd += @("-e", "HTTP_PROXY=$Proxy",  "-e", "http_proxy=$Proxy",
                     "-e", "HTTPS_PROXY=$Proxy", "-e", "https_proxy=$Proxy",
                     "-e", "ALL_PROXY=$Proxy")
        Write-Host "  Proxy: $Proxy" -ForegroundColor DarkGray
    }
    $runCmd += @($imageTag,
                 "pwsh", "-NonInteractive", "-File", "build.ps1",
                 "-appJson", $appJsonInContainer)
    if ($hasSeed)    { $runCmd += @("-PreviousManifestPath", "C:\toolset-repo\_local-build-seed.json") }
    if ($hasPrivate) { $runCmd += @("-PrivateAppsPath",      "C:\toolset-repo\_local-build-private.json") }

    try {
        docker @dockerArgs @runCmd
        if ($LASTEXITCODE -ne 0) { throw "build.ps1 inside container exited with code $LASTEXITCODE" }

        # Copy packs out of the container before it is removed
        Write-Host "  Copying packs from container..." -ForegroundColor DarkGray
        if (Test-Path $packsDir) { Remove-Item $packsDir -Recurse -Force }
        $null = New-Item -ItemType Directory -Force -Path (Split-Path $packsDir -Parent)
        docker @dockerArgs cp "${containerName}:C:\toolset-repo\build\packs" (Split-Path $packsDir -Parent)
        if ($LASTEXITCODE -ne 0) { throw "docker cp failed (exit $LASTEXITCODE)" }
    } finally {
        # Always remove the container and optionally the image
        docker @dockerArgs rm $containerName 2>$null | Out-Null
        if (-not $NoCleanup) { docker @dockerArgs rmi $imageTag 2>$null | Out-Null }
        Remove-TempBuildFiles
    }

# ---------------------------------------------------------------------------
# 4b. HOST MODE (-NoContainer)
# ---------------------------------------------------------------------------
} else {
    Write-Host ""
    Write-Host "Running build.ps1 on host (no container)..." -ForegroundColor Yellow
    Write-Warning "Host mode: scoop will modify PATH and environment variables in this session."

    if (-not $KeepBuildDir -and (Test-Path $packsDir)) { Remove-Item $packsDir -Recurse -Force }
    $null = New-Item -ItemType Directory -Force -Path $packsDir

    # Strip any existing scoop from PATH/SCOOP so the installer does not abort.
    $savedScoop       = $env:SCOOP
    $savedPath        = $env:PATH
    $savedHttpProxy   = $env:HTTP_PROXY
    $savedHttpsProxy  = $env:HTTPS_PROXY
    $savedAllProxy    = $env:ALL_PROXY
    $env:SCOOP  = $null
    $env:PATH   = ($env:PATH -split ';' |
        Where-Object { $_ -and $_ -notmatch [regex]::Escape('\scoop\shims') }) -join ';'
    if ($Proxy) {
        $env:HTTP_PROXY  = $Proxy
        $env:HTTPS_PROXY = $Proxy
        $env:http_proxy  = $Proxy
        $env:https_proxy = $Proxy
        $env:ALL_PROXY   = $Proxy
        Write-Host "  Proxy: $Proxy" -ForegroundColor DarkGray
    }

    $env:RELEASE_VERSION = $Version
    try {
        $buildArgs = [ordered]@{ appJson = $AppJson }
        if ($hasSeed)    { $buildArgs['PreviousManifestPath'] = $seedManifestInRepo }
        if ($hasPrivate) { $buildArgs['PrivateAppsPath']      = $privateAppsInRepo }
        & (Join-Path $scriptDir "build.ps1") @buildArgs
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "build.ps1 exited with code $LASTEXITCODE" }
    } finally {
        $env:RELEASE_VERSION = ""
        $env:SCOOP       = $savedScoop
        $env:PATH        = $savedPath
        $env:HTTP_PROXY  = $savedHttpProxy
        $env:HTTPS_PROXY = $savedHttpsProxy
        $env:http_proxy  = $savedHttpProxy
        $env:https_proxy = $savedHttpsProxy
        $env:ALL_PROXY   = $savedAllProxy
        Remove-TempBuildFiles
    }
}

# ---------------------------------------------------------------------------
# 5. Read the built manifest and patch packUrl for newly built packs
# ---------------------------------------------------------------------------
$builtManifestPath = Join-Path $packsDir "release-manifest.json"
if (-not (Test-Path $builtManifestPath)) {
    throw "build.ps1 did not produce $builtManifestPath"
}
$builtManifest = Get-Content $builtManifestPath -Raw | ConvertFrom-Json

$newPacks = @()
foreach ($app in $builtManifest.apps) {
    $packFile   = $app.pack
    $builtZip   = Join-Path $packsDir $packFile
    $hasPackUrl = $app.PSObject.Properties['packUrl'] -and $app.packUrl

    if (-not $hasPackUrl) {
        if (Test-Path $builtZip) {
            $newPacks += $packFile
            $app | Add-Member -NotePropertyName packUrl -NotePropertyValue (Join-Path $OutputDir $packFile) -Force
        } else {
            Write-Warning "Pack $packFile listed in manifest but not found in $packsDir — skipped"
        }
    }
}

# ---------------------------------------------------------------------------
# 5b. Check if OutputDir is reachable (L:\ may not be mapped on all machines).
#     When unreachable the build still succeeds — packs stay in build\packs\
#     and the patched manifest is written there for manual deployment later.
# ---------------------------------------------------------------------------
$outputReachable = $false
try {
    $null = New-Item -ItemType Directory -Force -Path $OutputDir -ErrorAction Stop
    $outputReachable = $true
} catch {
    Write-Warning "OutputDir '$OutputDir' is not reachable: $($_.Exception.Message)"
}

$finalManifestJson = $builtManifest | ConvertTo-Json -Depth 5

# ---------------------------------------------------------------------------
# 5a. Sanity check: warn if the build dropped apps that were in the seed.
#     A failed scoop install (e.g., SSL blocked) silently omits the app from
#     the manifest, and writing that back to OutputDir would corrupt future seeds.
# ---------------------------------------------------------------------------
if ($outputReachable -and $hasSeed -and $seedAppNames.Count -gt 0) {
    $builtNames      = @($builtManifest.apps | ForEach-Object { $_.name })
    $missingFromSeed = @($seedAppNames | Where-Object { $_ -notin $builtNames })
    if ($missingFromSeed.Count -gt 0) {
        Write-Warning ("Build is missing $($missingFromSeed.Count) app(s) that were in the seed: " +
            ($missingFromSeed -join ', '))
        Write-Warning "These apps likely failed to install (e.g., scoop SSL/firewall issue)."
        Write-Warning "Writing this manifest to $OutputDir would remove them from future builds."
        $answer = Read-Host "Overwrite $OutputDir\release-manifest.json anyway? [y/N]"
        if ($answer -notmatch '^[Yy]') {
            Write-Host "Aborted — $OutputDir not updated." -ForegroundColor Yellow
            exit 0
        }
    }
}

$copiedCount = 0

if ($outputReachable) {
    # -------------------------------------------------------------------------
    # 6. Copy newly built packs to $OutputDir (flat) and versioned subfolder
    # -------------------------------------------------------------------------
    $versionedDir = Join-Path $OutputDir $Version
    $null = New-Item -ItemType Directory -Force -Path $versionedDir

    foreach ($packFile in $newPacks) {
        $src = Join-Path $packsDir $packFile
        Copy-Item $src (Join-Path $OutputDir    $packFile) -Force
        Copy-Item $src (Join-Path $versionedDir $packFile) -Force
        $copiedCount++
        Write-Host "  Copied $packFile" -ForegroundColor DarkGray
    }

    # -------------------------------------------------------------------------
    # 7. Write patched manifest and copy toolset scripts to OutputDir
    # -------------------------------------------------------------------------
    Set-Content (Join-Path $OutputDir    "release-manifest.json") $finalManifestJson -Encoding UTF8
    Set-Content (Join-Path $versionedDir "release-manifest.json") $finalManifestJson -Encoding UTF8
    foreach ($f in @("toolset.ps1", "setup.ps1")) {
        $src = Join-Path $scriptDir $f
        if (Test-Path $src) { Copy-Item $src (Join-Path $OutputDir $f) -Force }
    }
} else {
    # OutputDir unreachable — write patched manifest to packsDir so the user
    # can copy build\packs\ to $OutputDir manually when the drive is available.
    Set-Content (Join-Path $packsDir "release-manifest.json") $finalManifestJson -Encoding UTF8
    $copiedCount = $newPacks.Count
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
$totalApps      = $builtManifest.apps.Count
$reusedApps     = $totalApps - $copiedCount
Write-Host ""
Write-Host "Local build complete: v$Version" -ForegroundColor Green
Write-Host "  $copiedCount pack(s) newly built, $reusedApps reused" -ForegroundColor Green
if ($outputReachable) {
    Write-Host "  Manifest : $(Join-Path $OutputDir 'release-manifest.json')" -ForegroundColor Green
    Write-Host "  Versioned: $versionedDir" -ForegroundColor Green
    Write-Host ""
    Write-Host "Clients run: toolset.ps1 update  (picks up v$Version from $OutputDir)" -ForegroundColor Cyan
} else {
    Write-Host "  Output   : $packsDir  (OutputDir '$OutputDir' was unreachable)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Copy $packsDir to $OutputDir when the drive is available," -ForegroundColor Yellow
    Write-Host "then clients run: toolset.ps1 update" -ForegroundColor Yellow
}
