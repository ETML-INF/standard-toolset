# standard-toolset
pour installer le toolset ETML portable

## Install

### Cmd.exe

``` shell
powershell -Command "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force; Invoke-RestMethod -Uri https://github.com/ETML-INF/standard-toolset/raw/main/bootstrap.ps1 | Invoke-Expression"
```

### Powershell / Pwsh
```pwsh
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
Invoke-RestMethod -Uri https://github.com/ETML-INF/standard-toolset/raw/main/bootstrap.ps1 | Invoke-Expression
```

#### Local and offline install
If you already downloaded an archive, you can either

- Reuse it adding -local $true as first parameter of bootstrap.ps1 [online bootstrap]

### Powershell / Pwsh
```pwsh
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
& ([ScriptBlock]::Create((Invoke-RestMethod -Uri https://github.com/ETML-INF/standard-toolset/raw/main/setup.ps1))) -Local $true
```

**You may also give a path to an archive or/and a path where to install  (usefull for offline deployment or to accelerate deployment from local resources...)**
### Powershell / Pwsh
```pwsh
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
& ([ScriptBlock]::Create((Invoke-RestMethod -Uri https://github.com/ETML-INF/standard-toolset/raw/main/setup.ps1))) -Source "C:\downloads\toolset.zip" -Destination "\\host\d$\data"
```



- Or extract it and run ‘install.ps1’ [complete offline]

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
Scoop: grande communauté (bcp d’apps), facile d’ajouter une app (bucket ETML ?), choix de destination... utilisation de shim au lieu de symlink (ok sur exfat)

## Cycle
Pour harmoniser les versions :
- [x] Une release par année
- [x] Patchs durant l’année si urgence
