$install_file = 'inf-toolset.ps1'
$target_folder = "D:\data"
$target_subfolder = "inf-toolset"
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
        New-Item -Path $target -ItemType Directory -ErrorAction Stop | Out-Null
        Write-Host "Directory created successfully at: $target" -ForegroundColor Green
    } catch {
        Write-Error "Error creating directory: $_" -ForegroundColor Red
        return
    }
}

Write-Host "Ready to install etml standard toolset"

# TODO if scoop already installed ... check that it is in toolset dir... otherwise uninstall ?
Invoke-RestMethod get.scoop.sh -outfile $install_file
& ".\$install_file" -ScoopDir "$target\Scoop"
Remove-Item $install_file

# Setup scoop

## 7zip
$sevenZipPath = Get-ChildItem -Path @("${env:ProgramFiles}", "${env:ProgramFiles(x86)}") -Filter "7z.exe" -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty DirectoryName

if ($sevenZipPath) {
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")

    if ($currentPath -split ";" -notcontains $sevenZipPath) {
        # Update user PATH environment variable (persistent across sessions)
        [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$sevenZipPath", "User")
        Write-Host "Added '$sevenZipPath' to user PATH."
        # Update PATH for current process
        $env:PATH = "$env:PATH;$sevenZipPath"
        Write-Host "Added '$sevenZipPath' to current process PATH."
    } else {
        Write-Host "Path '$sevenZipPath' already in user PATH."
    }

} else {
    Write-Host "7z.exe not found in standard program folders."
}
scoop config use_external_7zip true # Use system 7zip as issues with .ru...

scoop bucket add extras

# Install apps
# insomnia -> trop lourd ?
# git : requis par scoop, bien si dans l’image
# foxit (déjà dans l’image)
scoop install dbeaver nodejs-lts@22.14.0 vscode draw.io github cmder-full warp-terminal bruno pdfsam-visual

# Add toolbar for shorcuts
# Define the path to Scoop shortcuts folder
$scoopShortcutsFolder = "$env:USERPROFILE\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Scoop Apps\"

# Check if the folder exists
if (-not (Test-Path -Path $scoopShortcutsFolder)) {
    Write-Error "Scoop shortcuts folder not found at: $scoopShortcutsFolder"
    exit
}

# Add toolbar for shorcuts
# Define the path to Scoop shortcuts folder
$scoopShortcutsFolder = "$env:USERPROFILE\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Scoop Apps\"

$shortcutPath = [Environment]::GetFolderPath("Desktop") + "\$target_subfolder.lnk"

# Check if the shortcut already exists
if (Test-Path $shortcutPath) {
    Write-Output "Shortcut already exists. Replacing it..."
    Remove-Item $shortcutPath -Force # Remove the existing shortcut
} else {
    Write-Output "Shortcut does not exist. Creating it..."
}

$iconFile = "C:\Windows\System32\shell32.dll" # The file containing standard Windows icons
$iconIndex = 12

# Create a WScript.Shell COM object
$shell = New-Object -ComObject WScript.Shell

# Create the shortcut
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = "$scoopShortcutsFolder"
$shortcut.IconLocation = "$iconFile,$iconIndex"
$shortcut.Save()

Write-Output "Shortcut created on the desktop: $shortcutPath"

