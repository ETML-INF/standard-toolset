<#
  Build pipeline tests. Runs inside the build-test container.
  Verifies pack creation, zip root structure, and manifest schema.
  Exit 0 = all pass, Exit 1 = any failure.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"
$repoRoot = "C:\toolset-repo"
. "$repoRoot\tests\Test-Helpers.ps1"

# Test apps.json — jq is pre-installed in the base image (lightweight, reliable)
$testAppsJson = "$repoRoot\apps-build-test.json"
@(@{name="jq"}) | ConvertTo-Json | Set-Content $testAppsJson -Encoding UTF8

# Clear any previous pack output so tests start clean
$buildPacks = "$repoRoot\build\packs"
if (Test-Path $buildPacks) { Remove-Item $buildPacks -Recurse -Force }

Write-Host "[B1] build.ps1 — pack creation end-to-end" -ForegroundColor Cyan
$env:RELEASE_VERSION = "test-99.0.0"
pwsh -File "$repoRoot\build.ps1" $testAppsJson 2>&1 | ForEach-Object { Write-Host "  $_" }
$ec = $LASTEXITCODE
Assert "[B1] exit 0"               ($ec -eq 0)
Assert "[B1] packs dir created"    (Test-Path $buildPacks)
Assert "[B1] release-manifest"     (Test-Path "$buildPacks\release-manifest.json")
Assert "[B1] jq pack zip"        (@(Get-ChildItem "$buildPacks\jq-*.zip" -EA SilentlyContinue).Count -gt 0)

Write-Host "[B2] release-manifest.json — schema" -ForegroundColor Cyan
$m = Get-Content "$buildPacks\release-manifest.json" -Raw | ConvertFrom-Json
$props = $m.PSObject.Properties.Name
Assert "[B2] has version"          ($props -contains 'version')
Assert "[B2] has built"            ($props -contains 'built')
Assert "[B2] has apps"             ($m.apps -ne $null -and $m.apps.Count -gt 0)
Assert "[B2] scoop is first app"   ($m.apps[0].name -eq 'scoop')
Assert "[B2] app.name"             (-not [string]::IsNullOrEmpty($m.apps[0].name))
Assert "[B2] app.version"          (-not [string]::IsNullOrEmpty($m.apps[0].version))
Assert "[B2] app.pack"             (-not [string]::IsNullOrEmpty($m.apps[0].pack))
Assert "[B2] version matches env"  ($m.version -eq "test-99.0.0")

Write-Host "[B3] pack zip — root structure (jq)" -ForegroundColor Cyan
$zip = Get-ChildItem "$buildPacks\jq-*.zip" | Select-Object -First 1
$extractDir = "C:\tmp\b3-extract"
if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
Expand-Archive $zip.FullName -DestinationPath $extractDir -Force
Assert "[B3] root dir is appName\"              (Test-Path "$extractDir\jq")
# 'current' is a junction recreated by 'scoop reset *' after deployment — not in the pack.
# The versioned directory must be present and contain manifest.json.
$verDir = Get-ChildItem "$extractDir\jq" -Directory | Where-Object { $_.Name -ne 'current' } | Select-Object -First 1
Assert "[B3] versioned dir exists"              ($null -ne $verDir)
Assert "[B3] versioned manifest.json exists"    ($verDir -and (Test-Path "$($verDir.FullName)\manifest.json"))
$packVer  = if ($verDir) { (Get-Content "$($verDir.FullName)\manifest.json" | ConvertFrom-Json).version } else { $null }
$jqEntry  = $m.apps | Where-Object { $_.name -eq 'jq' } | Select-Object -First 1
Assert "[B3] pack version matches manifest"     ($jqEntry -and $jqEntry.version -eq $packVer)
Assert "[B3] current junction absent from pack" (-not (Test-Path "$extractDir\jq\current\manifest.json"))
Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "[B3b] scoop pack zip — versioned dir and scoop.ps1 present" -ForegroundColor Cyan
$scoopZip = Get-ChildItem "$buildPacks\scoop-*.zip" | Select-Object -First 1
Assert "[B3b] scoop zip exists"  ($null -ne $scoopZip)
if ($scoopZip) {
    $scoopExtract = "C:\tmp\b3b-extract"
    if (Test-Path $scoopExtract) { Remove-Item $scoopExtract -Recurse -Force }
    Expand-Archive $scoopZip.FullName -DestinationPath $scoopExtract -Force
    $scoopVerDir = Get-ChildItem "$scoopExtract\scoop" -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'current' } | Select-Object -First 1
    Assert "[B3b] scoop versioned dir exists"    ($null -ne $scoopVerDir)
    Assert "[B3b] scoop.ps1 in versioned dir"    ($scoopVerDir -and (Test-Path "$($scoopVerDir.FullName)\bin\scoop.ps1"))
    Assert "[B3b] no current\ in scoop pack"     (-not (Test-Path "$scoopExtract\scoop\current"))
    Remove-Item $scoopExtract -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "[B4] build.ps1 — skips scoop install on second run" -ForegroundColor Cyan
