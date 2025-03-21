# standard-toolset
pour installer le toolset ETML portable

## Install

```shell
powershell -Command Invoke-WebRequest -Uri https://github.com/ETML-INF/standard-toolset/raw/main/bootstrap.cmd -OutFile %TEMP%\inf-toolset-bootstrap.bat && %TEMP%\inf-toolset-bootstrap.bat
```

## CDC
- pas de droit admin
- installation à un endroit choisi (d:\...)
- possibilité de faire son propre package facilement
- idéalement résilient aux pannes... -> possible avec archive locale
- facile à "déplacer"/"copier"
- ...

## Candidats principaux
- [nomad](https://github.com/jonathanMelly/nomad)
- [winget](https://learn.microsoft.com/en-us/windows/package-manager/winget/)
- [scoop](https://scoop.sh)

### Avantages / Inconvénients
Nomad: in house mais demande la maintenance et utilise actuellement symlink
Winget: integré à windows, package plus compliqué à faire... pas de choix de destination d’installation (copie facile des programmes)
Scoop: grande communauté (bcp d’apps), facile d’ajouter une app (bucket ETML ?), choix de destination... utilisation de shim au lieu de symlink (ok sur exfat)
