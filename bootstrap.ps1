try {
    Set-StrictMode -Version Latest

    # Title
    Write-Host "+--------------------------------+" -ForegroundColor Cyan
    Write-Host "|" -ForegroundColor Cyan -NoNewline
    Write-Host "   ETML-INF STANDARD TOOLSET    " -ForegroundColor White -NoNewline
    Write-Host "|" -ForegroundColor Cyan
    Write-Host "+--------------------------------+" -ForegroundColor Cyan

    # Download archive
    Write-Output "About to download toolset..."
    $url="https://github.com/ETML-INF/standard-toolset/releases/latest/download/toolset.zip"
    $timestamp = Get-Date -format yyyy_MM_dd_H_mm_ss
    $archivename = "toolset-$timestamp"
    $archivepath = "$env:TEMP\$archivename.zip"
    Invoke-WebRequest -Uri "$url" -OutFile "$archivepath"

    # Extract
    $archivedirectory = "$env:TEMP\$archivename"
    Write-Output "About to extract $archivepath to $archivedirectory"
    Expand-Archive $archivepath $archivedirectory

    # Install
    Write-Output "About to launch install script"
    Set-Location $archivedirectory
    & .\install.ps1

    # Cleaning up
    Remove-Item $archivedirectory
    Remove-Item $archivepath
}
catch {
    Write-Error "Something went wrong: $_. Please contact the maintainer for more info..."
    Write-Info "Items still available: $archivepath, $archivedirectory"
}