if (Test-Path $buildPacks) { Remove-Item $buildPacks -Recurse -Force }
$out = pwsh -File "$repoRoot\build.ps1" $testAppsJson 2>&1
Assert "[B4] skip message shown"   ($out -match "already at")
Assert "[B4] manifest regenerated" (Test-Path "$buildPacks\release-manifest.json")

Write-Host "[B5] packUrl reuse — reused pack gets packUrl, no zip re-uploaded" -ForegroundColor Cyan
# Simulates the CI race condition fix: RELEASE_VERSION is set (CI mode) but instead of
# calling gh release list (unavailable in build container) we inject a fake previous
# manifest via -PreviousManifestPath (filesystem path, read with Get-Content — no URI/
# network involved).  The fake manifest claims jq at its current version — build.ps1
# should reuse it, write packUrl into the new manifest, and NOT produce a jq zip.
$jqApp = (Get-Content "$buildPacks\release-manifest.json" -Raw | ConvertFrom-Json).apps |
    Where-Object { $_.name -eq "jq" } | Select-Object -First 1
$fakePackUrl = "https://fake-cdn.example.com/releases/download/v98.0.0/$($jqApp.pack)"
$fakePrevManifest = @{
    version  = "98.0.0"
    apps     = @(@{ name = $jqApp.name; version = $jqApp.version; pack = $jqApp.pack; packUrl = $fakePackUrl })
} | ConvertTo-Json -Depth 5
$fakePrevManifestPath = "C:\tmp\b5-prev-manifest.json"
New-Item -Force -ItemType Directory "C:\tmp" | Out-Null
Set-Content $fakePrevManifestPath $fakePrevManifest -Encoding UTF8

