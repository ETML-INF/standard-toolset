param(
    [Parameter(Position=0)][string]$Command = "",
    [string]$Path = "C:\inf-toolset",
    [switch]$NoInteraction,
    [switch]$Clean,
    [switch]$ForceReinstall,
    [string]$Version = "",
    [string]$ManifestSource = "",
    [string]$PackSource = "",
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
            if (Test-Path $junctionPath) { [System.IO.Directory]::Delete($junctionPath) }
            New-Item -ItemType Junction -Path $junctionPath -Value $scoopVerDir.FullName | Out-Null
        }
    }
    # Pre-update current\ junctions from the release manifest before scoop reset *.
    # scoop reset reads the version from current\manifest.json; if current\ still points
    # to the old version (because the old dir could not be fully removed due to locked
    # files), scoop would re-link to the old version even though the new versioned dir
    # was just extracted.  Pointing current\ at the new version first fixes that.
    $localManifestPath = Join-Path $toolsetdir "release-manifest.json"
    if (Test-Path $localManifestPath -ErrorAction SilentlyContinue) {
        $mfForReset = Get-Content $localManifestPath -Raw | ConvertFrom-Json
        foreach ($appEntry in $mfForReset.apps) {
            if ($appEntry.name -eq 'scoop') { continue }
            # version may be absent on legacy/partial manifest entries - skip them
            if (-not $appEntry.PSObject.Properties['version']) { continue }
            $appDir     = "$scoopdir\apps\$($appEntry.name)"
            $verDir     = "$appDir\$($appEntry.version)"
            if (-not (Test-Path $verDir -ErrorAction SilentlyContinue)) { continue }
            $jPath      = "$appDir\current"
            $jItem      = Get-Item $jPath -ErrorAction SilentlyContinue
            $isJunction = $jItem -and ($jItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
            if ($jItem -and -not $isJunction) { continue }   # real dir, do not touch
            if ($isJunction) { [System.IO.Directory]::Delete($jPath) }
            New-Item -ItemType Junction -Path $jPath -Value $verDir | Out-Null
        }
    }
    if (Test-Path $scoopPs1 -ErrorAction SilentlyContinue) {
        Write-Host "Resetting scoop (restores current junctions)..." -ForegroundColor Green
        & $scoopPs1 reset *
    } else {
        Write-Warning "scoop.ps1 not found at $scoopPs1 - skipping junction reset (will complete on next activation)"
    }

    # Drop paths2DropToEnableMultiUser from each app's current\ dir so apps fall back to
    # per-user %APPDATA% instead of the shared portable-mode location.
    # Scoop's persist creates junctions: app\current\<path> -> scoop\persist\<app>\<path>.
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
                        # Directory junction  - Delete() removes only the link, not persist contents
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
        Write-Host "  No release manifest found  - skipping portable path cleanup." -ForegroundColor DarkGray
    }

    Write-Host "Updating scoop shims for path $toolsetdir..." -ForegroundColor Green
    $shimpath = "$scoopdir\shims"
    @("$shimpath\scoop","$shimpath\scoop.cmd","$shimpath\scoop.ps1") | ForEach-Object {
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

        # Text-like extensions that may embed absolute paths  - skip binaries for speed and safety
        $textExts = @('.js','.mjs','.cjs','.json','.cmd','.ps1','.bat','.npmrc','.ini','.cfg','.txt','.rc')

        $scanRoots = @(
            "$scoopdir\apps\nodejs-lts\$version",  # full versioned install (node_modules etc.)
            "$scoopdir\persist\nodejs-lts"          # persist dir (npmrc cache/prefix settings)
        )
        foreach ($root in $scanRoots) {
            if (-not (Test-Path $root)) { continue }
            # Use .NET enumeration for performance on large trees (node_modules has thousands of files)
            try { $files = [System.IO.Directory]::EnumerateFiles($root, '*', [System.IO.SearchOption]::AllDirectories) }
            catch { continue }
            foreach ($file in $files) {
                $ext = [System.IO.Path]::GetExtension($file)
                if (-not $ext -or $textExts -notcontains $ext.ToLowerInvariant()) { continue }
                $c = Get-Content $file -Raw -ErrorAction SilentlyContinue
                if ($c -and $c -match $oldPattern) {
                    $updated = [System.Text.RegularExpressions.Regex]::Replace(
                        $c, $oldPattern,
                        [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $newPersist }
                    )
                    [System.IO.File]::WriteAllText($file, $updated, [System.Text.UTF8Encoding]::new($false))
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
                $pct = [math]::Round(($progress.BytesTransferred / $progress.BytesTotal) * 100, 1)
                $mb  = [math]::Round($progress.BytesTransferred / 1MB, 1)
                $tot = [math]::Round($progress.BytesTotal / 1MB, 1)
                Write-Host ("`r" + " " * 80 + "`r  $label... $pct% ($mb / $tot MB)") -NoNewline
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

function Get-ReleaseManifest {
    param(
        [string]$ManifestSource,
        [string]$Version,
        [string]$LDrivePath = "L:\toolset",
        [bool]$NoInteraction = $false
    )
    if ($ManifestSource -and (Test-Path $ManifestSource)) {
        return Get-Content $ManifestSource -Raw | ConvertFrom-Json
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
                    Write-Warning "L:\toolset has v$($manifest.version) but GitHub has v$($ghManifest.version). Run offline-download.ps1 to refresh the network drive."
                    if (-not $NoInteraction) {
                        $answer = Read-Host "Use GitHub version v$($ghManifest.version) now instead? [Y/N]"
                        if ($answer -match '^[Yy]$') { return $ghManifest }
                    }
                }
            } catch { Write-Verbose "GitHub freshness check skipped: $_" }
        }

        return $manifest
    }

    # L: not available  - decide whether to try GitHub
    if ($NoInteraction) {
        throw "L:\toolset is not available and -NoInteraction prevents falling back to GitHub. Mount the drive or pass -ManifestSource explicitly."
    }
    $answer = Read-Host "L:\toolset is not available. Download manifest from GitHub instead? [Y/N]"
    if ($answer -notmatch '^[Yy]$') {
        throw "Aborted by user. Mount L:\toolset or pass -ManifestSource explicitly."
    }

    $url = if ([string]::IsNullOrEmpty($Version)) {
        "$repoBase/latest/download/release-manifest.json"
    } else {
        "$repoBase/download/v$Version/release-manifest.json"
    }
    try {
        return Invoke-RestMethod $url -ErrorAction Stop
    } catch {
        throw "GitHub manifest fetch failed: $_"
    }
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

        Falls back to current\manifest.json only when no versioned subdirectory exists
        (e.g., unusual scoop layouts in test fixtures).
    .PARAMETER toolsetdir
        Root of the toolset installation (contains scoop\).
    .OUTPUTS
        Hashtable of app name -> version string.
    #>
    param([string]$toolsetdir)
    $result = @{}
    $appsDir = "$toolsetdir\scoop\apps"
    if (-not (Test-Path $appsDir)) { return $result }
    Get-ChildItem $appsDir -Directory | ForEach-Object {
        $appDir = $_.FullName
        # Prefer the highest versioned dir over current\ (which may still point to the
        # previous version while the new version dir is already fully extracted).
        $vDir = Get-ChildItem $appDir -Directory |
                    Where-Object { $_.Name -ne 'current' } |
                    Sort-Object Name -Descending |
                    Select-Object -First 1
        $mPath = if ($vDir) {
            "$($vDir.FullName)\manifest.json"
        } else {
            # No versioned dir -- unusual layout; fall back to current\ (test/legacy).
            "$appDir\current\manifest.json"
        }
        if (Test-Path $mPath) {
            try { $result[$_.Name] = (Get-Content $mPath -Raw | ConvertFrom-Json).version } catch { }
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
                    $zipNote = if (Test-Path $local) { "Using zip." } else { "No zip found in PackSource  - this app will be skipped." }
                    Write-Warning "$msg $zipNote"
                } else {
                    $ans = Read-Host "$msg Re-extract from zip? [Y/N]"
                    if ($ans -notmatch '^[Yy]$') { return $localDir }
                }
                if (Test-Path $local) { return $local }
            } else {
                Write-Warning "Pre-extracted $packDir version mismatch  - falling back to zip"
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
                $zipNote = if (Test-Path $lPath) { "Using zip." } else { "No zip found on L:  - will attempt GitHub download." }
                Write-Warning "$msg $zipNote"
            } else {
                $ans = Read-Host "$msg Re-extract from zip? [Y/N]"
                if ($ans -notmatch '^[Yy]$') { return $lDirPath }
            }
            if (Test-Path $lPath) { return $lPath }
        } else {
            Write-Warning "Pre-extracted $packDir version mismatch  - falling back to zip"
        }
    }
    if (Test-Path $lPath) { return $lPath }

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
        Copy-Item $url $tmpFile -Force
        return $tmpFile
    }
    try {
        Invoke-Download -Url $url -OutFile $tmpFile -Description $packName
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
        Used by Test-AppIntegrity for consistent measurement both before and after
        scoop activation.
    .PARAMETER Path
        Root directory to enumerate.
    .OUTPUTS
        System.IO.FileInfo objects for every file that is not inside a reparse point.
    #>
    param([string]$Path)
    Get-ChildItem $Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            # Stop here -- do not traverse into junctions or symlinks.
        } elseif ($_.PSIsContainer) {
            Get-FilesNoJunction $_.FullName
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
    # Use Get-FilesNoJunction so that user modifications to scoop persist directories
    # (data\, settings\, bin\ junctions) don't inflate the count.
    $files = @(Get-FilesNoJunction $versionDir)
    if ($files.Count -ne [int]$App.fileCount) { return $false }
    $size = ($files | Measure-Object -Property Length -Sum).Sum
    return $size -eq [long]$App.totalSize
}

