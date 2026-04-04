param(
    [Parameter(Position=0)][string]$Command = "",
    [string]$Path = "C:\inf-toolset",
    [switch]$NoInteraction,
    [switch]$Clean,
    [switch]$CleanPrivate,
    [switch]$ForceReinstall,
    [string]$Version = "",
    [string]$ManifestSource = "",
    [string]$PackSource = "",
    [string]$LDrivePath = "L:\toolset",
    [string]$LogFile = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if (-not [string]::IsNullOrEmpty($LogFile)) {
    Start-Transcript -Path $LogFile -Append -Force | Out-Null
}

# -- helpers ----------------------------------------------------------------

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
        # Expected  - toolset-managed node, all good
    } else {
        Write-Warning "Node.js found at unexpected location: $nodePath. This may conflict with the toolset."
    }
}

function Set-GitSafeDirectory {
    param([string]$gitconfigPath, [string]$toolsetdir)

    $add = "`tdirectory = $($toolsetdir -replace '\\', '/')/*"

    $content = if (Test-Path $gitconfigPath) { @(Get-Content $gitconfigPath) } else { @() }

    $safeMatch = $content | Select-String "^\[safe\]$" | Select-Object -First 1
    $safeIndex = if ($safeMatch) { $safeMatch.LineNumber - 1 } else { -1 }
    $dirIndex = if ($safeIndex -ge 0) {
        if (($safeIndex + 1) -gt ($content.Length - 1)) {
            -1
        } else {
            $searchRange  = $content[($safeIndex + 1)..($content.Length - 1)]
            $nextSection  = $searchRange | Select-String "^\[.+\]" | Select-Object -First 1
            $sectionEnd   = if ($nextSection) { $safeIndex + $nextSection.LineNumber } else { $content.Length }
            if (($safeIndex + 1) -ge $sectionEnd) {
                -1
            } else {
                $inSafe = $content[($safeIndex + 1)..($sectionEnd - 1)]
                $hit    = $inSafe | Select-String "^\s*directory\s*=" | Select-Object -First 1
                if ($hit) { $safeIndex + $hit.LineNumber } else { -1 }
            }
        }
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

    # If scoop\apps\scoop\current\ is a real folder (not a junction) AND versioned dirs exist,
    # rename it to its detected version before the bootstrap runs.  Leaving it as-is causes:
    #   - "access denied": Remove-Item -Force (no -Recurse) on a non-empty real dir (line below)
    #   - silent wrong-version: bin\scoop.ps1 found so bootstrap is skipped, old binary activated
    $scoopCurrentDir = "$scoopdir\apps\scoop\current"
    $scoopCurrentDirItem = Get-Item $scoopCurrentDir -Force -ErrorAction SilentlyContinue
    if ($scoopCurrentDirItem -and
        -not ($scoopCurrentDirItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -and
        $scoopCurrentDirItem.PSIsContainer) {
        $scoopVersionedDirs = Get-ChildItem "$scoopdir\apps\scoop" -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne 'current' }
        if ($scoopVersionedDirs) {
            $priorVer = $null
            if (Test-Path "$scoopCurrentDir\manifest.json" -ErrorAction SilentlyContinue) {
                try { $priorVer = (Get-Content "$scoopCurrentDir\manifest.json" -Raw | ConvertFrom-Json).version } catch {}
            }
            if (-not $priorVer) {
                $priorVer = Get-ScoopVersionFromBinary "$scoopCurrentDir\bin\scoop.ps1"
            }
            $priorVerName   = if ($priorVer) { $priorVer } else { 'unknown' }
            $priorVerTarget = "$scoopdir\apps\scoop\$priorVerName"
            Write-Host "  scoop current\ is a real folder - renaming to $priorVerName\ for junction migration..." -ForegroundColor Yellow
            if (-not (Test-Path $priorVerTarget -ErrorAction SilentlyContinue)) {
                Rename-Item -LiteralPath $scoopCurrentDir -NewName $priorVerName -ErrorAction SilentlyContinue
            } else {
                # Target versioned dir already exists (e.g. reinstall of same version or pack just
                # extracted) - rename to 'unknown' to preserve content without overwriting the pack.
                $unknownTarget = "$scoopdir\apps\scoop\unknown"
                if (-not (Test-Path $unknownTarget -ErrorAction SilentlyContinue)) {
                    Rename-Item -LiteralPath $scoopCurrentDir -NewName 'unknown' -ErrorAction SilentlyContinue
                } else {
                    Remove-DirSafe $scoopCurrentDir
                }
            }
        }
        # Sanity check: if current\ is still a real folder after all rename/remove attempts,
        # the migration silently failed (locked file?).  bin\scoop.ps1 may still be found
        # inside it, causing the bootstrap below to be skipped and the old binary to be used.
        if (Test-Path $scoopCurrentDir -ErrorAction SilentlyContinue) {
            if (-not (Test-IsReparsePoint $scoopCurrentDir)) {
                Write-Warning "Could not vacate $scoopCurrentDir (rename/remove failed) - activation may use wrong scoop version"
            }
        }
    }

    $scoopPs1 = "$scoopdir\apps\scoop\current\bin\scoop.ps1"
    if (-not (Test-Path $scoopPs1 -ErrorAction SilentlyContinue)) {
        # current\ junction missing - fresh install or scoop update.
        # Find the versioned dir and create the junction so scoop reset * can run.
        $scoopVerDir = Get-ChildItem "$scoopdir\apps\scoop" -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne 'current' } |
            Sort-Object Name -Descending |
            Select-Object -First 1
        if ($scoopVerDir) {
            Write-Host "Bootstrapping scoop current\ junction ($($scoopVerDir.Name))..." -ForegroundColor Green
            $junctionPath = "$scoopdir\apps\scoop\current"
            if (Test-IsReparsePoint $junctionPath) {
                Remove-Junction $junctionPath
                if (Test-IsReparsePoint $junctionPath) {
                    Write-Warning "Could not remove scoop bootstrap junction '$junctionPath' - activation may be incomplete"
                }
            } elseif (Test-Path $junctionPath) {
                # Real (non-empty) dir left by a failed Rename-Item - use Remove-DirSafe so
                # PS5.1 doesn't throw "directory not empty" from Remove-Item -Force (no -Recurse).
                Remove-DirSafe $junctionPath
            }
            if (-not (Test-IsReparsePoint $junctionPath) -and -not (Test-Path $junctionPath)) {
                New-Item -ItemType Junction -Path $junctionPath -Value $scoopVerDir.FullName | Out-Null
            }
        }
    }
    # Pre-update current\ junctions from the release manifest before scoop reset *.
    # scoop reset reads the version from current\manifest.json; if current\ still points
    # to the old version (because the old dir could not be fully removed due to locked
    # files), scoop would re-link to the old version even though the new versioned dir
    # was just extracted.  Pointing current\ at the new version first fixes that.
    $localManifestPath = Join-Path $toolsetdir "release-manifest.json"
    $mf = if (Test-Path $localManifestPath -ErrorAction SilentlyContinue) {
        Get-Content $localManifestPath -Raw | ConvertFrom-Json
    } else { $null }
    if ($mf) {
        foreach ($appEntry in $mf.apps) {
            # version may be absent on legacy/partial manifest entries - skip them
            if (-not $appEntry.PSObject.Properties['version']) { continue }
            $appDir     = "$scoopdir\apps\$($appEntry.name)"
            $verDir     = "$appDir\$($appEntry.version)"
            $jPath      = "$appDir\current"
            # Use Test-IsReparsePoint (raw attribute read) so broken junctions (target
            # deleted/renamed) are detected correctly -- Get-Item returns $null for broken
            # junctions in PS5.1 making the Attributes check unreliable.
            $isJunction = Test-IsReparsePoint $jPath
            $exists     = $isJunction -or (Test-Path $jPath -ErrorAction SilentlyContinue)
            if ($exists -and -not $isJunction) {
                # current\ is a real folder - rename to its detected version so a proper junction
                # can be created.  Without this the new versioned dir is silently ignored: scoop
                # reset reads the old manifest and re-links to the old version.
                $priorVerInDir = $null
                if (Test-Path "$jPath\manifest.json" -ErrorAction SilentlyContinue) {
                    try { $priorVerInDir = (Get-Content "$jPath\manifest.json" -Raw | ConvertFrom-Json).version } catch {}
                }
                $priorVerDirName = if ($priorVerInDir) { $priorVerInDir } else { 'unknown' }
                $priorVerDirPath = "$appDir\$priorVerDirName"
                Write-Host "  $($appEntry.name) current\ is a real folder - renaming to $priorVerDirName\" -ForegroundColor Yellow
                if (-not (Test-Path $priorVerDirPath -ErrorAction SilentlyContinue)) {
                    Rename-Item -LiteralPath $jPath -NewName $priorVerDirName -ErrorAction SilentlyContinue
                } else {
                    # Target already exists (reinstall or pack just extracted) - preserve as 'unknown'
                    $unknownAppDir = "$appDir\unknown"
                    if (-not (Test-Path $unknownAppDir -ErrorAction SilentlyContinue)) {
                        Rename-Item -LiteralPath $jPath -NewName 'unknown' -ErrorAction SilentlyContinue
                    } else {
                        Remove-DirSafe $jPath
                    }
                }
                if (Test-Path $jPath -ErrorAction SilentlyContinue) {
                    Write-Warning "$($appEntry.name): could not vacate current\ (rename/remove failed) - junction not updated, version may be stale"
                    continue
                }
                # If the rename produced the exact versioned dir we need, point $verDir at it
                if ($priorVerDirName -eq $appEntry.version) { $verDir = $priorVerDirPath }
            }
            # Nothing to point current\ at - versioned dir not yet extracted
            if (-not (Test-Path $verDir -ErrorAction SilentlyContinue)) { continue }
            if ($isJunction) {
                Remove-Junction $jPath
                if (Test-IsReparsePoint $jPath) {
                    Write-Warning "Could not remove junction '$jPath' (still present after rmdir) - skipping '$($appEntry.name)'"
                    continue
                }
            }
            try {
                New-Item -ItemType Junction -Path $jPath -Value $verDir -ErrorAction Stop | Out-Null
            } catch {
                Write-Warning "Could not create junction '$jPath' -> '$verDir': $_"
            }
        }
    }
    if (Test-Path $scoopPs1 -ErrorAction SilentlyContinue) {
        Write-Host "Resetting scoop (restores current junctions)..." -ForegroundColor Green
        & $scoopPs1 reset *
    } else {
        if (-not (Test-Path $scoopdir -ErrorAction SilentlyContinue)) {
            throw "scoop.ps1 not found at $scoopPs1 - broken install detected (run update to repair)"
        }
        Write-Warning "scoop.ps1 not found at $scoopPs1 - skipping junction reset (will complete on next activation)"
    }

    # App shortcuts declared in manifest (shortcuts field: array of [exePath, displayName] pairs)
    # Mirrors scoop's own shortcuts field; exePath is relative to current\.
    # Shortcuts are recreated on every activation (idempotent).
    # WScript.Shell is not available in all environments (e.g. NanoServer containers);
    # each shortcut creation is individually guarded so activation never fails.
    if ($mf) {
        $startMenuScoop = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Scoop Apps"
        foreach ($appEntry in $mf.apps) {
            if (-not $appEntry.PSObject.Properties['shortcuts']) { continue }
            foreach ($pair in $appEntry.shortcuts) {
                $exeRel      = $pair[0]
                $displayName = $pair[1]
                $exeFull     = "$scoopdir\apps\$($appEntry.name)\current\$exeRel"
                $lnkPath     = "$startMenuScoop\$displayName.lnk"
                if (-not (Test-Path $exeFull -ErrorAction SilentlyContinue)) {
                    Write-Warning "Shortcut target not found, skipping: $exeFull"
                    continue
                }
                try {
                    $sc = (New-Object -ComObject WScript.Shell).CreateShortcut($lnkPath)
                    New-Item -ItemType Directory -Force -Path $startMenuScoop | Out-Null
                    $sc.TargetPath = $exeFull
                    $sc.Save()
                    Write-Host "  Shortcut: $displayName" -ForegroundColor DarkGray
                } catch {
                    Write-Warning "Could not create shortcut '$displayName': $_"
                }
            }
        }
    }

    # Drop paths2DropToEnableMultiUser from each app's current\ dir so apps fall back to
    # per-user %APPDATA% instead of the shared portable-mode location.
    # Scoop's persist creates junctions: app\current\<path> -> scoop\persist\<app>\<path>.
    # Deleting the junction leaves persist data intact but forces apps to use per-user dirs.
    Write-Host "Configuring per-user app settings..." -ForegroundColor Green
    $dropped = 0
    if ($mf) {
        foreach ($appEntry in $mf.apps) {
            if (-not $appEntry.PSObject.Properties['paths2DropToEnableMultiUser']) { continue }
            foreach ($rel in $appEntry.paths2DropToEnableMultiUser) {
                $target = Join-Path "$scoopdir\apps\$($appEntry.name)\current" $rel
                $item = Get-Item $target -Force -ErrorAction SilentlyContinue
                if (-not $item) { continue }
                try {
                    if ($item.PSIsContainer) {
                        # Junction link -- Remove-Junction removes only the reparse point
                        # entry, never the persist target, even if broken or non-empty.
                        Remove-Junction $item.FullName
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
        Write-Host "  No release manifest found  - skipping portable path cleanup." -ForegroundColor DarkGray
    }

    Write-Host "Updating scoop shims for path $toolsetdir..." -ForegroundColor Green
    $shimpath = "$scoopdir\shims"
    @("$shimpath\scoop","$shimpath\scoop.cmd","$shimpath\scoop.ps1") | ForEach-Object {
        if (-not (Test-Path $_ -ErrorAction SilentlyContinue)) { return }   # absent on partial/interrupted install
        $c = Get-Content $_ -Raw
        $newContent = [System.Text.RegularExpressions.Regex]::Replace(
            $c, '[A-Z]:.*?\\scoop\\',
            [System.Text.RegularExpressions.MatchEvaluator]{ param($m) "$scoopdir\" }
        )
        [System.IO.File]::WriteAllText($_, $newContent, [System.Text.UTF8Encoding]::new($false))
    }

    Write-Host "Fixing reg file paths..." -ForegroundColor Green
    Get-ChildItem "$scoopdir\apps\*\current\*.reg" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        $c = Get-Content $_ -Raw
        $regReplacement = "$($scoopdir -replace '\\','\\')\"
        $newContent = [System.Text.RegularExpressions.Regex]::Replace(
            $c, '[A-Z]:.*?\\\\scoop\\\\',
            [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $regReplacement }
        )
        $unicodeEncoding = [System.Text.UnicodeEncoding]::new($false, $true)  # LE with BOM, required by reg import
        [System.IO.File]::WriteAllText($_, $newContent, $unicodeEncoding)
    }

    # VSCode context menu  - use direct path, no dependency on scoop being on PATH
    $vsCodeReg = "$scoopdir\apps\vscode\current\install-context.reg"
    if (Test-Path $vsCodeReg) {
        try {
            & reg import $vsCodeReg
            Write-Output "VSCode context menu added/updated"
        } catch {
            Write-Warning "VSCode context menu update failed: $_"
        }
    }

    # Git safe.directory  - inline logic, no external script dependency
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Set-GitSafeDirectory -gitconfigPath "$env:USERPROFILE\.gitconfig" -toolsetdir $toolsetdir
        Write-Output "Git safe.directory configured"
    } else {
        Write-Host "Git not installed. Re-run toolset.ps1 after installing git." -ForegroundColor Red
    }

    # Admin Node.js detection
    Invoke-NodeCheck -toolsetdir $toolsetdir -NoInteraction $NoInteraction

    # Fix CI build paths embedded in installed apps
    # During the GitHub Actions build, scoop embeds the runner's persist path into text config/script
    # files (e.g. nodejs-lts npmrc). We replace that CI path with the user's actual persist dir.
    # Apps opt in via patchBuildPaths:true in apps.json.
    # nodejs-lts is always patched regardless of the manifest flag: it was the first app affected
    # (PR #21) and old manifests predate the patchBuildPaths field, so we keep it unconditional
    # for backward compat with any existing install.
    #
    # Default CI persist base = real GitHub Actions Windows runner path baked in at build time.
    # buildScoopPersistDir in the release manifest overrides this for test injection only.
    if ($mf) {
    $buildPersistBase = if ($mf.PSObject.Properties['buildScoopPersistDir']) {
        $mf.buildScoopPersistDir
    } else {
        'D:\a\standard-toolset\standard-toolset\build\scoop\persist'
    }
    # Text-like extensions that may embed absolute paths - skip binaries for speed and safety
    $textExts = @('.js','.mjs','.cjs','.json','.cmd','.ps1','.bat','.npmrc','.ini','.cfg','.txt','.rc')

    foreach ($appEntry in $mf.apps) {
        $shouldPatch = ($appEntry.name -eq 'nodejs-lts') -or
                       ($appEntry.PSObject.Properties['patchBuildPaths'] -and $appEntry.patchBuildPaths -eq $true)
        if (-not $shouldPatch) { continue }

        $appName = $appEntry.name
        if (-not (Test-Path "$scoopdir\apps\$appName\current\manifest.json")) { continue }

        Write-Host "Fixing $appName paths..." -ForegroundColor Green
        $version = (Get-Content "$scoopdir\apps\$appName\current\manifest.json" | ConvertFrom-Json).version

        $oldPattern = [regex]::Escape($buildPersistBase + '\' + $appName)
        $newPersist = "$scoopdir\persist\$appName"

        $scanRoots = @(
            "$scoopdir\apps\$appName\$version",  # full versioned install
            "$scoopdir\persist\$appName"          # persist dir
        )
        foreach ($root in $scanRoots) {
            if (-not (Test-Path $root)) { continue }
            # Use .NET enumeration for performance on large trees (node_modules has thousands of files)
            try { $files = [System.IO.Directory]::EnumerateFiles($root, '*', [System.IO.SearchOption]::AllDirectories) }
            catch { continue }
            foreach ($file in $files) {
                if ($file -like '*\node_modules\*') { continue }  # skip large dep trees
                $ext = [System.IO.Path]::GetExtension($file)
                if (-not $ext -or $textExts -notcontains $ext.ToLowerInvariant()) { continue }
                $c = Get-Content $file -Raw -ErrorAction SilentlyContinue
                if ($c -and $c -match $oldPattern) {
                    $updated = $c -replace $oldPattern, $newPersist
                    [System.IO.File]::WriteAllText($file, $updated, [System.Text.UTF8Encoding]::new($false))
                }
            }
        }
    } # end foreach ($appEntry in $mf.apps)
    } # end if ($mf) patchBuildPaths

    # Desktop shortcut
    $scoopShortcutsFolder = "$env:USERPROFILE\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Scoop Apps\"
    if (Test-Path $scoopShortcutsFolder) {
        $shortcutPath = [Environment]::GetFolderPath("Desktop") + "\$(Split-Path $toolsetdir -Leaf).lnk"
        if (Test-Path $shortcutPath) { Remove-Item $shortcutPath -Force }
        try {
            $shell = New-Object -ComObject WScript.Shell
            $sc = $shell.CreateShortcut($shortcutPath)
            $sc.TargetPath = $scoopShortcutsFolder
            $sc.IconLocation = "C:\Windows\System32\shell32.dll,12"
            $sc.Save()
            Write-Output "Shortcut created: $shortcutPath"
        } catch {
            Write-Warning "Could not create desktop shortcut: $_"
        }
    }

    # Grant all users full control  - best effort (requires elevation; silent if unavailable)
    Write-Host "Setting permissions for all users..." -ForegroundColor Green
    & icacls $toolsetdir /grant "Users:(OI)(CI)M" /T /C /Q 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Permissions set." -ForegroundColor Green
    } else {
        Write-Verbose "icacls returned $LASTEXITCODE  - run as administrator to set permissions"
    }
}

# -- manifest + pack helpers (used by update mode) -------------------------

function Add-ZipType {
    # Loads System.IO.Compression.FileSystem if not already available.
    # Required on PS5.1 (Win10+, .NET Framework 4.5+). No-op on PS7.
    if (-not ([System.Management.Automation.PSTypeName]'System.IO.Compression.ZipFile').Type) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
    }
}

function Expand-ZipWithProgress {
    # Replaces Expand-Archive. Extracts a zip entry-by-entry using ZipFile so we
    # can display a live progress bar. Overwrites existing files.
    param([string]$ZipPath, [string]$DestinationPath)
    Add-ZipType
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $entries = @($zip.Entries)
        $total   = $entries.Count
        $i       = 0
        foreach ($entry in $entries) {
            $i++
            $pct    = [int](($i / [Math]::Max(1, $total)) * 20)
            $filled = if ($pct -ge 20) { '=' * 20 } else { '=' * $pct + '>' + ' ' * (19 - $pct) }
            Write-Host ("`r    Extracting... $i / $total  [$filled]") -NoNewline

            $destRelative = $entry.FullName -replace '/', '\'
            $destFile     = Join-Path $DestinationPath $destRelative

            if ($entry.Name -eq '') {
                New-Item -ItemType Directory -Force -Path $destFile | Out-Null
                continue
            }
            $destDir = Split-Path $destFile -Parent
            if (-not (Test-Path $destDir -PathType Container)) {
                New-Item -ItemType Directory -Force -Path $destDir | Out-Null
            }
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destFile, $true)
        }
        Write-Host ""
    } finally {
        $zip.Dispose()
    }
}

