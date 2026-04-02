<#
  Container test runner. Runs inside Windows Nano Server.
  Exit 0 = all pass, Exit 1 = any failure.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"
$toolkit = "C:\toolset-repo\toolset.ps1"
$helper  = "C:\toolset-repo\tests\New-FakePack.ps1"
$fail = 0

. (Join-Path $PSScriptRoot "Test-Helpers.ps1")

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
New-FakeScoopStub -ScoopDir $sd9
New-TestShims -ScoopDir $sd9 -OldBase "D:\was-here\scoop\"
pwsh -File $toolkit -Path $d9 -NoInteraction
$ec9 = $LASTEXITCODE
Assert "[9] exit 0"              ($ec9 -eq 0)
Assert "[9] shim: old path gone" ((Get-Content "$sd9\shims\scoop" -Raw) -notlike '*was-here*')
Assert "[9] shim: new path set"  ((Get-Content "$sd9\shims\scoop" -Raw) -like "*$sd9*")
Remove-TestDir $d9

Write-Host "[10] Activation — reg file path replacement" -ForegroundColor Cyan
$d10 = "C:\tmp\s10d"; $sd10 = "$d10\scoop"
New-FakeScoopStub -ScoopDir $sd10
New-TestShims -ScoopDir $sd10 -OldBase "D:\was-here\scoop\"
$regDir = "$sd10\apps\testapp\current"
New-Item -Force -ItemType Directory $regDir | Out-Null
Set-Content "$regDir\testapp.reg" "REGEDIT4`r`n`"Path`"=`"D:\\was-here\\scoop\\apps\\testapp`"" -Encoding UTF8
pwsh -File $toolkit -Path $d10 -NoInteraction
Assert "[10] reg: old path gone"  ((Get-Content "$regDir\testapp.reg" -Raw) -notlike '*was-here*')
Remove-TestDir $d10

Write-Host "[12] Activation — paths2DropToEnableMultiUser cleanup" -ForegroundColor Cyan
$d12 = "C:\tmp\s12d"; $sd12 = "$d12\scoop"
New-FakeScoopStub -ScoopDir $sd12
New-TestShims -ScoopDir $sd12 -OldBase "$sd12\"
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
Set-Content "$sd21\shims\scoop"     "# stub" -Encoding UTF8
Set-Content "$sd21\shims\scoop.cmd" "# stub" -Encoding UTF8
Set-Content "$sd21\shims\scoop.ps1" "# stub" -Encoding UTF8
$out21 = pwsh -File $toolkit -Path $d21 -NoInteraction 2>&1
$ec21  = $LASTEXITCODE
Assert "[21] exit 0 despite missing scoop.ps1" ($ec21 -eq 0)
Assert "[21] warning emitted"                  ($out21 -match "scoop.ps1 not found")
Remove-TestDir $d21

Write-Host "[22] Integrity — missing file triggers repair" -ForegroundColor Cyan
$d22 = "C:\tmp\s22d"; $ps22 = "C:\tmp\s22p"
Install-FreshApp -PackDir $ps22 -InstallDir $d22
# Corrupt install: remove manifest.json from current\ dir (that's where fake pack puts files)
Remove-Item "$d22\scoop\apps\app1\current\manifest.json" -Force -ErrorAction SilentlyContinue
# Re-run — integrity check should detect missing file and repair
pwsh -File $toolkit update -Path $d22 -ManifestSource "$ps22\release-manifest.json" -PackSource $ps22 -NoInteraction
$ec22 = $LASTEXITCODE
Assert "[22] exit 0 after repair"           ($ec22 -eq 0)
Assert "[22] manifest.json restored"        (Test-Path "$d22\scoop\apps\app1\current\manifest.json")
Remove-TestDir $d22, $ps22

Write-Host "[23] Integrity — size mismatch triggers repair" -ForegroundColor Cyan
$d23 = "C:\tmp\s23d"; $ps23 = "C:\tmp\s23p"
Install-FreshApp -PackDir $ps23 -InstallDir $d23
# Corrupt install: inject extra field via substring splice — must stay valid JSON so
# Get-LocalAppVersions can read the version (repair, not re-install) and size mismatch is detected.
$raw23 = (Get-Content "$d23\scoop\apps\app1\current\manifest.json" -Raw).TrimEnd()
($raw23.Substring(0, $raw23.Length - 1) + ',"_pad":"size-pad-extra"}') |
    Set-Content "$d23\scoop\apps\app1\current\manifest.json" -Encoding UTF8
