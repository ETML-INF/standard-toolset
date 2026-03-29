# Tests

All tests run inside Windows containers for full isolation — no risk of modifying
your PATH, registry, or scoop installation.

## Prerequisites

- Docker Desktop in **Windows containers mode**
  (right-click tray icon → "Switch to Windows containers")
- PowerShell 7+ (`pwsh`)

## Toolset unit tests — `Run-ToolsetTests.ps1`

Tests `toolset.ps1` update, status, and activation behaviour.
Uses a minimal Nano Server image (~250 MB, no internet needed at run time).

```powershell
pwsh tests/Run-ToolsetTests.ps1
```

| Scenario                                       | What is tested                             |
|------------------------------------------------|--------------------------------------------|
| [1] Fresh install                              | Two apps installed from scratch            |
| [2] Partial update                             | Only outdated app is replaced              |
| [3a] -Clean                                    | Orphaned app removed                       |
| [3b] -NoInteraction                            | Orphaned app kept                          |
| [4] Missing pack                               | Continues, non-fatal exit                  |
| [5] No sources (non-interactive)               | Exits non-zero — L: unavailable, -NoInteraction blocks GitHub fallback |
| [6] Status — updates pending                   | Exit 1, app shown in output                |
| [7] Status — up to date                        | Exit 0                                     |
| [8] Update with -Version                       | Pinned version installs correctly          |
| [9] Activation — shim paths                    | Old path replaced in shim files            |
| [10] Activation — reg paths                    | Old path replaced in .reg files            |
| [11a] gitconfig — no file                      | `[safe]` block created from scratch        |
| [11b] gitconfig — no `[safe]`                  | Block prepended, existing config preserved |
| [11c] gitconfig — `[safe]` without `directory` | Line inserted after `[safe]`               |
| [11d] gitconfig — existing `directory`         | Old path replaced, no duplicate            |
| [27] packUrl — pack at prior release URL       | Pack fetched via `packUrl` (file://) when absent from local source; mirrors build.ps1 reuse optimization |

## Build pipeline tests — `Run-BuildTests.ps1`

Tests `build.ps1` pack creation, zip structure, and manifest schema.
Requires a **base image** (`build-base`) with scoop + 7zip pre-installed.
This image is **not pulled automatically** — you must have it locally before running the tests.

### First-time setup (fresh dev machine)

**Step 1 — fix Docker DNS** (one-time, if not already done)

Windows containers need DNS to reach the internet during the build.
If you skip this and the build fails with _"No such host is known"_, open
Docker Desktop → Settings → Docker Engine and add:
```json
"dns": ["8.8.8.8"]
```
Then click **Apply & Restart**.

**Step 2 — get the base image** (pick one option)

_Option A — build locally_ (always works, ~5–10 min first time):
```powershell
# Builds the image locally — no push, no login required
pwsh tests/Build-BaseImage.ps1
```

_Option B — pull from GHCR_ (only works after CI has pushed it at least once):
```powershell
docker pull ghcr.io/etml-inf/standard-toolset/build-base:latest
```
> If the pull fails with "unauthorized" or "not found", the image hasn't been pushed
> to GHCR yet — use Option A.

**Step 3 — run the tests**
```powershell
pwsh tests/Run-BuildTests.ps1
```

| Scenario             | What is tested                                             |
|----------------------|------------------------------------------------------------|
| [B1] End-to-end      | build.ps1 creates packs and manifest (test app: `jq`)      |
| [B2] Manifest schema | version, previousVersion, built, apps fields               |
| [B3] Zip structure   | Root dir is `<appName>\`, contains `current\manifest.json` |
| [B4] Skip reinstall  | Second run reuses existing scoop install                   |
| [B5] packUrl reuse   | Reused pack gets `packUrl` in manifest; no zip re-uploaded |

## Helper scripts

| Script                      | Purpose                                            |
|-----------------------------|----------------------------------------------------|
| `New-FakePack.ps1`          | Creates fake app zips + manifest for toolkit tests |
| `Build-BaseImage.ps1`       | Builds and pushes the build-base image to GHCR     |
| `Run-ToolsetTests.ps1`    | Runs toolkit tests                                 |
| `Run-BuildTests.ps1`        | Runs build pipeline tests                          |
| `Invoke-ToolsetTests.ps1` | Test scenarios (runs inside the container)         |
| `Invoke-BuildTests.ps1`     | Build test scenarios (runs inside the container)   |

## CI

On every push/PR (`ci.yml`), two jobs run:

1. **`test`** — runs the `validate-and-test` composite action:
   - Validates `apps.json` (JSON schema check)
   - Runs `Test-UpdateMode.ps1` (update-mode tests, no container)
   - Switches Docker to Windows containers mode
   - Runs `Run-ToolsetTests.ps1` (toolset unit tests in nanoserver container)

2. **`build-tests`** (runs only if `test` passes) — pulls the base image from GHCR and runs `Run-BuildTests.ps1`.

The base image (`build-base`) is rebuilt separately via `build-base-image.yml`
(triggered manually or when `Dockerfile.build-base` changes).
