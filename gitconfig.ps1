$path = $args[0]
$search = "[safe]","directory"
$add = "`tdirectory = C:/inf-toolset/*"

# Lire tout le fichier
$content = Get-Content $path

$safeIndex = ($content | Select-String "^\[safe\]$").LineNumber - 1
$dirIndex  = ($content | Select-String "^\s*directory\s*=").LineNumber - 1

# [safe] existe
if ($safeIndex -ge 0) {

    # directory existe → remplacer
    if($dirIndex -ge 0)
    {
        # Insérer après [safe]
        $content[$dirIndex] = $add
    } 
    # directory n'existe pas → ajouter après [safe]
    else {
        # Insérer après [safe]
        $content = $content[0..$dirIndex] + @($add) + $content[($dirIndex+1)..($content.Length-1)]
    }
}
# [safe] n'existe pas
else {
    # ajouter [safe] et directory au content
    $content = @("[safe]", $add) + $content
}

# réécrire le fichier
$content | Set-Content $path