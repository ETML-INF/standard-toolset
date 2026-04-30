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

    # Prevent scoop from auto-updating itself during 'scoop install'.
    # In an isolated container there is no internet access to scoop's GitHub repo, so the
    # git pull self-update fails with "You cannot call a method on a null-valued expression"
    # and the whole app install is skipped.
    # Write no_update_scoop to every location scoop may read its config from:
    #   - scoop 0.5.x / PS7: $env:XDG_CONFIG_HOME\scoop or $env:USERPROFILE\.config\scoop
    #   - older scoop / PS5: $env:APPDATA\scoop
    #   - belt-and-suspenders: $buildScoopDir itself
    # Also call 'scoop config' which always writes to whatever path scoop itself uses.
    $env:SCOOP_NO_UPDATE_SCOOP = '1'
    $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $cfgDirs = @(
        $(if ($env:XDG_CONFIG_HOME) { "$env:XDG_CONFIG_HOME\scoop" } else { $null }),
        "$env:USERPROFILE\.config\scoop",
        $(if ($env:APPDATA) { "$env:APPDATA\scoop" } else { $null }),
        $buildScoopDir
    ) | Where-Object { $_ }
    foreach ($cfgDir in $cfgDirs) {
        $cfgFile = Join-Path $cfgDir "config.json"
        $null = New-Item -ItemType Directory -Force -Path $cfgDir
        $cfg = if (Test-Path $cfgFile) { Get-Content $cfgFile -Raw | ConvertFrom-Json } `
               else { [PSCustomObject]@{} }
        $cfg | Add-Member -NotePropertyName 'no_update_scoop' -NotePropertyValue $true -Force
        $cfg | Add-Member -NotePropertyName 'lastupdate'      -NotePropertyValue $now  -Force
        $cfg | ConvertTo-Json | Set-Content $cfgFile -Encoding UTF8
    }
    # Also let scoop write the setting to its own canonical location
    & "$buildScoopDir\shims\scoop.ps1" config no_update_scoop true 2>$null | Out-Null
    & "$buildScoopDir\shims\scoop.ps1" config lastupdate $now 2>$null | Out-Null
    Write-Output "Scoop auto-update disabled (no_update_scoop = true, lastupdate = $now)"

    # Belt-and-suspenders: redirect scoop's own git remote to a local path so
    # that if the config-based disable is ignored, the git pull is a harmless
    # no-op rather than a network call that fails with a null-valued expression.
    # file:// URLs require forward slashes on all platforms, including Windows.
    $scoopGitDir = "$buildScoopDir\apps\scoop\current"
    if (Test-Path "$scoopGitDir\.git") {
        $gitUrl = "file:///" + ($scoopGitDir -replace '\\', '/')
        git -C $scoopGitDir remote set-url origin $gitUrl 2>$null
        Write-Output "Scoop git remote redirected to $gitUrl"
    }

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
    # computed by Get-FilesNoJunction, which stops at reparse points.
    # This keeps the counts consistent with what Test-AppIntegrity measures after
    # scoop activation, even if users later add files to their persist folder.
    function Add-ZipType {
        if (-not ([System.Management.Automation.PSTypeName]'System.IO.Compression.ZipFile').Type) {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
        }
    }

    function Expand-ZipWithProgress {
        param([string]$ZipPath, [string]$DestinationPath)
        Add-ZipType
        $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        try {
            $entries = @($zip.Entries); $total = $entries.Count; $i = 0
            foreach ($entry in $entries) {
                $i++
                $pct    = [int](($i / [Math]::Max(1, $total)) * 20)
                $filled = if ($pct -ge 20) { '=' * 20 } else { '=' * $pct + '>' + ' ' * (19 - $pct) }
                Write-Host ("`r    Extracting... $i / $total  [$filled]") -NoNewline
                $destRelative = $entry.FullName -replace '/', '\'
                $destFile     = Join-Path $DestinationPath $destRelative
                if ($entry.Name -eq '') { New-Item -ItemType Directory -Force -Path $destFile | Out-Null; continue }
                $destDir = Split-Path $destFile -Parent
                if (-not (Test-Path $destDir -PathType Container)) { New-Item -ItemType Directory -Force -Path $destDir | Out-Null }
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destFile, $true)
            }
            Write-Host ""
        } finally { $zip.Dispose() }
    }

    function New-ZipPack {
        param([string]$AppDir, [string]$DestZip)
        Add-ZipType
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

    function Invoke-PrePackPatch {
        # Patches app files listed in patchBuildPaths before the zip pack is created.
        # Delegates to Invoke-PatchMarkerFile (imported from toolset.ps1) for the core logic.
        param([string]$AppDir, [string]$BuildScoopDir, [string]$DefaultScoopDir, [string[]]$FilePaths)
        $verDir = Get-ChildItem $AppDir -Directory -ErrorAction SilentlyContinue |
                      Where-Object { $_.Name -ne 'current' } |
                      Sort-Object Name -Descending |
                      Select-Object -First 1 -ExpandProperty FullName
        if (-not $verDir) { return }
        foreach ($filePath in $FilePaths) {
            $full = Join-Path $verDir $filePath
            if (-not (Test-Path $full -PathType Leaf -ErrorAction SilentlyContinue)) { continue }
            Invoke-PatchMarkerFile -FilePath $full -OldPath $BuildScoopDir -NewPath $DefaultScoopDir
        }
    }

    # ── Functions loaded directly from toolset.ps1 (single source of truth) ──
    $_tsAst = [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $PSScriptRoot 'toolset.ps1'), [ref]$null, [ref]$null)
    foreach ($_fn in @('Get-FilesNoJunction', 'Invoke-PatchMarkerFile')) {
        $_fnDef = $_tsAst.FindAll({
            $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $args[0].Name -eq $_fn
        }, $true) | Select-Object -First 1
        if (-not $_fnDef) { throw "$_fn not found in toolset.ps1" }
        Invoke-Expression $_fnDef.Extent.Text
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
                    pack                  = $a.pack
                    url                   = $packUrl0
                    fileCount             = if ($a.PSObject.Properties['fileCount']) { $a.fileCount } else { $null }
                    totalSize             = if ($a.PSObject.Properties['totalSize']) { $a.totalSize } else { $null }
                    zipMd5                = if ($a.PSObject.Properties['zipMd5'])    { $a.zipMd5    } else { $null }
                    integrityExcludePaths = if ($a.PSObject.Properties['integrityExcludePaths']) { $a.integrityExcludePaths } else { $null }
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
                        pack                  = $a.pack
                        url                   = $packUrl
                        fileCount             = if ($a.PSObject.Properties['fileCount']) { $a.fileCount } else { $null }
                        totalSize             = if ($a.PSObject.Properties['totalSize']) { $a.totalSize } else { $null }
                        zipMd5                = if ($a.PSObject.Properties['zipMd5'])    { $a.zipMd5    } else { $null }
                        integrityExcludePaths = if ($a.PSObject.Properties['integrityExcludePaths']) { $a.integrityExcludePaths } else { $null }
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
            if ($null -ne $entry.zipMd5)     { $scoopPackResult['zipMd5']    = $entry.zipMd5    }
            $reusedCount++
        } else {
            $scoopPackName = "scoop-$scoopVer.zip"
            $scoopPackPath = "$packsDir\$scoopPackName"
            Write-Output "  Packing scoop $scoopVer..."
            New-ZipPack -AppDir $scoopAppDir -DestZip $scoopPackPath
            $scoopFiles = @(Get-FilesNoJunction -Path $scoopAppDir)
            $fc = $scoopFiles.Count
            $ts = [long]($scoopFiles | Measure-Object -Property Length -Sum).Sum
            $scoopPackResult = [ordered]@{ name = 'scoop'; version = $scoopVer; pack = $scoopPackName; fileCount = $fc; totalSize = $ts; zipMd5 = (Get-FileHash -Algorithm MD5 $scoopPackPath).Hash.ToLower() }
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
                # If integrityExcludePaths changed, the stored fileCount/totalSize were computed
                # under the old exclusion list.  Reusing them would make toolset.ps1 see a count
                # mismatch on every run and trigger a reinstall loop.  Force a rebuild so the new
                # counts are computed with the current exclusion list and stored in this manifest.
                $currentExcl = if ($app.PSObject.Properties['integrityExcludePaths']) {
                    @($app.integrityExcludePaths | ForEach-Object { "$_" } | Sort-Object)
                } else { @() }
                $storedExcl  = if ($null -ne $entry.integrityExcludePaths) {
                    @($entry.integrityExcludePaths | ForEach-Object { "$_" } | Sort-Object)
                } else { @() }
                $exclMismatch = ($currentExcl -join "|") -ne ($storedExcl -join "|")

                if ($exclMismatch) {
                    Write-Output "  Rebuilding $appName $availVer (integrityExcludePaths changed)"
                    # falls through to $appsToInstall.Add($app) below
                } else {
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
                    if ($null -ne $entry.zipMd5)     { $result['zipMd5']    = $entry.zipMd5    }
                    $packResults[$appName] = $result
                    $reusedCount++
                    $reused = $true
                }
            }
        }

        if (-not $reused) {
            $appsToInstall.Add($app)
        }
    }

    Write-Output "Plan: install $($appsToInstall.Count) apps, reuse $reusedCount packs"

    # ── Pre-install reused apps from local pack zips ──────────────────────
    # Reused apps are not re-downloaded, but scoop needs their files present in
    # build\scoop\apps\ to resolve dependencies during 'scoop install'. Without
    # this, installing vscode (which depends on 7zip) fails in NanoServer because
    # scoop tries to download and install 7zip via MSI, but msiexec.exe is absent.
    # Extracting the pack zip from the seed library pre-populates the app dir so
    # scoop sees the app as already installed and skips the download entirely.
    foreach ($key in $packLibrary.Keys) {
        $entry      = $packLibrary[$key]
        $appKey     = $key -split ':', 2
        $appName    = $appKey[0]
        $packVersion = if ($appKey.Count -gt 1) { $appKey[1] } else { '' }
        $appDir     = "$buildScoopDir\apps\$appName"
        if (Test-Path $appDir) { continue }          # already installed in scoop
        $packUrl = $entry.url
        if (-not $packUrl -or $packUrl -match '^https?://') { continue }  # remote URLs only available at client-side
        if (-not (Test-Path $packUrl)) { continue }  # local pack not accessible here

        Write-Output "  Pre-installing $appName $packVersion from pack (dependency support)..."
        Expand-ZipWithProgress -ZipPath $packUrl -DestinationPath "$buildScoopDir\apps"
        $versionDir = "$appDir\$packVersion"
        $currentDir = "$appDir\current"
        if ((Test-Path $versionDir) -and -not (Test-Path $currentDir)) {
            New-Item -ItemType Junction -Path $currentDir -Value $versionDir | Out-Null
        }
    }

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
            # --no-update-scoop: scoop 0.5.x checks is_scoop_outdated before every install
            # and calls scoop-update.ps1 when true. In an isolated container the git pull
            # inside scoop-update.ps1 fails with a null-valued expression and aborts the
            # whole install. The flag bypasses the update check entirely, regardless of the
            # no_update_scoop config setting (which only affects is_scoop_outdated).
            scoop install --no-update-scoop $installName
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
            if ($app.PSObject.Properties['patchBuildPaths'] -and @($app.patchBuildPaths).Count -gt 0) {
                $patchFiles = @($app.patchBuildPaths | ForEach-Object { [string]$_ })
                Invoke-PrePackPatch -AppDir "build\scoop\apps\$appName" -BuildScoopDir $buildScoopDir `
                    -DefaultScoopDir 'C:\inf-toolset\scoop' -FilePaths $patchFiles
            }
            # Zip root = <appName>\ -- extraction to scoop\apps\ gives the correct layout.
            # 'current' is a scoop junction recreated by 'scoop reset *' after extraction;
            # it is excluded by the [/\\]current[/\\] filter in New-ZipPack.
            New-ZipPack -AppDir "build\scoop\apps\$appName" -DestZip $packPath
            # Integrity metadata is computed from the versioned subdir (matching the path
            # Test-AppIntegrity uses on the client) so that integrityExcludePaths relative
            # paths are consistent -- no version-prefix mismatch from counting at the app dir level.
            # Persist entries from the scoop manifest.json are excluded so the recorded counts
            # match what Test-AppIntegrity measures after scoop activation (where they become
            # junctions/symlinks and are automatically skipped on the client).
            $excludePaths     = if ($app.PSObject.Properties['integrityExcludePaths']) { @($app.integrityExcludePaths) } else { @() }
            $persistDirExcl   = @()
            $persistFileExcl  = @()
            $appBuildDir      = "build\scoop\apps\$appName"
            $verObj           = Get-ChildItem $appBuildDir -Directory -ErrorAction SilentlyContinue |
                                    Where-Object { $_.Name -ne 'current' } |
                                    Sort-Object Name -Descending | Select-Object -First 1
            $measureRoot      = if ($verObj) { $verObj.FullName } else { (Resolve-Path $appBuildDir -ErrorAction SilentlyContinue).ProviderPath }
            $scoopMfst        = if ($measureRoot) { "$measureRoot\manifest.json" } else { "" }
            if ($scoopMfst -and (Test-Path $scoopMfst -ErrorAction SilentlyContinue)) {
                try {
                    $sm = Get-Content $scoopMfst -Raw | ConvertFrom-Json
                    if ($sm.PSObject.Properties['persist']) {
                        @($sm.persist) | ForEach-Object {
                            if ($_ -is [string]) {
                                $entry = $_.Replace('/', '\').TrimStart('\')
                                $persistDirExcl  += $entry
                                $persistFileExcl += $entry
                            }
                        }
                    }
                } catch { }
            }
            $measuredFiles = @(Get-FilesNoJunction -Path $measureRoot -ExcludePaths ($excludePaths + $persistDirExcl) -ExcludeFilePaths $persistFileExcl)
            $fc = $measuredFiles.Count
            $ts = [long]($measuredFiles | Measure-Object -Property Length -Sum).Sum
            $packResults[$appName] = [ordered]@{ name = $appName; version = $version; pack = $packName; fileCount = $fc; totalSize = $ts; zipMd5 = (Get-FileHash -Algorithm MD5 $packPath).Hash.ToLower() }
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
            if ($app.PSObject.Properties['integrityExcludePaths'])       { $entry['integrityExcludePaths']       = $app.integrityExcludePaths }
            if ($app.PSObject.Properties['patchBuildPaths'])             { $entry['patchBuildPaths']             = $app.patchBuildPaths }
            if ($app.PSObject.Properties['exeToCheck']      -and $app.exeToCheck)      { $entry['exeToCheck']      = $app.exeToCheck }
            if ($app.PSObject.Properties['uninstallSearch'] -and $app.uninstallSearch) { $entry['uninstallSearch'] = $app.uninstallSearch }
            $manifestApps += $entry
        }
    }

    $manifest = [ordered]@{
        version             = $releaseVersion
        built               = (Get-Date -Format "o")
        # Absolute scoop base path at build time -- toolset.ps1 replaces this with the
        # client scoop dir to fix any CI-runner paths embedded in installed app files.
        buildScoopDir        = $buildScoopDir
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
