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

Pour une installation sans accès à GitHub, utilisez directement `toolset.ps1 update` avec les paramètres appropriés (voir section déploiement ci-dessous).

### Déploiement depuis une machine de dev (push)

Cette méthode permet d’installer le toolset sur une machine distante sans y ouvrir de session interactive.

1. [Télécharger `toolset.ps1`](https://github.com/ETML-INF/standard-toolset/releases/latest/download/toolset.ps1) depuis la page de la dernière release (fichier unique, aucune dépendance).

2. Lancer le déploiement :

```powershell
# Packs téléchargés automatiquement depuis GitHub
powershell -File toolset.ps1 update -Path \\hostname\c$\inf-toolset -NoInteraction

# Ou entièrement hors ligne (packs pré-téléchargés avec offline-download.ps1)
powershell -File toolset.ps1 update -Path \\hostname\c$\inf-toolset `
    -PackSource C:\packs -ManifestSource C:\packs\release-manifest.json -NoInteraction
```

3. Ordre de résolution des packs : `-PackSource` → `L:\toolset` → GitHub.

   Les packs peuvent aussi être fournis sous forme de **dossiers pré-extraits** (sans `.zip`) :
   `C:\packs\vscode-1.95.3\` à la place de `C:\packs\vscode-1.95.3.zip`.
   Un contrôle rapide (version + comptage de fichiers via métadonnées du zip si les deux existent) détecte les incohérences et retombe sur le zip automatiquement.

4. Sur chaque machine cible, lancer `toolset.ps1` (sans argument) pour activer le toolset.

## **Activation**
Quand le toolset a été installé sur une machine, il faut lancer `toolset.ps1` (sans argument) depuis `c:\inf-toolset\` ou `d:\data\inf-toolset\` pour l’activer.
Cela va finaliser l’installation (si nécessaire), ajouter les apps dans le PATH et ajouter les menus contextuels (pour vscode par exemple).

## Utilisation
### Versions de node
Puisque NVM requiert des droits admin, pour jongler avec différentes versions d’un logiciel (par exemple node), il faut [activer le toolset](README.md#--activation--) et adapter l’exemple suivant à ses besoins:

``` shell
echo "Current installed node versions: " && scoop list nodejs
echo "Available versions : " && scoop search nodejs
echo "Install custom version: " && scoop install nodejs18
echo "Install another version: " && scoop install nodejs20
echo "Switch to an installed version: " && scoop reset nodejs20

```

## Développement

### Prérequis

- PowerShell 7+ (`pwsh`)
- Docker Desktop en mode **Windows containers**
  (clic droit icône barre des tâches → "Switch to Windows containers")
- Git

### Structure du projet

```
toolset.ps1          — point d'entrée utilisateur (update / status / activate)
build.ps1            — génère les packs d'apps pour une release
setup.ps1            — bootstrap : télécharge toolset.ps1 et lance update
offline-download.ps1 — prépare un dossier L:\toolset pour déploiement hors ligne
apps.json            — liste des apps incluses dans le toolset
tests/               — suite de tests (voir tests/README.md)
.github/workflows/   — CI/CD (release, tests, build de l'image de base)
```

### Lancer les tests

Les tests tournent dans des conteneurs Windows isolés — aucun risque de modifier
votre PATH, registre ou installation scoop locale.

```powershell
# Tests toolkit (update / status / activation) — aucune dépendance réseau
pwsh tests/Run-ContainerTests.ps1

# Tests build pipeline — nécessite l'image de base (voir ci-dessous)
pwsh tests/Run-BuildTests.ps1
```

Voir [tests/README.md](tests/README.md) pour le détail des scénarios et la mise
en place de l'image de base (`build-base`).

### Faire une release

Les releases sont gérées par [release-please](https://github.com/googleapis/release-please).
Écrire des commits en [Conventional Commits](https://www.conventionalcommits.org/) :

```
feat: add new app xyz
fix(toolkit): handle missing manifest gracefully
chore: update scoop bucket url
```

Un PR de release est automatiquement créé et mergé → déclenche `release.yml` →
`build.ps1` génère les packs → assets uploadés sur la release GitHub.

### Ajouter une app

1. Ajouter l'entrée dans `apps.json` :
   ```json
   { "name": "myapp", "bucket": "extras" }
   ```
   Ou avec version épinglée : `{ "name": "myapp", "version": "1.2.3" }`

2. Si l'app stocke ses paramètres dans son dossier d'installation (mode portable), ce qui empêche une configuration par utilisateur, ajouter le champ `paths2DropToEnableMultiUser` listant les chemins relatifs à supprimer lors de l'activation pour forcer l'utilisation de `%APPDATA%` :
   ```json
   { "name": "myapp", "paths2DropToEnableMultiUser": ["data"] }
   ```
   Ces chemins correspondent aux entrées `persist` du manifest scoop de l'app (junctions créées par scoop). Les supprimer force l'app à utiliser le profil Windows de l'utilisateur courant au lieu d'un dossier partagé. Laisser vide ou omettre si le comportement partagé est souhaité (ex: cmder — aliases communs à tous).

3. Vérifier que l'app est disponible dans un bucket scoop connu :
   ```powershell
   scoop search myapp
   ```

4. Créer un commit `feat: add myapp` → le prochain cycle de release inclura l'app.

### CI/CD

| Workflow               | Déclencheur                          | Rôle                                |
|------------------------|--------------------------------------|-------------------------------------|
| `ci.yml`               | push / PR sur main                   | Tests toolkit + build pipeline      |
| `release.yml`          | release-please merge                 | Build packs + upload release assets |
| `build-base-image.yml` | manuel / modif Dockerfile.build-base | Rebuild image de base des tests     |

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
