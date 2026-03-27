param(
    [Parameter(Position=0)][string]$Command = "",
    [string]$Path = "C:\inf-toolset",
    [switch]$NoInteraction,
    [switch]$Clean,
    [string]$Version = "",
    [string]$ManifestSource = "",
    [string]$PackSource = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── helpers ────────────────────────────────────────────────────────────────

function Find-ToolsetDir {
    param([string]$StartPath, [bool]$NoInteraction)
    $dir = $StartPath
    if (-not (Test-Path $dir)) {
        $dir = "D:\data\inf-toolset"
        if (-not (Test-Path $dir)) {
            if ($NoInteraction) { Write-Error "Toolset not found at $StartPath"; exit 1 }
            $userInput = Read-Host "Enter toolset path (empty to abort)"
            if ([string]::IsNullOrEmpty($userInput)) { exit 1 }
            if (-not (Test-Path $userInput)) { Write-Error "$userInput not found"; exit 2 }
            $dir = $userInput
        }
    }
    return $dir
}

function Invoke-NodeCheck {
    param([string]$toolsetdir, [bool]$NoInteraction)
    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    if (-not $nodeCmd) { return }

    $nodePath = $nodeCmd.Source
    $pfx86 = ${env:ProgramFiles(x86)}

    if ($nodePath.StartsWith($env:ProgramFiles) -or ($pfx86 -and $nodePath.StartsWith($pfx86))) {
        Write-Host ""
        Write-Host "+==================================================+" -ForegroundColor Red
        Write-Host "|  WARNING: Node.js detected in Program Files!     |" -ForegroundColor Yellow
        Write-Host "|  This will conflict with the toolset Node.js.    |" -ForegroundColor Yellow
        Write-Host "+==================================================+" -ForegroundColor Red
        Write-Host "  Detected: $nodePath" -ForegroundColor Yellow
        Write-Host "  To uninstall: winget uninstall --name `"Node.js`"" -ForegroundColor Cyan
        Write-Host ""

        if (-not $NoInteraction) {
            $answer = Read-Host "Uninstall now? (requires elevation) [Y/N]"
            if ($answer -match '^[Yy]$') {
                try {
                    $proc = Start-Process powershell -Verb RunAs -Wait -PassThru `
                            -ArgumentList "-Command winget uninstall --name 'Node.js'"
                    if ($proc.ExitCode -eq 0) {
                        Write-Host "Node.js uninstalled. Please re-run toolset.ps1." -ForegroundColor Green
                        exit 0
                    } else {
                        Write-Warning "Uninstall returned exit code $($proc.ExitCode). Please uninstall manually, then re-run toolset.ps1."
                    }
                } catch {
                    Write-Warning "Uninstall failed: $_. Please uninstall manually, then re-run toolset.ps1."
                }
            } else {
                Write-Warning "Please uninstall Node.js manually, then re-run toolset.ps1."
            }
        } else {
            Write-Warning "Admin-installed Node.js at $nodePath. Uninstall it manually: winget uninstall --name 'Node.js'"
        }
    } elseif ($nodePath.StartsWith($toolsetdir)) {
        # Expected — toolset-managed node, all good
    } else {
        Write-Warning "Node.js found at unexpected location: $nodePath. This may conflict with the toolset."
    }
}

function Set-GitSafeDirectory {
    param([string]$gitconfigPath, [string]$toolsetdir)

    $add = "`tdirectory = $($toolsetdir -replace '\\', '/')/*"

    $content = if (Test-Path $gitconfigPath) { @(Get-Content $gitconfigPath) } else { @() }

    $safeIndex = ($content | Select-String "^\[safe\]$" | Select-Object -First 1).LineNumber - 1
    $dirIndex = if ($safeIndex -ge 0) {
        $afterSafe = $content[($safeIndex+1)..($content.Length-1)]
        $hit = $afterSafe | Select-String "^\s*directory\s*=" | Select-Object -First 1
        if ($hit) { $safeIndex + $hit.LineNumber } else { -1 }
    } else { -1 }

    if ($safeIndex -ge 0) {
        if ($dirIndex -ge 0) {
            $content[$dirIndex] = $add
        } else {
            $tail = if (($safeIndex + 1) -le ($content.Length - 1)) { $content[($safeIndex+1)..($content.Length-1)] } else { @() }
            $content = $content[0..$safeIndex] + @($add) + $tail
        }
    } else {
        $content = @("[safe]", $add) + $content
    }

    $content | Set-Content $gitconfigPath -Encoding UTF8
}