function Copy-WithProgress {
    param([string]$Source, [string]$Destination, [string]$Label = "")
    $srcSize = (Get-Item $Source).Length
    $bufSize = 1MB
    $buf     = [byte[]]::new($bufSize)
    $src     = [System.IO.File]::OpenRead($Source)
    try {
        $dst = [System.IO.File]::Create($Destination)
        try {
            $copied = 0
            $sw     = [System.Diagnostics.Stopwatch]::StartNew()
            while (($read = $src.Read($buf, 0, $bufSize)) -gt 0) {
                $dst.Write($buf, 0, $read)
                $copied   += $read
                $mbCopied  = [math]::Round($copied / 1MB, 1)
                $mbTotal   = [math]::Round($srcSize / 1MB, 1)
                $pct       = [int](($copied / [Math]::Max(1, $srcSize)) * 20)
                $filled    = if ($pct -ge 20) { '=' * 20 } else { '=' * $pct + '>' + ' ' * (19 - $pct) }
                $elapsed   = $sw.Elapsed.TotalSeconds
                $speedStr  = if ($elapsed -gt 0) {
                    $speed = $copied / $elapsed / 1MB
                    if ($speed -ge 1000) { "{0:N0} GB/s" -f ($speed / 1000) }
                    else                 { "{0:N1} MB/s" -f $speed }
                } else { "" }
                Write-Host ("`r    Copying...   $mbCopied / $mbTotal MB  [$filled]  $speedStr  ") -NoNewline
            }
            Write-Host ""
        } finally { $dst.Dispose() }
    } catch {
        Write-Host ""
        throw
    } finally { $src.Dispose() }
}

