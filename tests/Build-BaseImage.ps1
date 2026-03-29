<#
.SYNOPSIS
    Builds (and optionally pushes) the build-base container image to GHCR.

.DESCRIPTION
    Run this when the scoop version or pre-installed apps need updating.
    The base image contains scoop + required buckets + 7zip pre-installed so
    build tests don't reinstall scoop on every run.

    Requires Docker Desktop in Windows containers mode.
    See Run-ContainerTests.ps1 for context switching details.

    NETWORK: Docker Desktop Windows containers need DNS during the build RUN step.
    If the build fails with "No such host is known", add to Docker Desktop →
    Settings → Docker Engine:
        "dns": ["8.8.8.8"]
    then restart Docker Desktop.

.PARAMETER Push
    Push the image to GHCR after building. Requires: docker login ghcr.io

.PARAMETER Tag
    Image tag (default: latest).

.PARAMETER BaseImage
    Override the base OS image. Default is nanoserver-1909 (small, ~250 MB).
    If MinGit is incompatible with your host, fall back to Server Core:
      -BaseImage mcr.microsoft.com/powershell:windowsservercore-1909
#>
param(
    [switch]$Push,
    [string]$Tag       = "latest",
    [string]$BaseImage = ""
)

$ErrorActionPreference = "Stop"
$image    = "ghcr.io/etml-inf/standard-toolset/build-base:$Tag"
$repoRoot = Split-Path $PSScriptRoot -Parent

# CI: mode already guaranteed — use default silently.
# Desktop: prefer 'desktop-windows'; warn if absent so the developer knows to switch.
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

Write-Host "Docker context : $(if ($context) { $context } else { '(default)' })" -ForegroundColor Cyan
Write-Host "Image          : $image" -ForegroundColor Cyan
Write-Host ""

Write-Host "Building base image (this installs scoop + apps — takes a few minutes)..." -ForegroundColor Yellow
$buildArgs = @("-f", "$PSScriptRoot\Dockerfile.build-base", "-t", $image, "--network", "nat")
if ($BaseImage) { $buildArgs += @("--build-arg", "BASE_IMAGE=$BaseImage") }
$buildArgs += $repoRoot

docker @dockerArgs build @buildArgs
if ($LASTEXITCODE -ne 0) { Write-Error "Build failed"; exit 1 }

Write-Host ""
Write-Host "Base image built: $image" -ForegroundColor Green

if ($Push) {
    Write-Host "Pushing to GHCR..." -ForegroundColor Yellow
    docker @dockerArgs push $image
    if ($LASTEXITCODE -ne 0) { Write-Error "Push failed"; exit 1 }
    Write-Host "Pushed: $image" -ForegroundColor Green
} else {
    Write-Host "Run with -Push to push to GHCR." -ForegroundColor Cyan
}
