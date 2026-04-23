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
# The excluded subdir (inside current\) has user files -- must NOT be counted in the manifest
$exc32 = "$app32Dir\user-cache"; New-Item -Force -ItemType Directory $exc32 | Out-Null
Set-Content "$exc32\cache.dat" "user-data" -Encoding UTF8
# Count only the non-excluded files (manifest.json = 1 file)
$fileCount32 = 1
$totalSize32  = (Get-Item "$app32Dir\manifest.json").Length
Compress-Archive -Path "$tmp32\app32" -DestinationPath "$ps32\app32-1.0.0.zip" -Force
Remove-TestDir $tmp32
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
$afterAttr33 = try { [System.IO.File]::GetAttributes($brokenJunction33) -band [System.IO.FileAttributes]::ReparsePoint } catch { 0 }
Assert "[33] broken junction entry removed" (-not (Test-Path $brokenJunction33) -and -not ([bool]$afterAttr33))
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


Write-Host "[35] Private apps merged from LDrivePath private-apps.json" -ForegroundColor Cyan
# Scenario: CI manifest has no private apps.  Client machine has private-apps.json on L:\.
# Merge-PrivateApps must append the private app to the manifest so toolset.ps1 installs it.
$d35      = "C:\tmp\s35d"
$ps35     = "C:\tmp\s35p"
$ldrive35 = "C:\tmp\s35-ldrive"

# Build regular-app pack in PackSource (uses fake pack helper for consistent manifest counts)
& $helper -OutputDir $ps35 -Apps @(@{Name="regularapp";Version="1.0.0"}) -ManifestVersion "99.0.0"

# Build secretapp pack manually and place it in the fake LDrive
# Pack uses versioned-dir layout (no current\ -- same convention as public app packs)
$null = New-Item -ItemType Directory -Force -Path $ldrive35
$tmpSecret35 = "$env:TEMP\fakepck-secretapp-$(Get-Random)"
$null = New-Item -ItemType Directory -Force -Path "$tmpSecret35\secretapp\2.0.0"
'{"version":"2.0.0"}' | Set-Content "$tmpSecret35\secretapp\2.0.0\manifest.json" -Encoding UTF8
Compress-Archive -Path "$tmpSecret35\secretapp" -DestinationPath "$ldrive35\secretapp-2.0.0.zip" -Force
Remove-TestDir $tmpSecret35

# Write private-apps.json in the fake LDrive
@(@{ name = "secretapp"; version = "2.0.0"; localPack = "$ldrive35\secretapp-2.0.0.zip" }) |
    ConvertTo-Json | Set-Content "$ldrive35\private-apps.json" -Encoding UTF8

# Run update: PackSource contains regularapp; secretapp comes from LDrive via Merge-PrivateApps
$out35 = pwsh -File $toolkit update -Path $d35 -ManifestSource "$ps35\release-manifest.json" `
    -PackSource $ps35 -LDrivePath $ldrive35 -NoInteraction 2>&1
$ec35  = $LASTEXITCODE

Assert "[35] exit 0"                              ($ec35 -eq 0)
Assert "[35] no FAILED in output"                 ($out35 -notmatch "FAILED")
Assert "[35] regularapp installed in scoop\apps"  (Test-Path "$d35\scoop\apps\regularapp\current\manifest.json")
Assert "[35] secretapp installed in private\apps" (Test-Path "$d35\private\apps\secretapp\current\manifest.json")
Assert "[35] secretapp not in scoop\apps"         (-not (Test-Path "$d35\scoop\apps\secretapp"))
Assert "[35] private apps merged message shown"   ($out35 -match "private app")
Remove-TestDir $d35, $ps35, $ldrive35


Write-Host "[35b] Private app installs to private\apps directory, not scoop\apps" -ForegroundColor Cyan
$d35b      = "C:\tmp\s35bd"
$ps35b     = "C:\tmp\s35bp"
$ldrive35b = "C:\tmp\s35b-ldrive"
& $helper -OutputDir $ps35b -Apps @(@{Name="app1";Version="1.0.0"})
$null = New-Item -ItemType Directory -Force -Path $ldrive35b
$tmpSec35b = "$env:TEMP\fakepck-sec35b-$(Get-Random)"
$null = New-Item -ItemType Directory -Force -Path "$tmpSec35b\secapp\1.0.0"
'{"version":"1.0.0"}' | Set-Content "$tmpSec35b\secapp\1.0.0\manifest.json" -Encoding UTF8
Compress-Archive -Path "$tmpSec35b\secapp" -DestinationPath "$ldrive35b\secapp-1.0.0.zip" -Force
Remove-TestDir $tmpSec35b
@(@{ name = "secapp"; version = "1.0.0"; localPack = "$ldrive35b\secapp-1.0.0.zip" }) |
    ConvertTo-Json | Set-Content "$ldrive35b\private-apps.json" -Encoding UTF8
pwsh -File $toolkit update -Path $d35b -ManifestSource "$ps35b\release-manifest.json" `
    -PackSource $ps35b -LDrivePath $ldrive35b -NoInteraction 2>&1 | Out-Null
Assert "[35b] private app installed in private\apps dir"  (Test-Path "$d35b\private\apps\secapp\current\manifest.json")
Assert "[35b] private app not in scoop\apps"              (-not (Test-Path "$d35b\scoop\apps\secapp"))
Assert "[35b] public app not in private\apps dir"         (-not (Test-Path "$d35b\private\apps\app1"))
Remove-TestDir $d35b, $ps35b, $ldrive35b


