# Changelog

## [1.12.0](https://github.com/philippe-hjik/standard-toolset/compare/v1.11.1...v1.12.0) (2026-02-06)


### Features

* **activate:** add gitconfig script for user ([597bf77](https://github.com/philippe-hjik/standard-toolset/commit/597bf7702d5223a7626d093b2cf12d324339db6d))
* **activate:** install nodejs-lts in activate.ps1 ([3245601](https://github.com/philippe-hjik/standard-toolset/commit/3245601e8455a7225a9d053c6c05dc33f4fb3efc))
* **apps:** add mqttx ([8f57789](https://github.com/philippe-hjik/standard-toolset/commit/8f57789949e3aa9577f2a349779222279c9725c9))

## [1.11.1](https://github.com/philippe-hjik/standard-toolset/compare/v1.11.0...v1.11.1) (2026-02-05)


### Miscellaneous Chores

* release 1.11.1 ([d210650](https://github.com/philippe-hjik/standard-toolset/commit/d2106508939ec67b95afc3f0a8de5ca51df13efa))

## [1.11.0](https://github.com/philippe-hjik/standard-toolset/compare/v1.10.0...v1.11.0) (2026-02-05)


### Features

* **apps.json:** add a new app ([b6b88a5](https://github.com/philippe-hjik/standard-toolset/commit/b6b88a5768da21cf59b7f3d75de710c0bbdc6558))
* **apps.json:** add new apps ([8534140](https://github.com/philippe-hjik/standard-toolset/commit/853414033588eb8b63516685b9ad0a6ce96ce7c2))
* **apps:** add laragon ([5939f19](https://github.com/philippe-hjik/standard-toolset/commit/5939f19fe8b42093468efdacbc56240317f7c8c8))
* **apps:** add python3 asked by MMN (devops cicd) ([e1e1e30](https://github.com/philippe-hjik/standard-toolset/commit/e1e1e30481d14d668a308c97889c366a35e60994))


### Bug Fixes

* **apps.json:** add new app ([508b282](https://github.com/philippe-hjik/standard-toolset/commit/508b282c2a7646a6c7fdf3e19c0ce60c63511f8b))
* **readme:** ajout du backslash manquant après la lettre de lecteur ([5fe2796](https://github.com/philippe-hjik/standard-toolset/commit/5fe2796676725208a2aaab3f44bcc20748eda256))

## [1.10.0](https://github.com/ETML-INF/standard-toolset/compare/v1.9.0...v1.10.0) (2025-12-03)


### Features

* **apps:** added filezilla ([80d2a74](https://github.com/ETML-INF/standard-toolset/commit/80d2a748969b5d9d33bff17aba64ec1020be208e))
* **print:** added transcript to be able to use parallel mode ([80e7f63](https://github.com/ETML-INF/standard-toolset/commit/80e7f63069024963bae41026151e8937b1eb04bd))


### Bug Fixes

* **activate:** log custom path correctly ([cd7ea7a](https://github.com/ETML-INF/standard-toolset/commit/cd7ea7a7debcee4387a8bf58854cfd5714ce487c))
* **setup:** try to avoid "path too long" limitation... ([3365ca7](https://github.com/ETML-INF/standard-toolset/commit/3365ca7e888ed9f8068657355400439b99eaafcb))

## [1.9.0](https://github.com/ETML-INF/standard-toolset/compare/v1.8.1...v1.9.0) (2025-08-12)


### Features

* **install:** add -Source to install.ps1 to be able to run dev ([4b07089](https://github.com/ETML-INF/standard-toolset/commit/4b070892aa5661d5050f3354e6b5bf0091294aa4))
* **install:** default to c:\inf-toolset and secondary to d:\data ([4b07089](https://github.com/ETML-INF/standard-toolset/commit/4b070892aa5661d5050f3354e6b5bf0091294aa4))
* **release:** add versions.txt to release to see apps details ([aa64c01](https://github.com/ETML-INF/standard-toolset/commit/aa64c01312f5bf66ef8011c4c6b08d5f5dc91f3a))
* **release:** print app versions ([9df4c18](https://github.com/ETML-INF/standard-toolset/commit/9df4c18b2e47e53c08b52882360604d81eb8691e))

## [1.8.1](https://github.com/ETML-INF/standard-toolset/compare/v1.8.0...v1.8.1) (2025-07-18)


### Bug Fixes

* **cicd:** write version(tag_name) instead of release status ([1c890e1](https://github.com/ETML-INF/standard-toolset/commit/1c890e12448ce8b0e4834461d4b22efa6a693829))
* **install:** exclude syntax without comma ([1c890e1](https://github.com/ETML-INF/standard-toolset/commit/1c890e12448ce8b0e4834461d4b22efa6a693829))
* **install:** exclude syntax without comma ([1d19bdf](https://github.com/ETML-INF/standard-toolset/commit/1d19bdf48616fde6aaeccae975bdaabbf3932a02))
* **nointeraction:** as boolean instead of string ([38bc49a](https://github.com/ETML-INF/standard-toolset/commit/38bc49a08db6704d751cc73d07714946cf75b39c))
* **setup:** better chance of cleanup + message ([1d454d1](https://github.com/ETML-INF/standard-toolset/commit/1d454d186c41105c5a0f192f9e60841ee3289f36))
* **setup:** correct check uncompressed archive source ([272bbea](https://github.com/ETML-INF/standard-toolset/commit/272bbeaab8c8f144059dfe763c15bebe6d736b77))
* **setup:** download error stops setup ([c8d31c8](https://github.com/ETML-INF/standard-toolset/commit/c8d31c859e6d7d988bb323a528f8e10f30305724))
* **setup:** download timeout increased to 75m ([c8d31c8](https://github.com/ETML-INF/standard-toolset/commit/c8d31c859e6d7d988bb323a528f8e10f30305724))

## [1.8.0](https://github.com/ETML-INF/standard-toolset/compare/v1.7.0...v1.8.0) (2025-07-17)


### Features

* **install:** do not copy install.ps1 ([7432f61](https://github.com/ETML-INF/standard-toolset/commit/7432f6116ec6cfdc01d79a86cfc0a7ee94faec5a))
* **install:** let scoop persist dir as is ([7432f61](https://github.com/ETML-INF/standard-toolset/commit/7432f6116ec6cfdc01d79a86cfc0a7ee94faec5a))


### Bug Fixes

* **cicd:** put back install script ! ([7432f61](https://github.com/ETML-INF/standard-toolset/commit/7432f6116ec6cfdc01d79a86cfc0a7ee94faec5a))
* **install:** use updated activate.ps1 ([7432f61](https://github.com/ETML-INF/standard-toolset/commit/7432f6116ec6cfdc01d79a86cfc0a7ee94faec5a))

## [1.7.0](https://github.com/ETML-INF/standard-toolset/compare/v1.6.0...v1.7.0) (2025-07-17)


### Features

* **setup:** allow install from local uncompressed archive ([73af5a4](https://github.com/ETML-INF/standard-toolset/commit/73af5a4aa90c68293cb58b4949a52594b1d2d508))


### Bug Fixes

* **archive:** add README and License ([73af5a4](https://github.com/ETML-INF/standard-toolset/commit/73af5a4aa90c68293cb58b4949a52594b1d2d508))
* **deploy:** do not activate upon remote deployment ([73af5a4](https://github.com/ETML-INF/standard-toolset/commit/73af5a4aa90c68293cb58b4949a52594b1d2d508))
* **install:** honor Nointeraction for activate.ps1 too ([73af5a4](https://github.com/ETML-INF/standard-toolset/commit/73af5a4aa90c68293cb58b4949a52594b1d2d508))
* **README:** everything in french ([73af5a4](https://github.com/ETML-INF/standard-toolset/commit/73af5a4aa90c68293cb58b4949a52594b1d2d508))

## [1.6.0](https://github.com/ETML-INF/standard-toolset/compare/v1.5.1...v1.6.0) (2025-07-15)


### Features

* **apps:** added rclone(needed for install) and kopia as backup util ([b006db1](https://github.com/ETML-INF/standard-toolset/commit/b006db1956c018781cde16f91065127aea18b766))
* **setup:** use bits instead of unreliable invoke-webrequest ([467faa1](https://github.com/ETML-INF/standard-toolset/commit/467faa158fafbd8a68a5c456a87a5552d11deb5b))


### Bug Fixes

* **archive:** includes .git folders ([8041cd4](https://github.com/ETML-INF/standard-toolset/commit/8041cd4aa8fae7b993af6aade281c318c6939fb6))
* **env:** fix scoop.cmd path AND reg files with updated path ([064ad90](https://github.com/ETML-INF/standard-toolset/commit/064ad905bad6675921cade24c75c54c8afbfa9b7))
* **install:** -Destination handling + directory creation in green ([b780edb](https://github.com/ETML-INF/standard-toolset/commit/b780edbd4c68c7620023f4e2dc35e2328ed6b320))
* **install:** sync global archive file (not only scoop) ([8177fa8](https://github.com/ETML-INF/standard-toolset/commit/8177fa878cc0b810cc204f0ac89f07c5e8c9fb75))
* **readme:** remove traces of bootstrap ([bee2553](https://github.com/ETML-INF/standard-toolset/commit/bee255326015c09ca84169ede8318c0699bfd38f))
* **setup:** progress report and Nointeraction flag forward ([dc7ea05](https://github.com/ETML-INF/standard-toolset/commit/dc7ea0501f8205aa65e765b132518726fce2c6c8))

## [1.5.1](https://github.com/ETML-INF/standard-toolset/compare/v1.5.0...v1.5.1) (2025-07-12)


### Bug Fixes

* **cicd:** use new name of configure env script ([3fb2a9f](https://github.com/ETML-INF/standard-toolset/commit/3fb2a9fe852942aa4c42377a953e63d062952d57))

## [1.5.0](https://github.com/ETML-INF/standard-toolset/compare/v1.4.2...v1.5.0) (2025-07-12)


### Features

* **setup:** allow custom source/destination usefull for deployment ([e9c98d5](https://github.com/ETML-INF/standard-toolset/commit/e9c98d59bbd92aa632548d4ba37d65b9cd6b05a3))


### Bug Fixes

* **bootstrap:** wait for antivirus after archive download ([213f5c9](https://github.com/ETML-INF/standard-toolset/commit/213f5c901b0929012c6c951d292d53fd27c96820))
* **cicd:** cache key not based on always updated timestamps ([e1e0b71](https://github.com/ETML-INF/standard-toolset/commit/e1e0b71931c74221b1c1d0864be10129f1fddf62))

## [1.4.2](https://github.com/ETML-INF/standard-toolset/compare/v1.4.1...v1.4.2) (2025-07-11)


### Bug Fixes

* **bootstrap:** missing local archive compatible with pwsh5 ([9e73384](https://github.com/ETML-INF/standard-toolset/commit/9e7338417cf79c12929909549de2fb716da7a220))
* **install:** nointeraction is bool ! ([b4ec50e](https://github.com/ETML-INF/standard-toolset/commit/b4ec50e2cca8caa2b1e70f4969dd0ed952377632))

## [1.4.1](https://github.com/ETML-INF/standard-toolset/compare/v1.4.0...v1.4.1) (2025-07-11)


### Bug Fixes

* **cicd:** purge cache with full path to scoop ([0576254](https://github.com/ETML-INF/standard-toolset/commit/0576254198f9ed9820bcc0cb680df8e827954b75))

## [1.4.0](https://github.com/ETML-INF/standard-toolset/compare/v1.3.0...v1.4.0) (2025-07-11)


### Features

* **bootstrap:** allow local archive reuse from bootstrap ([5ffb1f7](https://github.com/ETML-INF/standard-toolset/commit/5ffb1f7e4083d4c4a86c62cdb8b04ed69d9c8767))
* **setup user env:** added error handling (basic) ([40576d6](https://github.com/ETML-INF/standard-toolset/commit/40576d69f71bd2ba659d590a30c72ac16247d9a3))


### Bug Fixes

* **cicd:** use scoop fullpath for further steps (PATH not global) ([d32b029](https://github.com/ETML-INF/standard-toolset/commit/d32b0290f4f06b5933b3d659f804117edda29cfd))

## [1.3.0](https://github.com/ETML-INF/standard-toolset/compare/v1.2.0...v1.3.0) (2025-07-10)


### Features

* **archive:** remove downloaded apps from archive ([8e0d46c](https://github.com/ETML-INF/standard-toolset/commit/8e0d46cb4e1e41c475e3868da6a94aa4fc3d5415))
* **cicd:** split pwsh tasks to steps ([3b7b185](https://github.com/ETML-INF/standard-toolset/commit/3b7b185d50e7cba09b0d6ac8e6d1497630b466e9))
* **cicd:** use gh cache ([8e0d46c](https://github.com/ETML-INF/standard-toolset/commit/8e0d46cb4e1e41c475e3868da6a94aa4fc3d5415))


### Bug Fixes

* **install:** write-host instead of inexistant info ([8e0d46c](https://github.com/ETML-INF/standard-toolset/commit/8e0d46cb4e1e41c475e3868da6a94aa4fc3d5415))

## [1.2.0](https://github.com/ETML-INF/standard-toolset/compare/v1.1.0...v1.2.0) (2025-07-07)


### Features

* **cicd:** reword zip to build and zip ([afb228e](https://github.com/ETML-INF/standard-toolset/commit/afb228e96add216a4009ac10d0182cd7effae2af))


### Bug Fixes

* **cicd:** version taken from tag (not on not yet available VERSION.txt) ([dcfd965](https://github.com/ETML-INF/standard-toolset/commit/dcfd965b36be2bf56c2506891b11493e87ac5c2c))

## [1.1.0](https://github.com/ETML-INF/standard-toolset/compare/v1.0.0...v1.1.0) (2025-07-07)


### Features

* **bootstrap:** cleanup and basic error handling ([1bb89f1](https://github.com/ETML-INF/standard-toolset/commit/1bb89f1c9ff1997b6cbdcf60191264dca9e3171f))
* **cicd:** use final apps.json ([b9ec7d3](https://github.com/ETML-INF/standard-toolset/commit/b9ec7d3cd02637a15498a8469d683cdd6f018a3c))
* **install:** nointeraction mode and error handling ([2737557](https://github.com/ETML-INF/standard-toolset/commit/2737557f371a7bf52f32bb1178cad28ef0d80bd5))
* **setup user env:** ability to get path from arg ([5ade402](https://github.com/ETML-INF/standard-toolset/commit/5ade40222e187e1a47e4f4df5940a6fa98c5c540))


### Bug Fixes

* **bootstraping:** pwsh policy force (no interaction) and releaseS ([b3ce4ee](https://github.com/ETML-INF/standard-toolset/commit/b3ce4eed854800a0970284846e7c74ec379da2cf))

## 1.0.0 (2025-07-05)


### Features

* **archive mode:** draft for offline archive mode ([d3265c1](https://github.com/ETML-INF/standard-toolset/commit/d3265c10ded3d668ea1ea0e80d312df02e89db9e))
* **insomnia/warpterminal:** removed and removed association with vscode as must be run by user ([5340ffb](https://github.com/ETML-INF/standard-toolset/commit/5340ffbbbe8280ef5f81efe8e6dd4d9f0a09f9c2))
* **install:** first draft (not fully working) ([1cfe1da](https://github.com/ETML-INF/standard-toolset/commit/1cfe1da825cc88b53dc55e97326ce688a3207996))
* **install:** fixed install from simple command line ([5ba812d](https://github.com/ETML-INF/standard-toolset/commit/5ba812d152153ee6475be7bb8d9c0f29a4d13c5a))
* **nvm:** remove as needing mklink admin... ([433bd8d](https://github.com/ETML-INF/standard-toolset/commit/433bd8d375ea469f8cc11c52282d9f78f5fef03e))
* **scoop already installed:** better handling ([37b5d13](https://github.com/ETML-INF/standard-toolset/commit/37b5d1320455ab57b6a0ba17648f7135b912435a))
* **softs:** split by category, add vscode context and add workbench, looping and insomnia ([3bf1d44](https://github.com/ETML-INF/standard-toolset/commit/3bf1d4487fc655c196dfc04cbd55fb7f2d95d8f8))
* **title:** some art.. ([9b99e51](https://github.com/ETML-INF/standard-toolset/commit/9b99e5119387eedb08df1671c0d25bf828717320))
* **wterminal:** add context menu ([c3042bd](https://github.com/ETML-INF/standard-toolset/commit/c3042bd08b73cc41295f80490d386641e52e9a94))


### Bug Fixes

* **action,bootstrap,apps.json:** validates json, asset url, fix json ([aa8e299](https://github.com/ETML-INF/standard-toolset/commit/aa8e299e738b1176a733cf8e08eff4c3ceff2502))
* **action:** fix permission for new release please version ([f9d6937](https://github.com/ETML-INF/standard-toolset/commit/f9d6937b806b435184185b67202a912bc135fb38))
* **archive mode:** bunch of adjustements for draft ([3301f75](https://github.com/ETML-INF/standard-toolset/commit/3301f75d89d07c52b6a955fab76ea709b47ff84f))
* **boostrap:** correctly set policy for ps and start file ([9569ffc](https://github.com/ETML-INF/standard-toolset/commit/9569ffc8bbafdf9fa72a323c031e51b7f5bb4777))
* **bootstrap:** fix %% for script instead of command line ([9e25c14](https://github.com/ETML-INF/standard-toolset/commit/9e25c14bea399522f18578a5ba6635746d6a62c0))
* **bootstrap:** timestamp not dependant on env ([c15ef74](https://github.com/ETML-INF/standard-toolset/commit/c15ef7471c909af25a77b4846d107e46edf66d7f))
* **calling script location:** added .\ and removed unused copy pasted nomad stuff ([e6d48e3](https://github.com/ETML-INF/standard-toolset/commit/e6d48e31c3b5dccc60b6d0f6dfbab492b16b114e))
* **install:** download ps1 if needed ([055e02b](https://github.com/ETML-INF/standard-toolset/commit/055e02b49e9c59760eabdba955ccbc8c5694e098))
* **install:** remove nvm (use node directly) and use "inf-toolset" as name... ([7a7ddc5](https://github.com/ETML-INF/standard-toolset/commit/7a7ddc5d941cff1e85ce2424dec5c71d75d0dfb4))
* **install:** student cannot store script everywhere.. stores it in temp if needed ([abc3071](https://github.com/ETML-INF/standard-toolset/commit/abc30719d90aad582154b9421496dfd0d0de23f2))
* **looping:** ut back looping ([d2a0d6c](https://github.com/ETML-INF/standard-toolset/commit/d2a0d6c0d78dcfc6e3fe465646ac52546c855a99))
* **nodejs:** correct package lts with version + remove output of create-dir and help debug toolbar ([a5bec29](https://github.com/ETML-INF/standard-toolset/commit/a5bec2923214fd5ed5cc50ac7a208309f39e2970))
