param(
    [Parameter(Mandatory=$false,HelpMessage="Path to json file containing app definitions")]
    [string]$appJson = "apps.json"
    
)


Set-StrictMode -Version Latest
# Setup scoop
Write-Output "Installing scoop"

# To be done in action ?
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
Write-Output "Installing scoop"
$install_file = "iscoop.ps1"
Invoke-RestMethod get.scoop.sh -outfile "$($pwd)\$install_file"
& ".\$install_file" -ScoopDir "$($pwd.Path)\build\scoop"
Remove-Item $install_file

scoop bucket add extras
scoop bucket add etml-inf https://github.com/ETML-INF/standard-toolset-bucket

# Install apps
$apps = Get-Content -Raw $appJson | ConvertFrom-Json

foreach ($app in $apps) {
    try {
        $appName = if ($app.bucket) { "$($app.bucket)/$($app.name)" } else { $app.name }
	if ($app.version){ $appName = "$($appName)@$($app.version)"}
        Write-Output "Installing $appName..." -ForegroundColor Green
        scoop install $appName
    }
    catch {
        Write-Warning "Failed to install $($app.name): $_"
    }
}
