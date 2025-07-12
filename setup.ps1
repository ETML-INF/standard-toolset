param(
    [Parameter(Mandatory=$false,HelpMessage="Try to find a local toolset.zip to install from in current directory (not recursive)")][bool]$Local=$false,
    [Parameter(Mandatory=$false,HelpMessage="Give a file path to get archive from (instead of github). Implies -local" )][string]$Source=$null,
    [Parameter(Mandatory=$false,HelpMessage="Target custom folder where to install toolset (usefull for deployments...) [inf-toolset subfolder will be created in it]")][string]$Destination=$null
)
try {
    Set-StrictMode -Version Latest

    # Title
    Write-Host "+--------------------------------+" -ForegroundColor Cyan
    Write-Host "|" -ForegroundColor Cyan -NoNewline
    Write-Host "   ETML-INF STANDARD TOOLSET    " -ForegroundColor White -NoNewline
    Write-Host "|" -ForegroundColor Cyan
    Write-Host "+--------------------------------+" -ForegroundColor Cyan

    # Handles local args
    if($Local -or $Source)
    {
	if([string]::IsNullOrEmpty($Source))
	{
	    Write-Output "Looking for a toolset*.zip file in current directory..."
	    $existingfile = Get-ChildItem -Path ".\toolset*.zip" | Select-Object -First 1
	    $localarchivepath = if ($existingfile) { $existingfile.FullName } else { $null }
	}
	else{
	    Write-Output "Using given $Source as source"
	    $localarchivepath=$Source
	}
	
	if(![string]::IsNullOrEmpty($localarchivepath))
	{
	    $archivepath = $localarchivepath
	    Write-Host "Found local $archivepath"
	}
	else{
	    Write-Error "No local archive found, aborting local install"
	    Exit 2
	}
    }
    # Download archive
    else{
	Write-Output "About to download toolset..."
	$url="https://github.com/ETML-INF/standard-toolset/releases/latest/download/toolset.zip"
	$timestamp = Get-Date -format yyyy_MM_dd_H_mm_ss
	$archivename = "toolset-$timestamp"
	$archivepath = "$env:TEMP\$archivename.zip"
	Invoke-WebRequest -Uri "$url" -OutFile "$archivepath"

	# Wait for stable file size with 30s timeout (antivirus scan after invoke web-request...)
	$lastSize = 0; $elapsed = 0
	do {
	    Start-Sleep -Seconds 1; $elapsed++
	    try { $currentSize = (Get-Item $archivepath).Length } catch { $currentSize = -1 }
	    if ($currentSize -gt 0 -and $currentSize -eq $lastSize) { break }
	    if ($elapsed -ge 30) { exit 3 }
	    $lastSize = $currentSize
	} while ($true)
    }
    
    # Extract
    $archivedirectory = "$env:TEMP\toolset-$(New-Guid)"
    Write-Output "About to extract $archivepath to $archivedirectory"
    Expand-Archive $archivepath $archivedirectory

    # Install
    Write-Output "About to launch install script"
    Set-Location $archivedirectory
    & .\install.ps1 -Destination "$Destination"

    # Cleaning up
    Remove-Item $archivedirectory
    if(!$local)
    {
	Remove-Item $archivepath	
    }
    
}
catch {
    Write-Error "Something went wrong: $_. Please contact the maintainer for more info..."
    Write-Host "Items still available: $archivepath, $archivedirectory"
}
