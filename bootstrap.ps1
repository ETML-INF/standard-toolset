Set-StrictMode -Version Latest

# Title
Write-Output "+--------------------------------+" -ForegroundColor Cyan
Write-Output "|" -ForegroundColor Cyan -NoNewline
Write-Output "   ETML-INF STANDARD TOOLSET    " -ForegroundColor White -NoNewline
Write-Output "|" -ForegroundColor Cyan
Write-Output "+--------------------------------+" -ForegroundColor Cyan

# Download archive
Write-Output "About to download toolset..."
$url="https://github.com/ETML-INF/standard-toolset/release/latest/download/toolset.zip"
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


