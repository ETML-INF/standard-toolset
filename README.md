# standard-toolset
Set d’outils standardisés pour l’ETML.
Cette boîte à outils peut être facilement transportée/répliquée/déployée et contient uniquement des applications portables (pas de droit admin nécessaire).

La liste des apps est décrite dans le fichier [apps.json](apps.json)
## Installation

### Cmd.exe

``` shell
powershell -Command "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force; Invoke-RestMethod -Uri https://github.com/ETML-INF/standard-toolset/raw/main/setup.ps1 | Invoke-Expression"
```

### Powershell / Pwsh
```pwsh
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
Invoke-RestMethod -Uri https://github.com/ETML-INF/standard-toolset/raw/main/setup.ps1 | Invoke-Expression
```

#### En local ou offline
Après avoir [téléchargé l’archive](https://github.com/ETML-INF/standard-toolset/releases/latest/download/toolset.zip) on peut:

- Éviter qu’elle soit téléchargée en ajoutant ‘-Local $true’ :

```pwsh
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
& ([ScriptBlock]::Create((Invoke-RestMethod -Uri https://github.com/ETML-INF/standard-toolset/raw/main/setup.ps1))) -Local $true
```

- Indiquer clairement le chemin vers le zip ET/OU le répertoire de destination (utile pour le déploiement distant) ‘-Source ... -Destination ...’:

```pwsh
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
& ([ScriptBlock]::Create((Invoke-RestMethod -Uri https://github.com/ETML-INF/standard-toolset/raw/main/setup.ps1))) -Source "C:\downloads\toolset.zip" -Destination "\\host\d$\data"
```

- Indiquer le chemin vers le dossier déjà décompressé (nécessite 7z ou Expand-Archive) ‘-Source c:\directory’:
```pwsh
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
& ([ScriptBlock]::Create((Invoke-RestMethod -Uri https://github.com/ETML-INF/standard-toolset/raw/main/setup.ps1))) -Source "C:\downloads\toolset" -Destination "\\host\d$\data"
```

- Décompresser l’archive et lancer ‘install.ps1’ [complete offline]

## **Activation**
Quand le toolset a été installé sur une machine, il faut lancer ‘c:\inf-toolset\activate.ps1’ ou ‘d:data\inf-toolset\activate.ps1’ pour l’activer.
Cela va finaliser l’installation (si nécessaire), ajouter les apps dans le PATH et ajouter les menus contextuels (pour vscode par exemple).

## CDC
- pas de droit admin
- installation à un endroit choisi (d:\...)
- possibilité de faire son propre package facilement
- idéalement résilient aux pannes... -> possible avec archive locale
- facile à "déplacer"/"copier"
- ...

## Candidats principaux pour le moteur de base
- [nomad](https://github.com/jonathanMelly/nomad)
- [winget](https://learn.microsoft.com/en-us/windows/package-manager/winget/)
- [scoop](https://scoop.sh)

### Avantages / Inconvénients
Nomad: in house mais demande la maintenance et utilise actuellement symlink
Winget: integré à windows, package plus compliqué à faire... pas de choix de destination d’installation (copie facile des programmes)
Scoop: grande communauté (bcp d’apps), facile d’ajouter une app (bucket ETML ?), choix de destination... utilisation de shim au lieu de symlink (ok sur exfat)

## Cycle
Pour harmoniser les versions :
- [x] Une release par année
- [x] Patchs durant l’année si urgence