if (Test-Path $buildPacks) { Remove-Item $buildPacks -Recurse -Force }
$env:RELEASE_VERSION = "test-99.0.1"
$out5 = pwsh -File "$repoRoot\build.ps1" $testAppsJson `
    -PreviousManifestPath $fakePrevManifestPath 2>&1
$ec5 = $LASTEXITCODE
$m5  = if (Test-Path "$buildPacks\release-manifest.json") {
    Get-Content "$buildPacks\release-manifest.json" -Raw | ConvertFrom-Json
} else { $null }
$jqEntry5    = if ($m5) { $m5.apps | Where-Object { $_.name -eq "jq" } | Select-Object -First 1 } else { $null }
$jqPackUrl5  = if ($jqEntry5 -and $jqEntry5.PSObject.Properties['packUrl']) { $jqEntry5.packUrl } else { $null }
$jqZipCount  = @(Get-ChildItem "$buildPacks\jq-*.zip" -EA SilentlyContinue).Count
Assert "[B5] exit 0"                     ($ec5 -eq 0)
Assert "[B5] reuse message shown"        ($out5 -match "Reusing jq")
Assert "[B5] jq has packUrl in manifest" ($null -ne $jqPackUrl5)
Assert "[B5] packUrl points to origin"   ($jqPackUrl5 -eq $fakePackUrl)
Assert "[B5] no jq zip in packs dir"     ($jqZipCount -eq 0)
Remove-Item $fakePrevManifestPath -Force -ErrorAction SilentlyContinue

Write-Host "[B7] localPack — private pack sourced from local path, not uploaded" -ForegroundColor Cyan
# Create a fake zip that mimics a private pack (minimal valid zip)
$fakeLocalPackDir  = "C:\tmp\b7-localpack"
$fakeLocalPackZip  = "$fakeLocalPackDir\privateapp-2.0.0.zip"
New-Item -Force -ItemType Directory $fakeLocalPackDir | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
$tmpZip = [System.IO.Compression.ZipFile]::Open($fakeLocalPackZip, [System.IO.Compression.ZipArchiveMode]::Create)
$tmpZip.CreateEntry("privateapp/2.0.0/dummy.txt") | Out-Null
$tmpZip.Dispose()
# private-apps.json with a comment entry and the real app entry
$b7PrivateJson = "C:\tmp\b7-private.json"
@(
    @{ "//" = "comment entry - should be silently skipped" },
    @{ name = "privateapp"; version = "2.0.0"; localPack = $fakeLocalPackZip }
) | ConvertTo-Json | Set-Content $b7PrivateJson -Encoding UTF8
$b7AppsJson = "C:\tmp\b7-apps.json"
@() | ConvertTo-Json | Set-Content $b7AppsJson -Encoding UTF8   # empty public apps
if (Test-Path $buildPacks) { Remove-Item $buildPacks -Recurse -Force }
$env:RELEASE_VERSION = "test-99.0.2"
pwsh -File "$repoRoot\build.ps1" $b7AppsJson -PrivateAppsPath $b7PrivateJson 2>&1 | Out-Null
$ec7  = $LASTEXITCODE
$m7   = if (Test-Path "$buildPacks\release-manifest.json") {
    Get-Content "$buildPacks\release-manifest.json" -Raw | ConvertFrom-Json
} else { $null }
$priv7 = if ($m7) { $m7.apps | Where-Object { $_.name -eq "privateapp" } | Select-Object -First 1 } else { $null }
Assert "[B7] exit 0"                        ($ec7 -eq 0)
Assert "[B7] privateapp in manifest"        ($null -ne $priv7)
Assert "[B7] packUrl is local path"         ($priv7 -and $priv7.packUrl -eq $fakeLocalPackZip)
Assert "[B7] version correct"               ($priv7 -and $priv7.version -eq "2.0.0")
Assert "[B7] zip NOT copied to packs dir"   (-not (Test-Path "$buildPacks\privateapp-2.0.0.zip"))
# Missing local pack: build should warn but not fail
$missingPrivateJson = "C:\tmp\b7-missing.json"
@(@{ name = "ghost"; version = "1.0.0"; localPack = "C:\nonexistent\ghost-1.0.0.zip" }) | ConvertTo-Json | Set-Content $missingPrivateJson -Encoding UTF8
if (Test-Path $buildPacks) { Remove-Item $buildPacks -Recurse -Force }
$out7b = pwsh -File "$repoRoot\build.ps1" $b7AppsJson -PrivateAppsPath $missingPrivateJson 2>&1
$ec7b  = $LASTEXITCODE
$m7b   = if (Test-Path "$buildPacks\release-manifest.json") {
    Get-Content "$buildPacks\release-manifest.json" -Raw | ConvertFrom-Json
} else { $null }
Assert "[B7] missing pack: exit 0"          ($ec7b -eq 0)
Assert "[B7] missing pack: not in manifest" ($m7b -and -not ($m7b.apps | Where-Object { $_.name -eq "ghost" }))
Assert "[B7] missing pack: warning shown"   ($out7b -match "not found")
Remove-Item $fakeLocalPackDir  -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $b7AppsJson        -Force -ErrorAction SilentlyContinue
Remove-Item $b7PrivateJson     -Force -ErrorAction SilentlyContinue
Remove-Item $missingPrivateJson -Force -ErrorAction SilentlyContinue

Write-Host "[B8] integrityExcludePaths mismatch — forces rebuild; match — allows reuse" -ForegroundColor Cyan
# integrityExcludePaths is written into the manifest at build time (from apps.json),
# but the pack library (built from previous manifests) previously did NOT store it.
# When the exclusions change between releases, the stored fileCount/totalSize no longer
# match what toolset.ps1 counts on the client (which applies the new exclusions), so
# every toolset run reports the pack as dirty and triggers a reinstall loop.
# Fix: store integrityExcludePaths in the pack library; if the stored value differs
# from apps.json, force a rebuild so counts are recomputed with the new exclusions.

# Use jq version captured in B5 — stable across container runs.
$jqVer8    = $jqApp.version
$jqPack8   = $jqApp.pack
$fakeUrl8  = "https://fake-cdn.example.com/releases/download/v98.2.0/$jqPack8"

# [B8a] prev manifest has DIFFERENT integrityExcludePaths → should rebuild
$b8aAppsJson = "C:\tmp\b8a-apps.json"
@(@{ name = "jq"; integrityExcludePaths = @("apps/jq/current") }) |
    ConvertTo-Json -Depth 3 | Set-Content $b8aAppsJson -Encoding UTF8
$b8aPrev = "C:\tmp\b8a-prev.json"
@{
    version = "98.2.0"
    apps    = @(@{ name = "jq"; version = $jqVer8; pack = $jqPack8; packUrl = $fakeUrl8
                   integrityExcludePaths = @("apps/jq/current", "apps/jq/$jqVer8/jq.exe") })
} | ConvertTo-Json -Depth 5 | Set-Content $b8aPrev -Encoding UTF8

if (Test-Path $buildPacks) { Remove-Item $buildPacks -Recurse -Force }
$env:RELEASE_VERSION = "test-99.0.8a"
$out8a       = pwsh -File "$repoRoot\build.ps1" $b8aAppsJson -PreviousManifestPath $b8aPrev 2>&1
$jqZip8a     = @(Get-ChildItem "$buildPacks\jq-*.zip" -EA SilentlyContinue).Count
Assert "[B8a] exclusion mismatch: jq rebuilt (no reuse msg)" (-not ($out8a -match "Reusing jq"))
Assert "[B8a] exclusion mismatch: jq zip produced"           ($jqZip8a -gt 0)

# [B8b] prev manifest has SAME integrityExcludePaths → should reuse
$b8bAppsJson = "C:\tmp\b8b-apps.json"
@(@{ name = "jq"; integrityExcludePaths = @("apps/jq/current") }) |
    ConvertTo-Json -Depth 3 | Set-Content $b8bAppsJson -Encoding UTF8
$b8bPrev = "C:\tmp\b8b-prev.json"
@{
    version = "98.2.0"
    apps    = @(@{ name = "jq"; version = $jqVer8; pack = $jqPack8; packUrl = $fakeUrl8
                   integrityExcludePaths = @("apps/jq/current") })
} | ConvertTo-Json -Depth 5 | Set-Content $b8bPrev -Encoding UTF8

if (Test-Path $buildPacks) { Remove-Item $buildPacks -Recurse -Force }
$env:RELEASE_VERSION = "test-99.0.8b"
$out8b   = pwsh -File "$repoRoot\build.ps1" $b8bAppsJson -PreviousManifestPath $b8bPrev 2>&1
$jqZip8b = @(Get-ChildItem "$buildPacks\jq-*.zip" -EA SilentlyContinue).Count
Assert "[B8b] exclusion match: reuse message shown" ($out8b -match "Reusing jq")
Assert "[B8b] exclusion match: no jq zip produced"  ($jqZip8b -eq 0)

Remove-Item $b8aAppsJson -Force -ErrorAction SilentlyContinue
Remove-Item $b8aPrev     -Force -ErrorAction SilentlyContinue
Remove-Item $b8bAppsJson -Force -ErrorAction SilentlyContinue
Remove-Item $b8bPrev     -Force -ErrorAction SilentlyContinue

Write-Host "[B8c] dead GitHub packUrl forces rebuild instead of reusing stale manifest entry" -ForegroundColor Cyan
$b8cAppsJson = "C:\tmp\b8c-apps.json"
@(@{ name = "jq" }) | ConvertTo-Json -Depth 3 | Set-Content $b8cAppsJson -Encoding UTF8
$b8cPrev = "C:\tmp\b8c-prev.json"
$deadGitHubPackUrl = "https://github.com/ETML-INF/standard-toolset/releases/download/v0.0.0/nonexistent-jq.zip"
@{
    version = "98.3.0"
    apps    = @(@{ name = "jq"; version = $jqVer8; pack = $jqPack8; packUrl = $deadGitHubPackUrl })
} | ConvertTo-Json -Depth 5 | Set-Content $b8cPrev -Encoding UTF8

if (Test-Path $buildPacks) { Remove-Item $buildPacks -Recurse -Force }
$env:RELEASE_VERSION = "test-99.0.8c"
$out8c   = pwsh -File "$repoRoot\build.ps1" $b8cAppsJson -PreviousManifestPath $b8cPrev 2>&1
$jqZip8c = @(Get-ChildItem "$buildPacks\jq-*.zip" -EA SilentlyContinue).Count
$m8c  = if (Test-Path "$buildPacks\release-manifest.json") {
    Get-Content "$buildPacks\release-manifest.json" -Raw | ConvertFrom-Json
} else { $null }
$jqEntry8c = if ($m8c) { $m8c.apps | Where-Object { $_.name -eq "jq" } | Select-Object -First 1 } else { $null }
Assert "[B8c] dead url: jq rebuilt (no reuse msg)"                 (-not ($out8c -match "Reusing jq"))
Assert "[B8c] dead url: warning shown"                              ($out8c -match "unreachable")
Assert "[B8c] dead url: jq zip produced"                           ($jqZip8c -gt 0)
Assert "[B8c] dead url: stale packUrl not carried forward"         (-not ($jqEntry8c -and $jqEntry8c.PSObject.Properties['packUrl'] -and $jqEntry8c.packUrl -eq $deadGitHubPackUrl))

Remove-Item $b8cAppsJson -Force -ErrorAction SilentlyContinue
Remove-Item $b8cPrev     -Force -ErrorAction SilentlyContinue

Write-Host "[B6] toolset.ps1 / setup.ps1 — ASCII-only (PS 5.1 compatible)" -ForegroundColor Cyan
# PowerShell 5.1 reads UTF-8 files without BOM as ANSI (Windows-1252).
# Any non-ASCII byte (em dash, box-drawing chars, arrows, etc.) causes parse errors.
# Only these two files are downloaded and run on end-user machines that may have PS 5.1.
foreach ($name in @('toolset.ps1', 'setup.ps1')) {
    $bytes    = [System.IO.File]::ReadAllBytes("$repoRoot\$name")
    $badCount = @($bytes | Where-Object {
        $_ -gt 0x7E -or ($_ -lt 0x20 -and $_ -ne 0x09 -and $_ -ne 0x0D -and $_ -ne 0x0A)
    }).Count
    Assert "[B6] $name is ASCII-only" ($badCount -eq 0)
}

Write-Host "[B9] patchBuildPaths — build-time: marker comment + default path written into pack" -ForegroundColor Cyan
# Verifies that build.ps1 patches files listed in patchBuildPaths BEFORE creating the zip:
# inserts "# toolset:patch <template with __TOOLSET_SCOOP__>" and replaces buildScoopDir with
# C:\inf-toolset\scoop so packs ship already usable at the default install location.
# Leverages jq already installed by B1 — injects a fake config file into its installed dir.
$b9BuildScoopDir = "C:\toolset-repo\build\scoop"
$b9FakeConfig    = "$b9BuildScoopDir\apps\jq\current\fake-config.ini"
Set-Content $b9FakeConfig "prefix=$b9BuildScoopDir\persist\jq" -Encoding UTF8

$b9AppsJson = "C:\tmp\b9-apps.json"
@(@{ name = "jq"; patchBuildPaths = @("fake-config.ini") }) |
    ConvertTo-Json -Depth 5 | Set-Content $b9AppsJson -Encoding UTF8

if (Test-Path $buildPacks) { Remove-Item $buildPacks -Recurse -Force }
$env:RELEASE_VERSION = "test-99.0.9"
pwsh -File "$repoRoot\build.ps1" $b9AppsJson 2>&1 | Out-Null
$ec9 = $LASTEXITCODE

$b9PackZip    = Get-ChildItem "$buildPacks\jq-*.zip" -ErrorAction SilentlyContinue | Select-Object -First 1
$b9ExtractDir = "C:\tmp\b9-extract"
if ($b9PackZip) { Expand-Archive $b9PackZip.FullName -DestinationPath $b9ExtractDir -Force }
$b9ConfigFile = Get-ChildItem "$b9ExtractDir\jq\*\fake-config.ini" -ErrorAction SilentlyContinue | Select-Object -First 1
$b9Config     = if ($b9ConfigFile) { Get-Content $b9ConfigFile -Raw } else { $null }

Assert "[B9] exit 0"                         ($ec9 -eq 0)
Assert "[B9] jq pack produced"               ($null -ne $b9PackZip)
Assert "[B9] buildScoopDir gone from config" ($b9Config -notlike "*$b9BuildScoopDir*")
Assert "[B9] default path in config"         ($b9Config -like "*C:\inf-toolset\scoop\persist\jq*")
Assert "[B9] marker comment present"         ($b9Config -like "*# toolset:patch*__TOOLSET_SCOOP__*")

Remove-Item $b9FakeConfig -Force -ErrorAction SilentlyContinue
Remove-Item $b9AppsJson   -Force -ErrorAction SilentlyContinue
if (Test-Path $b9ExtractDir) { Remove-Item $b9ExtractDir -Recurse -Force -ErrorAction SilentlyContinue }

# Cleanup
Remove-Item $testAppsJson -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Results: $pass passed, $fail failed" -ForegroundColor $(if ($fail -eq 0) { "Green" } else { "Red" })
if ($fail -gt 0) {
    Write-Host ""
    Write-Host "Failed assertions:" -ForegroundColor Red
    foreach ($f in $failedAssertions) { Write-Host "  - $f" -ForegroundColor Red }
    exit 1
}