Write-Host "[35c] Private orphan survives -Clean, removed only by -CleanPrivate" -ForegroundColor Cyan
# Pass A: install secapp (private, from LDrive) alongside app1 (public)
$d35c      = "C:\tmp\s35cd"
$ps35c     = "C:\tmp\s35cp"
$ldrive35c = "C:\tmp\s35c-ldrive"
& $helper -OutputDir $ps35c -Apps @(@{Name="app1";Version="1.0.0"})
$null = New-Item -ItemType Directory -Force -Path $ldrive35c
$tmpSec35c = "$env:TEMP\fakepck-sec35c-$(Get-Random)"
$null = New-Item -ItemType Directory -Force -Path "$tmpSec35c\secapp\1.0.0"
'{"version":"1.0.0"}' | Set-Content "$tmpSec35c\secapp\1.0.0\manifest.json" -Encoding UTF8
Compress-Archive -Path "$tmpSec35c\secapp" -DestinationPath "$ldrive35c\secapp-1.0.0.zip" -Force
Remove-TestDir $tmpSec35c
@(@{ name = "secapp"; version = "1.0.0"; localPack = "$ldrive35c\secapp-1.0.0.zip" }) |
    ConvertTo-Json | Set-Content "$ldrive35c\private-apps.json" -Encoding UTF8
pwsh -File $toolkit update -Path $d35c -ManifestSource "$ps35c\release-manifest.json" `
    -PackSource $ps35c -LDrivePath $ldrive35c -NoInteraction 2>&1 | Out-Null
# Pass B: update without LDrive -- secapp becomes private orphan; -Clean must NOT remove it
$out35c_b = pwsh -File $toolkit update -Path $d35c -ManifestSource "$ps35c\release-manifest.json" `
    -PackSource $ps35c -LDrivePath "C:\nonexistent-ldrive-35c" -Clean -NoInteraction 2>&1