function Invoke-Activate {
    param([string]$toolsetdir, [bool]$NoInteraction)

    $scoopdir = "$toolsetdir\scoop"

    # Remove legacy files left by the old zip-based install
    @('activate.ps1', 'install.ps1') | ForEach-Object {
        $legacy = Join-Path $toolsetdir $_
        if (Test-Path $legacy) {
            Remove-Item $legacy -Force -ErrorAction SilentlyContinue
            Write-Host "  Removed legacy file: $_" -ForegroundColor DarkGray
        }
    }

    $scoopPs1 = "$scoopdir\apps\scoop\current\bin\scoop.ps1"
    if (Test-Path $scoopPs1 -ErrorAction SilentlyContinue) {
        Write-Host "Resetting scoop (restores current junctions)..." -ForegroundColor Green
        & $scoopPs1 reset *
    } else {
        Write-Warning "scoop.ps1 not found at $scoopPs1 — skipping junction reset (will complete on next activation)"
    }

    # Drop paths2DropToEnableMultiUser from each app's current\ dir so apps fall back to
    # per-user %APPDATA% instead of the shared portable-mode location.
    # Scoop's persist creates junctions: app\current\<path> → scoop\persist\<app>\<path>.
    # Deleting the junction leaves persist data intact but forces apps to use per-user dirs.
    Write-Host "Configuring per-user app settings..." -ForegroundColor Green
    $dropped = 0
    $mf = $null
    $localManifest = Join-Path $toolsetdir "release-manifest.json"
    if (Test-Path $localManifest -ErrorAction SilentlyContinue) {
        $mf = Get-Content $localManifest -Raw | ConvertFrom-Json
        foreach ($appEntry in $mf.apps) {
            if (-not $appEntry.PSObject.Properties['paths2DropToEnableMultiUser']) { continue }
            foreach ($rel in $appEntry.paths2DropToEnableMultiUser) {
                $target = Join-Path "$scoopdir\apps\$($appEntry.name)\current" $rel
                $item = Get-Item $target -Force -ErrorAction SilentlyContinue
                if (-not $item) { continue }
                try {
                    if ($item.PSIsContainer) {
                        # Directory junction — Delete() removes only the link, not persist contents
                        [System.IO.Directory]::Delete($item.FullName)
                    } else {
                        Remove-Item $item.FullName -Force
                    }
                    Write-Host "  Per-user: $($appEntry.name)\$rel" -ForegroundColor DarkGray
                    $dropped++
                } catch {
                    Write-Verbose "Could not remove $target : $_"
                }
            }
        }
        if ($dropped -eq 0) { Write-Host "  No portable mode triggers found." -ForegroundColor DarkGray }
    } else {
        Write-Host "  No release manifest found — skipping portable path cleanup." -ForegroundColor DarkGray
    }

    Write-Host "Updating scoop shims for path $toolsetdir..." -ForegroundColor Green
    $shimpath = "$scoopdir\shims"
    @("$shimpath\scoop","$shimpath\scoop.cmd","$shimpath\scoop.ps1") | ForEach-Object {
        $c = Get-Content $_ -Raw
        $c -replace '[A-Z]:.*?\\scoop\\', "$scoopdir\" | Set-Content $_ -NoNewline
    }

    Write-Host "Fixing reg file paths..." -ForegroundColor Green
    Get-ChildItem "$scoopdir\apps\*\current\*.reg" -Recurse | ForEach-Object {
        $c = Get-Content $_ -Raw
        $c -replace '[A-Z]:.*?\\\\scoop\\\\', "$($scoopdir -replace '\\','\\')\" | Set-Content $_ -NoNewline
    }

    # VSCode context menu — use direct path, no dependency on scoop being on PATH
    $vsCodeReg = "$scoopdir\apps\vscode\current\install-context.reg"
    if (Test-Path $vsCodeReg) {
        try {
            & reg import $vsCodeReg
            Write-Output "VSCode context menu added/updated"
        } catch {
            Write-Warning "VSCode context menu update failed: $_"
        }
    }

    # Git safe.directory — inline logic, no external script dependency
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Set-GitSafeDirectory -gitconfigPath "$env:USERPROFILE\.gitconfig" -toolsetdir $toolsetdir
        Write-Output "Git safe.directory configured"
    } else {
        Write-Host "Git not installed. Re-run toolset.ps1 after installing git." -ForegroundColor Red
    }

    # Admin Node.js detection
    Invoke-NodeCheck -toolsetdir $toolsetdir -NoInteraction $NoInteraction

    # Fix nodejs-lts npm paths
    # During CI build, npm embeds the CI persist path (D:\a\...\build\scoop\persist\nodejs-lts)
    # into text config/script files. We replace that CI path with the user's actual persist dir.
    # Scans all text-like files in the versioned dir + persist dir (skips binaries by extension).
    # (See also: ETML-INF/standard-toolset PR #21 which identified this issue in the old arch.)
    if (Test-Path "$scoopdir\apps\nodejs-lts\current\manifest.json") {
        Write-Host "Fixing nodejs-lts paths..." -ForegroundColor Green
        $version = (Get-Content "$scoopdir\apps\nodejs-lts\current\manifest.json" | ConvertFrom-Json).version
        # Read the CI build persist path from the release manifest so we don't hardcode
        # the GitHub Actions workspace directory (D:\a\<repo>\<repo>\build\scoop\persist).
        # Escape backslashes for PowerShell -replace (which uses regex), then append \nodejs-lts.
        $oldPattern = if ($mf -and $mf.PSObject.Properties['buildScoopPersistDir']) {
            ($mf.buildScoopPersistDir -replace '\\', '\\\\') + '\\nodejs-lts'
        } else {
            'D:\\a\\standard-toolset\\standard-toolset\\build\\scoop\\persist\\nodejs-lts'
        }
        $newPersist = "$scoopdir\persist\nodejs-lts"  # where npm cache/prefix live at runtime

        # Text-like extensions that may embed absolute paths — skip binaries for speed and safety
        $textExts = @('.js','.mjs','.cjs','.json','.cmd','.ps1','.bat','.npmrc','.ini','.cfg','.txt','.rc')

        $scanRoots = @(
            "$scoopdir\apps\nodejs-lts\$version",  # full versioned install (node_modules etc.)
            "$scoopdir\persist\nodejs-lts"          # persist dir (npmrc cache/prefix settings)
        )
        foreach ($root in $scanRoots) {
            if (-not (Test-Path $root)) { continue }
            Get-ChildItem $root -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $textExts -contains $_.Extension.ToLower() } |
                ForEach-Object {
                    $c = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
                    if ($c -and $c -match $oldPattern) {
                        $c -replace $oldPattern, $newPersist | Set-Content $_.FullName -NoNewline
                    }
                }
        }
    }

    # Desktop shortcut
    $scoopShortcutsFolder = "$env:USERPROFILE\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Scoop Apps\"
    if (Test-Path $scoopShortcutsFolder) {
        $shortcutPath = [Environment]::GetFolderPath("Desktop") + "\$(Split-Path $toolsetdir -Leaf).lnk"
        if (Test-Path $shortcutPath) { Remove-Item $shortcutPath -Force }
        $shell = New-Object -ComObject WScript.Shell
        $sc = $shell.CreateShortcut($shortcutPath)
        $sc.TargetPath = $scoopShortcutsFolder
        $sc.IconLocation = "C:\Windows\System32\shell32.dll,12"
        $sc.Save()
        Write-Output "Shortcut created: $shortcutPath"
    }

    # Grant all users full control — best effort (requires elevation; silent if unavailable)
    Write-Host "Setting permissions for all users..." -ForegroundColor Green
    & icacls $toolsetdir /grant "Users:(OI)(CI)M" /T /C /Q 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Permissions set." -ForegroundColor Green
    } else {
        Write-Verbose "icacls returned $LASTEXITCODE — run as administrator to set permissions"
    }
}

