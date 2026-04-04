# standard-toolset
Set d’outils standardisés pour l’ETML.
Cette boîte à outils peut être facilement transportée/répliquée/déployée et contient uniquement des applications portables (pas de droit admin nécessaire).

La liste des apps est décrite dans le fichier [apps.json](apps.json)
## Installation

### Depuis le réseau local (L:\) — recommandé en salle

Copier-coller dans **cmd.exe** :

```shell
powershell -ExecutionPolicy Bypass -File L:\toolset\toolset.ps1 update
```

Ou dans **PowerShell / pwsh** :

```powershell
& L:\toolset\toolset.ps1 update
```

> Les packs sont lus directement sur `L:\toolset` — aucun accès Internet nécessaire.
> Si des apps privées sont définies dans `L:\toolset\private-apps.json`, elles sont incluses automatiquement.

#### Mode entièrement hors ligne (contourne GitHub à 100%)

Par défaut, `toolset.ps1` fait une vérification non-bloquante sur GitHub pour détecter si une version plus récente est disponible sur le réseau.
Pour court-circuiter complètement GitHub (réseau sans accès Internet, déploiement de masse) :

```shell
powershell -ExecutionPolicy Bypass -File L:\toolset\toolset.ps1 update -ManifestSource L:\toolset\release-manifest.json -PackSource L:\toolset -NoInteraction
```

Ou en pwsh :

```powershell
& L:\toolset\toolset.ps1 update -ManifestSource L:\toolset\release-manifest.json -PackSource L:\toolset
```

> `-ManifestSource` force la lecture du manifest depuis ce fichier (pas de requête réseau).
> `-PackSource` indique le dossier local contenant les `.zip` — GitHub n'est jamais contacté.

### Depuis GitHub (Internet)

#### Cmd.exe

``` shell
powershell -Command "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://github.com/ETML-INF/standard-toolset/raw/main/setup.ps1'))"
```

#### PowerShell / pwsh

```pwsh
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://github.com/ETML-INF/standard-toolset/raw/main/setup.ps1'))
```

> **En cas d'erreur** (stratégie d'exécution bloquée), installer PowerShell 7 puis relancer :
> ```shell
> winget install Microsoft.PowerShell
> ```
> Puis relancer dans une nouvelle fenêtre `pwsh`.

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
Puisque NVM requiert des droits admin, pour jongler avec différentes versions d’un logiciel (par exemple node), il faut [activer le toolset](README.md#activation) et adapter l’exemple suivant à ses besoins:

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

### Build local (sans CI/CD)

`local-build.ps1` génère les packs sur votre machine et les déploie directement sur `L:\toolset` (ou tout autre dossier).

```powershell
# Build standard → déploie sur L:\toolset
.\local-build.ps1

# Avec proxy SOCKS5 (réseau restreint, pas d'accès direct à Internet)
.\local-build.ps1 -Proxy socks5://localhost:1234

# Avec proxy HTTP
.\local-build.ps1 -Proxy http://localhost:1234

# Dossier de sortie différent (L:\ non disponible — copier manuellement ensuite)
.\local-build.ps1 -OutputDir C:\tmp\toolset-out
```

> Le proxy est passé aux variables d'environnement `HTTP_PROXY`, `HTTPS_PROXY` et `ALL_PROXY`
> à l'intérieur du conteneur Docker. PowerShell 7 / .NET 6+ supporte nativement `socks5://`
> sans outil supplémentaire.
>
> Si `OutputDir` (`L:\toolset` par défaut) est inaccessible, le build se termine quand même :
> les packs et le manifest sont déposés dans `build\packs\` pour copie manuelle ultérieure.

### Lancer les tests

Les tests tournent dans des conteneurs Windows isolés — aucun risque de modifier
votre PATH, registre ou installation scoop locale.

```powershell
# Vérifications statiques + tests toolkit (update / status / activation)
pwsh tests/Test-All.ps1

# Tests toolkit seuls
pwsh tests/Run-ToolsetTests.ps1

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

   | Champ | Requis | Type | Description |
   |-------|--------|------|-------------|
   | `name` | ✅ | string | Nom de l'app dans scoop |
   | `bucket` | — | string | Bucket scoop à ajouter si l'app n'est pas dans le bucket principal (`main`) |
   | `version` | — | string | Version épinglée (ex. `"1.2.3"`). Sans ce champ, scoop installe la dernière version disponible |
   | `tags` | — | string | Catégorie libre (ex. `"system"`, `"dev"`) — non utilisé par le toolset, à titre indicatif |
   | `paths2DropToEnableMultiUser` | — | string[] | Chemins relatifs (entrées `persist` scoop) à supprimer lors de l'activation pour forcer l'utilisation de `%APPDATA%` au lieu du dossier partagé. Omettre si le partage est souhaité (ex. cmder — aliases communs) |
   | `integrityExcludePaths` | — | string[] | Chemins relatifs exclus du contrôle d'intégrité (ex. sous-dossiers accumulant des fichiers utilisateur après installation) |
   | `patchBuildPaths` | — | boolean | `true` pour remplacer le chemin persist du build CI par le chemin réel lors de l'activation (nécessaire si l'app embarque des chemins absolus dans ses fichiers de config) |
   | `shortcuts` | — | [string, string][] | Raccourcis à créer dans le menu Démarrer lors de l'activation. Chaque entrée est une paire `[cheminExe, nomAffiche]` où `cheminExe` est relatif à `current\` (ex. `[["MyApp.exe", "My App"]]`) |
   | `//comment` | — | string | Commentaire ignoré par le toolset |

   Exemple minimal : `{ "name": "myapp", "bucket": "extras" }`

   Exemple avec version épinglée : `{ "name": "myapp", "version": "1.2.3" }`

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
