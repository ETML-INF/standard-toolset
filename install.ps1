$install_file = 'install-etml-standard-toolset.ps1'
$target_folder = "D:\data"
$target_subfolder = "standard-toolset"
$target_folder_alternative = "C:\$target_subfolder"

# Title
Write-Host "+--------------------------------+" -ForegroundColor Cyan
Write-Host "|" -ForegroundColor Cyan -NoNewline
Write-Host "   ETML-INF STANDARD TOOLSET    " -ForegroundColor White -NoNewline
Write-Host "|" -ForegroundColor Cyan
Write-Host "+--------------------------------+" -ForegroundColor Cyan

# Check if the target folder exists
if (Test-Path -Path $target_folder) {
    # If the folder exists, set target to target_folder\target_subfolder
    $target = Join-Path -Path $target_folder -ChildPath $target_subfolder
    Write-Host "$target_folder folder exists. Target set to: $target"
} else {
    # If the folder doesn't exist, prompt the user
    Write-Warning "$target_folder folder not found."
    $userInput = Read-Host "Enter target folder path (press Enter for default: $target_folder_alternative)"
    
    # If user just pressed Enter, use the default path
    if ([string]::IsNullOrEmpty($userInput)) {
        $target = $target_folder_alternative
        Write-Host "Using default path: $target"
    } else {
        # Otherwise use whatever the user entered
        $target = $userInput
        Write-Host "Using custom path: $target"
    }
}

# Print the final target variable
Write-Host "Final target folder: $target"

if (-not (Test-Path -Path $target)) {
    try {
        New-Item -Path $target -ItemType Directory -ErrorAction Stop
        Write-Host "Directory created successfully at: $directoryPath" -ForegroundColor Green
    } catch {
        Write-Error "Error creating directory: $_" -ForegroundColor Red
        return
    }
}

Write-Host "Ready to install etml standard toolset"


Invoke-RestMethod get.scoop.sh -outfile $install_file
& ".\$install_file" -ScoopDir "$target\Scoop"
Remove-Item $install_file

# Setup scoop
scoop bucket add extras

# Install apps
# insomnia -> trop lourd ?
# git ?? / foxit ??
#scoop install dbeaver nvm vscode draw.io github cmder-full warp-terminal bruno pdfsam-visual

# Add toolbar for shorcuts
# Define the path to Scoop shortcuts folder
$scoopShortcutsFolder = "$env:USERPROFILE\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Scoop Apps\"

# Check if the folder exists
if (-not (Test-Path -Path $scoopShortcutsFolder)) {
    Write-Error "Scoop shortcuts folder not found at: $scoopShortcutsFolder"
    exit
}

# Check if the toolbar already exists
$existingToolbars = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Toolbars\*" -ErrorAction SilentlyContinue
$toolbarExists = $false

foreach ($toolbar in $existingToolbars) {
    if ($toolbar.PSPath -like "*$scoopShortcutsFolder*") {
        $toolbarExists = $true
        break
    }
}

# Only create the toolbar if it doesn't exist
if (-not $toolbarExists) {
    # Create the registry key for the toolbar
    $registryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Toolbars\$scoopShortcutsFolder"
    if (-not (Test-Path -Path $registryPath)) {
        New-Item -Path $registryPath -Force | Out-Null
    }

    # Add the Toolbar to the registry
    New-ItemProperty -Path $registryPath -Name "Toolbar" -Value "Tools" -PropertyType String -Force | Out-Null

    # Restart Explorer to apply changes
    Write-Host "Toolbar added. Restarting Explorer to apply changes..." -ForegroundColor Green
    Stop-Process -Name explorer -Force
    Start-Process explorer
} else {
    Write-Warning "Toolbar for Scoop shortcuts already exists."
}

