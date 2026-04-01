param(
    [Parameter(Mandatory=$false,HelpMessage="Path to json file containing app definitions")]
    [string]$appJson = "apps.json",
    [Parameter(Mandatory=$false)][bool]$ConsoleOutput = $true,
    # Filesystem path to a fake "previous release" manifest — used by tests to exercise
    # pack reuse without needing live GitHub releases.  Read with Get-Content, bypassing
    # the URL chain entirely.  Leave empty in production.
    [Parameter(Mandatory=$false)][string]$PreviousManifestPath = "",
    # Path to a private apps manifest (same format as apps.json) that extends the public
    # list with local-only entries. Defaults to L:\toolset\private-apps.json. Only loaded
    # if the file is accessible — silently skipped otherwise so CI builds still work.
    [Parameter(Mandatory=$false)][string]$PrivateAppsPath = "L:\toolset\private-apps.json"
)

# Start transcript for logging (parallel-safe with unique filename)
if (-not $ConsoleOutput) {
    $logFile = "$PSScriptRoot\build-$PID.log"
    Start-Transcript -Path $logFile -Append -Force
}

try {
    Set-StrictMode -Version Latest

    $repoRoot      = $pwd.Path   # capture before any external command may change $PWD
    $buildScoopDir = "$repoRoot\build\scoop"
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

    # Ensure scoop's own app dir has the versioned structure New-ZipPack requires.
    # Fresh install puts files in apps\scoop\current\ as a real folder (no versioned dirs).
    # New-ZipPack excludes anything under current\ (to skip the junction for other apps),
    # so the scoop zip would be empty without this step.
    # 'scoop update scoop' creates apps\scoop\<version>\ and makes current\ a junction —
    # exactly the structure we need. It is idempotent (no-op when already up to date).
    $scoopCurrentPath = "$buildScoopDir\apps\scoop\current"
    $scoopCurrentItem = Get-Item $scoopCurrentPath -ErrorAction SilentlyContinue
    $isJunction = $scoopCurrentItem -and ($scoopCurrentItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
    if ($scoopCurrentItem -and -not $isJunction) {
        # current\ is a real dir (fresh install). Create versioned dir + junction so
        # New-ZipPack can include scoop's files without hitting the current\ exclusion.
        # 'scoop update scoop' only creates versioned dirs on an actual version bump,
        # so we normalize manually. Version detection runs in a child process to avoid
        # null-reference failures in scoop's own code under Set-StrictMode -Version Latest.
        $normalizeVer = $null
        if (Test-Path "$scoopCurrentPath\manifest.json") {
            $normalizeVer = (Get-Content "$scoopCurrentPath\manifest.json" -Raw | ConvertFrom-Json).version
        }
        if (-not $normalizeVer) {
            $verOut = pwsh -NoProfile -NonInteractive -Command "& '$scoopCurrentPath\bin\scoop.ps1' --version 2>&1" 2>&1 | Out-String
            if ($verOut -match '(\d+\.\d+\.\d+)') { $normalizeVer = $Matches[1] }
        }
        if ($normalizeVer) {
            $normalizeVerDir = "$buildScoopDir\apps\scoop\$normalizeVer"
            if (-not (Test-Path $normalizeVerDir)) {
                Write-Output "Normalizing scoop to versioned structure ($normalizeVer)..."
                Copy-Item $scoopCurrentPath $normalizeVerDir -Recurse -Force
            }
            Remove-Item $scoopCurrentPath -Recurse -Force
            New-Item -ItemType Junction -Path $scoopCurrentPath -Value $normalizeVerDir | Out-Null
        } else {
            Write-Warning "Could not determine scoop version - scoop will not be packed"
        }
    }

    # Ensure required buckets exist (idempotent — safe whether scoop is fresh or pre-installed)
    scoop bucket add extras 2>$null
    scoop bucket add etml-inf https://github.com/ETML-INF/standard-toolset-bucket 2>$null

    Write-Output "About to install apps defined in $appJson"
    $apps = Get-Content -Raw $appJson | ConvertFrom-Json

    # Merge private apps from network drive (silently skipped when unreachable or absent).
    # private-apps.json lives only on L:\ — never committed to the repo — so private app
    # names, versions, and localPack paths never appear in git history or CI logs.
    if (Test-Path $PrivateAppsPath -ErrorAction SilentlyContinue) {
        $privateApps = Get-Content -Raw $PrivateAppsPath | ConvertFrom-Json
        Write-Output "Loaded $($privateApps.Count) private app(s) from $PrivateAppsPath"
        $apps = @($apps) + @($privateApps)
    } else {
        Write-Output "No private apps manifest at $PrivateAppsPath (skipped)"
    }

    # ── New-ZipPack: .NET-based zip helper ────────────────────────────────
    # Replaces Compress-Archive, which silently skips .git directories.
    # Excludes scoop's 'current' junction (a reparse point); it is recreated
    # by 'scoop reset *' after installation.
    # Persist junctions (data\, bin\, settings\, …) ARE followed when zipping so
    # that fresh installs receive the default persisted files.  However the
    # recorded fileCount/totalSize (used by Test-AppIntegrity on clients) is
    # computed by Measure-SourceNoJunction, which stops at reparse points.
    # This keeps the counts consistent with what Test-AppIntegrity measures after
    # scoop activation, even if users later add files to their persist folder.
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

    # ── Measure-SourceNoJunction: junction-aware file counter ─────────────
    # Recursively walks $Path, stopping at reparse points (scoop persist
    # junctions: data\, bin\, settings\, …) instead of following them.
    # Also skips the current\ subtree, which is excluded from packs.
    # Returns a hashtable with Count (file count) and TotalSize (bytes).
    # Used to record fileCount/totalSize in the release manifest so they match
    # what Test-AppIntegrity measures on the client after scoop activation.
    function Measure-SourceNoJunction {
        param([string]$Path)
        $count = 0
        $size  = [long]0
        Get-ChildItem $Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                # Stop at junctions — do not traverse into scoop persist targets.
            } elseif ($_.PSIsContainer) {
                if ($_.Name -ne 'current') {
                    $sub = Measure-SourceNoJunction $_.FullName
                    $count += $sub.Count
                    $size  += $sub.TotalSize
                }
            } else {
                $count++
                $size += $_.Length
            }
        }
        return @{ Count = $count; TotalSize = $size }
    }

    # ── Pack library: enumerate past releases via gh release list ─────────
    # In CI (RELEASE_VERSION set) we call "gh release list --limit 50" to get all
    # available release tags, then fetch each manifest in order (newest first).
    # A 404 (deleted release) is silently skipped — the chain never breaks.
    # Locally (no RELEASE_VERSION) the queue is left empty and everything is rebuilt.
    #
    # packUrl fix: a reused pack in a prior release already carries a packUrl pointing to
    # the release where it was originally built.  We must use that URL rather than
    # constructing "v<thatRelease>/<pack>" — the zip was never uploaded to every release.
    # Derive repo slug and base URL — avoids hardcoding so forks work without modification.
    # GitHub Actions sets GITHUB_REPOSITORY automatically; locally we parse the git remote.
    $repoSlug = if ($env:GITHUB_REPOSITORY) {
        $env:GITHUB_REPOSITORY
    } else {
        $remote = git remote get-url origin 2>$null
        if ($remote -match 'github\.com[:/](.+?)(?:\.git)?$') { $Matches[1] } else { $null }
    }
    $repoBase = if ($repoSlug) {
        "https://github.com/$repoSlug/releases"
    } else {
        Write-Warning "Could not determine GitHub repo — pack library disabled."
        $null
    }
    $packLibrary = @{}      # "appName:version" → {pack, url}
    $maxHops     = 10

    try {
        Write-Output "Building pack library from release chain..."

        # Determine start URL: skip the release being built in CI to avoid a 404
        # (release-please creates the tag before assets exist).
        # Priority: explicit -PreviousManifestPath (tests) → gh release list (CI) → latest (local)
        $currentTag  = $env:RELEASE_VERSION   # e.g. "v2.1.0", empty outside CI

        # Test injection: seed the pack library from a local file, skip the URL chain entirely.
        # This path requires no GitHub URL, so the repoBase guard below does not apply.
        if (-not [string]::IsNullOrEmpty($PreviousManifestPath)) {
            $m0 = Get-Content $PreviousManifestPath -Raw | ConvertFrom-Json
            foreach ($a in $m0.apps) {
                $key = "$($a.name):$($a.version)"
                if ($packLibrary.ContainsKey($key)) { continue }
                $packUrl0 = if ($a.PSObject.Properties['packUrl'] -and $a.packUrl) { $a.packUrl } elseif ($repoBase) {
                    "$repoBase/download/v$($m0.version)/$($a.pack)"
                } else { $null }
                $packLibrary[$key] = @{
                    pack      = $a.pack
                    url       = $packUrl0
                    fileCount = if ($a.PSObject.Properties['fileCount']) { $a.fileCount } else { $null }
                    totalSize = if ($a.PSObject.Properties['totalSize']) { $a.totalSize } else { $null }
                }
            }
            Write-Output "Pack library: $($packLibrary.Count) entries (injected from $PreviousManifestPath)"
        }

        # Build a queue of manifest URLs to try, newest-first.
        # CI mode: enumerate all releases upfront so deleted intermediate releases
        #          are skipped with 'continue' rather than breaking the chain.
        # Local mode: follow previousVersion links (no gh auth required).
        $manifestQueue = [System.Collections.Generic.Queue[string]]::new()

        if (-not [string]::IsNullOrEmpty($PreviousManifestPath)) {
            # already seeded above; skip URL chain
        } elseif (-not $repoBase) {
            Write-Warning "No GitHub repo URL — URL chain disabled, only injected entries available."
        } elseif ($currentTag) {
            # CI: pre-enumerate all release tags so a missing intermediate release
            # (404) only skips that release rather than aborting the whole chain.
            $allTags = gh release list --repo $repoSlug --limit 50 --json tagName 2>$null |
                ConvertFrom-Json |
                Where-Object { $_.tagName -ne $currentTag } |
                ForEach-Object { $_.tagName }
            foreach ($tag in $allTags) {
                $manifestQueue.Enqueue("$repoBase/download/$tag/release-manifest.json")
            }
        } else {
            # Local / ad-hoc build: no RELEASE_VERSION → no gh auth assumed → queue stays
            # empty → pack library is never populated → every app is freshly zipped.
            # Pack reuse only matters in CI (avoids re-uploading unchanged zips to a release).
            # Locally you typically run this to test the build pipeline itself, not to produce
            # a deployable release — so rebuilding everything is correct and expected.
        }

        $hop = 0
        while ($manifestQueue.Count -gt 0 -and $hop -lt $maxHops) {
            $manifestUrl = $manifestQueue.Dequeue()
            try {
                $m = Invoke-RestMethod $manifestUrl -ErrorAction Stop
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
                $hop++
            } catch {
                # A 404 means that release was deleted — skip and try the next one.
                Write-Verbose "Skipping release (unreachable): $manifestUrl - $_"
                continue
            }
        }
        Write-Output "Pack library: $($packLibrary.Count) entries across $hop release(s)"
    } catch {
        Write-Warning "Cannot build pack library (will build all packs): $_"
    }

    $packsDir = "$repoRoot\build\packs"
    New-Item -ItemType Directory -Force -Path $packsDir | Out-Null

    $releaseVersion = ($env:RELEASE_VERSION -replace '^v', '')
    if ([string]::IsNullOrEmpty($releaseVersion)) { $releaseVersion = "dev" }

    $appsToInstall = [System.Collections.Generic.List[object]]::new()
    $packResults   = @{}  # appName → [ordered]@{name, version, pack}
    $reusedCount   = 0

    # ── Pack scoop itself (always first in manifest) ──────────────────────
    # scoop must be present on the client so Invoke-Activate can run
    # 'scoop reset *' to recreate current\ junctions after pack extraction.
    # It is bootstrapped during build but not listed in apps.json, so we
    # handle it here independently of the normal app loop.
    $scoopAppDir     = "$buildScoopDir\apps\scoop"
    # After normalization above, current\ is a junction to a versioned dir.
    # manifest.json may not exist (scoop installs itself without one); fall back to
    # the versioned dir name, which was set to the version string during normalization.
    $scoopVer = $null
    if (Test-Path "$scoopAppDir\current\manifest.json") {
        $scoopVer = (Get-Content "$scoopAppDir\current\manifest.json" -Raw | ConvertFrom-Json).version
    }
    if (-not $scoopVer) {
        $scoopVer = Get-ChildItem $scoopAppDir -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne 'current' } |
            Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty Name
    }
    $scoopPackResult = $null
    if ($scoopVer) {
        $scoopKey = "scoop:$scoopVer"
        if ($packLibrary.ContainsKey($scoopKey)) {
            $entry = $packLibrary[$scoopKey]
            Write-Output "  Reusing scoop $scoopVer (pack stays at $($entry.url))"
            $scoopPackResult = [ordered]@{ name = 'scoop'; version = $scoopVer; pack = $entry.pack; packUrl = $entry.url }
            if ($null -ne $entry.fileCount) { $scoopPackResult['fileCount'] = $entry.fileCount }
            if ($null -ne $entry.totalSize)  { $scoopPackResult['totalSize'] = $entry.totalSize }
            $reusedCount++
        } else {
            $scoopPackName = "scoop-$scoopVer.zip"
            $scoopPackPath = "$packsDir\$scoopPackName"
            Write-Output "  Packing scoop $scoopVer..."
            New-ZipPack -AppDir $scoopAppDir -DestZip $scoopPackPath
            $m = Measure-SourceNoJunction $scoopAppDir
            $fc = $m.Count; $ts = $m.TotalSize
            $scoopPackResult = [ordered]@{ name = 'scoop'; version = $scoopVer; pack = $scoopPackName; fileCount = $fc; totalSize = $ts }
        }
    } else {
        Write-Warning "Could not determine scoop version under $scoopAppDir - scoop will not be included in this release"
    }

    # ── Pre-flight: check available version via scoop cat ─────────────────
    # Use bucket-qualified name when available to avoid ambiguity across buckets.
    # 'scoop cat <app>' uses scoop's own bucket priority — no internal path assumptions.
    foreach ($app in $apps) {
        # Skip comment-only entries (e.g. {"//": "..."} used as JSON comments)
        if (-not ($app | Get-Member -Name 'name')) { continue }
        # Local packs (localPack field) are private files on L:\ — skip scoop entirely.
        if ($app | Get-Member -Name 'localPack') { continue }

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
            # Integrity metadata is computed from the source dir without following junctions
            # (scoop persist: data\, bin\, settings\, …) so user modifications to persisted
            # data do not trigger false integrity failures on the client.
            $m  = Measure-SourceNoJunction "build\scoop\apps\$appName"
            $fc = $m.Count; $ts = $m.TotalSize
            $packResults[$appName] = [ordered]@{ name = $appName; version = $version; pack = $packName; fileCount = $fc; totalSize = $ts }
        }
    }

    # ── Local (private) packs — sourced from L:\ or any local path ──────
    # Apps with a 'localPack' field are not installed via scoop and are not uploaded
    # to GitHub releases. Their packUrl in the manifest points to the local path so
    # toolset.ps1 copies them directly from there at deploy time.
    # Missing local pack = warning + skip (build does not fail).
    foreach ($app in $apps) {
        if (-not ($app | Get-Member -Name 'name'))     { continue }
        if (-not ($app | Get-Member -Name 'localPack')) { continue }
        $lp = $app.localPack
        if (-not (Test-Path $lp)) {
            Write-Warning "Local pack not found: $lp - $($app.name) will be omitted from this release"
            continue
        }
        $lpFile = Split-Path $lp -Leaf
        $lpVer  = if ($app | Get-Member -Name 'version') { $app.version } `
                  elseif ($lpFile -match '-(\d[\d.]*)\.zip$') { $Matches[1] } `
                  else { 'unknown' }
        Write-Output "  Local pack: $($app.name) $lpVer from $lp"
        $packResults[$app.name] = [ordered]@{ name = $app.name; version = $lpVer; pack = $lpFile; packUrl = $lp }
    }

    # ── Write release-manifest.json in apps.json order ───────────────────
    # scoop is always first: Invoke-Activate needs it before any other app.
    $manifestApps = @()
    if ($scoopPackResult) { $manifestApps += $scoopPackResult }
    foreach ($app in $apps) {
        if (-not ($app | Get-Member -Name 'name')) { continue }
        if ($packResults.ContainsKey($app.name)) {
            $entry = $packResults[$app.name]
            if ($app.PSObject.Properties['paths2DropToEnableMultiUser']) { $entry['paths2DropToEnableMultiUser'] = $app.paths2DropToEnableMultiUser }
            $manifestApps += $entry
        }
    }

    $manifest = [ordered]@{
        version             = $releaseVersion
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