# Re-run — size mismatch should trigger repair
$out23 = pwsh -File $toolkit update -Path $d23 -ManifestSource "$ps23\release-manifest.json" -PackSource $ps23 -NoInteraction 2>&1
$ec23 = $LASTEXITCODE
Assert "[23] exit 0 after repair"           ($ec23 -eq 0)
Assert "[23] integrity fail shown"          ($out23 -match "\[!\]")
$repaired23 = (Get-Content "$d23\scoop\apps\app1\current\manifest.json" -Raw) -notmatch "_pad"
Assert "[23] manifest.json restored clean"  ($repaired23)
Remove-TestDir $d23, $ps23

Write-Host "[24] -ForceReinstall reinstalls up-to-date app" -ForegroundColor Cyan
$d24 = "C:\tmp\s24d"; $ps24 = "C:\tmp\s24p"
Install-FreshApp -PackDir $ps24 -InstallDir $d24
$out24 = pwsh -File $toolkit update -Path $d24 -ManifestSource "$ps24\release-manifest.json" -PackSource $ps24 -NoInteraction -ForceReinstall 2>&1
$ec24 = $LASTEXITCODE
Assert "[24] exit 0"                        ($ec24 -eq 0)
Assert "[24] [!] shown for forced app"      ($out24 -match "\[!\]")
Assert "[24] manifest.json present"         (Test-Path "$d24\scoop\apps\app1\current\manifest.json")
Remove-TestDir $d24, $ps24

Write-Host "[25] Integrity pass — no download when healthy" -ForegroundColor Cyan
$d25 = "C:\tmp\s25d"; $ps25 = "C:\tmp\s25p"
Install-FreshApp -PackDir $ps25 -InstallDir $d25
# Delete the zip — if integrity passes, no download is attempted and update still succeeds
Remove-Item "$ps25\app1-1.0.0.zip" -Force
$out25 = pwsh -File $toolkit update -Path $d25 -ManifestSource "$ps25\release-manifest.json" -PackSource $ps25 -NoInteraction 2>&1
$ec25 = $LASTEXITCODE
Assert "[25] exit 0 without zip"            ($ec25 -eq 0)
Assert "[25] no FAILED in output"           ($out25 -notmatch "FAILED")
Assert "[25] [=] shown (up to date)"        ($out25 -match "\[=\]")
Remove-TestDir $d25, $ps25

Write-Host "[26] -LogFile creates log file with expected output" -ForegroundColor Cyan
$d26 = "C:\tmp\s26d"; $ps26 = "C:\tmp\s26p"
& $helper -OutputDir $ps26 -Apps @(@{Name="app1";Version="1.0.0"})
New-Item -Force -ItemType Directory $d26 | Out-Null
$log26a = "C:\tmp\s26a.log"
$log26b = "C:\tmp\s26b.log"
# First instance
pwsh -File $toolkit update -Path $d26 -ManifestSource "$ps26\release-manifest.json" -PackSource $ps26 -NoInteraction -LogFile $log26a
$ec26a = $LASTEXITCODE
# Second instance (separate install dir)
$d26b = "C:\tmp\s26db"
New-Item -Force -ItemType Directory $d26b | Out-Null
pwsh -File $toolkit update -Path $d26b -ManifestSource "$ps26\release-manifest.json" -PackSource $ps26 -NoInteraction -LogFile $log26b
$ec26b = $LASTEXITCODE
Assert "[26] exit 0 with -LogFile (a)"     ($ec26a -eq 0)
Assert "[26] exit 0 with -LogFile (b)"     ($ec26b -eq 0)
Assert "[26] log file a created"           (Test-Path $log26a)
Assert "[26] log file b created"           (Test-Path $log26b)
Assert "[26] log a contains app1"          ((Get-Content $log26a -Raw) -match "app1")
Assert "[26] log b contains app1"          ((Get-Content $log26b -Raw) -match "app1")
Assert "[26] logs are separate files"      ($log26a -ne $log26b)
Remove-TestDir $d26, $d26b, $ps26
Remove-Item $log26a, $log26b -Force -ErrorAction SilentlyContinue

