<#
  Build pipeline tests. Runs inside the build-test container.
  Verifies pack creation, zip root structure, and manifest schema.
  Exit 0 = all pass, Exit 1 = any failure.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"
$repoRoot = "C:\toolset-repo"
$pass = 0; $fail = 0
$failedAssertions = [System.Collections.Generic.List[string]]::new()

function Assert {
    param([string]$Name, $Cond, [string]$Detail="")
    if ($Cond) { $script:pass++ }
    else       { Write-Host "  FAIL: $Name $Detail" -ForegroundColor Red; $script:fail++; $script:failedAssertions.Add($Name) }
}

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
Assert "[B2] has previousVersion"  ($props -contains 'previousVersion')
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
