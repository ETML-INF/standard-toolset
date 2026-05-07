<#
.SYNOPSIS
    Static checks: PSScriptAnalyzer lint, ASCII-only validation, and apps.json schema.

.DESCRIPTION
    Runs all repository-wide static checks that do not require a running toolset or
    Docker container.  Intended to be called as a pre-flight step from both
    Run-ToolsetTests.ps1 (local) and the validate-and-test CI/CD action.

    Checks performed:
      1. PSScriptAnalyzer -- all .ps1 files in the repository, Error + Warning severity.
      2. ASCII-only       -- toolset.ps1 and setup.ps1 must contain no non-ASCII bytes
                            (PS 5.1 reads UTF-8-without-BOM as ANSI/Windows-1252).
      3. apps.json schema -- every entry must have 'name' and use only known fields.

    Exits 0 when all checks pass, 1 on the first failing check.

.PARAMETER RepoRoot
    Root directory of the repository.
    Defaults to the parent directory of $PSScriptRoot.

.PARAMETER PrivateAppsPath
    Optional path to a local private-apps.json manifest. When present, validate it
    with the same JSON/schema checks as apps.json, plus localPack-specific fields.
#>
param(
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$PrivateAppsPath = "L:\toolset\private-apps.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"
$failed = $false

function Write-CheckHeader {
    param([string]$Title)
    Write-Host ""
    Write-Host "-- $Title" -ForegroundColor Cyan
}

function Fail {
    param([string]$Message)
    Write-Host "  FAIL: $Message" -ForegroundColor Red
    $script:failed = $true
}

# ── 1. PSScriptAnalyzer ───────────────────────────────────────────────────
Write-CheckHeader "PSScriptAnalyzer"
$psaModule = Get-Module -ListAvailable -Name PSScriptAnalyzer | Select-Object -First 1
if (-not $psaModule) {
    Write-Host "  PSScriptAnalyzer not installed -- installing (CurrentUser)..." -ForegroundColor Yellow
    Install-Module PSScriptAnalyzer -Force -Scope CurrentUser -ErrorAction Stop
}
$settings  = Join-Path $RepoRoot "PSScriptAnalyzerSettings.psd1"
$psFiles   = @(Get-ChildItem $RepoRoot -Filter "*.ps1" -Recurse -ErrorAction Stop |
               Where-Object { $_.FullName -notmatch '\\build\\' })
Write-Host "  Analyzing $($psFiles.Count) script(s):" -ForegroundColor DarkGray
foreach ($f in $psFiles | Sort-Object FullName) {
    Write-Host "    $($f.FullName.Substring($RepoRoot.Length + 1))" -ForegroundColor DarkGray
}
$lintResults = @(Invoke-ScriptAnalyzer -Path $RepoRoot -Recurse -Settings $settings `
    -Severity Error, Warning -ErrorAction Stop)
if ($lintResults.Count -gt 0) {
    $lintResults | Format-Table -AutoSize
    Fail "PSScriptAnalyzer found $($lintResults.Count) issue(s)"
} else {
    Write-Host "  OK -- no issues found" -ForegroundColor Green
}

# ── 2. ASCII-only check for PS 5.1-distributed scripts ───────────────────
# PS 5.1 reads UTF-8 files without BOM as ANSI (Windows-1252).
# Non-ASCII bytes (em dashes, arrows, ellipses, box-drawing chars, etc.)
# cause parse errors on end-user machines.  Only these two files are
# downloaded and executed directly on machines that may have PS 5.1.
Write-CheckHeader "ASCII-only (toolset.ps1, setup.ps1)"
foreach ($name in @('toolset.ps1', 'setup.ps1')) {
    $filePath = Join-Path $RepoRoot $name
    if (-not (Test-Path $filePath)) {
        Write-Host "  SKIP: $name not found" -ForegroundColor DarkGray
        continue
    }
    $bytes    = [System.IO.File]::ReadAllBytes($filePath)
    $badBytes = @($bytes | Where-Object {
        $_ -gt 0x7E -or ($_ -lt 0x20 -and $_ -ne 0x09 -and $_ -ne 0x0D -and $_ -ne 0x0A)
    })
    if ($badBytes.Count -gt 0) {
        Fail "$name contains $($badBytes.Count) non-ASCII byte(s)"
    } else {
        Write-Host "  OK -- $name is ASCII-only" -ForegroundColor Green
    }
}

# ── 3. apps.json schema ───────────────────────────────────────────────────
Write-CheckHeader "apps.json schema"
$appsJsonScript = Join-Path $PSScriptRoot "Test-AppsJson.ps1"
$appsJsonPath   = Join-Path $RepoRoot "apps.json"
pwsh -File $appsJsonScript -Path $appsJsonPath
if ($LASTEXITCODE -ne 0) { Fail "apps.json validation failed" }

# ── 4. private-apps.json schema (local only) ──────────────────────────────
Write-CheckHeader "private-apps.json schema"
if (Test-Path $PrivateAppsPath -ErrorAction SilentlyContinue) {
    pwsh -File $appsJsonScript -Path $PrivateAppsPath -AllowLocalPack
    if ($LASTEXITCODE -ne 0) { Fail "private-apps.json validation failed" }
} else {
    Write-Host "  SKIP: private-apps.json not found at $PrivateAppsPath" -ForegroundColor DarkGray
}

# ── Result ────────────────────────────────────────────────────────────────
Write-Host ""
if ($failed) {
    Write-Host "Static checks FAILED -- fix issues before running container tests." -ForegroundColor Red
    exit 1
}
Write-Host "Static checks passed." -ForegroundColor Green
exit 0