Write-Host "[27] packUrl — pack fetched from explicit URL when absent from local source" -ForegroundColor Cyan
$d27 = "C:\tmp\s27d"; $ps27 = "C:\tmp\s27p"; $ps27b = "C:\tmp\s27pb"
& $helper -OutputDir $ps27 -Apps @(@{Name="app1";Version="1.0.0"})
New-Item -Force -ItemType Directory $ps27b | Out-Null
# Serve the pack over localhost HTTP — file:// is not supported by Invoke-WebRequest in
# Nano Server, so a minimal HttpListener is the lightest hermetic alternative.
# The job creates its own listener (objects are not serialisable across job boundaries).
$port27 = 18099
$zip27  = "$ps27\app1-1.0.0.zip"
$serverJob27 = Start-Job -ScriptBlock {
    param([int]$port, [string]$zipPath)
    $l = [System.Net.HttpListener]::new()
    $l.Prefixes.Add("http://localhost:$port/")
    $l.Start()
    try {
        $ctx   = $l.GetContext()
        $bytes = [System.IO.File]::ReadAllBytes($zipPath)
        $ctx.Response.ContentType        = 'application/zip'
        $ctx.Response.ContentLength64    = $bytes.Length
        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $ctx.Response.Close()
    } finally { $l.Stop() }
} -ArgumentList $port27, $zip27
Start-Sleep -Seconds 1   # let the listener bind before toolset connects
# ps27b has the manifest but NOT the zip — toolset must follow packUrl
$mf27 = Get-Content "$ps27\release-manifest.json" -Raw | ConvertFrom-Json
$mf27.apps[0] | Add-Member -NotePropertyName packUrl `
    -NotePropertyValue "http://localhost:$port27/app1-1.0.0.zip" -Force
$mf27 | ConvertTo-Json -Depth 5 | Set-Content "$ps27b\release-manifest.json" -Encoding UTF8
New-Item -Force -ItemType Directory $d27 | Out-Null
# No -PackSource: L: is unavailable in the container → falls through to packUrl download
pwsh -File $toolkit update -Path $d27 -ManifestSource "$ps27b\release-manifest.json" -NoInteraction
$ec27 = $LASTEXITCODE
Wait-Job $serverJob27 -Timeout 10 | Out-Null
Remove-Job $serverJob27 -Force -ErrorAction SilentlyContinue
Assert "[27] exit 0"         ($ec27 -eq 0)
Assert "[27] app1 installed" (Test-Path "$d27\scoop\apps\app1\current\manifest.json")
Remove-TestDir $d27, $ps27, $ps27b

Write-Host "[28] Fresh install — scoop pack bootstraps current\ junction" -ForegroundColor Cyan
$d28 = "C:\tmp\s28d"; $ps28 = "C:\tmp\s28p"
New-Item -Force -ItemType Directory $ps28 | Out-Null
# Build a minimal fake scoop pack: versioned dir only, no current\ (mirrors real pack layout)
Add-Type -AssemblyName System.IO.Compression.FileSystem
$scoopVer28 = "1.0.0"
$zip28 = [System.IO.Compression.ZipFile]::Open("$ps28\scoop-$scoopVer28.zip", [System.IO.Compression.ZipArchiveMode]::Create)
foreach ($e28 in @(
    @{ name = "scoop/$scoopVer28/manifest.json"; content = "{`"version`":`"$scoopVer28`"}" }
    @{ name = "scoop/$scoopVer28/bin/scoop.ps1"; content = "# fake scoop stub" }
)) {
    $ze = $zip28.CreateEntry($e28.name, [System.IO.Compression.CompressionLevel]::Optimal)
    $sw = [System.IO.StreamWriter]::new($ze.Open())
    $sw.Write($e28.content); $sw.Dispose()
}
$zip28.Dispose()
# app1 pack via helper (includes current\ in zip for test simplicity)
& $helper -OutputDir $ps28 -Apps @(@{Name="app1";Version="1.0.0"})
# Manifest with scoop first (as build.ps1 now produces)
@{
    version = "99.0.0"
    built   = (Get-Date -Format "o")
    apps    = @(
        @{ name = "scoop"; version = $scoopVer28; pack = "scoop-$scoopVer28.zip" }
        @{ name = "app1";  version = "1.0.0";     pack = "app1-1.0.0.zip" }
    )
} | ConvertTo-Json -Depth 5 | Set-Content "$ps28\release-manifest.json" -Encoding UTF8
New-Item -Force -ItemType Directory $d28 | Out-Null
pwsh -File $toolkit update -Path $d28 -ManifestSource "$ps28\release-manifest.json" -PackSource $ps28 -NoInteraction
$ec28 = $LASTEXITCODE
Assert "[28] exit 0"                 ($ec28 -eq 0)
Assert "[28] scoop current\ created" (Test-Path "$d28\scoop\apps\scoop\current")
Assert "[28] scoop.ps1 accessible"   (Test-Path "$d28\scoop\apps\scoop\current\bin\scoop.ps1")
Assert "[28] app1 installed"         (Test-Path "$d28\scoop\apps\app1\current\manifest.json")
Remove-TestDir $d28, $ps28