function Invoke-Download {
    param(
        [string]$Url,
        [string]$OutFile,
        [string]$Description = ""
    )
    $label = if ($Description) { $Description } else { Split-Path $Url -Leaf }

    # Try BITS first  - resumable, progress display, handles large packs well.
    # Falls through silently if BITS is unavailable (containers, PS remoting, etc.)
    $job = $null
    try {
        Import-Module BitsTransfer -ErrorAction Stop
        $job         = Start-BitsTransfer -Source $Url -Destination $OutFile `
                           -Asynchronous -DisplayName $label -ErrorAction Stop
        $timeout     = (Get-Date).AddMinutes(75)
        $lastBytes   = -1
        $staleStart  = $null
        $stallSecs   = 60
        do {
            Start-Sleep -Seconds 3
            $progress = Get-BitsTransfer -JobId $job.JobId
            if ($progress.BytesTransferred -gt 0 -and $progress.BytesTotal -gt 0) {
                $pct      = [math]::Round(($progress.BytesTransferred / $progress.BytesTotal) * 100, 1)
                $mb       = [math]::Round($progress.BytesTransferred / 1MB, 1)
                $tot      = [math]::Round($progress.BytesTotal / 1MB, 1)
                $p        = [int]($pct / 5)
                $dlFilled = if ($p -ge 20) { '=' * 20 } else { '=' * $p + '>' + ' ' * (19 - $p) }
                Write-Host ("`r    Downloading...  $mb / $tot MB  [$dlFilled]  ") -NoNewline
            }
            if ($progress.BytesTransferred -ne $lastBytes) {
                $lastBytes  = $progress.BytesTransferred
                $staleStart = $null
            } else {
                if (-not $staleStart) { $staleStart = Get-Date }
                elseif (((Get-Date) - $staleStart).TotalSeconds -ge $stallSecs) {
                    Remove-BitsTransfer -BitsJob $job
                    $job = $null
                    throw "BITS stalled for ${stallSecs}s - falling back to Invoke-WebRequest"
                }
            }
            if ((Get-Date) -gt $timeout) {
                Remove-BitsTransfer -BitsJob $job
                $job = $null
                throw "BITS timeout after 75 minutes"
            }
        } while ($progress.JobState -in @("Transferring", "Connecting", "TransientError"))
        Write-Host ""
        if ($progress.JobState -eq "Transferred") {
            Complete-BitsTransfer -BitsJob $job
            $job = $null
            return
        }
        Remove-BitsTransfer -BitsJob $job
        $job = $null
        throw "BITS ended in state: $($progress.JobState)  - $($progress.ErrorDescription)"
    } catch [System.Management.Automation.PipelineStoppedException] {
        # Ctrl+C: clean up the BITS job so it doesn't keep running in the background, then stop.
        Write-Host ""
        if ($job) { try { Remove-BitsTransfer -BitsJob $job -ErrorAction SilentlyContinue } catch {} }
        throw
    } catch {
        Write-Host ""  # end any open progress line before the warning
        if ($job) { try { Remove-BitsTransfer -BitsJob $job -ErrorAction SilentlyContinue } catch {} }
        $msg = "$_"
        if ($msg -match 'stalled|timeout') {
            Write-Warning "BITS: $msg - retrying with Invoke-WebRequest"
        } else {
            Write-Verbose "BITS unavailable for $label : $msg - falling back to Invoke-WebRequest"
        }
    }

    # Fallback: works in containers and environments without BITS.
    # -UseBasicParsing bypasses the IE engine on Windows PS 5.1 (Server Core, fresh installs).
    # Retries 3 times for transient failures (EOF, connection reset, etc.).
    $iwrArgs    = @{ Uri = $Url; OutFile = $OutFile; ErrorAction = 'Stop' }
    if ($PSVersionTable.PSVersion.Major -lt 6) { $iwrArgs['UseBasicParsing'] = $true }
    $attempts   = 0
    $maxAttempts = 3
    while ($attempts -lt $maxAttempts) {
        $attempts++
        try { Invoke-WebRequest @iwrArgs; break } catch {
            if ($attempts -ge $maxAttempts) { throw }
            Write-Verbose "IWR attempt $attempts failed for $label : $_ - retrying in 5s"
            Remove-Item $OutFile -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 5
        }
    }
}

