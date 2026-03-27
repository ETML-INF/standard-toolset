<#
  Container test runner. Runs inside Windows Nano Server.
  Exit 0 = all pass, Exit 1 = any failure.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"
$toolkit = "C:\toolset-repo\toolset.ps1"
$helper  = "C:\toolset-repo\tests\New-FakePack.ps1"
$pass = 0; $fail = 0

function Assert {
    param([string]$Name, $Cond, [string]$Detail="")
    if ($Cond) { Write-Host "  PASS: $Name" -ForegroundColor Green; $script:pass++ }
    else       { Write-Host "  FAIL: $Name $Detail" -ForegroundColor Red; $script:fail++ }
}

function Remove-TestDir {
    param([string[]]$Paths)
    foreach ($p in $Paths) {
        if (-not (Test-Path $p)) { continue }
        # Strip readonly flags first so Remove-Item doesn't hit access denied
        Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue |
            ForEach-Object { try { $_.Attributes = 'Normal' } catch {} }
        Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "[1] Fresh install" -ForegroundColor Cyan
$p = "C:\tmp\s1p"; $d = "C:\tmp\s1d"
& $helper -OutputDir $p -Apps @(@{Name="app1";Version="1.0.0"},@{Name="app2";Version="2.0.0"})
pwsh -File $toolkit update -Path $d -ManifestSource "$p\release-manifest.json" -PackSource $p -NoInteraction
Assert "app1 installed" (Test-Path "$d\scoop\apps\app1\current\manifest.json")
Assert "app2 installed" (Test-Path "$d\scoop\apps\app2\current\manifest.json")

Write-Host "[2] Partial update" -ForegroundColor Cyan
$p = "C:\tmp\s2p"; $d = "C:\tmp\s2d"
foreach ($x in @("app1/1.0.0","app2/2.0.0")) {
    $n,$v = $x -split "/"; $cd = "$d\scoop\apps\$n\current"
    New-Item -Force -ItemType Directory $cd | Out-Null
    @{version=$v} | ConvertTo-Json | Set-Content "$cd\manifest.json" -Encoding UTF8
}
& $helper -OutputDir $p -Apps @(@{Name="app1";Version="1.1.0"},@{Name="app2";Version="2.0.0"})
pwsh -File $toolkit update -Path $d -ManifestSource "$p\release-manifest.json" -PackSource $p -NoInteraction
$v1 = (Get-Content "$d\scoop\apps\app1\current\manifest.json"|ConvertFrom-Json).version
$v2 = (Get-Content "$d\scoop\apps\app2\current\manifest.json"|ConvertFrom-Json).version
Assert "app1 updated to 1.1.0"  ($v1 -eq "1.1.0")
Assert "app2 still at 2.0.0"    ($v2 -eq "2.0.0")

Write-Host "[3a] -Clean removes orphan" -ForegroundColor Cyan
$p = "C:\tmp\s3ap"; $d = "C:\tmp\s3ad"
& $helper -OutputDir $p -Apps @(@{Name="app1";Version="1.0.0"})
$od = "$d\scoop\apps\orphan\current"; New-Item -Force -ItemType Directory $od | Out-Null
@{version="0.1"} | ConvertTo-Json | Set-Content "$od\manifest.json" -Encoding UTF8
pwsh -File $toolkit update -Path $d -ManifestSource "$p\release-manifest.json" -PackSource $p -NoInteraction -Clean
Assert "orphan removed" (-not (Test-Path "$d\scoop\apps\orphan"))

Write-Host "[3b] -NoInteraction keeps orphan" -ForegroundColor Cyan
$p = "C:\tmp\s3bp"; $d = "C:\tmp\s3bd"
& $helper -OutputDir $p -Apps @(@{Name="app1";Version="1.0.0"})
$od = "$d\scoop\apps\orphan\current"; New-Item -Force -ItemType Directory $od | Out-Null
@{version="0.1"} | ConvertTo-Json | Set-Content "$od\manifest.json" -Encoding UTF8
pwsh -File $toolkit update -Path $d -ManifestSource "$p\release-manifest.json" -PackSource $p -NoInteraction
Assert "orphan kept" (Test-Path "$d\scoop\apps\orphan")

Write-Host "[4] Pack missing — continues" -ForegroundColor Cyan
$p = "C:\tmp\s4p"; $d = "C:\tmp\s4d"
& $helper -OutputDir $p -Apps @(@{Name="app1";Version="1.0.0"},@{Name="app2";Version="2.0.0"})
Remove-Item "$p\app2-2.0.0.zip" -Force
pwsh -File $toolkit update -Path $d -ManifestSource "$p\release-manifest.json" -PackSource $p -NoInteraction
$ec = $LASTEXITCODE
Assert "app1 installed despite missing pack"  (Test-Path "$d\scoop\apps\app1\current\manifest.json")
Assert "non-fatal exit"                       ($ec -eq 0)

Write-Host "[5] No sources available" -ForegroundColor Cyan
$d = "C:\tmp\s5d"
pwsh -File $toolkit update -Path $d -NoInteraction
$ec = $LASTEXITCODE
Assert "exits non-zero" ($ec -ne 0)

Write-Host "[6] Status — exit 1 when updates available" -ForegroundColor Cyan
$p = "C:\tmp\s6p"; $d = "C:\tmp\s6d"
& $helper -OutputDir $p -Apps @(@{Name="app1";Version="1.1.0"}) -ManifestVersion "2.0.0"
New-Item -Force -ItemType Directory "$d\scoop\apps\app1\current" | Out-Null
@{version="1.0.0"} | ConvertTo-Json | Set-Content "$d\scoop\apps\app1\current\manifest.json" -Encoding UTF8
$out = pwsh -File $toolkit status -Path $d -ManifestSource "$p\release-manifest.json" 2>&1
$ec = $LASTEXITCODE
Assert "[6] status shows app1"     ($out -match "app1")
Assert "[6] exit 1 (pending)"      ($ec -eq 1)
Remove-TestDir $d,$p

Write-Host "[7] Status — exit 0 when up to date" -ForegroundColor Cyan
$p = "C:\tmp\s7p"; $d = "C:\tmp\s7d"
& $helper -OutputDir $p -Apps @(@{Name="app1";Version="1.0.0"}) -ManifestVersion "2.0.0"
New-Item -Force -ItemType Directory "$d\scoop\apps\app1\current" | Out-Null
@{version="1.0.0"} | ConvertTo-Json | Set-Content "$d\scoop\apps\app1\current\manifest.json" -Encoding UTF8
pwsh -File $toolkit status -Path $d -ManifestSource "$p\release-manifest.json" 2>$null
$ec = $LASTEXITCODE
Assert "[7] exit 0 (up to date)"   ($ec -eq 0)
Remove-TestDir $d,$p

Write-Host "[8] Update with -Version" -ForegroundColor Cyan
$p = "C:\tmp\s8p"; $d = "C:\tmp\s8d"
& $helper -OutputDir $p -Apps @(@{Name="app1";Version="1.0.0"}) -ManifestVersion "5.0.0"
pwsh -File $toolkit update -Path $d `
    -ManifestSource "$p\release-manifest.json" -PackSource $p -Version 5.0.0 -NoInteraction
Assert "[8] app1 installed with -Version" (Test-Path "$d\scoop\apps\app1\current\manifest.json")
Remove-TestDir $d,$p

Write-Host "[9] Activation — shim path replacement" -ForegroundColor Cyan
$d9 = "C:\tmp\s9d"; $sd9 = "$d9\scoop"
New-Item -Force -ItemType Directory "$sd9\apps\scoop\current\bin" | Out-Null
Set-Content "$sd9\apps\scoop\current\bin\scoop.ps1" "# fake scoop stub" -Encoding UTF8
New-Item -Force -ItemType Directory "$sd9\shims" | Out-Null
$old9 = "D:\was-here\scoop\"
Set-Content "$sd9\shims\scoop"     "$($old9)shims\scoop"     -Encoding UTF8
Set-Content "$sd9\shims\scoop.cmd" "$($old9)shims\scoop.cmd" -Encoding UTF8
Set-Content "$sd9\shims\scoop.ps1" "$($old9)shims\scoop.ps1" -Encoding UTF8
pwsh -File $toolkit -Path $d9 -NoInteraction
$ec9 = $LASTEXITCODE
Assert "[9] exit 0"              ($ec9 -eq 0)
Assert "[9] shim: old path gone" ((Get-Content "$sd9\shims\scoop" -Raw) -notlike '*was-here*')
Assert "[9] shim: new path set"  ((Get-Content "$sd9\shims\scoop" -Raw) -like "*$sd9*")
Remove-TestDir $d9

Write-Host "[10] Activation — reg file path replacement" -ForegroundColor Cyan
$d10 = "C:\tmp\s10d"; $sd10 = "$d10\scoop"
New-Item -Force -ItemType Directory "$sd10\apps\scoop\current\bin" | Out-Null
Set-Content "$sd10\apps\scoop\current\bin\scoop.ps1" "# fake scoop stub" -Encoding UTF8
New-Item -Force -ItemType Directory "$sd10\shims" | Out-Null
$old10 = "D:\was-here\scoop\"
Set-Content "$sd10\shims\scoop"     "$($old10)shims\scoop"     -Encoding UTF8
Set-Content "$sd10\shims\scoop.cmd" "$($old10)shims\scoop.cmd" -Encoding UTF8
Set-Content "$sd10\shims\scoop.ps1" "$($old10)shims\scoop.ps1" -Encoding UTF8
$regDir = "$sd10\apps\testapp\current"
New-Item -Force -ItemType Directory $regDir | Out-Null
Set-Content "$regDir\testapp.reg" "REGEDIT4`r`n`"Path`"=`"D:\\was-here\\scoop\\apps\\testapp`"" -Encoding UTF8
pwsh -File $toolkit -Path $d10 -NoInteraction
Assert "[10] reg: old path gone"  ((Get-Content "$regDir\testapp.reg" -Raw) -notlike '*was-here*')
Remove-TestDir $d10

Write-Host "[11] gitconfig.ps1 — safe.directory patching" -ForegroundColor Cyan
$gc = "C:\toolset-repo\gitconfig.ps1"
$dir = "C:\tmp\s11-toolset"

# [11a] No existing .gitconfig file at all → [safe] block created from scratch
$f = "C:\tmp\s11a.gitconfig"
Remove-Item $f -Force -ErrorAction SilentlyContinue
& pwsh -File $gc $f $dir *> $null
$c = Get-Content $f -Raw
Assert "[11a] [safe] section created"    ($c -match '\[safe\]')
Assert "[11a] directory line added"      ($c -match 'directory\s*=')
Assert "[11a] path in directory"         ($c -match [regex]::Escape($dir.Replace('\','/')))

# [11b] .gitconfig exists without [safe] → block prepended
$f = "C:\tmp\s11b.gitconfig"
Set-Content $f "[user]`n`tname = Test" -Encoding UTF8
& pwsh -File $gc $f $dir *> $null
$c = Get-Content $f -Raw
Assert "[11b] [safe] prepended"          ($c -match '\[safe\]')
Assert "[11b] [user] still present"      ($c -match '\[user\]')
Assert "[11b] directory points to dir"   ($c -match [regex]::Escape($dir.Replace('\','/')))

# [11c] .gitconfig has [safe] but no directory → line inserted after [safe]
$f = "C:\tmp\s11c.gitconfig"
Set-Content $f "[safe]`n[user]`n`tname = Test" -Encoding UTF8
& pwsh -File $gc $f $dir *> $null
$c = Get-Content $f -Raw
Assert "[11c] directory inserted"        ($c -match 'directory\s*=')
Assert "[11c] path correct"             ($c -match [regex]::Escape($dir.Replace('\','/')))

# [11d] .gitconfig has [safe] with existing directory → replaced
$f = "C:\tmp\s11d.gitconfig"
Set-Content $f "[safe]`n`tdirectory = C:/old/path/*" -Encoding UTF8
& pwsh -File $gc $f $dir *> $null
$lines = Get-Content $f
$dirLines = @($lines | Where-Object { $_ -match 'directory\s*=' })
Assert "[11d] only one directory line"   ($dirLines.Count -eq 1)
Assert "[11d] old path replaced"         ($dirLines[0] -notmatch 'old/path')
Assert "[11d] new path set"              ($dirLines[0] -match [regex]::Escape($dir.Replace('\','/')))

# [11e] Another section has a directory= key — must not be touched; only [safe] section is updated
$f = "C:\tmp\s11e.gitconfig"
Set-Content $f "[url `"git@github.com:`"]`n`tdirectory = some/repo/path`n[safe]`n`tdirectory = C:/old/path/*" -Encoding UTF8
& pwsh -File $gc $f $dir *> $null
$lines11e = Get-Content $f
$urlDirLines11e  = @($lines11e | Where-Object { $_ -match '^\s*directory\s*=\s*some/repo/path' })
$safeDirLines11e = @($lines11e | Where-Object { $_ -match [regex]::Escape($dir.Replace('\','/')) })
Assert "[11e] [url] directory line untouched"  ($urlDirLines11e.Count -eq 1)
Assert "[11e] [safe] directory updated"        ($safeDirLines11e.Count -eq 1)

Remove-Item "C:\tmp\s11*.gitconfig" -Force -ErrorAction SilentlyContinue

Write-Host "[12] Activation — paths2DropToEnableMultiUser cleanup" -ForegroundColor Cyan
$d12 = "C:\tmp\s12d"; $sd12 = "$d12\scoop"
New-Item -Force -ItemType Directory "$sd12\apps\scoop\current\bin" | Out-Null
Set-Content "$sd12\apps\scoop\current\bin\scoop.ps1" "# fake scoop stub" -Encoding UTF8
New-Item -Force -ItemType Directory "$sd12\shims" | Out-Null
Set-Content "$sd12\shims\scoop"     "$sd12\shims\scoop"     -Encoding UTF8
Set-Content "$sd12\shims\scoop.cmd" "$sd12\shims\scoop.cmd" -Encoding UTF8
Set-Content "$sd12\shims\scoop.ps1" "$sd12\shims\scoop.ps1" -Encoding UTF8
# Manifest with MIXED apps: one has paths2DropToEnableMultiUser, one does NOT.
# This is the production-realistic shape and exercises the PSObject.Properties guard
# (without it, StrictMode throws PropertyNotFoundException on apps that lack the field).
@{  version = "1.0.0"
    apps = @(
        @{ name = "plainapp" }                                                                  # no paths2Drop — must not throw
        @{ name = "fakeapp"; paths2DropToEnableMultiUser = @("data", ".portable") }            # has paths2Drop — must clean up
    )
} | ConvertTo-Json -Depth 5 | Set-Content "$d12\release-manifest.json" -Encoding UTF8
# Empty dir simulates a directory junction; file simulates a .portable trigger
New-Item -Force -ItemType Directory "$sd12\apps\fakeapp\current\data" | Out-Null
New-Item -Force -ItemType File      "$sd12\apps\fakeapp\current\.portable" | Out-Null
pwsh -File $toolkit -Path $d12 -NoInteraction
$ec12 = $LASTEXITCODE
Assert "[12] exit 0 (mixed manifest — no StrictMode crash)" ($ec12 -eq 0)
Assert "[12] data dir removed"  (-not (Test-Path "$sd12\apps\fakeapp\current\data"))
Assert "[12] .portable removed" (-not (Test-Path "$sd12\apps\fakeapp\current\.portable"))
Remove-TestDir $d12

Write-Host "[13] Pre-extracted pack directory on PackSource" -ForegroundColor Cyan
$d13 = "C:\tmp\s13d"; $sd13 = "$d13\scoop"; $ps13 = "C:\tmp\s13p"
New-Item -Force -ItemType Directory $ps13 | Out-Null
@{ version = "99.0.0"; apps = @(@{ name = "app1"; version = "1.0.0"; pack = "app1-1.0.0.zip" }) } |
    ConvertTo-Json -Depth 5 | Set-Content "$ps13\release-manifest.json" -Encoding UTF8
# Pre-extracted directory mirrors zip contents: <packName-without-.zip>\<appname>\current\
New-Item -Force -ItemType Directory "$ps13\app1-1.0.0\app1\current" | Out-Null
@{ version = "1.0.0" } | ConvertTo-Json | Set-Content "$ps13\app1-1.0.0\app1\current\manifest.json" -Encoding UTF8
New-Item -Force -ItemType Directory $d13 | Out-Null
pwsh -File $toolkit update -Path $d13 -ManifestSource "$ps13\release-manifest.json" -PackSource $ps13 -NoInteraction
$ec13 = $LASTEXITCODE
Assert "[13] exit 0"         ($ec13 -eq 0)
Assert "[13] app1 installed" (Test-Path "$sd13\apps\app1\current\manifest.json")
Remove-TestDir $d13
Remove-TestDir $ps13

Write-Host "[14] Pre-extracted dir version mismatch falls back to zip" -ForegroundColor Cyan
$d14 = "C:\tmp\s14d"; $sd14 = "$d14\scoop"; $ps14 = "C:\tmp\s14p"
& $helper -OutputDir $ps14 -Apps @(@{Name="app1";Version="1.0.0"})
# Stale pre-extracted dir claims version 0.9.0, manifest expects 1.0.0 → must fall back to zip
New-Item -Force -ItemType Directory "$ps14\app1-1.0.0\app1\current" | Out-Null
@{ version = "0.9.0" } | ConvertTo-Json | Set-Content "$ps14\app1-1.0.0\app1\current\manifest.json" -Encoding UTF8
New-Item -Force -ItemType Directory $d14 | Out-Null
pwsh -File $toolkit update -Path $d14 -ManifestSource "$ps14\release-manifest.json" -PackSource $ps14 -NoInteraction
$ec14 = $LASTEXITCODE
$installedVer14 = try { (Get-Content "$sd14\apps\app1\current\manifest.json" -Raw | ConvertFrom-Json).version } catch { "" }
Assert "[14] exit 0"                   ($ec14 -eq 0)
Assert "[14] correct version from zip" ($installedVer14 -eq "1.0.0")
Remove-TestDir $d14
Remove-TestDir $ps14

Write-Host "[15] Pre-extracted dir file-count mismatch falls back to zip (NoInteraction)" -ForegroundColor Cyan
$d15 = "C:\tmp\s15d"; $sd15 = "$d15\scoop"; $ps15 = "C:\tmp\s15p"
& $helper -OutputDir $ps15 -Apps @(@{Name="app1";Version="1.0.0"})
# Pre-extracted dir has correct version but an extra unexpected file → count mismatch
New-Item -Force -ItemType Directory "$ps15\app1-1.0.0\app1\current" | Out-Null
@{ version = "1.0.0" } | ConvertTo-Json | Set-Content "$ps15\app1-1.0.0\app1\current\manifest.json" -Encoding UTF8
Set-Content "$ps15\app1-1.0.0\app1\current\unexpected.txt" "stale" -Encoding UTF8
New-Item -Force -ItemType Directory $d15 | Out-Null
pwsh -File $toolkit update -Path $d15 -ManifestSource "$ps15\release-manifest.json" -PackSource $ps15 -NoInteraction
$ec15 = $LASTEXITCODE
$installedVer15 = try { (Get-Content "$sd15\apps\app1\current\manifest.json" -Raw | ConvertFrom-Json).version } catch { "" }
Assert "[15] exit 0"                      ($ec15 -eq 0)
Assert "[15] correct version from zip"    ($installedVer15 -eq "1.0.0")
Assert "[15] unexpected file not present" (-not (Test-Path "$sd15\apps\app1\current\unexpected.txt"))
Remove-TestDir $d15
Remove-TestDir $ps15

Write-Host "[16] Activate — NoInteraction with missing toolset → exit non-zero" -ForegroundColor Cyan
$d16 = "C:\tmp\s16d-unique-missing-toolset-xyz"
Remove-TestDir $d16   # ensure it doesn't exist
# D:\data\inf-toolset also absent in container → Find-ToolsetDir exits 1
pwsh -File $toolkit -Path $d16 -NoInteraction 2>$null
$ec16 = $LASTEXITCODE
Assert "[16] exits non-zero when toolset missing + NoInteraction" ($ec16 -ne 0)

Write-Host "[17] Activate — broken install (no scoop.ps1) falls back to update" -ForegroundColor Cyan
$d17 = "C:\tmp\s17d"; $ps17 = "C:\tmp\s17p"
& $helper -OutputDir $ps17 -Apps @(@{Name="app1";Version="1.0.0"})
# Toolset dir exists but has NO scoop\apps\scoop\current\bin\scoop.ps1 → Invoke-Activate throws
New-Item -Force -ItemType Directory $d17 | Out-Null
# Run as activate mode (no command); -ManifestSource/-PackSource are forwarded to the update fallback
pwsh -File $toolkit -Path $d17 `
    -ManifestSource "$ps17\release-manifest.json" -PackSource $ps17 -NoInteraction
$ec17 = $LASTEXITCODE
Assert "[17] exit 0 after broken-install fallback" ($ec17 -eq 0)
Assert "[17] app1 installed via update fallback"   (Test-Path "$d17\scoop\apps\app1\current\manifest.json")
Remove-TestDir $d17
Remove-TestDir $ps17

Write-Host "[18] Update saves release-manifest.json to toolset dir" -ForegroundColor Cyan
$d18 = "C:\tmp\s18d"; $ps18 = "C:\tmp\s18p"
& $helper -OutputDir $ps18 -Apps @(@{Name="app1";Version="1.0.0"})
New-Item -Force -ItemType Directory $d18 | Out-Null
pwsh -File $toolkit update -Path $d18 `
    -ManifestSource "$ps18\release-manifest.json" -PackSource $ps18 -NoInteraction
Assert "[18] release-manifest.json saved"  (Test-Path "$d18\release-manifest.json")
$savedMf18 = try { Get-Content "$d18\release-manifest.json" -Raw | ConvertFrom-Json } catch { $null }
Assert "[18] saved manifest has version"   ($savedMf18 -and $savedMf18.version -eq "99.0.0")
Assert "[18] saved manifest has apps"      ($savedMf18 -and $savedMf18.apps.Count -eq 1)
Remove-TestDir $d18
Remove-TestDir $ps18

Write-Host "[19] Count mismatch via real zip: zip has 2 files, dir has 1 — NoInteraction uses zip" -ForegroundColor Cyan
$d19 = "C:\tmp\s19d"; $ps19 = "C:\tmp\s19p"; $src19 = "C:\tmp\s19src"
# Build zip manually so Get-ZipEntryCount is tested against real Compress-Archive output
New-Item -Force -ItemType Directory "$src19\app1\current" | Out-Null
@{ version = "1.0.0" } | ConvertTo-Json | Set-Content "$src19\app1\current\manifest.json" -Encoding UTF8
Set-Content "$src19\app1\current\data.bin" "payload" -Encoding UTF8   # 2nd file in zip
New-Item -Force -ItemType Directory $ps19 | Out-Null
Compress-Archive -Path "$src19\*" -DestinationPath "$ps19\app1-1.0.0.zip" -Force
@{ version = "99.0.0"; apps = @(@{ name = "app1"; version = "1.0.0"; pack = "app1-1.0.0.zip" }) } |
    ConvertTo-Json -Depth 5 | Set-Content "$ps19\release-manifest.json" -Encoding UTF8
# Pre-extracted dir is INCOMPLETE: only manifest, missing data.bin (1 file vs zip's 2)
New-Item -Force -ItemType Directory "$ps19\app1-1.0.0\app1\current" | Out-Null
@{ version = "1.0.0" } | ConvertTo-Json | Set-Content "$ps19\app1-1.0.0\app1\current\manifest.json" -Encoding UTF8
New-Item -Force -ItemType Directory $d19 | Out-Null
$out19 = pwsh -File $toolkit update -Path $d19 `
    -ManifestSource "$ps19\release-manifest.json" -PackSource $ps19 -NoInteraction 2>&1
$ec19 = $LASTEXITCODE
Assert "[19] exit 0"                    ($ec19 -eq 0)
Assert "[19] zip used (data.bin present)" (Test-Path "$d19\scoop\apps\app1\current\data.bin")
Assert "[19] count mismatch warning"    ($out19 -match "files but")
Assert "[19] 'Using zip.' message"      ($out19 -match "Using zip\.")
Remove-TestDir $d19, $ps19, $src19

Write-Host "[20] Pack with .git dir installs correctly (no .git-force hack needed)" -ForegroundColor Cyan
$d20 = "C:\tmp\s20d"; $ps20 = "C:\tmp\s20p"
New-Item -Force -ItemType Directory $ps20 | Out-Null
@{ version = "99.0.0"; apps = @(@{ name = "app1"; version = "1.0.0"; pack = "app1-1.0.0.zip" }) } |
    ConvertTo-Json -Depth 5 | Set-Content "$ps20\release-manifest.json" -Encoding UTF8
# Build zip using the same .NET approach as New-ZipPack in build.ps1
# Include a .git directory to prove Expand-Archive round-trip works without rename hack
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip20 = [System.IO.Compression.ZipFile]::Open("$ps20\app1-1.0.0.zip", [System.IO.Compression.ZipArchiveMode]::Create)
foreach ($entry in @(
    @{ name = "app1/current/manifest.json"; content = '{"version":"1.0.0"}' }
    @{ name = "app1/current/.git/HEAD";     content = 'ref: refs/heads/main' }
    @{ name = "app1/current/.git/config";   content = '[core]' }
)) {
    $e  = $zip20.CreateEntry($entry.name, [System.IO.Compression.CompressionLevel]::Optimal)
    $sw = [System.IO.StreamWriter]::new($e.Open())
    $sw.Write($entry.content); $sw.Dispose()
}
$zip20.Dispose()
New-Item -Force -ItemType Directory $d20 | Out-Null
pwsh -File $toolkit update -Path $d20 `
    -ManifestSource "$ps20\release-manifest.json" -PackSource $ps20 -NoInteraction
$ec20 = $LASTEXITCODE
Assert "[20] exit 0"                   ($ec20 -eq 0)
Assert "[20] .git/HEAD present"        (Test-Path "$d20\scoop\apps\app1\current\.git\HEAD")
Assert "[20] no .git-force residue"    (-not (Test-Path "$d20\scoop\apps\app1\current\.git-force"))
Remove-TestDir $d20, $ps20

Write-Host "[21] Activation — missing scoop.ps1 emits warning, exits 0" -ForegroundColor Cyan
$d21 = "C:\tmp\s21d"; $sd21 = "$d21\scoop"
# Deliberately omit scoop.ps1 — no apps\scoop\current\bin\scoop.ps1
New-Item -Force -ItemType Directory "$sd21\shims" | Out-Null
Set-Content "$sd21\shims\scoop"     "$sd21\shims\scoop"     -Encoding UTF8
Set-Content "$sd21\shims\scoop.cmd" "$sd21\shims\scoop.cmd" -Encoding UTF8
Set-Content "$sd21\shims\scoop.ps1" "$sd21\shims\scoop.ps1" -Encoding UTF8
$out21 = pwsh -File $toolkit -Path $d21 -NoInteraction 2>&1
$ec21  = $LASTEXITCODE
Assert "[21] exit 0 despite missing scoop.ps1" ($ec21 -eq 0)
Assert "[21] warning emitted"                  ($out21 -match "scoop.ps1 not found")
Remove-TestDir $d21

Write-Host ""
Write-Host "Results: $pass passed, $fail failed" -ForegroundColor $(if($fail -eq 0){"Green"}else{"Red"})
if ($fail -gt 0) { exit 1 }
