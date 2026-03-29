<#
.SYNOPSIS
    Builds and runs the build pipeline container tests.

.DESCRIPTION
    Requires the build-base image with scoop pre-installed.
    Build it locally first: pwsh tests/Build-BaseImage.ps1

    Targets the 'desktop-windows' context explicitly — no manual mode switch needed.
    To switch Docker Desktop to Windows containers mode:
    right-click the Docker tray icon → "Switch to Windows containers"

.PARAMETER NoCleanup
    Keep the toolset-build-test image after the run (useful for debugging).

.PARAMETER BaseImage
    Override the base image (default: ghcr.io/etml-inf/standard-toolset/build-base:latest).
#>
param(
    [switch]$NoCleanup,
    [string]$BaseImage = "ghcr.io/etml-inf/standard-toolset/build-base:latest"
)

$ErrorActionPreference = "Stop"
$image    = "toolset-build-test"
$repoRoot = Split-Path $PSScriptRoot -Parent

$availableContexts = docker context ls --format "{{.Name}}" 2>$null
$context = if ($availableContexts -contains "desktop-windows") {
    "desktop-windows"
} else {
    Write-Warning "'desktop-windows' context not found — using current default context."
    Write-Warning "If the build fails, make sure Docker Desktop is in Windows containers mode."
    $null
}
$dockerArgs = if ($context) { @("--context", $context) } else { @() }

Write-Host "Docker context : $(if ($context) { $context } else { '(default)' })" -ForegroundColor Cyan
Write-Host ""

Write-Host "Building $image ..." -ForegroundColor Yellow
$buildArgs = @("-f", "$PSScriptRoot\Dockerfile.build-test", "-t", $image,
               "--build-arg", "BASE_IMAGE=$BaseImage")
$buildArgs += $repoRoot

docker @dockerArgs build @buildArgs
if ($LASTEXITCODE -ne 0) { Write-Error "Build failed"; exit 1 }

Write-Host ""
Write-Host "Running build tests..." -ForegroundColor Yellow
docker @dockerArgs run --rm $image
$exitCode = $LASTEXITCODE

if (-not $NoCleanup) {
    Write-Host ""
    Write-Host "Removing image $image ..." -ForegroundColor DarkGray
    docker @dockerArgs rmi $image 2>$null | Out-Null
}

exit $exitCode