Write-Host "[29] Update — old version with scoop-style junctions (persist + current) removed cleanly" -ForegroundColor Cyan
# Reproduces the prod "Access Denied" failure: Remove-Item -Recurse cannot traverse a dir
# tree that contains junction points.  Mimics a real scoop install:
#   scoop\apps\app1\1.0.0\           versioned dir
#   scoop\apps\app1\1.0.0\data\      junction -> scoop\persist\app1\data\  (persist)
#   scoop\apps\app1\current\         junction -> scoop\apps\app1\1.0.0\
$d29  = "C:\tmp\s29d"; $ps29 = "C:\tmp\s29p"
New-Item -Force -ItemType Directory $ps29 | Out-Null
# New pack uses real versioned-dir layout (no current\ in zip, mirrors build.ps1 output)
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip29 = [System.IO.Compression.ZipFile]::Open("$ps29\app1-2.0.0.zip", [System.IO.Compression.ZipArchiveMode]::Create)
$ze29  = $zip29.CreateEntry("app1/2.0.0/manifest.json", [System.IO.Compression.CompressionLevel]::Optimal)
$sw29  = [System.IO.StreamWriter]::new($ze29.Open()); $sw29.Write('{"version":"2.0.0"}'); $sw29.Dispose()
$zip29.Dispose()
@{ version = "99.0.0"; apps = @(@{ name = "app1"; version = "2.0.0"; pack = "app1-2.0.0.zip" }) } |
    ConvertTo-Json -Depth 5 | Set-Content "$ps29\release-manifest.json" -Encoding UTF8
