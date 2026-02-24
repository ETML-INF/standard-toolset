# standard-toolset Copilot Instructions

## When reviewing code, focus on:

### Security Critical Issues
- Check for hardcoded paths that assume a specific drive letter or username (use `$env:USERPROFILE`, `$env:TEMP`, `$PSScriptRoot` instead)
- Verify that no credentials, tokens, or secrets are embedded in scripts
- Review file operations that write to arbitrary user-supplied paths — validate paths before use
- Check that GitHub API calls use proper token handling (token should come from `$env:GITHUB_TOKEN`, never hardcoded)

### Code Quality Essentials
- Scripts should use `Set-StrictMode -Version Latest` to catch undefined variable usage
- Every function must have complete comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.OUTPUTS`)
- Use approved PowerShell verbs — check with `Get-Verb` if unsure (`Get-`, `New-`, `Set-`, `Remove-`, `Test-`, `Write-`, `Compare-`, `Generate-`)
- No cmdlet aliases in scripts — use full names (`ForEach-Object` not `%`, `Where-Object` not `?`, `Write-Host` not nothing)
- Functions must return structured hashtables or objects, not raw strings, for machine-consumable output
- Avoid global state — prefer parameter passing over `$global:` variables

### Testability
- New library functions in `lib/` must be written as pure, side-effect-free functions that can run in an isolated temp directory
- External dependencies (GitHub API, network, real filesystem paths) must be mockable — follow the `$env:GITHUB_MOCK_PATH` pattern used in `Get-GitHubRelease.ps1`
- Scripts that write to disk must accept output path parameters, never hardcode destination paths

### Performance Issues
- Avoid loading entire file contents into memory when line-by-line processing is sufficient
- Don't call `Get-ChildItem -Recurse` on large directories without filtering — use `-Filter` or `-Include`
- Use `Compress-Archive` with care on large directories; check existing workarounds (e.g., `.git` rename issue in release workflow)

## Review Style
- Be specific and actionable in feedback
- Explain the rationale behind recommendations
- Acknowledge good patterns when you see them (especially testability design)
- Ask clarifying questions when script intent is unclear

## Review Test Coverage
- New `lib/` functions must have corresponding Pester tests in `tests/integration/`
- Tests must use isolated temp directories (GUID-based, under `$env:TEMP`) — never the real installation
- Tests must clean up after themselves in `AfterAll` blocks

Always prioritize security issues and testability gaps over style concerns.

---

## Repository Overview

**standard-toolset** is a portable Windows application toolkit for ETML (École Technique de la Vallée de Joux et du Lac de Joux) built on Scoop. It deploys 25+ developer tools (Git, Node.js, VSCode, Python, DBeaver, etc.) without admin rights, and supports intelligent delta updates to minimize bandwidth usage.

**Key Technologies:**
- **Language:** PowerShell 5.1+ (Windows built-in, no install required)
- **Package Manager:** Scoop (embedded in the distribution)
- **Testing:** Pester 5.0+ (auto-installed by test runner)
- **Linting:** PSScriptAnalyzer (configured in `PSScriptAnalyzerSettings.psd1`)
- **CI/CD:** GitHub Actions (Windows runners)
- **Release:** release-please (semantic versioning + changelog automation)
- **Sync/Deploy:** rclone for file distribution to network locations

## Commands

### Run all tests
```powershell
.\tests\Run-Tests.ps1
.\tests\Run-Tests.ps1 -Verbosity Detailed      # verbose output
.\tests\Run-Tests.ps1 -GenerateResults          # save test-results.xml
```

### Run PSScriptAnalyzer
```powershell
Install-Module PSScriptAnalyzer -Force -Scope CurrentUser
Invoke-ScriptAnalyzer -Path lib -Recurse -Settings PSScriptAnalyzerSettings.psd1
```

### Build a full toolset package locally
```powershell
.\build.ps1
```

### Apply a delta update
```powershell
.\update.ps1
```

## Project Structure

```
lib/                              # Reusable, testable library modules
  Compare-Versions.ps1            # Compare two versions.txt (scoop list format)
  Get-GitHubRelease.ps1           # GitHub API wrapper (mockable via $env:GITHUB_MOCK_PATH)
  Generate-DeltaPackage.ps1       # Create delta archives from build directories

tests/
  integration/                    # Pester integration tests (7 suites)
    DeltaGeneration.Tests.ps1
    CompareVersions.Tests.ps1
    VersionDetection.Tests.ps1
    GitHubReleaseMocking.Tests.ps1
    DeltaApplication.Tests.ps1
    DeltaChain.Tests.ps1
    Fallback.Tests.ps1
  helpers/                        # Test fixture generators
    New-MockRelease.ps1
    New-MockInstallation.ps1
    New-MockReleaseRepository.ps1
  Run-Tests.ps1                   # Test runner with verbosity and XML output

setup.ps1                         # Bootstrap: download and extract toolset
install.ps1                       # Deploy to target location (no admin needed)
activate.ps1                      # Finalize: PATH, context menus, shortcuts
update.ps1                        # Apply delta or full update
build.ps1                         # Build full package via Scoop
detect-version.ps1                # Detect installed version
apps.json                         # Application manifest (name, version, bucket)
PSScriptAnalyzerSettings.psd1     # Linter rules
```

## Key Domain Concepts

- **versions.txt** — Output of `scoop list`, used to compare what's installed between versions
- **Delta package** — ZIP containing only changed/new apps between two releases (vs full ~1 GB package)
- **DELTA-MANIFEST.json** — Describes what a delta contains and from which base version it applies
- **Delta chain** — Sequence of deltas applied to reach current version (max 3 before falling back to full)
- **Activation** — Final step that sets up PATH, registry entries, context menus, and shortcuts
- **Mock mode** — Test isolation via `$env:GITHUB_MOCK_PATH` pointing to a local folder mimicking the GitHub API

## Development Workflow

1. Add/modify a `lib/*.ps1` function
2. Write a Pester test in `tests/integration/<Feature>.Tests.ps1`
3. Run `.\tests\Run-Tests.ps1 -Verbosity Detailed` — all tests must pass
4. Run PSScriptAnalyzer — zero errors allowed (warnings reviewed case by case)
5. Push → CI runs tests on Windows runner and validates linting
6. PRs target `main`; release-please automates versioning and changelog

## Common Pitfalls to Avoid

- Using `$PSScriptRoot` without verifying the script is not dot-sourced from an unexpected location
- Assuming `C:\` or `D:\` as the drive — always use parameters or environment variables for paths
- Not wrapping GitHub API calls in mock-awareness (`$env:GITHUB_MOCK_PATH` check)
- Creating goroutine-style parallel jobs without proper cleanup on failure
- Forgetting `| Out-Null` on commands that produce unwanted pipeline output inside test assertions
- Using `Write-Host` for data output — use `return` or `Write-Output` for data, `Write-Host` only for UX/display
- Not calling `Remove-Item -Recurse -Force -ErrorAction SilentlyContinue` in `AfterAll` test cleanup
- Hardcoding version strings — read from `VERSION.txt` or parameters
- Using `Compress-Archive` on directories containing `.git` — rename it first (known workaround in `release.yml`)