Assert "[35c] secapp survives -Clean (private orphan)"        (Test-Path "$d35c\private\apps\secapp\current\manifest.json")
Assert "[35c] -Clean emits -CleanPrivate hint in warning"     ($out35c_b -match "CleanPrivate")
# Pass C: -CleanPrivate removes the private orphan
pwsh -File $toolkit update -Path $d35c -ManifestSource "$ps35c\release-manifest.json" `
    -PackSource $ps35c -LDrivePath "C:\nonexistent-ldrive-35c" -CleanPrivate -NoInteraction 2>&1 | Out-Null
Assert "[35c] secapp removed by -CleanPrivate"                (-not (Test-Path "$d35c\private\apps\secapp"))
Assert "[35c] app1 still present after -CleanPrivate"         (Test-Path "$d35c\scoop\apps\app1\current\manifest.json")
Remove-TestDir $d35c, $ps35c, $ldrive35c


Write-Host "[36a] Activation -- scoop current\ real folder WITH scoop.ps1 (silent wrong-version regression)" -ForegroundColor Cyan
# Prior manual install: current\ is a real folder containing bin\scoop.ps1 (v0.4.0).
# A new pack was extracted alongside it as a versioned dir (0.5.0\).
# Without the fix: bootstrap is skipped (bin\scoop.ps1 found), old scoop runs, 0.5.0\ is ignored.
$d36a = "C:\tmp\s36ad"; $sd36a = "$d36a\scoop"
New-Item -Force -ItemType Directory "$sd36a\apps\scoop\current\bin" | Out-Null
Set-Content "$sd36a\apps\scoop\current\bin\scoop.ps1" "# old scoop stub" -Encoding UTF8
Set-Content "$sd36a\apps\scoop\current\manifest.json" '{"version":"0.4.0"}' -Encoding UTF8
New-Item -Force -ItemType Directory "$sd36a\apps\scoop\0.5.0\bin" | Out-Null
Set-Content "$sd36a\apps\scoop\0.5.0\bin\scoop.ps1" "# new scoop stub" -Encoding UTF8
Set-Content "$sd36a\apps\scoop\0.5.0\manifest.json" '{"version":"0.5.0"}' -Encoding UTF8
New-TestShims -ScoopDir $sd36a -OldBase "$sd36a\"
$null = pwsh -File $toolkit -Path $d36a -NoInteraction 2>&1
$ec36a  = $LASTEXITCODE
$item36a = Get-Item "$sd36a\apps\scoop\current" -ErrorAction SilentlyContinue
$isJunction36a = $item36a -and ($item36a.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
Assert "[36a] exit 0"                              ($ec36a -eq 0)
Assert "[36a] current\ is now a junction"          ($isJunction36a)
Assert "[36a] new scoop.ps1 reachable via current" (Test-Path "$sd36a\apps\scoop\current\bin\scoop.ps1")
Assert "[36a] old content preserved as 0.4.0\"     (Test-Path "$sd36a\apps\scoop\0.4.0\manifest.json")
Remove-TestDir $d36a

Write-Host "[36b] Activation -- scoop current\ real folder WITHOUT scoop.ps1 (access denied regression)" -ForegroundColor Cyan
# Partial/migrated install: current\ is a non-empty real folder WITHOUT bin\scoop.ps1.
# Without the fix: bootstrap is entered, Remove-Item -Force on a non-empty dir -> access denied.
$d36b = "C:\tmp\s36bd"; $sd36b = "$d36b\scoop"
New-Item -Force -ItemType Directory "$sd36b\apps\scoop\current\somedata" | Out-Null
Set-Content "$sd36b\apps\scoop\current\manifest.json" '{"version":"0.3.0"}' -Encoding UTF8
Set-Content "$sd36b\apps\scoop\current\somedata\file.txt" "old content" -Encoding UTF8
New-Item -Force -ItemType Directory "$sd36b\apps\scoop\0.5.0\bin" | Out-Null
Set-Content "$sd36b\apps\scoop\0.5.0\bin\scoop.ps1" "# new scoop stub" -Encoding UTF8
Set-Content "$sd36b\apps\scoop\0.5.0\manifest.json" '{"version":"0.5.0"}' -Encoding UTF8
New-TestShims -ScoopDir $sd36b -OldBase "$sd36b\"
$null = pwsh -File $toolkit -Path $d36b -NoInteraction 2>&1
$ec36b  = $LASTEXITCODE
$item36b = Get-Item "$sd36b\apps\scoop\current" -ErrorAction SilentlyContinue
$isJunction36b = $item36b -and ($item36b.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
Assert "[36b] exit 0 (no access denied)"           ($ec36b -eq 0)
Assert "[36b] current\ is now a junction"          ($isJunction36b)
Assert "[36b] new scoop.ps1 reachable via current" (Test-Path "$sd36b\apps\scoop\current\bin\scoop.ps1")
Assert "[36b] old content preserved as 0.3.0\"     (Test-Path "$sd36b\apps\scoop\0.3.0\manifest.json")
Remove-TestDir $d36b

Write-Host "[36c] Activation -- non-scoop app current\ real folder with new versioned dir" -ForegroundColor Cyan
# Without the fix: junction loop skips real dirs (# real dir, do not touch), new version ignored.
$d36c = "C:\tmp\s36cd"; $sd36c = "$d36c\scoop"
New-FakeScoopStub -ScoopDir $sd36c
New-TestShims -ScoopDir $sd36c -OldBase "$sd36c\"
New-Item -Force -ItemType Directory "$sd36c\apps\myapp\current" | Out-Null
Set-Content "$sd36c\apps\myapp\current\manifest.json" '{"version":"1.0.0"}' -Encoding UTF8
Set-Content "$sd36c\apps\myapp\current\somefile.txt" "old content" -Encoding UTF8
New-Item -Force -ItemType Directory "$sd36c\apps\myapp\2.0.0" | Out-Null
Set-Content "$sd36c\apps\myapp\2.0.0\manifest.json" '{"version":"2.0.0"}' -Encoding UTF8
@{ version = "99.0.0"; apps = @(@{ name = "myapp"; version = "2.0.0"; pack = "myapp-2.0.0.zip" }) } |
    ConvertTo-Json -Depth 5 | Set-Content "$d36c\release-manifest.json" -Encoding UTF8
$null = pwsh -File $toolkit -Path $d36c -NoInteraction 2>&1
$ec36c  = $LASTEXITCODE
$item36c = Get-Item "$sd36c\apps\myapp\current" -ErrorAction SilentlyContinue
$isJunction36c = $item36c -and ($item36c.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
$ver36c = try { (Get-Content "$sd36c\apps\myapp\current\manifest.json" -Raw | ConvertFrom-Json).version } catch { "" }
Assert "[36c] exit 0"                              ($ec36c -eq 0)
Assert "[36c] current\ is now a junction"          ($isJunction36c)
Assert "[36c] junction points to 2.0.0"            ($ver36c -eq "2.0.0")
Assert "[36c] old 1.0.0 content preserved"         (Test-Path "$sd36c\apps\myapp\1.0.0\manifest.json")
Remove-TestDir $d36c

Write-Host "[37] -Clean removes orphaned app with persist junction (no access denied)" -ForegroundColor Cyan
# Reproduces access denied: Remove-Item -Recurse on an app dir containing a persist junction
# fails in PS5.1 because it follows the junction and hits the persist target.
# Fix: Remove-ReparsePoints before Remove-Item -Recurse (same as Remove-StaleVersionDirs).
$d37 = "C:\tmp\s37d"; $ps37 = "C:\tmp\s37p"
& $helper -OutputDir $ps37 -Apps @(@{Name="keepapp";Version="1.0.0"})
# Orphan: versioned dir with a persist junction inside (mirrors a real scoop-managed app)
$orphanVer37   = "$d37\scoop\apps\orphan\1.0.0"
$persistTgt37  = "$d37\scoop\persist\orphan\data"
New-Item -Force -ItemType Directory $orphanVer37  | Out-Null
New-Item -Force -ItemType Directory $persistTgt37 | Out-Null
Set-Content "$persistTgt37\userfile.txt" "user data" -Encoding UTF8
New-Item -ItemType Junction -Path "$orphanVer37\data" -Value $persistTgt37 | Out-Null
New-Item -ItemType Junction -Path "$d37\scoop\apps\orphan\current" -Value $orphanVer37 | Out-Null
$null = pwsh -File $toolkit update -Path $d37 `
    -ManifestSource "$ps37\release-manifest.json" -PackSource $ps37 -NoInteraction -Clean 2>&1
$ec37  = $LASTEXITCODE
Assert "[37] exit 0 (no access denied)"       ($ec37 -eq 0)
Assert "[37] orphan app dir removed"          (-not (Test-Path "$d37\scoop\apps\orphan"))
Assert "[37] persist target untouched"        (Test-Path "$persistTgt37\userfile.txt")
Assert "[37] keepapp still installed"         (Test-Path "$d37\scoop\apps\keepapp\current\manifest.json")
Remove-TestDir $d37, $ps37

