param(
    [Parameter(Mandatory=$false,HelpMessage="Path to json file containing app definitions")]
    [string]$appJson = "apps.json",
    [Parameter(Mandatory=$false)][bool]$ConsoleOutput = $true,
    # Override the starting URL for the pack library chain — used by tests to inject a
    # local fake manifest (file:// URI) without needing live GitHub releases.
    # In production this is left empty and the URL is derived from RELEASE_VERSION / latest.
    [Parameter(Mandatory=$false)][string]$PreviousManifestUrl = ""
)

# Start transcript for logging (parallel-safe with unique filename)
if (-not $ConsoleOutput) {
    $logFile = "$PSScriptRoot\build-$PID.log"
    Start-Transcript -Path $logFile -Append -Force
}

try {
    Set-StrictMode -Version Latest

    $buildScoopDir = "$($pwd.Path)\build\scoop"
    $env:SCOOP = $buildScoopDir
    $env:PATH  = "$buildScoopDir\shims;" + $env:PATH

    # Warn if another scoop is in PATH — it won't be used, but signals a potential conflict
    $systemScoop = Get-Command scoop -ErrorAction SilentlyContinue
    if ($systemScoop -and -not $systemScoop.Source.StartsWith($buildScoopDir)) {
        Write-Warning "System scoop detected at $($systemScoop.Source) — build uses its own isolated copy at $buildScoopDir"
    }

    if (Test-Path "$buildScoopDir\shims") {
        Write-Output "Scoop already at $buildScoopDir — skipping install"
    } else {
        Write-Output "Installing scoop to $buildScoopDir..."
        $install_file = "iscoop.ps1"
        Invoke-RestMethod get.scoop.sh -outfile "$($pwd)\$install_file"
        & ".\$install_file" -ScoopDir $buildScoopDir
        Remove-Item $install_file
    }

    # Ensure required buckets exist (idempotent — safe whether scoop is fresh or pre-installed)
    scoop bucket add extras 2>$null
    scoop bucket add etml-inf https://github.com/ETML-INF/standard-toolset-bucket 2>$null

    Write-Output "About to install apps defined in $appJson"
    $apps = Get-Content -Raw $appJson | ConvertFrom-Json

    # ── New-ZipPack: .NET-based zip helper ────────────────────────────────
    # Replaces Compress-Archive, which silently skips .git directories.
    # Excludes scoop's 'current' junction (a reparse point); it is recreated
    # by 'scoop reset *' after installation.
    function New-ZipPack {
        param([string]$AppDir, [string]$DestZip)
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $appName = Split-Path $AppDir -Leaf
        $absDir  = (Resolve-Path $AppDir).ProviderPath
        if (Test-Path -LiteralPath $DestZip) { Remove-Item -LiteralPath $DestZip -Force }
        $zip = [System.IO.Compression.ZipFile]::Open($DestZip, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            Get-ChildItem $AppDir -Recurse -File -Force |
                Where-Object { $_.FullName -notmatch '[/\\]current[/\\]' } |
                ForEach-Object {
                    $rel   = $_.FullName.Substring($absDir.Length).TrimStart('\') -replace '\\', '/'
                    $entry = $zip.CreateEntry("$appName/$rel", [System.IO.Compression.CompressionLevel]::Optimal)
                    $es = $entry.Open()
                    $fs = [System.IO.File]::OpenRead($_.FullName)
                    try { $fs.CopyTo($es) } finally { $fs.Dispose(); $es.Dispose() }
                }
        } finally { $zip.Dispose() }
    }

    # ── Pack library: walk the manifest chain via plain HTTP ──────────────
    # release-manifest.json carries a 'previousVersion' field that chains releases
    # together. We follow the chain using direct download URLs (no GitHub API token
    # needed, no rate-limit concerns). Pack download URLs are constructed the same way.
    #
    # Starting URL: when RELEASE_VERSION is set (CI context), release-please has already
    # created the new GitHub Release tag before this script runs — so "latest" now points
    # to the release being built (no assets yet) and returns 404.  We skip it by finding
    # the most recent *previous* release via "gh release list".  Locally (no RELEASE_VERSION)
    # we fall back to the plain latest URL so the script stays usable without gh auth.
    #
    # Chain: v<previousRelease>/release-manifest.json
    #          → releases/download/v<previousVersion>/release-manifest.json
    #          → ...  (up to $maxHops releases back)
    #
    # packUrl fix: a reused pack in a prior release already carries a packUrl pointing to
    # the release where it was originally built.  We must use that URL rather than
    # constructing "v<thatRelease>/<pack>" — the zip was never uploaded to every release.
    $repoBase   = "https://github.com/ETML-INF/standard-toolset/releases"
    $packLibrary = @{}      # "appName:version" → {pack, url}
    $prevVersion = $null    # version of current-latest, stored as previousVersion in new manifest
    $maxHops     = 10

    try {
        Write-Output "Building pack library from release chain..."

        # Determine start URL: skip the release being built in CI to avoid a 404
        # (release-please creates the tag before assets exist).
        # Priority: explicit -PreviousManifestUrl (tests) → gh release list (CI) → latest (local)
        $currentTag  = $env:RELEASE_VERSION   # e.g. "v2.1.0", empty outside CI
        $manifestUrl = if (-not [string]::IsNullOrEmpty($PreviousManifestUrl)) {
            $PreviousManifestUrl
        } elseif ($currentTag) {
            $prevTag = gh release list --limit 10 --json tagName 2>$null |
                ConvertFrom-Json |
                Where-Object { $_.tagName -ne $currentTag } |
                Select-Object -First 1 -ExpandProperty tagName
            if ($prevTag) { "$repoBase/download/$prevTag/release-manifest.json" } else { $null }
        } else {
            "$repoBase/latest/download/release-manifest.json"
        }

        $hop = 0
        while ($manifestUrl -and $hop -lt $maxHops) {
            try {
                $m = Invoke-RestMethod $manifestUrl -ErrorAction Stop
                if ($hop -eq 0) { $prevVersion = $m.version }  # remember before we overwrite
                foreach ($a in $m.apps) {
                    $key = "$($a.name):$($a.version)"
                    if ($packLibrary.ContainsKey($key)) { continue }  # newer release already has it
                    # Carry the authoritative download URL forward:
                    # - If this entry already has packUrl, it was reused from an older release and
                    #   was never uploaded to $m.version — use packUrl as-is.
                    # - Otherwise the pack was built for $m.version — construct the URL from that tag.
                    # fileCount/totalSize are carried forward so reused packs keep integrity
                    # metadata without needing to download the zip just to read its directory.
                    $packUrl = if ($a.PSObject.Properties['packUrl'] -and $a.packUrl) {
                        $a.packUrl
                    } else {
                        "$repoBase/download/v$($m.version)/$($a.pack)"
                    }
                    $packLibrary[$key] = @{
                        pack      = $a.pack
                        url       = $packUrl
                        fileCount = if ($a.PSObject.Properties['fileCount']) { $a.fileCount } else { $null }
                        totalSize = if ($a.PSObject.Properties['totalSize']) { $a.totalSize } else { $null }
                    }
                }
                $manifestUrl = if ($m.PSObject.Properties['previousVersion'] -and $m.previousVersion) {
                    "$repoBase/download/v$($m.previousVersion)/release-manifest.json"
                } else { $null }
                $hop++
            } catch {
                Write-Verbose "Chain ended at hop $hop : $_"
                break
            }
        }
        Write-Output "Pack library: $($packLibrary.Count) entries across $hop release(s)"
    } catch {
        Write-Warning "Cannot build pack library (will build all packs): $_"
    }

    $packsDir = "$($pwd.Path)\build\packs"
    New-Item -ItemType Directory -Force -Path $packsDir | Out-Null

    $releaseVersion = ($env:RELEASE_VERSION -replace '^v', '')
    if ([string]::IsNullOrEmpty($releaseVersion)) { $releaseVersion = "dev" }

    $appsToInstall = [System.Collections.Generic.List[object]]::new()
    $packResults   = @{}  # appName → [ordered]@{name, version, pack}
    $reusedCount   = 0

    # ── Pre-flight: check available version via scoop cat ─────────────────
    # Use bucket-qualified name when available to avoid ambiguity across buckets.
    # 'scoop cat <app>' uses scoop's own bucket priority — no internal path assumptions.
    foreach ($app in $apps) {
        $appName     = $app.name
        $qualifiedName = if ($app | Get-Member -Name 'bucket') { "$($app.bucket)/$($app.name)" } else { $app.name }

        $availVer = $null
        if ($app | Get-Member -Name 'version') {
            $availVer = $app.version  # pinned in apps.json
        } else {
            try {
                $catOutput = & scoop cat $qualifiedName 2>&1
                $catText   = $catOutput -join "`n"
                $catTrim   = $catText.TrimStart()
                if ($catTrim.StartsWith('{') -or $catTrim.StartsWith('[')) {
                    $manifest = $catText | ConvertFrom-Json
                    if ($manifest -and $manifest.PSObject.Properties.Name -contains 'version') {
                        $availVer = $manifest.version
                    }
                }
            } catch { }
        }

        $reused = $false
        if ($availVer) {
            # Use unqualified app name for packLibrary lookup to match stored keys ("<appName>:<version>")
            $key = "$($appName):$($availVer)"
            if ($packLibrary.ContainsKey($key)) {
                $entry = $packLibrary[$key]
                Write-Output "  Reusing $appName $availVer (pack stays at $($entry.url))"
                # Do NOT download the pack — it will not be re-uploaded to this release.
                # toolset.ps1 resolves the pack via packUrl in the manifest, pointing directly
                # to the release where it was originally built.  Re-downloading + re-uploading
                # identical bytes to every new release was the original flaw: it wasted CI time,
                # doubled GitHub storage, and made all releases look like full rebuilds.
                $result = [ordered]@{
                    name    = $appName
                    version = $availVer
                    pack    = $entry.pack
                    packUrl = $entry.url   # explicit URL; toolset.ps1 uses this instead of <newVersion>/<pack>
                }
                if ($null -ne $entry.fileCount) { $result['fileCount'] = $entry.fileCount }
                if ($null -ne $entry.totalSize)  { $result['totalSize'] = $entry.totalSize }
                $packResults[$appName] = $result
                $reusedCount++
                $reused = $true
            }
        }

        if (-not $reused) {
            $appsToInstall.Add($app)
        }
    }

    Write-Output "Plan: install $($appsToInstall.Count) apps, reuse $reusedCount packs"

    # ── Install only apps that need rebuilding ────────────────────────────
    foreach ($app in $appsToInstall) {
        try {
            $installName = $app.name
            if ($app | Get-Member -Name 'bucket') {
                $installName = "$($app.bucket)/$installName"
            }
            if ($app | Get-Member -Name 'version') {
                $installName = "$installName@$($app.version)"
            }
            Write-Host "Installing $installName..." -ForegroundColor Green
            scoop install $installName
        } catch {
            Write-Warning "Failed to install $($app.name): $_"
        }
    }
    #We could purge cache here but won't be able to use ghaction cache abilities in that case...

    # ── Generate packs for newly installed apps ───────────────────────────
    if ($appsToInstall.Count -gt 0) {
        Write-Output "Generating packs..."

        foreach ($app in $appsToInstall) {
            $appName      = $app.name
            $manifestPath = "build\scoop\apps\$appName\current\manifest.json"
            if (-not (Test-Path $manifestPath)) {
                Write-Warning "No manifest.json for $appName — install may have failed, skipping pack"
                continue
            }
            $version  = (Get-Content $manifestPath -Raw | ConvertFrom-Json).version
            $packName = "$appName-$version.zip"
            $packPath = "$packsDir\$packName"

            Write-Output "  Packing $appName $version..."
            # Zip root = <appName>\ — extraction to scoop\apps\ gives the correct layout.
            # 'current' is a scoop junction recreated by 'scoop reset *' after extraction;
            # it is excluded by the [/\\]current[/\\] filter in New-ZipPack.
            New-ZipPack -AppDir "build\scoop\apps\$appName" -DestZip $packPath
            # Read integrity metadata from the freshly-created zip (assembly already loaded by New-ZipPack)
            $zr = [System.IO.Compression.ZipFile]::OpenRead($packPath)
            try {
                $fc = $zr.Entries.Count
                $ts = [long]($zr.Entries | Measure-Object -Property Length -Sum).Sum
            } finally { $zr.Dispose() }
            $packResults[$appName] = [ordered]@{ name = $appName; version = $version; pack = $packName; fileCount = $fc; totalSize = $ts }
        }
    }

    # ── Write release-manifest.json in apps.json order ───────────────────
    $manifestApps = @()
    foreach ($app in $apps) {
        if ($packResults.ContainsKey($app.name)) {
            $entry = $packResults[$app.name]
            if ($app.PSObject.Properties['paths2DropToEnableMultiUser']) { $entry['paths2DropToEnableMultiUser'] = $app.paths2DropToEnableMultiUser }
            $manifestApps += $entry
        }
    }

    $manifest = [ordered]@{
        version             = $releaseVersion
        previousVersion     = $prevVersion   # enables chain-walking without GitHub API
        built               = (Get-Date -Format "o")
        # Absolute path of scoop\persist at build time — used by toolset.ps1 to fix
        # embedded paths in nodejs-lts npm modules without hardcoding the CI workspace.
        buildScoopPersistDir = "$buildScoopDir\persist"
        apps                = $manifestApps
    }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content "$packsDir\release-manifest.json" -Encoding UTF8

    Write-Output "Done: $($manifestApps.Count) apps ($reusedCount reused, $($appsToInstall.Count) rebuilt)"

}
catch {
    Write-Error "Something went wrong: $_. "
} finally {
    if (-not $ConsoleOutput) {
        Stop-Transcript
    }
}
