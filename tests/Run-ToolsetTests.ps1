<#
.SYNOPSIS
    Builds and runs the toolset container tests.

.DESCRIPTION
    Requires Docker Desktop in Windows containers mode.
    This script targets the 'desktop-windows' context explicitly — no manual mode switch needed,
    regardless of whether your Docker Desktop is currently in Linux or Windows mode.

    To switch Docker Desktop to Windows containers mode:
    right-click the Docker tray icon → "Switch to Windows containers"

    If 'desktop-windows' context is not available (Linux host, non-Docker-Desktop setup),
    the script falls back to the current default context and warns you.

    The container base image defaults to mcr.microsoft.com/powershell:nanoserver-1909
    (build 18363) for old Win10 dev machines — no argument needed.
    CI and Win11/Server 2022 devs should pass -BaseImage with the ltsc2022 image
    (or the GHCR-cached test-base:latest).

.PARAMETER NoCleanup
    Keep the toolset-test image after the run (useful for debugging).

.PARAMETER BaseImage
    Override the container base image.
    Default: mcr.microsoft.com/powershell:nanoserver-1909 (build 18363, for old Win10 dev machines).
    CI and Win11/Server 2022 devs should pass: mcr.microsoft.com/powershell:nanoserver-ltsc2022
    (or the GHCR-cached equivalent ghcr.io/etml-inf/standard-toolset/test-base:latest).
#>
param(
    [switch]$NoCleanup,
    [string]$BaseImage = ""
)

$ErrorActionPreference = "Stop"
$image   = "toolset-test"
$repoRoot = Split-Path $PSScriptRoot -Parent

# ── Determine Docker context ──────────────────────────────────────────────
# CI: mode already guaranteed by switch-docker-windows — use default silently.
# Desktop: prefer 'desktop-windows' so the test works regardless of current mode;
#          warn if absent so the developer knows to switch Docker Desktop.
$availableContexts = docker context ls --format "{{.Name}}" 2>$null
$context = if ($env:CI) {
    $null
} elseif ($availableContexts -contains "desktop-windows") {
    "desktop-windows"
} else {
    Write-Warning "'desktop-windows' context not found — using current default context."
    Write-Warning "If the build fails, make sure Docker Desktop is in Windows containers mode."
    $null
}
$dockerArgs = if ($context) { @("--context", $context) } else { @() }

Write-Host "Docker context : $( if ($context) { $context } else { '(default)' } )" -ForegroundColor Cyan
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
docker @dockerArgs run --rm $image
$exitCode = $LASTEXITCODE

# ── Cleanup ───────────────────────────────────────────────────────────────
if (-not $NoCleanup) {
    Write-Host ""
    Write-Host "Removing image $image ..." -ForegroundColor DarkGray
    docker @dockerArgs rmi $image 2>$null | Out-Null
}

exit $exitCode
