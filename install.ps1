param(
    [Parameter(Mandatory=$false, HelpMessage="Disable user ability to chose folder")][bool]$nointeraction=$false
)
Set-StrictMode -Version Latest

$target_folder = "D:\data"
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
	if ($nointeraction)
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
            Write-Output "Directory created successfully at: $target" -ForegroundColor Green
	} catch {
            Write-Error "Error creating directory: $_"
            return
	}
    }

    # bootstrap.ps1 sets location to extracted archive directory
    # Rclone with archive content
    $scoopdirectory="$target\scoop"
    if (-not (Test-Path $scoopdirectory))
    {
	New-Item -ItemType Directory -Path $scoopdirectory
    }
    Write-Host "Syncing files"
    & (Get-ChildItem -Path "scoop\apps\rclone\*\rclone.exe" | Select-Object -First 1).FullName --progress .\scoop $scoopdirectory

    # Configure environment for current user (vscode context menu+shortcut) AND restore "current" junctions !!!
    & .\setup-user-env.ps1 $target

    Write-Host "Toolset install/update terminated on host" -ForegroundColor Green
    Write-Warning "For other users, please run 'powershell $target\setup-user-env.ps1' to add desktop shortcut and setup PATH"

}
catch {
    Write-Error "Error installing toolset: $_"
}