function Merge-PrivateApps {
    <#
    .SYNOPSIS
        Merges private app entries from L:\toolset\private-apps.json into a manifest object.
    .DESCRIPTION
        Private apps are defined in private-apps.json (never committed to git) with a
        'localPack' field pointing to a zip on L:\.  They are included in the release
        manifest when build.ps1 runs with L:\ access, but CI builds (no L:\ access) omit
        them.  This function ensures private apps are always present when L:\ is reachable,
        regardless of whether the manifest was built with or without L:\ access.
        Apps already present in the manifest (by name) are not duplicated.
    .PARAMETER Manifest
        PSCustomObject returned by ConvertFrom-Json for the release manifest.
    .PARAMETER LDrivePath
        Root of the local toolset network drive.  Defaults to L:\toolset.
    .OUTPUTS
        The same manifest object, with private apps appended to the apps array.
    #>
    param([object]$Manifest, [string]$LDrivePath = "L:\toolset")
    $privateAppsPath = "$LDrivePath\private-apps.json"
    if (-not (Test-Path $privateAppsPath -ErrorAction SilentlyContinue)) { return $Manifest }
    try {
        $privateApps  = Get-Content $privateAppsPath -Raw | ConvertFrom-Json
        $existingNames = @($Manifest.apps | ForEach-Object { $_.name })
        $added = 0
        foreach ($pa in $privateApps) {
            if (-not $pa.PSObject.Properties['name'])      { continue }
            if ($pa.name -in $existingNames)               { continue }
            if (-not $pa.PSObject.Properties['localPack']) { continue }
            $lpFile = Split-Path $pa.localPack -Leaf
            $lpVer  = if ($pa.PSObject.Properties['version']) { $pa.version } `
                      elseif ($lpFile -match '-(\d[\d.]*)\.zip$') { $Matches[1] } `
                      else { 'unknown' }
            $entry = [pscustomobject]@{ name = $pa.name; version = $lpVer; pack = $lpFile; packUrl = $pa.localPack }
            $Manifest.apps = @($Manifest.apps) + @($entry)
            $existingNames += $pa.name
            $added++
        }
        if ($added -gt 0) { Write-Host "  $added private app(s) merged from $privateAppsPath" -ForegroundColor DarkGray }
    } catch {
        Write-Warning "Could not load private apps from $privateAppsPath : $_"
    }
    return $Manifest
}

