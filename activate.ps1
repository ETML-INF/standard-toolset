param(
    [Parameter(Mandatory=$false,HelpMessage="Path where to expect toolset to be")][string]$Path="C:\inf-toolset",
    [Parameter(Mandatory=$false, HelpMessage="Disable user ability to chose folder")][bool]$Nointeraction=$false,
    [Parameter(Mandatory=$false)][bool]$ConsoleOutput = $true
)
# Start transcript for logging (parallel-safe with unique filename)
if (-not $ConsoleOutput) {
    $logFile = "$PSScriptRoot\activate-$PID.log"
    Start-Transcript -Path $logFile -Append -Force
}

try {
    Set-StrictMode -Version Latest
    # Validate current install
    $toolsetdir = $Path
    if (-not (Test-Path -Path $toolsetdir))
    {
	$toolsetdir = "c:\data\inf-toolset"
	if (-not (Test-Path -Path $toolsetdir))
	{
	    Write-Output "Toolset not found in given/standard locations"
	    if(-not $Nointeraction){
		$userInput = Read-Host "Enter custom toolset path (empty/ctrl-c to abort)"	
	    }
	    if ([string]::IsNullOrEmpty($userInput))
	    {
		Exit 1
	    }
	    elseif (Test-Path $userinput)
	    {
		# Otherwise use whatever the user entered
		$toolsetdir = $userInput
		Write-Output "Using custom path: $toolsetdir"
	    }
	    else{
		Write-Error "$userinput does not seem to exist, aborting"
		Exit 2
	    }
	}
    }

    # For initial install : mainly restore "current" junctions (removed by Compress-Archive during build)
    # For further user setup: mainly set path for current user
    $scoopdir = "$toolsetdir\scoop"
    Write-Host "Resetting scoop to mainly handle path settings for user"
    & $scoopdir\apps\scoop\current\bin\scoop.ps1 reset *
    
    # regen scoop special shims
    Write-Output "Updating scoop shims with path $toolsetdir..."
    $shimpath = "$scoopdir\shims"
    @("$shimpath\scoop", "$shimpath\scoop.cmd","$shimpath\scoop.ps1") | ForEach-Object { 
	$content = Get-Content $_ -Raw
	$content -replace '[A-Z]:.*?\\scoop\\', "$scoopdir\" | Set-Content $_ -NoNewline
    }

    # Fix paths in reg files too
    Write-Host "Fixing path to $toolsetdir for reg files..."
    Get-ChildItem "$scoopdir\apps\*\current\*.reg" -Recurse | ForEach-Object {
	$content = Get-Content $_ -Raw
	$content -replace '[A-Z]:.*?\\\\scoop\\\\', "$($scoopdir -replace '\\', '\\')\\" | Set-Content $_ -NoNewline
    }

    # Add context menu for vscode (now scoop should be in path...)
    $vscode = scoop prefix vscode
    & reg import "$vscode\install-context.reg"
    Write-Output "VSCode context menu added/updated"

    # Add toolbar for shorcuts
    # Define the path to Scoop shortcuts folder
    $scoopShortcutsFolder = "$env:USERPROFILE\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Scoop Apps\"

    # Check if the folder exists (after reset, it should exist !)
    if (-not (Test-Path -Path $scoopShortcutsFolder))
    {
	Write-Error "Scoop shortcuts folder not found at: $scoopShortcutsFolder"
	exit
    }

    $target_subfolder = Split-Path -Path $toolsetdir -Leaf
    $shortcutPath = [Environment]::GetFolderPath("Desktop") + "\$target_subfolder.lnk"

    # Check if the shortcut already exists
    if (Test-Path $shortcutPath)
    {
	Write-Output "Shortcut already exists. Replacing it..."
	Remove-Item $shortcutPath -Force # Remove the existing shortcut
    } else
    {
	Write-Output "Shortcut does not exist. Creating it..."
    }

    $iconFile = "C:\Windows\System32\shell32.dll" # The file containing standard Windows icons
    $iconIndex = 12 #Chip

    # Create a WScript.Shell COM object
    $shell = New-Object -ComObject WScript.Shell

    # Create the shortcut
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = "$scoopShortcutsFolder"
    $shortcut.IconLocation = "$iconFile,$iconIndex"
    $shortcut.Save()

    Write-Output "Shortcut created on the desktop: $shortcutPath"
	# npm config ls -l dit que  cache = "D:\\a\\standard-toolset\\standard-toolset\\build\\scoop\\persist\\nodejs-lts\\cache" prefix = "D:\\a\\standard-toolset\\standard-toolset\\build\\scoop\\persist\\nodejs-lts\\bin"
	# saufe que nous on veux C: donc
	# j'ai généré ce script avec gemini
	# Fix npm configuration files
	Write-Host "Fixing npm config paths..."
	Get-ChildItem "$scoopdir\persist\nodejs*\bin\etc\npmrc" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
		Write-Host "Fixing $_"
		$content = Get-Content $_ -Raw
		# Fix paths like D:\a\standard-toolset\standard-toolset\build\scoop\persist to correct installation path
		$content = $content -replace 'D:\\a\\standard-toolset\\standard-toolset\\build\\scoop\\persist', "$($scoopdir -replace '\\', '\\')\persist"
		# Also fix any general pattern with drive letter for build paths
		$content = $content -replace '[A-Z]:\\\\a\\\\.*? \\\\build\\\\scoop\\\\persist', "$($scoopdir -replace '\\', '\\')\persist"
		Set-Content $_ -Value $content -NoNewline
	}

	# Also fix the builtin npmrc in the nodejs installation itself
	Get-ChildItem "$scoopdir\apps\nodejs*\*\node_modules\npm\npmrc" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
		Write-Host "Fixing builtin npmrc:  $_"
		$content = Get-Content $_ -Raw
		$content = $content -replace 'D:\\a\\standard-toolset\\standard-toolset\\build\\scoop\\persist', "$($scoopdir -replace '\\', '\\')\persist"
		$content = $content -replace '[A-Z]:\\a\\.*?\\build\\scoop\\persist', "$($scoopdir -replace '\\', '\\')\persist"
		Set-Content $_ -Value $content -NoNewline
	}
}
catch {
    Write-Error "Something went wrong: $_. "
} finally {
    if (-not $ConsoleOutput) {
        Stop-Transcript
    }
}