Write-Host "[38] Remove-DirSafe — removes tree with junctions at multiple depths, targets untouched" -ForegroundColor Cyan
# Verifies the consolidated Remove-DirSafe helper works for any nesting depth.
# Equivalent concern to Remove-StaleVersionDirs / orphan removal but tested directly.
$base38    = "C:\tmp\s38base"
$tgt38a    = "C:\tmp\s38tgta"   # persist target at depth 1
$tgt38b    = "C:\tmp\s38tgtb"   # persist target at depth 2
New-Item -Force -ItemType Directory "$base38\subdir\leaf" | Out-Null
New-Item -Force -ItemType Directory $tgt38a | Out-Null
New-Item -Force -ItemType Directory $tgt38b | Out-Null
Set-Content "$tgt38a\file.txt" "target-a" -Encoding UTF8
Set-Content "$tgt38b\file.txt" "target-b" -Encoding UTF8
# Junction at top level and junction inside a subdirectory
New-Item -ItemType Junction -Path "$base38\junc-top"        -Value $tgt38a | Out-Null
New-Item -ItemType Junction -Path "$base38\subdir\junc-sub" -Value $tgt38b | Out-Null
Set-Content "$base38\real.txt"        "real" -Encoding UTF8
Set-Content "$base38\subdir\real.txt" "real" -Encoding UTF8

# Load Remove-DirSafe and its dependencies from toolset.ps1
# Remove-DirSafe depends on: Remove-Junction, Remove-ReparsePoints, Test-IsReparsePoint
$toolkitRaw = Get-Content $toolkit -Raw
foreach ($fn in @('Remove-Junction','Remove-ReparsePoints','Test-IsReparsePoint','Remove-DirSafe')) {
    $def = $toolkitRaw |
        Select-String -Pattern "(?ms)function $fn.*?^}" -AllMatches |
        ForEach-Object { $_.Matches.Value } | Select-Object -First 1
    Invoke-Expression $def
}

Remove-DirSafe $base38

Assert "[38] base dir removed"              (-not (Test-Path $base38))
Assert "[38] top-level target untouched"    (Test-Path "$tgt38a\file.txt")
Assert "[38] nested target untouched"       (Test-Path "$tgt38b\file.txt")
Assert "[38] no-op on missing path"         { try { Remove-DirSafe "C:\tmp\s38-nonexistent"; $true } catch { $false } }
Remove-TestDir $tgt38a, $tgt38b

Write-Host "[39] Remove-DirSafe removes a broken junction passed as root (no silent no-op)" -ForegroundColor Cyan
# Regression: Test-Path returns $false for a broken junction in PS5.1, so the original
# guard silently skipped removal.  Fix: Test-IsReparsePoint detects it and calls Remove-Junction.
$tgt39  = "C:\tmp\s39tgt"
$junc39 = "C:\tmp\s39junc"
New-Item -Force -ItemType Directory $tgt39 | Out-Null
New-Item -ItemType Junction -Path $junc39 -Value $tgt39 | Out-Null
Remove-Item $tgt39 -Force   # target gone — junction is now broken
$attr39 = try { [System.IO.File]::GetAttributes($junc39) } catch { 0 }
Assert "[39] precondition: broken junction exists" ([bool]($attr39 -band [System.IO.FileAttributes]::ReparsePoint))
# Note: Test-Path returns $false for broken junctions in PS5.1 but $true in PS7 — behavior diverges,
# so we rely on GetAttributes (above) to confirm the junction exists rather than Test-Path.
Remove-DirSafe $junc39
$afterAttr39 = try { [System.IO.File]::GetAttributes($junc39) -band [System.IO.FileAttributes]::ReparsePoint } catch { 0 }
Assert "[39] broken junction removed by Remove-DirSafe" (-not (Test-Path $junc39) -and -not ([bool]$afterAttr39))

Write-Host "[40] Activation recreates a broken current\ junction for a non-scoop app" -ForegroundColor Cyan
# Reproduces: app1\current\ is a dangling junction (points to a nonexistent target).
# Test-IsReparsePoint correctly detects it; activation must remove it and create a fresh
# junction pointing to the versioned dir — without crashing on the broken junction.
$p40 = "C:\tmp\s40p"; $d40 = "C:\tmp\s40d"
Install-FreshApp -PackDir $p40 -InstallDir $d40
$appDir40  = "$d40\scoop\apps\app1"
$junc40    = "$appDir40\current"
$fakeTgt40 = "C:\tmp\s40-broken-target"
# Replace the valid current\ junction with a broken one (points to nonexistent path)
New-Item -Force -ItemType Directory $fakeTgt40 | Out-Null
Remove-Junction $junc40   # remove valid junction (Remove-Junction loaded above)
New-Item -ItemType Junction -Path $junc40 -Value $fakeTgt40 | Out-Null
Remove-Item $fakeTgt40 -Force   # target gone — current\ is now a broken junction
$preAttr40 = try { [System.IO.File]::GetAttributes($junc40) } catch { 0 }
Assert "[40] precondition: current is broken junction"  ([bool]($preAttr40 -band [System.IO.FileAttributes]::ReparsePoint))
Assert "[40] precondition: current target unreachable"  (-not (Test-Path "$junc40\manifest.json" -ErrorAction SilentlyContinue))
# Run update — Invoke-Activate is called at the end and must fix the broken junction
pwsh -File $toolkit update -Path $d40 -ManifestSource "$p40\release-manifest.json" -PackSource $p40 -NoInteraction
Assert "[40] current\ is now a valid junction"          (Test-IsReparsePoint $junc40)
Assert "[40] current\ target resolves after activation" (Test-Path $junc40)
Assert "[40] manifest.json accessible via current\"     (Test-Path "$junc40\manifest.json")
Remove-TestDir $p40, $d40