# ── manifest + pack helpers (used by update mode) ─────────────────────────

function Invoke-Download {
    param(
        [string]$Url,
        [string]$OutFile,
        [string]$Description = ""
    )
    $label = if ($Description) { $Description } else { Split-Path $Url -Leaf }

    # Try BITS first — resumable, progress display, handles large packs well.
    # Falls through silently if BITS is unavailable (containers, PS remoting, etc.)
    try {
        Import-Module BitsTransfer -ErrorAction Stop
        $job     = Start-BitsTransfer -Source $Url -Destination $OutFile `
                       -Asynchronous -DisplayName $label -ErrorAction Stop
        $timeout = (Get-Date).AddMinutes(75)
        do {
            Start-Sleep -Seconds 3
            $progress = Get-BitsTransfer -JobId $job.JobId
            if ($progress.BytesTransferred -gt 0 -and $progress.BytesTotal -gt 0) {
                $pct = [math]::Round(($progress.BytesTransferred / $progress.BytesTotal) * 100, 1)
                $mb  = [math]::Round($progress.BytesTransferred / 1MB, 1)
                $tot = [math]::Round($progress.BytesTotal / 1MB, 1)
                Write-Host ("`r" + " " * 80 + "`r    $pct% ($mb / $tot MB)") -NoNewline
            }
            if ((Get-Date) -gt $timeout) {
                Remove-BitsTransfer -BitsJob $job
                throw "BITS timeout after 75 minutes"
            }
        } while ($progress.JobState -in @("Transferring", "Connecting", "TransientError"))
        Write-Host ""
        if ($progress.JobState -eq "Transferred") {
            Complete-BitsTransfer -BitsJob $job
            return
        }
        Remove-BitsTransfer -BitsJob $job
        throw "BITS ended in state: $($progress.JobState) — $($progress.ErrorDescription)"
    } catch {
        Write-Verbose "BITS unavailable for $label : $_ — falling back to Invoke-WebRequest"
    }

    # Fallback: works in containers and environments without BITS
    Invoke-WebRequest $Url -OutFile $OutFile -ErrorAction Stop
}

function Get-ReleaseManifest {
    param(
        [string]$ManifestSource,
        [string]$Version,
        [string]$LDrivePath = "L:\toolset"
    )
    if ($ManifestSource -and (Test-Path $ManifestSource)) {
        return Get-Content $ManifestSource -Raw | ConvertFrom-Json
    }
    $repoBase = "https://github.com/ETML-INF/standard-toolset/releases"
    if ([string]::IsNullOrEmpty($Version)) {
        # Latest: GitHub first, L: fallback
        try {
            return Invoke-RestMethod "$repoBase/latest/download/release-manifest.json" -ErrorAction Stop
        } catch { Write-Verbose "GitHub manifest fetch failed: $_" }
        $lManifest = "$LDrivePath\release-manifest.json"
        if (Test-Path $lManifest) { return Get-Content $lManifest -Raw | ConvertFrom-Json }
    } else {
        # Pinned version: L: first, GitHub fallback
        $lManifest = "$LDrivePath\$Version\release-manifest.json"
        if (Test-Path $lManifest) { return Get-Content $lManifest -Raw | ConvertFrom-Json }
        try {
            return Invoke-RestMethod "$repoBase/download/v$Version/release-manifest.json" -ErrorAction Stop
        } catch { Write-Verbose "GitHub manifest for v$Version failed: $_" }
    }
    throw "Cannot reach GitHub and L:\toolset is not available. Please connect to the network or the internal drive and try again."
}

function Get-LocalAppVersions {
    param([string]$toolsetdir)
    $result = @{}
    $appsDir = "$toolsetdir\scoop\apps"
    if (-not (Test-Path $appsDir)) { return $result }
    Get-ChildItem $appsDir -Directory | ForEach-Object {
        $mPath = "$($_.FullName)\current\manifest.json"
        if (Test-Path $mPath) {
            try { $result[$_.Name] = (Get-Content $mPath -Raw | ConvertFrom-Json).version } catch { }
        }
    }
    return $result
}

function Get-ZipEntryCount {
    # Reads only the zip central directory (metadata) — no extraction.
    # Returns count of file entries only (directory entries are excluded).
    param([string]$ZipPath)
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip   = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        $count = @($zip.Entries | Where-Object { -not $_.FullName.EndsWith('/') }).Count
        $zip.Dispose()
        return $count
    } catch { return -1 }
}

function Test-PreExtractedDir {
    # Validates a pre-extracted pack directory.
    # Returns "ok", "version_mismatch", or "count_mismatch:<zipCount>:<dirCount>".
    param([string]$Dir, [object]$App, [string]$ZipPath = "")
    $mPath = Join-Path $Dir "$($App.name)\current\manifest.json"
    if (-not (Test-Path $mPath)) { return "version_mismatch" }
    try {
        $v = (Get-Content $mPath -Raw | ConvertFrom-Json).version
        if ($v -ne $App.version) { return "version_mismatch" }
    } catch { return "version_mismatch" }

    if ($ZipPath -and (Test-Path $ZipPath)) {
        $zipCount = Get-ZipEntryCount $ZipPath
        if ($zipCount -ge 0) {
            $dirCount = @(Get-ChildItem $Dir -Recurse -File -Force -ErrorAction SilentlyContinue).Count
            if ($zipCount -ne $dirCount) { return "count_mismatch:$zipCount`:$dirCount" }
        }
    }
    return "ok"
}

