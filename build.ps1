param(
    [Parameter(Mandatory=$false,HelpMessage="Path to json file containing app definitions")]
    [string]$appJson = "apps.json",
    [Parameter(Mandatory=$false)][bool]$ConsoleOutput = $true
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
    # Chain: latest/download/release-manifest.json
    #          → releases/download/v<previousVersion>/release-manifest.json
    #          → ...  (up to $maxHops releases back)
    $repoBase   = "https://github.com/ETML-INF/standard-toolset/releases"
    $packLibrary = @{}      # "appName:version" → {pack, url}
    $prevVersion = $null    # version of current-latest, stored as previousVersion in new manifest
    $maxHops     = 10

    try {
        Write-Output "Building pack library from release chain..."
        $manifestUrl = "$repoBase/latest/download/release-manifest.json"
        $hop = 0
        while ($manifestUrl -and $hop -lt $maxHops) {
            try {
                $m = Invoke-RestMethod $manifestUrl -ErrorAction Stop
                if ($hop -eq 0) { $prevVersion = $m.version }  # remember before we overwrite
                foreach ($a in $m.apps) {
                    $key = "$($a.name):$($a.version)"
                    if ($packLibrary.ContainsKey($key)) { continue }  # newer release already has it
                    $packLibrary[$key] = @{
                        pack = $a.pack
                        url  = "$repoBase/download/v$($m.version)/$($a.pack)"
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
    # 'scoop cat <app>' uses scoop's own bucket priority — no internal path assumptions.
    foreach ($app in $apps) {
        $appName = $app.name

        $availVer = $null
        if ($app | Get-Member -Name 'version') {
            $availVer = $app.version  # pinned in apps.json
        } else {
            try {
                $catOutput = & scoop cat $appName 2>&1
                $availVer  = ($catOutput | ConvertFrom-Json).version
            } catch { }
        }

        $reused = $false
        if ($availVer) {
            $key = "$($appName):$($availVer)"
            if ($packLibrary.ContainsKey($key)) {
                $entry    = $packLibrary[$key]
                $destPack = "$packsDir\$($entry.pack)"
                Write-Output "  Reusing $appName $availVer"
                try {
                    Invoke-WebRequest $entry.url -OutFile $destPack -ErrorAction Stop
                    $packResults[$appName] = [ordered]@{ name = $appName; version = $availVer; pack = $entry.pack }
                    $reusedCount++
                    $reused = $true
                } catch {
                    Write-Warning "  Download failed for $appName, will rebuild: $_"
                }
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
            $packResults[$appName] = [ordered]@{ name = $appName; version = $version; pack = $packName }
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
        version         = $releaseVersion
        previousVersion = $prevVersion   # enables chain-walking without GitHub API
        built           = (Get-Date -Format "o")
        apps            = $manifestApps
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
