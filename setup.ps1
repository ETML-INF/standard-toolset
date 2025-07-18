param(
    [Parameter(Mandatory=$false,HelpMessage="Try to find a local toolset.zip to install from in current directory (not recursive)")][bool]$Local=$false,
    [Parameter(Mandatory=$false,HelpMessage="Path to a toolset.zip file OR a directory where toolset.zip has already been extracted (to accelerate deployment)" )][string]$Source=$null,
    [Parameter(Mandatory=$false,HelpMessage="Target custom folder where to install toolset (usefull for deployments...) [inf-toolset subfolder will be created in it]")][string]$Destination=$null,
    [Parameter(Mandatory=$false, HelpMessage="Disable user ability to chose folder")][bool]$Nointeraction=$true
)
#Use functions to avoid having utils functions at beginning...
function Main{
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

	    if (-not (DownloadWithBits -Url $url -Destination $archivepath)) {
		exit 1
	    }
	}
	
	# Extract
	if(Test-Path -Path "$archivepath" -PathType Container)
	{
	    $archivedirectory=$archivepath
	    if(-not (Test-Path -Path "$archivepath\version.txt" -and Test-Path -Path "$archivepath\scoop\apps\scoop\current\bin\scoop.ps1"))
	    {
		Write-Error "$archivedirectory seems invalid, please check, aborting install!"
		Exit 3
	    }
	}
	else{
	    $archivedirectory = "$env:TEMP\toolset-$(New-Guid)"
	    Write-Output "About to extract $archivepath to $archivedirectory"
	    Expand-Archive $archivepath $archivedirectory
	}
	# Compress-Archive excludes (hard coded) .git directories.. they have been renamed before zipping, they need to be adjusted!
	Get-ChildItem -Path $archivedirectory -Recurse -Directory -Force -Filter ".git-force" | Rename-Item -NewName ".git"

	# Install
	Write-Output "About to launch install script"
	Set-Location $archivedirectory
	& .\install.ps1 -Destination "$Destination" -Nointeraction "$Nointeraction"

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
}

function DownloadWithBits {
    param(
        [string]$Url,
        [string]$Destination,
        [int]$TimeoutMinutes = 75,
        [int]$AvWaitSeconds = 5 #av=antivirus
    )
    
    # Function has its own parameters, but can still access script-level variables if needed
    # For example: $DestinationPath is still accessible here (though not needed in this case)
    
    try {
        Import-Module BitsTransfer -ErrorAction Stop
        Write-Output "Downloading $Url to $Destination..."
        
        $job = Start-BitsTransfer -Source $Url -Destination $Destination -Asynchronous -DisplayName "Inf Toolset Download"
        
        $timeout = (Get-Date).AddMinutes($TimeoutMinutes)
        do {
            Start-Sleep -Seconds 3
            $progress = Get-BitsTransfer -JobId $job.JobId
            
            if ($progress.BytesTransferred -gt 0) {
                $percent = [math]::Round(($progress.BytesTransferred / $progress.BytesTotal) * 100, 1)
                $mbTransferred = [math]::Round($progress.BytesTransferred / 1MB, 1)
                $mbTotal = [math]::Round($progress.BytesTotal / 1MB, 1)
		
		$progressText = "Progress: $percent% ($mbTransferred MB / $mbTotal MB)"
		#`r move cursor at the beginning of the line
                Write-Host ("`r" + " " * 120 + "`r" + $progressText) -NoNewline
            }
            
            if ((Get-Date) -gt $timeout) {
                Write-Host ""
                Remove-BitsTransfer -BitsJob $job
                throw "Download timeout after $TimeoutMinutes minutes"
            }
            
        } while ($progress.JobState -eq "Transferring" -or $progress.JobState -eq "Connecting" -or $progress.JobState -eq "TransientError")
        
        if ($progress.JobState -eq "Transferred") {
            Write-Host ""
            Complete-BitsTransfer -BitsJob $job
            Write-Output "✓ Download completed successfully"
            
            if ($AvWaitSeconds -gt 0) {
                Write-Output "Waiting for file stabilization...(av scan...)"
                Start-Sleep -Seconds 2
                
                $lastSize = 0; $elapsed = 0
                do {
                    Start-Sleep -Seconds 1; $elapsed++
                    try { 
                        $currentSize = (Get-Item $Destination).Length 
                        if ($currentSize -gt 0 -and $currentSize -eq $lastSize) { 
                            break 
                        }
                        $lastSize = $currentSize
                    } catch { }
                    if ($elapsed -ge $AvWaitSeconds) { 
                        Write-Output "File stabilized (timeout after $AvWaitSeconds seconds)"
                        break 
                    }
                } while ($true)
            }
            
            return $true
        } else {
            Write-Host ""
            Remove-BitsTransfer -BitsJob $job
            throw "Download failed: $($progress.JobState) - $($progress.ErrorDescription)"
        }
        
    } catch {
        Write-Warning "BITS download failed: $($_.Exception.Message)"
        return $false
    }
}

Main