# Old install: versioned dir with a persist junction inside + current\ junction
$appDir29     = "$d29\scoop\apps\app1"
$verDir29old  = "$appDir29\1.0.0"
$persistDir29 = "$d29\scoop\persist\app1\data"
New-Item -Force -ItemType Directory $verDir29old  | Out-Null
New-Item -Force -ItemType Directory $persistDir29 | Out-Null
@{ version = "1.0.0" } | ConvertTo-Json | Set-Content "$verDir29old\manifest.json" -Encoding UTF8
New-Item -ItemType Junction -Path "$verDir29old\data" -Value $persistDir29 | Out-Null
New-Item -ItemType Junction -Path "$appDir29\current" -Value $verDir29old  | Out-Null
$out29 = pwsh -File $toolkit update -Path $d29 `
    -ManifestSource "$ps29\release-manifest.json" -PackSource $ps29 -NoInteraction 2>&1
$ec29  = $LASTEXITCODE
$ver29 = try { (Get-Content "$d29\scoop\apps\app1\current\manifest.json" -Raw | ConvertFrom-Json).version } catch { "" }
Assert "[29] exit 0"                  ($ec29 -eq 0)
Assert "[29] no FAILED in output"     ($out29 -notmatch "FAILED")
Assert "[29] v2.0.0 current"          ($ver29 -eq "2.0.0")
Assert "[29] old version dir removed" (-not (Test-Path "$appDir29\1.0.0"))
Assert "[29] persist data untouched"  (Test-Path $persistDir29)
Remove-TestDir $d29, $ps29

Write-Host "[30] Version detection — versioned dir preferred over stale current\ junction" -ForegroundColor Cyan
# Scenario: the new version dir has already been extracted (e.g. from a prior partial update)
# but the current\ junction still points to the old version.  Get-LocalAppVersions must
# detect v2.0.0 from the versioned dir and NOT trigger a re-download.
$d30 = "C:\tmp\s30d"; $ps30 = "C:\tmp\s30p"
New-Item -Force -ItemType Directory $ps30 | Out-Null
# Release manifest says app1 is at v2.0.0.  No fileCount — graceful degradation so the test
# focuses purely on version detection, not integrity.
@{
    version = "99.0.0"
    apps    = @(@{ name = "app1"; version = "2.0.0"; pack = "app1-2.0.0.zip" })
} | ConvertTo-Json -Depth 5 | Set-Content "$ps30\release-manifest.json" -Encoding UTF8
# Old version dir
$v1Dir30 = "$d30\scoop\apps\app1\1.0.0"
New-Item -Force -ItemType Directory $v1Dir30 | Out-Null
@{ version = "1.0.0" } | ConvertTo-Json | Set-Content "$v1Dir30\manifest.json" -Encoding UTF8
# New version dir already present (fully populated — simulates successful prior extraction)
$v2Dir30 = "$d30\scoop\apps\app1\2.0.0"
New-Item -Force -ItemType Directory $v2Dir30 | Out-Null
@{ version = "2.0.0" } | ConvertTo-Json | Set-Content "$v2Dir30\manifest.json" -Encoding UTF8
# current\ junction still points to old v1 dir (not yet updated by scoop reset)
New-Item -ItemType Junction -Path "$d30\scoop\apps\app1\current" -Value $v1Dir30 | Out-Null
# No zip in pack source — if a download is attempted the test will FAIL with a download error
$out30 = pwsh -File $toolkit update -Path $d30 `
    -ManifestSource "$ps30\release-manifest.json" -PackSource $ps30 -NoInteraction 2>&1
$ec30  = $LASTEXITCODE
Assert "[30] exit 0 (v2.0.0 detected without download)" ($ec30 -eq 0)
Assert "[30] [=] shown (app is up to date)"             ($out30 -match "\[=\]")
Assert "[30] no FAILED in output"                       ($out30 -notmatch "FAILED")
Remove-TestDir $d30, $ps30

Write-Host "[31] Integrity — persist junction with user files does not trigger repair" -ForegroundColor Cyan
# Scenario: an app is installed cleanly (fileCount=1: manifest.json only).  Scoop then
# creates a persist junction inside the versioned dir pointing to a user-writable directory.
# Users add files to that directory (settings, history, etc.).  Get-FilesNoJunction must
# stop at the junction so the extra files do not inflate the count and falsely flag repair.
$d31 = "C:\tmp\s31d"; $ps31 = "C:\tmp\s31p"; $persist31 = "C:\tmp\s31persist"
& $helper -OutputDir $ps31 -Apps @(@{Name="app1"; Version="1.0.0"})
New-Item -Force -ItemType Directory $d31 | Out-Null
# Fresh install — fileCount=1 (manifest.json only)
pwsh -File $toolkit update -Path $d31 `
    -ManifestSource "$ps31\release-manifest.json" -PackSource $ps31 -NoInteraction
# Simulate scoop persist: replace a subdir with a junction into a user-writable location
New-Item -Force -ItemType Directory $persist31 | Out-Null
Set-Content "$persist31\user-settings.json" "{}" -Encoding UTF8          # user file 1
Set-Content "$persist31\user-history.txt"   "history" -Encoding UTF8     # user file 2
New-Item -ItemType Junction -Path "$d31\scoop\apps\app1\current\userdata" -Value $persist31 | Out-Null
# Remove the zip — if integrity fails and a repair is attempted, the test will FAILED
Remove-Item "$ps31\app1-1.0.0.zip" -Force
$out31 = pwsh -File $toolkit update -Path $d31 `
    -ManifestSource "$ps31\release-manifest.json" -PackSource $ps31 -NoInteraction 2>&1
$ec31  = $LASTEXITCODE
Assert "[31] exit 0 (persist files ignored)"                    ($ec31 -eq 0)
Assert "[31] [=] shown (integrity passes despite extra files)"  ($out31 -match "\[=\]")
Assert "[31] no FAILED in output"                               ($out31 -notmatch "FAILED")
Assert "[31] persist data untouched"                            (Test-Path "$persist31\user-settings.json")
Remove-TestDir $d31, $ps31, $persist31

