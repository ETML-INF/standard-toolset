param([string]$ToolkitPath = (Join-Path (Split-Path $PSScriptRoot -Parent) "toolset.ps1"))
$pass = 0; $fail = 0
$helper = Join-Path $PSScriptRoot "New-FakePack.ps1"

function Assert {
    param([string]$Name, $Cond, [string]$Detail="")
    if ($Cond) { Write-Host "PASS: $Name" -ForegroundColor Green; $script:pass++ }
    else       { Write-Host "FAIL: $Name $Detail" -ForegroundColor Red; $script:fail++ }
}

# ── Test 1: manifest resolution via -ManifestSource ──────────────────────
$p1 = "$env:TEMP\t1-packs-$(Get-Random)"
& $helper -OutputDir $p1 -Apps @(@{Name="vscode";Version="1.0.0"}) -ManifestVersion "5.0.0"
$d1 = "$env:TEMP\t1-inst-$(Get-Random)"
$out = pwsh -File $ToolkitPath update -Path $d1 `
    -ManifestSource "$p1\release-manifest.json" -PackSource $p1 `
    -NoInteraction 2>&1
Assert "T1: status table shows vscode" ($out -match "vscode")
Remove-Item $d1,$p1 -Recurse -Force -ErrorAction SilentlyContinue

# ── Test 2: fresh install creates app dirs ────────────────────────────────
$p2 = "$env:TEMP\t2-packs-$(Get-Random)"
& $helper -OutputDir $p2 `
    -Apps @(@{Name="app1";Version="1.0.0"},@{Name="app2";Version="2.0.0"}) `
    -ManifestVersion "5.0.0"
$d2 = "$env:TEMP\t2-inst-$(Get-Random)"
pwsh -File $ToolkitPath update -Path $d2 `
    -ManifestSource "$p2\release-manifest.json" -PackSource $p2 `
    -NoInteraction 2>&1 | Out-Null
Assert "T2: app1 installed" (Test-Path "$d2\scoop\apps\app1\current\manifest.json")
Assert "T2: app2 installed" (Test-Path "$d2\scoop\apps\app2\current\manifest.json")
Remove-Item $d2,$p2 -Recurse -Force -ErrorAction SilentlyContinue

# ── Test 3: partial update — only outdated app is replaced ───────────────
$p3 = "$env:TEMP\t3-packs-$(Get-Random)"
# Manifest: app1@1.1.0 (update), app2@2.0.0 (same)
& $helper -OutputDir $p3 `
    -Apps @(@{Name="app1";Version="1.1.0"},@{Name="app2";Version="2.0.0"}) `
    -ManifestVersion "5.0.0"
$d3 = "$env:TEMP\t3-inst-$(Get-Random)"
foreach ($p in @("app1/1.0.0","app2/2.0.0")) {
    $n,$v = $p -split "/"; $cd = "$d3\scoop\apps\$n\current"
    New-Item -ItemType Directory -Force $cd | Out-Null
    @{version=$v} | ConvertTo-Json | Set-Content "$cd\manifest.json" -Encoding UTF8
}
pwsh -File $ToolkitPath update -Path $d3 `
    -ManifestSource "$p3\release-manifest.json" -PackSource $p3 `
    -NoInteraction 2>&1 | Out-Null
$app1ver = (Get-Content "$d3\scoop\apps\app1\current\manifest.json" | ConvertFrom-Json).version
$app2ver = (Get-Content "$d3\scoop\apps\app2\current\manifest.json" | ConvertFrom-Json).version
Assert "T3: app1 updated to 1.1.0"  ($app1ver -eq "1.1.0")
Assert "T3: app2 still at 2.0.0"    ($app2ver -eq "2.0.0")
Remove-Item $d3,$p3 -Recurse -Force -ErrorAction SilentlyContinue

# ── Test 4: -Clean removes orphaned app ──────────────────────────────────
$p4 = "$env:TEMP\t4-packs-$(Get-Random)"
& $helper -OutputDir $p4 -Apps @(@{Name="app1";Version="1.0.0"})
$d4 = "$env:TEMP\t4-inst-$(Get-Random)"
$od = "$d4\scoop\apps\orphan\current"
New-Item -ItemType Directory -Force $od | Out-Null
@{version="0.1"} | ConvertTo-Json | Set-Content "$od\manifest.json" -Encoding UTF8
pwsh -File $ToolkitPath update -Path $d4 `
    -ManifestSource "$p4\release-manifest.json" -PackSource $p4 `
    -NoInteraction -Clean 2>&1 | Out-Null
Assert "T4: orphan removed with -Clean"  (-not (Test-Path "$d4\scoop\apps\orphan"))
Remove-Item $d4,$p4 -Recurse -Force -ErrorAction SilentlyContinue

# ── Test 5: -NoInteraction without -Clean leaves orphan ──────────────────
$p5 = "$env:TEMP\t5-packs-$(Get-Random)"
& $helper -OutputDir $p5 -Apps @(@{Name="app1";Version="1.0.0"})
$d5 = "$env:TEMP\t5-inst-$(Get-Random)"
$od5 = "$d5\scoop\apps\orphan\current"
New-Item -ItemType Directory -Force $od5 | Out-Null
@{version="0.1"} | ConvertTo-Json | Set-Content "$od5\manifest.json" -Encoding UTF8
pwsh -File $ToolkitPath update -Path $d5 `
    -ManifestSource "$p5\release-manifest.json" -PackSource $p5 `
    -NoInteraction 2>&1 | Out-Null
Assert "T5: orphan kept without -Clean"  (Test-Path "$d5\scoop\apps\orphan")
Remove-Item $d5,$p5 -Recurse -Force -ErrorAction SilentlyContinue

# ── Test 6: missing pack — continues and reports ──────────────────────────
$p6 = "$env:TEMP\t6-packs-$(Get-Random)"
& $helper -OutputDir $p6 `
    -Apps @(@{Name="app1";Version="1.0.0"},@{Name="app2";Version="2.0.0"})
Remove-Item "$p6\app2-2.0.0.zip" -Force
$d6 = "$env:TEMP\t6-inst-$(Get-Random)"
pwsh -File $ToolkitPath update -Path $d6 `
    -ManifestSource "$p6\release-manifest.json" -PackSource $p6 `
    -NoInteraction 2>&1 | Out-Null
$ec = $LASTEXITCODE
Assert "T6: app1 installed despite missing pack"  (Test-Path "$d6\scoop\apps\app1\current\manifest.json")
Assert "T6: non-fatal exit code"                  ($ec -eq 0)
Remove-Item $d6,$p6 -Recurse -Force -ErrorAction SilentlyContinue

# ── Summary ──────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Results: $pass passed, $fail failed" -ForegroundColor $(if ($fail -eq 0){"Green"}else{"Red"})
if ($fail -gt 0) { exit 1 }