function Get-ReleaseManifest {
    param(
        [string]$ManifestSource,
        [string]$Version,
        [string]$LDrivePath = "L:\toolset",
        [bool]$NoInteraction = $false
    )
    if ($ManifestSource -and (Test-Path $ManifestSource)) {
        Write-Host "  Manifest source: $ManifestSource" -ForegroundColor DarkGray
        return Merge-PrivateApps (Get-Content $ManifestSource -Raw | ConvertFrom-Json) $LDrivePath
    }

    # Primary source is always L: (internal network drive)  - fast, no auth, works offline from Internet.
    # GitHub is a fallback for machines not on the school network (home use, external sites, etc.).
    # Falling back silently to GitHub in non-interactive mode would surprise an admin who expects
    # the internal version; requiring confirmation keeps the behaviour predictable and auditable.
    $repoBase = "https://github.com/ETML-INF/standard-toolset/releases"
    $lManifest = if ([string]::IsNullOrEmpty($Version)) {
        "$LDrivePath\release-manifest.json"
    } else {
        "$LDrivePath\$Version\release-manifest.json"
    }

    if (Test-Path $lManifest) {
        $manifest = Get-Content $lManifest -Raw | ConvertFrom-Json
        Write-Host "  Manifest source: LAN ($lManifest)" -ForegroundColor DarkGray

        # Non-blocking freshness check: compare the L: version against the latest on GitHub.
        # Only done for the unversioned (latest) case  - a pinned -Version is intentional
        # and comparing it against latest would always warn by design.
        # Uses a short timeout so a slow or unreachable GitHub never stalls the install.
        # Any failure is silently swallowed: the L: manifest is authoritative, the check
        # is advisory only.
        if ([string]::IsNullOrEmpty($Version)) {
            try {
                $ghManifest = Invoke-RestMethod "$repoBase/latest/download/release-manifest.json" `
                                  -TimeoutSec 5 -ErrorAction Stop
                if ($ghManifest.version -ne $manifest.version) {
                    Write-Warning "LAN has v$($manifest.version) but GitHub has v$($ghManifest.version). Run offline-download.ps1 to refresh the network drive."
                    if (-not $NoInteraction) {
                        $answer = Read-Host "Use GitHub version v$($ghManifest.version) now instead? [Y/n]"
                        if ($answer -notmatch '^[Nn]') {
                            Write-Host "  Manifest source: remote/GitHub" -ForegroundColor DarkGray
                            return Merge-PrivateApps $ghManifest $LDrivePath
                        }
                    }
                }
            } catch { Write-Verbose "GitHub freshness check skipped: $_" }
        }

        return Merge-PrivateApps $manifest $LDrivePath
    }

    # L: not available  - decide whether to try GitHub
    if ($NoInteraction) {
        throw "LAN ($LDrivePath) is not available and -NoInteraction prevents falling back to GitHub. Mount the drive or pass -ManifestSource explicitly."
    }
    $answer = Read-Host "LAN ($LDrivePath) is not available. Download manifest from GitHub instead? [Y/n]"
    if ($answer -match '^[Nn]') {
        throw "Aborted by user. Mount $LDrivePath or pass -ManifestSource explicitly."
    }

    $url = if ([string]::IsNullOrEmpty($Version)) {
        "$repoBase/latest/download/release-manifest.json"
    } else {
        "$repoBase/download/v$Version/release-manifest.json"
    }
    try {
        $result = Merge-PrivateApps (Invoke-RestMethod $url -ErrorAction Stop) $LDrivePath
        Write-Host "  Manifest source: remote/GitHub" -ForegroundColor DarkGray
        return $result
    } catch {
        throw "GitHub manifest fetch failed: $_"
    }
}

function Get-ScoopVersionFromBinary {
    <#
    .SYNOPSIS
        Tries to determine the scoop version by invoking its PowerShell script.
    .DESCRIPTION
        Calls scoop.ps1 --version in a child process and parses the semver from the output.
        Returns the version string, or $null if it cannot be determined.
    .PARAMETER ScoopBin
        Full path to scoop.ps1 (e.g. scoop\apps\scoop\current\bin\scoop.ps1).
    .OUTPUTS
        Version string, or $null.
    #>
    param([string]$ScoopBin)
    if (-not (Test-Path $ScoopBin -ErrorAction SilentlyContinue)) { return $null }
    try {
        $raw = & powershell.exe -NoProfile -NonInteractive -Command `
            "& '$ScoopBin' --version 2>&1" 2>&1 |
            Out-String
        # Scoop outputs something like "v0.5.3 - released at ..." or just "0.5.3"
        if ($raw -match '\bv?(\d+\.\d+\.\d+)\b') { return $Matches[1] }
    } catch { }
    return $null
}

function Get-LocalAppVersions {
    <#
    .SYNOPSIS
        Returns a hashtable of installed app name -> version for all apps under scoop\apps\.
    .DESCRIPTION
        Always checks versioned subdirectories first (highest name, descending sort),
        so that a partially-updated installation -- where a new version directory has been
        extracted but the current\ junction still points to the old version -- is reported
        correctly and does not trigger a needless re-download.

        Consistency note: Test-AppIntegrity also checks the versioned directory by
        $App.version first, so the integrity check validates exactly the same directory
        that this function reports. Incomplete version directories are therefore caught
        by the ToRepair path rather than being silently skipped.

        Falls back to current\manifest.json when no versioned subdirectory exists.
        When manifest.json is absent but a versioned dir exists, the dir name is used as
        the version (scoop itself is installed without a manifest.json in its versioned dir).
        When only a real current\ dir exists (not a junction) with no manifest.json, the
        scoop binary is invoked to detect the version; "?" is returned if all else fails.
    .PARAMETER toolsetdir
        Root of the toolset installation (contains scoop\).
    .OUTPUTS
        Hashtable of app name -> version string.  May contain "?" for apps whose version
        could not be determined but whose directory clearly exists.
    #>
    param([string]$toolsetdir)
    $result = @{}
    $appsDir = "$toolsetdir\scoop\apps"
    if (-not (Test-Path $appsDir)) { return $result }
    Get-ChildItem $appsDir -Directory | ForEach-Object {
        $appDir  = $_.FullName
        $appName = $_.Name
        # Prefer the highest versioned dir over current\ (which may still point to the
        # previous version while the new version dir is already fully extracted).
        $vDir = Get-ChildItem $appDir -Directory |
                    Where-Object { $_.Name -ne 'current' } |
                    Sort-Object Name -Descending |
                    Select-Object -First 1
        if ($vDir) {
            $mPath = "$($vDir.FullName)\manifest.json"
            if (Test-Path $mPath) {
                try { $result[$appName] = (Get-Content $mPath -Raw | ConvertFrom-Json).version } catch { }
            } else {
                # manifest.json absent -- scoop itself does not always ship one.
                # The versioned dir name IS the version string (scoop convention).
                $result[$appName] = $vDir.Name
            }
        } else {
            # No versioned dir -- check current\ (may be a junction or a real dir).
            $currentDir = "$appDir\current"
            if (-not (Test-Path $currentDir -ErrorAction SilentlyContinue)) { return }
            $mPath = "$currentDir\manifest.json"
            if (Test-Path $mPath) {
                try { $result[$appName] = (Get-Content $mPath -Raw | ConvertFrom-Json).version } catch { }
            } else {
                # current\ is a real dir with no manifest.json (e.g. manually-renamed
                # versioned dir, or a pre-existing scoop installation).
                $isJunction = (Get-Item $currentDir -ErrorAction SilentlyContinue).Attributes `
                    -band [System.IO.FileAttributes]::ReparsePoint
                if (-not $isJunction) {
                    # Try to ask the binary directly (works for scoop).
                    $ver = Get-ScoopVersionFromBinary "$currentDir\bin\scoop.ps1"
                    $result[$appName] = if ($ver) { $ver } else { '?' }
                }
            }
        }
    }
    return $result
}

function Get-ZipEntryCount {
    # Reads only the zip central directory (metadata)  - no extraction.
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

function Resolve-ToArchives {
    <#
    .SYNOPSIS
        Moves a downloaded pack zip into the local archives cache directory.
    .DESCRIPTION
        Called after every successful L:\ or GitHub pack download to populate the
        local archives cache.  Uses Move-Item (not Copy-Item) to avoid a second copy
        on disk.  Returns the new archives path on success, or the original path if
        the move fails (so the install can still proceed from TEMP).
        No-op when ArchivesDir is empty - returns TmpPath unchanged.
    #>
    param([string]$TmpPath, [string]$ArchivesDir, [string]$PackName)
    if ([string]::IsNullOrEmpty($ArchivesDir)) { return $TmpPath }
    $dest = Join-Path $ArchivesDir $PackName
    try {
        $null = New-Item -ItemType Directory -Force -Path $ArchivesDir
        Move-Item $TmpPath $dest -Force -ErrorAction Stop
        return $dest
    } catch {
        Write-Warning "Archives cache write skipped: $_"
        return $TmpPath
    }
}

function Get-Pack {
    param(
        [object]$App,
        [string]$PackSource,
        [string]$Version,
        [bool]$NoInteraction = $false,
        [string]$LDrivePath = "L:\toolset",
        [string]$ArchivesDir = ""
    )
    $packName = $App.pack
    $packDir  = $packName -replace '\.zip$', ''   # pre-extracted directory name
    $tmpFile  = "$env:TEMP\$packName"

    # Archives cache hit: return the cached zip directly (no TEMP copy needed)
    if (-not [string]::IsNullOrEmpty($ArchivesDir)) {
        $cachedPath = Join-Path $ArchivesDir $packName
        if (Test-Path $cachedPath) {
            Write-Host " [cache]" -ForegroundColor DarkGray
            return $cachedPath
        }
    }

    # Private apps carry a local-path packUrl (set by Merge-PrivateApps).
    # Resolve them immediately before any PackSource check so they are never
    # rejected with "Pack not found in PackSource".
    $isLocalPackUrl = $App.PSObject.Properties['packUrl'] -and $App.packUrl -and
                      ($App.packUrl -match '^[A-Za-z]:\\' -or $App.packUrl -match '^\\\\')
    if ($isLocalPackUrl) {
        if (-not (Test-Path $App.packUrl)) {
            throw "Local pack not accessible: $($App.packUrl)"
        }
        Write-Host " [L:\]" -ForegroundColor DarkGray
        Copy-WithProgress $App.packUrl $tmpFile $packName
        $tmpFile = Resolve-ToArchives $tmpFile $ArchivesDir $packName
        return $tmpFile
    }

    if ($PackSource) {
        $local    = Join-Path $PackSource $packName
        $localDir = Join-Path $PackSource $packDir
        if (Test-Path $localDir -PathType Container) {
            $check = Test-PreExtractedDir $localDir $App -ZipPath $local
            if ($check -eq "ok")              { Write-Host " [pre-extracted]" -ForegroundColor DarkGray; return $localDir }
            if ($check -like "count_mismatch:*") {
                $parts = $check.Split(':')
                $msg   = "Pre-extracted $packDir has $($parts[2]) files but zip has $($parts[1]) entries."
                if ($NoInteraction) {
                    $zipNote = if (Test-Path $local) { "Using zip." } else { "No zip found in PackSource  - this app will be skipped." }
                    Write-Warning "$msg $zipNote"
                } else {
                    $ans = Read-Host "$msg Re-extract from zip? [Y/n]"
                    if ($ans -match '^[Nn]') { Write-Host " [pre-extracted]" -ForegroundColor DarkGray; return $localDir }
                }
                if (Test-Path $local) { Write-Host " [PackSource]" -ForegroundColor DarkGray; return $local }
            } else {
                Write-Warning "Pre-extracted $packDir version mismatch  - falling back to zip"
            }
        }
        if (Test-Path $local) { Write-Host " [PackSource]" -ForegroundColor DarkGray; return $local }
        throw "Pack not found in PackSource: $local"
    }

    $lBase    = if ($Version) { "$LDrivePath\$Version" } else { $LDrivePath }
    $lPath    = "$lBase\$packName"
    $lDirPath = "$lBase\$packDir"
    if (Test-Path $lDirPath -PathType Container) {
        $check = Test-PreExtractedDir $lDirPath $App -ZipPath $lPath
        if ($check -eq "ok")              { Write-Host " [L:\pre-extracted]" -ForegroundColor DarkGray; return $lDirPath }
        if ($check -like "count_mismatch:*") {
            $parts = $check.Split(':')
            $msg   = "Pre-extracted $packDir has $($parts[2]) files but zip has $($parts[1]) entries."
            if ($NoInteraction) {
                $zipNote = if (Test-Path $lPath) { "Using zip." } else { "No zip found on L:  - will attempt GitHub download." }
                Write-Warning "$msg $zipNote"
            } else {
                $ans = Read-Host "$msg Re-extract from zip? [Y/n]"
                if ($ans -match '^[Nn]') { Write-Host " [L:\pre-extracted]" -ForegroundColor DarkGray; return $lDirPath }
            }
            if (Test-Path $lPath) {
                Write-Host " [L:\]" -ForegroundColor DarkGray
                Copy-WithProgress $lPath $tmpFile $packName
                $tmpFile = Resolve-ToArchives $tmpFile $ArchivesDir $packName
                return $tmpFile
            }
        } else {
            Write-Warning "Pre-extracted $packDir version mismatch  - falling back to zip"
        }
    }
    if (Test-Path $lPath) {
        Write-Host " [L:\]" -ForegroundColor DarkGray
        Copy-WithProgress $lPath $tmpFile $packName
        $tmpFile = Resolve-ToArchives $tmpFile $ArchivesDir $packName
        return $tmpFile
    }

    # Pack not found in the versioned L:\ folder.  Scan all other version subfolders of
    # LDrivePath (newest first) -- the same pack file may already exist in an older release
    # folder (reused packs keep their filename across releases).  This avoids a GitHub
    # round-trip for packs that are already on the local network drive.
    if (Test-Path $LDrivePath -PathType Container) {
        $otherFolders = Get-ChildItem $LDrivePath -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne $Version } |
            Sort-Object Name -Descending
        foreach ($folder in $otherFolders) {
            $altPath = Join-Path $folder.FullName $packName
            if (Test-Path $altPath) {
                Write-Host " [L:\]" -ForegroundColor DarkGray
                Copy-WithProgress $altPath $tmpFile $packName
                $tmpFile = Resolve-ToArchives $tmpFile $ArchivesDir $packName
                return $tmpFile
            }
        }
    }

    $repoBase = "https://github.com/ETML-INF/standard-toolset/releases"
    # packUrl is written by build.ps1 for packs reused from a prior release  - it points to the
    # release where the pack was actually built rather than the current manifest version.
    # Without this, every new release would have to re-upload all unchanged packs, and a client
    # asking for v2.0.1/app-1.0.0.zip would 404 for any app that didn't change in that release.
    $url = if ($App.PSObject.Properties['packUrl'] -and $App.packUrl) {
        $App.packUrl
    } elseif ($Version) {
        "$repoBase/download/v$Version/$packName"
    } else {
        "$repoBase/latest/download/$packName"
    }
    # Local path (L:\ or UNC \\) - copy directly instead of HTTP download
    if ($url -match '^[A-Za-z]:\\' -or $url -match '^\\\\') {
        if (-not (Test-Path $url)) {
            throw "Local pack not accessible: $url"
        }
        Write-Host " [L:\]" -ForegroundColor DarkGray
        Copy-WithProgress $url $tmpFile $packName
        $tmpFile = Resolve-ToArchives $tmpFile $ArchivesDir $packName
        return $tmpFile
    }
    Write-Host " [GitHub]" -ForegroundColor DarkGray
    try {
        Invoke-Download -Url $url -OutFile $tmpFile -Description $packName
        $tmpFile = Resolve-ToArchives $tmpFile $ArchivesDir $packName
        return $tmpFile
    } catch {
        throw "Cannot download $packName from L: or GitHub: $_"
    }
}

function Get-FilesNoJunction {
    <#
    .SYNOPSIS
        Returns all files under a directory without following junction (reparse) points.
    .DESCRIPTION
        Recursively enumerates a directory tree, stopping at any reparse point instead of
        traversing into it.  This ensures that scoop persist junctions (data\, bin\,
        settings\, etc.) are not followed, so files added by users to the persist folder
        (app settings, installed extensions, etc.) do not inflate the file count and
        break integrity checks.
        Optionally skips named subdirectories (ExcludePaths) for apps that store user
        data in real (non-junction) subdirectories that should not be counted.
        Used by Test-AppIntegrity for consistent measurement both before and after
        scoop activation.
    .PARAMETER Path
        Root directory to enumerate.
    .PARAMETER ExcludePaths
        Optional list of relative path prefixes (e.g. "vendor\conemu-maximus5") whose
        subtrees are skipped entirely.  Comparison is case-insensitive.
    .PARAMETER RootPath
        Internal -- root of the enumeration used to compute relative paths.
        Callers should omit this; it is set on the first call automatically.
    .OUTPUTS
        System.IO.FileInfo objects for every file that is not inside a reparse point
        or an excluded subtree.
    #>
    param([string]$Path, [string[]]$ExcludePaths = @(), [string]$RootPath = '')
    if ($RootPath -eq '') { $RootPath = $Path }
    Get-ChildItem $Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            # Stop here -- do not traverse into junctions or symlinks.
        } elseif ($_.PSIsContainer) {
            # Check exclusion list (relative path from root, case-insensitive).
            $rel = $_.FullName.Substring($RootPath.Length).TrimStart('\').TrimStart('/')
            $excluded = $false
            foreach ($ex in $ExcludePaths) {
                if ($rel -like "$ex" -or $rel -like "$ex\*" -or $rel -like "$ex/*") {
                    $excluded = $true; break
                }
            }
            if (-not $excluded) { Get-FilesNoJunction $_.FullName $ExcludePaths $RootPath }
        } else {
            $_
        }
    }
}

function Test-AppIntegrity {
    <#
    .SYNOPSIS
        Returns $true when the installed app directory matches the expected file count and total size.
    .DESCRIPTION
        Compares the number of files and their combined uncompressed size against the
        fileCount and totalSize fields in the release manifest.  Files inside junction
        (reparse) points -- scoop persist directories such as data\, bin\, settings\ --
        are excluded from the count so that user modifications to persisted data do not
        cause false integrity failures.
        Paths listed in the app's integrityExcludePaths manifest field are also excluded,
        for apps that store user-modifiable data in real (non-junction) subdirectories
        (e.g. cmder's vendor\conemu-maximus5\).
        Old manifests that lack fileCount/totalSize are treated as healthy (graceful
        degradation for legacy releases).
    .PARAMETER App
        App entry object from the release manifest (must have name, version, fileCount, totalSize).
    .PARAMETER toolsetdir
        Root of the toolset installation (contains scoop\).
    .OUTPUTS
        Boolean
    #>
    param([object]$App, [string]$toolsetdir)
    # Graceful degradation: old manifests without metadata are treated as healthy
    if (-not ($App.PSObject.Properties['fileCount'] -and $App.PSObject.Properties['totalSize'])) { return $true }
    # Check versioned dir first (real scoop layout), fall back to current\ (test/legacy layout)
    $versionDir = "$toolsetdir\scoop\apps\$($App.name)\$($App.version)"
    if (-not (Test-Path $versionDir -ErrorAction SilentlyContinue)) {
        $versionDir = "$toolsetdir\scoop\apps\$($App.name)\current"
    }
    if (-not (Test-Path $versionDir -ErrorAction SilentlyContinue)) { return $false }
    $excludePaths = if ($App.PSObject.Properties['integrityExcludePaths']) {
        @($App.integrityExcludePaths)
    } else { @() }
    $files = @(Get-FilesNoJunction $versionDir $excludePaths)
    if ($files.Count -ne [int]$App.fileCount) { return $false }
    $size = ($files | Measure-Object -Property Length -Sum).Sum
    return $size -eq [long]$App.totalSize
}

function Remove-Junction {
    <#
    .SYNOPSIS
        Removes a single junction (directory reparse point) without following its target.
    .DESCRIPTION
        Uses cmd.exe's rmdir to remove the directory entry unconditionally.
        Unlike Remove-Item, this works for both valid junctions and broken ones
        (where the target directory no longer exists).  PS5.1's Remove-Item
        tries to stat the target before removing the reparse point entry; when
        the target is gone it throws instead of just deleting the link.
        cmd rmdir without /s never recurses into the target.
    .PARAMETER Path
        Full path to the junction directory entry to remove.
    .OUTPUTS
        None
    #>
    param([string]$Path)
    cmd /c rmdir "$Path" 2>$null
}

function Test-IsReparsePoint {
    <#
    .SYNOPSIS
        Returns $true when the path is a reparse point (junction/symlink), including broken ones.
    .DESCRIPTION
        Uses [System.IO.File]::GetAttributes() which reads raw filesystem attributes without
        following the reparse point.  Get-Item / Test-Path in PS5.1 follow the junction
        and return $null / $false when the junction target no longer exists (broken junction),
        making them unreliable for detection.
    .PARAMETER Path
        Full path to test.
    .OUTPUTS
        Boolean
    #>
    param([string]$Path)
    try {
        $attr = [System.IO.File]::GetAttributes($Path)
        return [bool]($attr -band [System.IO.FileAttributes]::ReparsePoint)
    } catch { return $false }
}

function Remove-ReparsePoints {
    <#
    .SYNOPSIS
        Removes all reparse points (junction links) under a directory without following them.
    .DESCRIPTION
        Recursively enumerates a directory tree, stopping at reparse points instead of
        traversing into them, then removes each link via Remove-Junction (cmd rmdir) so the
        junction target (e.g. scoop\persist) is never touched.
        This is required before Remove-Item -Recurse on a versioned app dir because
        PS5.1 / .NET 4.x follow junctions during recursive enumeration and raise
        "Access Denied" when the persist target contains files.
    .PARAMETER Path
        Root directory to search for reparse points.
    .OUTPUTS
        None
    #>
    param([string]$Path)
    Get-ChildItem $Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            Remove-Junction $_.FullName
        } elseif ($_.PSIsContainer) {
            Remove-ReparsePoints $_.FullName
        }
    }
}

function Remove-DirSafe {
    <#
    .SYNOPSIS
        Removes a directory tree safely on both PS5.1 and PS7.
    .DESCRIPTION
        Strips all junction links first (without following them into their targets),
        then removes the remaining real content with Remove-Item -Recurse.
        This two-step pattern is required on PS5.1 / .NET 4.x where Remove-Item -Recurse
        follows junctions during enumeration and raises "Access Denied" when the persist
        target contains files.  PS7 handles junctions correctly on its own, but the guard
        is harmless there and keeps the code safe across both runtimes.
        Junction targets are never deleted.
    .PARAMETER Path
        Directory to remove.  No-op if the path does not exist.
    #>
    param([string]$Path)
    # Handle a broken (dangling) junction passed as root: Test-Path returns $false for broken
    # junctions in PS5.1, so the normal guard misses them.  Detect and remove via Remove-Junction.
    if (Test-IsReparsePoint $Path) { Remove-Junction $Path; return }
    if (-not (Test-Path $Path -ErrorAction SilentlyContinue)) { return }
    Remove-ReparsePoints $Path
    Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue
}

function Remove-StaleVersionDirs {
    <#
    .SYNOPSIS
        Removes old versioned app directories left over after a toolset update.
    .DESCRIPTION
        Scoop keeps every versioned directory until explicitly cleaned. After applying a
        delta pack the old version dirs are stale and can be removed. Junction links
        (scoop persist: data\, bin\, settings\, etc.) must be stripped before
        Remove-Item -Recurse or PS5.1 raises "Access Denied" by following them.
    .PARAMETER toolsetdir
        Root of the toolset installation (contains scoop\).
    .PARAMETER AppName
        Scoop app name (directory under scoop\apps\).
    .PARAMETER KeepVersion
        Version string to preserve; all other versioned dirs are removed.
    .OUTPUTS
        None
    #>
    param([string]$toolsetdir, [string]$AppName, [string]$KeepVersion)
    $appDir = "$toolsetdir\scoop\apps\$AppName"
    if (-not (Test-Path $appDir -ErrorAction SilentlyContinue)) { return }
    Get-ChildItem $appDir -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne $KeepVersion -and $_.Name -ne 'current' } |
        ForEach-Object {
            $dir  = $_.FullName
            $name = $_.Name
            Remove-DirSafe $dir
            if (Test-Path $dir) {
                # Still present: locked file (app running).  Rename out of the way so the
                # new version dir is unambiguous.  Next run will retry the removal.
                $tagged = "$dir-toBeDeleted"
                if (Test-Path $tagged) {
                    Remove-DirSafe $tagged
                }
                try {
                    Rename-Item $dir $tagged -ErrorAction Stop
                    Write-Warning "  $AppName\$name is locked - renamed to $name-toBeDeleted (remove when app is closed)"
                } catch {
                    Write-Warning "  $AppName\$name could not be removed or renamed: $_"
                }
            } else {
                Write-Verbose "  Removed stale $AppName\$name"
            }
        }
}

function Get-AppDiff {
    param($Manifest, $LocalVersions, [string]$toolsetdir, [bool]$ForceReinstall = $false)
    $names = $Manifest.apps | ForEach-Object { $_.name }

    # Pre-compute integrity once per app to avoid checking each app twice.
    # Integrity is needed only when the installed version matches the manifest (repair vs
    # up-to-date tiebreaker) or is unknown '?' (install vs up-to-date tiebreaker).
    $integrityCache = @{}
    $appsToCheck = @($Manifest.apps | Where-Object {
        -not $ForceReinstall -and
        $LocalVersions.ContainsKey($_.name) -and
        ($LocalVersions[$_.name] -eq $_.version -or $LocalVersions[$_.name] -eq '?')
    })
    if ($appsToCheck.Count -gt 0) {
        $isTerminal = -not [Console]::IsOutputRedirected
        if ($isTerminal) {
            [Console]::Write("  Checking integrity...")
        } else {
            Write-Host "  Checking integrity ($($appsToCheck.Count) apps)..." -ForegroundColor DarkGray -NoNewline
        }
        foreach ($app in $appsToCheck) {
            if ($isTerminal) {
                [Console]::Write("`r  $($app.name)...                              ")
            }
            $integrityCache[$app.name] = Test-AppIntegrity -App $app -toolsetdir $toolsetdir
        }
        if ($isTerminal) {
            [Console]::Write("`r" + (' ' * 55) + "`r")
        } else {
            Write-Host ' done' -ForegroundColor DarkGray
        }
    }

    return [pscustomobject]@{
        # "?" means version unknown but directory exists: use integrity as the tiebreaker.
        # If files match the target version -> treat as UpToDate. Otherwise fresh install.
        ToInstall = @($Manifest.apps | Where-Object {
            (-not $LocalVersions.ContainsKey($_.name)) -or
            ($LocalVersions[$_.name] -eq '?' -and -not $integrityCache[$_.name])
        })
        ToUpdate  = @($Manifest.apps | Where-Object {
            $LocalVersions.ContainsKey($_.name) -and
            $LocalVersions[$_.name] -ne $_.version -and
            $LocalVersions[$_.name] -ne '?'
        })
        ToRepair  = @($Manifest.apps | Where-Object {
            $LocalVersions.ContainsKey($_.name) -and $LocalVersions[$_.name] -eq $_.version -and
            ($ForceReinstall -or -not $integrityCache[$_.name])
        })
        UpToDate  = @($Manifest.apps | Where-Object {
            $LocalVersions.ContainsKey($_.name) -and -not $ForceReinstall -and
            $integrityCache[$_.name] -and
            ($LocalVersions[$_.name] -eq $_.version -or $LocalVersions[$_.name] -eq '?')
        })
        Removed   = @($LocalVersions.Keys | Where-Object { $_ -notin $names })
    }
}

function Show-AppStatus {
    param($Diff, $LocalVersions, [switch]$SkipPending)
    Write-Host ""
    if (-not $SkipPending) {
        foreach ($a in $Diff.ToInstall) { Write-Host "  [^] $($a.name.PadRight(20)) $($a.version)  will install" -ForegroundColor Cyan }
        foreach ($a in $Diff.ToUpdate)  { Write-Host "  [+] $($a.name.PadRight(20)) $($a.version)  will update from $($LocalVersions[$a.name])" -ForegroundColor Cyan }
    }
    foreach ($a in $Diff.ToRepair)  { Write-Host "  [!] $($a.name.PadRight(20)) $($a.version)  needs repair" -ForegroundColor Yellow }
    foreach ($a in $Diff.UpToDate) {
        if ($LocalVersions[$a.name] -eq '?') {
            Write-Host "  [=] $($a.name.PadRight(20)) $($a.version)  up to date (version unknown, files OK)" -ForegroundColor Green
        } else {
            Write-Host "  [=] $($a.name.PadRight(20)) $($a.version)  up to date" -ForegroundColor Green
        }
    }
    foreach ($n in $Diff.Removed)   { Write-Host "  [X] $($n.PadRight(20)) $($LocalVersions[$n])  not in manifest" -ForegroundColor Red }
}

function Install-Pack {
    param([string]$PackPath, [string]$toolsetdir)
    $appsDir = "$toolsetdir\scoop\apps"
    New-Item -ItemType Directory -Force -Path $appsDir | Out-Null

    # Pack root contains top-level app dirs (e.g. git\, vscode\); each holds one or more
    # versioned subdirs (e.g. vscode\1.88.0\).  We do NOT pre-remove the app dir:
    # the new versioned subdir is extracted first so the app remains usable during the
    # update, and so the current\ junction can be pointed at the new version before the
    # old dir is removed.  Remove-StaleVersionDirs handles cleanup of the old version dir
    # after extraction, with a rename fallback for locked files.

    if (Test-Path $PackPath -PathType Container) {
        # Pre-extracted pack directory - top-level dirs are app names, same as zip root
        Copy-Item "$PackPath\*" $appsDir -Recurse -Force
    } else {
        Expand-ZipWithProgress -ZipPath $PackPath -DestinationPath $appsDir
    }
}

# Shared manifest fetch used by both 'update' and 'status'.
# Prints the fetch header, delegates to Get-ReleaseManifest (which prints the
# source line), then confirms the loaded version.  Exits with code 1 on failure.
function Get-CurrentManifest {
    param([string]$ManifestSource, [string]$Version, [string]$LDrivePath, [bool]$NoInteraction)
    Write-Host "Fetching manifest (LAN: $LDrivePath | remote: GitHub)..." -ForegroundColor Yellow
    try {
        $m = Get-ReleaseManifest -ManifestSource $ManifestSource -Version $Version `
                 -LDrivePath $LDrivePath -NoInteraction $NoInteraction
    } catch {
        Write-Host $_ -ForegroundColor Red
        exit 1
    }
    Write-Host "Manifest: v$($m.version) ($($m.apps.Count) apps)" -ForegroundColor Green
    return $m
}

# -- entry point ------------------------------------------------------------

if ($Command -eq "update") {

    # Update mode resolves the path directly  - do not call Find-ToolsetDir
    # because fresh installs arrive here with a non-existent path, which would
    # cause Find-ToolsetDir to exit 1 before the directory can be created.
    $toolsetdir = $Path
    if (-not (Test-Path $toolsetdir)) {
        # Try the conventional alternative before creating at the given path
        if (Test-Path "D:\data\inf-toolset") {
            $toolsetdir = "D:\data\inf-toolset"
        } elseif ($toolsetdir -like '\\*') {
            Write-Host "The specified toolset path '$toolsetdir' is an unreachable UNC path. Ensure the network location is available and try again." -ForegroundColor Red
            exit 1
        } else {
            New-Item -ItemType Directory -Force -Path $toolsetdir | Out-Null
            Write-Host "Created $toolsetdir (fresh install)" -ForegroundColor Green
        }
    }

    $manifest = Get-CurrentManifest -ManifestSource $ManifestSource -Version $Version -LDrivePath $LDrivePath -NoInteraction ([bool]$NoInteraction)

    $localVersions = Get-LocalAppVersions -toolsetdir $toolsetdir
    $diff      = Get-AppDiff -Manifest $manifest -LocalVersions $localVersions -toolsetdir $toolsetdir -ForceReinstall ([bool]$ForceReinstall)
    $toInstall = $diff.ToInstall
    $toUpdate  = $diff.ToUpdate
    $toRepair  = $diff.ToRepair
    $removed   = $diff.Removed
    Show-AppStatus -Diff $diff -LocalVersions $localVersions -SkipPending

    # Removed app handling - split public orphans from private apps (marker: .toolset-private).
    # Private apps are protected from -Clean: only -CleanPrivate removes them, so a temporarily
    # unreachable L:\ does not cause accidental deletion.
    $removedPublic  = @($removed | Where-Object { -not (Test-Path "$toolsetdir\scoop\apps\$_\.toolset-private") })
    $removedPrivate = @($removed | Where-Object {       Test-Path "$toolsetdir\scoop\apps\$_\.toolset-private"  })

    if ($removedPublic.Count -gt 0) {
        if ($Clean) {
            foreach ($name in $removedPublic) {
                Remove-DirSafe "$toolsetdir\scoop\apps\$name"
                Write-Host "  Removed $name" -ForegroundColor DarkGray
            }
        } elseif ($NoInteraction) {
            Write-Warning "Orphaned apps detected: $($removedPublic -join ', '). Use -Clean to remove them."
        } else {
            foreach ($name in $removedPublic) {
                $answer = Read-Host "Remove $name (no longer in manifest)? [Y/N]"
                if ($answer -match '^[Yy]$') {
                    Remove-DirSafe "$toolsetdir\scoop\apps\$name"
                    Write-Host "  Removed $name" -ForegroundColor DarkGray
                }
            }
        }
    }

    if ($removedPrivate.Count -gt 0) {
        if ($CleanPrivate) {
            foreach ($name in $removedPrivate) {
                Remove-DirSafe "$toolsetdir\scoop\apps\$name"
                Write-Host "  Removed private app $name" -ForegroundColor DarkGray
            }
        } else {
            Write-Warning "Private apps not in manifest (L:\ unreachable?): $($removedPrivate -join ', '). Use -CleanPrivate to remove."
        }
    }

    # Confirm and download
    $toDo = @($toInstall) + @($toUpdate) + @($toRepair)
    if ($toDo.Count -eq 0) {
        Write-Host "Everything is up to date." -ForegroundColor Green
    } else {
        if (-not $NoInteraction) {
            $answer = Read-Host "Proceed with $($toDo.Count) download(s)? [Y/n]"
            if ($answer -match '^[Nn]') { Write-Host "Cancelled."; exit 0 }
        }

        # Use the manifest's own version for pack URLs when no explicit -Version was given.
        # This avoids a race where a new release is published between manifest fetch and pack download.
        $effectiveVersion = if ([string]::IsNullOrEmpty($Version)) { $manifest.version } else { $Version }
        $archivesDir      = Join-Path $toolsetdir "archives"

        $failed = @()
        foreach ($app in $toDo) {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            Write-Host "  $($app.pack.PadRight(30))" -ForegroundColor Yellow -NoNewline
            try {
                $packPath = Get-Pack -App $app -PackSource $PackSource -Version $effectiveVersion -LDrivePath $LDrivePath -ArchivesDir $archivesDir -NoInteraction $NoInteraction
                Install-Pack -PackPath $packPath -toolsetdir $toolsetdir
                # Mark private apps (local-path packUrl) so they are protected from -Clean removal
                # when L:\ is temporarily unreachable.  The marker survives until the app dir is removed.
                $isPrivatePack = $app.PSObject.Properties['packUrl'] -and $app.packUrl -and
                                 ($app.packUrl -match '^[A-Za-z]:\\' -or $app.packUrl -match '^\\\\')
                if ($isPrivatePack) {
                    New-Item -ItemType File -Force -Path "$toolsetdir\scoop\apps\$($app.name)\.toolset-private" | Out-Null
                }
                $sw.Stop()
                $elapsed = [math]::Round($sw.Elapsed.TotalSeconds, 1)
                if ($packPath.StartsWith($env:TEMP)) { Remove-Item $packPath -Force -ErrorAction SilentlyContinue }
                Remove-StaleVersionDirs -toolsetdir $toolsetdir -AppName $app.name -KeepVersion $app.version
                # Purge older cached zips for this app from archives (keep only the current version)
                if (Test-Path $archivesDir) {
                    Get-ChildItem $archivesDir -Filter "$($app.name)-*.zip" -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -ne $app.pack } |
                        ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
                }
                Write-Host "  [+] $($app.name.PadRight(20)) $($app.version.PadRight(12)) done (${elapsed}s)" -ForegroundColor Green
            } catch {
                Write-Host ""
                Write-Host "  [+] $($app.name.PadRight(20)) $($app.version.PadRight(12)) FAILED" -ForegroundColor Red
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

    # Re-run activation (skipped for remote UNC paths  - run toolset.ps1 locally on target to activate)
    Write-Host ""
    if ($toolsetdir.StartsWith("\\")) {
        Write-Host "Remote path  - skipping activation. Run toolset.ps1 on the target machine to activate." -ForegroundColor Yellow
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
    $manifest = Get-CurrentManifest -ManifestSource $ManifestSource -Version $Version -LDrivePath $LDrivePath -NoInteraction ([bool]$NoInteraction)
    $localVersions = Get-LocalAppVersions -toolsetdir $toolsetdir
    $diff = Get-AppDiff -Manifest $manifest -LocalVersions $localVersions -toolsetdir $toolsetdir
    Show-AppStatus -Diff $diff -LocalVersions $localVersions
    $pending = $diff.ToInstall.Count + $diff.ToUpdate.Count
    if ($pending -gt 0) {
        Write-Host "$pending update(s) available. Run toolset.ps1 update to apply." -ForegroundColor Yellow
        exit 1
    }
    Write-Host "Everything is up to date." -ForegroundColor Green

} else {
    # Activate mode  - if activation fails (broken install), fall back to update
    $toolsetdir = Find-ToolsetDir -StartPath $Path -NoInteraction $NoInteraction
    try {
        Invoke-Activate -toolsetdir $toolsetdir -NoInteraction $NoInteraction
    } catch {
        Write-Warning "Activation failed: $_"
        Write-Host "Broken install detected  - switching to update mode..." -ForegroundColor Yellow
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