Write-Host "[32] Integrity — integrityExcludePaths suppresses extra files in real subdir" -ForegroundColor Cyan
# Scenario: cmder-style app has a real subdir (vendor\conemu-maximus5) that accumulates
# user files after install. The manifest lists it in integrityExcludePaths so those extra
# files are ignored and integrity passes.
$d32 = "C:\tmp\s32d"; $ps32 = "C:\tmp\s32p"
New-Item -Force -ItemType Directory $ps32 | Out-Null
# Build a fake app dir: one base file + the excluded real subdir
$tmp32 = Join-Path $env:TEMP "fakepck32-$(Get-Random)"
$app32Dir = "$tmp32\app32\current"
New-Item -Force -ItemType Directory $app32Dir | Out-Null
Set-Content "$app32Dir\manifest.json" (@{version="1.0.0"}|ConvertTo-Json) -Encoding UTF8
# The excluded subdir has user files -- must NOT be counted in the manifest
$exc32 = "$tmp32\app32\user-cache"; New-Item -Force -ItemType Directory $exc32 | Out-Null
Set-Content "$exc32\cache.dat" "user-data" -Encoding UTF8
# Count only the non-excluded files (manifest.json = 1 file)
$fileCount32 = 1
$totalSize32  = (Get-Item "$app32Dir\manifest.json").Length
Compress-Archive -Path "$tmp32\app32" -DestinationPath "$ps32\app32-1.0.0.zip" -Force
Remove-Item $tmp32 -Recurse -Force -ErrorAction SilentlyContinue
# Manifest records counts WITHOUT the excluded subdir, plus integrityExcludePaths
@{
    version = "99.0.0"; built = (Get-Date -Format "o")
    apps = @(@{name="app32"; version="1.0.0"; pack="app32-1.0.0.zip"
               fileCount=$fileCount32; totalSize=$totalSize32
               integrityExcludePaths=@("user-cache")})
} | ConvertTo-Json -Depth 5 | Set-Content "$ps32\release-manifest.json" -Encoding UTF8
# Fresh install
pwsh -File $toolkit update -Path $d32 `
    -ManifestSource "$ps32\release-manifest.json" -PackSource $ps32 -NoInteraction
# Add extra user files into the excluded dir (simulating post-install user activity)
Set-Content "$d32\scoop\apps\app32\current\user-cache\extra1.dat" "extra" -Encoding UTF8
Set-Content "$d32\scoop\apps\app32\current\user-cache\extra2.dat" "extra" -Encoding UTF8
# Remove zip so a repair would fail with a clear error
Remove-Item "$ps32\app32-1.0.0.zip" -Force
$out32 = pwsh -File $toolkit update -Path $d32 `
    -ManifestSource "$ps32\release-manifest.json" -PackSource $ps32 -NoInteraction 2>&1
$ec32  = $LASTEXITCODE
Assert "[32] exit 0 (excluded dir ignored)"                 ($ec32 -eq 0)
Assert "[32] [=] shown (integrity passes)"                  ($out32 -match "\[=\]")
Assert "[32] no FAILED in output"                           ($out32 -notmatch "FAILED")
Remove-TestDir $d32, $ps32

Write-Host "[33] Remove-Junction removes a broken junction cleanly" -ForegroundColor Cyan
# A junction whose target no longer exists (broken junction) must be removable without error.
$brokenTarget33 = "C:\tmp\s33target"
$brokenJunction33 = "C:\tmp\s33junction"
New-Item -Force -ItemType Directory $brokenTarget33 | Out-Null
New-Item -ItemType Junction -Path $brokenJunction33 -Value $brokenTarget33 | Out-Null
Remove-Item $brokenTarget33 -Force   # target gone -- junction is now broken
# Verify junction entry still exists (broken)
$attr33 = try { [System.IO.File]::GetAttributes($brokenJunction33) } catch { 0 }
Assert "[33] broken junction entry exists before removal" ([bool]($attr33 -band [System.IO.FileAttributes]::ReparsePoint))
# Load Remove-Junction from toolset.ps1 and call it
$removeJunctionDef = Get-Content $toolkit -Raw |
    Select-String -Pattern '(?ms)function Remove-Junction.*?^}' -AllMatches |
    ForEach-Object { $_.Matches.Value } | Select-Object -First 1
