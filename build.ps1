param(
    [Parameter(Mandatory=$false,HelpMessage="Path to json file containing app definitions")]
    [string]$appJson = "apps.json"
    
)

try {
    Set-StrictMode -Version Latest

    Write-Output "Installing scoop"
    $install_file = "iscoop.ps1"
    Invoke-RestMethod get.scoop.sh -outfile "$($pwd)\$install_file"
    & ".\$install_file" -ScoopDir "$($pwd.Path)\build\scoop"
    Remove-Item $install_file

    scoop bucket add extras
    scoop bucket add etml-inf https://github.com/ETML-INF/standard-toolset-bucket

    # Install apps
    Write-Output "About to install apps defined in $appJson"
    $apps = Get-Content -Raw $appJson | ConvertFrom-Json

    foreach ($app in $apps) {
	try {
	    if ($app | Get-Member -Name 'bucket') {
		$appName =  "$($app.bucket)/$($app.name)"
	    }
	    else {
		$appName = $app.name
	    }
	    if ($app | Get-Member -Name 'version') {
		$appName = "$($appName)@$($app.version)"
	    }
            Write-Host "Installing $appName..." -ForegroundColor Green
            scoop install $appName
	}
	catch {
            Write-Warning "Failed to install $($app.name): $_"
	}
    }
    #We could purge cache here but won't be able to use ghaction cache abilities in that case...

}
catch {
    Write-Error "Something went wrong: $_. "
}