function Get-Pack {
    param(
        [object]$App,
        [string]$PackSource,
        [string]$Version,
        [bool]$NoInteraction = $false,
        [string]$LDrivePath = "L:\toolset"
    )
    $packName = $App.pack
    $packDir  = $packName -replace '\.zip$', ''   # pre-extracted directory name
    $tmpFile  = "$env:TEMP\$packName"

    if ($PackSource) {
        $local    = Join-Path $PackSource $packName
        $localDir = Join-Path $PackSource $packDir
        if (Test-Path $localDir -PathType Container) {
            $check = Test-PreExtractedDir $localDir $App -ZipPath $local
            if ($check -eq "ok")              { return $localDir }
            if ($check -like "count_mismatch:*") {
                $parts = $check.Split(':')
                $msg   = "Pre-extracted $packDir has $($parts[2]) files but zip has $($parts[1]) entries."
                if ($NoInteraction) {
                    $zipNote = if (Test-Path $local) { "Using zip." } else { "No zip found in PackSource — this app will be skipped." }
                    Write-Warning "$msg $zipNote"
                } else {
                    $ans = Read-Host "$msg Re-extract from zip? [Y/N]"
                    if ($ans -notmatch '^[Yy]$') { return $localDir }
                }
                if (Test-Path $local) { return $local }
            } else {
                Write-Warning "Pre-extracted $packDir version mismatch — falling back to zip"
            }
        }
        if (Test-Path $local) { return $local }
        throw "Pack not found in PackSource: $local"
    }

    $lBase    = if ($Version) { "$LDrivePath\$Version" } else { $LDrivePath }
    $lPath    = "$lBase\$packName"
    $lDirPath = "$lBase\$packDir"
    if (Test-Path $lDirPath -PathType Container) {
        $check = Test-PreExtractedDir $lDirPath $App -ZipPath $lPath
        if ($check -eq "ok")              { return $lDirPath }
        if ($check -like "count_mismatch:*") {
            $parts = $check.Split(':')
            $msg   = "Pre-extracted $packDir has $($parts[2]) files but zip has $($parts[1]) entries."
            if ($NoInteraction) {
                $zipNote = if (Test-Path $lPath) { "Using zip." } else { "No zip found on L: — will attempt GitHub download." }
                Write-Warning "$msg $zipNote"
            } else {
                $ans = Read-Host "$msg Re-extract from zip? [Y/N]"
                if ($ans -notmatch '^[Yy]$') { return $lDirPath }
            }
            if (Test-Path $lPath) { return $lPath }
        } else {
            Write-Warning "Pre-extracted $packDir version mismatch — falling back to zip"
        }
    }
    if (Test-Path $lPath) { return $lPath }

    $repoBase = "https://github.com/ETML-INF/standard-toolset/releases"
    $url = if ($Version) { "$repoBase/download/v$Version/$packName" } else { "$repoBase/latest/download/$packName" }
    try {
        Invoke-Download -Url $url -OutFile $tmpFile -Description $packName
        return $tmpFile
    } catch {
        throw "Cannot download $packName from L: or GitHub: $_"
    }
}