function Remove-ReparsePoints {
    <#
    .SYNOPSIS
        Removes all reparse points (junction links) under a directory without following them.
    .DESCRIPTION
        Recursively enumerates a directory tree, stopping at reparse points instead of
        traversing into them, then removes each link with Remove-Item (no -Recurse) so the
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
            # Remove-Item without -Recurse removes only the junction link, not the target.
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
        } elseif ($_.PSIsContainer) {
            Remove-ReparsePoints $_.FullName
        }
    }
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
            # Remove-Item -Recurse fails with "Access Denied" in PS5.1 on dirs that contain
            # junction points (scoop persist junctions: data\, bin\, Codecs\, etc.).
            # Fix: strip junction links first (Remove-ReparsePoints recurses into real
            # sub-dirs only, never follows junctions), then the remaining real content
            # is removable by Remove-Item -Recurse.
            Remove-ReparsePoints $dir
            Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path $dir) {
                # Still present: locked file (app running).  Rename out of the way so the
                # new version dir is unambiguous.  Next run will retry the removal.
                $tagged = "$dir-toBeDeleted"
                if (Test-Path $tagged) {
                    Remove-ReparsePoints $tagged
                    Remove-Item $tagged -Recurse -Force -ErrorAction SilentlyContinue
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
    return [pscustomobject]@{
        ToInstall = @($Manifest.apps | Where-Object { -not $LocalVersions.ContainsKey($_.name) })
        ToUpdate  = @($Manifest.apps | Where-Object { $LocalVersions.ContainsKey($_.name) -and $LocalVersions[$_.name] -ne $_.version })
        ToRepair  = @($Manifest.apps | Where-Object {
            $LocalVersions.ContainsKey($_.name) -and $LocalVersions[$_.name] -eq $_.version -and
            ($ForceReinstall -or -not (Test-AppIntegrity -App $_ -toolsetdir $toolsetdir))
        })
        UpToDate  = @($Manifest.apps | Where-Object {
            $LocalVersions.ContainsKey($_.name) -and $LocalVersions[$_.name] -eq $_.version -and
            -not $ForceReinstall -and (Test-AppIntegrity -App $_ -toolsetdir $toolsetdir)
        })
        Removed   = @($LocalVersions.Keys | Where-Object { $_ -notin $names })
    }
}

function Show-AppStatus {
    param($Diff, $LocalVersions)
    Write-Host ""
    Write-Host "Status:" -ForegroundColor Cyan
    foreach ($a in $Diff.UpToDate)  { Write-Host "  [=] $($a.name.PadRight(20)) $($a.version)  up to date" -ForegroundColor Green }
    foreach ($a in $Diff.ToUpdate)  { Write-Host "  [^] $($a.name.PadRight(20)) $($LocalVersions[$a.name]) -> $($a.version)" -ForegroundColor Yellow }
    foreach ($a in $Diff.ToRepair)  { Write-Host "  [!] $($a.name.PadRight(20)) $($a.version)  integrity fail" -ForegroundColor Magenta }
    foreach ($a in $Diff.ToInstall) { Write-Host "  [+] $($a.name.PadRight(20)) (not installed)" -ForegroundColor Cyan }
    foreach ($n in $Diff.Removed)   { Write-Host "  [X] $($n.PadRight(20)) $($LocalVersions[$n])  not in manifest" -ForegroundColor Red }
    Write-Host ""
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
        # Pre-extracted pack (L: directory)  - top-level dirs are app names, same as zip root
        Copy-Item "$PackPath\*" $appsDir -Recurse -Force
    } else {
        Expand-Archive -Path $PackPath -DestinationPath $appsDir -Force
    }
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

    Write-Host "Resolving manifest..." -ForegroundColor Yellow
    try {
        $manifest = Get-ReleaseManifest -ManifestSource $ManifestSource -Version $Version -NoInteraction ([bool]$NoInteraction)
    } catch {
        Write-Host $_ -ForegroundColor Red
        exit 1
    }
    Write-Host "Manifest: v$($manifest.version) ($($manifest.apps.Count) apps)" -ForegroundColor Green

    $localVersions = Get-LocalAppVersions -toolsetdir $toolsetdir
    $diff      = Get-AppDiff -Manifest $manifest -LocalVersions $localVersions -toolsetdir $toolsetdir -ForceReinstall ([bool]$ForceReinstall)
    $toInstall = $diff.ToInstall
    $toUpdate  = $diff.ToUpdate
    $toRepair  = $diff.ToRepair
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
    $toDo = @($toInstall) + @($toUpdate) + @($toRepair)
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
                Remove-StaleVersionDirs -toolsetdir $toolsetdir -AppName $app.name -KeepVersion $app.version
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
    Write-Host "Resolving manifest..." -ForegroundColor Yellow
    try {
        $manifest = Get-ReleaseManifest -ManifestSource $ManifestSource -Version $Version -NoInteraction ([bool]$NoInteraction)
    } catch {
        Write-Host $_ -ForegroundColor Red
        exit 1
    }
    Write-Host "Manifest: v$($manifest.version) ($($manifest.apps.Count) apps)" -ForegroundColor Green
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