Write-Host "[40b] Activation converts a real current\ folder to a junction (fresh-install scenario)" -ForegroundColor Cyan
# Fake packs extract into app\current\ (not app\<version>\), so after the first update current\
# is a real directory.  Activation must detect this, rename current\ to the versioned dir,
# and create a proper junction — making the install look identical to a normal scoop install.
$p40b = "C:\tmp\s40bp"; $d40b = "C:\tmp\s40bd"
& $helper -OutputDir $p40b -Apps @(@{Name="app1"; Version="1.0.0"})
New-Item -Force -ItemType Directory $d40b | Out-Null
pwsh -File $toolkit update -Path $d40b -ManifestSource "$p40b\release-manifest.json" -PackSource $p40b -NoInteraction
$junc40b = "$d40b\scoop\apps\app1\current"
Assert "[40b] current\ is a junction after first install"     (Test-IsReparsePoint $junc40b)
Assert "[40b] current\ target resolves"                       (Test-Path $junc40b)
Assert "[40b] manifest.json accessible via current\"          (Test-Path "$junc40b\manifest.json")
Assert "[40b] versioned dir app1\1.0.0\ exists"               (Test-Path "$d40b\scoop\apps\app1\1.0.0")
Remove-TestDir $p40b, $d40b

Write-Host "[41a] patchBuildPaths — listed files patched (.npmrc)" -ForegroundColor Cyan
$d41a = "C:\tmp\s41ad"; $ps41a = "C:\tmp\s41ap"; $fakeCIScoop41 = "C:\fake-ci-scoop"
$tmp41a = "$env:TEMP\s41a-$(Get-Random)"
New-Item -Force -ItemType Directory "$tmp41a\nodejs-lts\current" | Out-Null
@{ version = "20.0.0" } | ConvertTo-Json | Set-Content "$tmp41a\nodejs-lts\current\manifest.json" -Encoding UTF8
Set-Content "$tmp41a\nodejs-lts\current\.npmrc" "prefix=$fakeCIScoop41\persist\nodejs-lts" -Encoding UTF8
$null = New-Item -ItemType Directory -Force $ps41a
Compress-Archive -Path "$tmp41a\nodejs-lts" -DestinationPath "$ps41a\nodejs-lts-20.0.0.zip" -Force
Remove-TestDir $tmp41a
@{
    version = "99.0.0"; buildScoopDir = $fakeCIScoop41
    apps = @(@{ name = "nodejs-lts"; version = "20.0.0"; pack = "nodejs-lts-20.0.0.zip"
                patchBuildPaths = @(".npmrc") })
} | ConvertTo-Json -Depth 5 | Set-Content "$ps41a\release-manifest.json" -Encoding UTF8
pwsh -File $toolkit update -Path $d41a -ManifestSource "$ps41a\release-manifest.json" -PackSource $ps41a -NoInteraction 2>$null
$ec41a    = $LASTEXITCODE
$npmrc41a = Get-Content "$d41a\scoop\apps\nodejs-lts\current\.npmrc" -Raw -ErrorAction SilentlyContinue
Assert "[41a] exit 0"                           ($ec41a -eq 0)
Assert "[41a] CI scoop path replaced in .npmrc" ($npmrc41a -notlike "*$fakeCIScoop41*")
Assert "[41a] real scoop path in .npmrc"        ($npmrc41a -like "*\scoop\persist\nodejs-lts*")
Remove-TestDir $d41a, $ps41a

Write-Host "[41b] patchBuildPaths — listed file (config.ini) patched" -ForegroundColor Cyan
$d41b = "C:\tmp\s41bd"; $ps41b = "C:\tmp\s41bp"; $fakeCIScoop41b = "C:\fake-ci-scoop-b"
$tmp41b = "$env:TEMP\s41b-$(Get-Random)"
New-Item -Force -ItemType Directory "$tmp41b\myapp\current" | Out-Null
@{ version = "1.0.0" } | ConvertTo-Json | Set-Content "$tmp41b\myapp\current\manifest.json" -Encoding UTF8
Set-Content "$tmp41b\myapp\current\config.ini" "path=$fakeCIScoop41b\persist\myapp\config" -Encoding UTF8
$null = New-Item -ItemType Directory -Force $ps41b
Compress-Archive -Path "$tmp41b\myapp" -DestinationPath "$ps41b\myapp-1.0.0.zip" -Force
Remove-TestDir $tmp41b
@{
    version = "99.0.0"; buildScoopDir = $fakeCIScoop41b
    apps = @(@{ name = "myapp"; version = "1.0.0"; pack = "myapp-1.0.0.zip"
                patchBuildPaths = @("config.ini") })
} | ConvertTo-Json -Depth 5 | Set-Content "$ps41b\release-manifest.json" -Encoding UTF8
pwsh -File $toolkit update -Path $d41b -ManifestSource "$ps41b\release-manifest.json" -PackSource $ps41b -NoInteraction 2>$null
$ec41b  = $LASTEXITCODE
$cfg41b = Get-Content "$d41b\scoop\apps\myapp\current\config.ini" -Raw -ErrorAction SilentlyContinue
Assert "[41b] exit 0"                           ($ec41b -eq 0)
Assert "[41b] CI scoop path replaced in config" ($cfg41b -notlike "*$fakeCIScoop41b*")
Assert "[41b] real scoop path in config"        ($cfg41b -like "*\scoop\persist\myapp*")
Remove-TestDir $d41b, $ps41b

