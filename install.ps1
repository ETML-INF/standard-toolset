Set-StrictMode -Version Latest

$target_folder = "D:\data"
$target_subfolder = "inf-toolset"
$target_folder_alternative = "C:\$target_subfolder"


# Check if the target folder exists
if (Test-Path -Path $target_folder) {
    # If the folder exists, set target to target_folder\target_subfolder
    $target = Join-Path -Path $target_folder -ChildPath $target_subfolder
    Write-Output "$target_folder folder exists. Target set to: $target"
} else {
    # If the folder doesn't exist, prompt the user
    Write-Warning "$target_folder folder not found."
    $userInput = Read-Host "Enter target folder path (press Enter for default: $target_folder_alternative)"
    
    # If user just pressed Enter, use the default path
    if ([string]::IsNullOrEmpty($userInput)) {
        $target = $target_folder_alternative
        Write-Output "Using default path: $target"
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
        Write-Error "Error creating directory: $_" -ForegroundColor Red
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
scoop\apps\rclone\current\rclone sync --progress .\scoop $scoopdirectory

Write-Output "Toolset install/update terminated"
Write-Output "If needed, please run 'powershell $target\setup-user-env.ps1"