function Test-AppIntegrity {
    param([object]$App, [string]$toolsetdir)
    # Graceful degradation: old manifests without metadata are treated as healthy
    if (-not ($App.PSObject.Properties['fileCount'] -and $App.PSObject.Properties['totalSize'])) { return $true }
    # Check versioned dir first (real scoop layout), fall back to current\ (test/legacy layout)
    $versionDir = "$toolsetdir\scoop\apps\$($App.name)\$($App.version)"
    if (-not (Test-Path $versionDir -ErrorAction SilentlyContinue)) {
        $versionDir = "$toolsetdir\scoop\apps\$($App.name)\current"
    }
    if (-not (Test-Path $versionDir -ErrorAction SilentlyContinue)) { return $false }
    $files = @(Get-ChildItem $versionDir -Recurse -File -Force -ErrorAction SilentlyContinue)
    if ($files.Count -ne [int]$App.fileCount) { return $false }
    $size = ($files | Measure-Object -Property Length -Sum).Sum
    return $size -eq [long]$App.totalSize
}

function Remove-StaleVersionDirs {
    param([string]$toolsetdir, [string]$AppName, [string]$KeepVersion)
    $appDir = "$toolsetdir\scoop\apps\$AppName"
    if (-not (Test-Path $appDir -ErrorAction SilentlyContinue)) { return }
    Get-ChildItem $appDir -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne $KeepVersion -and $_.Name -ne 'current' } |
        ForEach-Object {
            Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            Write-Verbose "  Removed stale $AppName\$($_.Name)"
        }
}

