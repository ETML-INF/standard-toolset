<#
.SYNOPSIS
    Builds and runs the toolset container tests.

.DESCRIPTION
    Runs static pre-flight checks (PSScriptAnalyzer, ASCII-only, apps.json schema)
    before building the Docker image, so failures are reported immediately without
    waiting for a container build.

    Requires Docker Desktop in Windows containers mode.
    This script targets the 'desktop-windows' context explicitly -- no manual mode switch needed,
    regardless of whether your Docker Desktop is currently in Linux or Windows mode.

    To switch Docker Desktop to Windows containers mode:
    right-click the Docker tray icon -> "Switch to Windows containers"

    If 'desktop-windows' context is not available (Linux host, non-Docker-Desktop setup),
    the script falls back to the current default context and warns you.

    The container base image defaults to mcr.microsoft.com/powershell:nanoserver-1909
    (build 18363) for old Win10 dev machines -- no argument needed.
    CI and Win11/Server 2022 devs should pass -BaseImage with the ltsc2022 image
    (or the GHCR-cached test-base:latest).

.PARAMETER NoCleanup
    Keep the toolset-test image after the run (useful for debugging).

.PARAMETER BaseImage
    Override the container base image.
    Default: mcr.microsoft.com/powershell:nanoserver-1909 (build 18363, for old Win10 dev machines).
    CI and Win11/Server 2022 devs should pass: mcr.microsoft.com/powershell:nanoserver-ltsc2022
    (or the GHCR-cached equivalent ghcr.io/etml-inf/standard-toolset/test-base:latest).

.PARAMETER SkipStaticChecks
    Skip pre-flight static checks (PSScriptAnalyzer, ASCII, apps.json).
    Use only when PSScriptAnalyzer is not installed and you want container tests only.
#>
param(
    [switch]$NoCleanup,
    [string]$BaseImage = "",
    [switch]$SkipStaticChecks,
    [string[]]$Scenario = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$image    = "toolset-test"
$repoRoot = Split-Path $PSScriptRoot -Parent

# ── Pre-flight: static checks ─────────────────────────────────────────────
# Runs before Docker so failures are instant (no container build wasted).
if (-not $SkipStaticChecks) {
    pwsh -File (Join-Path $PSScriptRoot "Test-StaticChecks.ps1") -RepoRoot $repoRoot
    if ($LASTEXITCODE -ne 0) { exit 1 }
}

. (Join-Path $PSScriptRoot "Test-DockerHelpers.ps1")
$dockerArgs = Get-DockerArgs
Write-Host ""

# ── Build ─────────────────────────────────────────────────────────────────
Write-Host "Building $image ..." -ForegroundColor Yellow
$buildArgs = @("-f", "$PSScriptRoot\Dockerfile.test", "-t", $image)
if ($BaseImage) { $buildArgs += @("--build-arg", "BASE_IMAGE=$BaseImage") }
$buildArgs += $repoRoot

docker @dockerArgs build @buildArgs
if ($LASTEXITCODE -ne 0) { Write-Error "Build failed"; exit 1 }

# ── Run ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Running tests..." -ForegroundColor Yellow
$scenarioArgs = if ($Scenario) { @("-Scenario") + $Scenario } else { @() }
docker @dockerArgs run --rm $image @scenarioArgs
$exitCode = $LASTEXITCODE

# ── Cleanup ───────────────────────────────────────────────────────────────
if (-not $NoCleanup) {
    Write-Host ""
    Write-Host "Removing image $image ..." -ForegroundColor DarkGray
    docker @dockerArgs rmi $image 2>$null | Out-Null
}

exit $exitCode
