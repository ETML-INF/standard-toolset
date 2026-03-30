<#
.SYNOPSIS
    Bootstrap installer for ETML-INF standard toolset.
    Downloads toolset.ps1 from GitHub (or L:\toolset as fallback) and runs it.

.PARAMETER Destination
    Target install path passed to toolset.ps1 (default: C:\inf-toolset).

.PARAMETER NoInteraction
    Suppress all prompts (passed through to toolset.ps1).
#>
param(
    [string]$Destination = "C:\inf-toolset",
    [switch]$NoInteraction
)

Set-StrictMode -Version Latest

$githubUrl      = "https://github.com/ETML-INF/standard-toolset/releases/latest/download/toolset.ps1"
$lDriveFallback = "L:\toolset\toolset.ps1"
$tmpToolset     = "$env:TEMP\toolset-bootstrap-$(Get-Random).ps1"

Write-Host "+--------------------------------+" -ForegroundColor Cyan
Write-Host "|   ETML-INF STANDARD TOOLSET    |" -ForegroundColor White
Write-Host "+--------------------------------+" -ForegroundColor Cyan
Write-Host ""

$downloaded = $false
try {
    Write-Host "Downloading toolset.ps1 from GitHub..." -ForegroundColor Yellow
    # Additive TLS 1.2 flag  - the -bor 3072 pattern (3072 = Tls12) is the scoop/choco proven
    # approach: works on .NET 2.0+, doesn't remove TLS 1.3, no enum dependency.
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    (New-Object System.Net.WebClient).DownloadFile($githubUrl, $tmpToolset)
    $downloaded = $true
    Write-Host "Downloaded from GitHub." -ForegroundColor Green
} catch {
    Write-Warning "GitHub unavailable: $_"
}

if (-not $downloaded) {
    if (Test-Path $lDriveFallback) {
        Write-Host "Using L:\toolset\toolset.ps1 (offline fallback)." -ForegroundColor Yellow
        Copy-Item $lDriveFallback $tmpToolset
        $downloaded = $true
    }
}

if (-not $downloaded) {
    Write-Error "Cannot reach GitHub and L:\toolset is not available. Please connect to the network or the internal drive and try again."
    exit 1
}

$shell = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }

try {
    # toolset.ps1 already falls back to L:\toolset automatically when GitHub is unreachable,
    # so no -PackSource is needed here for the standard offline scenario.
    & $shell -File $tmpToolset update -Path $Destination -NoInteraction:$NoInteraction
} finally {
    Remove-Item $tmpToolset -Force -ErrorAction SilentlyContinue
}