function Get-AppDiff {
    param($Manifest, $LocalVersions)
    $names = $Manifest.apps | ForEach-Object { $_.name }
    return [pscustomobject]@{
        ToInstall = @($Manifest.apps | Where-Object { -not $LocalVersions.ContainsKey($_.name) })
        ToUpdate  = @($Manifest.apps | Where-Object { $LocalVersions.ContainsKey($_.name) -and $LocalVersions[$_.name] -ne $_.version })
        UpToDate  = @($Manifest.apps | Where-Object { $LocalVersions.ContainsKey($_.name) -and $LocalVersions[$_.name] -eq $_.version })
        Removed   = @($LocalVersions.Keys | Where-Object { $_ -notin $names })
    }
}

function Show-AppStatus {
    param($Diff, $LocalVersions)
    Write-Host ""
    Write-Host "Status:" -ForegroundColor Cyan
    foreach ($a in $Diff.UpToDate)  { Write-Host "  [=] $($a.name.PadRight(20)) $($a.version)  up to date" -ForegroundColor Green }
    foreach ($a in $Diff.ToUpdate)  { Write-Host "  [^] $($a.name.PadRight(20)) $($LocalVersions[$a.name]) -> $($a.version)" -ForegroundColor Yellow }
    foreach ($a in $Diff.ToInstall) { Write-Host "  [+] $($a.name.PadRight(20)) (not installed)" -ForegroundColor Cyan }
    foreach ($n in $Diff.Removed)   { Write-Host "  [X] $($n.PadRight(20)) $($LocalVersions[$n])  not in manifest" -ForegroundColor Red }
    Write-Host ""
}