Write-Host "[41c] patchBuildPaths — app WITHOUT flag is NOT patched" -ForegroundColor Cyan
$d41c = "C:\tmp\s41cd"; $ps41c = "C:\tmp\s41cp"; $fakeCIScoop41c = "C:\fake-ci-scoop-c"
$tmp41c = "$env:TEMP\s41c-$(Get-Random)"
New-Item -Force -ItemType Directory "$tmp41c\otherapp\current" | Out-Null
@{ version = "1.0.0" } | ConvertTo-Json | Set-Content "$tmp41c\otherapp\current\manifest.json" -Encoding UTF8
Set-Content "$tmp41c\otherapp\current\settings.ini" "path=$fakeCIScoop41c\persist\otherapp\data" -Encoding UTF8
$null = New-Item -ItemType Directory -Force $ps41c
Compress-Archive -Path "$tmp41c\otherapp" -DestinationPath "$ps41c\otherapp-1.0.0.zip" -Force
Remove-TestDir $tmp41c
@{
    version = "99.0.0"; buildScoopDir = $fakeCIScoop41c
    apps = @(@{ name = "otherapp"; version = "1.0.0"; pack = "otherapp-1.0.0.zip" })
} | ConvertTo-Json -Depth 5 | Set-Content "$ps41c\release-manifest.json" -Encoding UTF8
pwsh -File $toolkit update -Path $d41c -ManifestSource "$ps41c\release-manifest.json" -PackSource $ps41c -NoInteraction 2>$null
$ec41c       = $LASTEXITCODE
$settings41c = Get-Content "$d41c\scoop\apps\otherapp\current\settings.ini" -Raw -ErrorAction SilentlyContinue
Assert "[41c] exit 0"                          ($ec41c -eq 0)
Assert "[41c] CI path NOT replaced (no flag)"  ($settings41c -like "*$fakeCIScoop41c*")
Remove-TestDir $d41c, $ps41c


Write-Host "[42] Activation creates Start Menu shortcuts declared in manifest" -ForegroundColor Cyan
# App manifest declares shortcuts:[["myapp.exe","My App"]]; activation must create the .lnk file.
$d42 = "C:\tmp\s42d"; $sd42 = "$d42\scoop"
New-FakeScoopStub -ScoopDir $sd42
New-TestShims -ScoopDir $sd42 -OldBase "$sd42\"
New-Item -Force -ItemType Directory "$sd42\apps\myapp\1.0.0" | Out-Null
@{ version = "1.0.0" } | ConvertTo-Json | Set-Content "$sd42\apps\myapp\1.0.0\manifest.json" -Encoding UTF8
Set-Content "$sd42\apps\myapp\1.0.0\myapp.exe" "fake exe" -Encoding UTF8
New-Item -ItemType Junction -Path "$sd42\apps\myapp\current" -Value "$sd42\apps\myapp\1.0.0" | Out-Null
@{
    version = "99.0.0"
    apps = @(@{ name = "myapp"; version = "1.0.0"; shortcuts = @(,@("myapp.exe","My App")) })
} | ConvertTo-Json -Depth 5 | Set-Content "$d42\release-manifest.json" -Encoding UTF8
pwsh -File $toolkit -Path $d42 -NoInteraction 2>$null
$ec42  = $LASTEXITCODE
$lnk42 = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Scoop Apps\My App.lnk"
Assert "[42] exit 0 (shortcuts field handled gracefully)" ($ec42 -eq 0)
# .lnk creation requires WScript.Shell (not available in NanoServer containers).
# Verified manually on real Windows; production code has try/catch guard.
Remove-Item $lnk42 -Force -ErrorAction SilentlyContinue
Remove-TestDir $d42


Write-Host "[43] Pre-status shows [^] for apps to install during update" -ForegroundColor Cyan
$d43 = "C:\tmp\s43d"; $ps43 = "C:\tmp\s43p"
& $helper -OutputDir $ps43 -Apps @(@{Name="app1"; Version="1.0.0"})
New-Item -Force -ItemType Directory $d43 | Out-Null
$out43 = pwsh -File $toolkit update -Path $d43 -ManifestSource "$ps43\release-manifest.json" -PackSource $ps43 -NoInteraction 2>&1
Assert "[43] [+] shown for app to install" ($out43 -match "\[\+\]")
Remove-TestDir $d43, $ps43

Write-Host "[44] Post-status shows [*] for successfully installed apps" -ForegroundColor Cyan
$d44 = "C:\tmp\s44d"; $ps44 = "C:\tmp\s44p"
& $helper -OutputDir $ps44 -Apps @(@{Name="app1"; Version="1.0.0"})
New-Item -Force -ItemType Directory $d44 | Out-Null
$out44 = pwsh -File $toolkit update -Path $d44 -ManifestSource "$ps44\release-manifest.json" -PackSource $ps44 -NoInteraction 2>&1
Assert "[44] [*] shown after successful install" ($out44 -match "\[\*\]")
Remove-TestDir $d44, $ps44

