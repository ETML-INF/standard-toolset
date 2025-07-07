# Changelog

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
