param(
    [Parameter(Mandatory=$false, HelpMessage="Disable user ability to chose folder")][bool]$Nointeraction=$false,
    [Parameter(Mandatory=$false,HelpMessage="Target custom folder where to install toolset (usefull for deployments...) [inf-toolset subfolder will be created in it]")][string]$Destination=$null
)
Set-StrictMode -Version Latest

$target_folder = if([string]::IsNullOrEmpty($Destination)){"D:\data"}else{$Destination} 
$target_subfolder = "inf-toolset"
$target_folder_alternative = "C:\$target_subfolder"

try{

    # Check if the target folder exists
    if (Test-Path -Path $target_folder) {
	# If the folder exists, set target to target_folder\target_subfolder
	$target = Join-Path -Path $target_folder -ChildPath $target_subfolder
	Write-Output "$target_folder folder exists. Target set to: $target"
    } else {
	# If the folder doesn't exist, prompt the user
	Write-Warning "$target_folder folder not found."
	if ($Nointeraction)
	{
	    $userInput=""
	}
	else{
	    $userInput = Read-Host "Enter target folder path (press Enter for default: $target_folder_alternative)"
	}
	
	# If user just pressed Enter/or no interaction, use the default alt path
	if ([string]::IsNullOrEmpty($userInput)) {
            $target = $target_folder_alternative
            Write-Output "Using default alternative path: $target"
	} else {
            # Otherwise use whatever the user entered
            $target = $userInput
            Write-Output "Using custom path: $target"
	}
    }

    # Create target if needed
    Write-Output "Checking existence of final target folder: $target"
    if (-not (Test-Path -Path $target)) {
	try {
            New-Item -Path $target -ItemType Directory -ErrorAction Stop | Out-Null
            Write-Host "Directory created successfully at: $target" -ForegroundColor Green
	} catch {
            Write-Error "Error creating directory: $_"
            return
	}
    }

    # bootstrap.ps1 sets location to extracted archive directory
    # Rclone with archive content
    Write-Host "Installing/Updating files..."
    # Compress-Archive excludes (hard coded) .git directories.. they have been renamed before zipping, they need to be adjusted!
	Get-ChildItem -Path .\ -Recurse -Directory -Force -Filter ".git-force" | Rename-Item -NewName ".git"
    $rclone=(Get-ChildItem -Path "scoop\apps\rclone\*\rclone.exe" | Select-Object -First 1).FullName
    # Exclude install to avoid confusion for end user (only activate.ps1 should be available in target dir)
    & $rclone sync --progress --exclude /install.ps1 --exclude /scoop/persist .\ $target

    # Configure environment for current user (vscode context menu+shortcut) AND restore "current" junctions !!!
    if(-not $target.StartsWith("\\")) # remote hosts cannot be activated through simple filesystem share... (must open a remote session...)
    {
	& .\activate.ps1 -Path $target -Nointeraction $true	
    }
    else{
	Write-Warning "As host is remote, no activation is run..."
    }

    Write-Host "Toolset install/update terminated" -ForegroundColor Green
    Write-Warning "For user activation, please run 'powershell $target\activate.ps1' to add desktop shortcut and setup PATH"

}
catch {
    Write-Error "Error installing toolset: $_"
}