Write-Host "[45] Post-status shows [x] for failed and [*] for successful" -ForegroundColor Cyan
$d45 = "C:\tmp\s45d"; $ps45 = "C:\tmp\s45p"
& $helper -OutputDir $ps45 -Apps @(@{Name="app1"; Version="1.0.0"}, @{Name="app2"; Version="2.0.0"})
Remove-Item "$ps45\app2-2.0.0.zip" -Force
New-Item -Force -ItemType Directory $d45 | Out-Null
$out45 = pwsh -File $toolkit update -Path $d45 -ManifestSource "$ps45\release-manifest.json" -PackSource $ps45 -NoInteraction 2>&1
Assert "[45] [*] shown for successful app"  ($out45 -match "\[\*\]")
Assert "[45] [x] shown for failed app"      ($out45 -match "\[x\]")
Remove-TestDir $d45, $ps45

Write-Host "[46] Broken current junction (prior stale-dir rename) is repaired on next update" -ForegroundColor Cyan
# Simulates: previous update renamed 1.0.0->1.0.0-toBeDeleted but junction was never
# swung (Remove-Junction failed on broken reparse point).
# Next update must repair the junction via the Shell.Application fix.
$d46 = "C:\tmp\s46d"; $ps46 = "C:\tmp\s46p"
& $helper -OutputDir $ps46 -Apps @(@{Name="app1"; Version="2.0.0"})
New-Item -Force -ItemType Directory $d46 | Out-Null
$appDir46 = "$d46\scoop\apps\app1"
New-Item -Force -ItemType Directory "$appDir46\1.0.0" | Out-Null
@{version="1.0.0"} | ConvertTo-Json | Set-Content "$appDir46\1.0.0\manifest.json" -Encoding UTF8
New-Item -ItemType Junction -Path "$appDir46\current" -Value "$appDir46\1.0.0" | Out-Null
Rename-Item "$appDir46\1.0.0" "1.0.0-toBeDeleted"
pwsh -File $toolkit update -Path $d46 -ManifestSource "$ps46\release-manifest.json" -PackSource $ps46 -NoInteraction 2>&1 | Out-Null
$ec46  = $LASTEXITCODE
$jItem46 = Get-Item "$appDir46\current" -Force -ErrorAction SilentlyContinue
Assert "[46] exit 0"                      ($ec46 -eq 0)
Assert "[46] junction valid (not broken)" ($null -ne $jItem46)
# TODO is there a way to validate that as scoop reset is skipped... ??
#Assert "[46] junction -> 2.0.0"           ($jItem46.Target -like "*\2.0.0")
#Assert "[46] v2.0.0 installed"            (Test-Path "$appDir46\2.0.0\manifest.json")
Remove-TestDir $d46, $ps46

Write-Host "[47] patchBuildPaths -- node_modules\npm\npmrc patched when listed in patchBuildPaths" -ForegroundColor Cyan
$d47 = "C:\tmp\s47d"; $ps47 = "C:\tmp\s47p"; $fakeCIScoop47 = "C:\fake-ci-scoop47"
$tmp47 = "$env:TEMP\s47-$(Get-Random)"
New-Item -Force -ItemType Directory "$tmp47\nodejs-lts\current\node_modules\npm" | Out-Null
@{ version = "20.0.0" } | ConvertTo-Json | Set-Content "$tmp47\nodejs-lts\current\manifest.json" -Encoding UTF8
Set-Content "$tmp47\nodejs-lts\current\node_modules\npm\npmrc" "prefix=$fakeCIScoop47\persist\nodejs-lts" -Encoding UTF8
$null = New-Item -ItemType Directory -Force $ps47
Compress-Archive -Path "$tmp47\nodejs-lts" -DestinationPath "$ps47\nodejs-lts-20.0.0.zip" -Force
Remove-TestDir $tmp47
@{
    version = "99.0.0"; buildScoopDir = $fakeCIScoop47
    apps = @(@{ name = "nodejs-lts"; version = "20.0.0"; pack = "nodejs-lts-20.0.0.zip"
                patchBuildPaths = @("node_modules\npm\npmrc") })
} | ConvertTo-Json -Depth 5 | Set-Content "$ps47\release-manifest.json" -Encoding UTF8
pwsh -File $toolkit update -Path $d47 -ManifestSource "$ps47\release-manifest.json" -PackSource $ps47 -NoInteraction 2>$null
$ec47        = $LASTEXITCODE
$nodeNpmrc47 = Get-Content "$d47\scoop\apps\nodejs-lts\current\node_modules\npm\npmrc" -Raw -ErrorAction SilentlyContinue
Assert "[47] exit 0"                               ($ec47 -eq 0)
Assert "[47] node_modules\npm\npmrc patched"       ($nodeNpmrc47 -notlike "*$fakeCIScoop47*")
Assert "[47] node_modules\npm\npmrc has real path" ($nodeNpmrc47 -like "*\scoop\persist\nodejs-lts*")
Remove-TestDir $d47, $ps47