function Install-Pack {
    param([string]$PackPath, [string]$toolsetdir)
    $appsDir = "$toolsetdir\scoop\apps"
    New-Item -ItemType Directory -Force -Path $appsDir | Out-Null
    if (Test-Path $PackPath -PathType Container) {
        # Pre-extracted pack (L: directory) — contents mirror zip root, copy directly into apps\
        Copy-Item "$PackPath\*" $appsDir -Recurse -Force
    } else {
        Expand-Archive -Path $PackPath -DestinationPath $appsDir -Force
    }
}

# ── entry point ────────────────────────────────────────────────────────────

if ($Command -eq "update") {

    # Update mode resolves the path directly — do not call Find-ToolsetDir
    # because fresh installs arrive here with a non-existent path, which would
    # cause Find-ToolsetDir to exit 1 before the directory can be created.
    $toolsetdir = $Path
    if (-not (Test-Path $toolsetdir)) {
        # Try the conventional alternative before creating at the given path
        if (Test-Path "D:\data\inf-toolset") {
            $toolsetdir = "D:\data\inf-toolset"
        } else {
            New-Item -ItemType Directory -Force -Path $toolsetdir | Out-Null
            Write-Host "Created $toolsetdir (fresh install)" -ForegroundColor Green
        }
    }

    Write-Host "Resolving manifest..." -ForegroundColor Yellow
    try {
        $manifest = Get-ReleaseManifest -ManifestSource $ManifestSource -Version $Version
    } catch {
        Write-Host $_ -ForegroundColor Red
        exit 1
    }
    Write-Host "Manifest: v$($manifest.version) ($($manifest.apps.Count) apps)" -ForegroundColor Green

    $localVersions = Get-LocalAppVersions -toolsetdir $toolsetdir
    $diff     = Get-AppDiff -Manifest $manifest -LocalVersions $localVersions
    $toInstall = $diff.ToInstall
    $toUpdate  = $diff.ToUpdate
    $removed   = $diff.Removed
    Show-AppStatus -Diff $diff -LocalVersions $localVersions

    # Removed app handling
    if ($removed.Count -gt 0) {
        if ($Clean) {
            foreach ($name in $removed) {
                Remove-Item "$toolsetdir\scoop\apps\$name" -Recurse -Force
                Write-Host "  Removed $name" -ForegroundColor DarkGray
            }
        } elseif ($NoInteraction) {
            Write-Warning "Orphaned apps detected: $($removed -join ', '). Use -Clean to remove them."
        } else {
            foreach ($name in $removed) {
                $answer = Read-Host "Remove $name (no longer in manifest)? [Y/N]"
                if ($answer -match '^[Yy]$') {
                    Remove-Item "$toolsetdir\scoop\apps\$name" -Recurse -Force
                    Write-Host "  Removed $name" -ForegroundColor DarkGray
                }
            }
        }
    }

    # Confirm and download
    $toDo = @($toInstall) + @($toUpdate)
    if ($toDo.Count -eq 0) {
        Write-Host "Everything is up to date." -ForegroundColor Green
    } else {
        if (-not $NoInteraction) {
            $answer = Read-Host "Proceed with $($toDo.Count) download(s)? [Y/N]"
            if ($answer -notmatch '^[Yy]$') { Write-Host "Cancelled."; exit 0 }
        }

        # Use the manifest's own version for pack URLs when no explicit -Version was given.
        # This avoids a race where a new release is published between manifest fetch and pack download.
        $effectiveVersion = if ([string]::IsNullOrEmpty($Version)) { $manifest.version } else { $Version }

        $failed = @()
        foreach ($app in $toDo) {
            Write-Host "  Downloading $($app.pack)..." -ForegroundColor Yellow -NoNewline
            try {
                $packPath = Get-Pack -App $app -PackSource $PackSource -Version $effectiveVersion -NoInteraction $NoInteraction
                Install-Pack -PackPath $packPath -toolsetdir $toolsetdir
                if ($packPath.StartsWith($env:TEMP)) { Remove-Item $packPath -Force -ErrorAction SilentlyContinue }
                Write-Host " done" -ForegroundColor Green
            } catch {
                Write-Host " FAILED" -ForegroundColor Red
                Write-Warning "  $_"
                $failed += $app.name
            }
        }

        if ($failed.Count -gt 0) {
            Write-Warning "The following apps may be incomplete: $($failed -join ', ')"
        }
    }

    # Persist manifest so Invoke-Activate can read paths2DropToEnableMultiUser at activation time
    $manifest | ConvertTo-Json -Depth 5 | Set-Content "$toolsetdir\release-manifest.json" -Encoding UTF8

    # Self-update toolset.ps1 in toolsetdir
    # Safe: PowerShell reads the entire script into memory before execution begins,
    # so overwriting the source file mid-run does not affect the current execution.
    $myPath = $PSCommandPath
    if ($myPath -and (Test-Path $myPath)) {
        Copy-Item $myPath "$toolsetdir\toolset.ps1" -Force
    }

    # Re-run activation (skipped for remote UNC paths — run toolset.ps1 locally on target to activate)
    Write-Host ""
    if ($toolsetdir.StartsWith("\\")) {
        Write-Host "Remote path — skipping activation. Run toolset.ps1 on the target machine to activate." -ForegroundColor Yellow
    } else {
        Write-Host "Running activation..." -ForegroundColor Cyan
        try {
            Invoke-Activate -toolsetdir $toolsetdir -NoInteraction $NoInteraction
        } catch {
            Write-Warning "Activation step failed (will complete on next run): $_"
        }
    }

} elseif ($Command -eq "status") {

    $toolsetdir = $Path
    Write-Host "Resolving manifest..." -ForegroundColor Yellow
    try {
        $manifest = Get-ReleaseManifest -ManifestSource $ManifestSource -Version $Version
    } catch {
        Write-Host $_ -ForegroundColor Red
        exit 1
    }
    Write-Host "Manifest: v$($manifest.version) ($($manifest.apps.Count) apps)" -ForegroundColor Green
    $localVersions = Get-LocalAppVersions -toolsetdir $toolsetdir
    $diff = Get-AppDiff -Manifest $manifest -LocalVersions $localVersions
    Show-AppStatus -Diff $diff -LocalVersions $localVersions
    $pending = $diff.ToInstall.Count + $diff.ToUpdate.Count
    if ($pending -gt 0) {
        Write-Host "$pending update(s) available. Run toolset.ps1 update to apply." -ForegroundColor Yellow
        exit 1
    }
    Write-Host "Everything is up to date." -ForegroundColor Green

} else {
    # Activate mode — if activation fails (broken install), fall back to update
    $toolsetdir = Find-ToolsetDir -StartPath $Path -NoInteraction $NoInteraction
    try {
        Invoke-Activate -toolsetdir $toolsetdir -NoInteraction $NoInteraction
    } catch {
        Write-Warning "Activation failed: $_"
        Write-Host "Broken install detected — switching to update mode..." -ForegroundColor Yellow
        if ($PSCommandPath) {
            $LASTEXITCODE = 0   # initialize; PowerShell scripts don't set $LASTEXITCODE
            & $PSCommandPath update -Path $toolsetdir -PackSource:$PackSource -ManifestSource:$ManifestSource -NoInteraction:$NoInteraction
            exit $LASTEXITCODE
        } else {
            Write-Error "Cannot repair automatically (script path unknown). Run: toolset.ps1 update -Path $toolsetdir"
            exit 1
        }
    }
}