Invoke-Expression $removeJunctionDef
Remove-Junction $brokenJunction33
Assert "[33] broken junction entry removed" (-not (Test-Path $brokenJunction33) -and `
    -not ([bool](try { [System.IO.File]::GetAttributes($brokenJunction33) -band [System.IO.FileAttributes]::ReparsePoint } catch { 0 })))
Remove-TestDir $brokenTarget33   # already gone, no-op


Write-Host "[34] Integrity -- exclusion works with versioned dir layout (scoop real structure)" -ForegroundColor Cyan
# Scenario: app is installed as scoop\apps\app34\1.0.0\ (versioned dir) with current\ as a
# junction.  Test-AppIntegrity measures from 1.0.0\ as root.  Excluded path "user-cache" must
# match relative to that root -- this exercises the regression fixed in build.ps1 where
# Measure-SourceNoJunction was called with a relative path causing wrong relative path offsets.
$d34     = "C:\tmp\s34d"
$ps34    = "C:\tmp\s34p"
$ver34   = "$d34\scoop\apps\app34\1.0.0"
$exc34   = "$ver34\user-cache"
New-Item -Force -ItemType Directory $ver34 | Out-Null
New-Item -Force -ItemType Directory $exc34 | Out-Null
Set-Content "$ver34\manifest.json" (@{version="1.0.0"} | ConvertTo-Json) -Encoding UTF8
Set-Content "$ver34\base.txt"      "base-content"                         -Encoding UTF8
# current\ -> versioned dir (exactly like real scoop after 'scoop reset')
New-Item -ItemType Junction -Path "$d34\scoop\apps\app34\current" -Value $ver34 | Out-Null
# manifest: count only manifest.json + base.txt (2 files); user-cache\ excluded
$fc34 = 2
$ts34 = (Get-Item "$ver34\manifest.json").Length + (Get-Item "$ver34\base.txt").Length
New-Item -Force -ItemType Directory $ps34 | Out-Null
@{
    version = "99.0.0"; built = (Get-Date -Format "o")
    apps = @(@{ name="app34"; version="1.0.0"; fileCount=$fc34; totalSize=$ts34
                integrityExcludePaths=@("user-cache") })
} | ConvertTo-Json -Depth 5 | Set-Content "$ps34\release-manifest.json" -Encoding UTF8
# --- pass A: excluded dir is empty (fresh install state) -- should be [=] ---
$outA34 = pwsh -File $toolkit status -Path $d34 -ManifestSource "$ps34\release-manifest.json" -NoInteraction 2>&1
Assert "[34] [=] with empty excluded dir (versioned layout)"   ($outA34 -match "\[=\]")
Assert "[34] no [!] on fresh install (versioned layout)"       ($outA34 -notmatch "\[!\]")
# --- pass B: user adds files to the excluded dir -- must still be [=] ---
Set-Content "$exc34\colour-scheme.xml" "<scheme/>" -Encoding UTF8
Set-Content "$exc34\backup.xml"        "<bak/>"    -Encoding UTF8
$outB34 = pwsh -File $toolkit status -Path $d34 -ManifestSource "$ps34\release-manifest.json" -NoInteraction 2>&1
Assert "[34] [=] after user files added to excluded dir"       ($outB34 -match "\[=\]")
Assert "[34] no [!] after user files in excluded dir"          ($outB34 -notmatch "\[!\]")
# --- pass C: file added OUTSIDE the excluded dir -- must flag [!] integrity fail ---
Set-Content "$ver34\extra-injected.dll" "injected" -Encoding UTF8
$outC34 = pwsh -File $toolkit status -Path $d34 -ManifestSource "$ps34\release-manifest.json" -NoInteraction 2>&1
Assert "[34] [!] when non-excluded file is added"              ($outC34 -match "\[!\]")
Remove-TestDir $d34, $ps34


if ($script:fail -gt 0) {
    Write-Host ""
    Write-Host "Failed assertions:" -ForegroundColor Red
    foreach ($f in $failedAssertions) { Write-Host "  - $f" -ForegroundColor Red }
    exit 1
}