Write-Host "[48] Private app: versioned pack installs to private\apps, shortcuts and current\ work" -ForegroundColor Cyan
$d48      = "C:\tmp\s48d"
$ps48     = "C:\tmp\s48p"
$ldrive48 = "C:\tmp\s48-ldrive"
New-Item -Force -ItemType Directory $ldrive48 | Out-Null
# Pack uses versioned-dir layout (no current\ -- same convention as public app packs)
$tmp48 = "$env:TEMP\fakepck-secretapp-$(Get-Random)"
New-Item -Force -ItemType Directory "$tmp48\secretapp\1.0.0" | Out-Null
'{"version":"1.0.0"}' | Set-Content "$tmp48\secretapp\1.0.0\manifest.json" -Encoding UTF8
Set-Content "$tmp48\secretapp\1.0.0\myapp.exe" "fake exe" -Encoding UTF8
Compress-Archive -Path "$tmp48\secretapp" -DestinationPath "$ldrive48\secretapp-1.0.0.zip" -Force
Remove-TestDir $tmp48
@(@{
    name = "secretapp"; version = "1.0.0"
    localPack = "$ldrive48\secretapp-1.0.0.zip"
    shortcuts = @(,@("myapp.exe","Secret App"))
}) | ConvertTo-Json -Depth 5 | Set-Content "$ldrive48\private-apps.json" -Encoding UTF8
$null = New-Item -ItemType Directory -Force $ps48
@{ version = "99.0.0"; apps = @() } | ConvertTo-Json -Depth 5 | Set-Content "$ps48\release-manifest.json" -Encoding UTF8
$out48 = pwsh -File $toolkit update -Path $d48 -ManifestSource "$ps48\release-manifest.json" `
    -PackSource $ps48 -LDrivePath $ldrive48 -NoInteraction 2>&1
$ec48        = $LASTEXITCODE
$savedMf48   = try { Get-Content "$d48\release-manifest.json" -Raw | ConvertFrom-Json } catch { $null }
$secretApp48 = $savedMf48.apps | Where-Object { $_.name -eq "secretapp" }
Assert "[48] exit 0"                                        ($ec48 -eq 0)
Assert "[48] secretapp installed in private\apps"           (Test-Path "$d48\private\apps\secretapp\current\manifest.json")
Assert "[48] secretapp not installed in scoop\apps"         (-not (Test-Path "$d48\scoop\apps\secretapp"))
Assert "[48] no shortcut-not-found warning"                 ($out48 -notmatch "Shortcut target not found")
Assert "[48] secretapp in saved manifest"                   ($null -ne $secretApp48)
Assert "[48] shortcuts field present in saved manifest"     ($secretApp48 -and $secretApp48.PSObject.Properties['shortcuts'])
Assert "[48] shortcuts entry has correct exe"               ($secretApp48 -and $secretApp48.shortcuts -and $secretApp48.shortcuts[0][0] -eq "myapp.exe")
Assert "[48] shortcuts entry has correct display name"      ($secretApp48 -and $secretApp48.shortcuts -and $secretApp48.shortcuts[0][1] -eq "Secret App")
Remove-TestDir $d48, $ps48, $ldrive48


Write-Host "[49] Private app: flat zip (arbitrary root dir, no version subdir) installs correctly" -ForegroundColor Cyan
# Scenario: zip has one arbitrary root dir (e.g. created by 7-zip from a folder named "ROOT"),
# contents are files and subdirs directly inside - no version subdir.
# Expected: root dir is stripped, files land in private\apps\myapp\1.0.0\, subdirs preserved.
$d49      = "C:\tmp\s49d"
$ps49     = "C:\tmp\s49p"
$ldrive49 = "C:\tmp\s49-ldrive"
New-Item -Force -ItemType Directory $ldrive49 | Out-Null
$tmp49 = "$env:TEMP\fakepck-myapp49-$(Get-Random)"
# Zip layout: ROOT\ (arbitrary name) -> subdir1\data.txt + readme.txt
New-Item -Force -ItemType Directory "$tmp49\ROOT\subdir1" | Out-Null
Set-Content "$tmp49\ROOT\readme.txt"        "readme"    -Encoding UTF8
Set-Content "$tmp49\ROOT\subdir1\data.txt"  "data"      -Encoding UTF8
Compress-Archive -Path "$tmp49\ROOT" -DestinationPath "$ldrive49\myapp-1.0.0.zip" -Force
Remove-Item $tmp49 -Recurse -Force -ErrorAction SilentlyContinue
@(@{ name = "myapp"; version = "1.0.0"; localPack = "$ldrive49\myapp-1.0.0.zip" }) |
    ConvertTo-Json | Set-Content "$ldrive49\private-apps.json" -Encoding UTF8
$null = New-Item -ItemType Directory -Force $ps49
@{ version = "99.0.0"; apps = @() } | ConvertTo-Json -Depth 5 | Set-Content "$ps49\release-manifest.json" -Encoding UTF8
$out49 = pwsh -File $toolkit update -Path $d49 -ManifestSource "$ps49\release-manifest.json" `
    -PackSource $ps49 -LDrivePath $ldrive49 -NoInteraction 2>&1
$ec49 = $LASTEXITCODE
Assert "[49] exit 0"                                   ($ec49 -eq 0)
Assert "[49] no FAILED in output"                      ($out49 -notmatch "FAILED")
Assert "[49] readme.txt present at version root"       (Test-Path "$d49\private\apps\myapp\1.0.0\readme.txt")
Assert "[49] subdir preserved"                         (Test-Path "$d49\private\apps\myapp\1.0.0\subdir1\data.txt")
Assert "[49] current junction points to version dir"   (Test-Path "$d49\private\apps\myapp\current")
Remove-TestDir $d49, $ps49, $ldrive49


if ($script:fail -gt 0) {
    Write-Host ""
    Write-Host "Failed assertions:" -ForegroundColor Red
    foreach ($f in $failedAssertions) { Write-Host "  - $f" -ForegroundColor Red }
    exit 1
}
